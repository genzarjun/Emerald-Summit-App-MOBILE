-- Emerald Summit — keep the volunteer hours Google Sheet in sync
-- Run AFTER volunteer_hours_setup.sql and summit_followup_setup.sql. Needs the
-- pg_net and pg_cron extensions. Safe to re-run.
--
-- The `sync-hours-sheet` Edge Function rewrites the whole sheet from the
-- database. Any change that affects a row (a log, a session assignment, a
-- session's times, a volunteer's name or details, feedback, the summit date)
-- marks the sheet dirty, and a cron job calls the function once a minute
-- while it's dirty, plus once an hour no matter what. Bursts of edits turn
-- into one rewrite, and a missed call is fixed within the hour.
--
-- One-time setup after running this file (not committed, the secret is
-- private): pick a random secret, store it here and as the function's
-- HOURS_SYNC_SECRET.
--   insert into private.hours_sheet_sync (id, function_url, secret)
--   values (true,
--           'https://<project-ref>.supabase.co/functions/v1/sync-hours-sheet',
--           '<secret>')
--   on conflict (id) do update
--     set function_url = excluded.function_url, secret = excluded.secret;

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create table if not exists private.hours_sheet_sync (
  id           boolean primary key default true check (id),
  function_url text not null,
  secret       text not null,
  dirty        boolean not null default true,
  last_sent_at timestamptz
);

-- Trigger function: mark the sheet dirty. Cheap; the cron does the call.
create or replace function private.mark_hours_sheet_dirty()
returns trigger language plpgsql security definer set search_path = private as $$
begin
  update private.hours_sheet_sync set dirty = true where not dirty;
  return null;
end;
$$;

-- Called by cron: POST to the function when dirty or an hour has passed.
create or replace function private.flush_hours_sheet_sync()
returns void language plpgsql security definer set search_path = private, public as $$
declare
  cfg private.hours_sheet_sync%rowtype;
begin
  select * into cfg from private.hours_sheet_sync where id;
  if not found then return; end if;
  if not cfg.dirty and cfg.last_sent_at > now() - interval '1 hour' then
    return;
  end if;
  -- Clear first: a change made while the sync runs marks it dirty again.
  update private.hours_sheet_sync set dirty = false, last_sent_at = now();
  perform net.http_post(
    url := cfg.function_url,
    headers := jsonb_build_object('Content-Type', 'application/json',
                                  'x-sync-secret', cfg.secret),
    body := '{}'::jsonb,
    timeout_milliseconds := 30000
  );
end;
$$;

-- Statement-level triggers on the tables whose every change matters.
do $$
declare t text;
begin
  foreach t in array array['volunteer_hour_logs', 'session_volunteers',
                           'expert_feedback', 'eaf_future_interest',
                           'summit_settings'] loop
    execute format('drop trigger if exists hours_sheet_dirty on public.%I', t);
    execute format(
      'create trigger hours_sheet_dirty after insert or update or delete '
      'on public.%I for each statement '
      'execute function private.mark_hours_sheet_dirty()', t);
  end loop;
end;
$$;

-- Sessions: only the fields that show on the sheet.
drop trigger if exists hours_sheet_dirty on public.sessions;
create trigger hours_sheet_dirty
  after update of title, start_time, end_time, discipline_id or delete
  on public.sessions
  for each statement execute function private.mark_hours_sheet_dirty();

-- Profiles: only volunteers and admins, and only fields that show on the sheet.
drop trigger if exists hours_sheet_dirty on public.profiles;
create trigger hours_sheet_dirty
  after update on public.profiles
  for each row
  when ((old.role in ('volunteer', 'admin') or new.role in ('volunteer', 'admin'))
        and (old.full_name is distinct from new.full_name
             or old.email is distinct from new.email
             or old.details is distinct from new.details
             or old.role is distinct from new.role
             or old.volunteer_subtype is distinct from new.volunteer_subtype))
  execute function private.mark_hours_sheet_dirty();

-- The function reads with the service-role key. This project doesn't grant
-- service_role table access by default, so grant read on exactly what it uses.
grant select on public.profiles, public.volunteer_hour_logs,
  public.summit_settings, public.sessions, public.disciplines,
  public.session_volunteers, public.expert_feedback, public.eaf_future_interest
  to service_role;

-- Every minute; flush_hours_sheet_sync decides whether to call.
select cron.unschedule('sync-hours-sheet')
 where exists (select 1 from cron.job where jobname = 'sync-hours-sheet');
select cron.schedule('sync-hours-sheet', '* * * * *',
                     'select private.flush_hours_sheet_sync()');
