-- Emerald Summit — per-volunteer capability columns on profiles
-- Run AFTER rename_mentor_to_volunteer.sql and BEFORE role_allowlist_v2.sql.
--
-- Adds the fine-grained volunteer fields the enforcement trigger owns. Like
-- managed_disciplines, these are WRITE-PROTECTED for users: only the trigger
-- (from the synced allowlist) may set them. The app reads them to gate UI, but
-- the database is the real guard.

alter table public.profiles
  add column if not exists volunteer_subtype        text,
  add column if not exists can_edit_sessions        boolean not null default false,
  add column if not exists can_post_announcements   boolean not null default false,
  add column if not exists can_check_in_front_desk  boolean not null default false;

-- volunteer_subtype is one of 'eaf_ambassador' | 'parent_volunteer' |
-- 'student_volunteer' (null for non-volunteers). The three booleans are the
-- capabilities described in role_allowlist_v2.sql. Admins are global and ignore
-- these columns (the app grants them everything implicitly).
