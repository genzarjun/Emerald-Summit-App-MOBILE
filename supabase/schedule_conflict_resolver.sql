-- Emerald Summit — clear the time conflicts people signed up for while
-- conflicts were off. Run AFTER participation_cap.sql. Safe to re-run (it
-- only defines the function; nothing happens until someone calls it).
--
-- While track times were not final, summit_settings.schedule_conflicts_on was
-- off and people could add overlapping tracks. Once the real times are in:
--
--   1. update public.summit_settings set schedule_conflicts_on = true;
--      (from then on register_for_session refuses new overlaps itself)
--   2. select * from public.resolve_schedule_conflicts();
--      Preview: lists every registration it would take off and what it
--      keeps instead. Changes nothing.
--   3. select * from public.resolve_schedule_conflicts(true);
--      Does it: deletes those registrations and sends each person a
--      personal "Schedule change" announcement per track removed.
--
-- It only needs to run once. Afterwards the conflict checks in
-- register_for_session and the "time change clashes" warning in the track
-- editor (session_time_conflicts / notify_session_time_conflicts) keep
-- schedules clean. Running it again finds nothing to do.
--
-- Which track a person keeps, per person, in this order:
--   1. A track they manage (session_volunteers) always wins; registrations
--      that overlap it go.
--   2. Serving as an expert, then participating, then spectating.
--   3. Same kind: a team registration with teammates on it beats one
--      without, so nobody's team loses a member if it can be helped.
--   4. Still tied (the 50/50 case): the one they registered for first stays.
--      Last resort, the session id, so the answer never changes between the
--      preview and the real run.
-- It walks each person's registrations in that order and keeps each one that
-- does not overlap anything already kept; the rest are removed. Tracks whose
-- start or end time is blank never count as overlapping.
--
-- Removing a team owner hands the team to the teammate who joined first
-- (cleanup_empty_team), and teammates get the usual "Teammate left" notice.
-- Only callable from the SQL editor / service role, not from the apps.

create or replace function public.resolve_schedule_conflicts(p_apply boolean default false)
returns table (
  person_id     uuid,
  person_name   text,
  removed_track text,
  removed_as    text,
  removed_time  text,
  kept_track    text,
  kept_as       text,
  kept_time     text)
language plpgsql security definer set search_path = public as $$
declare
  v_user uuid;
  v_kept uuid[];
  r      record;
  k      record;
begin
  if p_apply and not coalesce(
       (select st.schedule_conflicts_on from public.summit_settings st limit 1),
       false) then
    raise exception 'Turn on summit_settings.schedule_conflicts_on first, so '
                    'no new overlaps come in while this runs.';
  end if;

  for v_user in
    select distinct reg.user_id from public.registrations reg order by 1
  loop
    -- Tracks they manage are kept no matter what.
    v_kept := array(select sv.session_id from public.session_volunteers sv
                     where sv.user_id = v_user);

    for r in
      select reg.id, reg.session_id, reg.participation_type,
             s.title, s.discipline_id,
             public.schedule_time(s.start_time) as t_start,
             public.schedule_time(s.end_time)   as t_end,
             s.start_time, s.end_time
        from public.registrations reg
        join public.sessions s on s.id = reg.session_id
       where reg.user_id = v_user
       order by case reg.participation_type
                  when 'expert' then 0 when 'participant' then 1 else 2 end,
                exists (select 1 from public.registrations mate
                         where reg.team_id is not null
                           and mate.team_id = reg.team_id
                           and mate.user_id <> reg.user_id) desc,
                reg.created_at, reg.session_id
    loop
      select s.title, s.start_time, s.end_time,
             coalesce(kr.participation_type, 'manager') as kind
        into k
        from public.sessions s
        left join public.registrations kr
          on kr.session_id = s.id and kr.user_id = v_user
       where s.id = any(v_kept)
         and r.t_start is not null and r.t_end is not null
         and public.schedule_time(s.start_time) < r.t_end
         and r.t_start < public.schedule_time(s.end_time)
       order by public.schedule_time(s.start_time), s.id
       limit 1;

      if not found then
        v_kept := v_kept || r.session_id;
        continue;
      end if;

      person_id     := v_user;
      person_name   := (select p.full_name from public.profiles p where p.id = v_user);
      removed_track := r.title;
      removed_as    := r.participation_type;
      removed_time  := public.schedule_time_label(r.start_time, r.end_time);
      kept_track    := k.title;
      kept_as       := k.kind;
      kept_time     := public.schedule_time_label(k.start_time, k.end_time);
      return next;

      if p_apply then
        delete from public.registrations where id = r.id;
        insert into public.announcements
          (title, body, author, audience, pinned, discipline_id, created_by,
           target_user_id, session_id)
        values (
          'Schedule change',
          format('Track times are now final. "%s" (%s) overlaps with "%s" (%s), '
                 || 'which you %s, so "%s" was taken off your day. You can '
                 || 'add another track that fits from Explore.',
                 r.title, public.schedule_time_label(r.start_time, r.end_time),
                 k.title, public.schedule_time_label(k.start_time, k.end_time),
                 case k.kind
                   when 'manager' then 'are managing'
                   when 'expert' then 'are serving as an expert for'
                   when 'participant' then 'are participating in'
                   else 'are spectating' end,
                 r.title),
          'Emerald Summit', 'Personal', false, r.discipline_id, null,
          v_user, r.session_id);
      end if;
    end loop;
  end loop;
end;
$$;

-- '09:30' / '9:30' → time; blank or unreadable → null (never overlaps).
create or replace function public.schedule_time(p text)
returns time language plpgsql immutable as $$
begin
  return nullif(btrim(coalesce(p, '')), '')::time;
exception when others then
  return null;
end;
$$;

-- '09:30', '10:30' → '9:30 AM – 10:30 AM'.
create or replace function public.schedule_time_label(p_start text, p_end text)
returns text language sql immutable as $$
  select coalesce(to_char(public.schedule_time(p_start), 'FMHH12:MI AM'), 'TBD')
         || ' – '
         || coalesce(to_char(public.schedule_time(p_end), 'FMHH12:MI AM'), 'TBD');
$$;

revoke execute on function public.resolve_schedule_conflicts(boolean)
  from public, anon, authenticated;
