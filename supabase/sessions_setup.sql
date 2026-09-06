-- Emerald Summit — sessions (activities) + live enrollment view
-- Run this in the Supabase dashboard AFTER disciplines_setup.sql.
--
-- A session is one activity a participant can add to their day. Previously
-- hard-coded (lib/data/sample_data.dart). `enrolled` is NOT stored — it is
-- always the live count of registrations, exposed via the sessions_with_counts
-- view below, so the number can never drift from reality.

-- 1. Table -------------------------------------------------------------------
create table if not exists public.sessions (
  id            uuid primary key default gen_random_uuid(),
  discipline_id text not null references public.disciplines (id) on delete cascade,
  title         text not null,
  track         text not null default '',
  room          text not null default '',
  expert_name   text not null default '',
  start_time    text not null,             -- "HH:mm" 24h (matches app parsing)
  end_time      text not null,             -- "HH:mm" 24h
  capacity      int  not null default 0,
  description   text not null default '',
  sponsor       text,
  created_by    uuid references auth.users (id) on delete set null,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create index if not exists sessions_discipline_idx
  on public.sessions (discipline_id);

-- 2. Row Level Security ------------------------------------------------------
-- Public read. Mentor/admin write policies are added in role_allowlist_setup.sql
-- (Phase 2), which defines public.is_admin() and public.can_manage_discipline().
alter table public.sessions enable row level security;

drop policy if exists "Public read sessions" on public.sessions;
create policy "Public read sessions"
  on public.sessions for select
  to anon, authenticated
  using (true);

grant select on public.sessions to anon, authenticated;

drop trigger if exists sessions_touch_updated_at on public.sessions;
create trigger sessions_touch_updated_at
  before update on public.sessions
  for each row execute function public.touch_updated_at();

-- The sessions_with_counts view (sessions + live enrolled count + discipline
-- name) lives in registrations_setup.sql, since it references the registrations
-- table — run that file next.

