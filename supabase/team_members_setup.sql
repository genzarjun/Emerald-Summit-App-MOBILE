-- Emerald Summit — teammate notifications + owners removing members
-- Run in the Supabase dashboard AFTER project_prompt_setup.sql. Safe to re-run.
--
--   * When someone joins a team (registering with its code, or switching to it
--     later), every OTHER member gets a personal announcement in their feed
--     (and an in-app banner, via the existing target_user_id Realtime path).
--   * A team owner can remove a member (e.g. someone who got the code but
--     isn't on the team). The removed person stays registered for the session
--     — it stays on their schedule — but is taken off the team with no project
--     answer, so the session page asks them to add their project details. They
--     get a personal announcement saying so, and can't rejoin that team with
--     its code (teams.removed_user_ids; find_team reports 'removed').
-- These notices deliberately leave announcements.session_id null: that column
-- tags volunteer-assignment notices, which unassigning deletes by session.

-- 1. Removed members can't rejoin ---------------------------------------------
alter table public.teams
  add column if not exists removed_user_ids uuid[] not null default '{}';

-- Enforced on the registration row itself, so every path (register, switch
-- teams) is covered without redefining those RPCs. The RPCs surface it as an
-- error whose message is 'removed_from_team'.
create or replace function public.block_removed_rejoin()
returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.team_id is not null
     and (tg_op = 'INSERT' or new.team_id is distinct from old.team_id)
     and exists (select 1 from public.teams
                  where id = new.team_id
                    and new.user_id = any(removed_user_ids)) then
    raise exception 'removed_from_team';
  end if;
  return new;
end;
$$;

drop trigger if exists registrations_block_removed_rejoin on public.registrations;
create trigger registrations_block_removed_rejoin
  before insert or update of team_id on public.registrations
  for each row execute function public.block_removed_rejoin();

-- find_team — also tells a removed member they can't rejoin. Supersedes the
-- version in team_size_limits.sql.
--   adds outcome: "removed"
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
  if auth.uid() = any(v_team.removed_user_ids) then
    return jsonb_build_object('outcome', 'removed',
                              'project_name', v_team.project_name);
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

-- 2. "X joined your team" -----------------------------------------------------
create or replace function public.notify_team_join()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_team   public.teams%rowtype;
  v_sess   public.sessions%rowtype;
  v_joiner text;
begin
  if new.team_id is null
     or (tg_op = 'UPDATE' and new.team_id is not distinct from old.team_id) then
    return null;
  end if;
  select * into v_team from public.teams where id = new.team_id;
  select * into v_sess from public.sessions where id = new.session_id;
  select coalesce(nullif(full_name, ''), email, 'Someone') into v_joiner
    from public.profiles where id = new.user_id;

  insert into public.announcements
    (title, body, author, audience, pinned, discipline_id, created_by,
     target_user_id)
  select 'New teammate',
         format('%s joined your team "%s" for "%s".',
                coalesce(v_joiner, 'Someone'), v_team.project_name,
                v_sess.title),
         'Emerald Summit', 'Personal', false, v_sess.discipline_id,
         new.user_id, r.user_id
    from public.registrations r
   where r.team_id = new.team_id
     and r.user_id <> new.user_id;
  return null;
end;
$$;

drop trigger if exists registrations_notify_team_join on public.registrations;
create trigger registrations_notify_team_join
  after insert or update of team_id on public.registrations
  for each row execute function public.notify_team_join();

-- 3. remove_team_member — owner takes someone off the team --------------------
--   returns { "outcome": "removed" | "not_owner" | "not_member"
--                        | "cannot_remove_self" }
create or replace function public.remove_team_member(
  p_session_id uuid, p_user_id uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid  uuid := auth.uid();
  v_team public.teams%rowtype;
  v_sess public.sessions%rowtype;
begin
  select t.* into v_team
    from public.registrations r
    join public.teams t on t.id = r.team_id
   where r.user_id = v_uid and r.session_id = p_session_id
   for update of t;
  if not found or v_team.owner_id is distinct from v_uid then
    return jsonb_build_object('outcome', 'not_owner');
  end if;
  if p_user_id = v_uid then
    return jsonb_build_object('outcome', 'cannot_remove_self');
  end if;

  update public.registrations
     set team_id = null, project_mode = null, project_name = null
   where user_id = p_user_id and session_id = p_session_id
     and team_id = v_team.id;
  if not found then
    return jsonb_build_object('outcome', 'not_member');
  end if;
  update public.teams
     set removed_user_ids = array_append(removed_user_ids, p_user_id)
   where id = v_team.id and not (p_user_id = any(removed_user_ids));

  select * into v_sess from public.sessions where id = p_session_id;
  insert into public.announcements
    (title, body, author, audience, pinned, discipline_id, created_by,
     target_user_id)
  values (
    'Removed from a team',
    format('The owner of "%s" removed you from their team for "%s". You''re '
           || 'still registered for the session — open it to add your '
           || 'project details, or to go solo or join another team.',
           v_team.project_name, v_sess.title),
    'Emerald Summit', 'Personal', false, v_sess.discipline_id, v_uid,
    p_user_id);
  return jsonb_build_object('outcome', 'removed');
end;
$$;

grant execute on function public.remove_team_member(uuid, uuid) to authenticated;
