-- Emerald Summit — rooms catalog + session→room link
-- Run AFTER role_allowlist_v2.sql (it uses public.is_admin()).
--
-- Rooms are an ADMIN-MANAGED catalog inside the app (not the Google Sheet).
-- Every session is tied to one room; only one session runs in a room at a time.
-- The volunteer→SESSION assignment (session_volunteers_setup.sql) — not the room
-- — is what grants roster/attendance access; a room is just where a session meets.

-- 1. Table -------------------------------------------------------------------
create table if not exists public.rooms (
  id          uuid primary key default gen_random_uuid(),
  name        text not null unique,
  sort_order  int  not null default 0,
  created_at  timestamptz not null default now()
);

-- 2. Row Level Security ------------------------------------------------------
-- Public read (the catalog is shown wherever a session's room is displayed);
-- admin-only write.
alter table public.rooms enable row level security;

drop policy if exists "Public read rooms" on public.rooms;
create policy "Public read rooms"
  on public.rooms for select
  to anon, authenticated
  using (true);

drop policy if exists "Admins write rooms" on public.rooms;
create policy "Admins write rooms"
  on public.rooms for all
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());

grant select on public.rooms to anon, authenticated;
grant insert, update, delete on public.rooms to authenticated;

-- 3. Link sessions to a room -------------------------------------------------
alter table public.sessions
  add column if not exists room_id uuid references public.rooms (id) on delete set null;

create index if not exists sessions_room_idx on public.sessions (room_id);

-- 4. Migrate today's sessions (auto — no admin work needed) ------------------
-- Seed the catalog from the distinct room strings the existing sessions already
-- carry (e.g. 'Room 204', 'Gym A', 'Lab 101'), then point each session's new
-- room_id at its matching room. Sessions with a blank room stay room_id = NULL
-- ("Unassigned") for an admin to fix. The legacy sessions.room TEXT stays as the
-- display label (kept in sync by the editor going forward).
insert into public.rooms (name)
select distinct btrim(room)
  from public.sessions
 where coalesce(btrim(room), '') <> ''
on conflict (name) do nothing;

update public.sessions s
   set room_id = r.id
  from public.rooms r
 where btrim(s.room) = r.name
   and s.room_id is null;

-- 5. Recreate the view to expose room_id -------------------------------------
-- sessions_with_counts (registrations_setup.sql) selects s.*; a plain
-- CREATE OR REPLACE can't reorder columns, so drop + recreate to pick up the new
-- room_id column. Same security_invoker=false rationale as the original.
drop view if exists public.sessions_with_counts;
create view public.sessions_with_counts
with (security_invoker = false) as
  select
    s.*,
    d.name as discipline_name,
    (select count(*) from public.registrations r where r.session_id = s.id)
      as enrolled
  from public.sessions s
  join public.disciplines d on d.id = s.discipline_id;

grant select on public.sessions_with_counts to anon, authenticated;
