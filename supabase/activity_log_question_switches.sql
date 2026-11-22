-- Emerald Summit: log the participant question switches.
-- Run AFTER activity_log_more.sql and participant_question_switches.sql.
-- Safe to re-run.
--
-- participant_question_switches.sql added sessions.ask_participant_questions
-- and sessions.ask_project_name. This redefines the two track functions from
-- activity_log_more.sql so that:
--   * track_edited lists either switch in details.changes when it flips,
--     e.g. {"ask_participant_questions": {"from": true, "to": false}};
--   * track_created and track_deleted keep both switches in their copy of
--     the track.
-- Everything else is the same as activity_log_more.sql. The triggers there
-- already call these functions, so nothing else needs re-creating.
--
-- activity_log_more.sql lists the two switches for track_edited as well, so
-- re-running it keeps logging flips. Run this file again after it anyway, so
-- created and deleted tracks keep the switches in their copy.

create or replace function public.activity_track_snapshot(s public.sessions)
returns jsonb
language sql stable as $$
  select jsonb_build_object(
    'session_title', s.title,
    'discipline_id', s.discipline_id,
    'start_time',    s.start_time,
    'end_time',      s.end_time,
    'room',          s.room,
    'expert_name',   s.expert_name,
    'capacity',      s.capacity,
    'max_team_size', s.max_team_size,
    'ask_participant_questions', s.ask_participant_questions,
    'ask_project_name', s.ask_project_name,
    'description',   s.description);
$$;

revoke all on function public.activity_track_snapshot(public.sessions) from public, anon, authenticated;

create or replace function public.activity_from_sessions()
returns trigger
language plpgsql security definer set search_path = public as $$
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
    'title', 'discipline_id', 'track', 'room', 'room_id', 'expert_name', 'start_time',
    'end_time', 'capacity', 'max_team_size', 'participant_deadline',
    'allow_eighth_graders', 'ask_participant_questions', 'ask_project_name',
    'sponsor', 'hero_image_url']);
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
$$;

-- To check it, in the SQL Editor (rolled back, so nothing is kept):
--
--   begin;
--   update public.sessions set ask_participant_questions = not ask_participant_questions
--    where id = (select id from public.sessions limit 1);
--   select action, details -> 'changes' from public.activity_log
--    order by at desc limit 1;
--   rollback;
