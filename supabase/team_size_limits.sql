-- Emerald Summit — team size limits 2–8, and solo-only sessions
-- Run in the Supabase dashboard AFTER teams_ownership_setup.sql. Safe to
-- re-run.
--
-- sessions.max_team_size now ranges 1–8:
--   * 2–8 → the most people one team may have (default 4)
--   * 1   → SOLO ONLY: no teams allowed. Creating or joining a team is refused
--           with 'teams_not_allowed'. Switching an existing session to solo
--           only never removes anyone: people already on a team can stay on
--           it (or go solo), but no new teams form and nobody new joins.
-- Redefines find_team, register_for_session, and update_my_registration with
-- that check (same signatures as teams_ownership_setup.sql).

-- 1. The range ----------------------------------------------------------------
update public.sessions set max_team_size = 8 where max_team_size > 8;

alter table public.sessions
  drop constraint if exists sessions_max_team_size_check;
alter table public.sessions
  add constraint sessions_max_team_size_check
  check (max_team_size between 1 and 8);

-- 2. find_team — reports solo-only sessions -----------------------------------
--   returns { "outcome": "found" | "full" | "not_found" | "wrong_session"
--                        | "teams_not_allowed", ... }
create or replace function public.find_team(p_session_id uuid, p_code text)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_team  public.teams%rowtype;
  v_count int;
  v_max   int;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;
  select * into v_team from public.teams
   where code = public.normalize_team_code(p_code);
  if not found then
    return jsonb_build_object('outcome', 'not_found');
  end if;
  if v_team.session_id <> p_session_id then
    return jsonb_build_object(
      'outcome', 'wrong_session',
      'session_title',
      (select title from public.sessions where id = v_team.session_id));
  end if;
  select count(*) into v_count from public.registrations
   where team_id = v_team.id;
  select max_team_size into v_max from public.sessions where id = p_session_id;
  if v_max < 2 then
    return jsonb_build_object('outcome', 'teams_not_allowed');
  end if;
  return jsonb_build_object(
    'outcome', case when v_count >= v_max then 'full' else 'found' end,
    'project_name', v_team.project_name,
    'member_count', v_count,
    'max_team_size', v_max);
end;
$$;

grant execute on function public.find_team(uuid, text) to authenticated;

-- 3. register_for_session — refuses teams in solo-only sessions ---------------
create or replace function public.register_for_session(
  p_session_id uuid,
  p_participation_type text default 'participant',
  p_answers jsonb default '{}'::jsonb,
  p_project_mode text default null,
  p_project_name text default null,
  p_team_code text default null,
  p_new_owner_id uuid default null)
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  v_uid     uuid := auth.uid();
  v_sess    public.sessions%rowtype;
  v_reg     public.registrations%rowtype;
  v_count   int;
  v_clash   text;
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
    if v_reg.team_id is not null then
      v_problem := public.team_hand_off(v_reg.team_id, p_new_owner_id);
      if v_problem is not null then
        return jsonb_build_object('outcome', v_problem);
      end if;
    end if;
    delete from public.registrations where id = v_reg.id;
    return jsonb_build_object('outcome', 'removed');
  end if;

  select * into v_sess from public.sessions where id = p_session_id;
  if not found then
    raise exception 'Session not found';
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
$$;

grant execute on function
  public.register_for_session(uuid, text, jsonb, text, text, text, uuid)
  to authenticated;

-- 4. update_my_registration — refuses new teams in solo-only sessions ---------
create or replace function public.update_my_registration(
  p_session_id uuid,
  p_answers jsonb,
  p_project_mode text,
  p_project_name text default null,
  p_team_code text default null,
  p_new_owner_id uuid default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid     uuid := auth.uid();
  v_reg     public.registrations%rowtype;
  v_sess    public.sessions%rowtype;
  v_team    public.teams%rowtype;
  v_name    text := nullif(btrim(coalesce(p_project_name, '')), '');
  v_problem text;
begin
  if v_uid is null then
    raise exception 'Not authenticated';
  end if;
  if p_answers is null or jsonb_typeof(p_answers) <> 'object' then
    raise exception 'Answers must be a JSON object';
  end if;

  select * into v_reg from public.registrations
   where user_id = v_uid and session_id = p_session_id
     and participation_type = 'participant';
  if not found then
    return jsonb_build_object('outcome', 'not_registered');
  end if;
  select * into v_sess from public.sessions where id = p_session_id;

  -- Validate the destination before touching the current team. A solo-only
  -- session (max_team_size 1) refuses new teams and joins; anyone already on
  -- a team from before the switch can stay on it or go solo.
  if p_project_mode = 'create' and v_sess.max_team_size < 2 then
    return jsonb_build_object('outcome', 'teams_not_allowed');
  end if;
  case p_project_mode
    when 'solo', 'create' then
      if v_name is null then
        return jsonb_build_object('outcome', 'project_name_required');
      end if;
    when 'join' then
      select * into v_team from public.teams
       where code = public.normalize_team_code(p_team_code)
       for update;
      if not found then
        return jsonb_build_object('outcome', 'team_not_found');
      elsif v_team.session_id <> p_session_id then
        return jsonb_build_object('outcome', 'team_wrong_session');
      elsif v_team.id is distinct from v_reg.team_id
            and v_sess.max_team_size < 2 then
        return jsonb_build_object('outcome', 'teams_not_allowed');
      elsif v_team.id is distinct from v_reg.team_id
            and (select count(*) from public.registrations
                  where team_id = v_team.id) >= v_sess.max_team_size then
        return jsonb_build_object('outcome', 'team_full');
      end if;
    when 'stay' then
      select * into v_team from public.teams where id = v_reg.team_id;
      if not found then
        return jsonb_build_object('outcome', 'no_team');
      end if;
    else
      raise exception 'Unknown project mode %', p_project_mode;
  end case;

  -- Leaving the current team? An owner with teammates hands it over first.
  if v_reg.team_id is not null
     and p_project_mode <> 'stay'
     and v_team.id is distinct from v_reg.team_id then
    v_problem := public.team_hand_off(v_reg.team_id, p_new_owner_id);
    if v_problem is not null then
      return jsonb_build_object('outcome', v_problem);
    end if;
  end if;

  case p_project_mode
    when 'solo' then
      update public.registrations
         set answers = p_answers, project_mode = 'solo',
             project_name = v_name, team_id = null
       where id = v_reg.id;
      return jsonb_build_object('outcome', 'updated', 'project_name', v_name);
    when 'create' then
      insert into public.teams
        (session_id, code, project_name, created_by, owner_id)
        values (p_session_id,
                public.new_team_code(public.team_code_prefix(v_sess.discipline_id)),
                v_name, v_uid, v_uid)
        returning * into v_team;
    when 'stay' then
      if v_name is not null and v_name <> v_team.project_name then
        update public.teams set project_name = v_name
         where id = v_team.id
        returning * into v_team;
      end if;
    else
      null; -- 'join': v_team already resolved
  end case;

  update public.registrations
     set answers = p_answers, project_mode = 'team',
         project_name = null, team_id = v_team.id
   where id = v_reg.id;
  return jsonb_build_object('outcome', 'updated',
                            'team_code', v_team.code,
                            'project_name', v_team.project_name);
end;
$$;

grant execute on function
  public.update_my_registration(uuid, jsonb, text, text, text, uuid)
  to authenticated;
