-- Emerald Summit — managing a session replaces whatever it clashes with
-- Run AFTER registrations_manage_overlap.sql, teams_ownership_setup.sql,
-- team_leave_notices.sql and unassign_notification.sql. Safe to re-run.
-- Additive only: no existing function changes, so app builds keep working.
--
-- A person does one thing at a time at the summit. assign_volunteer_to_session
-- and set_session_manage refuse anyone already busy at that time, and they
-- still do (the app uses them). These two admin-only RPCs let an admin assign
-- the person anyway, and the managed session WINS:
--
--  1. preview_manager_assignment(p_session_id, p_user_id) → jsonb
--     What assigning would take off their day, so the admin sees it first:
--       { "already_managing": bool,
--         "replaces": [ { "session_id", "title", "start_time", "end_time",
--                         "kind": "registered_this" | "registered" | "managing",
--                         "participation_type",          -- registrations only
--                         "team_name", "team_owner",     -- null when solo
--                         "teammates" } ] }              -- others on the team
--     'registered_this' = signed up for THIS session: they'll manage it
--     instead of taking part. 'registered' / 'managing' = another session at
--     the same time, which is dropped.
--
--  2. assign_manager_replacing_conflicts(p_session_id, p_user_id) → jsonb
--     In one transaction:
--       a. deletes their registration for this session and every registration
--          that overlaps it. The registration triggers do the team work: an
--          emptied team is deleted, an owner's team passes to the earliest-
--          joined teammate ("You're now the owner"), and teammates get
--          "Teammate removed". Nothing goes into session_removals, so they
--          can sign up for those sessions again later.
--       b. removes them as manager of every overlapping session. Its old
--          "You're managing …" notice stays in their feed and bell, as a
--          dated record; the new notice says they've stopped.
--       c. adds them to session_volunteers (the usual co-organizer notices
--          fire).
--       d. sends them ONE personal notice that names what was replaced,
--          tagged with session_id so unassigning removes it. An admin passing
--          their own id (self-manage) gets no notice.
--     Returns { "outcome": "assigned", "replaced": [ same items as above ] }.
--
-- Summit-day volunteer hours follow session_volunteers, so they follow the
-- replacement too; nothing double-counts.

-- What the person is doing during p_session_id (this session's sign-up, plus
-- anything overlapping). Internal; both RPCs below use it.
create or replace function public.manager_assignment_conflicts(
  p_session_id uuid, p_user_id uuid)
returns jsonb
language sql stable security definer set search_path = public as $$
  with target as (
    select * from public.sessions where id = p_session_id
  ), items as (
    select s.id as session_id, s.title, s.start_time, s.end_time,
           case when s.id = p_session_id then 'registered_this' else 'registered' end as kind,
           r.participation_type, t.project_name as team_name,
           (t.id is not null and t.owner_id = p_user_id) as team_owner,
           (select count(*) from public.registrations o
             where t.id is not null and o.team_id = t.id
               and o.user_id <> p_user_id)::int as teammates,
           case when s.id = p_session_id then 0 else 1 end as ord
      from public.registrations r
      join public.sessions s on s.id = r.session_id
      left join public.teams t on t.id = r.team_id
      cross join target v
     where r.user_id = p_user_id
       and (s.id = p_session_id
            or (v.start_time::time < s.end_time::time
                and s.start_time::time < v.end_time::time))
    union all
    select s.id, s.title, s.start_time, s.end_time, 'managing',
           null, null, null, null, 2
      from public.session_volunteers sv
      join public.sessions s on s.id = sv.session_id
      cross join target v
     where sv.user_id = p_user_id and s.id <> p_session_id
       and v.start_time::time < s.end_time::time
       and s.start_time::time < v.end_time::time
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'session_id', session_id, 'title', title,
           'start_time', start_time, 'end_time', end_time, 'kind', kind,
           'participation_type', participation_type,
           'team_name', team_name, 'team_owner', team_owner,
           'teammates', teammates)
         order by ord, start_time, title), '[]'::jsonb)
    from items;
$$;

revoke execute on function public.manager_assignment_conflicts(uuid, uuid)
  from public, anon, authenticated;

-- 1. Preview -----------------------------------------------------------------
create or replace function public.preview_manager_assignment(
  p_session_id uuid, p_user_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then
    raise exception 'Only admins may assign volunteers';
  end if;
  if not exists (select 1 from public.sessions where id = p_session_id) then
    raise exception 'Session not found';
  end if;
  if exists (select 1 from public.session_volunteers
              where session_id = p_session_id and user_id = p_user_id) then
    return jsonb_build_object('already_managing', true, 'replaces', '[]'::jsonb);
  end if;
  return jsonb_build_object(
    'already_managing', false,
    'replaces', public.manager_assignment_conflicts(p_session_id, p_user_id));
end;
$$;

revoke execute on function public.preview_manager_assignment(uuid, uuid) from public, anon;
grant execute on function public.preview_manager_assignment(uuid, uuid) to authenticated;

-- 2. Assign, replacing clashes -----------------------------------------------
create or replace function public.assign_manager_replacing_conflicts(
  p_session_id uuid, p_user_id uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_sess     public.sessions%rowtype;
  v_disc     text;
  v_replaced jsonb;
  v_item     jsonb;
  v_lines    text[] := '{}';
  v_self     boolean := p_user_id = auth.uid();
begin
  if not public.is_admin() then
    raise exception 'Only admins may assign volunteers';
  end if;

  if exists (select 1 from public.session_volunteers
             where session_id = p_session_id and user_id = p_user_id) then
    return jsonb_build_object('outcome', 'assigned', 'replaced', '[]'::jsonb);
  end if;

  select * into v_sess from public.sessions where id = p_session_id;
  if not found then
    raise exception 'Session not found';
  end if;

  v_replaced := public.manager_assignment_conflicts(p_session_id, p_user_id);

  for v_item in select * from jsonb_array_elements(v_replaced) loop
    if v_item->>'kind' = 'managing' then
      -- Their old "You're managing …" notice for it stays (a dated record).
      delete from public.session_volunteers
       where session_id = (v_item->>'session_id')::uuid and user_id = p_user_id;
      v_lines := v_lines || format('"%s" (you were managing it)', v_item->>'title');
    else
      -- Triggers hand off or delete the team and tell teammates.
      delete from public.registrations
       where session_id = (v_item->>'session_id')::uuid and user_id = p_user_id;
      if v_item->>'kind' = 'registered_this' then
        v_lines := v_lines || format('your sign-up to %s in "%s" (you''ll run it instead)',
          case v_item->>'participation_type'
            when 'expert' then 'serve as an expert'
            when 'spectator' then 'spectate'
            else 'participate' end,
          v_item->>'title');
      else
        v_lines := v_lines || format('"%s" (you were signed up to %s)',
          v_item->>'title',
          case v_item->>'participation_type'
            when 'expert' then 'serve as an expert'
            when 'spectator' then 'spectate'
            else 'participate' end);
      end if;
    end if;
  end loop;

  insert into public.session_volunteers (session_id, user_id, assigned_by)
    values (p_session_id, p_user_id, auth.uid());

  if not v_self then
    select name into v_disc from public.disciplines where id = v_sess.discipline_id;
    insert into public.announcements
      (title, body, author, audience, pinned, discipline_id, created_by,
       target_user_id, session_id)
    values (
      'You''re managing a session',
      format('You have been assigned to manage "%s" in %s.',
             v_sess.title, coalesce(v_disc, 'the summit'))
        || case when cardinality(v_lines) > 0
             then ' You can only do one thing at a time, so an admin took this off '
                  || 'your day: ' || array_to_string(v_lines, '; ') || '.'
             else '' end,
      'Summit Admin', 'Personal', false,
      v_sess.discipline_id, auth.uid(), p_user_id, p_session_id);
  end if;

  return jsonb_build_object('outcome', 'assigned', 'replaced', v_replaced);
end;
$$;

revoke execute on function public.assign_manager_replacing_conflicts(uuid, uuid) from public, anon;
grant execute on function public.assign_manager_replacing_conflicts(uuid, uuid) to authenticated;
