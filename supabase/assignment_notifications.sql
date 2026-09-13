-- Emerald Summit — assignment notifications + "already registered" confirm
-- Run AFTER session_volunteers_setup.sql and announcements_write_setup.sql.
--
-- Two additions:
--  1. Announcements can target a single user (target_user_id). When an admin
--     assigns a volunteer to a session, the assign RPC drops a PERSONAL
--     announcement into that volunteer's feed ("You have been assigned to
--     manage <session> in <discipline>"), which also fires their in-app banner.
--  2. If the volunteer is already REGISTERED for that session, the RPC returns
--     'registered_confirm' instead of assigning, so the admin UI can ask
--     "<name> is registered for this session. Assign them to manage it?" and
--     re-call with p_confirm_registered = true.

-- 1. Per-user targeting on announcements -------------------------------------
alter table public.announcements
  add column if not exists target_user_id uuid references auth.users (id) on delete cascade;

-- Read policy: broadcasts (target_user_id null) stay public; a targeted
-- announcement is visible only to its recipient. (anon has auth.uid() = null,
-- so anon sees only broadcasts.) Replaces the old "Public read access" policy.
drop policy if exists "Public read access" on public.announcements;
drop policy if exists "Read announcements" on public.announcements;
create policy "Read announcements"
  on public.announcements for select
  to anon, authenticated
  using (target_user_id is null or target_user_id = auth.uid());

-- 2. assign RPC: registered-confirm + assignment notification ----------------
-- Supersedes the version in session_volunteers_setup.sql. Drop the old 2-arg
-- signature so there's no overload ambiguity, then create the 3-arg version.
drop function if exists public.assign_volunteer_to_session(uuid, uuid);

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

  -- Idempotent: already assigned → success.
  if exists (select 1 from public.session_volunteers
             where session_id = p_session_id and user_id = p_user_id) then
    return jsonb_build_object('outcome', 'assigned');
  end if;

  select * into v_sess from public.sessions where id = p_session_id;
  if not found then
    raise exception 'Session not found';
  end if;

  -- Overlap vs the volunteer's OTHER assignments, then their own registrations
  -- (excluding this session — being registered for it is not a conflict).
  select s.title into v_clash
    from public.session_volunteers sv
    join public.sessions s on s.id = sv.session_id
   where sv.user_id = p_user_id
     and s.id <> p_session_id
     and v_sess.start_time::time < s.end_time::time
     and s.start_time::time     < v_sess.end_time::time
   limit 1;

  if v_clash is null then
    select s.title into v_clash
      from public.registrations r
      join public.sessions s on s.id = r.session_id
     where r.user_id = p_user_id
       and s.id <> p_session_id
       and v_sess.start_time::time < s.end_time::time
       and s.start_time::time     < v_sess.end_time::time
     limit 1;
  end if;

  if v_clash is not null then
    return jsonb_build_object('outcome', 'conflict',
                              'conflicting_title', v_clash);
  end if;

  -- Registered for THIS session → ask the admin to confirm (once).
  if not p_confirm_registered
     and exists (select 1 from public.registrations
                 where user_id = p_user_id and session_id = p_session_id) then
    return jsonb_build_object('outcome', 'registered_confirm');
  end if;

  insert into public.session_volunteers (session_id, user_id, assigned_by)
    values (p_session_id, p_user_id, auth.uid());

  -- Personal notification in the volunteer's announcements feed.
  select name into v_disc from public.disciplines where id = v_sess.discipline_id;
  insert into public.announcements
    (title, body, author, audience, pinned, discipline_id, created_by, target_user_id)
  values (
    'You''re managing a session',
    format('You have been assigned to manage "%s" in %s.',
           v_sess.title, coalesce(v_disc, 'the summit')),
    'Summit Admin', 'Personal', false,
    v_sess.discipline_id, auth.uid(), p_user_id);

  return jsonb_build_object('outcome', 'assigned');
end;
$$;

grant execute on function public.assign_volunteer_to_session(uuid, uuid, boolean) to authenticated;
