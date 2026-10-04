-- Emerald Summit — QR front-desk check-in
-- Run AFTER attendance_setup.sql (reuses summit_checkins + can_check_in_front_desk).
--
-- Every attendee's Profile tab shows a QR code that encodes their user id (the
-- same payload the website's QR pass uses). A front-desk volunteer scans it and
-- the app calls scan_summit_checkin, which checks the attendee in atomically.
-- Undo reuses mark_summit_checkin(id, false) from attendance_setup.sql.

-- RPC: scan an attendee's pass. Gated to front-desk volunteers / admins.
-- Returns one row describing the outcome:
--   attendee_found = false      → no account with that id (not a summit pass)
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

  select * into v_profile from public.profiles where id = p_attendee_id;
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
