-- Emerald Summit — editable wording for the built-in project question
-- Run in the Supabase dashboard AFTER team_size_limits.sql. Safe to re-run.
--
-- The app always asks solo participants and team creators for their project.
-- Session editors may now reword that question per session (e.g. "What will
-- you be presenting?"). sessions.project_prompt holds the custom wording; null
-- means the app's default, "What is your project name?". The question itself
-- stays built in and required — only its wording changes. The answer is still
-- stored as the project name (registrations.project_name / teams.project_name).

alter table public.sessions
  add column if not exists project_prompt text;

alter table public.sessions
  drop constraint if exists sessions_project_prompt_check;
alter table public.sessions
  add constraint sessions_project_prompt_check
  check (project_prompt is null
         or length(btrim(project_prompt)) between 1 and 200);

-- Rebuild sessions_with_counts so it exposes the new column (a `select s.*`
-- view freezes its column list at creation — see
-- session_participation_setup.sql). Same definition as before.
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
