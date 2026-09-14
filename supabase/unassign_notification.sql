-- Emerald Summit — assignment/unassignment notifications (feed + banner)
-- Run AFTER assignment_notifications.sql.
--
-- Adds a session link to announcements so an assignment's "You're managing …"
-- notice can be found and cleaned up when the admin later removes the volunteer.
-- On unassign, the RPC: (1) deletes the session_volunteers row, (2) deletes that
-- stale "managing" announcement from the volunteer's feed, and (3) posts a
-- "you're no longer managing …" notice (which the app also shows as a banner).

-- 1. Link announcements to a session (nullable; most announcements have none) --
alter table public.announcements
  add column if not exists session_id uuid references public.sessions (id) on delete set null;

-- 2. assign RPC — same as before, but tag the notification with session_id ------
create or replace function public.assign_volunteer_to_session(
  p_session_id uuid, p_user_id uuid, p_confirm_registered boolean default false)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_sess  public.sessions%rowtype;
  v_clash text;
  v_disc  text;
begin
  if not public.is_admin() then
    raise exception 'Only admins may assign volunteers';
  end if;

  if exists (select 1 from public.session_volunteers
             where session_id = p_session_id and user_id = p_user_id) then
    return jsonb_build_object('outcome', 'assigned');
  end if;

  select * into v_sess from public.sessions where id = p_session_id;
  if not found then
    raise exception 'Session not found';
  end if;

  select s.title into v_clash
    from public.session_volunteers sv
    join public.sessions s on s.id = sv.session_id
   where sv.user_id = p_user_id and s.id <> p_session_id
     and v_sess.start_time::time < s.end_time::time
     and s.start_time::time     < v_sess.end_time::time
   limit 1;
  if v_clash is null then
    select s.title into v_clash
      from public.registrations r
      join public.sessions s on s.id = r.session_id
     where r.user_id = p_user_id and s.id <> p_session_id
       and v_sess.start_time::time < s.end_time::time
       and s.start_time::time     < v_sess.end_time::time
     limit 1;
  end if;
  if v_clash is not null then
    return jsonb_build_object('outcome', 'conflict', 'conflicting_title', v_clash);
  end if;

  if not p_confirm_registered
     and exists (select 1 from public.registrations
                 where user_id = p_user_id and session_id = p_session_id) then
    return jsonb_build_object('outcome', 'registered_confirm');
  end if;

  insert into public.session_volunteers (session_id, user_id, assigned_by)
    values (p_session_id, p_user_id, auth.uid());

  select name into v_disc from public.disciplines where id = v_sess.discipline_id;
  insert into public.announcements
    (title, body, author, audience, pinned, discipline_id, created_by,
     target_user_id, session_id)
  values (
    'You''re managing a session',
    format('You have been assigned to manage "%s" in %s.',
           v_sess.title, coalesce(v_disc, 'the summit')),
    'Summit Admin', 'Personal', false,
    v_sess.discipline_id, auth.uid(), p_user_id, p_session_id);

  return jsonb_build_object('outcome', 'assigned');
end;
$$;

grant execute on function public.assign_volunteer_to_session(uuid, uuid, boolean) to authenticated;

-- 3. unassign RPC — delete assignment + stale notice, post removal notice ------
create or replace function public.unassign_volunteer_from_session(
  p_session_id uuid, p_user_id uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_sess    public.sessions%rowtype;
  v_disc    text;
  v_removed int;
begin
  if not public.is_admin() then
    raise exception 'Only admins may unassign volunteers';
  end if;

  delete from public.session_volunteers
    where session_id = p_session_id and user_id = p_user_id;
  get diagnostics v_removed = row_count;
  if v_removed = 0 then
    return;  -- wasn't assigned; nothing to notify/clean up
  end if;

  select * into v_sess from public.sessions where id = p_session_id;
  select name into v_disc from public.disciplines where id = v_sess.discipline_id;

  -- Remove the stale "You're managing …" notice for this volunteer + session.
  -- Matches the session_id tag (new notices) and, as a fallback, older untagged
  -- ones by their title/body so pre-existing notices are cleaned up too.
  delete from public.announcements
   where target_user_id = p_user_id
     and (session_id = p_session_id
          or (session_id is null
              and title = 'You''re managing a session'
              and body like '%"' || coalesce(v_sess.title, '') || '"%'));

  insert into public.announcements
    (title, body, author, audience, pinned, discipline_id, created_by, target_user_id)
  values (
    'Session assignment removed',
    format('You''re no longer managing "%s" in %s.',
           coalesce(v_sess.title, 'a session'), coalesce(v_disc, 'the summit')),
    'Summit Admin', 'Personal', false,
    v_sess.discipline_id, auth.uid(), p_user_id);
end;
$$;

grant execute on function public.unassign_volunteer_from_session(uuid, uuid) to authenticated;
