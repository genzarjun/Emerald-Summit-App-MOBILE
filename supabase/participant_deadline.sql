-- Emerald Summit — a deadline for registering to PARTICIPATE in a session
-- Run in the Supabase dashboard AFTER project_prompt_setup.sql. Safe to re-run.
--
-- sessions.participant_deadline (timestamptz, nullable) is set by the
-- session's editors. Null = no deadline. From that moment on nobody can add
-- the session as a participant ('participation_closed'); spectating (and
-- serving as an expert) still works while seats are left — the usual capacity
-- cap applies. People who registered before the deadline keep their spot and
-- can still edit their project.
-- Redefines register_for_session with that check (same signature as
-- team_size_limits.sql).

-- 1. The column ---------------------------------------------------------------
alter table public.sessions
  add column if not exists participant_deadline timestamptz;

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

-- 2. register_for_session — refuses participants after the deadline -----------
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
