-- Emerald Summit — managing and signing up never overlap
-- Run AFTER registrations_lockdown.sql. Safe to re-run.
--
-- A manager runs a session; they don't take part in it or in anything at the
-- same time. Every refusal is outcome 'conflict' (older app builds already
-- show a clash message for it) with a conflict_kind for newer builds.
--
--  1. register_for_session refuses any sign-up, participant, spectator or
--     expert, for a session the caller manages ('managing_this') or one that
--     overlaps it ('managing'). Before, only other registrations counted.
--     Otherwise unchanged from registrations_lockdown.sql (same signature).
--  2. assign_volunteer_to_session and set_session_manage refuse a session the
--     person is signed up for ('registered_this'); they remove it from their
--     day first. The admin's old "Assign anyway?" step for that case is gone.
--     They already refused overlaps with other sign-ups.
--
-- Nothing on dev breaks: no one both manages and is signed up for the same
-- session (checked 2026-10-27).

-- 1. register_for_session -----------------------------------------------------

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

-- 2. Managing refuses a session you're signed up for -------------------------
-- Copied from the live definitions (2026-10-27) with only the
-- 'registered_this' check added, and the registered_confirm step removed.
CREATE OR REPLACE FUNCTION public.assign_volunteer_to_session(p_session_id uuid, p_user_id uuid, p_confirm_registered boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_sess  public.sessions%rowtype;
  v_clash text;
  v_disc  text;
begin
  if not public.is_admin() then
    raise exception 'Only admins may assign volunteers';
  end if;

  if exists (select 1 from public.session_volunteers
             where session_id = p_session_id and user_id = p_user_id) then
    return jsonb_build_object('outcome', 'assigned');
  end if;

  select * into v_sess from public.sessions where id = p_session_id;
  if not found then
    raise exception 'Session not found';
  end if;

  -- Signed up for this session: they remove it from their day before they
  -- can manage it. This replaces the old 'registered_confirm' step, which let
  -- an admin assign them anyway; p_confirm_registered is kept for older app
  -- builds and no longer does anything.
  if exists (select 1 from public.registrations
              where user_id = p_user_id and session_id = p_session_id) then
    return jsonb_build_object('outcome', 'conflict',
                              'conflicting_title', v_sess.title,
                              'conflict_kind', 'registered_this');
  end if;

  select s.title into v_clash
    from public.session_volunteers sv
    join public.sessions s on s.id = sv.session_id
   where sv.user_id = p_user_id and s.id <> p_session_id
     and v_sess.start_time::time < s.end_time::time
     and s.start_time::time     < v_sess.end_time::time
   limit 1;
  if v_clash is null then
    select s.title into v_clash
      from public.registrations r
      join public.sessions s on s.id = r.session_id
     where r.user_id = p_user_id and s.id <> p_session_id
       and v_sess.start_time::time < s.end_time::time
       and s.start_time::time     < v_sess.end_time::time
     limit 1;
  end if;
  if v_clash is not null then
    return jsonb_build_object('outcome', 'conflict', 'conflicting_title', v_clash);
  end if;

  insert into public.session_volunteers (session_id, user_id, assigned_by)
    values (p_session_id, p_user_id, auth.uid());

  select name into v_disc from public.disciplines where id = v_sess.discipline_id;
  insert into public.announcements
    (title, body, author, audience, pinned, discipline_id, created_by,
     target_user_id, session_id)
  values (
    'You''re managing a session',
    format('You have been assigned to manage "%s" in %s.',
           v_sess.title, coalesce(v_disc, 'the summit')),
    'Summit Admin', 'Personal', false,
    v_sess.discipline_id, auth.uid(), p_user_id, p_session_id);

  return jsonb_build_object('outcome', 'assigned');
end;
$function$;

CREATE OR REPLACE FUNCTION public.set_session_manage(p_session_id uuid, p_manage boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid   uuid := auth.uid();
  v_sess  public.sessions%rowtype;
  v_clash text;
begin
  if not public.is_admin() then
    raise exception 'Only admins may self-manage a session';
  end if;

  -- Remove.
  if not coalesce(p_manage, false) then
    delete from public.session_volunteers
      where session_id = p_session_id and user_id = v_uid;
    return jsonb_build_object('outcome', 'unmanaged');
  end if;

  -- Idempotent add.
  if exists (select 1 from public.session_volunteers
             where session_id = p_session_id and user_id = v_uid) then
    return jsonb_build_object('outcome', 'managing');
  end if;

  select * into v_sess from public.sessions where id = p_session_id;
  if not found then
    raise exception 'Session not found';
  end if;

  -- Signed up for this session: they remove it from their day first. A
  -- manager runs the session; they don't also take part in it.
  if exists (select 1 from public.registrations
              where user_id = v_uid and session_id = p_session_id) then
    return jsonb_build_object('outcome', 'conflict',
                              'conflicting_title', v_sess.title,
                              'conflict_kind', 'registered_this');
  end if;

  -- Overlap vs the admin's other managed sessions, then their registrations
  -- (excluding this session).
  select s.title into v_clash
    from public.session_volunteers sv
    join public.sessions s on s.id = sv.session_id
   where sv.user_id = v_uid
     and s.id <> p_session_id
     and v_sess.start_time::time < s.end_time::time
     and s.start_time::time     < v_sess.end_time::time
   limit 1;

  if v_clash is null then
    select s.title into v_clash
      from public.registrations r
      join public.sessions s on s.id = r.session_id
     where r.user_id = v_uid
       and s.id <> p_session_id
       and v_sess.start_time::time < s.end_time::time
       and s.start_time::time     < v_sess.end_time::time
     limit 1;
  end if;

  if v_clash is not null then
    return jsonb_build_object('outcome', 'conflict',
                              'conflicting_title', v_clash);
  end if;

  insert into public.session_volunteers (session_id, user_id, assigned_by)
    values (p_session_id, v_uid, v_uid);
  return jsonb_build_object('outcome', 'managing');
end;
$function$;
