// Emerald Summit — sync-allowlist Edge Function (private Google Sheets API)
//
// Copies the two Google Sheets (volunteers, admins) into the role_allowlist
// table that RLS enforces. Reads the sheets PRIVATELY via the Google Sheets API
// using a service account — the sheets stay unpublished, so no volunteer/admin
// emails are ever exposed on a public URL. Uses the Supabase service role
// (bypasses RLS); never expose this function's secrets to the client.
//
// Secrets (set with `supabase secrets set` or in the dashboard):
//   GOOGLE_SERVICE_ACCOUNT_EMAIL  — the service account's email
//   GOOGLE_PRIVATE_KEY            — its private key (PEM; keep the \n escapes)
//   VOLUNTEERS_SHEET_ID          — the volunteers spreadsheet id (from its URL)
//                                  (legacy MENTORS_SHEET_ID is accepted too)
//   ADMINS_SHEET_ID             — the admins spreadsheet id
//   VOLUNTEERS_RANGE (optional, default "A:F")
//        columns: email | subtype | disciplines | can_edit_sessions |
//                 can_post_announcements | can_check_in_front_desk
//   ADMINS_RANGE  (optional, default "A:A")  — email
//   ALLOWLIST_SYNC_SECRET — must match private.allowlist_sync.secret; every
//        request without it in an `x-sync-secret` header gets a 401
//   ALLOWLIST_ALLOW_BIG_DROP (optional) — set to "true" for one sync to let a
//        role lose more than half its rows (see the prune guard below); unset
//        it again afterwards
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are injected automatically.
//
// Setup: share each sheet (Viewer) with GOOGLE_SERVICE_ACCOUNT_EMAIL, and
// enable the Google Sheets API in the service account's GCP project. See
// SUPABASE.md.
//
// Deploy:   supabase functions deploy sync-allowlist --no-verify-jwt
// Schedule: the `pull-from-sheets` pg_cron job, every 5 min, sends the secret
//           (see allowlist_sync_secret.sql).

import { createClient, type SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

interface AllowRow {
  email: string;
  role: "volunteer" | "admin";
  disciplines: string[];
  subtype: string | null;
  can_edit_sessions: boolean | null;
  can_post_announcements: boolean | null;
  can_check_in_front_desk: boolean | null;
}

// ---- Cell parsing ----------------------------------------------------------

// TRUE/FALSE/blank → true/false/null. Blank means "use the subtype default"
// (the DB trigger applies it), so we send NULL, not false.
function parseBool(cell: string | undefined): boolean | null {
  const v = (cell ?? "").trim().toLowerCase();
  if (v === "") return null;
  if (/^(true|yes|y|1|x|✓)$/.test(v)) return true;
  if (/^(false|no|n|0)$/.test(v)) return false;
  return null;
}

// Normalize the subtype cell to a stored id, tolerating a few spellings.
function parseSubtype(cell: string | undefined): string | null {
  const v = (cell ?? "").trim().toLowerCase().replace(/[\s-]+/g, "_");
  if (v === "") return null;
  if (v === "eaf_ambassador" || v.includes("ambassador") || v === "eaf") {
    return "eaf_ambassador";
  }
  if (v === "parent_volunteer" || v.startsWith("parent")) return "parent_volunteer";
  if (v === "student_volunteer" || v.startsWith("student")) return "student_volunteer";
  return null;
}

// ---- Google service-account auth (OAuth2 JWT bearer) -----------------------

function base64url(bytes: Uint8Array): string {
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function pemToPkcs8(pem: string): ArrayBuffer {
  const body = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s+/g, "");
  const raw = atob(body);
  const buf = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) buf[i] = raw.charCodeAt(i);
  return buf.buffer;
}

async function getAccessToken(): Promise<string> {
  const email = Deno.env.get("GOOGLE_SERVICE_ACCOUNT_EMAIL")!;
  // Secrets often store the PEM with literal "\n"; normalize to real newlines.
  const pem = (Deno.env.get("GOOGLE_PRIVATE_KEY") ?? "").replace(/\\n/g, "\n");
  const now = Math.floor(Date.now() / 1000);
  const enc = new TextEncoder();

  const header = base64url(enc.encode(JSON.stringify({ alg: "RS256", typ: "JWT" })));
  const claim = base64url(enc.encode(JSON.stringify({
    iss: email,
    scope: "https://www.googleapis.com/auth/spreadsheets.readonly",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  })));
  const signingInput = `${header}.${claim}`;

  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToPkcs8(pem),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = new Uint8Array(
    await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, enc.encode(signingInput)),
  );
  const jwt = `${signingInput}.${base64url(sig)}`;

  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });
  if (!res.ok) throw new Error(`Google token exchange failed: ${await res.text()}`);
  return (await res.json()).access_token as string;
}

async function readSheet(
  token: string,
  sheetId: string | undefined,
  range: string,
  role: "volunteer" | "admin",
): Promise<AllowRow[]> {
  if (!sheetId) return [];
  const url =
    `https://sheets.googleapis.com/v4/spreadsheets/${sheetId}/values/${encodeURIComponent(range)}`;
  const res = await fetch(url, { headers: { Authorization: `Bearer ${token}` } });
  if (!res.ok) throw new Error(`Read ${role} sheet failed: ${res.status} ${await res.text()}`);
  const rows: string[][] = (await res.json()).values ?? [];

  const out: AllowRow[] = [];
  const seen = new Set<string>();
  for (const r of rows) {
    const email = (r[0] ?? "").trim().toLowerCase();
    if (!email || email === "email" || !email.includes("@")) continue; // header/blank
    if (seen.has(email)) continue;
    seen.add(email);

    let disciplines: string[] = [];
    let subtype: string | null = null;
    let canEdit: boolean | null = null;
    let canPost: boolean | null = null;
    let canFrontDesk: boolean | null = null;

    if (role === "volunteer") {
      // A email | B subtype | C disciplines | D can_edit_sessions |
      // E can_post_announcements | F can_check_in_front_desk
      subtype = parseSubtype(r[1]);
      const cell = (r[2] ?? "").trim();
      if (/^(all|\*)$/i.test(cell)) disciplines = ["*"];
      else if (cell) disciplines = cell.split(/[,;]/).map((s) => s.trim()).filter(Boolean);
      canEdit = parseBool(r[3]);
      canPost = parseBool(r[4]);
      canFrontDesk = parseBool(r[5]);
    }

    out.push({
      email,
      role,
      disciplines,
      subtype,
      can_edit_sessions: canEdit,
      can_post_announcements: canPost,
      can_check_in_front_desk: canFrontDesk,
    });
  }
  return out;
}

// ---- Sync ------------------------------------------------------------------

Deno.serve(async (req) => {
  const secret = Deno.env.get("ALLOWLIST_SYNC_SECRET");
  if (!secret || req.headers.get("x-sync-secret") !== secret) {
    return json({ ok: false, error: "unauthorized" }, 401);
  }
  try {
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    let volunteers: AllowRow[];
    let admins: AllowRow[];
    try {
      const token = await getAccessToken();
      volunteers = await readSheet(
        token,
        Deno.env.get("VOLUNTEERS_SHEET_ID") ?? Deno.env.get("MENTORS_SHEET_ID"),
        Deno.env.get("VOLUNTEERS_RANGE") ?? Deno.env.get("MENTORS_RANGE") ?? "A:F",
        "volunteer",
      );
      admins = await readSheet(
        token, Deno.env.get("ADMINS_SHEET_ID"),
        Deno.env.get("ADMINS_RANGE") ?? "A:A", "admin",
      );
    } catch (e) {
      // Google sign-in or a sheet read failed, so nothing in role_allowlist was
      // touched. Tell the admins, then report the real error as before.
      try {
        await refreshSheetNotice(supabase, [
          "The app couldn't read the Google Sheets, so it can't add or remove " +
          "volunteers or admins right now. Nobody's access has changed.",
        ]);
      } catch (noticeError) {
        console.error(noticeError);
      }
      throw e;
    }
    const all = [...volunteers, ...admins];

    // Count what's there before the upsert adds new rows, for the prune guard.
    const volunteersBefore = await countRole(supabase, "volunteer");
    const adminsBefore = await countRole(supabase, "admin");

    if (all.length > 0) {
      const { error } = await supabase
        .from("role_allowlist")
        .upsert(
          all.map((a) => ({ ...a, updated_at: new Date().toISOString() })),
          { onConflict: "email,role" },
        );
      if (error) {
        throw new Error(`role_allowlist upsert failed: ${error.message ?? JSON.stringify(error)}`);
      }
    }

    // Each role is checked on its own, so a broken Admins sheet doesn't stop
    // volunteer removals (and the other way round).
    const refused = [
      await guardedPrune(supabase, "volunteer", "Volunteers", volunteers, volunteersBefore),
      await guardedPrune(supabase, "admin", "Admins", admins, adminsBefore),
    ].filter((r): r is Refusal => r !== null);

    await refreshSheetNotice(supabase, refused.map((r) => r.notice));

    if (refused.length > 0) {
      return json({
        ok: false,
        error: refused.map((r) => r.error).join(" "),
        volunteers: volunteers.length,
        admins: admins.length,
      }, 422);
    }
    return json({ ok: true, volunteers: volunteers.length, admins: admins.length });
  } catch (e) {
    // Serialize properly so the real message shows instead of "[object Object]".
    const msg = e instanceof Error
      ? (e.message || e.stack || "Error")
      : (typeof e === "object" ? JSON.stringify(e) : String(e));
    return json({ ok: false, error: msg }, 500);
  }
});

async function countRole(
  supabase: SupabaseClient,
  role: "volunteer" | "admin",
): Promise<number> {
  const { count, error } = await supabase
    .from("role_allowlist")
    .select("email", { count: "exact", head: true })
    .eq("role", role);
  if (error) {
    throw new Error(`role_allowlist count failed: ${error.message ?? JSON.stringify(error)}`);
  }
  return count ?? 0;
}

// Why a role wasn't pruned: `error` for the function logs, `notice` for the
// admins' in-app notice.
interface Refusal {
  error: string;
  notice: string;
}

// Removing a row drops that person's role, so a sheet that suddenly reads back
// empty or much shorter (emptied, unshared, wrong range) must not wipe the list.
// Returns null after pruning, or why it refused to.
async function guardedPrune(
  supabase: SupabaseClient,
  role: "volunteer" | "admin",
  sheetName: string,
  rows: AllowRow[],
  before: number,
): Promise<Refusal | null> {
  const after = rows.length;
  if (after === 0 && before === 0) return null; // nothing there to lose
  const access = `${role} access from`;
  const n = (k: number) => `${k} ${role}${k === 1 ? "" : "s"}`;
  if (after === 0) {
    return {
      error: `The ${sheetName} sheet came back with no email rows, so nobody was ` +
        `removed from the ${role} list. Check that the sheet still has emails in ` +
        `column A, that it's shared with the service account, and that its sheet ` +
        `id and range are right.`,
      notice: `The ${sheetName} Google Sheet came back empty, which would have ` +
        `taken away ${access} ${before === 1 ? `the only ${role}` : `all ${n(before)}`}. ` +
        `The app kept everyone's access for now.`,
    };
  }
  // Small lists can legitimately halve (3 admins down to 1), so only a drop of
  // 5 or more rows counts.
  const bigDrop = after < before / 2 && before - after >= 5;
  if (bigDrop && Deno.env.get("ALLOWLIST_ALLOW_BIG_DROP") !== "true") {
    return {
      error: `The ${sheetName} sheet has ${after} emails but the ${role} list has ` +
        `${before}, so nobody was removed. If that many people really left, set ` +
        `ALLOWLIST_ALLOW_BIG_DROP=true for one sync, then unset it.`,
      notice: `The ${sheetName} Google Sheet now lists ${n(after)}, down ` +
        `from ${before}, which would have taken away ${access} ` +
        `${before - after} of them. The app kept everyone's access for now.`,
    };
  }
  await prune(supabase, role, rows.map((r) => r.email));
  return null;
}

async function prune(
  supabase: SupabaseClient,
  role: "volunteer" | "admin",
  keepEmails: string[],
) {
  // Only called with a non-empty list (guardedPrune refuses an empty sheet), so
  // this never deletes a whole role.
  const list = keepEmails.map((e) => `"${e}"`).join(",");
  const { error } = await supabase
    .from("role_allowlist")
    .delete()
    .eq("role", role)
    .not("email", "in", `(${list})`);
  if (error) {
    throw new Error(`role_allowlist prune (${role}) failed: ${error.message ?? JSON.stringify(error)}`);
  }
}

// One rolling notice per admin, like "Experts waiting for approval": posted
// when a sync first refuses to prune or can't read the sheets, its text kept current while the problem lasts
// (without marking it unread again every 5 minutes), removed once a sync goes
// through cleanly.
const SHEET_NOTICE_TITLE = "Problem with the Google Sheet";

async function refreshSheetNotice(supabase: SupabaseClient, lines: string[]) {
  const fail = (what: string, error: { message?: string }) =>
    new Error(`Sheet notice ${what} failed: ${error.message ?? JSON.stringify(error)}`);
  if (lines.length === 0) {
    const { error } = await supabase.from("announcements").delete()
      .eq("title", SHEET_NOTICE_TITLE).eq("audience", "Personal");
    if (error) throw fail("cleanup", error);
    return;
  }

  const body = [...lines, "Please tell Arjun to check the Google Sheet."].join("\n\n");
  const { data: existing, error: readError } = await supabase
    .from("announcements").select("body")
    .eq("title", SHEET_NOTICE_TITLE).eq("audience", "Personal");
  if (readError) throw fail("read", readError);

  if (existing && existing.length > 0) {
    if (existing.some((n) => n.body !== body)) {
      const { error } = await supabase.from("announcements").update({ body })
        .eq("title", SHEET_NOTICE_TITLE).eq("audience", "Personal");
      if (error) throw fail("update", error);
    }
    return;
  }

  const { data: admins, error: adminsError } = await supabase
    .from("profiles").select("id").eq("role", "admin");
  if (adminsError) throw fail("admin lookup", adminsError);
  if (!admins || admins.length === 0) return;

  const { error } = await supabase.from("announcements").insert(
    admins.map((a) => ({
      title: SHEET_NOTICE_TITLE,
      body,
      author: "Emerald Summit",
      audience: "Personal",
      pinned: false,
      target_user_id: a.id,
    })),
  );
  if (error) throw fail("post", error);
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
