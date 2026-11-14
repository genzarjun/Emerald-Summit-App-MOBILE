-- Emerald Summit — 8th graders participate only in sessions that allow it.
-- Run AFTER registration_closed_lock.sql. Additive; safe to re-run.
--
-- 1. sessions.allow_eighth_graders (default false). Session editors (admins,
--    and volunteers with can_edit_sessions in that discipline) tick it per
--    session: "Let 8th graders participate". Anyone can spectate any session,
--    8th graders included; the box is only about participating.
-- 2. sessions_with_counts is rebuilt so it carries the new column (the view's
--    s.* was expanded when it was created). Same definition as before.
-- 3. grade_number(text) reads a sign-up grade answer the way the app's and the
--    website's gradeLabel do: "8", "8th", "eighth" -> 8; "11th", "Junior" -> 11;
--    anything else -> null.
-- 4. register_for_session refuses a NEW participant registration (solo,
--    creating or joining a team) when the caller's profiles.details.grade is
--    below 9, unless it's 8 and the session allows 8th graders:
--      grade 8, box unticked  -> error 'eighth_grade_not_allowed'
--      grade 7 or lower       -> error 'middle_school_not_allowed'
--    A blank grade isn't blocked. Unticking the box later doesn't remove
--    8th graders who already registered. The rest of the function is copied
--    unchanged from registration_closed_lock.sql (same signature, outcomes and
--    registration_closed check).

-- 1. The column -----------------------------------------------------------------
alter table public.sessions
  add column if not exists allow_eighth_graders boolean not null default false;

-- 2. The view -------------------------------------------------------------------
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

-- 3. Reading a grade answer ---------------------------------------------------------
create or replace function public.grade_number(p_grade text)
returns int
language sql
immutable
as $$
  select case
    when g = '' then null
    when g like '%freshman%'  then 9
    when g like '%sophomore%' then 10
    when g like '%junior%'    then 11
    when g like '%senior%'    then 12
    when g like '%eighth%'    then 8
    when d ~ '^[0-9]{1,2}$' and d::int between 1 and 12 then d::int
    else null
  end
  from (select lower(btrim(coalesce(p_grade, ''))) as g) a,
       lateral (select substring(a.g from '[0-9]+') as d) b;
$$;

grant execute on function public.grade_number(text) to authenticated;

-- 4. register_for_session --------------------------------------------------------
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
  v_team    public.teams%rowtype;
  v_team_id uuid;
  v_mode    text;
  v_solo    text;
  v_problem text;
  v_grade   int;
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
  -- experts fall through to the normal capacity / overlap checks.
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

  -- Validate the project choice before anything is written.
  if v_type = 'participant' and p_project_mode is not null then
    if p_project_mode in ('create', 'join') and v_sess.max_team_size < 2 then
      return jsonb_build_object('outcome', 'teams_not_allowed');
    elsif p_project_mode in ('solo', 'create') and v_name is null then
      return jsonb_build_object('outcome', 'project_name_required');
    elsif p_project_mode = 'join' then
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
    elsif p_project_mode not in ('solo', 'create', 'join') then
      raise exception 'Unknown project mode %', p_project_mode;
    end if;
  end if;

  -- Capacity cap (all registration types count).
  select count(*) into v_count
    from public.registrations where session_id = p_session_id;
  if v_count >= v_sess.capacity then
    return jsonb_build_object('outcome', 'full');
  end if;

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

  if v_type = 'participant' then
    case p_project_mode
      when 'solo' then
        v_mode := 'solo';
        v_solo := v_name;
      when 'create' then
        insert into public.teams
          (session_id, code, project_name, created_by, owner_id)
          values (p_session_id,
                  public.new_team_code(public.team_code_prefix(v_sess.discipline_id)),
                  v_name, v_uid, v_uid)
          returning * into v_team;
        v_mode := 'team';
        v_team_id := v_team.id;
      when 'join' then
        v_mode := 'team';
        v_team_id := v_team.id;
      else
        null; -- older app build: no project answer yet
    end case;
  end if;

  insert into public.registrations
    (user_id, session_id, participation_type, answers,
     project_mode, project_name, team_id)
    values (v_uid, p_session_id, v_type, coalesce(p_answers, '{}'::jsonb),
            v_mode, v_solo, v_team_id);

  return jsonb_build_object(
    'outcome', 'added',
    'team_code', v_team.code,
    'project_name', coalesce(v_team.project_name, v_solo));
end;
$function$;

grant execute on function public.register_for_session(
  uuid, text, jsonb, text, text, text, uuid, text) to authenticated;
