// Emerald Summit — sync-hours-sheet
//
// Rewrites the volunteer hours Google Sheet from the database, in the format
// of the "Student Volunteer Timecard" template (16 columns, one row per entry):
//   * one row per manual log in volunteer_hour_logs, and
//   * one row per session a volunteer or admin managed on summit day
//     (session_volunteers), once that session has ended on the summit date.
//     These rows also carry the session's expert feedback and the person's
//     "volunteer for EAF again?" answer.
// Parent name / email / phone and Board feedback are left blank.
//
// Called by the `sync-hours-sheet` pg_cron job (see hours_sheet_sync.sql)
// with an `x-sync-secret` header. Deploy with --no-verify-jwt.
//
// Secrets:
//   GOOGLE_SERVICE_ACCOUNT_EMAIL / GOOGLE_PRIVATE_KEY — shared with
//     sync-allowlist. Share the hours spreadsheet with this email as Editor.
//   HOURS_SHEET_ID     — the spreadsheet id (the token in its URL)
//   HOURS_SHEET_TAB    — optional tab name; defaults to the first tab
//   HOURS_SYNC_SECRET  — must match private.hours_sheet_sync.secret

import { createClient, type SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

const TZ = "America/Los_Angeles";

const HEADER = [
  "Timestamp",
  "Email Address",
  "Name (First, Last)",
  "Student ID",
  "Grade",
  "Non-DUSD email",
  "Parent name",
  "Parent email",
  "Parent phone number",
  "Date",
  "Start time",
  "End time",
  "Volunteer work performed",
  "External fdbk",
  "Board feedback",
  "Thank you for your efforts. \nWould like to volunteer for EAF in future?",
];

type Profile = {
  id: string;
  email: string | null;
  full_name: string | null;
  role: string;
  volunteer_subtype: string | null;
  details: Record<string, unknown> | null;
};

// ---- Google service-account auth (same as sync-allowlist, write scope) -----

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
  const pem = (Deno.env.get("GOOGLE_PRIVATE_KEY") ?? "").replace(/\\n/g, "\n");
  const now = Math.floor(Date.now() / 1000);
  const enc = new TextEncoder();

  const header = base64url(enc.encode(JSON.stringify({ alg: "RS256", typ: "JWT" })));
  const claim = base64url(enc.encode(JSON.stringify({
    iss: email,
    scope: "https://www.googleapis.com/auth/spreadsheets",
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

// ---- Time formatting (Pacific, like the Google Form) ------------------------

function pacificParts(d: Date) {
  const parts = Object.fromEntries(
    new Intl.DateTimeFormat("en-US", {
      timeZone: TZ,
      year: "numeric", month: "numeric", day: "numeric",
      hour: "numeric", minute: "2-digit", second: "2-digit", hourCycle: "h23",
    }).formatToParts(d).map((p) => [p.type, p.value]),
  );
  return {
    y: +parts.year, mo: +parts.month, d: +parts.day,
    h: +parts.hour, mi: +parts.minute, s: +parts.second,
  };
}

const pad = (n: number) => String(n).padStart(2, "0");

/** "10/18/2026" */
const dateText = (y: number, mo: number, d: number) => `${mo}/${d}/${y}`;

/** "3:05 PM" */
function clockText(h: number, mi: number): string {
  const h12 = h % 12 === 0 ? 12 : h % 12;
  return `${h12}:${pad(mi)} ${h >= 12 ? "PM" : "AM"}`;
}

/** "10/18/2026 15:04:05", the Google Form timestamp format. */
function stampText(y: number, mo: number, d: number, h: number, mi: number, s = 0) {
  return `${dateText(y, mo, d)} ${h}:${pad(mi)}:${pad(s)}`;
}

/** Sortable "YYYY-MM-DD HH:mm". */
const sortKey = (y: number, mo: number, d: number, h: number, mi: number) =>
  `${y}-${pad(mo)}-${pad(d)} ${pad(h)}:${pad(mi)}`;

function hhmm(t: string): [number, number] {
  const [h, m] = t.split(":");
  return [+h, +m];
}

// ---- Data ------------------------------------------------------------------

async function fetchAll<T>(db: SupabaseClient, table: string, select: string): Promise<T[]> {
  const out: T[] = [];
  for (let from = 0; ; from += 1000) {
    const { data, error } = await db.from(table).select(select).range(from, from + 999);
    if (error) throw new Error(`${table}: ${error.message}`);
    out.push(...(data as T[]));
    if (!data || data.length < 1000) return out;
  }
}

const text = (v: unknown) => (v == null ? "" : String(v).trim());

/** Grade goes on the sheet for student volunteers, EAF ambassadors, and admins
 * who gave one. Never for parent volunteers. */
function gradeFor(p: Profile): string {
  if (p.role === "volunteer" && p.volunteer_subtype === "parent_volunteer") return "";
  return text(p.details?.grade);
}

async function buildRows(db: SupabaseClient): Promise<string[][]> {
  const everyone = await fetchAll<Profile>(
    db, "profiles", "id, email, full_name, role, volunteer_subtype, details",
  );
  const byId = new Map(everyone
    .filter((p) => p.role === "volunteer" || p.role === "admin")
    .map((p) => [p.id, p]));

  const person = (p: Profile) => [
    text(p.email), // Email Address
    text(p.full_name), // Name (First, Last)
    text(p.details?.student_id), // Student ID
    gradeFor(p), // Grade
    text(p.email), // Non-DUSD email: the account's email
    "", "", "", // Parent name / email / phone
  ];

  const rows: { key: string; cells: string[] }[] = [];

  // Manual logs.
  const logs = await fetchAll<{
    user_id: string; started_at: string; ended_at: string;
    description: string; created_at: string;
  }>(db, "volunteer_hour_logs", "user_id, started_at, ended_at, description, created_at");
  for (const log of logs) {
    const p = byId.get(log.user_id);
    if (!p) continue;
    const c = pacificParts(new Date(log.created_at));
    const s = pacificParts(new Date(log.started_at));
    const e = pacificParts(new Date(log.ended_at));
    rows.push({
      key: sortKey(s.y, s.mo, s.d, s.h, s.mi),
      cells: [
        stampText(c.y, c.mo, c.d, c.h, c.mi, c.s),
        ...person(p),
        dateText(s.y, s.mo, s.d),
        clockText(s.h, s.mi),
        clockText(e.h, e.mi),
        text(log.description),
        "", "", "", // External fdbk / Board feedback / future EAF
      ],
    });
  }

  // Summit-day rows: one per managed session, once it has ended.
  const { data: settings } = await db.from("summit_settings")
    .select("summit_date").maybeSingle();
  const summitDate = settings?.summit_date as string | null | undefined;
  if (summitDate) {
    const [y, mo, d] = summitDate.split("-").map(Number);
    const n = pacificParts(new Date());
    const nowKey = sortKey(n.y, n.mo, n.d, n.h, n.mi);

    const sessions = new Map((await fetchAll<{
      id: string; title: string; start_time: string; end_time: string;
      discipline_id: string | null;
    }>(db, "sessions", "id, title, start_time, end_time, discipline_id"))
      .map((s) => [s.id, s]));
    const disciplines = new Map((await fetchAll<{ id: string; name: string }>(
      db, "disciplines", "id, name",
    )).map((x) => [x.id, x.name]));
    const assignments = await fetchAll<{ session_id: string; user_id: string }>(
      db, "session_volunteers", "session_id, user_id",
    );

    // Session feedback from every expert, one line each.
    const names = new Map(everyone.map((x) => [x.id, text(x.full_name)]));
    const feedback = new Map<string, string[]>();
    for (const f of await fetchAll<{
      expert_id: string; kind: string; session_id: string; rating: number; comment: string;
    }>(db, "expert_feedback", "expert_id, kind, session_id, rating, comment")) {
      if (f.kind !== "session") continue;
      const comment = text(f.comment);
      const line = `${names.get(f.expert_id) || "Expert"}: ${f.rating}/5` +
        (comment ? `. ${comment}` : "");
      feedback.set(f.session_id, [...(feedback.get(f.session_id) ?? []), line]);
    }

    const interest = new Map((await fetchAll<{ user_id: string; wants_to_volunteer: boolean }>(
      db, "eaf_future_interest", "user_id, wants_to_volunteer",
    )).map((x) => [x.user_id, x.wants_to_volunteer ? "Yes" : "No"]));

    for (const a of assignments) {
      const p = byId.get(a.user_id);
      const s = sessions.get(a.session_id);
      if (!p || !s) continue;
      const [sh, sm] = hhmm(s.start_time);
      const [eh, em] = hhmm(s.end_time);
      if (sortKey(y, mo, d, eh, em) > nowKey) continue; // not over yet
      const discipline = s.discipline_id ? disciplines.get(s.discipline_id) : null;
      rows.push({
        key: sortKey(y, mo, d, sh, sm),
        cells: [
          stampText(y, mo, d, eh, em),
          ...person(p),
          dateText(y, mo, d),
          clockText(sh, sm),
          clockText(eh, em),
          `Managed "${text(s.title)}"${discipline ? ` (${discipline})` : ""} on summit day`,
          (feedback.get(s.id) ?? []).join("\n"),
          "", // Board feedback
          interest.get(p.id) ?? "",
        ],
      });
    }
  }

  rows.sort((a, b) => a.key.localeCompare(b.key) || a.cells[2].localeCompare(b.cells[2]));
  return rows.map((r) => r.cells);
}

// ---- Sheet write -------------------------------------------------------------

async function sheets(token: string, path: string, init: RequestInit = {}) {
  const res = await fetch(`https://sheets.googleapis.com/v4/spreadsheets/${path}`, {
    ...init,
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
      ...(init.headers ?? {}),
    },
  });
  if (!res.ok) throw new Error(`Sheets API ${res.status}: ${await res.text()}`);
  return res.json();
}

async function writeSheet(token: string, sheetId: string, values: string[][]) {
  let tab = Deno.env.get("HOURS_SHEET_TAB");
  if (!tab) {
    const meta = await sheets(token, `${sheetId}?fields=sheets.properties.title`);
    tab = meta.sheets[0].properties.title as string;
  }
  const quoted = `'${tab.replace(/'/g, "''")}'`;
  await sheets(token, `${sheetId}/values/${encodeURIComponent(`${quoted}!A:P`)}:clear`, {
    method: "POST",
    body: "{}",
  });
  // RAW keeps values exactly as written (no leading zeros dropped from IDs).
  await sheets(
    token,
    `${sheetId}/values/${encodeURIComponent(`${quoted}!A1`)}?valueInputOption=RAW`,
    { method: "PUT", body: JSON.stringify({ values }) },
  );
}

Deno.serve(async (req) => {
  const secret = Deno.env.get("HOURS_SYNC_SECRET");
  if (!secret || req.headers.get("x-sync-secret") !== secret) {
    return new Response(JSON.stringify({ ok: false, error: "unauthorized" }), {
      status: 401,
      headers: { "Content-Type": "application/json" },
    });
  }
  const sheetId = Deno.env.get("HOURS_SHEET_ID");
  if (!sheetId) {
    return Response.json({ ok: true, skipped: "HOURS_SHEET_ID is not set" });
  }
  try {
    const db = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      { auth: { persistSession: false } },
    );
    const rows = await buildRows(db);
    const token = await getAccessToken();
    await writeSheet(token, sheetId, [HEADER, ...rows]);
    return Response.json({ ok: true, rows: rows.length });
  } catch (e) {
    console.error(e);
    return Response.json({ ok: false, error: String(e) }, { status: 500 });
  }
});
