-- Emerald Summit — Archie knowledge base storage
--
-- Creates the PRIVATE Storage bucket the archie-chat Edge Function reads the
-- organizers' fact sheet from (supabase/archie/knowledge.md, uploaded as
-- "knowledge.md"). Private: no one can list or download it through the app's
-- API; the function reads it with the service role, and admins upload it from
-- the dashboard (Storage → archie). No policies are needed for either.
-- Safe to re-run.

insert into storage.buckets (id, name, public)
values ('archie', 'archie', false)
on conflict (id) do nothing;
