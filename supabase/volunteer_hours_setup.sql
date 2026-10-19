-- Emerald Summit — volunteer hour logs
-- Run in the Supabase dashboard AFTER role_allowlist_setup.sql. Safe to re-run.
--
-- Volunteers and admins track their own hours from Profile → "Track volunteer
-- hours". Each row is one manual log: a start, an end, and what they did. The
-- app works out the length (end minus start).
--
-- Summit-day hours are NOT stored here. The app counts them from the sessions
-- the person manages (session_volunteers), so they follow assignments as an
-- admin changes them.
--
-- RLS: everyone reads and edits only their own rows, and only volunteers and
-- admins may add or change a log.

-- 1. Table -------------------------------------------------------------------
create table if not exists public.volunteer_hour_logs (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null default auth.uid()
                references auth.users (id) on delete cascade,
  started_at  timestamptz not null,
  ended_at    timestamptz not null,
  description text not null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  constraint volunteer_hour_logs_order check (ended_at > started_at),
  constraint volunteer_hour_logs_max_length
    check (ended_at - started_at <= interval '24 hours'),
  constraint volunteer_hour_logs_description
    check (char_length(trim(description)) between 1 and 500)
);

create index if not exists volunteer_hour_logs_user_idx
  on public.volunteer_hour_logs (user_id, started_at desc);

-- 2. Helper: is the caller a volunteer or admin? -----------------------------
create or replace function public.is_volunteer_or_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.profiles
     where id = auth.uid() and role in ('volunteer', 'admin')
  );
$$;

revoke execute on function public.is_volunteer_or_admin() from public, anon;
grant execute on function public.is_volunteer_or_admin() to authenticated;

-- 3. Row Level Security ------------------------------------------------------
alter table public.volunteer_hour_logs enable row level security;

drop policy if exists "Read own hour logs" on public.volunteer_hour_logs;
create policy "Read own hour logs"
  on public.volunteer_hour_logs for select
  to authenticated
  using (user_id = auth.uid());

drop policy if exists "Add own hour logs" on public.volunteer_hour_logs;
create policy "Add own hour logs"
  on public.volunteer_hour_logs for insert
  to authenticated
  with check (user_id = auth.uid() and public.is_volunteer_or_admin());

drop policy if exists "Edit own hour logs" on public.volunteer_hour_logs;
create policy "Edit own hour logs"
  on public.volunteer_hour_logs for update
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid() and public.is_volunteer_or_admin());

drop policy if exists "Delete own hour logs" on public.volunteer_hour_logs;
create policy "Delete own hour logs"
  on public.volunteer_hour_logs for delete
  to authenticated
  using (user_id = auth.uid());

grant select, insert, update, delete on public.volunteer_hour_logs to authenticated;

-- 4. Keep updated_at current -------------------------------------------------
create or replace function public.touch_volunteer_hour_log()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists volunteer_hour_logs_touch on public.volunteer_hour_logs;
create trigger volunteer_hour_logs_touch
  before update on public.volunteer_hour_logs
  for each row execute function public.touch_volunteer_hour_log();
