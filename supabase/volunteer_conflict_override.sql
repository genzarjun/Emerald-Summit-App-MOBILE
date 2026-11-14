-- Emerald Summit — admins can assign a volunteer despite a schedule clash
-- Run AFTER registrations_manage_overlap.sql and session_organizer_notices.sql.
-- Safe to re-run. Additive only: nothing the app reads changes.
--
-- assign_volunteer_to_session and set_session_manage refuse anyone who already
-- manages or is signed up for a session at the same time. That stays the
-- default. This file lets an admin knowingly override it:
--
--  1. session_volunteers.conflict_override (boolean, default false). True on
--     an assignment an admin made over a time clash, so the website can mark
--     it. Admins read it straight from the table (RLS already lets them); a
--     volunteer can read it on their own rows.
--  2. assign_volunteer_overriding_conflict(p_session_id, p_user_id), admin
--     only. Same as assign_volunteer_to_session, but an overlap with another
--     session the person manages or is signed up for doesn't stop it. It
--     still refuses someone signed up for THIS session ('conflict' with
--     conflict_kind 'registered_this'): a manager runs a session, they don't
--     also take part in it, so they remove it from their day first.
--     An admin can pass their own id to manage a session over a clash (the
--     override for set_session_manage); they get no "You're managing" notice.
--     Returns {outcome: 'assigned', conflicting_title: <title or null>}.
--
-- The old RPCs are unchanged, so app builds keep refusing clashes as before.
-- The app has no override button yet (see the README's website to-do list).
-- Note: summit-day hours are counted per managed session, so an overridden
-- assignment counts both overlapping sessions in full.

-- 1. Column ------------------------------------------------------------------
alter table public.session_volunteers
  add column if not exists conflict_override boolean not null default false;

-- 2. Override RPC ------------------------------------------------------------
create or replace function public.assign_volunteer_overriding_conflict(
  p_session_id uuid, p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_sess  public.sessions%rowtype;
  v_clash text;
  v_disc  text;
  v_self  boolean := p_user_id = auth.uid();
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

  -- Signed up for this very session: still refused, override or not.
  if exists (select 1 from public.registrations
              where user_id = p_user_id and session_id = p_session_id) then
    return jsonb_build_object('outcome', 'conflict',
                              'conflicting_title', v_sess.title,
                              'conflict_kind', 'registered_this');
  end if;

  -- Find the clash being overridden (managed sessions first, then sign-ups),
  -- only to record it and name it in the notice.
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

  insert into public.session_volunteers
    (session_id, user_id, assigned_by, conflict_override)
    values (p_session_id, p_user_id, auth.uid(), v_clash is not null);

  if not v_self then
    select name into v_disc from public.disciplines where id = v_sess.discipline_id;
    insert into public.announcements
      (title, body, author, audience, pinned, discipline_id, created_by,
       target_user_id, session_id)
    values (
      'You''re managing a session',
      format('You have been assigned to manage "%s" in %s.',
             v_sess.title, coalesce(v_disc, 'the summit'))
        || case when v_clash is not null
             then format(' It overlaps with "%s", which is also on your schedule. '
                         'An admin approved the overlap.', v_clash)
             else '' end,
      'Summit Admin', 'Personal', false,
      v_sess.discipline_id, auth.uid(), p_user_id, p_session_id);
  end if;

  return jsonb_build_object('outcome', 'assigned',
                            'conflicting_title', v_clash);
end;
$function$;

revoke execute on function public.assign_volunteer_overriding_conflict(uuid, uuid)
  from public, anon;
grant execute on function public.assign_volunteer_overriding_conflict(uuid, uuid)
  to authenticated;
