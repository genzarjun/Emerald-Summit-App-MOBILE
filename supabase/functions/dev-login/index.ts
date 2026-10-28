// Emerald Summit — dev-login Edge Function (TEST ONLY — never enable in prod)
//
// Lets a registered "code email" sign in WITHOUT an emailed OTP, so you can test
// each privilege level. Given a code email that exists in the test_accounts
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
//      sends it. A wrong password and an email that isn't a code email get the
//      same 401 after the same delay, so the function never confirms which
//      emails are test accounts.
//   3. The app only shows the test-account form when built with
//      --dart-define DEV_LOGIN=true (the website: VITE_DEV_LOGIN=true).
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

// Every refusal past the enabled check waits this long, which keeps password
// guessing slow and makes "not a code email" look the same as "wrong password".
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

    // Guard #2: the shared password, compared in constant time.
    if (!email || !(await sameSecret(password, expected))) {
      return await refuse(email, "wrong password");
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // Only code emails may bypass, even with the right password.
    const { data: row } = await supabase
      .from("test_accounts")
      .select("email")
      .eq("email", email)
      .maybeSingle();
    if (!row) return await refuse(email, "not a code email");

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
    const msg = e instanceof Error ? (e.message || "Error") : String(e);
    return json({ error: msg }, 500);
  }
});

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
