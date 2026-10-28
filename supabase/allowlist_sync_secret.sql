-- Emerald Summit — sync-allowlist only answers callers with the shared secret
-- Run AFTER hours_sheet_sync.sql (it reuses the `private` schema). Needs the
-- pg_net and pg_cron extensions. Safe to re-run.
--
-- The sync-allowlist Edge Function runs with "Verify JWT" off, so before this
-- anyone with its URL could start a sheet sync and read the counts and error
-- text it returns. The function now refuses any request without an
-- `x-sync-secret` header that matches its ALLOWLIST_SYNC_SECRET, the same way
-- sync-hours-sheet works.
--
--  1. private.allowlist_sync holds the function URL and the secret. The secret
--     is generated here, in the database, so it never sits in git.
--  2. private.flush_allowlist_sync() POSTs to the function with the header.
--  3. The `pull-from-sheets` cron job (every 5 minutes, first made by hand in
--     the dashboard with no headers) now calls that function instead.
--
-- One-time setup after running this file: copy the secret into the function.
--   select secret from private.allowlist_sync;
--   supabase secrets set ALLOWLIST_SYNC_SECRET=<that value>
-- Then redeploy: supabase functions deploy sync-allowlist --no-verify-jwt
-- (Until the redeploy the old function ignores the header, so nothing breaks
-- in between. Do the secret before the redeploy, or syncs fail with 401.)

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

-- 1. Config row ---------------------------------------------------------------
create table if not exists private.allowlist_sync (
  id           boolean primary key default true check (id),
  function_url text not null,
  secret       text not null
);
-- `private` isn't exposed to the API, so this is a second lock: no policies
-- means no client role can read it. The owner (postgres, which runs the cron
-- and the function below) isn't subject to RLS.
alter table private.allowlist_sync enable row level security;

-- Re-running keeps the existing secret, so the function secret stays valid.
insert into private.allowlist_sync (id, function_url, secret)
values (true,
        'https://dgrskmykbkvphnaasfzl.supabase.co/functions/v1/sync-allowlist',
        encode(extensions.gen_random_bytes(32), 'hex'))
on conflict (id) do nothing;

-- 2. The call -----------------------------------------------------------------
create or replace function private.flush_allowlist_sync()
returns void language plpgsql security definer set search_path = private, public as $$
declare
  cfg private.allowlist_sync%rowtype;
begin
  select * into cfg from private.allowlist_sync where id;
  if not found then return; end if;
  perform net.http_post(
    url := cfg.function_url,
    headers := jsonb_build_object('Content-Type', 'application/json',
                                  'x-sync-secret', cfg.secret),
    body := '{}'::jsonb,
    timeout_milliseconds := 30000
  );
end;
$$;

revoke all on function private.flush_allowlist_sync() from public, anon, authenticated;

-- 3. Cron -----------------------------------------------------------------------
select cron.unschedule('pull-from-sheets')
 where exists (select 1 from cron.job where jobname = 'pull-from-sheets');
select cron.schedule('pull-from-sheets', '*/5 * * * *',
                     'select private.flush_allowlist_sync()');
