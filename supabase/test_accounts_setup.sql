-- Emerald Summit — test/dev "code email" accounts (TEST ONLY)
-- Run in your DEV project only. Backs the dev-login Edge Function, which lets a
-- known code email sign in WITHOUT an emailed OTP so you can test each privilege
-- level. Do NOT run this (or deploy dev-login) in production.
--
-- The permissions for each code email still come from the Google Sheets exactly
-- like a real user: put the same mock emails in the Volunteers/Admins sheet with
-- the roles/capabilities you want to test.

create table if not exists public.test_accounts (
  email      text primary key,   -- store lowercased
  label      text,               -- optional note, e.g. "student + front desk"
  created_at timestamptz not null default now()
);

-- Lock it down: RLS on, NO policies → no client (anon/authenticated) can read or
-- write it. Only the dev-login Edge Function (service role, bypasses RLS) reads
-- it; service_role still needs table privileges because this project doesn't
-- auto-expose new tables.
alter table public.test_accounts enable row level security;
grant select, insert, update, delete on public.test_accounts to service_role;

-- Seed your code emails here (or in the Table Editor). Examples — edit to taste:
-- insert into public.test_accounts (email, label) values
--   ('admin@ehsacademics.org',              'admin'),
--   ('ambassador-tech@ehsacademics.org',    'eaf ambassador · techverse'),
--   ('student-frontdesk@ehsacademics.org',  'student · front desk'),
--   ('student-plain@ehsacademics.org',      'student · no extra caps'),
--   ('parent-helper@ehsacademics.org',      'parent · assigned in-app'),
--   ('participant@ehsacademics.org',        'plain participant')
-- on conflict (email) do nothing;
