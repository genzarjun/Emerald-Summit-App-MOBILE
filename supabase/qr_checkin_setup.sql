-- Emerald Summit — QR front-desk check-in
-- Run AFTER attendance_setup.sql (reuses summit_checkins + can_check_in_front_desk).
-- Safe to re-run.
--
-- Every attendee's Profile tab shows a QR code that encodes their user id (the
-- same payload the website's QR pass uses). A front-desk volunteer scans it and
-- the app calls scan_summit_checkin, which checks the attendee in atomically.
-- Undo reuses mark_summit_checkin(id, false) from attendance_setup.sql.

-- Only ONBOARDED accounts count as attendees. A profiles row is created the
-- moment someone REQUESTS a sign-in code (handle_new_user on auth.users), so
-- typo'd or never-verified emails leave blank onboarded = false rows behind;
-- those never appear in the front-desk directory and can't be checked in.

-- RPC: the attendee directory (replaces attendance_setup.sql's version, which
-- listed every profiles row). Same signature and gate.
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
     where p.onboarded
       and (coalesce(btrim(p_query), '') = ''
            or p.full_name ilike '%' || p_query || '%'
            or p.email     ilike '%' || p_query || '%')
     order by p.full_name;
end;
$$;

grant execute on function public.fetch_attendee_directory(text) to authenticated;

-- RPC: scan an attendee's pass. Gated to front-desk volunteers / admins.
-- Returns one row describing the outcome:
--   attendee_found = false      → no onboarded account with that id
--   already_checked_in = true   → they were already present; checked_in_at is
--                                 the ORIGINAL arrival time (not overwritten)
--   otherwise                   → checked in now
create or replace function public.scan_summit_checkin(p_attendee_id uuid)
returns table (attendee_found boolean, already_checked_in boolean, full_name text,
               email text, role text, checked_in_at timestamptz)
language plpgsql security definer set search_path = public as $$
declare
  v_profile public.profiles%rowtype;
  v_prior   public.summit_checkins%rowtype;
  v_at      timestamptz;
begin
  if not public.can_check_in_front_desk() then
    raise exception 'Not authorized for front-desk check-in';
  end if;

  select * into v_profile from public.profiles
   where id = p_attendee_id and onboarded;
  if not found then
    return query select false, false, null::text, null::text, null::text,
                        null::timestamptz;
    return;
  end if;

  -- Lock the row so two desks scanning the same pass can't both "check in".
  select * into v_prior from public.summit_checkins
   where attendee_id = p_attendee_id for update;
  if found and v_prior.present then
    return query select true, true, v_profile.full_name, v_profile.email,
                        v_profile.role::text, v_prior.checked_in_at;
    return;
  end if;

  insert into public.summit_checkins (attendee_id, present, checked_in_at, marked_by)
    values (p_attendee_id, true, now(), auth.uid())
  on conflict (attendee_id) do update
    set present       = true,
        checked_in_at = excluded.checked_in_at,
        marked_by     = excluded.marked_by
  returning summit_checkins.checked_in_at into v_at;

  return query select true, false, v_profile.full_name, v_profile.email,
                      v_profile.role::text, v_at;
end;
$$;

grant execute on function public.scan_summit_checkin(uuid) to authenticated;

-- RPC: the signed-in user's own front-desk status, for the QR pass on their
-- Profile tab. summit_checkins has no direct-read policy, so this exposes
-- exactly the caller's own row and nothing else.
create or replace function public.my_summit_checkin()
returns table (present boolean, checked_in_at timestamptz)
language sql stable security definer set search_path = public as $$
  select coalesce(c.present, false), c.checked_in_at
    from (select auth.uid() as uid) me
    left join public.summit_checkins c on c.attendee_id = me.uid
   where me.uid is not null;
$$;

grant execute on function public.my_summit_checkin() to authenticated;

-- RPC: live front-desk stats — onboarded accounts per role and how many of
-- each are checked in. The app sums these into Everyone / Participants /
-- Volunteers tiles. Gated like the directory.
create or replace function public.fetch_checkin_stats()
returns table (role text, total bigint, checked_in bigint)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.can_check_in_front_desk() then
    raise exception 'Not authorized for front-desk check-in';
  end if;
  return query
    select p.role::text, count(*),
           count(*) filter (where coalesce(c.present, false))
      from public.profiles p
      left join public.summit_checkins c on c.attendee_id = p.id
     where p.onboarded
     group by p.role;
end;
$$;

grant execute on function public.fetch_checkin_stats() to authenticated;

-- Realtime: front-desk screens refresh their stats + list whenever any desk
-- checks someone in or out. postgres_changes only delivers rows the subscriber
-- can SELECT, so front-desk volunteers / admins get a read policy (they can
-- already see every row through fetch_attendee_directory). Writes still go
-- only through the SECURITY DEFINER RPCs.
drop policy if exists "summit_checkins_front_desk_read" on public.summit_checkins;
create policy "summit_checkins_front_desk_read"
  on public.summit_checkins for select to authenticated
  using (public.can_check_in_front_desk());

do $$
begin
  alter publication supabase_realtime add table public.summit_checkins;
exception
  when duplicate_object then null;
end $$;
