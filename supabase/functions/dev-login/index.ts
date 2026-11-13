// Emerald Summit — dev-login Edge Function (TEST ONLY — never enable in prod)
//
// Lets a registered "code email" sign in WITHOUT an emailed OTP, so you can test
// each privilege level. Two calls, both from the normal sign-in screen:
//   { email, check: true } → { test: true | false }: is this a code email? The
//     client asks for the password only when it is.
//   { email, password }    → the one-time code (below).
// Given a code email that exists in the test_accounts
// table AND the shared test-account password, it ensures a confirmed auth user
// exists and returns that user's one-time code; the client then completes the
// NORMAL verifyOtp flow, producing a real Supabase session (so RLS, the role
// trigger, and every RPC behave exactly like production). Permissions still come
// from the Google Sheets like any user.
//
// Both the app and the public website call this, and anyone can read the
// publishable key out of either, so the password is the real gate:
//   1. Refuses unless the secret DEV_LOGIN_ENABLED === "true".
//   2. Refuses unless DEV_LOGIN_PASSWORD is set (12+ characters) and the caller
//      sends it. A wrong password gets a 401 after a delay, which keeps
//      guessing slow, and is recorded in dev_login_failures: 5 from one IP in
//      15 minutes, or 50 from anywhere in an hour, and every sign-in attempt
//      gets a 429 until they age out (dev_login_lockout.sql). If that table
//      is missing, the function still works, without the lockout. (The check call does say which emails are code emails;
//      they're named by role anyway, so the password is what protects them.)
//   3. The app only calls this when built with --dart-define DEV_LOGIN=true
//      (the website: VITE_DEV_LOGIN=true).
// Deploy it to your DEV project only.
//
// Secrets: DEV_LOGIN_ENABLED="true", DEV_LOGIN_PASSWORD="<shared password>".
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are injected automatically. Deploy
// with --no-verify-jwt (clients call it with only the publishable key, before
// any session exists).

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const MIN_PASSWORD_LENGTH = 12;

// Lockout limits; see dev_login_lockout.sql.
const IP_LIMIT = 5;
const IP_WINDOW_MS = 15 * 60 * 1000;
const GLOBAL_LIMIT = 50;
const GLOBAL_WINDOW_MS = 60 * 60 * 1000;

// Every refused sign-in waits this long, which keeps password guessing slow.
const REFUSAL_DELAY_MS = 1500;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS });
  }
  try {
    // Guard #1: hard off unless explicitly enabled on this project.
    const expected = Deno.env.get("DEV_LOGIN_PASSWORD") ?? "";
    if (
      Deno.env.get("DEV_LOGIN_ENABLED") !== "true" ||
      expected.length < MIN_PASSWORD_LENGTH
    ) {
      return json({ error: "disabled" }, 403);
    }

    const body = await req.json().catch(() => ({}));
    const email = String(body.email ?? "").trim().toLowerCase();
    const password = String(body.password ?? "");
    if (!email) return json({ test: false }, 200);

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );
    const isCodeEmail = async () => {
      const { data: row, error } = await supabase
        .from("test_accounts")
        .select("email")
        .eq("email", email)
        .maybeSingle();
      if (error) throw error;
      return row != null;
    };

    // The sign-in screen's first call: should it ask for the password?
    if (body.check === true) {
      return json({ test: await isCodeEmail() }, 200);
    }

    // Guard #2: too many wrong passwords lately, from this address or overall.
    const ip = callerIp(req);
    if (await isLockedOut(supabase, ip)) {
      console.warn(`dev-login: locked out ${ip} (${email})`);
      return json({ error: "too many attempts" }, 429);
    }

    // Guard #3: the shared password, compared in constant time. Only code
    // emails may bypass, even with the right password.
    if (!(await sameSecret(password, expected))) {
      await recordFailure(supabase, ip, email);
      return await refuse(email, "wrong password");
    }
    if (!(await isCodeEmail())) return await refuse(email, "not a code email");
    await clearFailures(supabase, ip);

    // Ensure a confirmed auth user exists (idempotent — ignore "already
    // registered"). Their profile + role/caps get applied by the DB trigger from
    // the allowlist on first sign-in, exactly like a real user.
    await supabase.auth.admin.createUser({ email, email_confirm: true });

    // Generate (don't send) a one-time code for this email.
    const { data: link, error: linkErr } = await supabase.auth.admin
      .generateLink({ type: "magiclink", email });
    if (linkErr) throw linkErr;

    const props = link.properties as
      | { email_otp?: string; verification_type?: string }
      | undefined;
    if (!props?.email_otp) throw new Error("no OTP returned");

    console.log(`dev-login: signed in ${email}`);
    return json({
      test: true,
      otp: props.email_otp,
      type: props.verification_type ?? "magiclink",
    }, 200);
  } catch (e) {
    // The details go to the function logs, not to whoever called.
    console.error("dev-login:", e instanceof Error ? e.message : String(e));
    return json({ error: "test sign-in failed" }, 500);
  }
});

// deno-lint-ignore no-explicit-any
type Client = any;

/** The caller's address as the Supabase gateway reports it. */
function callerIp(req: Request): string {
  const forwarded = req.headers.get("x-forwarded-for") ?? "";
  return forwarded.split(",")[0].trim() ||
    req.headers.get("cf-connecting-ip") ||
    "unknown";
}

/** True while this address, or everyone together, has used up its tries. */
async function isLockedOut(supabase: Client, ip: string): Promise<boolean> {
  const now = Date.now();
  const since = (ms: number) => new Date(now - ms).toISOString();
  const [mine, all] = await Promise.all([
    supabase.from("dev_login_failures").select("id", { count: "exact", head: true })
      .eq("ip", ip).gte("at", since(IP_WINDOW_MS)),
    supabase.from("dev_login_failures").select("id", { count: "exact", head: true })
      .gte("at", since(GLOBAL_WINDOW_MS)),
  ]);
  // Table not set up yet: no lockout, as before.
  if (mine.error || all.error) return false;
  return (mine.count ?? 0) >= IP_LIMIT || (all.count ?? 0) >= GLOBAL_LIMIT;
}

async function recordFailure(supabase: Client, ip: string, email: string) {
  const { error } = await supabase.from("dev_login_failures").insert({ ip, email });
  if (error) console.warn(`dev-login: could not record a failure: ${error.message}`);
}

async function clearFailures(supabase: Client, ip: string) {
  await supabase.from("dev_login_failures").delete().eq("ip", ip);
}

/** Logs the attempt (function logs only) and answers 401 after the delay. */
async function refuse(email: string, reason: string): Promise<Response> {
  console.warn(`dev-login: refused ${email || "(no email)"}: ${reason}`);
  await new Promise((r) => setTimeout(r, REFUSAL_DELAY_MS));
  return json({ error: "wrong email or password" }, 401);
}

/** Compares SHA-256 digests so the time taken doesn't depend on the input. */
async function sameSecret(given: string, expected: string): Promise<boolean> {
  const enc = new TextEncoder();
  const [a, b] = await Promise.all([
    crypto.subtle.digest("SHA-256", enc.encode(given)),
    crypto.subtle.digest("SHA-256", enc.encode(expected)),
  ]);
  const x = new Uint8Array(a);
  const y = new Uint8Array(b);
  let diff = 0;
  for (let i = 0; i < x.length; i++) diff |= x[i] ^ y[i];
  return diff === 0;
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}
