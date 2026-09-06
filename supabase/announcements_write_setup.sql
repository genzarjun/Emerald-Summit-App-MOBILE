-- Emerald Summit — announcements: admin write access + Realtime (Phase 3)
-- Run this in the Supabase dashboard AFTER announcements_setup.sql and
-- role_allowlist_setup.sql (it uses public.is_admin()).
--
-- Lets admins POST announcements from inside the app (previously the table was
-- read-only, edited in the dashboard). Public read stays as-is. Realtime is
-- enabled so every open app sees a new announcement the instant it's inserted.

-- 1. New columns -------------------------------------------------------------
alter table public.announcements
  add column if not exists created_by    uuid references auth.users (id) on delete set null,
  add column if not exists discipline_id text references public.disciplines (id) on delete set null;

-- 2. Admin write policies (public read policy already exists) -----------------
drop policy if exists "Admins insert announcements" on public.announcements;
create policy "Admins insert announcements"
  on public.announcements for insert
  to authenticated
  with check (public.is_admin());

drop policy if exists "Admins update announcements" on public.announcements;
create policy "Admins update announcements"
  on public.announcements for update
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());

drop policy if exists "Admins delete announcements" on public.announcements;
create policy "Admins delete announcements"
  on public.announcements for delete
  to authenticated
  using (public.is_admin());

grant insert, update, delete on public.announcements to authenticated;

-- 3. Realtime ----------------------------------------------------------------
-- Add the table to the realtime publication so postgres_changes events fire.
-- (Safe to run repeatedly; ignore "already member of publication".)
do $$
begin
  alter publication supabase_realtime add table public.announcements;
exception
  when duplicate_object then null;
end $$;
