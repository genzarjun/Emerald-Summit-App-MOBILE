-- Emerald Summit: more of the activity log
-- Run in the Supabase dashboard (or `supabase db query --linked -f ...`)
-- AFTER activity_log_setup.sql and announcement_activity_log.sql (which adds
-- activity_change_via()). Safe to re-run. track_edited already lists the
-- participant question switches (ask_participant_questions,
-- ask_project_name) when they flip; a column that doesn't exist yet never
-- shows as changed. If you re-run this file, run
-- activity_log_question_switches.sql again after it so created and deleted
-- tracks keep the switches in their copy too.
--
-- Adds triggers so these land in activity_log too, each with who did it,
-- what changed (old and new values), and how it came in (details.via:
-- "website or app", "dashboard / SQL" or "server key"):
--
--   Tracks (sessions)       track_created, track_edited, track_deleted
--                           (a delete keeps a copy of the track and how many
--                           people were registered; their registrations
--                           each get removed_from_session as before)
--   Site switches           summit_setting_changed (registration open,
--     (summit_settings)     session times shown, Summit date)
--   People's permissions    permissions_changed (can edit sessions, can post
--     (profiles)            announcements, front-desk check-in, managed
--                           disciplines, volunteer type, expert status),
--                           expert_verified (BeAMentor clearance verified)
--   Disciplines             discipline_created, discipline_edited,
--                           discipline_deleted
--   Volunteer hours         hours_logged, hours_edited, hours_deleted
--     (volunteer_hour_logs)
--   Volunteer/admin list    allowlist_added, allowlist_changed,
--     (role_allowlist)      allowlist_removed
--
-- user_id is the person the record is about (the volunteer whose hours or
-- permissions changed, the person on the allowlist), or, for tracks,
-- disciplines and switches, whoever made the change. actor_id is always
-- whoever made the change (null from the dashboard or a server key).
--
-- Only real changes are logged: the sheet sync rewrites role_allowlist and
-- re-applies permissions every 5 minutes, and a rewrite with the same values
-- logs nothing. A logging error never blocks the real change.
--
-- To read it (SQL Editor, newest first):
--
--   select a.at, a.action, p.full_name as about, actor.full_name as done_by,
--          a.details ->> 'via' as via, a.details
--     from public.activity_log a
--     left join public.profiles p     on p.id = a.user_id
--     left join public.profiles actor on actor.id = a.actor_id
--    order by a.at desc
--    limit 100;

-- Helpers ---------------------------------------------------------------------

-- {"key": {"from": old, "to": new}} for each listed key whose value changed.
create or replace function public.activity_changes(o jsonb, n jsonb, keys text[])
returns jsonb
language sql immutable as $$
  select coalesce(jsonb_object_agg(k, jsonb_build_object('from', o -> k, 'to', n -> k)), '{}'::jsonb)
    from unnest(keys) k
   where (o -> k) is distinct from (n -> k);
$$;

-- Names of the listed keys whose value changed (for long text and JSON).
create or replace function public.activity_changed_names(o jsonb, n jsonb, keys text[])
returns jsonb
language sql immutable as $$
  select coalesce(jsonb_agg(k order by k), '[]'::jsonb)
    from unnest(keys) k
   where (o -> k) is distinct from (n -> k);
$$;

revoke all on function public.activity_changes(jsonb, jsonb, text[]) from public, anon, authenticated;
revoke all on function public.activity_changed_names(jsonb, jsonb, text[]) from public, anon, authenticated;

-- 1. Tracks (sessions) ----------------------------------------------------------
create or replace function public.activity_track_snapshot(s public.sessions)
returns jsonb
language sql stable as $$
  select jsonb_build_object(
    'session_title', s.title,
    'discipline_id', s.discipline_id,
    'start_time',    s.start_time,
    'end_time',      s.end_time,
    'room',          s.room,
    'expert_name',   s.expert_name,
    'capacity',      s.capacity,
    'max_team_size', s.max_team_size,
    'description',   s.description);
$$;

revoke all on function public.activity_track_snapshot(public.sessions) from public, anon, authenticated;

create or replace function public.activity_from_sessions()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  o jsonb;
  n jsonb;
  changes jsonb;
  texts jsonb;
  v_registered int;
begin
  if tg_op = 'INSERT' then
    perform public.log_activity('track_created', auth.uid(), new.id,
      public.activity_track_snapshot(new) || jsonb_build_object('via', public.activity_change_via()));
    return new;
  end if;

  if tg_op = 'DELETE' then
    -- BEFORE DELETE, so the registrations are still there to count.
    select count(*) into v_registered from public.registrations r where r.session_id = old.id;
    perform public.log_activity('track_deleted', auth.uid(), old.id,
      public.activity_track_snapshot(old)
        || jsonb_build_object('via', public.activity_change_via(),
                              'registered_when_deleted', v_registered));
    return old;
  end if;

  o := to_jsonb(old);
  n := to_jsonb(new);
  changes := public.activity_changes(o, n, array[
    'title', 'discipline_id', 'track', 'room', 'room_id', 'expert_name', 'start_time',
    'end_time', 'capacity', 'max_team_size', 'participant_deadline',
    'allow_eighth_graders', 'ask_participant_questions', 'ask_project_name',
    'sponsor', 'hero_image_url']);
  texts := public.activity_changed_names(o, n, array[
    'description', 'page_blocks', 'participant_questions', 'project_prompt']);
  if changes <> '{}'::jsonb or texts <> '[]'::jsonb then
    perform public.log_activity('track_edited', auth.uid(), new.id,
      jsonb_build_object('session_title', new.title,
                         'discipline_id', new.discipline_id,
                         'changes', changes,
                         'text_changed', texts,
                         'via', public.activity_change_via()));
  end if;
  return new;
exception when others then
  raise warning 'activity_from_sessions: %', sqlerrm;
  return coalesce(new, old);
end;
$$;

drop trigger if exists activity_log_sessions on public.sessions;
create trigger activity_log_sessions
  after insert or update on public.sessions
  for each row execute function public.activity_from_sessions();

drop trigger if exists activity_log_sessions_delete on public.sessions;
create trigger activity_log_sessions_delete
  before delete on public.sessions
  for each row execute function public.activity_from_sessions();

-- 2. Site switches (summit_settings) ---------------------------------------------
create or replace function public.activity_from_summit_settings()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  changes jsonb;
begin
  changes := public.activity_changes(
    case when tg_op = 'UPDATE' then to_jsonb(old) else '{}'::jsonb end,
    to_jsonb(new),
    array['website_registration_open', 'website_show_session_times', 'summit_date']);
  if changes <> '{}'::jsonb then
    perform public.log_activity('summit_setting_changed', auth.uid(), null,
      jsonb_build_object('changes', changes, 'via', public.activity_change_via()));
  end if;
  return new;
exception when others then
  raise warning 'activity_from_summit_settings: %', sqlerrm;
  return new;
end;
$$;

drop trigger if exists activity_log_summit_settings on public.summit_settings;
create trigger activity_log_summit_settings
  after insert or update on public.summit_settings
  for each row execute function public.activity_from_summit_settings();

-- 3. People's permissions (profiles) ----------------------------------------------
-- role_changed is already logged by activity_from_profiles; this covers the
-- extra permissions and the expert's clearance.
create or replace function public.activity_from_profile_permissions()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  changes jsonb;
begin
  changes := public.activity_changes(to_jsonb(old), to_jsonb(new), array[
    'can_edit_sessions', 'can_post_announcements', 'can_check_in_front_desk',
    'managed_disciplines', 'volunteer_subtype', 'expert_status']);
  if changes <> '{}'::jsonb then
    perform public.log_activity('permissions_changed', new.id, null,
      jsonb_build_object('role', new.role, 'changes', changes,
                         'via', public.activity_change_via()));
  end if;
  if old.beamentor_verified_at is null and new.beamentor_verified_at is not null then
    perform public.log_activity('expert_verified', new.id, null,
      jsonb_build_object('verified_by', new.beamentor_verified_by,
                         'via', public.activity_change_via()));
  end if;
  return new;
exception when others then
  raise warning 'activity_from_profile_permissions: %', sqlerrm;
  return new;
end;
$$;

drop trigger if exists activity_log_profile_permissions on public.profiles;
create trigger activity_log_profile_permissions
  after update on public.profiles
  for each row execute function public.activity_from_profile_permissions();

-- 4. Disciplines --------------------------------------------------------------------
create or replace function public.activity_from_disciplines()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  changes jsonb;
begin
  if tg_op = 'INSERT' then
    perform public.log_activity('discipline_created', auth.uid(), null,
      jsonb_build_object('discipline_id', new.id, 'name', new.name, 'tagline', new.tagline,
                         'sort_order', new.sort_order, 'via', public.activity_change_via()));
    return new;
  end if;
  if tg_op = 'DELETE' then
    perform public.log_activity('discipline_deleted', auth.uid(), null,
      jsonb_build_object('discipline_id', old.id, 'name', old.name, 'tagline', old.tagline,
                         'icon', old.icon, 'sort_order', old.sort_order,
                         'via', public.activity_change_via()));
    return old;
  end if;
  changes := public.activity_changes(to_jsonb(old), to_jsonb(new),
    array['id', 'name', 'tagline', 'icon', 'sort_order']);
  if changes <> '{}'::jsonb then
    perform public.log_activity('discipline_edited', auth.uid(), null,
      jsonb_build_object('discipline_id', new.id, 'name', new.name, 'changes', changes,
                         'via', public.activity_change_via()));
  end if;
  return new;
exception when others then
  raise warning 'activity_from_disciplines: %', sqlerrm;
  return coalesce(new, old);
end;
$$;

drop trigger if exists activity_log_disciplines on public.disciplines;
create trigger activity_log_disciplines
  after insert or update or delete on public.disciplines
  for each row execute function public.activity_from_disciplines();

-- 5. Volunteer hours ------------------------------------------------------------------
create or replace function public.activity_from_volunteer_hours()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  r public.volunteer_hour_logs;
  changes jsonb;
  snap jsonb;
begin
  r := coalesce(new, old);
  -- Skipped while an account is being deleted (nothing left behind).
  if tg_op = 'DELETE' and public.activity_user_gone(old.user_id) then
    return old;
  end if;
  snap := jsonb_build_object(
    'log_id', r.id, 'started_at', r.started_at, 'ended_at', r.ended_at,
    'hours', round(extract(epoch from (r.ended_at - r.started_at)) / 3600.0, 2),
    'description', r.description, 'via', public.activity_change_via());

  if tg_op = 'INSERT' then
    perform public.log_activity('hours_logged', new.user_id, null, snap);
    return new;
  end if;
  if tg_op = 'DELETE' then
    perform public.log_activity('hours_deleted', old.user_id, null, snap);
    return old;
  end if;
  changes := public.activity_changes(to_jsonb(old), to_jsonb(new),
    array['started_at', 'ended_at', 'description']);
  if changes <> '{}'::jsonb then
    perform public.log_activity('hours_edited', new.user_id, null,
      snap || jsonb_build_object('changes', changes));
  end if;
  return new;
exception when others then
  raise warning 'activity_from_volunteer_hours: %', sqlerrm;
  return coalesce(new, old);
end;
$$;

drop trigger if exists activity_log_volunteer_hours on public.volunteer_hour_logs;
create trigger activity_log_volunteer_hours
  after insert or update or delete on public.volunteer_hour_logs
  for each row execute function public.activity_from_volunteer_hours();

-- 6. Volunteer/admin allowlist (role_allowlist) -----------------------------------------
create or replace function public.activity_from_role_allowlist()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  r public.role_allowlist;
  v_user uuid;
  changes jsonb;
  snap jsonb;
begin
  r := coalesce(new, old);
  select p.id into v_user from public.profiles p where lower(p.email) = lower(r.email) limit 1;
  snap := jsonb_build_object(
    'email', r.email, 'role', r.role, 'subtype', r.subtype, 'disciplines', to_jsonb(r.disciplines),
    'can_edit_sessions', r.can_edit_sessions, 'can_post_announcements', r.can_post_announcements,
    'can_check_in_front_desk', r.can_check_in_front_desk, 'via', public.activity_change_via());

  if tg_op = 'INSERT' then
    perform public.log_activity('allowlist_added', v_user, null, snap);
    return new;
  end if;
  if tg_op = 'DELETE' then
    perform public.log_activity('allowlist_removed', v_user, null, snap);
    return old;
  end if;
  changes := public.activity_changes(to_jsonb(old), to_jsonb(new), array[
    'email', 'role', 'subtype', 'disciplines', 'can_edit_sessions',
    'can_post_announcements', 'can_check_in_front_desk']);
  if changes <> '{}'::jsonb then
    perform public.log_activity('allowlist_changed', v_user, null,
      snap || jsonb_build_object('changes', changes));
  end if;
  return new;
exception when others then
  raise warning 'activity_from_role_allowlist: %', sqlerrm;
  return coalesce(new, old);
end;
$$;

drop trigger if exists activity_log_role_allowlist on public.role_allowlist;
create trigger activity_log_role_allowlist
  after insert or update or delete on public.role_allowlist
  for each row execute function public.activity_from_role_allowlist();
