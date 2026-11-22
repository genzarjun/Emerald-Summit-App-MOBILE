// Emerald Summit — bug-report-email Edge Function
//
// Emails a bug report or feedback after submit_bug_report() saved it
// (supabase/bug_reports_setup.sql). The client calls it once, right after
// submitting, with { report_id }:
//   * if the sender ticked "Email me a copy", they get the whole report,
//     including everything the app attached from their account, so they can
//     see exactly what was shared;
//   * if BUG_REPORT_TO is set, the team gets the same report at that address
//     (comma-separated for several), with Reply-To set to the sender.
// It only ever emails the caller's own sign-in address and the fixed team
// address, and only once per report (emailed_at is claimed atomically), so it
// can't be used to send mail to anyone else or to resend a report.
//
// It sends through Resend (Supabase Auth's email only covers sign-in
// messages). Secrets:
//   RESEND_API_KEY   an API key from resend.com (Sending access is enough)
//   BUG_REPORT_FROM  the sender, on a domain verified in Resend, e.g.
//                    "Emerald Summit '27 App <app@ehsacademics.org>"
//   BUG_REPORT_TO    optional: where every ticket goes (comma-separated)
// (SITE_URL is no longer read: the team email's "Open in Reports" link went
// when the website dropped its reports page on Nov 22, 2026.)
// Without RESEND_API_KEY and BUG_REPORT_FROM it answers
// { ok: false, error: "email_not_configured" } and sends nothing; the report
// itself is already saved.
//
// Deploy with --no-verify-jwt, like the project's other functions: it checks
// the caller's session itself (auth.getUser), and the gateway's JWT check
// doesn't fit the project's new signing keys.
//   supabase functions deploy bug-report-email --no-verify-jwt
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are injected automatically.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const BUCKET = "bug_report_screenshots";
const LINK_SECONDS = 60 * 60 * 24 * 30; // screenshot links work for 30 days

type Json = Record<string, unknown>;

interface Report {
  id: string;
  ticket_no: number;
  user_id: string;
  kind: "bug" | "feedback";
  reporter_name: string;
  description: string;
  screenshots: string[];
  email_copy: boolean;
  client: Json;
  snapshot: Json;
  created_at: string;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  try {
    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );
    const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
    const { data: auth } = await admin.auth.getUser(token);
    const user = auth?.user;
    if (!user) return json({ error: "not_signed_in" }, 401);

    const body = await req.json().catch(() => ({}));
    const reportId = String(body.report_id ?? "");
    if (!/^[0-9a-f-]{36}$/i.test(reportId)) return json({ error: "bad_report_id" }, 400);

    if (!transportConfigured()) {
      return json({ ok: false, error: "email_not_configured" }, 200);
    }

    // Claim the report: only the sender, only once.
    const { data: report, error: claimError } = await admin
      .from("bug_reports")
      .update({ emailed_at: new Date().toISOString(), email_error: null })
      .eq("id", reportId)
      .eq("user_id", user.id)
      .is("emailed_at", null)
      .select("id, ticket_no, user_id, kind, reporter_name, description, screenshots, email_copy, client, snapshot, created_at")
      .maybeSingle<Report>();
    if (claimError) throw claimError;
    if (!report) return json({ ok: true, already: true }, 200);

    const links: { name: string; url: string }[] = [];
    for (const path of report.screenshots ?? []) {
      const { data } = await admin.storage.from(BUCKET).createSignedUrl(path, LINK_SECONDS);
      if (data?.signedUrl) links.push({ name: path.split("/").pop() ?? path, url: data.signedUrl });
    }

    const label = report.kind === "feedback" ? "Feedback" : "Bug";
    const errors: string[] = [];
    let sentCopy = false;
    let sentTeam = false;

    if (report.email_copy && user.email) {
      try {
        await sendMail({
          to: [user.email],
          subject: report.kind === "feedback"
            ? `Your Emerald Summit Feedback (Feedback #${report.ticket_no})`
            : `Your Emerald Summit Bug Report (Bug #${report.ticket_no})`,
          html: renderHtml(report, links, "copy"),
          text: renderText(report, links, "copy"),
          replyTo: teamAddresses()[0],
        });
        sentCopy = true;
      } catch (e) {
        errors.push(`copy: ${message(e)}`);
      }
    }

    const team = teamAddresses();
    if (team.length) {
      try {
        await sendMail({
          to: team,
          subject: `[${label} #${report.ticket_no}] ${firstLine(report.description)}`,
          html: renderHtml(report, links, "team"),
          text: renderText(report, links, "team"),
          replyTo: user.email ?? undefined,
        });
        sentTeam = true;
      } catch (e) {
        errors.push(`team: ${message(e)}`);
      }
    }

    if (errors.length) {
      await admin.from("bug_reports").update({ email_error: errors.join("; ").slice(0, 1000) }).eq("id", report.id);
    }
    return json({ ok: errors.length === 0, sent_copy: sentCopy, sent_team: sentTeam, error: errors[0] }, 200);
  } catch (e) {
    console.error(e);
    return json({ error: message(e) }, 500);
  }
});

// ── Sending ────────────────────────────────────────────────────────────────

function teamAddresses(): string[] {
  return (Deno.env.get("BUG_REPORT_TO") ?? "").split(",").map((s) => s.trim()).filter(Boolean);
}

function transportConfigured(): boolean {
  return Boolean(Deno.env.get("RESEND_API_KEY") && Deno.env.get("BUG_REPORT_FROM"));
}

async function sendMail(m: { to: string[]; subject: string; html: string; text: string; replyTo?: string }) {
  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${Deno.env.get("RESEND_API_KEY")}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from: Deno.env.get("BUG_REPORT_FROM"),
      to: m.to,
      subject: m.subject,
      html: m.html,
      text: m.text,
      ...(m.replyTo ? { reply_to: m.replyTo } : {}),
    }),
  });
  if (!res.ok) throw new Error(`Resend ${res.status}: ${(await res.text()).slice(0, 300)}`);
}

// ── Rendering ──────────────────────────────────────────────────────────────

type Audience = "copy" | "team";

function esc(v: unknown): string {
  return String(v ?? "").replace(/[&<>"']/g, (c) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]!);
}

function firstLine(s: string): string {
  const line = s.trim().split("\n")[0] ?? "";
  return line.length > 70 ? `${line.slice(0, 67)}…` : line;
}

function message(e: unknown): string {
  return e instanceof Error ? e.message : String(e);
}

const asArray = (v: unknown): Json[] => (Array.isArray(v) ? (v as Json[]) : []);
const asObject = (v: unknown): Json => (v && typeof v === "object" && !Array.isArray(v) ? (v as Json) : {});

/** The readable summary: label → value rows, grouped. */
function summary(report: Report): { title: string; rows: [string, string][] }[] {
  const snap = asObject(report.snapshot);
  const auth = asObject(snap.auth);
  const profile = asObject(snap.profile);
  const client = asObject(report.client);
  const device = asObject(client.device);
  const build = asObject(client.build);

  const session = (r: Json) => {
    const s = asObject(r.session);
    const team = asObject(r.team);
    const type = r.participation_type ? ` · ${r.participation_type}` : "";
    const teamText = team.project_name ? ` · team "${team.project_name}"` : "";
    return `${s.title ?? "?"} (${s.start_time ?? "?"}–${s.end_time ?? "?"}, ${s.room || "no room"})${type}${teamText}`;
  };

  const account: [string, string][] = [
    ["Email", String(auth.email ?? "")],
    ["Role", [profile.role, profile.volunteer_subtype].filter(Boolean).join(" · ")],
    ["Account created", String(auth.created_at ?? "")],
    ["Signs in with", asArray(auth.providers).join(", ")],
  ];
  if (profile.expert_status) account.push(["Expert status", String(profile.expert_status)]);
  const caps = ["can_edit_sessions", "can_post_announcements", "can_check_in_front_desk"]
    .filter((k) => profile[k] === true);
  if (caps.length) account.push(["Permissions", caps.join(", ")]);

  const regs = asArray(snap.registrations);
  const managing = asArray(snap.managing);
  const removed = asArray(snap.removed_from);
  const day: [string, string][] = [
    ["Sessions on your day", regs.length ? regs.map(session).join("\n") : "None"],
  ];
  if (managing.length) day.push(["Managing", managing.map(session).join("\n")]);
  if (removed.length) day.push(["Removed from", removed.map((r) => String(r.session_title ?? "")).join("\n")]);

  const pages = asArray(client.route_history).map((r) => String(r.path ?? "")).slice(-8);
  const errors = asArray(client.errors);
  const failed = asArray(client.failed_requests);
  const tech: [string, string][] = [
    ["Sent from", `${client.app ?? "website"} · ${client.page ?? ""}`],
    ["Pages before this", pages.join(" → ") || "None"],
    ["Browser", String(device.user_agent ?? "")],
    ["Screen", `${device.viewport ?? "?"} viewport, ${device.theme ?? "?"} theme, ${device.timezone ?? "?"}`],
    ["Build", [build.commit, build.built_at].filter(Boolean).join(" · ") || "unknown"],
    ["Recent errors", errors.length ? `${errors.length} (in the full data below)` : "None"],
    ["Failed requests", failed.length ? `${failed.length} (in the full data below)` : "None"],
  ];

  return [
    { title: "Your account", rows: account },
    { title: "Your sessions", rows: day },
    { title: "Device and page", rows: tech },
  ];
}

function renderHtml(report: Report, links: { name: string; url: string }[], audience: Audience): string {
  const label = report.kind === "feedback" ? "Feedback" : "Bug";
  const intro = audience === "copy"
    ? `<p style="margin:0 0 16px">Thanks, ${esc(report.reporter_name)}. We got your ${report.kind === "feedback" ? "feedback" : "bug report"}. This is a copy of everything that was sent, including what the Summit app attached from your account to help us fix it. Only Summit app developers can read reports. Reply to this email if you have more to add.</p>`
    : `<p style="margin:0 0 16px">From ${esc(report.reporter_name)} (${esc(asObject(asObject(report.snapshot).auth).email)}).</p>`;
  const shots = links.length
    ? `<p style="margin:12px 0 0"><b>Screenshots</b><br>${links.map((l) => `<a href="${esc(l.url)}">${esc(l.name)}</a>`).join("<br>")}</p>`
    : "";
  const sections = summary(report).map((s) => `
    <h3 style="font-size:15px;margin:24px 0 8px">${esc(s.title)}</h3>
    <table style="border-collapse:collapse;width:100%;font-size:13px">
      ${s.rows.map(([k, v]) => `<tr><td style="padding:4px 12px 4px 0;color:#555;vertical-align:top;white-space:nowrap">${esc(k)}</td><td style="padding:4px 0;white-space:pre-wrap">${esc(v)}</td></tr>`).join("")}
    </table>`).join("");
  const full = JSON.stringify({ client: report.client, account: report.snapshot }, null, 2);
  return `<!doctype html><html><body style="font-family:-apple-system,Segoe UI,Roboto,sans-serif;color:#111;max-width:680px;margin:0 auto;padding:24px">
    <h2 style="margin:0 0 4px">${label} #${report.ticket_no}</h2>
    <p style="margin:0 0 16px;color:#555;font-size:13px">${esc(new Date(report.created_at).toUTCString())}</p>
    ${intro}
    <div style="border:1px solid #ddd;border-radius:8px;padding:16px">
      <p style="margin:0 0 8px"><b>Name</b><br>${esc(report.reporter_name)}</p>
      <p style="margin:0;white-space:pre-wrap"><b>Description</b><br>${esc(report.description)}</p>
      ${shots}
    </div>
    ${sections}
    <h3 style="font-size:15px;margin:24px 0 8px">Everything attached, exactly as stored</h3>
    <pre style="font-size:11px;background:#f5f5f5;padding:12px;border-radius:8px;white-space:pre-wrap;word-break:break-word">${esc(full)}</pre>
  </body></html>`;
}

function renderText(report: Report, links: { name: string; url: string }[], audience: Audience): string {
  const label = report.kind === "feedback" ? "Feedback" : "Bug";
  const lines = [
    `${label} #${report.ticket_no}`,
    audience === "copy"
      ? "This is a copy of everything that was sent, including what the Summit app attached from your account. Only Summit app developers can read reports."
      : `From ${report.reporter_name}`,
    "",
    `Name: ${report.reporter_name}`,
    "Description:",
    report.description,
    ...(links.length ? ["", "Screenshots:", ...links.map((l) => `${l.name}: ${l.url}`)] : []),
  ];
  for (const s of summary(report)) {
    lines.push("", s.title.toUpperCase(), ...s.rows.map(([k, v]) => `${k}: ${v}`));
  }
  lines.push("", "EVERYTHING ATTACHED", JSON.stringify({ client: report.client, account: report.snapshot }, null, 2));
  return lines.join("\n");
}

function json(body: unknown, status: number) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}
