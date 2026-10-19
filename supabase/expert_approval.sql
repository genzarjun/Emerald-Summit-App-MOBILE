-- Emerald Summit — expert accounts need an admin's approval
-- Run in the Supabase dashboard AFTER hours_sheet_sync.sql. Safe to re-run.
--
-- Anyone can pick the Expert role at sign-up, but the account stays
-- 'pending' until an admin approves it in the app (Profile → Expert
-- approvals). Until then the app only shows a "waiting for approval" screen.
--
--  1. profiles.expert_status: null (not an expert) | 'pending' | 'approved' |
--     'declined' (an admin said no; the account is now a participant and sees
--     a one-time note). profiles.expert_requested_at: when it went pending.
--  2. enforce_role_allowlist (the profiles BEFORE trigger) owns those two
--     columns. Picking Expert makes the account pending; only review_expert()
--     can approve it. Everything else in the trigger is unchanged from
--     role_allowlist_v2.sql.
--  3. Existing expert accounts become pending too, so every expert is
--     reviewed.
--  4. Admins are NOT sent a notice per sign-up; they check Expert approvals.
--  5. fetch_expert_requests() / review_expert() for the admin screen, and
--     acknowledge_expert_decline() for the declined person's note.
--  6. session_experts(): names of the approved experts registered for a
--     session, for the "Expert" line on the session page (replaces the old
--     free-text sessions.expert_name, which the app no longer shows or edits).
--  7. register_for_session refuses 'expert' sign-ups from anyone who isn't an
--     approved expert ('expert_not_approved'). Same signature; otherwise the
--     same as participant_deadline.sql.

-- 1. Columns -------------------------------------------------------------------
alter table public.profiles
  add column if not exists expert_status text
    check (expert_status in ('pending', 'approved', 'declined')),
  add column if not exists expert_requested_at timestamptz;

-- 2. Enforcement trigger -------------------------------------------------------
create or replace function public.enforce_role_allowlist()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_email text;
  v_allow public.role_allowlist%rowtype;
  v_is_ambassador boolean;
begin
  v_email := lower(coalesce(new.email,
                            (select email from auth.users where id = new.id)));

  -- Default: clear all volunteer state; specific branches re-populate it.
  new.managed_disciplines    := '{}';
  new.volunteer_subtype      := null;
  new.can_edit_sessions      := false;
  new.can_post_announcements := false;
  new.can_check_in_front_desk := false;

  if new.role in ('volunteer', 'admin') then
    select * into v_allow from public.role_allowlist
      where lower(email) = v_email and role = new.role;

    if not found then
      new.role := 'participant';
    elsif new.role = 'volunteer' then
      new.volunteer_subtype   := v_allow.subtype;
      new.managed_disciplines := coalesce(v_allow.disciplines, '{}');
      v_is_ambassador := (v_allow.subtype = 'eaf_ambassador');
      -- Subtype default: only ambassadors edit sessions; parents/students don't.
      -- Announcements + front-desk are opt-in per person (default false).
      new.can_edit_sessions       := coalesce(v_allow.can_edit_sessions, v_is_ambassador);
      new.can_post_announcements  := coalesce(v_allow.can_post_announcements, false);
      new.can_check_in_front_desk := coalesce(v_allow.can_check_in_front_desk, false);
    end if;
    -- admin: everything stays cleared (global; app grants implicitly).
  end if;

  -- Expert approval. Only review_expert() and acknowledge_expert_decline()
  -- change expert_status on purpose: they turn app.expert_review on for their
  -- own update. Any other write (sign-up, Edit profile, a crafted API call)
  -- keeps the status or resets it here, so nobody can approve themselves.
  if coalesce(current_setting('app.expert_review', true), '') <> 'on' then
    if new.role = 'expert' then
      if tg_op = 'UPDATE' and old.role = 'expert'
         and old.expert_status in ('pending', 'approved') then
        new.expert_status       := old.expert_status;
        new.expert_requested_at := old.expert_requested_at;
      else
        new.expert_status       := 'pending';
        new.expert_requested_at := now();
      end if;
    else
      -- Not an expert. A 'declined' status stays until the person has seen
      -- the note about it (acknowledge_expert_decline); anything else clears.
      new.expert_status := case
        when tg_op = 'UPDATE' and old.expert_status = 'declined' then 'declined'
      end;
      new.expert_requested_at := null;
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists profiles_enforce_role on public.profiles;
create trigger profiles_enforce_role
  before insert or update on public.profiles
  for each row execute function public.enforce_role_allowlist();

-- 4. No notice to admins per sign-up (there are several admins). They see
--    who is waiting in Profile → Expert approvals. Drop the earlier version's
--    trigger and the notices it posted.
drop trigger if exists profiles_expert_request_notice on public.profiles;
drop function if exists public.notify_admins_expert_request();
delete from public.announcements
 where title = 'Expert waiting for approval' and audience = 'Personal';

-- 3. Existing experts need approval too ----------------------------------------
-- The trigger turns a null status on an expert into 'pending'.
update public.profiles
   set expert_status = 'pending'
 where role = 'expert' and expert_status is null;

-- 5. Admin review --------------------------------------------------------------
create or replace function public.fetch_expert_requests()
returns table (user_id uuid, full_name text, email text, expertise text,
               bio text, phone text, requested_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then
    raise exception 'Only admins can review experts';
  end if;
  return query
    select p.id, p.full_name, p.email,
           nullif(btrim(p.details->>'expertise'), ''),
           nullif(btrim(p.details->>'bio'), ''),
           nullif(btrim(p.details->>'phone'), ''),
           p.expert_requested_at
      from public.profiles p
     where p.role = 'expert' and p.expert_status = 'pending' and p.onboarded
     order by p.expert_requested_at nulls last, p.full_name;
end;
$$;

grant execute on function public.fetch_expert_requests() to authenticated;

-- Approve: the account becomes a working expert account and gets a notice.
-- Decline: the account becomes a participant, its expert sign-ups for
-- sessions are removed, and the app shows it a one-time note.
-- Returns 'approved', 'declined', or 'not_pending' (already reviewed, or the
-- person switched roles).
create or replace function public.review_expert(p_user_id uuid,
                                                p_approve boolean)
returns text language plpgsql security definer set search_path = public as $$
declare
  v_row public.profiles%rowtype;
begin
  if not public.is_admin() then
    raise exception 'Only admins can review experts';
  end if;
  select * into v_row from public.profiles where id = p_user_id for update;
  if not found or v_row.role <> 'expert'
     or v_row.expert_status is distinct from 'pending' then
    return 'not_pending';
  end if;

  perform set_config('app.expert_review', 'on', true);
  if p_approve then
    update public.profiles set expert_status = 'approved'
     where id = p_user_id;
    insert into public.announcements
      (title, body, author, audience, pinned, discipline_id, created_by,
       target_user_id)
    values ('Your expert account is approved',
            'You can now sign up to serve as an expert in any session.',
            'Emerald Summit', 'Personal', false, null, auth.uid(), p_user_id);
  else
    update public.profiles
       set role = 'participant', expert_status = 'declined',
           expert_requested_at = null
     where id = p_user_id;
    delete from public.registrations
     where user_id = p_user_id and participation_type = 'expert';
  end if;
  perform set_config('app.expert_review', '', true);

  return case when p_approve then 'approved' else 'declined' end;
end;
$$;

grant execute on function public.review_expert(uuid, boolean) to authenticated;

-- The declined person has seen the note: clear it.
create or replace function public.acknowledge_expert_decline()
returns void language plpgsql security definer set search_path = public as $$
begin
  perform set_config('app.expert_review', 'on', true);
  update public.profiles set expert_status = null
   where id = auth.uid() and expert_status = 'declined';
  perform set_config('app.expert_review', '', true);
end;
$$;

grant execute on function public.acknowledge_expert_decline() to authenticated;

-- 6. Experts shown on the session page -----------------------------------------
create or replace function public.session_experts(p_session_id uuid)
returns setof text
language sql stable security definer set search_path = public as $$
  select p.full_name
    from public.registrations r
    join public.profiles p on p.id = r.user_id
   where r.session_id = p_session_id
     and r.participation_type = 'expert'
     and p.role = 'expert' and p.expert_status = 'approved'
     and btrim(p.full_name) <> ''
   order by r.created_at;
$$;

grant execute on function public.session_experts(uuid) to authenticated;

-- 7. register_for_session — approved experts only ------------------------------
create or replace function public.register_for_session(
  p_session_id uuid,
  p_participation_type text default 'participant',
  p_answers jsonb default '{}'::jsonb,
  p_project_mode text default null,
  p_project_name text default null,
  p_team_code text default null,
  p_new_owner_id uuid default null)
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  v_uid     uuid := auth.uid();
  v_sess    public.sessions%rowtype;
  v_reg     public.registrations%rowtype;
  v_count   int;
  v_clash   text;
  v_type    text := coalesce(p_participation_type, 'participant');
  v_name    text := nullif(btrim(coalesce(p_project_name, '')), '');
  v_team    public.teams%rowtype;
  v_team_id uuid;
  v_mode    text;
  v_solo    text;
  v_problem text;
begin
  if v_uid is null then
    raise exception 'Not authenticated';
  end if;

  if v_type not in ('participant', 'spectator', 'expert') then
    v_type := 'participant';
  end if;

  -- Already registered → toggle OFF. A team owner with teammates must hand the
  -- team over first.
  select * into v_reg from public.registrations
   where user_id = v_uid and session_id = p_session_id;
  if found then
    if v_reg.team_id is not null then
      v_problem := public.team_hand_off(v_reg.team_id, p_new_owner_id);
      if v_problem is not null then
        return jsonb_build_object('outcome', v_problem);
      end if;
    end if;
    delete from public.registrations where id = v_reg.id;
    return jsonb_build_object('outcome', 'removed');
  end if;

  select * into v_sess from public.sessions where id = p_session_id;
  if not found then
    raise exception 'Session not found';
  end if;

  -- Only an approved expert can serve as one. Everyone else (including an
  -- expert still waiting for approval) gets 'expert_not_approved'.
  if v_type = 'expert' and not exists (
       select 1 from public.profiles
        where id = v_uid and role = 'expert' and expert_status = 'approved') then
    return jsonb_build_object('outcome', 'expert_not_approved');
  end if;

  -- Past the participant deadline: no new participants. Spectators and
  -- experts fall through to the normal capacity / overlap checks.
  if v_type = 'participant'
     and v_sess.participant_deadline is not null
     and now() >= v_sess.participant_deadline then
    return jsonb_build_object('outcome', 'participation_closed',
                              'deadline', v_sess.participant_deadline);
  end if;

  -- Validate the project choice before anything is written.
  if v_type = 'participant' and p_project_mode is not null then
    if p_project_mode in ('create', 'join') and v_sess.max_team_size < 2 then
      return jsonb_build_object('outcome', 'teams_not_allowed');
    elsif p_project_mode in ('solo', 'create') and v_name is null then
      return jsonb_build_object('outcome', 'project_name_required');
    elsif p_project_mode = 'join' then
      select * into v_team from public.teams
       where code = public.normalize_team_code(p_team_code)
       for update;
      if not found then
        return jsonb_build_object('outcome', 'team_not_found');
      elsif v_team.session_id <> p_session_id then
        return jsonb_build_object('outcome', 'team_wrong_session');
      elsif (select count(*) from public.registrations
              where team_id = v_team.id) >= v_sess.max_team_size then
        return jsonb_build_object('outcome', 'team_full');
      end if;
    elsif p_project_mode not in ('solo', 'create', 'join') then
      raise exception 'Unknown project mode %', p_project_mode;
    end if;
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

  if v_type = 'participant' then
    case p_project_mode
      when 'solo' then
        v_mode := 'solo';
        v_solo := v_name;
      when 'create' then
        insert into public.teams
          (session_id, code, project_name, created_by, owner_id)
          values (p_session_id,
                  public.new_team_code(public.team_code_prefix(v_sess.discipline_id)),
                  v_name, v_uid, v_uid)
          returning * into v_team;
        v_mode := 'team';
        v_team_id := v_team.id;
      when 'join' then
        v_mode := 'team';
        v_team_id := v_team.id;
      else
        null; -- older app build: no project answer yet
    end case;
  end if;

  insert into public.registrations
    (user_id, session_id, participation_type, answers,
     project_mode, project_name, team_id)
    values (v_uid, p_session_id, v_type, coalesce(p_answers, '{}'::jsonb),
            v_mode, v_solo, v_team_id);

  return jsonb_build_object(
    'outcome', 'added',
    'team_code', v_team.code,
    'project_name', coalesce(v_team.project_name, v_solo));
end;
$$;

grant execute on function
  public.register_for_session(uuid, text, jsonb, text, text, text, uuid)
  to authenticated;
