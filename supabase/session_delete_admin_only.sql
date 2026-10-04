-- Emerald Summit — only admins may delete sessions
-- Run in the Supabase dashboard AFTER team_members_setup.sql. Safe to re-run.
--
-- Session editors (admins, or volunteers who can edit sessions and are scoped
-- to the discipline) used to share one FOR ALL policy, so they could also
-- delete. Deleting a session wipes its registrations and teams, so it's now
-- admin-only: editors keep insert + update, and DELETE requires is_admin().

drop policy if exists "Managers write sessions" on public.sessions;
drop policy if exists "Managers insert sessions" on public.sessions;
drop policy if exists "Managers update sessions" on public.sessions;
drop policy if exists "Admins delete sessions" on public.sessions;

create policy "Managers insert sessions"
  on public.sessions for insert
  to authenticated
  with check (public.can_manage_discipline(discipline_id));

create policy "Managers update sessions"
  on public.sessions for update
  to authenticated
  using (public.can_manage_discipline(discipline_id))
  with check (public.can_manage_discipline(discipline_id));

create policy "Admins delete sessions"
  on public.sessions for delete
  to authenticated
  using (public.is_admin());
