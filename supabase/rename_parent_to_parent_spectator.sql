-- Emerald Summit — rename the 'parent' role to 'parentSpectator'
-- Run once in the Supabase dashboard. Safe to re-run (idempotent update).
--
-- The app's SummitRole enum member was renamed parent → parentSpectator for
-- clarity (this is the role that auto-spectates: every session it adds becomes
-- "Spectating"). SummitRole.id is the enum `name`, so the stored value is now
-- 'parentSpectator'. profiles.role is free-form text (no enum type / CHECK), so
-- this is a plain data update — mirrors rename_mentor_to_volunteer.sql.

update public.profiles
   set role = 'parentSpectator'
 where role = 'parent';
