-- Drops two unused columns from public.sessions:
--   track   - the old "track" a session belonged to, from before every
--             session became a track itself. No editor has set it since; the
--             website never read it, and the app stopped showing it on
--             Nov 23, 2026. Its leftover text was cleared the same day.
--   sponsor - a per-track sponsor note, empty on every track. Both apps
--             stopped showing it on Nov 23, 2026. (The Summit's sponsor
--             tiers live in the apps' code and are unaffected.)
--
-- sessions_with_counts lists every column by name, so it is dropped and
-- recreated without the two (same body, same security_invoker = false as
-- rooms_setup.sql / teams_ownership_setup.sql). The edit-history trigger
-- stops watching the two columns. Safe to re-run.

begin;

drop view if exists public.sessions_with_counts;

alter table public.sessions
  drop column if exists track,
  drop column if exists sponsor;

create view public.sessions_with_counts
with (security_invoker = false) as
select s.id,
       s.discipline_id,
       s.title,
       s.room,
       s.expert_name,
       s.start_time,
       s.end_time,
       s.capacity,
       s.description,
       s.created_by,
       s.created_at,
       s.updated_at,
       s.room_id,
       s.hero_image_url,
       s.page_blocks,
       s.participant_questions,
       s.max_team_size,
       s.project_prompt,
       s.participant_deadline,
       s.allow_eighth_graders,
       s.ask_participant_questions,
       s.ask_project_name,
       d.name as discipline_name,
       (select count(*) from public.registrations r where r.session_id = s.id) as enrolled
from public.sessions s
join public.disciplines d on d.id = s.discipline_id;

grant select on public.sessions_with_counts to anon, authenticated;

create or replace function public.activity_from_sessions()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  o jsonb;
  n jsonb;
  changes jsonb;
  texts jsonb;
  v_registered int;
begin
  if tg_op = 'INSERT' then
    perform public.log_activity('track_created', auth.uid(), new.id,
      public.activity_track_snapshot(new) || jsonb_build_object('via', public.activity_change_via()));
    return new;
  end if;

  if tg_op = 'DELETE' then
    -- BEFORE DELETE, so the registrations are still there to count.
    select count(*) into v_registered from public.registrations r where r.session_id = old.id;
    perform public.log_activity('track_deleted', auth.uid(), old.id,
      public.activity_track_snapshot(old)
        || jsonb_build_object('via', public.activity_change_via(),
                              'registered_when_deleted', v_registered));
    return old;
  end if;

  o := to_jsonb(old);
  n := to_jsonb(new);
  changes := public.activity_changes(o, n, array[
    'title', 'discipline_id', 'room', 'room_id', 'expert_name', 'start_time',
    'end_time', 'capacity', 'max_team_size', 'participant_deadline',
    'allow_eighth_graders', 'ask_participant_questions', 'ask_project_name',
    'hero_image_url']);
  texts := public.activity_changed_names(o, n, array[
    'description', 'page_blocks', 'participant_questions', 'project_prompt']);
  if changes <> '{}'::jsonb or texts <> '[]'::jsonb then
    perform public.log_activity('track_edited', auth.uid(), new.id,
      jsonb_build_object('session_title', new.title,
                         'discipline_id', new.discipline_id,
                         'changes', changes,
                         'text_changed', texts,
                         'via', public.activity_change_via()));
  end if;
  return new;
exception when others then
  raise warning 'activity_from_sessions: %', sqlerrm;
  return coalesce(new, old);
end;
$function$;

notify pgrst, 'reload schema';

commit;
