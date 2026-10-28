-- Emerald Summit — table access for sync-allowlist's admin notice
-- Run in the Supabase dashboard AFTER announcements_insert_lockdown.sql.
-- Safe to re-run.
--
-- sync-allowlist posts, updates and deletes the admins' rolling "Problem with
-- the Google Sheet" notice with the service-role key, and reads the admin list
-- to address it. service_role bypasses RLS but this project doesn't grant it
-- table access by default, so grant exactly what that code uses. Deleting the
-- notice cascades to announcement_reads and announcement_dismissals as the
-- table owner, so those need nothing here.

grant select, insert, update, delete on public.announcements to service_role;

-- Also granted by hours_sheet_sync.sql; repeated so this file works alone.
grant select on public.profiles to service_role;
