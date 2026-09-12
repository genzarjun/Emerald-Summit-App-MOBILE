-- Emerald Summit — attendance: session rosters + front-desk check-in
-- Run AFTER session_volunteers_setup.sql.
--
-- Two INDEPENDENT systems:
--   1. Session attendance — a volunteer ASSIGNED to a session marks each
--      registered participant present/absent (per-registration).
--   2. Front-desk check-in — a volunteer with can_check_in_front_desk marks ANY
--      attendee as physically arrived at the summit (summit-wide).

-- ============================================================================
-- 1. Session attendance
-- ============================================================================
alter table public.registrations
  add column if not exists attended    boolean not null default false,
  add column if not exists attended_at timestamptz,
  add column if not exists marked_by   uuid references auth.users (id) on delete set null;

-- RPC: the roster for a session (registered participants + attendance state).
-- Regular RLS scopes registrations to their owner, so an assigned volunteer
-- couldn't otherwise read other people's rows; this SECURITY DEFINER function
-- exposes exactly the roster, gated to the assigned volunteer or an admin.
create or replace function public.fetch_session_roster(p_session_id uuid)
returns table (user_id uuid, full_name text, email text,
               attended boolean, attended_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not (public.is_assigned_to_session(p_session_id) or public.is_admin()) then
    raise exception 'Not authorized for this session roster';
  end if;
  return query
    select p.id, p.full_name, p.email, r.attended, r.attended_at
      from public.registrations r
      join public.profiles p on p.id = r.user_id
     where r.session_id = p_session_id
     order by p.full_name;
end;
$$;

grant execute on function public.fetch_session_roster(uuid) to authenticated;

-- RPC: mark one participant present/absent for a session.
create or replace function public.mark_session_attendance(
  p_session_id uuid, p_user_id uuid, p_attended boolean)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if not (public.is_assigned_to_session(p_session_id) or public.is_admin()) then
    raise exception 'Not authorized to mark this session';
  end if;
  update public.registrations
     set attended    = p_attended,
         attended_at = case when p_attended then now() else null end,
         marked_by   = auth.uid()
   where session_id = p_session_id and user_id = p_user_id;
end;
$$;

grant execute on function public.mark_session_attendance(uuid, uuid, boolean) to authenticated;

-- ============================================================================
-- 2. Front-desk (summit-wide) check-in
-- ============================================================================
create table if not exists public.summit_checkins (
  attendee_id   uuid primary key references auth.users (id) on delete cascade,
  present       boolean not null default false,
  checked_in_at timestamptz,
  marked_by     uuid references auth.users (id) on delete set null
);

alter table public.summit_checkins enable row level security;
-- No direct policies: all access is through the two SECURITY DEFINER RPCs below,
-- which enforce the front-desk capability. (RLS on with no policy = deny direct
-- access, which is what we want.) The table owner (definer) still reads/writes.
grant select, insert, update on public.summit_checkins to authenticated;

-- RPC: the attendee directory (everyone with an account) + present flag.
-- Gated to front-desk volunteers / admins. Optional case-insensitive filter on
-- name or email.
create or replace function public.fetch_attendee_directory(p_query text default '')
returns table (id uuid, full_name text, email text, role text, present boolean)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.can_check_in_front_desk() then
    raise exception 'Not authorized for front-desk check-in';
  end if;
  return query
    select p.id, p.full_name, p.email, p.role,
           coalesce(c.present, false)
      from public.profiles p
      left join public.summit_checkins c on c.attendee_id = p.id
     where coalesce(btrim(p_query), '') = ''
        or p.full_name ilike '%' || p_query || '%'
        or p.email     ilike '%' || p_query || '%'
     order by p.full_name;
end;
$$;

grant execute on function public.fetch_attendee_directory(text) to authenticated;

-- RPC: mark an attendee arrived / not arrived.
create or replace function public.mark_summit_checkin(
  p_attendee_id uuid, p_present boolean)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.can_check_in_front_desk() then
    raise exception 'Not authorized for front-desk check-in';
  end if;
  insert into public.summit_checkins (attendee_id, present, checked_in_at, marked_by)
    values (p_attendee_id, p_present,
            case when p_present then now() else null end, auth.uid())
  on conflict (attendee_id) do update
    set present       = excluded.present,
        checked_in_at = excluded.checked_in_at,
        marked_by     = excluded.marked_by;
end;
$$;

grant execute on function public.mark_summit_checkin(uuid, boolean) to authenticated;
