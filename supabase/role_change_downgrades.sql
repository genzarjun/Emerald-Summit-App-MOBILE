-- Emerald Summit — role changes move sessions down to spectating, and the
-- admins' "experts waiting" notice + badge
-- Run in the Supabase dashboard AFTER expert_approval.sql. Safe to re-run.
--
--  1. When someone's role changes, any session they're in a way the new role
--     can't be is moved down to SPECTATING:
--       * participating → spectating unless the new role is participant,
--         volunteer or admin. They leave their team. A team owner's team goes
--         to the teammate who joined first (cleanup_empty_team already does
--         this); a team with no one else in it is deleted and its code stops
--         working.
--       * serving as an expert → spectating unless the new role is expert.
--       * managing → spectating unless the new role is volunteer or admin.
--         If the session is full, it's dropped from their day instead. If
--         they were already registered for it, they just stop managing.
--     It runs from a profiles trigger, so it covers Change role, a declined
--     expert, and the allowlist sync alike.
--  2. preview_role_change(role): what the change WOULD do to the caller's
--     sessions, for the Change role screen. Same code path, no writes.
--  3. review_expert: declining no longer deletes expert sign-ups; the role
--     trigger moves them to spectating like any other role change.
--  4. One rolling "Experts waiting for approval" notice per admin, with the
--     current count. A new waiting expert replaces it (so it shows as new
--     again); a review updates the count; it's removed once nobody is
--     waiting. Replaces the per-sign-up notice expert_approval.sql removed.
--  5. profiles.expert_queue_seen_at: when the admin last opened Profile. The
--     app's red badge on the Home avatar shows while a waiting expert signed
--     up after that.

-- 1. The downgrade (dry run or for real) ---------------------------------------
-- Returns a list of what changes, one item per session:
--   { session_id, title, from: participant|expert|managing,
--     to: spectator|dropped|unchanged,
--     team: { action: handed_off|deleted|left, project_name, code, to_name } }
create or replace function public.apply_role_change(p_user uuid,
                                                    p_new_role text,
                                                    p_dry_run boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
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
$$;

revoke execute on function public.apply_role_change(uuid, text, boolean)
  from public, anon, authenticated;

create or replace function public.profiles_role_downgrade()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.role is distinct from old.role then
    perform public.apply_role_change(new.id, new.role, false);
  end if;
  return null;
end;
$$;

drop trigger if exists profiles_role_downgrade on public.profiles;
create trigger profiles_role_downgrade
  after update of role on public.profiles
  for each row execute function public.profiles_role_downgrade();

-- 2. Preview for the Change role screen ----------------------------------------
create or replace function public.preview_role_change(p_role text)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;
  return public.apply_role_change(auth.uid(), p_role, true);
end;
$$;

grant execute on function public.preview_role_change(text) to authenticated;

-- 3. review_expert: declining moves expert sign-ups to spectating --------------
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
    -- The role change moves any expert sign-ups to spectating.
    update public.profiles
       set role = 'participant', expert_status = 'declined',
           expert_requested_at = null
     where id = p_user_id;
  end if;
  perform set_config('app.expert_review', '', true);

  return case when p_approve then 'approved' else 'declined' end;
end;
$$;

grant execute on function public.review_expert(uuid, boolean) to authenticated;

-- 4. The admins' rolling notice ------------------------------------------------
create or replace function public.refresh_expert_queue_notice(p_new boolean)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_title constant text := 'Experts waiting for approval';
  v_count int;
  v_body  text;
begin
  select count(*) into v_count from public.profiles
   where role = 'expert' and expert_status = 'pending' and onboarded;

  if v_count = 0 then
    delete from public.announcements
     where title = v_title and audience = 'Personal';
    return;
  end if;

  v_body := case when v_count = 1
    then '1 expert is waiting for approval.'
    else format('%s experts are waiting for approval.', v_count)
  end || ' Review them in Profile, under Expert approvals.';

  if p_new or not exists (select 1 from public.announcements
                           where title = v_title and audience = 'Personal') then
    -- Replace it so it shows as new (unread, at the top) for every admin.
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
$$;

revoke execute on function public.refresh_expert_queue_notice(boolean)
  from public, anon, authenticated;

create or replace function public.profiles_expert_queue_notice()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_was boolean := tg_op = 'UPDATE' and old.role = 'expert'
                   and old.expert_status = 'pending' and old.onboarded;
  v_is  boolean := new.role = 'expert' and new.expert_status = 'pending'
                   and new.onboarded;
begin
  if v_is and not v_was then
    perform public.refresh_expert_queue_notice(true);
  elsif v_was and not v_is then
    perform public.refresh_expert_queue_notice(false);
  end if;
  return null;
end;
$$;

drop trigger if exists profiles_expert_queue_notice on public.profiles;
create trigger profiles_expert_queue_notice
  after insert or update of role, expert_status, onboarded on public.profiles
  for each row execute function public.profiles_expert_queue_notice();

-- Post it now for anyone already waiting.
select public.refresh_expert_queue_notice(false);

-- 5. When the admin last looked --------------------------------------------------
alter table public.profiles
  add column if not exists expert_queue_seen_at timestamptz;
