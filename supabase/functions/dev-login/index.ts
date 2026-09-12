// Emerald Summit — dev-login Edge Function (TEST ONLY — never enable in prod)
//
// Lets a registered "code email" sign in WITHOUT an emailed OTP, so you can test
// each privilege level. Given a code email that exists in the test_accounts
// table, it ensures a confirmed auth user exists and returns that user's one-time
// code; the app then completes the NORMAL verifyOtp flow, producing a real
// Supabase session (so RLS, the role trigger, and every RPC behave exactly like
// production). Permissions still come from the Google Sheets like any user.
//
// TWO GUARDS keep this out of production:
//   1. This function refuses unless the secret DEV_LOGIN_ENABLED === "true".
//   2. The app only calls it when built with --dart-define DEV_LOGIN=true.
// Deploy it to your DEV project only.
//
// Secrets: DEV_LOGIN_ENABLED="true". SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY
// are injected automatically. Deploy with --no-verify-jwt (the app calls it with
// only the publishable key, before any session exists).

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS });
  }
  try {
    // Guard #1: hard off unless explicitly enabled on this project.
    if (Deno.env.get("DEV_LOGIN_ENABLED") !== "true") {
      return json({ test: false, error: "dev login disabled" }, 403);
    }

    const body = await req.json().catch(() => ({}));
    const email = String(body.email ?? "").trim().toLowerCase();
    if (!email) return json({ test: false }, 200);

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // Only code emails may bypass. Anything else → the app uses normal OTP.
    const { data: row } = await supabase
      .from("test_accounts")
      .select("email")
      .eq("email", email)
      .maybeSingle();
    if (!row) return json({ test: false }, 200);

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

    return json({
      test: true,
      otp: props.email_otp,
      type: props.verification_type ?? "magiclink",
    }, 200);
  } catch (e) {
    const msg = e instanceof Error ? (e.message || "Error") : String(e);
    return json({ test: false, error: msg }, 500);
  }
});

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}
