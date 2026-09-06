-- Emerald Summit — extend the profiles table for per-user app state
-- Run this in the Supabase dashboard AFTER profiles_setup.sql.
--
-- Moves the last of the in-memory per-user state (AppState.notificationsEnabled,
-- AppState.volunteerHours) onto the account's profile row, and adds the mentor
-- scope column that Phase 2 (role_allowlist_setup.sql) populates and enforces.

alter table public.profiles
  add column if not exists notifications_enabled boolean not null default true,
  add column if not exists volunteer_hours       numeric not null default 0,
  add column if not exists managed_disciplines   text[]  not null default '{}';

-- managed_disciplines holds the discipline ids a mentor may manage, or the
-- single sentinel '*' for a high-level mentor who manages every discipline.
-- Admins are global and ignore this column. It is WRITE-PROTECTED for users:
-- the enforcement trigger added in role_allowlist_setup.sql (Phase 2) is the
-- only thing allowed to set it, from the synced allowlist. The existing
-- "Users update own profile" policy still lets a user edit their own
-- notifications_enabled / volunteer_hours / name.
