-- Emerald Summit — rename the "mentor" role to "volunteer" (Phase: Volunteers)
-- Run this FIRST in the volunteers upgrade, BEFORE role_allowlist_v2.sql, so the
-- new enforcement trigger (which only recognizes 'volunteer'/'admin') doesn't
-- demote existing mentors back to participant.
--
-- WHY: the single "mentor" management role is being replaced by "volunteer",
-- which splits into subtypes (EAF ambassador, parent, student) with fine-grained
-- capabilities. The stored role string changes from 'mentor' to 'volunteer'
-- everywhere it appears.

-- 1. Widen the role_allowlist check constraint to accept 'volunteer' ----------
-- The inline `check (role in ('mentor','admin'))` from role_allowlist_setup.sql
-- is auto-named role_allowlist_role_check. Drop it, migrate the data, re-add a
-- constraint that allows the new value. (We allow both during the transition so
-- the UPDATE below never trips the constraint mid-flight.)
alter table public.role_allowlist
  drop constraint if exists role_allowlist_role_check;

-- 2. Migrate existing rows ---------------------------------------------------
update public.role_allowlist set role = 'volunteer' where role = 'mentor';
update public.profiles       set role = 'volunteer' where role = 'mentor';

-- 3. Re-add the constraint, now on the new value -----------------------------
alter table public.role_allowlist
  add constraint role_allowlist_role_check
  check (role in ('volunteer', 'admin'));
