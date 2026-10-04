-- Emerald Summit — "left your team" + "you're now the owner" notices
-- Run in the Supabase dashboard AFTER team_members_setup.sql. Safe to re-run.
--
--   * When someone leaves a team — going solo, switching teams, or removing the
--     session from their day — every remaining member gets a personal
--     "X left your team" announcement (+ in-app banner).
--   * When an owner removes someone, the other remaining members get
--     "X was removed from your team" (the owner did it, so they don't).
--   * Whoever becomes a team's owner — handed over by a leaving owner, a
--     transfer, or the automatic backstop — gets "You're now the owner".
-- Nothing is sent when the session itself is being deleted (its registrations
-- and teams go with it), or when the last member leaves (the team is deleted).
-- Like the join notices, these leave announcements.session_id null.

-- 1. Leaving / removed ---------------------------------------------------------
create or replace function public.notify_team_leave()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_team   public.teams%rowtype;
  v_sess   public.sessions%rowtype;
  v_name   text;
  v_actor  uuid := auth.uid();
  v_self   boolean;
begin
  if old.team_id is null
     or (tg_op = 'UPDATE' and new.team_id is not distinct from old.team_id) then
    return null;
  end if;
  -- A session being deleted takes its registrations with it; stay quiet.
  select * into v_sess from public.sessions where id = old.session_id;
  if not found then
    return null;
  end if;
  -- The last member leaving deletes the team (earlier trigger); no one to tell.
  select * into v_team from public.teams where id = old.team_id;
  if not found then
    return null;
  end if;
  select coalesce(nullif(full_name, ''), email) into v_name
    from public.profiles where id = old.user_id;
  v_name := coalesce(v_name, 'A teammate');
  -- They left on their own (or their account was deleted) vs. were removed.
  v_self := v_actor is null or v_actor = old.user_id;

  insert into public.announcements
    (title, body, author, audience, pinned, discipline_id, created_by,
     target_user_id)
  select case when v_self then 'Teammate left' else 'Teammate removed' end,
         case when v_self
           then format('%s left your team "%s" for "%s".',
                       v_name, v_team.project_name, v_sess.title)
           else format('%s was removed from your team "%s" for "%s".',
                       v_name, v_team.project_name, v_sess.title)
         end,
         -- created_by is only ever the acting user (null for e.g. an account
         -- deletion): it references auth.users, so naming a user who's being
         -- deleted would block the deletion.
         'Emerald Summit', 'Personal', false, v_sess.discipline_id,
         v_actor, r.user_id
    from public.registrations r
   where r.team_id = old.team_id
     and r.user_id <> old.user_id
     and r.user_id is distinct from v_actor;
  return null;
end;
$$;

drop trigger if exists registrations_notify_team_leave on public.registrations;
create trigger registrations_notify_team_leave
  after delete or update of team_id on public.registrations
  for each row execute function public.notify_team_leave();

-- 2. New owner ------------------------------------------------------------------
create or replace function public.notify_team_owner()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_sess public.sessions%rowtype;
begin
  if new.owner_id is null
     or new.owner_id is not distinct from old.owner_id then
    return null;
  end if;
  select * into v_sess from public.sessions where id = new.session_id;
  if not found then
    return null;
  end if;
  insert into public.announcements
    (title, body, author, audience, pinned, discipline_id, created_by,
     target_user_id)
  values (
    'You''re now a team owner',
    format('You''re now the owner of "%s" for "%s". From the session page you '
           || 'can remove members or hand the team over.',
           new.project_name, v_sess.title),
    'Emerald Summit', 'Personal', false, v_sess.discipline_id,
    auth.uid(), new.owner_id);
  return null;
end;
$$;

drop trigger if exists teams_notify_owner on public.teams;
create trigger teams_notify_owner
  after update of owner_id on public.teams
  for each row execute function public.notify_team_owner();
