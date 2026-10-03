-- Emerald Summit — project teams for session participants
-- Run in the Supabase dashboard AFTER session_participation_setup.sql and
-- registration_answers_edit.sql. Safe to re-run.
--
-- Every PARTICIPANT registration now answers the app's built-in project
-- question: are you doing your project SOLO or as a TEAM?
--   * solo        → registrations.project_mode = 'solo' + registrations.project_name
--   * create team → a new `teams` row (project name + a shareable code), and the
--                   creator's registration points at it
--   * join team   → the registration points at an existing team, found by code
-- Team codes start with the discipline's two-letter prefix (TV, VV, BS, NS, CV,
-- IX) followed by digits, e.g. TV4821. A team only exists for one session.
-- Teammates are grouped under their project on the session roster, which the
-- session's editors (admins + scoped ambassadors) and its attendance takers see.
--
-- `teams` has no client grants — every read/write goes through the SECURITY
-- DEFINER RPCs below, which only ever act on the caller's own registration.

-- 1. Tables / columns --------------------------------------------------------
create table if not exists public.teams (
  id            uuid primary key default gen_random_uuid(),
  session_id    uuid not null references public.sessions (id) on delete cascade,
  code          text not null unique,
  project_name  text not null check (length(btrim(project_name)) > 0),
  created_by    uuid references auth.users (id) on delete set null,
  created_at    timestamptz not null default now()
);

create index if not exists teams_session_idx on public.teams (session_id);

alter table public.teams enable row level security;
-- (No policies, no grants: RPC-only access.)

alter table public.registrations
  add column if not exists project_mode text,
  add column if not exists project_name text,
  add column if not exists team_id uuid references public.teams (id) on delete set null;

alter table public.registrations
  drop constraint if exists registrations_project_mode_check;
alter table public.registrations
  add constraint registrations_project_mode_check
  check (project_mode is null or project_mode in ('solo', 'team'));

create index if not exists registrations_team_idx
  on public.registrations (team_id);

-- 2. Team codes --------------------------------------------------------------
-- The two-letter prefix for a discipline. The six summit disciplines are pinned
-- so renaming one never changes its prefix; any other discipline falls back to
-- the capital letters of its name (e.g. "RoboSphere" → RS).
create or replace function public.team_code_prefix(p_discipline_id text)
returns text
language sql stable security definer set search_path = public as $$
  select coalesce(
    case p_discipline_id
      when 'techverse'    then 'TV'
      when 'ventureverse' then 'VV'
      when 'biosphere'    then 'BS'
      when 'novasphere'   then 'NS'
      when 'civicverse'   then 'CV'
      when 'imaginex'     then 'IX'
    end,
    (select case
              when length(regexp_replace(d.name, '[^A-Z]', '', 'g')) >= 2
                then left(regexp_replace(d.name, '[^A-Z]', '', 'g'), 2)
              else rpad(upper(left(regexp_replace(d.name, '[^A-Za-z]', '', 'g'), 2)),
                        2, 'X')
            end
       from public.disciplines d where d.id = p_discipline_id),
    'TM');
$$;

-- A fresh, unused code: prefix + 4 random digits (grows a digit if a prefix
-- ever gets crowded).
create or replace function public.new_team_code(p_prefix text)
returns text
language plpgsql volatile security definer set search_path = public as $$
declare
  v_code   text;
  v_digits int := 4;
  v_tries  int := 0;
begin
  loop
    v_code := p_prefix || lpad(
      floor(random() * power(10, v_digits))::bigint::text, v_digits, '0');
    exit when not exists (select 1 from public.teams where code = v_code);
    v_tries := v_tries + 1;
    if v_tries % 25 = 0 then
      v_digits := v_digits + 1;
    end if;
  end loop;
  return v_code;
end;
$$;

-- Normalizes user-typed codes: "tv 4821" → "TV4821".
create or replace function public.normalize_team_code(p_code text)
returns text
language sql immutable as $$
  select upper(regexp_replace(coalesce(p_code, ''), '\s', '', 'g'));
$$;

-- A team with no members left is deleted, so its code stops working. Fires on
-- unregister, on switching teams/solo, and on account deletion (cascade).
create or replace function public.cleanup_empty_team()
returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if old.team_id is not null
     and (tg_op = 'DELETE' or new.team_id is distinct from old.team_id) then
    delete from public.teams t
     where t.id = old.team_id
       and not exists (select 1 from public.registrations r
                        where r.team_id = t.id);
  end if;
  return null;
end;
$$;

drop trigger if exists registrations_cleanup_team on public.registrations;
create trigger registrations_cleanup_team
  after delete or update of team_id on public.registrations
  for each row execute function public.cleanup_empty_team();

-- 3. find_team — look up a code before joining --------------------------------
-- Lets the registration form confirm "Is your project name X?" before the user
-- commits.
--   returns { "outcome": "found" | "not_found" | "wrong_session",
--             "project_name", "member_count", "session_title" }
create or replace function public.find_team(p_session_id uuid, p_code text)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_team public.teams%rowtype;
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
  return jsonb_build_object(
    'outcome', 'found',
    'project_name', v_team.project_name,
    'member_count',
    (select count(*) from public.registrations where team_id = v_team.id));
end;
$$;

grant execute on function public.find_team(uuid, text) to authenticated;

-- 4. register_for_session — now records the project choice --------------------
-- Supersedes the version in session_participation_setup.sql. Drop the older
-- overloads so PostgREST never sees an ambiguous candidate set.
--   p_project_mode: 'solo' | 'create' | 'join' (participants), or null.
--   returns { "outcome": "added" | "removed" | "full" | "conflict"
--                        | "team_not_found" | "team_wrong_session"
--                        | "project_name_required",
--             "conflicting_title", "team_code", "project_name" }
drop function if exists public.register_for_session(uuid);
drop function if exists public.register_for_session(uuid, text, jsonb);

create or replace function public.register_for_session(
  p_session_id uuid,
  p_participation_type text default 'participant',
  p_answers jsonb default '{}'::jsonb,
  p_project_mode text default null,
  p_project_name text default null,
  p_team_code text default null)
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  v_uid     uuid := auth.uid();
  v_sess    public.sessions%rowtype;
  v_count   int;
  v_clash   text;
  v_type    text := coalesce(p_participation_type, 'participant');
  v_name    text := nullif(btrim(coalesce(p_project_name, '')), '');
  v_team    public.teams%rowtype;
  v_team_id uuid;
  v_mode    text;
  v_solo    text;
begin
  if v_uid is null then
    raise exception 'Not authenticated';
  end if;

  if v_type not in ('participant', 'spectator', 'expert') then
    v_type := 'participant';
  end if;

  -- Already registered → toggle OFF (the trigger tidies an emptied team).
  if exists (select 1 from public.registrations
             where user_id = v_uid and session_id = p_session_id) then
    delete from public.registrations
      where user_id = v_uid and session_id = p_session_id;
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
       where code = public.normalize_team_code(p_team_code);
      if not found then
        return jsonb_build_object('outcome', 'team_not_found');
      elsif v_team.session_id <> p_session_id then
        return jsonb_build_object('outcome', 'team_wrong_session');
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
        insert into public.teams (session_id, code, project_name, created_by)
          values (p_session_id,
                  public.new_team_code(public.team_code_prefix(v_sess.discipline_id)),
                  v_name, v_uid)
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
  public.register_for_session(uuid, text, jsonb, text, text, text)
  to authenticated;

-- 5. update_my_registration — change answers + project later ------------------
-- A participant can switch solo ↔ team, create a new team, join a different
-- team, stay on their team (optionally renaming its project), and revise their
-- answers. Only ever touches the caller's own participant registration.
--   p_project_mode: 'solo' | 'create' | 'join' | 'stay'
--   returns { "outcome": "updated" | "not_registered" | "team_not_found"
--                        | "team_wrong_session" | "project_name_required"
--                        | "no_team",
--             "team_code", "project_name" }
create or replace function public.update_my_registration(
  p_session_id uuid,
  p_answers jsonb,
  p_project_mode text,
  p_project_name text default null,
  p_team_code text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid  uuid := auth.uid();
  v_reg  public.registrations%rowtype;
  v_sess public.sessions%rowtype;
  v_team public.teams%rowtype;
  v_name text := nullif(btrim(coalesce(p_project_name, '')), '');
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

  case p_project_mode
    when 'solo' then
      if v_name is null then
        return jsonb_build_object('outcome', 'project_name_required');
      end if;
      update public.registrations
         set answers = p_answers, project_mode = 'solo',
             project_name = v_name, team_id = null
       where id = v_reg.id;
      return jsonb_build_object('outcome', 'updated', 'project_name', v_name);

    when 'create' then
      if v_name is null then
        return jsonb_build_object('outcome', 'project_name_required');
      end if;
      insert into public.teams (session_id, code, project_name, created_by)
        values (p_session_id,
                public.new_team_code(public.team_code_prefix(v_sess.discipline_id)),
                v_name, v_uid)
        returning * into v_team;

    when 'join' then
      select * into v_team from public.teams
       where code = public.normalize_team_code(p_team_code);
      if not found then
        return jsonb_build_object('outcome', 'team_not_found');
      elsif v_team.session_id <> p_session_id then
        return jsonb_build_object('outcome', 'team_wrong_session');
      end if;

    when 'stay' then
      select * into v_team from public.teams where id = v_reg.team_id;
      if not found then
        return jsonb_build_object('outcome', 'no_team');
      end if;
      if v_name is not null and v_name <> v_team.project_name then
        update public.teams set project_name = v_name
         where id = v_team.id
        returning * into v_team;
      end if;

    else
      raise exception 'Unknown project mode %', p_project_mode;
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
  public.update_my_registration(uuid, jsonb, text, text, text) to authenticated;

-- 6. fetch_my_project — the caller's project for a session --------------------
-- Drives the project card on the session page (team code to share + teammates).
--   returns null when not registered, else
--   { "mode": "solo" | "team" | null, "project_name", "team_code",
--     "members": [names] }
create or replace function public.fetch_my_project(p_session_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_reg  public.registrations%rowtype;
  v_team public.teams%rowtype;
begin
  select * into v_reg from public.registrations
   where user_id = auth.uid() and session_id = p_session_id;
  if not found then
    return null;
  end if;
  if v_reg.team_id is null then
    return jsonb_build_object('mode', v_reg.project_mode,
                              'project_name', v_reg.project_name);
  end if;
  select * into v_team from public.teams where id = v_reg.team_id;
  return jsonb_build_object(
    'mode', 'team',
    'project_name', v_team.project_name,
    'team_code', v_team.code,
    'members', coalesce((
      select jsonb_agg(coalesce(nullif(p.full_name, ''), p.email)
                       order by p.full_name)
        from public.registrations r
        join public.profiles p on p.id = r.user_id
       where r.team_id = v_team.id), '[]'::jsonb));
end;
$$;

grant execute on function public.fetch_my_project(uuid) to authenticated;

-- 7. fetch_session_roster — now carries each person's project/team ------------
-- Supersedes the version in session_participation_setup.sql. The app groups
-- teammates under their project. Also opens the roster (read-only — marking
-- attendance is still assignment/admin-gated) to the session's editors, so
-- ambassadors who own the discipline can see who's working on what.
drop function if exists public.fetch_session_roster(uuid);

create or replace function public.fetch_session_roster(p_session_id uuid)
returns table (user_id uuid, full_name text, email text,
               attended boolean, attended_at timestamptz,
               participation_type text, answers jsonb,
               project_mode text, project_name text,
               team_id uuid, team_code text)
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
           t.id, t.code
      from public.registrations r
      join public.profiles p on p.id = r.user_id
      left join public.teams t on t.id = r.team_id
     where r.session_id = p_session_id
     order by p.full_name;
end;
$$;

grant execute on function public.fetch_session_roster(uuid) to authenticated;
