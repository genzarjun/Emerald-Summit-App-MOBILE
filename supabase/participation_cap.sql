-- Emerald Summit — participate in up to 3 tracks; time conflicts on a switch.
-- Run AFTER participant_question_switches.sql. Safe to re-run.
--
-- Track times are not final yet, so for now (organizers, Nov 22, 2026):
--
-- 1. summit_settings.max_participating (default 3; null = no cap). A person
--    can register to participate in at most this many tracks. Spectating
--    and serving as an expert have no cap. Going over raises
--    'participation_limit_reached'; its hint is the message to show.
-- 2. summit_settings.schedule_conflicts_on (default false). While off,
--    register_for_session lets people add tracks that overlap their day or
--    a track they manage. A manager still can't sign up for the track they
--    run ('conflict', conflict_kind 'managing_this'). Turned on, the overlap
--    checks from participant_question_switches.sql apply again, unchanged.
--    The website reads it too (suggestions skip overlapping tracks).
--
-- When times are final: turn schedule_conflicts_on on, then run
-- resolve_schedule_conflicts() (schedule_conflict_resolver.sql) to clear
-- the overlaps people already have and notify them.
--
-- Organizer-side checks never changed: assigning a volunteer
-- (assign_volunteer_to_session) and an admin managing a track
-- (set_session_manage) still check overlaps.
--
-- register_for_session is copied from participant_question_switches.sql;
-- only the cap and the switch around the overlap checks are new.

alter table public.summit_settings
  add column if not exists max_participating int default 3,
  add column if not exists schedule_conflicts_on boolean not null default false;

create or replace function public.register_for_session(
  p_session_id uuid,
  p_participation_type text default 'participant',
  p_answers jsonb default '{}'::jsonb,
  p_project_mode text default null,
  p_project_name text default null,
  p_team_code text default null,
  p_new_owner_id uuid default null,
  p_intent text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_uid     uuid := auth.uid();
  v_sess    public.sessions%rowtype;
  v_reg     public.registrations%rowtype;
  v_count   int;
  v_clash   text;
  v_same    boolean;
  v_type    text := coalesce(p_participation_type, 'participant');
  v_name    text := nullif(btrim(coalesce(p_project_name, '')), '');
  v_pmode   text := p_project_mode;
  v_answers jsonb := coalesce(p_answers, '{}'::jsonb);
  v_code    text;
  v_team    public.teams%rowtype;
  v_team_id uuid;
  v_mode    text;
  v_solo    text;
  v_problem text;
  v_grade   int;
  v_cap     int;
  v_conflicts boolean;
begin
  if v_uid is null then
    raise exception 'Not authenticated';
  end if;

  if v_type not in ('participant', 'spectator', 'expert') then
    v_type := 'participant';
  end if;

  -- Already registered → toggle OFF. A team owner with teammates must hand the
  -- team over first.
  select * into v_reg from public.registrations
   where user_id = v_uid and session_id = p_session_id;
  if found then
    -- An add for a session they're already in changes nothing.
    if p_intent = 'add' then
      return jsonb_build_object('outcome', 'added');
    end if;
    if v_reg.team_id is not null then
      v_problem := public.team_hand_off(v_reg.team_id, p_new_owner_id);
      if v_problem is not null then
        return jsonb_build_object('outcome', v_problem);
      end if;
    end if;
    delete from public.registrations where id = v_reg.id;
    return jsonb_build_object('outcome', 'removed');
  end if;

  -- A remove for a session they've already left changes nothing.
  if p_intent = 'remove' then
    return jsonb_build_object('outcome', 'removed');
  end if;

  -- Registration closed (summit_settings.website_registration_open is off):
  -- no new sign-ups of any kind. Leaving a session (above) still works.
  -- Raised, not returned: older builds read an outcome they don't know as
  -- 'added', but show an error as an error.
  select st.max_participating, coalesce(st.schedule_conflicts_on, true)
    into v_cap, v_conflicts
    from public.summit_settings st limit 1;
  if not coalesce((select st.website_registration_open
                     from public.summit_settings st limit 1), false) then
    raise exception 'registration_closed'
      using hint = 'Registration will open on November 21st';
  end if;

  -- Lock the session row so two people can't both take its last seat: the
  -- second waits here until the first has inserted, then counts again.
  select * into v_sess from public.sessions where id = p_session_id for update;
  if not found then
    raise exception 'Session not found';
  end if;

  -- Only an approved expert can serve as one. Everyone else (including an
  -- expert still waiting for approval) gets 'expert_not_approved'.
  if v_type = 'expert' and not exists (
       select 1 from public.profiles
        where id = v_uid and role = 'expert' and expert_status = 'approved') then
    return jsonb_build_object('outcome', 'expert_not_approved');
  end if;

  -- Past the participant deadline: no new participants. Spectators and
  -- experts fall through to the normal capacity / cap / overlap checks.
  if v_type = 'participant'
     and v_sess.participant_deadline is not null
     and now() >= v_sess.participant_deadline then
    return jsonb_build_object('outcome', 'participation_closed',
                              'deadline', v_sess.participant_deadline);
  end if;

  -- Middle schoolers: an 8th grader participates only where the session's
  -- leads ticked allow_eighth_graders; younger students only spectate.
  -- Spectating and serving as an expert are open to every grade. Raised, not
  -- returned, for the same reason as registration_closed.
  if v_type = 'participant' then
    v_grade := public.grade_number(
      (select p.details ->> 'grade' from public.profiles p where p.id = v_uid));
    if v_grade is not null and v_grade < 9
       and not (v_grade = 8 and v_sess.allow_eighth_graders) then
      if v_grade = 8 then
        raise exception 'eighth_grade_not_allowed'
          using hint = 'This session is not open to 8th graders. They can still spectate.';
      else
        raise exception 'middle_school_not_allowed'
          using hint = 'Participating is for high schoolers and, in some sessions, 8th graders.';
      end if;
    end if;
  end if;

  -- A track that asks nothing: no project, no answers.
  if v_type = 'participant' and not v_sess.ask_participant_questions then
    v_pmode := null;
    v_answers := '{}'::jsonb;
  end if;

  -- Validate the project choice before anything is written.
  if v_type = 'participant' and v_pmode is not null then
    if v_pmode in ('create', 'join') and v_sess.max_team_size < 2 then
      return jsonb_build_object('outcome', 'teams_not_allowed');
    elsif v_pmode in ('solo', 'create') and v_name is null
          and v_sess.ask_project_name then
      return jsonb_build_object('outcome', 'project_name_required');
    elsif v_pmode = 'join' then
      select * into v_team from public.teams
       where code = public.normalize_team_code(p_team_code)
       for update;
      if not found then
        return jsonb_build_object('outcome', 'team_not_found');
      elsif v_team.session_id <> p_session_id then
        return jsonb_build_object('outcome', 'team_wrong_session');
      elsif (select count(*) from public.registrations
              where team_id = v_team.id) >= v_sess.max_team_size then
        return jsonb_build_object('outcome', 'team_full');
      end if;
    elsif v_pmode not in ('solo', 'create', 'join') then
      raise exception 'Unknown project mode %', v_pmode;
    end if;
  end if;

  -- Capacity cap (all registration types count).
  select count(*) into v_count
    from public.registrations where session_id = p_session_id;
  if v_count >= v_sess.capacity then
    return jsonb_build_object('outcome', 'full');
  end if;

  -- Participating is capped (summit_settings.max_participating, 3 for now;
  -- null = no cap). Spectating and serving as an expert are not. Raised, not
  -- returned, for the same reason as registration_closed; the hint is the
  -- message to show. The person's profile row is locked first so two adds
  -- sent at once can't both slip under the cap.
  if v_type = 'participant' and v_cap is not null then
    perform 1 from public.profiles where id = v_uid for update;
    if (select count(*) from public.registrations
         where user_id = v_uid and participation_type = 'participant') >= v_cap then
      raise exception 'participation_limit_reached'
        using hint = format('You can participate in up to %s tracks for now. '
                            || 'You can still spectate as many as you like.', v_cap);
    end if;
  end if;

  if v_conflicts then
    -- No double-booking: reject if it overlaps a session already in the plan.
    select s.title into v_clash
      from public.registrations r
      join public.sessions s on s.id = r.session_id
     where r.user_id = v_uid
       and v_sess.start_time::time < s.end_time::time
       and s.start_time::time     < v_sess.end_time::time
     limit 1;
    if v_clash is not null then
      return jsonb_build_object('outcome', 'conflict',
                                'conflicting_title', v_clash);
    end if;

    -- Nor one the caller manages (session_volunteers), whatever the
    -- registration type, this session included: a manager runs a session, they
    -- don't also sign up for it. Same-session first, for the clearer message.
    select s.title, s.id = p_session_id into v_clash, v_same
      from public.session_volunteers sv
      join public.sessions s on s.id = sv.session_id
     where sv.user_id = v_uid
       and (s.id = p_session_id
            or (v_sess.start_time::time < s.end_time::time
                and s.start_time::time  < v_sess.end_time::time))
     order by s.id = p_session_id desc
     limit 1;
    if v_clash is not null then
      return jsonb_build_object(
        'outcome', 'conflict',
        'conflicting_title', v_clash,
        'conflict_kind', case when v_same then 'managing_this' else 'managing' end);
    end if;
  else
    -- Time conflicts are off while track times are not final
    -- (summit_settings.schedule_conflicts_on). A manager still can't sign up
    -- for the track they run.
    if exists (select 1 from public.session_volunteers sv
                where sv.user_id = v_uid and sv.session_id = p_session_id) then
      return jsonb_build_object(
        'outcome', 'conflict',
        'conflicting_title', v_sess.title,
        'conflict_kind', 'managing_this');
    end if;
  end if;

  if v_type = 'participant' then
    case v_pmode
      when 'solo' then
        v_mode := 'solo';
        v_solo := v_name;
      when 'create' then
        v_code := public.new_team_code(public.team_code_prefix(v_sess.discipline_id));
        insert into public.teams
          (session_id, code, project_name, created_by, owner_id)
          values (p_session_id, v_code,
                  coalesce(v_name, public.default_team_name(v_uid, v_code)),
                  v_uid, v_uid)
          returning * into v_team;
        v_mode := 'team';
        v_team_id := v_team.id;
      when 'join' then
        v_mode := 'team';
        v_team_id := v_team.id;
      else
        null; -- no project: an older app build, or a track that asks nothing
    end case;
  end if;

  insert into public.registrations
    (user_id, session_id, participation_type, answers,
     project_mode, project_name, team_id)
    values (v_uid, p_session_id, v_type, v_answers,
            v_mode, v_solo, v_team_id);

  return jsonb_build_object(
    'outcome', 'added',
    'team_code', v_team.code,
    'project_name', coalesce(v_team.project_name, v_solo));
end;
$function$;

grant execute on function public.register_for_session(
  uuid, text, jsonb, text, text, text, uuid, text) to authenticated;
