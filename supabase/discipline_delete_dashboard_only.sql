-- Emerald Summit — disciplines can only be deleted from the Supabase dashboard
-- Run in the Supabase dashboard AFTER session_cancel_notices.sql. Safe to
-- re-run.
--
-- The app no longer offers deleting a discipline, and no app user — admins
-- included — may delete one through the API. Admins keep creating and editing
-- disciplines. Deleting one is done by the project owner in the dashboard
-- (Table Editor, or `delete from public.disciplines where id = '…';` in the SQL
-- Editor), which runs as a privileged role that bypasses these rules.
--
-- What a dashboard delete does: its sessions cascade away, and each session's
-- "Session cancelled" trigger (session_cancel_notices.sql) notifies everyone
-- registered for it and its assigned volunteers. Use DELETE, not TRUNCATE —
-- TRUNCATE skips triggers, so nobody would be notified.

-- Replace the admin "for all" write policy with insert + update only.
drop policy if exists "Admins write disciplines" on public.disciplines;
drop policy if exists "Admins insert disciplines" on public.disciplines;
drop policy if exists "Admins update disciplines" on public.disciplines;

create policy "Admins insert disciplines"
  on public.disciplines for insert
  to authenticated
  with check (public.is_admin());

create policy "Admins update disciplines"
  on public.disciplines for update
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());

-- Belt and braces: app roles lose the DELETE privilege outright.
revoke delete on public.disciplines from anon, authenticated;
grant insert, update on public.disciplines to authenticated;
