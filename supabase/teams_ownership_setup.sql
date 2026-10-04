-- Emerald Summit — team owners, leaving a team, and team size limits
-- Run in the Supabase dashboard AFTER teams_setup.sql. Safe to re-run.
--
--   * Every team has an OWNER (teams.owner_id) — whoever created it, until they
--     hand it over. An owner who leaves (switches to solo, moves to another team,
--     or unregisters) while teammates remain must choose one of them as the new
--     owner; the RPCs refuse with 'choose_new_owner' otherwise. The last member
--     leaving still deletes the team. Owners can also hand ownership over while
--     staying (transfer_team_ownership).
--   * Each session has a team size limit (sessions.max_team_size, default 4),
--     set by its editors. Joining a full team is refused with 'team_full'.
--     Lowering the limit never removes anyone; it only blocks new joins.
--   * The roster marks each team's owner for organizers and attendance takers.

-- 1. Columns -----------------------------------------------------------------
alter table public.teams
  add column if not exists owner_id uuid references auth.users (id) on delete set null;

-- Existing teams: the creator owns it if they're still on it, else the
-- earliest-joined member does.
update public.teams t set owner_id = t.created_by
 where t.owner_id is null
   and exists (select 1 from public.registrations r
                where r.team_id = t.id and r.user_id = t.created_by);
update public.teams t
   set owner_id = (select r.user_id from public.registrations r
                    where r.team_id = t.id
                    order by r.created_at, r.user_id limit 1)
 where t.owner_id is null
    or not exists (select 1 from public.registrations r
                    where r.team_id = t.id and r.user_id = t.owner_id);

alter table public.sessions
  add column if not exists max_team_size int not null default 4;
alter table public.sessions
  drop constraint if exists sessions_max_team_size_check;
alter table public.sessions
  add constraint sessions_max_team_size_check
  check (max_team_size between 2 and 50);

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

-- 2. Membership trigger ------------------------------------------------------
-- Supersedes the version in teams_setup.sql. Still deletes an emptied team; if
-- members remain but the owner is gone (only possible without an explicit
-- hand-off, e.g. an account deletion), promotes the earliest-joined member.
create or replace function public.cleanup_empty_team()
returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if old.team_id is not null
     and (tg_op = 'DELETE' or new.team_id is distinct from old.team_id) then
    if not exists (select 1 from public.registrations
                    where team_id = old.team_id) then
      delete from public.teams where id = old.team_id;
    else
      update public.teams t
         set owner_id = (select r.user_id from public.registrations r
                          where r.team_id = t.id
                          order by r.created_at, r.user_id limit 1)
       where t.id = old.team_id
         and (t.owner_id is null
              or not exists (select 1 from public.registrations r
                              where r.team_id = t.id
                                and r.user_id = t.owner_id));
    end if;
  end if;
  return null;
end;
$$;

-- 3. Hand-off helper (internal) ----------------------------------------------
-- Called before the CALLER leaves p_team_id. Returns null when they may go
-- (they aren't the owner, or nobody else is left — the trigger then deletes the
-- team), after moving ownership to p_new_owner when needed. Otherwise returns
-- 'choose_new_owner' or 'invalid_new_owner'. Not callable by clients.
create or replace function public.team_hand_off(p_team_id uuid, p_new_owner uuid)
returns text
language plpgsql security definer set search_path = public as $$
declare
  v_uid   uuid := auth.uid();
  v_owner uuid;
begin
  select owner_id into v_owner from public.teams where id = p_team_id for update;
  if v_owner is distinct from v_uid then
    return null;
  end if;
  if not exists (select 1 from public.registrations
                  where team_id = p_team_id and user_id <> v_uid) then
    return null;
  end if;
  if p_new_owner is null then
    return 'choose_new_owner';
  end if;
  if p_new_owner = v_uid
     or not exists (select 1 from public.registrations
                     where team_id = p_team_id and user_id = p_new_owner) then
    return 'invalid_new_owner';
  end if;
  update public.teams set owner_id = p_new_owner where id = p_team_id;
  return null;
end;
$$;

revoke execute on function public.team_hand_off(uuid, uuid)
  from public, anon, authenticated;

-- 4. find_team — now reports fullness -----------------------------------------
--   returns { "outcome": "found" | "full" | "not_found" | "wrong_session",
--             "project_name", "member_count", "max_team_size", "session_title" }
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
  return jsonb_build_object(
    'outcome', case when v_count >= v_max then 'full' else 'found' end,
    'project_name', v_team.project_name,
    'member_count', v_count,
    'max_team_size', v_max);
end;
$$;

grant execute on function public.find_team(uuid, text) to authenticated;

-- 5. register_for_session — owner + size rules -------------------------------
-- Supersedes teams_setup.sql's version (adds p_new_owner_id).
--   adds outcomes: "team_full", "choose_new_owner", "invalid_new_owner"
drop function if exists
  public.register_for_session(uuid, text, jsonb, text, text, text);

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
    if p_project_mode in ('solo', 'create') and v_name is null then
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

-- 6. update_my_registration — owner + size rules ------------------------------
-- Supersedes teams_setup.sql's version (adds p_new_owner_id). 'solo' is also
-- how a member leaves their team.
--   adds outcomes: "team_full", "choose_new_owner", "invalid_new_owner"
drop function if exists
  public.update_my_registration(uuid, jsonb, text, text, text);

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

  -- Validate the destination before touching the current team.
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

-- 7. transfer_team_ownership — owner hands over while staying -----------------
--   returns { "outcome": "transferred" | "not_owner" | "invalid_new_owner" }
create or replace function public.transfer_team_ownership(
  p_session_id uuid, p_new_owner_id uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid  uuid := auth.uid();
  v_team public.teams%rowtype;
begin
  select t.* into v_team
    from public.registrations r
    join public.teams t on t.id = r.team_id
   where r.user_id = v_uid and r.session_id = p_session_id
   for update of t;
  if not found or v_team.owner_id is distinct from v_uid then
    return jsonb_build_object('outcome', 'not_owner');
  end if;
  if p_new_owner_id is null or p_new_owner_id = v_uid
     or not exists (select 1 from public.registrations
                     where team_id = v_team.id and user_id = p_new_owner_id) then
    return jsonb_build_object('outcome', 'invalid_new_owner');
  end if;
  update public.teams set owner_id = p_new_owner_id where id = v_team.id;
  return jsonb_build_object('outcome', 'transferred');
end;
$$;

grant execute on function
  public.transfer_team_ownership(uuid, uuid) to authenticated;

-- 8. fetch_my_project — adds owner info + the size limit ----------------------
--   { "mode", "project_name", "team_code", "is_owner", "max_team_size",
--     "members": [names],                       (kept for older app builds)
--     "member_details": [{ "id", "name", "is_owner" }] }   (join order)
create or replace function public.fetch_my_project(p_session_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_reg  public.registrations%rowtype;
  v_team public.teams%rowtype;
  v_max  int;
begin
  select * into v_reg from public.registrations
   where user_id = auth.uid() and session_id = p_session_id;
  if not found then
    return null;
  end if;
  select max_team_size into v_max from public.sessions where id = p_session_id;
  if v_reg.team_id is null then
    return jsonb_build_object('mode', v_reg.project_mode,
                              'project_name', v_reg.project_name,
                              'max_team_size', v_max);
  end if;
  select * into v_team from public.teams where id = v_reg.team_id;
  return jsonb_build_object(
    'mode', 'team',
    'project_name', v_team.project_name,
    'team_code', v_team.code,
    'is_owner', v_team.owner_id = auth.uid(),
    'max_team_size', v_max,
    'members', coalesce((
      select jsonb_agg(coalesce(nullif(p.full_name, ''), p.email)
                       order by r.created_at, r.user_id)
        from public.registrations r
        join public.profiles p on p.id = r.user_id
       where r.team_id = v_team.id), '[]'::jsonb),
    'member_details', coalesce((
      select jsonb_agg(jsonb_build_object(
                         'id', r.user_id,
                         'name', coalesce(nullif(p.full_name, ''), p.email),
                         'is_owner', r.user_id = v_team.owner_id)
                       order by r.created_at, r.user_id)
        from public.registrations r
        join public.profiles p on p.id = r.user_id
       where r.team_id = v_team.id), '[]'::jsonb));
end;
$$;

grant execute on function public.fetch_my_project(uuid) to authenticated;

-- 9. fetch_session_roster — marks each team's owner ---------------------------
-- Supersedes teams_setup.sql's version (adds is_team_owner). Same gate.
drop function if exists public.fetch_session_roster(uuid);

create or replace function public.fetch_session_roster(p_session_id uuid)
returns table (user_id uuid, full_name text, email text,
               attended boolean, attended_at timestamptz,
               participation_type text, answers jsonb,
               project_mode text, project_name text,
               team_id uuid, team_code text, is_team_owner boolean)
language plpgsql stable security definer set search_path = public as $$
begin
  if not (public.is_assigned_to_session(p_session_id)
          or public.is_admin()
          or public.can_manage_discipline(
               (select discipline_id from public.sessions
                 where id = p_session_id))) then
    raise exception 'Not authorized for this session roster';
  end if;
  return query
    select p.id, p.full_name, p.email, r.attended, r.attended_at,
           r.participation_type, r.answers,
           r.project_mode, coalesce(t.project_name, r.project_name),
           t.id, t.code, coalesce(t.owner_id = r.user_id, false)
      from public.registrations r
      join public.profiles p on p.id = r.user_id
      left join public.teams t on t.id = r.team_id
     where r.session_id = p_session_id
     order by p.full_name;
end;
$$;

grant execute on function public.fetch_session_roster(uuid) to authenticated;
