-- Emerald Summit — lockout for the dev-login test sign-in (TEST ONLY)
-- Run AFTER test_accounts_setup.sql, on the project dev-login is deployed to.
-- Safe to re-run.
--
-- The shared test-account password is the only gate on dev-login, and anyone
-- can call the function with the publishable key. The function records every
-- wrong password here and refuses (429) while:
--   * one address (the caller's IP) has 5 wrong passwords in 15 minutes, or
--   * there have been 50 wrong passwords in the last hour from anywhere, which
--     catches guessing spread over many addresses. It also blocks the test
--     accounts for everyone until the hour passes, which is fine for a test
--     sign-in.
-- A right password clears that address's count.

create table if not exists public.dev_login_failures (
  id         bigint generated always as identity primary key,
  ip         text not null,
  email      text not null default '',
  at         timestamptz not null default now()
);

create index if not exists dev_login_failures_ip_at
  on public.dev_login_failures (ip, at desc);
create index if not exists dev_login_failures_at
  on public.dev_login_failures (at desc);

-- RLS on with no policies: no client can read or write it. Only the function
-- (service role) uses it.
alter table public.dev_login_failures enable row level security;
revoke all on public.dev_login_failures from anon, authenticated;
grant select, insert, delete on public.dev_login_failures to service_role;
