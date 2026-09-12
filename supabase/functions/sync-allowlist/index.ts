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
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are injected automatically.
//
// Setup: share each sheet (Viewer) with GOOGLE_SERVICE_ACCOUNT_EMAIL, and
// enable the Google Sheets API in the service account's GCP project. See
// SUPABASE.md.
//
// Deploy:   supabase functions deploy sync-allowlist
// Schedule: a cron (pg_cron) POSTing this function's URL every ~5 min.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

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

Deno.serve(async () => {
  try {
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const token = await getAccessToken();
    const volunteers = await readSheet(
      token,
      Deno.env.get("VOLUNTEERS_SHEET_ID") ?? Deno.env.get("MENTORS_SHEET_ID"),
      Deno.env.get("VOLUNTEERS_RANGE") ?? Deno.env.get("MENTORS_RANGE") ?? "A:F",
      "volunteer",
    );
    const admins = await readSheet(
      token, Deno.env.get("ADMINS_SHEET_ID"),
      Deno.env.get("ADMINS_RANGE") ?? "A:A", "admin",
    );
    const all = [...volunteers, ...admins];

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

    await prune(supabase, "volunteer", volunteers.map((v) => v.email));
    await prune(supabase, "admin", admins.map((a) => a.email));

    return json({ ok: true, volunteers: volunteers.length, admins: admins.length });
  } catch (e) {
    // Serialize properly so the real message shows instead of "[object Object]".
    const msg = e instanceof Error
      ? (e.message || e.stack || "Error")
      : (typeof e === "object" ? JSON.stringify(e) : String(e));
    return json({ ok: false, error: msg }, 500);
  }
});

async function prune(
  supabase: ReturnType<typeof createClient>,
  role: "volunteer" | "admin",
  keepEmails: string[],
) {
  let q = supabase.from("role_allowlist").delete().eq("role", role);
  if (keepEmails.length > 0) {
    const list = keepEmails.map((e) => `"${e}"`).join(",");
    q = q.not("email", "in", `(${list})`);
  }
  await q;
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
