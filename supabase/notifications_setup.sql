-- Emerald Summit — Notifications feed (the bell), separate from News
-- Run AFTER the announcement, registration, session_volunteers and
-- summit_followup SQL files. Safe to re-run.
--
-- News is the organizers' posts. The bell is short notes about you:
--   * 'announcement' "Priya Shah posted to TechVerse" → opens the post.
--   * 'notice'       personal notices ("You have been assigned to manage …",
--                    team changes, expert approval, sheet problems). They are
--                    still inserted into announcements with target_user_id by
--                    the existing RPCs and triggers; a trigger copies each one
--                    here, and the apps no longer show them in News.
--   * 'reminder'     "Coming up at 10:30 AM: AI Playground", within the hour
--                    before a session you're in or managing, on summit day.
--
-- Every row is written by the SECURITY DEFINER functions below; users can only
-- read their own rows and mark them read through mark_notifications_read().
-- notifications_enabled does not filter this table: it only mutes the phone's
-- banner (and push, once built). The bell fills either way.

-- 1. Table -------------------------------------------------------------------
create table if not exists public.notifications (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid not null references auth.users (id) on delete cascade,
  kind             text not null check (kind in ('announcement', 'notice', 'reminder')),
  title            text not null,
  body             text not null default '',
  announcement_id  uuid references public.announcements (id) on delete cascade,
  session_id       uuid references public.sessions (id) on delete cascade,
  created_at       timestamptz not null default now(),
  read_at          timestamptz
);

create index if not exists notifications_user_idx
  on public.notifications (user_id, created_at desc);

-- One note per person per announcement, and one reminder per person per session.
create unique index if not exists notifications_one_per_announcement
  on public.notifications (user_id, announcement_id)
  where announcement_id is not null;
create unique index if not exists notifications_one_reminder
  on public.notifications (user_id, session_id)
  where kind = 'reminder';

-- 2. Row Level Security ------------------------------------------------------
alter table public.notifications enable row level security;

drop policy if exists "Users read own notifications" on public.notifications;
create policy "Users read own notifications"
  on public.notifications for select
  to authenticated
  using (user_id = auth.uid());

revoke all on public.notifications from anon, authenticated;
grant select on public.notifications to authenticated;

-- 3. Mark read ---------------------------------------------------------------
-- p_ids null marks every unread note of the caller ("Mark all as read").
create or replace function public.mark_notifications_read(p_ids uuid[] default null)
returns int
language plpgsql security definer set search_path = public as $$
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
$$;

revoke all on function public.mark_notifications_read(uuid[]) from public, anon;
grant execute on function public.mark_notifications_read(uuid[]) to authenticated;

-- 4. Announcements → notifications -------------------------------------------
-- A post to Everyone or a discipline: one note per person it reaches, using the
-- same audience as the News feed (admins, volunteers who manage the
-- discipline, and anyone registered in one of its sessions). The poster gets
-- none. A personal notice (target_user_id): one note for that person.
create or replace function public.notify_from_announcement()
returns trigger
language plpgsql security definer set search_path = public as $$
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
$$;

drop trigger if exists notify_from_announcement on public.announcements;
create trigger notify_from_announcement
  after insert on public.announcements
  for each row execute function public.notify_from_announcement();

-- A personal notice that's rewritten in place (the admins' "experts waiting"
-- and "problem with the Google Sheet" notices) updates its note and shows it
-- as unread again.
create or replace function public.notify_from_announcement_update()
returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.target_user_id is not null
     and (new.title is distinct from old.title or new.body is distinct from old.body) then
    update public.notifications
       set title = new.title, body = new.body, read_at = null
     where announcement_id = new.id;
  end if;
  return new;
end;
$$;

drop trigger if exists notify_from_announcement_update on public.announcements;
create trigger notify_from_announcement_update
  after update of title, body on public.announcements
  for each row execute function public.notify_from_announcement_update();

-- Existing personal notices get a note too. One the person already opened in
-- News counts as read.
insert into public.notifications
  (user_id, kind, title, body, announcement_id, session_id, created_at, read_at)
select a.target_user_id, 'notice', a.title, a.body, a.id, a.session_id, a.created_at,
       (select coalesce(r.opened_at, r.read_at) from public.announcement_reads r
         where r.user_id = a.target_user_id and r.announcement_id = a.id)
  from public.announcements a
 where a.target_user_id is not null
on conflict do nothing;

-- 5. Session reminders -------------------------------------------------------
-- On summit day (summit_settings.summit_date, Pacific time), a session that
-- starts within the next hour gets a note for everyone registered for it
-- (participating, spectating or serving as an expert) and every volunteer
-- managing it. Nothing happens while the summit date is unset.
create or replace function public.queue_session_reminders(p_user uuid default null)
returns int
language plpgsql security definer set search_path = public as $$
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
$$;

-- Everyone at once: for a scheduled job only (see below), never the apps.
revoke all on function public.queue_session_reminders(uuid) from public, anon, authenticated;

-- The apps call this while open (on launch and every few minutes), so the bell
-- gets reminders even without the scheduled job.
create or replace function public.queue_my_session_reminders()
returns int
language sql security definer set search_path = public as $$
  select case when auth.uid() is null then 0
              else public.queue_session_reminders(auth.uid()) end;
$$;

revoke all on function public.queue_my_session_reminders() from public, anon;
grant execute on function public.queue_my_session_reminders() to authenticated;

-- Optional, for push later: run every 5 minutes with pg_cron (Database →
-- Extensions → pg_cron), so reminders are written even when nobody has the app
-- open:
--   select cron.schedule('session-reminders', '*/5 * * * *',
--                        $$select public.queue_session_reminders()$$);

-- 6. Realtime ----------------------------------------------------------------
do $$
begin
  alter publication supabase_realtime add table public.notifications;
exception
  when duplicate_object then null;
end $$;
