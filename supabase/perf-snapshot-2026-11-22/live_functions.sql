CREATE OR REPLACE FUNCTION private.bug_report_snapshot(p_user uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select jsonb_build_object(
    'captured_at', now(),
    'auth', (
      select jsonb_build_object(
        'email', u.email,
        'created_at', u.created_at,
        'last_sign_in_at', u.last_sign_in_at,
        'email_confirmed_at', u.email_confirmed_at,
        'providers', u.raw_app_meta_data -> 'providers')
        from auth.users u where u.id = p_user),
    'profile', (
      select (to_jsonb(p) - 'details')
             || jsonb_build_object('details', coalesce(p.details, '{}'::jsonb)
                    - array['phone', 'student_id', 'school', 'grade', 'emergency_contact', 'emergency_phone'])
        from public.profiles p where p.id = p_user),
    'registrations', coalesce((
      select jsonb_agg(
               (to_jsonb(r) - 'user_id')
               || jsonb_build_object(
                    'session', jsonb_build_object(
                      'title', s.title, 'discipline_id', s.discipline_id, 'track', s.track,
                      'room', s.room, 'start_time', s.start_time, 'end_time', s.end_time,
                      'capacity', s.capacity),
                    'team', (
                      select (to_jsonb(t) - 'code')
                             || jsonb_build_object('members', (
                                  select count(*) from public.registrations m where m.team_id = t.id))
                        from public.teams t where t.id = r.team_id))
               order by s.start_time, s.title)
        from public.registrations r
        join public.sessions s on s.id = r.session_id
       where r.user_id = p_user), '[]'::jsonb),
    'managing', coalesce((
      select jsonb_agg(
               (to_jsonb(v) - 'user_id')
               || jsonb_build_object('session', jsonb_build_object(
                    'title', s.title, 'room', s.room, 'start_time', s.start_time, 'end_time', s.end_time))
               order by s.start_time)
        from public.session_volunteers v
        join public.sessions s on s.id = v.session_id
       where v.user_id = p_user), '[]'::jsonb),
    'removed_from', coalesce((
      select jsonb_agg((to_jsonb(x) - 'user_id') || jsonb_build_object('session_title', s.title)
                       order by x.removed_at desc)
        from public.session_removals x
        join public.sessions s on s.id = x.session_id
       where x.user_id = p_user), '[]'::jsonb),
    'checkin', (
      select to_jsonb(c) - 'attendee_id' from public.summit_checkins c where c.attendee_id = p_user),
    'allowlist', coalesce((
      select jsonb_agg(to_jsonb(a) - 'email')
        from public.role_allowlist a
       where lower(a.email) = lower((select email from auth.users where id = p_user))), '[]'::jsonb),
    'recent_notifications', coalesce((
      select jsonb_agg(jsonb_build_object(
               'kind', n.kind, 'title', n.title, 'body', left(n.body, 300),
               'session_id', n.session_id, 'announcement_id', n.announcement_id,
               'created_at', n.created_at, 'read_at', n.read_at)
               order by n.created_at desc)
        from (select * from public.notifications
               where user_id = p_user order by created_at desc limit 10) n), '[]'::jsonb),
    'recent_volunteer_hours', coalesce((
      select jsonb_agg(to_jsonb(h) - 'user_id')
        from (select * from public.volunteer_hour_logs
               where user_id = p_user order by created_at desc limit 10) h), '[]'::jsonb),
    'summit_settings', (select to_jsonb(ss) from public.summit_settings ss limit 1),
    'earlier_reports', (select count(*) from public.bug_reports b where b.user_id = p_user)
  );
$function$


CREATE OR REPLACE FUNCTION private.flush_allowlist_sync()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'private', 'public'
AS $function$
declare
  cfg private.allowlist_sync%rowtype;
begin
  select * into cfg from private.allowlist_sync where id;
  if not found then return; end if;
  perform net.http_post(
    url := cfg.function_url,
    headers := jsonb_build_object('Content-Type', 'application/json',
                                  'x-sync-secret', cfg.secret),
    body := '{}'::jsonb,
    timeout_milliseconds := 30000
  );
end;
$function$


CREATE OR REPLACE FUNCTION private.flush_hours_sheet_sync()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'private', 'public'
AS $function$
declare
  cfg private.hours_sheet_sync%rowtype;
begin
  select * into cfg from private.hours_sheet_sync where id;
  if not found then return; end if;
  if not cfg.dirty and cfg.last_sent_at > now() - interval '1 hour' then
    return;
  end if;
  -- Clear first: a change made while the sync runs marks it dirty again.
  update private.hours_sheet_sync set dirty = false, last_sent_at = now();
  perform net.http_post(
    url := cfg.function_url,
    headers := jsonb_build_object('Content-Type', 'application/json',
                                  'x-sync-secret', cfg.secret),
    body := '{}'::jsonb,
    timeout_milliseconds := 30000
  );
end;
$function$


CREATE OR REPLACE FUNCTION private.mark_hours_sheet_dirty()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'private'
AS $function$
begin
  update private.hours_sheet_sync set dirty = true where not dirty;
  return null;
end;
$function$


CREATE OR REPLACE FUNCTION public.acknowledge_expert_decline()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  perform set_config('app.expert_review', 'on', true);
  update public.profiles set expert_status = null
   where id = auth.uid() and expert_status = 'declined';
  perform set_config('app.expert_review', '', true);
end;
$function$


CREATE OR REPLACE FUNCTION public.activity_announcement_snapshot(a announcements)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$
  select jsonb_build_object(
    'announcement_id', a.id,
    'title',           a.title,
    'body',            a.body,
    'audience',        a.audience,
    'discipline_id',   a.discipline_id,
    'pinned',          a.pinned,
    'attachments',     to_jsonb(a.attachments),
    'author',          a.author,
    'created_by',      a.created_by,
    'created_at',      a.created_at);
$function$


CREATE OR REPLACE FUNCTION public.activity_change_via()
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  select case
    when auth.uid() is not null then 'website or app'
    when coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb ->> 'role'
         = 'service_role' then 'server key'
    when nullif(current_setting('request.jwt.claims', true), '') is not null then 'API, signed out'
    else 'dashboard / SQL'
  end;
$function$


CREATE OR REPLACE FUNCTION public.activity_changed_names(o jsonb, n jsonb, keys text[])
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select coalesce(jsonb_agg(k order by k), '[]'::jsonb)
    from unnest(keys) k
   where (o -> k) is distinct from (n -> k);
$function$


CREATE OR REPLACE FUNCTION public.activity_changes(o jsonb, n jsonb, keys text[])
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select coalesce(jsonb_object_agg(k, jsonb_build_object('from', o -> k, 'to', n -> k)), '{}'::jsonb)
    from unnest(keys) k
   where (o -> k) is distinct from (n -> k);
$function$


CREATE OR REPLACE FUNCTION public.activity_from_announcements()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  r       public.announcements;
  changed text[];
begin
  r := coalesce(new, old);
  -- Only posts to everyone or to a discipline; personal notices are system noise.
  if r.target_user_id is not null or r.audience = 'Personal' then
    return r;
  end if;

  if tg_op = 'INSERT' then
    perform public.log_activity('announcement_posted', auth.uid(), null,
      public.activity_announcement_snapshot(new)
        || jsonb_build_object('via', public.activity_change_via()));
    return new;
  end if;

  if tg_op = 'DELETE' then
    perform public.log_activity('announcement_deleted', auth.uid(), null,
      public.activity_announcement_snapshot(old)
        || jsonb_build_object('via', public.activity_change_via()));
    return old;
  end if;

  -- UPDATE: log only real changes, with the old title and text kept.
  select array_agg(k order by k) into changed
    from unnest(array['title', 'body', 'audience', 'discipline_id', 'pinned', 'attachments']) k
   where to_jsonb(new) -> k is distinct from to_jsonb(old) -> k;
  if changed is not null and cardinality(changed) > 0 then
    perform public.log_activity('announcement_edited', auth.uid(), null,
      public.activity_announcement_snapshot(new)
        || jsonb_build_object('via', public.activity_change_via(),
                              'fields', to_jsonb(changed),
                              'old_title', old.title,
                              'old_body', old.body));
  end if;
  return new;
exception when others then
  -- Logging never blocks the post itself.
  raise warning 'activity_from_announcements: %', sqlerrm;
  return coalesce(new, old);
end;
$function$


CREATE OR REPLACE FUNCTION public.activity_from_disciplines()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$


CREATE OR REPLACE FUNCTION public.activity_from_profile_permissions()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$


CREATE OR REPLACE FUNCTION public.activity_from_profiles()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  o jsonb;
  n jsonb;
  changed text[];
begin
  if tg_op = 'DELETE' then
    delete from public.activity_log where user_id = old.id;
    return old;
  end if;

  n := to_jsonb(new);

  if tg_op = 'INSERT' then
    perform public.log_activity('account_created', new.id, null,
      jsonb_build_object('email_domain', split_part(coalesce(new.email, ''), '@', 2)));
    if coalesce(new.onboarded, false) then
      perform public.log_activity('signed_up', new.id, null,
        jsonb_build_object('role', new.role,
                           'school', new.details ->> 'school',
                           'grade', new.details ->> 'grade'));
    end if;
    return new;
  end if;

  o := to_jsonb(old);

  if not coalesce(old.onboarded, false) and coalesce(new.onboarded, false) then
    perform public.log_activity('signed_up', new.id, null,
      jsonb_build_object('role', new.role,
                         'school', new.details ->> 'school',
                         'grade', new.details ->> 'grade'));
  elsif coalesce(old.onboarded, false) then
    if new.role is distinct from old.role then
      perform public.log_activity('role_changed', new.id, null,
        jsonb_build_object('from', old.role, 'to', new.role));
    end if;

    -- Which profile fields changed (names only, not values).
    select array_agg(k order by k) into changed
      from (
        select k from jsonb_object_keys(coalesce(new.details, '{}'::jsonb)) k
        union
        select k from jsonb_object_keys(coalesce(old.details, '{}'::jsonb)) k
      ) keys
     where (new.details -> k) is distinct from (old.details -> k);
    if new.full_name is distinct from old.full_name then
      changed := array_append(coalesce(changed, '{}'), 'full_name');
    end if;
    if changed is not null and cardinality(changed) > 0 then
      perform public.log_activity('profile_edited', new.id, null,
        jsonb_build_object('fields', to_jsonb(changed)));
    end if;
  end if;

  -- code_of_conduct.sql may not be run yet, so read the column by name.
  if (n ->> 'code_of_conduct_version') is not null
     and (n ->> 'code_of_conduct_version') is distinct from (o ->> 'code_of_conduct_version') then
    perform public.log_activity('agreed_to_code_of_conduct', new.id, null,
      jsonb_build_object('version', n ->> 'code_of_conduct_version'));
  end if;

  return new;
exception when others then
  raise warning 'activity_from_profiles: %', sqlerrm;
  return coalesce(new, old);
end;
$function$


CREATE OR REPLACE FUNCTION public.activity_from_registrations()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  snap jsonb;
  ot text;
  nt text;
begin
  snap := public.activity_session_snapshot(coalesce(new.session_id, old.session_id));

  if tg_op = 'INSERT' then
    perform public.log_activity('registered', new.user_id, new.session_id,
      snap || jsonb_build_object('participation_type', new.participation_type,
                                 'team_id', new.team_id));
    return new;
  end if;

  if tg_op = 'DELETE' then
    if public.activity_user_gone(old.user_id) then
      return old;
    end if;
    perform public.log_activity(
      case when auth.uid() is distinct from old.user_id and auth.uid() is not null
           then 'removed_from_session' else 'unregistered' end,
      old.user_id, old.session_id,
      snap || jsonb_build_object('participation_type', old.participation_type,
                                 'team_id', old.team_id,
                                 'registered_at', old.created_at));
    return old;
  end if;

  -- UPDATE
  if new.participation_type is distinct from old.participation_type then
    perform public.log_activity('participation_changed', new.user_id, new.session_id,
      snap || jsonb_build_object('from', old.participation_type,
                                 'to', new.participation_type));
  end if;

  if new.team_id is distinct from old.team_id then
    select t.code into ot from public.teams t where t.id = old.team_id;
    select t.code into nt from public.teams t where t.id = new.team_id;
    perform public.log_activity(
      case when old.team_id is null then 'joined_team'
           when new.team_id is null then 'left_team'
           else 'switched_team' end,
      new.user_id, new.session_id,
      snap || jsonb_build_object('from_team', old.team_id, 'from_code', ot,
                                 'to_team', new.team_id, 'to_code', nt));
  end if;

  if new.project_name is distinct from old.project_name
     or new.project_mode is distinct from old.project_mode then
    perform public.log_activity('project_edited', new.user_id, new.session_id,
      snap || jsonb_build_object('project_name', new.project_name,
                                 'project_mode', new.project_mode));
  end if;

  if new.answers is distinct from old.answers then
    perform public.log_activity('answers_edited', new.user_id, new.session_id, snap);
  end if;

  if coalesce(new.attended, false) is distinct from coalesce(old.attended, false) then
    perform public.log_activity(
      case when coalesce(new.attended, false) then 'checked_in' else 'check_in_undone' end,
      new.user_id, new.session_id, snap);
  end if;

  return new;
exception when others then
  raise warning 'activity_from_registrations: %', sqlerrm;
  return coalesce(new, old);
end;
$function$


CREATE OR REPLACE FUNCTION public.activity_from_role_allowlist()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$


CREATE OR REPLACE FUNCTION public.activity_from_session_volunteers()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if tg_op = 'INSERT' then
    perform public.log_activity('volunteer_assigned', new.user_id, new.session_id,
      public.activity_session_snapshot(new.session_id)
        || jsonb_build_object('conflict_override', new.conflict_override));
    return new;
  end if;
  if public.activity_user_gone(old.user_id) then
    return old;
  end if;
  perform public.log_activity('volunteer_unassigned', old.user_id, old.session_id,
    public.activity_session_snapshot(old.session_id));
  return old;
exception when others then
  raise warning 'activity_from_session_volunteers: %', sqlerrm;
  return coalesce(new, old);
end;
$function$


CREATE OR REPLACE FUNCTION public.activity_from_sessions()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$


CREATE OR REPLACE FUNCTION public.activity_from_summit_checkins()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if tg_op = 'DELETE' then
    if coalesce(old.present, false) and not public.activity_user_gone(old.attendee_id) then
      perform public.log_activity('summit_check_in_undone', old.attendee_id);
    end if;
    return old;
  end if;

  if coalesce(new.present, false) is distinct from
     coalesce(case when tg_op = 'UPDATE' then old.present end, false) then
    perform public.log_activity(
      case when coalesce(new.present, false) then 'summit_checked_in'
           else 'summit_check_in_undone' end,
      new.attendee_id);
  end if;
  return new;
exception when others then
  raise warning 'activity_from_summit_checkins: %', sqlerrm;
  return coalesce(new, old);
end;
$function$


CREATE OR REPLACE FUNCTION public.activity_from_summit_settings()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$


CREATE OR REPLACE FUNCTION public.activity_from_volunteer_hours()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$


CREATE OR REPLACE FUNCTION public.activity_session_snapshot(p_session_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(
    (select jsonb_build_object('session_title', s.title,
                               'discipline_id', s.discipline_id,
                               'start_time', s.start_time)
       from public.sessions s where s.id = p_session_id),
    '{}'::jsonb);
$function$


CREATE OR REPLACE FUNCTION public.activity_track_snapshot(s sessions)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$
  select jsonb_build_object(
    'session_title', s.title,
    'discipline_id', s.discipline_id,
    'start_time',    s.start_time,
    'end_time',      s.end_time,
    'room',          s.room,
    'expert_name',   s.expert_name,
    'capacity',      s.capacity,
    'max_team_size', s.max_team_size,
    'ask_participant_questions', s.ask_participant_questions,
    'ask_project_name', s.ask_project_name,
    'description',   s.description);
$function$


CREATE OR REPLACE FUNCTION public.activity_user_gone(p_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select not exists (select 1 from auth.users where id = p_user_id);
$function$


CREATE OR REPLACE FUNCTION public.agree_to_code_of_conduct(p_version text, p_photo_consent boolean DEFAULT NULL::boolean)
 RETURNS timestamp with time zone
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_at timestamptz := now();
begin
  if auth.uid() is null then
    raise exception 'not_signed_in';
  end if;
  if length(btrim(coalesce(p_version, ''))) = 0 then
    raise exception 'missing_version';
  end if;
  update public.profiles
     set code_of_conduct_version = btrim(p_version),
         code_of_conduct_agreed_at = v_at,
         photo_consent = p_photo_consent
   where id = auth.uid();
  return v_at;
end;
$function$


CREATE OR REPLACE FUNCTION public.allow_back_to_session(p_session_id uuid, p_user_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if auth.uid() is null or not public.can_see_session_roster(p_session_id) then
    raise exception 'Not authorized for this session roster';
  end if;
  delete from public.session_removals
   where session_id = p_session_id and user_id = p_user_id;
end;
$function$


CREATE OR REPLACE FUNCTION public.announcement_author_from_profile()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare
  v_name text;
  v_role text;
begin
  if current_user <> 'authenticated' then
    return new;
  end if;
  select nullif(btrim(full_name), ''), role into v_name, v_role
    from public.profiles where id = auth.uid();
  new.author := coalesce(
    v_name,
    case when v_role = 'admin' then 'Summit Admin' else 'Summit Volunteer' end);
  return new;
end;
$function$


CREATE OR REPLACE FUNCTION public.announcement_edit_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin
  if current_user <> 'authenticated' then
    return new;
  end if;

  if not public.is_admin() then
    new.id             := old.id;
    new.created_by     := old.created_by;
    new.created_at     := old.created_at;
    new.author         := old.author;
    new.audience       := old.audience;
    new.discipline_id  := old.discipline_id;
    new.target_user_id := old.target_user_id;
    new.session_id     := old.session_id;
    new.pinned         := old.pinned;
  end if;

  if new.title is distinct from old.title
     or new.body is distinct from old.body
     or new.attachments is distinct from old.attachments then
    new.edited_at := now();
  else
    new.edited_at := old.edited_at;
  end if;
  return new;
end;
$function$


CREATE OR REPLACE FUNCTION public.apply_role_change(p_user uuid, p_new_role text, p_dry_run boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_keep_participant boolean := p_new_role in ('participant', 'volunteer', 'admin');
  v_keep_expert      boolean := p_new_role = 'expert';
  v_keep_managing    boolean := p_new_role in ('volunteer', 'admin');
  v_items  jsonb := '[]'::jsonb;
  v_item   jsonb;
  v_team   public.teams%rowtype;
  v_next   text;
  r        record;
begin
  for r in
    select reg.id, reg.session_id, reg.participation_type, reg.team_id,
           s.title, s.start_time
      from public.registrations reg
      join public.sessions s on s.id = reg.session_id
     where reg.user_id = p_user
       and ((reg.participation_type = 'participant' and not v_keep_participant)
         or (reg.participation_type = 'expert' and not v_keep_expert))
     order by s.start_time, s.title
  loop
    v_item := jsonb_build_object('session_id', r.session_id, 'title', r.title,
                                 'from', r.participation_type,
                                 'to', 'spectator');
    if r.team_id is not null then
      select * into v_team from public.teams where id = r.team_id;
      if v_team.owner_id = p_user then
        -- Same pick as cleanup_empty_team: the teammate who joined first.
        select coalesce(nullif(p.full_name, ''), p.email) into v_next
          from public.registrations o
          join public.profiles p on p.id = o.user_id
         where o.team_id = r.team_id and o.user_id <> p_user
         order by o.created_at, o.user_id
         limit 1;
        v_item := v_item || jsonb_build_object('team', case
          when v_next is null then
            jsonb_build_object('action', 'deleted',
                               'project_name', v_team.project_name,
                               'code', v_team.code)
          else
            jsonb_build_object('action', 'handed_off',
                               'project_name', v_team.project_name,
                               'to_name', v_next)
          end);
      else
        v_item := v_item || jsonb_build_object('team', jsonb_build_object(
          'action', 'left', 'project_name', v_team.project_name));
      end if;
    end if;
    if not p_dry_run then
      -- Leaving the team fires cleanup_empty_team (hand-off or delete) and
      -- the usual teammate notices.
      update public.registrations
         set participation_type = 'spectator', project_mode = null,
             project_name = null, team_id = null, answers = '{}'::jsonb
       where id = r.id;
    end if;
    v_items := v_items || jsonb_build_array(v_item);
  end loop;

  if not v_keep_managing then
    for r in
      select sv.session_id, s.title, s.capacity,
             exists (select 1 from public.registrations x
                      where x.session_id = sv.session_id
                        and x.user_id = p_user) as registered,
             (select count(*) from public.registrations x
               where x.session_id = sv.session_id) as taken
        from public.session_volunteers sv
        join public.sessions s on s.id = sv.session_id
       where sv.user_id = p_user
       order by s.start_time, s.title
    loop
      v_item := jsonb_build_object('session_id', r.session_id,
                                   'title', r.title, 'from', 'managing',
                                   'to', case
                                     when r.registered then 'unchanged'
                                     when r.taken < r.capacity then 'spectator'
                                     else 'dropped' end);
      if not p_dry_run then
        delete from public.session_volunteers
         where session_id = r.session_id and user_id = p_user;
        -- Their "You're managing …" notice for it, as unassigning does.
        delete from public.announcements
         where target_user_id = p_user and session_id = r.session_id;
        if not r.registered and r.taken < r.capacity then
          insert into public.registrations
            (user_id, session_id, participation_type)
          values (p_user, r.session_id, 'spectator');
        end if;
      end if;
      v_items := v_items || jsonb_build_array(v_item);
    end loop;
  end if;

  return v_items;
end;
$function$


CREATE OR REPLACE FUNCTION public.archie_bump_usage(p_limit integer)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid   uuid := auth.uid();
  v_day   date := (now() at time zone 'America/Los_Angeles')::date;
  v_count int;
begin
  if v_uid is null then
    return false;
  end if;

  insert into public.archie_usage (user_id, day, count)
  values (v_uid, v_day, 1)
  on conflict (user_id, day)
    do update set count = public.archie_usage.count + 1
  returning count into v_count;

  return v_count <= greatest(p_limit, 0);
end;
$function$


CREATE OR REPLACE FUNCTION public.archie_enforce_chat_length()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if new.role = 'user' and (
    select count(*) from public.archie_messages
    where chat_id = new.chat_id and role = 'user'
  ) >= 15 then
    raise exception 'archie_chat_full' using errcode = 'P0001';
  end if;
  -- Keep the chat's "last used" time current for ordering + pruning.
  update public.archie_chats set updated_at = now() where id = new.chat_id;
  return new;
end;
$function$


CREATE OR REPLACE FUNCTION public.archie_prune_chats()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  delete from public.archie_chats
  where user_id = new.user_id
    and id not in (
      select id from public.archie_chats
      where user_id = new.user_id
      order by updated_at desc, created_at desc
      limit 10
    );
  return null;
end;
$function$


CREATE OR REPLACE FUNCTION public.archie_recent_exchanges(p_limit integer DEFAULT 100)
 RETURNS TABLE(question text, answer text, source_count integer, asked_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.is_admin() then
    raise exception 'Admins only';
  end if;
  return query
    select q.content,
           a.content,
           jsonb_array_length(a.sources),
           a.created_at
    from public.archie_messages a
    join lateral (
      select u.content from public.archie_messages u
      where u.chat_id = a.chat_id and u.role = 'user' and u.id < a.id
      order by u.id desc
      limit 1
    ) q on true
    where a.role = 'assistant'
    order by a.id desc
    limit least(greatest(p_limit, 1), 500);
end;
$function$


CREATE OR REPLACE FUNCTION public.archie_save_exchange(p_chat_id uuid, p_title text, p_question text, p_answer text, p_sources jsonb DEFAULT '[]'::jsonb, p_steps jsonb DEFAULT '[]'::jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare
  v_chat uuid := p_chat_id;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;
  if v_chat is null then
    insert into public.archie_chats (title)
    values (left(coalesce(p_title, ''), 120))
    returning id into v_chat;
  end if;
  insert into public.archie_messages (chat_id, role, content)
  values (v_chat, 'user', p_question);
  insert into public.archie_messages (chat_id, role, content, sources, steps)
  values (v_chat, 'assistant', p_answer,
          coalesce(p_sources, '[]'::jsonb), coalesce(p_steps, '[]'::jsonb));
  return v_chat;
end;
$function$


CREATE OR REPLACE FUNCTION public.assign_manager_replacing_conflicts(p_session_id uuid, p_user_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$


CREATE OR REPLACE FUNCTION public.assign_volunteer_overriding_conflict(p_session_id uuid, p_user_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$


CREATE OR REPLACE FUNCTION public.assign_volunteer_to_session(p_session_id uuid, p_user_id uuid, p_confirm_registered boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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

  -- Signed up for this session: they remove it from their day before they
  -- can manage it. This replaces the old 'registered_confirm' step, which let
  -- an admin assign them anyway; p_confirm_registered is kept for older app
  -- builds and no longer does anything.
  if exists (select 1 from public.registrations
              where user_id = p_user_id and session_id = p_session_id) then
    return jsonb_build_object('outcome', 'conflict',
                              'conflicting_title', v_sess.title,
                              'conflict_kind', 'registered_this');
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
$function$


CREATE OR REPLACE FUNCTION public.block_removed_registration()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if exists (select 1 from public.session_removals
              where session_id = new.session_id and user_id = new.user_id) then
    raise exception 'removed_from_session';
  end if;
  return new;
end;
$function$


CREATE OR REPLACE FUNCTION public.block_removed_rejoin()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if new.team_id is not null
     and (tg_op = 'INSERT' or new.team_id is distinct from old.team_id)
     and exists (select 1 from public.teams
                  where id = new.team_id
                    and new.user_id = any(removed_user_ids)) then
    raise exception 'removed_from_team';
  end if;
  return new;
end;
$function$


CREATE OR REPLACE FUNCTION public.can_check_in_front_desk()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (
    select 1 from public.profiles
     where id = auth.uid()
       and (role = 'admin'
            or (role = 'volunteer' and can_check_in_front_desk))
  );
$function$


CREATE OR REPLACE FUNCTION public.can_create_rooms()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (
    select 1 from public.profiles
     where id = auth.uid()
       and (role = 'admin'
            or (role = 'volunteer' and can_edit_sessions))
  );
$function$


CREATE OR REPLACE FUNCTION public.can_manage_discipline(p_discipline_id text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (
    select 1 from public.profiles
     where id = auth.uid()
       and (
         role = 'admin'
         or (role = 'volunteer' and can_edit_sessions
             and (managed_disciplines @> array['*']
                  or managed_disciplines @> array[p_discipline_id]))
       )
  );
$function$


CREATE OR REPLACE FUNCTION public.can_manage_session_photo(object_name text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select public.is_admin() or public.can_manage_discipline(
    (select s.discipline_id
       from public.sessions s
      where s.id = ((storage.foldername(object_name))[1])::uuid)
  )
$function$


CREATE OR REPLACE FUNCTION public.can_post_announcements()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (
    select 1 from public.profiles
     where id = auth.uid()
       and (role = 'admin'
            or (role = 'volunteer' and can_post_announcements))
  );
$function$


CREATE OR REPLACE FUNCTION public.can_post_to_discipline(p_discipline_id text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (
    select 1 from public.profiles
     where id = auth.uid()
       and (
         role = 'admin'
         or (role = 'volunteer' and can_post_announcements
             and (managed_disciplines @> array['*']
                  or managed_disciplines @> array[p_discipline_id]))
       )
  );
$function$


CREATE OR REPLACE FUNCTION public.can_see_session_roster(p_session_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select public.is_assigned_to_session(p_session_id)
      or public.is_admin()
      or public.can_manage_discipline(
           (select discipline_id from public.sessions where id = p_session_id));
$function$


CREATE OR REPLACE FUNCTION public.cleanup_empty_team()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if old.team_id is not null
     and (tg_op = 'DELETE' or new.team_id is distinct from old.team_id) then
    if not exists (select 1 from public.registrations
                    where team_id = old.team_id) then
      delete from public.teams where id = old.team_id;
    else
      update public.teams t
         set owner_id = (select r.user_id from public.registrations r
                          where r.team_id = t.id
                          order by r.created_at, r.user_id limit 1)
       where t.id = old.team_id
         and (t.owner_id is null
              or not exists (select 1 from public.registrations r
                              where r.team_id = t.id
                                and r.user_id = t.owner_id));
    end if;
  end if;
  return null;
end;
$function$


CREATE OR REPLACE FUNCTION public.default_team_name(p_owner uuid, p_code text)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(
    (select split_part(btrim(p.full_name), ' ', 1) || '''s team'
       from public.profiles p
      where p.id = p_owner and btrim(coalesce(p.full_name, '')) <> ''),
    'Team ' || p_code);
$function$


CREATE OR REPLACE FUNCTION public.delete_my_account()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'not_signed_in';
  end if;
  delete from auth.users where id = uid;
end;
$function$


CREATE OR REPLACE FUNCTION public.enforce_role_allowlist()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_auth_email text;
  v_email text;
  v_allow public.role_allowlist%rowtype;
  v_is_ambassador boolean;
begin
  -- Match the allowlist on the email the account signed in with. A user can
  -- write their own profiles row, including its email copy, so that copy is
  -- never trusted and is pinned to the sign-in email on every write.
  select email into v_auth_email from auth.users where id = new.id;
  if v_auth_email is not null then
    new.email := v_auth_email;
  end if;
  v_email := lower(v_auth_email);

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
$function$


CREATE OR REPLACE FUNCTION public.fetch_attendee_directory(p_query text DEFAULT ''::text)
 RETURNS TABLE(id uuid, full_name text, email text, role text, present boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.can_check_in_front_desk() then
    raise exception 'Not authorized for front-desk check-in';
  end if;
  return query
    select p.id, p.full_name, p.email, p.role,
           coalesce(c.present, false)
      from public.profiles p
      left join public.summit_checkins c on c.attendee_id = p.id
     where coalesce(btrim(p_query), '') = ''
        or p.full_name ilike '%' || p_query || '%'
        or p.email     ilike '%' || p_query || '%'
     order by p.full_name;
end;
$function$


CREATE OR REPLACE FUNCTION public.fetch_expert_dashboard()
 RETURNS TABLE(user_id uuid, full_name text, email text, details jsonb, onboarded boolean, requested_at timestamp with time zone, beamentor_submitted_at timestamp with time zone, beamentor_verified_at timestamp with time zone, verified_by_name text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.is_admin() then
    raise exception 'Only admins can see the expert dashboard';
  end if;
  return query
    select p.id, p.full_name, p.email, coalesce(p.details, '{}'::jsonb),
           coalesce(p.onboarded, false), p.expert_requested_at,
           p.beamentor_submitted_at, p.beamentor_verified_at, v.full_name
      from public.profiles p
      left join public.profiles v on v.id = p.beamentor_verified_by
     where p.role = 'expert' and p.expert_status in ('pending', 'approved')
       -- Only experts in the app: they ticked BeAMentor (or were verified).
       -- Two states on the dashboard: verified or not.
       and (p.beamentor_submitted_at is not null or p.beamentor_verified_at is not null)
     order by coalesce(p.beamentor_submitted_at, p.expert_requested_at) desc nulls last;
end;
$function$


CREATE OR REPLACE FUNCTION public.fetch_expert_requests()
 RETURNS TABLE(user_id uuid, full_name text, email text, expertise text, bio text, phone text, requested_at timestamp with time zone)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$


CREATE OR REPLACE FUNCTION public.fetch_my_project(p_session_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_reg  public.registrations%rowtype;
  v_team public.teams%rowtype;
  v_max  int;
begin
  select * into v_reg from public.registrations
   where user_id = auth.uid() and session_id = p_session_id;
  if not found then
    return null;
  end if;
  select max_team_size into v_max from public.sessions where id = p_session_id;
  if v_reg.team_id is null then
    return jsonb_build_object('mode', v_reg.project_mode,
                              'project_name', v_reg.project_name,
                              'max_team_size', v_max);
  end if;
  select * into v_team from public.teams where id = v_reg.team_id;
  return jsonb_build_object(
    'mode', 'team',
    'project_name', v_team.project_name,
    'team_code', v_team.code,
    'is_owner', v_team.owner_id = auth.uid(),
    'max_team_size', v_max,
    'members', coalesce((
      select jsonb_agg(coalesce(nullif(p.full_name, ''), p.email)
                       order by r.created_at, r.user_id)
        from public.registrations r
        join public.profiles p on p.id = r.user_id
       where r.team_id = v_team.id), '[]'::jsonb),
    'member_details', coalesce((
      select jsonb_agg(jsonb_build_object(
                         'id', r.user_id,
                         'name', coalesce(nullif(p.full_name, ''), p.email),
                         'is_owner', r.user_id = v_team.owner_id)
                       order by r.created_at, r.user_id)
        from public.registrations r
        join public.profiles p on p.id = r.user_id
       where r.team_id = v_team.id), '[]'::jsonb));
end;
$function$


CREATE OR REPLACE FUNCTION public.fetch_photo_permissions()
 RETURNS TABLE(user_id uuid, full_name text, email text, role text, school text, photo_consent boolean, agreed_at timestamp with time zone)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.is_admin() then
    raise exception 'not_admin';
  end if;
  return query
    select p.id, p.full_name, p.email, p.role, p.details ->> 'school',
           p.photo_consent, p.code_of_conduct_agreed_at
      from public.profiles p
     where p.onboarded and p.role <> 'expert'
     order by lower(coalesce(nullif(btrim(p.full_name), ''), p.email));
end;
$function$


CREATE OR REPLACE FUNCTION public.fetch_session_removals(p_session_id uuid)
 RETURNS TABLE(user_id uuid, full_name text, email text, participation_type text, removed_by_name text, removed_at timestamp with time zone)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.can_see_session_roster(p_session_id) then
    raise exception 'Not authorized for this session roster';
  end if;
  return query
    select sr.user_id, p.full_name, p.email, sr.participation_type,
           coalesce(nullif(b.full_name, ''), b.email), sr.removed_at
      from public.session_removals sr
      left join public.profiles p on p.id = sr.user_id
      left join public.profiles b on b.id = sr.removed_by
     where sr.session_id = p_session_id
     order by sr.removed_at desc;
end;
$function$


CREATE OR REPLACE FUNCTION public.fetch_session_roster(p_session_id uuid)
 RETURNS TABLE(user_id uuid, full_name text, email text, attended boolean, attended_at timestamp with time zone, participation_type text, answers jsonb, project_mode text, project_name text, team_id uuid, team_code text, is_team_owner boolean, role text, details jsonb)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not (public.is_assigned_to_session(p_session_id)
          or public.is_admin()
          or public.can_manage_discipline(
               (select discipline_id from public.sessions
                 where id = p_session_id))) then
    raise exception 'Not authorized for this session roster';
  end if;
  return query
    select p.id, p.full_name, p.email, r.attended, r.attended_at,
           r.participation_type, r.answers,
           r.project_mode, coalesce(t.project_name, r.project_name),
           t.id, t.code, coalesce(t.owner_id = r.user_id, false),
           p.role, coalesce(p.details, '{}'::jsonb)
      from public.registrations r
      join public.profiles p on p.id = r.user_id
      left join public.teams t on t.id = r.team_id
     where r.session_id = p_session_id
     order by p.full_name;
end;
$function$


CREATE OR REPLACE FUNCTION public.fetch_session_volunteers(p_session_id uuid)
 RETURNS TABLE(user_id uuid, full_name text, email text, subtype text, role text, phone text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$


CREATE OR REPLACE FUNCTION public.fetch_summit_metrics()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.is_admin() then
    raise exception 'Only admins can see summit metrics';
  end if;

  return jsonb_build_object(
    'people', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', p.id,
               'role', p.role,
               'school', p.details ->> 'school',
               'grade', p.details ->> 'grade'))
        from public.profiles p
       where p.onboarded), '[]'::jsonb),
    'registrations', coalesce((
      select jsonb_agg(jsonb_build_object(
               'user_id', r.user_id,
               'session_id', r.session_id,
               'discipline_id', s.discipline_id,
               'discipline_name', d.name,
               'participation_type', r.participation_type))
        from public.registrations r
        join public.sessions s on s.id = r.session_id
        join public.disciplines d on d.id = s.discipline_id), '[]'::jsonb)
  );
end;
$function$


CREATE OR REPLACE FUNCTION public.fetch_summit_status()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select jsonb_build_object(
    'summit_date', (select summit_date from public.summit_settings),
    'feedback_open', public.summit_feedback_open()
  );
$function$


CREATE OR REPLACE FUNCTION public.fetch_volunteer_hub()
 RETURNS TABLE(id uuid, full_name text, role text, subtype text, phone text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  -- Qualify every column: the OUT params (id, role, …) share their names, and
  -- an unqualified reference is ambiguous in PL/pgSQL.
  if not exists (
    select 1 from public.profiles me
     where me.id = auth.uid() and me.role in ('volunteer', 'admin')
  ) then
    raise exception 'Only volunteers and admins may open the volunteer hub';
  end if;
  return query
    select p.id, p.full_name, p.role::text, p.volunteer_subtype,
           nullif(trim(p.details->>'phone'), '')
      from public.profiles p
     where p.role in ('volunteer', 'admin')
       and p.onboarded
       and p.id <> auth.uid()
     order by (p.role = 'admin') desc, p.full_name;
end;
$function$


CREATE OR REPLACE FUNCTION public.fetch_volunteers()
 RETURNS TABLE(id uuid, full_name text, email text, subtype text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.is_admin() then
    raise exception 'Only admins may list volunteers';
  end if;
  return query
    select p.id, p.full_name, p.email, p.volunteer_subtype
      from public.profiles p
     where p.role = 'volunteer'
     order by p.full_name;
end;
$function$


CREATE OR REPLACE FUNCTION public.find_team(p_session_id uuid, p_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid    uuid := auth.uid();
  v_team   public.teams%rowtype;
  v_count  int;
  v_max    int;
  v_misses int;
begin
  if v_uid is null then
    raise exception 'Not authenticated';
  end if;
  select count(*) into v_misses from private.team_code_misses
   where user_id = v_uid and missed_at > now() - interval '15 minutes';
  if v_misses >= 10 then
    return jsonb_build_object('outcome', 'too_many_tries');
  end if;
  select * into v_team from public.teams
   where code = public.normalize_team_code(p_code);
  if not found then
    insert into private.team_code_misses (user_id) values (v_uid);
    delete from private.team_code_misses
     where user_id = v_uid and missed_at < now() - interval '1 day';
    return jsonb_build_object('outcome', 'not_found');
  end if;
  if v_team.session_id <> p_session_id then
    return jsonb_build_object(
      'outcome', 'wrong_session',
      'session_title',
      (select title from public.sessions where id = v_team.session_id));
  end if;
  if v_uid = any(v_team.removed_user_ids) then
    return jsonb_build_object('outcome', 'removed',
                              'project_name', v_team.project_name);
  end if;
  select count(*) into v_count from public.registrations
   where team_id = v_team.id;
  select max_team_size into v_max from public.sessions where id = p_session_id;
  if v_max < 2 then
    return jsonb_build_object('outcome', 'teams_not_allowed');
  end if;
  return jsonb_build_object(
    'outcome', case when v_count >= v_max then 'full' else 'found' end,
    'project_name', v_team.project_name,
    'member_count', v_count,
    'max_team_size', v_max);
end;
$function$


CREATE OR REPLACE FUNCTION public.grade_number(p_grade text)
 RETURNS integer
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select case
    when g = '' then null
    when g like '%freshman%'  then 9
    when g like '%sophomore%' then 10
    when g like '%junior%'    then 11
    when g like '%senior%'    then 12
    when g like '%eighth%'    then 8
    when d ~ '^[0-9]{1,2}$' and d::int between 1 and 12 then d::int
    else null
  end
  from (select lower(btrim(coalesce(p_grade, ''))) as g) a,
       lateral (select substring(a.g from '[0-9]+') as d) b;
$function$


CREATE OR REPLACE FUNCTION public.handle_new_user()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  insert into public.profiles (id, email)
  values (new.id, new.email)
  on conflict (id) do nothing;
  return new;
end;
$function$


CREATE OR REPLACE FUNCTION public.is_admin()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (
    select 1 from public.profiles
     where id = auth.uid() and role = 'admin'
  );
$function$


CREATE OR REPLACE FUNCTION public.is_assigned_to_session(p_session_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (
    select 1 from public.session_volunteers
     where session_id = p_session_id and user_id = auth.uid()
  );
$function$


CREATE OR REPLACE FUNCTION public.is_volunteer_or_admin()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (
    select 1 from public.profiles
     where id = auth.uid() and role in ('volunteer', 'admin')
  );
$function$


CREATE OR REPLACE FUNCTION public.log_activity(p_action text, p_user_id uuid, p_session_id uuid DEFAULT NULL::uuid, p_details jsonb DEFAULT '{}'::jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  insert into public.activity_log (actor_id, user_id, action, session_id, details)
  values (auth.uid(), p_user_id, p_action, p_session_id,
          coalesce(p_details, '{}'::jsonb));
end;
$function$


CREATE OR REPLACE FUNCTION public.manager_assignment_conflicts(p_session_id uuid, p_user_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$


CREATE OR REPLACE FUNCTION public.mark_beamentor_submitted()
 RETURNS timestamp with time zone
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_row public.profiles%rowtype;
  v_at  timestamptz := now();
begin
  if auth.uid() is null then
    raise exception 'not_signed_in';
  end if;
  select * into v_row from public.profiles where id = auth.uid() for update;
  if not found or v_row.role <> 'expert'
     or v_row.expert_status not in ('pending', 'approved') then
    raise exception 'not_an_expert';
  end if;
  if v_row.beamentor_submitted_at is not null then
    return v_row.beamentor_submitted_at;
  end if;

  perform set_config('app.expert_review', 'on', true);
  update public.profiles
     set beamentor_submitted_at = v_at,
         expert_status = 'approved'
   where id = auth.uid();
  perform set_config('app.expert_review', '', true);
  return v_at;
end;
$function$


CREATE OR REPLACE FUNCTION public.mark_notifications_read(p_ids uuid[] DEFAULT NULL::uuid[])
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_count int;
begin
  if auth.uid() is null then
    raise exception 'Sign in first';
  end if;
  update public.notifications
     set read_at = now()
   where user_id = auth.uid()
     and read_at is null
     and (p_ids is null or id = any (p_ids));
  get diagnostics v_count = row_count;
  return v_count;
end;
$function$


CREATE OR REPLACE FUNCTION public.mark_session_attendance(p_session_id uuid, p_user_id uuid, p_attended boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not (public.is_assigned_to_session(p_session_id) or public.is_admin()) then
    raise exception 'Not authorized to mark this session';
  end if;
  update public.registrations
     set attended    = p_attended,
         attended_at = case when p_attended then now() else null end,
         marked_by   = auth.uid()
   where session_id = p_session_id and user_id = p_user_id;
end;
$function$


CREATE OR REPLACE FUNCTION public.mark_summit_checkin(p_attendee_id uuid, p_present boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.can_check_in_front_desk() then
    raise exception 'Not authorized for front-desk check-in';
  end if;
  insert into public.summit_checkins (attendee_id, present, checked_in_at, marked_by)
    values (p_attendee_id, p_present,
            case when p_present then now() else null end, auth.uid())
  on conflict (attendee_id) do update
    set present       = excluded.present,
        checked_in_at = excluded.checked_in_at,
        marked_by     = excluded.marked_by;
end;
$function$


CREATE OR REPLACE FUNCTION public.my_summit_checkin()
 RETURNS TABLE(present boolean, checked_in_at timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(c.present, false), c.checked_in_at
    from (select auth.uid() as uid) me
    left join public.summit_checkins c on c.attendee_id = me.uid
   where me.uid is not null;
$function$


CREATE OR REPLACE FUNCTION public.new_team_code(p_prefix text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  c_chars constant text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  c_len   constant int  := 6;
  v_code  text;
  v_bytes bytea;
  v_b     int;
begin
  loop
    v_code := p_prefix;
    while length(v_code) < length(p_prefix) + c_len loop
      v_bytes := extensions.gen_random_bytes(16);
      for i in 0..15 loop
        v_b := get_byte(v_bytes, i);
        -- 248 = 31 * 8. Skipping 248..255 keeps every character equally likely.
        if v_b < 248 and length(v_code) < length(p_prefix) + c_len then
          v_code := v_code || substr(c_chars, v_b % 31 + 1, 1);
        end if;
      end loop;
    end loop;
    exit when not exists (select 1 from public.teams where code = v_code);
  end loop;
  return v_code;
end;
$function$


CREATE OR REPLACE FUNCTION public.normalize_team_code(p_code text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select upper(regexp_replace(coalesce(p_code, ''), '\s', '', 'g'));
$function$


CREATE OR REPLACE FUNCTION public.notify_from_announcement()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_where text;
  v_who   text;
begin
  if new.target_user_id is not null then
    insert into public.notifications
      (user_id, kind, title, body, announcement_id, session_id, created_at)
    values
      (new.target_user_id, 'notice', new.title, new.body, new.id,
       new.session_id, new.created_at)
    on conflict (user_id, announcement_id) where announcement_id is not null
    do update set title = excluded.title, body = excluded.body,
                  session_id = excluded.session_id, read_at = null;
    return new;
  end if;

  v_where := case
    when new.discipline_id is null then 'everyone'
    else coalesce((select d.name from public.disciplines d where d.id = new.discipline_id),
                  nullif(new.audience, ''), new.discipline_id)
  end;
  v_who := coalesce(nullif(btrim(new.author), ''), 'An organizer');

  insert into public.notifications
    (user_id, kind, title, body, announcement_id, created_at)
  select p.id, 'announcement', v_who || ' posted to ' || v_where, new.title,
         new.id, new.created_at
    from public.profiles p
   where p.id is distinct from new.created_by
     and (
       new.discipline_id is null
       or p.role = 'admin'
       or (p.role = 'volunteer' and p.can_edit_sessions
           and (p.managed_disciplines @> array['*']
                or p.managed_disciplines @> array[new.discipline_id]))
       or exists (
         select 1
           from public.registrations r
           join public.sessions s on s.id = r.session_id
          where r.user_id = p.id
            and s.discipline_id = new.discipline_id)
     )
  on conflict do nothing;
  return new;
end;
$function$


CREATE OR REPLACE FUNCTION public.notify_from_announcement_update()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if new.target_user_id is not null then
    -- A personal notice rewritten in place (the admins' "experts waiting" and
    -- "problem with the Google Sheet" notices) shows as unread again.
    if new.title is distinct from old.title or new.body is distinct from old.body then
      update public.notifications
         set title = new.title, body = new.body, read_at = null
       where announcement_id = new.id;
    end if;
  elsif new.title is distinct from old.title then
    -- An edited post: the note's body is the post's title. read_at is left
    -- alone so readers aren't told anything changed.
    update public.notifications
       set body = new.title
     where announcement_id = new.id
       and kind = 'announcement';
  end if;
  return new;
end;
$function$


CREATE OR REPLACE FUNCTION public.notify_organizers_of_coworker()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$


CREATE OR REPLACE FUNCTION public.notify_organizers_of_expert()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$


CREATE OR REPLACE FUNCTION public.notify_session_cancelled()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_disc text;
  v_when text;
begin
  -- Null when the discipline itself is being deleted (see above).
  select name into v_disc from public.disciplines where id = old.discipline_id;
  v_when := to_char(old.start_time::time, 'FMHH12:MI AM') || ' – '
         || to_char(old.end_time::time, 'FMHH12:MI AM');

  insert into public.announcements
    (title, body, author, audience, pinned, discipline_id, created_by,
     target_user_id)
  select 'Session cancelled',
         format('"%s" (%s%s) has been cancelled, so it was removed from your '
                || 'schedule.',
                old.title, v_when,
                case when v_disc is null then '' else ', ' || v_disc end),
         'Emerald Summit', 'Personal', false,
         case when v_disc is not null then old.discipline_id end, auth.uid(),
         people.user_id
    from (select user_id from public.registrations
           where session_id = old.id
          union
          select user_id from public.session_volunteers
           where session_id = old.id) people
   where people.user_id is distinct from auth.uid();
  return old;
end;
$function$


CREATE OR REPLACE FUNCTION public.notify_team_join()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_team   public.teams%rowtype;
  v_sess   public.sessions%rowtype;
  v_joiner text;
begin
  if new.team_id is null
     or (tg_op = 'UPDATE' and new.team_id is not distinct from old.team_id) then
    return null;
  end if;
  select * into v_team from public.teams where id = new.team_id;
  select * into v_sess from public.sessions where id = new.session_id;
  select coalesce(nullif(full_name, ''), email, 'Someone') into v_joiner
    from public.profiles where id = new.user_id;

  insert into public.announcements
    (title, body, author, audience, pinned, discipline_id, created_by,
     target_user_id)
  select 'New teammate',
         format('%s joined your team "%s" for "%s".',
                coalesce(v_joiner, 'Someone'), v_team.project_name,
                v_sess.title),
         'Emerald Summit', 'Personal', false, v_sess.discipline_id,
         new.user_id, r.user_id
    from public.registrations r
   where r.team_id = new.team_id
     and r.user_id <> new.user_id;
  return null;
end;
$function$


CREATE OR REPLACE FUNCTION public.notify_team_leave()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_team   public.teams%rowtype;
  v_sess   public.sessions%rowtype;
  v_name   text;
  v_actor  uuid := auth.uid();
  v_self   boolean;
begin
  if old.team_id is null
     or (tg_op = 'UPDATE' and new.team_id is not distinct from old.team_id) then
    return null;
  end if;
  -- A session being deleted takes its registrations with it; stay quiet.
  select * into v_sess from public.sessions where id = old.session_id;
  if not found then
    return null;
  end if;
  -- The last member leaving deletes the team (earlier trigger); no one to tell.
  select * into v_team from public.teams where id = old.team_id;
  if not found then
    return null;
  end if;
  select coalesce(nullif(full_name, ''), email) into v_name
    from public.profiles where id = old.user_id;
  v_name := coalesce(v_name, 'A teammate');
  -- They left on their own (or their account was deleted) vs. were removed.
  v_self := v_actor is null or v_actor = old.user_id;

  insert into public.announcements
    (title, body, author, audience, pinned, discipline_id, created_by,
     target_user_id)
  select case when v_self then 'Teammate left' else 'Teammate removed' end,
         case when v_self
           then format('%s left your team "%s" for "%s".',
                       v_name, v_team.project_name, v_sess.title)
           else format('%s was removed from your team "%s" for "%s".',
                       v_name, v_team.project_name, v_sess.title)
         end,
         -- created_by is only ever the acting user (null for e.g. an account
         -- deletion): it references auth.users, so naming a user who's being
         -- deleted would block the deletion.
         'Emerald Summit', 'Personal', false, v_sess.discipline_id,
         v_actor, r.user_id
    from public.registrations r
   where r.team_id = old.team_id
     and r.user_id <> old.user_id
     and r.user_id is distinct from v_actor;
  return null;
end;
$function$


CREATE OR REPLACE FUNCTION public.notify_team_owner()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_sess public.sessions%rowtype;
begin
  if new.owner_id is null
     or new.owner_id is not distinct from old.owner_id then
    return null;
  end if;
  select * into v_sess from public.sessions where id = new.session_id;
  if not found then
    return null;
  end if;
  insert into public.announcements
    (title, body, author, audience, pinned, discipline_id, created_by,
     target_user_id)
  values (
    'You''re now a team owner',
    format('You''re now the owner of "%s" for "%s". From the session page you '
           || 'can remove members or hand the team over.',
           new.project_name, v_sess.title),
    'Emerald Summit', 'Personal', false, v_sess.discipline_id,
    auth.uid(), new.owner_id);
  return null;
end;
$function$


CREATE OR REPLACE FUNCTION public.preview_manager_assignment(p_session_id uuid, p_user_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$


CREATE OR REPLACE FUNCTION public.preview_role_change(p_role text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;
  return public.apply_role_change(auth.uid(), p_role, true);
end;
$function$


CREATE OR REPLACE FUNCTION public.profiles_expert_queue_notice()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_was boolean := tg_op = 'UPDATE' and old.role = 'expert'
                   and old.beamentor_submitted_at is not null
                   and old.beamentor_verified_at is null;
  v_is  boolean := new.role = 'expert'
                   and new.beamentor_submitted_at is not null
                   and new.beamentor_verified_at is null;
begin
  if v_is and not v_was then
    perform public.refresh_expert_queue_notice(true);
  elsif v_was and not v_is then
    perform public.refresh_expert_queue_notice(false);
  end if;
  return null;
end;
$function$


CREATE OR REPLACE FUNCTION public.profiles_guard_beamentor()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  if coalesce(current_setting('app.expert_review', true), '') <> 'on' then
    if tg_op = 'INSERT' then
      new.beamentor_submitted_at := null;
      new.beamentor_verified_at  := null;
      new.beamentor_verified_by  := null;
    else
      new.beamentor_submitted_at := old.beamentor_submitted_at;
      new.beamentor_verified_at  := old.beamentor_verified_at;
      new.beamentor_verified_by  := old.beamentor_verified_by;
    end if;
  end if;
  -- Someone who stops being an expert starts over if they come back.
  if new.role is distinct from 'expert' then
    new.beamentor_submitted_at := null;
    new.beamentor_verified_at  := null;
    new.beamentor_verified_by  := null;
  end if;
  return new;
end;
$function$


CREATE OR REPLACE FUNCTION public.profiles_role_downgrade()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_items    jsonb;
  v_sessions text;
  v_count    int;
  v_name     text;
begin
  if new.role is not distinct from old.role then
    return null;
  end if;
  v_items := public.apply_role_change(new.id, new.role, false);

  -- 6. Sessions they stopped managing → tell the other admins.
  select count(*),
         string_agg(format('"%s"%s', i->>'title',
                    case when not exists (
                           select 1 from public.session_volunteers sv
                            where sv.session_id = (i->>'session_id')::uuid)
                         then ' (nobody is managing it now)' else '' end),
                    ', ')
    into v_count, v_sessions
    from jsonb_array_elements(v_items) i
   where i->>'from' = 'managing';
  if v_count > 0 then
    v_name := coalesce(nullif(btrim(new.full_name), ''), new.email, 'Someone');
    insert into public.announcements
      (title, body, author, audience, pinned, discipline_id, created_by,
       target_user_id)
    select case when v_count = 1 then 'A session lost a manager'
                else 'Sessions lost a manager' end,
           format('%s changed from %s to %s, so they no longer manage %s. '
                  || 'Assign someone else on the session''s Volunteers tab.',
                  v_name, public.role_label(old.role),
                  public.role_label(new.role), v_sessions),
           'Emerald Summit', 'Personal', false, null, new.id, a.id
      from public.profiles a
     where a.role = 'admin' and a.id <> new.id;
  end if;
  return null;
end;
$function$


CREATE OR REPLACE FUNCTION public.queue_my_session_reminders()
 RETURNS integer
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select case when auth.uid() is null then 0
              else public.queue_session_reminders(auth.uid()) end;
$function$


CREATE OR REPLACE FUNCTION public.queue_session_reminders(p_user uuid DEFAULT NULL::uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_now   timestamp := now() at time zone 'America/Los_Angeles';
  v_day   date;
  v_count int;
begin
  select summit_date into v_day from public.summit_settings;
  if v_day is null or v_now::date <> v_day then
    return 0;
  end if;

  insert into public.notifications (user_id, kind, title, body, session_id)
  select people.user_id, 'reminder',
         'Coming up at ' || to_char(v_day + s.start_time::time, 'FMHH12:MI AM') || ': ' || s.title,
         'Your session starts within the hour.',
         s.id
    from public.sessions s
    join (
      select r.user_id, r.session_id from public.registrations r
      union
      select v.user_id, v.session_id from public.session_volunteers v
    ) people on people.session_id = s.id
   where v_day + s.start_time::time > v_now
     and v_day + s.start_time::time <= v_now + interval '1 hour'
     and (p_user is null or people.user_id = p_user)
  on conflict do nothing;
  get diagnostics v_count = row_count;
  return v_count;
end;
$function$


CREATE OR REPLACE FUNCTION public.reconcile_profiles_from_allowlist()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_email text := lower(coalesce(new.email, old.email));
begin
  update public.profiles set updated_at = now()
    where lower(email) = v_email;
  return null;
end;
$function$


CREATE OR REPLACE FUNCTION public.refresh_expert_queue_notice(p_new boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_old_title constant text := 'Experts waiting for approval';
  v_title constant text := 'Experts waiting for verification';
  v_count int;
  v_body  text;
begin
  delete from public.announcements
   where title = v_old_title and audience = 'Personal';

  select count(*) into v_count from public.profiles
   where role = 'expert' and beamentor_submitted_at is not null
     and beamentor_verified_at is null;

  if v_count = 0 then
    delete from public.announcements
     where title = v_title and audience = 'Personal';
    return;
  end if;

  v_body := case when v_count = 1
    then '1 expert submitted BeAMentor and is waiting to be verified.'
    else format('%s experts submitted BeAMentor and are waiting to be verified.', v_count)
  end || ' Verify them in Profile, under Expert verification.';

  if p_new or not exists (select 1 from public.announcements
                           where title = v_title and audience = 'Personal') then
    delete from public.announcements
     where title = v_title and audience = 'Personal';
    insert into public.announcements
      (title, body, author, audience, pinned, discipline_id, created_by,
       target_user_id)
    select v_title, v_body, 'Emerald Summit', 'Personal', false, null, null,
           a.id
      from public.profiles a
     where a.role = 'admin';
  else
    update public.announcements set body = v_body
     where title = v_title and audience = 'Personal';
  end if;
end;
$function$


CREATE OR REPLACE FUNCTION public.register_for_session(p_session_id uuid, p_participation_type text DEFAULT 'participant'::text, p_answers jsonb DEFAULT '{}'::jsonb, p_project_mode text DEFAULT NULL::text, p_project_name text DEFAULT NULL::text, p_team_code text DEFAULT NULL::text, p_new_owner_id uuid DEFAULT NULL::uuid, p_intent text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid     uuid := auth.uid();
  v_sess    public.sessions%rowtype;
  v_reg     public.registrations%rowtype;
  v_count   int;
  v_clash   text;
  v_same    boolean;
  v_type    text := coalesce(p_participation_type, 'participant');
  v_name    text := nullif(btrim(coalesce(p_project_name, '')), '');
  v_pmode   text := p_project_mode;
  v_answers jsonb := coalesce(p_answers, '{}'::jsonb);
  v_code    text;
  v_team    public.teams%rowtype;
  v_team_id uuid;
  v_mode    text;
  v_solo    text;
  v_problem text;
  v_grade   int;
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
    -- An add for a session they're already in changes nothing.
    if p_intent = 'add' then
      return jsonb_build_object('outcome', 'added');
    end if;
    if v_reg.team_id is not null then
      v_problem := public.team_hand_off(v_reg.team_id, p_new_owner_id);
      if v_problem is not null then
        return jsonb_build_object('outcome', v_problem);
      end if;
    end if;
    delete from public.registrations where id = v_reg.id;
    return jsonb_build_object('outcome', 'removed');
  end if;

  -- A remove for a session they've already left changes nothing.
  if p_intent = 'remove' then
    return jsonb_build_object('outcome', 'removed');
  end if;

  -- Registration closed (summit_settings.website_registration_open is off):
  -- no new sign-ups of any kind. Leaving a session (above) still works.
  -- Raised, not returned: older builds read an outcome they don't know as
  -- 'added', but show an error as an error.
  if not coalesce((select st.website_registration_open
                     from public.summit_settings st limit 1), false) then
    raise exception 'registration_closed'
      using hint = 'Registration will open on November 21st';
  end if;

  -- Lock the session row so two people can't both take its last seat: the
  -- second waits here until the first has inserted, then counts again.
  select * into v_sess from public.sessions where id = p_session_id for update;
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

  -- Middle schoolers: an 8th grader participates only where the session's
  -- leads ticked allow_eighth_graders; younger students only spectate.
  -- Spectating and serving as an expert are open to every grade. Raised, not
  -- returned, for the same reason as registration_closed.
  if v_type = 'participant' then
    v_grade := public.grade_number(
      (select p.details ->> 'grade' from public.profiles p where p.id = v_uid));
    if v_grade is not null and v_grade < 9
       and not (v_grade = 8 and v_sess.allow_eighth_graders) then
      if v_grade = 8 then
        raise exception 'eighth_grade_not_allowed'
          using hint = 'This session is not open to 8th graders. They can still spectate.';
      else
        raise exception 'middle_school_not_allowed'
          using hint = 'Participating is for high schoolers and, in some sessions, 8th graders.';
      end if;
    end if;
  end if;

  -- A track that asks nothing: no project, no answers.
  if v_type = 'participant' and not v_sess.ask_participant_questions then
    v_pmode := null;
    v_answers := '{}'::jsonb;
  end if;

  -- Validate the project choice before anything is written.
  if v_type = 'participant' and v_pmode is not null then
    if v_pmode in ('create', 'join') and v_sess.max_team_size < 2 then
      return jsonb_build_object('outcome', 'teams_not_allowed');
    elsif v_pmode in ('solo', 'create') and v_name is null
          and v_sess.ask_project_name then
      return jsonb_build_object('outcome', 'project_name_required');
    elsif v_pmode = 'join' then
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
    elsif v_pmode not in ('solo', 'create', 'join') then
      raise exception 'Unknown project mode %', v_pmode;
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

  -- Nor one the caller manages (session_volunteers), whatever the
  -- registration type, this session included: a manager runs a session, they
  -- don't also sign up for it. Same-session first, for the clearer message.
  select s.title, s.id = p_session_id into v_clash, v_same
    from public.session_volunteers sv
    join public.sessions s on s.id = sv.session_id
   where sv.user_id = v_uid
     and (s.id = p_session_id
          or (v_sess.start_time::time < s.end_time::time
              and s.start_time::time  < v_sess.end_time::time))
   order by s.id = p_session_id desc
   limit 1;
  if v_clash is not null then
    return jsonb_build_object(
      'outcome', 'conflict',
      'conflicting_title', v_clash,
      'conflict_kind', case when v_same then 'managing_this' else 'managing' end);
  end if;

  if v_type = 'participant' then
    case v_pmode
      when 'solo' then
        v_mode := 'solo';
        v_solo := v_name;
      when 'create' then
        v_code := public.new_team_code(public.team_code_prefix(v_sess.discipline_id));
        insert into public.teams
          (session_id, code, project_name, created_by, owner_id)
          values (p_session_id, v_code,
                  coalesce(v_name, public.default_team_name(v_uid, v_code)),
                  v_uid, v_uid)
          returning * into v_team;
        v_mode := 'team';
        v_team_id := v_team.id;
      when 'join' then
        v_mode := 'team';
        v_team_id := v_team.id;
      else
        null; -- no project: an older app build, or a track that asks nothing
    end case;
  end if;

  insert into public.registrations
    (user_id, session_id, participation_type, answers,
     project_mode, project_name, team_id)
    values (v_uid, p_session_id, v_type, v_answers,
            v_mode, v_solo, v_team_id);

  return jsonb_build_object(
    'outcome', 'added',
    'team_code', v_team.code,
    'project_name', coalesce(v_team.project_name, v_solo));
end;
$function$


CREATE OR REPLACE FUNCTION public.remove_session_registration(p_session_id uuid, p_user_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid  uuid := auth.uid();
  v_type text;
  v_sess public.sessions%rowtype;
begin
  if v_uid is null or not public.can_see_session_roster(p_session_id) then
    raise exception 'Not authorized for this session roster';
  end if;
  if p_user_id = v_uid then
    return jsonb_build_object('outcome', 'cannot_remove_self');
  end if;

  delete from public.registrations
   where session_id = p_session_id and user_id = p_user_id
  returning participation_type into v_type;
  if not found then
    return jsonb_build_object('outcome', 'not_registered');
  end if;

  insert into public.session_removals
    (session_id, user_id, participation_type, removed_by)
  values (p_session_id, p_user_id, v_type, v_uid)
  on conflict (session_id, user_id) do update
    set participation_type = excluded.participation_type,
        removed_by = excluded.removed_by,
        removed_at = now();

  select * into v_sess from public.sessions where id = p_session_id;
  insert into public.announcements
    (title, body, author, audience, pinned, discipline_id, created_by,
     target_user_id)
  values (
    'Removed from a session',
    format('An organizer removed you from "%s", so it''s no longer on your '
           || 'schedule. If you think this was a mistake, contact the summit '
           || 'team.', v_sess.title),
    'Emerald Summit', 'Personal', false, v_sess.discipline_id, v_uid,
    p_user_id);

  return jsonb_build_object('outcome', 'removed');
end;
$function$


CREATE OR REPLACE FUNCTION public.remove_team_member(p_session_id uuid, p_user_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid  uuid := auth.uid();
  v_team public.teams%rowtype;
  v_sess public.sessions%rowtype;
begin
  select t.* into v_team
    from public.registrations r
    join public.teams t on t.id = r.team_id
   where r.user_id = v_uid and r.session_id = p_session_id
   for update of t;
  if not found or v_team.owner_id is distinct from v_uid then
    return jsonb_build_object('outcome', 'not_owner');
  end if;
  if p_user_id = v_uid then
    return jsonb_build_object('outcome', 'cannot_remove_self');
  end if;

  update public.registrations
     set team_id = null, project_mode = null, project_name = null
   where user_id = p_user_id and session_id = p_session_id
     and team_id = v_team.id;
  if not found then
    return jsonb_build_object('outcome', 'not_member');
  end if;
  update public.teams
     set removed_user_ids = array_append(removed_user_ids, p_user_id)
   where id = v_team.id and not (p_user_id = any(removed_user_ids));

  select * into v_sess from public.sessions where id = p_session_id;
  insert into public.announcements
    (title, body, author, audience, pinned, discipline_id, created_by,
     target_user_id)
  values (
    'Removed from a team',
    format('The owner of "%s" removed you from their team for "%s". You''re '
           || 'still registered for the session — open it to add your '
           || 'project details, or to go solo or join another team.',
           v_team.project_name, v_sess.title),
    'Emerald Summit', 'Personal', false, v_sess.discipline_id, v_uid,
    p_user_id);
  return jsonb_build_object('outcome', 'removed');
end;
$function$


CREATE OR REPLACE FUNCTION public.review_expert(p_user_id uuid, p_approve boolean)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_row public.profiles%rowtype;
begin
  if not public.is_admin() then
    raise exception 'Only admins can review experts';
  end if;
  select * into v_row from public.profiles where id = p_user_id for update;
  if not found or v_row.role <> 'expert'
     or v_row.expert_status not in ('pending', 'approved')
     or v_row.beamentor_verified_at is not null then
    return 'not_pending';
  end if;

  perform set_config('app.expert_review', 'on', true);
  if p_approve then
    update public.profiles
       set expert_status = 'approved',
           beamentor_verified_at = now(),
           beamentor_verified_by = auth.uid()
     where id = p_user_id;
    insert into public.announcements
      (title, body, author, audience, pinned, discipline_id, created_by,
       target_user_id)
    values ('Your BeAMentor clearance is verified',
            'A Summit organizer checked your BeAMentor clearance. You are all set for Emerald Summit ''27.',
            'Emerald Summit', 'Personal', false, null, auth.uid(), p_user_id);
  else
    -- The role change moves any expert sign-ups to spectating.
    update public.profiles
       set role = 'participant', expert_status = 'declined',
           expert_requested_at = null
     where id = p_user_id;
  end if;
  perform set_config('app.expert_review', '', true);

  return case when p_approve then 'approved' else 'declined' end;
end;
$function$


CREATE OR REPLACE FUNCTION public.rls_auto_enable()
 RETURNS event_trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE
  cmd record;
BEGIN
  FOR cmd IN
    SELECT *
    FROM pg_event_trigger_ddl_commands()
    WHERE command_tag IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
      AND object_type IN ('table','partitioned table')
  LOOP
     IF cmd.schema_name IS NOT NULL AND cmd.schema_name IN ('public') AND cmd.schema_name NOT IN ('pg_catalog','information_schema') AND cmd.schema_name NOT LIKE 'pg_toast%' AND cmd.schema_name NOT LIKE 'pg_temp%' THEN
      BEGIN
        EXECUTE format('alter table if exists %s enable row level security', cmd.object_identity);
        RAISE LOG 'rls_auto_enable: enabled RLS on %', cmd.object_identity;
      EXCEPTION
        WHEN OTHERS THEN
          RAISE LOG 'rls_auto_enable: failed to enable RLS on %', cmd.object_identity;
      END;
     ELSE
        RAISE LOG 'rls_auto_enable: skip % (either system schema or not in enforced list: %.)', cmd.object_identity, cmd.schema_name;
     END IF;
  END LOOP;
END;
$function$


CREATE OR REPLACE FUNCTION public.role_label(p_role text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select case p_role
    when 'participant'     then 'Participant'
    when 'expert'          then 'Expert'
    when 'parentSpectator' then 'Parent / Spectator'
    when 'volunteer'       then 'Volunteer'
    when 'admin'           then 'Admin'
    else coalesce(p_role, 'another role') end;
$function$


CREATE OR REPLACE FUNCTION public.scan_summit_checkin(p_attendee_id uuid)
 RETURNS TABLE(attendee_found boolean, already_checked_in boolean, full_name text, email text, role text, checked_in_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$


CREATE OR REPLACE FUNCTION public.session_experts(p_session_id uuid)
 RETURNS SETOF text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select p.full_name
    from public.registrations r
    join public.profiles p on p.id = r.user_id
   where r.session_id = p_session_id
     and r.participation_type = 'expert'
     and p.role = 'expert' and p.expert_status = 'approved'
     and btrim(p.full_name) <> ''
   order by r.created_at;
$function$


CREATE OR REPLACE FUNCTION public.set_bug_report_status(p_id uuid, p_status text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.is_admin() then
    raise exception 'not_admin';
  end if;
  if p_status not in ('open', 'resolved') then
    raise exception 'bad_status';
  end if;
  update public.bug_reports
     set status = p_status,
         resolved_at = case when p_status = 'resolved' then now() else null end
   where bug_reports.id = p_id;
end;
$function$


CREATE OR REPLACE FUNCTION public.set_eaf_future_interest(p_yes boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.is_volunteer_or_admin() then
    raise exception 'Only volunteers and admins answer this';
  end if;
  if not public.summit_feedback_open() then
    raise exception 'This opens after the summit';
  end if;
  insert into public.eaf_future_interest (user_id, wants_to_volunteer)
    values (auth.uid(), p_yes)
  on conflict (user_id) do update
    set wants_to_volunteer = excluded.wants_to_volunteer,
        answered_at = now();
end;
$function$


CREATE OR REPLACE FUNCTION public.set_session_manage(p_session_id uuid, p_manage boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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

  -- Signed up for this session: they remove it from their day first. A
  -- manager runs the session; they don't also take part in it.
  if exists (select 1 from public.registrations
              where user_id = v_uid and session_id = p_session_id) then
    return jsonb_build_object('outcome', 'conflict',
                              'conflicting_title', v_sess.title,
                              'conflict_kind', 'registered_this');
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
$function$


CREATE OR REPLACE FUNCTION public.submit_bug_report(p_id uuid, p_kind text, p_name text, p_description text, p_screenshots text[], p_client jsonb, p_email_copy boolean)
 RETURNS TABLE(id uuid, ticket_no bigint)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
declare
  v_user  uuid := auth.uid();
  v_shots text[];
  v_row   public.bug_reports;
begin
  if v_user is null then
    raise exception 'not_signed_in';
  end if;
  if p_id is null then
    raise exception 'missing_id';
  end if;
  if coalesce(p_kind, '') not in ('bug', 'feedback') then
    raise exception 'bad_kind';
  end if;
  if length(btrim(coalesce(p_name, ''))) = 0 then
    raise exception 'name_required';
  end if;
  if length(btrim(coalesce(p_description, ''))) = 0 then
    raise exception 'description_required';
  end if;
  if length(btrim(p_name)) > 120 or length(btrim(p_description)) > 5000 then
    raise exception 'too_long';
  end if;
  if octet_length(coalesce(p_client, '{}'::jsonb)::text) > 200000 then
    raise exception 'client_too_large';
  end if;
  if (select count(*) from public.bug_reports b
       where b.user_id = v_user and b.created_at > now() - interval '1 hour') >= 10 then
    raise exception 'too_many_reports';
  end if;

  -- Only screenshots that were really uploaded into this report's folder.
  select coalesce(array_agg(s order by ord), '{}')
    into v_shots
    from unnest(coalesce(p_screenshots, '{}')) with ordinality as t(s, ord)
   where ord <= 5
     and s like v_user::text || '/' || p_id::text || '/%'
     and exists (select 1 from storage.objects o
                  where o.bucket_id = 'bug_report_screenshots' and o.name = s);

  insert into public.bug_reports
    (id, user_id, kind, reporter_name, description, screenshots, email_copy, client, snapshot)
  values
    (p_id, v_user, p_kind, btrim(p_name), btrim(p_description), v_shots,
     coalesce(p_email_copy, false), coalesce(p_client, '{}'::jsonb),
     private.bug_report_snapshot(v_user))
  returning * into v_row;

  return query select v_row.id, v_row.ticket_no;
end;
$function$


CREATE OR REPLACE FUNCTION public.submit_expert_feedback(p_items jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_item    jsonb;
  v_kind    text;
  v_session uuid;
begin
  if not exists (select 1 from public.profiles
                  where id = auth.uid() and role = 'expert') then
    raise exception 'Only experts give summit feedback';
  end if;
  if not public.summit_feedback_open() then
    raise exception 'Feedback opens after the summit';
  end if;

  for v_item in select * from jsonb_array_elements(p_items) loop
    v_kind := v_item->>'kind';
    v_session := nullif(v_item->>'session_id', '')::uuid;
    if v_kind = 'session' and not exists (
      select 1 from public.registrations r
       where r.user_id = auth.uid() and r.session_id = v_session
         and r.participation_type = 'expert'
    ) then
      raise exception 'You can only rate sessions you served in as an expert';
    end if;

    delete from public.expert_feedback
     where expert_id = auth.uid() and kind = v_kind
       and session_id is not distinct from v_session;
    insert into public.expert_feedback (expert_id, kind, session_id, rating, comment)
      values (auth.uid(), v_kind, v_session,
              (v_item->>'rating')::smallint,
              trim(coalesce(v_item->>'comment', '')));
  end loop;
end;
$function$


CREATE OR REPLACE FUNCTION public.summit_feedback_open()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce((
    select (now() at time zone 'America/Los_Angeles') >=
           st.summit_date
             + coalesce((select max(s.end_time::time) from public.sessions s),
                        time '23:59')
      from public.summit_settings st
     where st.summit_date is not null
  ), false);
$function$


CREATE OR REPLACE FUNCTION public.team_code_prefix(p_discipline_id text)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(
    case p_discipline_id
      when 'techverse'    then 'TV'
      when 'ventureverse' then 'VV'
      when 'biosphere'    then 'BS'
      when 'novasphere'   then 'NS'
      when 'civicverse'   then 'CV'
      when 'imaginex'     then 'IX'
    end,
    (select case
              when length(regexp_replace(d.name, '[^A-Z]', '', 'g')) >= 2
                then left(regexp_replace(d.name, '[^A-Z]', '', 'g'), 2)
              else rpad(upper(left(regexp_replace(d.name, '[^A-Za-z]', '', 'g'), 2)),
                        2, 'X')
            end
       from public.disciplines d where d.id = p_discipline_id),
    'TM');
$function$


CREATE OR REPLACE FUNCTION public.team_hand_off(p_team_id uuid, p_new_owner uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid   uuid := auth.uid();
  v_owner uuid;
begin
  select owner_id into v_owner from public.teams where id = p_team_id for update;
  if v_owner is distinct from v_uid then
    return null;
  end if;
  if not exists (select 1 from public.registrations
                  where team_id = p_team_id and user_id <> v_uid) then
    return null;
  end if;
  if p_new_owner is null then
    return 'choose_new_owner';
  end if;
  if p_new_owner = v_uid
     or not exists (select 1 from public.registrations
                     where team_id = p_team_id and user_id = p_new_owner) then
    return 'invalid_new_owner';
  end if;
  update public.teams set owner_id = p_new_owner where id = p_team_id;
  return null;
end;
$function$


CREATE OR REPLACE FUNCTION public.touch_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  new.updated_at = now();
  return new;
end;
$function$


CREATE OR REPLACE FUNCTION public.touch_volunteer_hour_log()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  new.updated_at := now();
  return new;
end;
$function$


CREATE OR REPLACE FUNCTION public.transfer_team_ownership(p_session_id uuid, p_new_owner_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid  uuid := auth.uid();
  v_team public.teams%rowtype;
begin
  select t.* into v_team
    from public.registrations r
    join public.teams t on t.id = r.team_id
   where r.user_id = v_uid and r.session_id = p_session_id
   for update of t;
  if not found or v_team.owner_id is distinct from v_uid then
    return jsonb_build_object('outcome', 'not_owner');
  end if;
  if p_new_owner_id is null or p_new_owner_id = v_uid
     or not exists (select 1 from public.registrations
                     where team_id = v_team.id and user_id = p_new_owner_id) then
    return jsonb_build_object('outcome', 'invalid_new_owner');
  end if;
  update public.teams set owner_id = p_new_owner_id where id = v_team.id;
  return jsonb_build_object('outcome', 'transferred');
end;
$function$


CREATE OR REPLACE FUNCTION public.unassign_volunteer_from_session(p_session_id uuid, p_user_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$


CREATE OR REPLACE FUNCTION public.update_my_registration(p_session_id uuid, p_answers jsonb, p_project_mode text, p_project_name text DEFAULT NULL::text, p_team_code text DEFAULT NULL::text, p_new_owner_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid     uuid := auth.uid();
  v_reg     public.registrations%rowtype;
  v_sess    public.sessions%rowtype;
  v_team    public.teams%rowtype;
  v_name    text := nullif(btrim(coalesce(p_project_name, '')), '');
  v_code    text;
  v_problem text;
begin
  if v_uid is null then
    raise exception 'Not authenticated';
  end if;
  if p_answers is null or jsonb_typeof(p_answers) <> 'object' then
    raise exception 'Answers must be a JSON object';
  end if;

  select * into v_reg from public.registrations
   where user_id = v_uid and session_id = p_session_id
     and participation_type = 'participant';
  if not found then
    return jsonb_build_object('outcome', 'not_registered');
  end if;
  select * into v_sess from public.sessions where id = p_session_id;

  -- Validate the destination before touching the current team. A solo-only
  -- session (max_team_size 1) refuses new teams and joins; anyone already on
  -- a team from before the switch can stay on it or go solo.
  if p_project_mode = 'create' and v_sess.max_team_size < 2 then
    return jsonb_build_object('outcome', 'teams_not_allowed');
  end if;
  case p_project_mode
    when 'solo', 'create' then
      if v_name is null and v_sess.ask_project_name
         and v_sess.ask_participant_questions then
        return jsonb_build_object('outcome', 'project_name_required');
      end if;
    when 'join' then
      select * into v_team from public.teams
       where code = public.normalize_team_code(p_team_code)
       for update;
      if not found then
        return jsonb_build_object('outcome', 'team_not_found');
      elsif v_team.session_id <> p_session_id then
        return jsonb_build_object('outcome', 'team_wrong_session');
      elsif v_team.id is distinct from v_reg.team_id
            and v_sess.max_team_size < 2 then
        return jsonb_build_object('outcome', 'teams_not_allowed');
      elsif v_team.id is distinct from v_reg.team_id
            and (select count(*) from public.registrations
                  where team_id = v_team.id) >= v_sess.max_team_size then
        return jsonb_build_object('outcome', 'team_full');
      end if;
    when 'stay' then
      select * into v_team from public.teams where id = v_reg.team_id;
      if not found then
        return jsonb_build_object('outcome', 'no_team');
      end if;
    else
      raise exception 'Unknown project mode %', p_project_mode;
  end case;

  -- Leaving the current team? An owner with teammates hands it over first.
  if v_reg.team_id is not null
     and p_project_mode <> 'stay'
     and v_team.id is distinct from v_reg.team_id then
    v_problem := public.team_hand_off(v_reg.team_id, p_new_owner_id);
    if v_problem is not null then
      return jsonb_build_object('outcome', v_problem);
    end if;
  end if;

  case p_project_mode
    when 'solo' then
      update public.registrations
         set answers = p_answers, project_mode = 'solo',
             project_name = v_name, team_id = null
       where id = v_reg.id;
      return jsonb_build_object('outcome', 'updated', 'project_name', v_name);
    when 'create' then
      v_code := public.new_team_code(public.team_code_prefix(v_sess.discipline_id));
      insert into public.teams
        (session_id, code, project_name, created_by, owner_id)
        values (p_session_id, v_code,
                coalesce(v_name, public.default_team_name(v_uid, v_code)),
                v_uid, v_uid)
        returning * into v_team;
    when 'stay' then
      if v_name is not null and v_name <> v_team.project_name then
        update public.teams set project_name = v_name
         where id = v_team.id
        returning * into v_team;
      end if;
    else
      null; -- 'join': v_team already resolved
  end case;

  update public.registrations
     set answers = p_answers, project_mode = 'team',
         project_name = null, team_id = v_team.id
   where id = v_reg.id;
  return jsonb_build_object('outcome', 'updated',
                            'team_code', v_team.code,
                            'project_name', v_team.project_name);
end;
$function$


CREATE OR REPLACE FUNCTION public.update_registration_answers(p_session_id uuid, p_answers jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'Not authenticated';
  end if;
  if p_answers is null or jsonb_typeof(p_answers) <> 'object' then
    raise exception 'Answers must be a JSON object';
  end if;

  update public.registrations
     set answers = p_answers
   where user_id = v_uid and session_id = p_session_id;
  if not found then
    return jsonb_build_object('outcome', 'not_registered');
  end if;
  return jsonb_build_object('outcome', 'updated');
end;
$function$
