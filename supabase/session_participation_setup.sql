-- Emerald Summit — session participation model: how each person joins a session
-- Run in the Supabase dashboard AFTER registrations_setup.sql,
-- session_volunteers_setup.sql, and attendance_setup.sql. Safe to re-run.
--
-- Adds a *participation type* to each registration and *per-session questions*:
--   * registrations.participation_type — 'participant' | 'spectator' | 'expert'.
--     Everyone who adds a session to their day is a registration; the type is HOW
--     they joined. "Managing" is separate (session_volunteers).
--   * registrations.answers — a participant's answers to the session's questions,
--     keyed by question id (e.g. {"q_123":"Solar Rover"}).
--   * sessions.participant_questions — ordered [{id, prompt}] the session's
--     admins/managers author (e.g. "What is your project name?").
-- Per the product decision, ALL registrations (participant/spectator/expert)
-- count toward capacity, so the capacity rule is unchanged.

-- 1. New columns -------------------------------------------------------------
alter table public.registrations
  add column if not exists participation_type text not null default 'participant',
  add column if not exists answers jsonb not null default '{}'::jsonb;

-- Constrain the type to the known set (drop-then-add so re-runs stay clean).
alter table public.registrations
  drop constraint if exists registrations_participation_type_check;
alter table public.registrations
  add constraint registrations_participation_type_check
  check (participation_type in ('participant', 'spectator', 'expert'));

alter table public.sessions
  add column if not exists participant_questions jsonb not null default '[]'::jsonb;

-- Rebuild sessions_with_counts so it actually exposes the session-page columns.
-- IMPORTANT: a view created with `select s.*` freezes its column list at
-- creation time — columns ADDED to `sessions` afterwards (hero_image_url,
-- page_blocks, participant_questions) do NOT appear in the view, so the app read
-- them back as null (hero fell back to the first gallery photo; content sections
-- and questions never reappeared after saving). Re-expanding s.* inserts the new
-- columns mid-list, which CREATE OR REPLACE VIEW forbids, so drop and recreate.
-- security_invoker = false is required (see registrations_setup.sql) so the
-- enrolled count sees every registration, not just the caller's.
drop view if exists public.sessions_with_counts;
create view public.sessions_with_counts
  with (security_invoker = false) as
  select
    s.*,
    d.name as discipline_name,
    (select count(*) from public.registrations r where r.session_id = s.id)
      as enrolled
  from public.sessions s
  join public.disciplines d on d.id = s.discipline_id;

grant select on public.sessions_with_counts to anon, authenticated;

-- 2. register_for_session — now records participation type + answers ----------
-- Supersedes the version in registrations_setup.sql. The new params are
-- defaulted so any older caller (participant, no answers) keeps working. Same
-- toggle / capacity / no-overlap rules as before.
create or replace function public.register_for_session(
  p_session_id uuid,
  p_participation_type text default 'participant',
  p_answers jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_sess   public.sessions%rowtype;
  v_count  int;
  v_clash  text;
  v_type   text := coalesce(p_participation_type, 'participant');
begin
  if v_uid is null then
    raise exception 'Not authenticated';
  end if;

  -- Guard the type against the allowed set (defensive; the CHECK also enforces).
  if v_type not in ('participant', 'spectator', 'expert') then
    v_type := 'participant';
  end if;

  -- Already registered → toggle OFF.
  if exists (select 1 from public.registrations
             where user_id = v_uid and session_id = p_session_id) then
    delete from public.registrations
      where user_id = v_uid and session_id = p_session_id;
    return jsonb_build_object('outcome', 'removed');
  end if;

  select * into v_sess from public.sessions where id = p_session_id;
  if not found then
    raise exception 'Session not found';
  end if;

  -- Capacity cap (all registration types count).
  select count(*) into v_count
    from public.registrations where session_id = p_session_id;
  if v_count >= v_sess.capacity then
    return jsonb_build_object('outcome', 'full');
  end if;

  -- No double-booking: reject if it overlaps a session already in the plan.
  select s.title into v_clash
    from public.registrations r
    join public.sessions s on s.id = r.session_id
   where r.user_id = v_uid
     and v_sess.start_time::time < s.end_time::time
     and s.start_time::time     < v_sess.end_time::time
   limit 1;
  if v_clash is not null then
    return jsonb_build_object('outcome', 'conflict',
                              'conflicting_title', v_clash);
  end if;

  insert into public.registrations
    (user_id, session_id, participation_type, answers)
    values (v_uid, p_session_id, v_type, coalesce(p_answers, '{}'::jsonb));
  return jsonb_build_object('outcome', 'added');
end;
$$;

grant execute on function
  public.register_for_session(uuid, text, jsonb) to authenticated;

-- 3. fetch_session_roster — now returns participation type + answers ----------
-- Supersedes the version in attendance_setup.sql. Same authorization gate
-- (assigned volunteer or admin); adds the two columns the Participants/Experts
-- tabs show. The return type gains columns, so Postgres won't let us CREATE OR
-- REPLACE over the old signature — drop it first.
drop function if exists public.fetch_session_roster(uuid);

create or replace function public.fetch_session_roster(p_session_id uuid)
returns table (user_id uuid, full_name text, email text,
               attended boolean, attended_at timestamptz,
               participation_type text, answers jsonb)
language plpgsql stable security definer set search_path = public as $$
begin
  if not (public.is_assigned_to_session(p_session_id) or public.is_admin()) then
    raise exception 'Not authorized for this session roster';
  end if;
  return query
    select p.id, p.full_name, p.email, r.attended, r.attended_at,
           r.participation_type, r.answers
      from public.registrations r
      join public.profiles p on p.id = r.user_id
     where r.session_id = p_session_id
     order by p.full_name;
end;
$$;

grant execute on function public.fetch_session_roster(uuid) to authenticated;

-- 4. set_session_manage — admin self-manage (add/remove) ---------------------
-- Lets an admin put themselves on a session as a MANAGER (session_volunteers),
-- and toggle it back off. Overlap-guarded like assign_volunteer_to_session, but
-- self-scoped and admin-only. No notification (self-initiated).
--   returns { "outcome": "managing" | "unmanaged" | "conflict",
--             "conflicting_title": <text|null> }
create or replace function public.set_session_manage(
  p_session_id uuid, p_manage boolean)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid   uuid := auth.uid();
  v_sess  public.sessions%rowtype;
  v_clash text;
begin
  if not public.is_admin() then
    raise exception 'Only admins may self-manage a session';
  end if;

  -- Remove.
  if not coalesce(p_manage, false) then
    delete from public.session_volunteers
      where session_id = p_session_id and user_id = v_uid;
    return jsonb_build_object('outcome', 'unmanaged');
  end if;

  -- Idempotent add.
  if exists (select 1 from public.session_volunteers
             where session_id = p_session_id and user_id = v_uid) then
    return jsonb_build_object('outcome', 'managing');
  end if;

  select * into v_sess from public.sessions where id = p_session_id;
  if not found then
    raise exception 'Session not found';
  end if;

  -- Overlap vs the admin's other managed sessions, then their registrations
  -- (excluding this session).
  select s.title into v_clash
    from public.session_volunteers sv
    join public.sessions s on s.id = sv.session_id
   where sv.user_id = v_uid
     and s.id <> p_session_id
     and v_sess.start_time::time < s.end_time::time
     and s.start_time::time     < v_sess.end_time::time
   limit 1;

  if v_clash is null then
    select s.title into v_clash
      from public.registrations r
      join public.sessions s on s.id = r.session_id
     where r.user_id = v_uid
       and s.id <> p_session_id
       and v_sess.start_time::time < s.end_time::time
       and s.start_time::time     < v_sess.end_time::time
     limit 1;
  end if;

  if v_clash is not null then
    return jsonb_build_object('outcome', 'conflict',
                              'conflicting_title', v_clash);
  end if;

  insert into public.session_volunteers (session_id, user_id, assigned_by)
    values (p_session_id, v_uid, v_uid);
  return jsonb_build_object('outcome', 'managing');
end;
$$;

grant execute on function public.set_session_manage(uuid, boolean) to authenticated;

-- 5. Time-change conflict detection ------------------------------------------
-- When a session's time is edited, some people registered for it may now clash
-- with another session they're registered for. This helper returns, for a
-- candidate [p_start, p_end) on session A, each registrant of A who is ALSO
-- registered for a DIFFERENT session overlapping that window — with the clashing
-- session's title (the earliest one, one row per person). Gated to admins and
-- the session's discipline editors (the people who can edit its time).
create or replace function public.session_time_conflicts(
  p_session_id uuid, p_start text, p_end text)
returns table (user_id uuid, full_name text, other_title text)
language sql stable security definer set search_path = public as $$
  select distinct on (r.user_id) r.user_id, p.full_name, s2.title
    from public.registrations r
    join public.profiles p on p.id = r.user_id
    join public.registrations r2
      on r2.user_id = r.user_id and r2.session_id <> p_session_id
    join public.sessions s2 on s2.id = r2.session_id
   where r.session_id = p_session_id
     and (public.is_admin() or public.can_manage_discipline(
           (select discipline_id from public.sessions where id = p_session_id)))
     and p_start::time < s2.end_time::time
     and s2.start_time::time < p_end::time
   order by r.user_id, s2.start_time;
$$;

grant execute on function
  public.session_time_conflicts(uuid, text, text) to authenticated;

-- 6. Notify people a time change created a clash for -------------------------
-- Computes the conflicts for the session's CURRENT (just-saved) time and drops a
-- personal announcement (+ in-app banner, via the existing target_user_id path)
-- into each affected person's feed. Returns how many were notified. Admin/editor
-- gated. The editor calls this right after saving a time change.
create or replace function public.notify_session_time_conflicts(p_session_id uuid)
returns int
language plpgsql security definer set search_path = public as $$
declare
  v_sess  public.sessions%rowtype;
  r       record;
  v_count int := 0;
begin
  select * into v_sess from public.sessions where id = p_session_id;
  if not found then
    raise exception 'Session not found';
  end if;
  if not (public.is_admin()
          or public.can_manage_discipline(v_sess.discipline_id)) then
    raise exception 'Not authorized';
  end if;

  for r in
    select * from public.session_time_conflicts(
      p_session_id, v_sess.start_time::text, v_sess.end_time::text)
  loop
    insert into public.announcements
      (title, body, author, audience, pinned, discipline_id, created_by,
       target_user_id)
    values (
      'Schedule change',
      format('An admin/volunteer changed the session timing of "%s", and now '
             || 'that overlaps with "%s" session. Please adjust your schedule '
             || 'accordingly.', v_sess.title, r.other_title),
      'Summit Admin', 'Personal', false,
      v_sess.discipline_id, auth.uid(), r.user_id);
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

grant execute on function
  public.notify_session_time_conflicts(uuid) to authenticated;
