-- Emerald Summit — session co-workers + organizer notices
-- Run in the Supabase dashboard AFTER volunteer_hub.sql. Safe to re-run.
--
-- A session's ORGANIZERS are the people in session_volunteers for it: the
-- volunteers an admin assigned, plus any admin who self-managed it. Its
-- EDITORS are anyone who can_manage_discipline() its discipline — a
-- discipline-wide scope, not a per-session one.
--
--  1. fetch_session_volunteers is no longer admin-only. A session's organizers
--     and editors can read it too, so the session page's Volunteers tab shows
--     them who they're working with, with each person's role and mobile number
--     (the same number the volunteer hub already shares with every volunteer
--     and admin). Email stays admin-only.
--  2. When someone signs up for a session as an EXPERT, each of its organizers
--     gets a personal "New expert" notice (feed + in-app banner).
--  3. When someone is added as an organizer (an admin assigning a volunteer,
--     or an admin self-managing), each of the session's OTHER organizers gets a
--     personal notice naming their new co-worker. The admin who did it is
--     skipped.
-- Editors who aren't organizers get neither notice. Both notices leave
-- announcements.session_id null: that column tags the assignee's own
-- "You're managing …" notice, which unassigning deletes by session.

-- 1. Organizers + editors can see a session's volunteers ---------------------
-- The return type changed (role + phone added), so drop the first version.
drop function if exists public.fetch_session_volunteers(uuid);

create or replace function public.fetch_session_volunteers(p_session_id uuid)
returns table (user_id uuid, full_name text, email text, subtype text,
               role text, phone text)
language plpgsql stable security definer set search_path = public as $$
declare
  v_admin boolean := public.is_admin();
begin
  -- Qualify every column: the OUT params (user_id, role, …) share their names,
  -- and an unqualified reference is ambiguous in PL/pgSQL.
  if not (
    v_admin
    or exists (select 1 from public.session_volunteers me
                where me.session_id = p_session_id
                  and me.user_id = auth.uid())
    or exists (select 1 from public.sessions s
                where s.id = p_session_id
                  and public.can_manage_discipline(s.discipline_id))
  ) then
    raise exception 'Only admins, this session''s organizers and its editors '
                    'may view its volunteers';
  end if;
  return query
    select p.id, p.full_name,
           case when v_admin then p.email end,
           p.volunteer_subtype, p.role::text,
           nullif(trim(p.details->>'phone'), '')
      from public.session_volunteers sv
      join public.profiles p on p.id = sv.user_id
     where sv.session_id = p_session_id
     order by (p.role = 'admin') desc, p.full_name;
end;
$$;

revoke execute on function public.fetch_session_volunteers(uuid) from public, anon;
grant execute on function public.fetch_session_volunteers(uuid) to authenticated;

-- 2. "X signed up as an expert" → the session's organizers -------------------
create or replace function public.notify_organizers_of_expert()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_sess   public.sessions%rowtype;
  v_expert text;
begin
  if new.participation_type is distinct from 'expert'
     or (tg_op = 'UPDATE'
         and old.participation_type is not distinct from 'expert') then
    return null;
  end if;
  select * into v_sess from public.sessions where id = new.session_id;
  select coalesce(nullif(full_name, ''), 'Someone') into v_expert
    from public.profiles where id = new.user_id;

  insert into public.announcements
    (title, body, author, audience, pinned, discipline_id, created_by,
     target_user_id)
  select 'New expert',
         format('%s signed up as an expert for "%s".',
                coalesce(v_expert, 'Someone'), v_sess.title),
         'Emerald Summit', 'Personal', false, v_sess.discipline_id,
         new.user_id, sv.user_id
    from public.session_volunteers sv
   where sv.session_id = new.session_id
     and sv.user_id <> new.user_id;
  return null;
end;
$$;

drop trigger if exists registrations_notify_expert on public.registrations;
create trigger registrations_notify_expert
  after insert or update of participation_type on public.registrations
  for each row execute function public.notify_organizers_of_expert();

-- 3. "X is now helping you manage …" → the session's other organizers ---------
create or replace function public.notify_organizers_of_coworker()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_sess public.sessions%rowtype;
  v_new  text;
begin
  select * into v_sess from public.sessions where id = new.session_id;
  select coalesce(nullif(full_name, ''), 'A volunteer') into v_new
    from public.profiles where id = new.user_id;

  insert into public.announcements
    (title, body, author, audience, pinned, discipline_id, created_by,
     target_user_id)
  select 'New co-organizer',
         format('%s is now helping you manage "%s".',
                coalesce(v_new, 'A volunteer'), v_sess.title),
         'Summit Admin', 'Personal', false, v_sess.discipline_id,
         new.assigned_by, sv.user_id
    from public.session_volunteers sv
   where sv.session_id = new.session_id
     and sv.user_id <> new.user_id
     and sv.user_id is distinct from new.assigned_by;
  return null;
end;
$$;

drop trigger if exists session_volunteers_notify_coworkers
  on public.session_volunteers;
create trigger session_volunteers_notify_coworkers
  after insert on public.session_volunteers
  for each row execute function public.notify_organizers_of_coworker();
