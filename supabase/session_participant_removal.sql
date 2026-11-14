-- Emerald Summit — organizers remove someone from a session
-- Run in the Supabase dashboard AFTER roster_profile_details.sql and
-- team_leave_notices.sql. Safe to re-run.
--
-- Anyone who can see a session's roster (fetch_session_roster's gate: an admin,
-- a volunteer assigned to the session, or a session editor scoped to its
-- discipline) can take someone off it, e.g. an account that looks fake.
--
--   * remove_session_registration deletes their registration (participant,
--     spectator or expert) and records it in session_removals. The existing
--     registration triggers do the team work: an emptied team is deleted, a
--     removed owner's team passes to the earliest-joined member ("You're now
--     the owner"), and the other members get "X was removed from your team".
--   * The removed person gets a personal "Removed from a session" notice.
--   * They can't sign up for that session again: a trigger on registrations
--     refuses with the error 'removed_from_session'. Organizers can undo it
--     with allow_back_to_session, after which they may register again.
--   * fetch_session_removals lists who was removed, for the roster's
--     "Removed" section. The website shows the Remove buttons only once this
--     function exists, so it is safe to deploy the website first.

-- 1. Who was removed ------------------------------------------------------------
create table if not exists public.session_removals (
  session_id          uuid not null references public.sessions (id) on delete cascade,
  user_id             uuid not null references auth.users (id) on delete cascade,
  participation_type  text,
  removed_by          uuid references auth.users (id) on delete set null,
  removed_at          timestamptz not null default now(),
  primary key (session_id, user_id)
);

-- Read and written only through the functions below.
alter table public.session_removals enable row level security;
revoke all on public.session_removals from anon, authenticated;

-- Internal: fetch_session_roster's gate.
create or replace function public.can_see_session_roster(p_session_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select public.is_assigned_to_session(p_session_id)
      or public.is_admin()
      or public.can_manage_discipline(
           (select discipline_id from public.sessions where id = p_session_id));
$$;

grant execute on function public.can_see_session_roster(uuid) to authenticated;

-- 2. No signing back up ---------------------------------------------------------
-- On the registration row itself, so every sign-up path is covered without
-- redefining register_for_session.
create or replace function public.block_removed_registration()
returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if exists (select 1 from public.session_removals
              where session_id = new.session_id and user_id = new.user_id) then
    raise exception 'removed_from_session';
  end if;
  return new;
end;
$$;

drop trigger if exists registrations_block_removed on public.registrations;
create trigger registrations_block_removed
  before insert on public.registrations
  for each row execute function public.block_removed_registration();

-- 3. remove_session_registration ------------------------------------------------
--   returns { "outcome": "removed" | "not_registered" | "cannot_remove_self" }
create or replace function public.remove_session_registration(
  p_session_id uuid, p_user_id uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid  uuid := auth.uid();
  v_type text;
  v_sess public.sessions%rowtype;
begin
  if v_uid is null or not public.can_see_session_roster(p_session_id) then
    raise exception 'Not authorized for this session roster';
  end if;
  if p_user_id = v_uid then
    return jsonb_build_object('outcome', 'cannot_remove_self');
  end if;

  delete from public.registrations
   where session_id = p_session_id and user_id = p_user_id
  returning participation_type into v_type;
  if not found then
    return jsonb_build_object('outcome', 'not_registered');
  end if;

  insert into public.session_removals
    (session_id, user_id, participation_type, removed_by)
  values (p_session_id, p_user_id, v_type, v_uid)
  on conflict (session_id, user_id) do update
    set participation_type = excluded.participation_type,
        removed_by = excluded.removed_by,
        removed_at = now();

  select * into v_sess from public.sessions where id = p_session_id;
  insert into public.announcements
    (title, body, author, audience, pinned, discipline_id, created_by,
     target_user_id)
  values (
    'Removed from a session',
    format('An organizer removed you from "%s", so it''s no longer on your '
           || 'schedule. If you think this was a mistake, contact the summit '
           || 'team.', v_sess.title),
    'Emerald Summit', 'Personal', false, v_sess.discipline_id, v_uid,
    p_user_id);

  return jsonb_build_object('outcome', 'removed');
end;
$$;

grant execute on function public.remove_session_registration(uuid, uuid) to authenticated;

-- 4. allow_back_to_session ------------------------------------------------------
-- Lifts the block. Doesn't re-register them; they sign up again themselves.
create or replace function public.allow_back_to_session(
  p_session_id uuid, p_user_id uuid)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null or not public.can_see_session_roster(p_session_id) then
    raise exception 'Not authorized for this session roster';
  end if;
  delete from public.session_removals
   where session_id = p_session_id and user_id = p_user_id;
end;
$$;

grant execute on function public.allow_back_to_session(uuid, uuid) to authenticated;

-- 5. fetch_session_removals -----------------------------------------------------
create or replace function public.fetch_session_removals(p_session_id uuid)
returns table (user_id uuid, full_name text, email text,
               participation_type text, removed_by_name text,
               removed_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.can_see_session_roster(p_session_id) then
    raise exception 'Not authorized for this session roster';
  end if;
  return query
    select sr.user_id, p.full_name, p.email, sr.participation_type,
           coalesce(nullif(b.full_name, ''), b.email), sr.removed_at
      from public.session_removals sr
      left join public.profiles p on p.id = sr.user_id
      left join public.profiles b on b.id = sr.removed_by
     where sr.session_id = p_session_id
     order by sr.removed_at desc;
end;
$$;

grant execute on function public.fetch_session_removals(uuid) to authenticated;
