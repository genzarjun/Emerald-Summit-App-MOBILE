-- Emerald Summit: log announcements in the activity log
-- Run in the Supabase dashboard (or `supabase db query --linked -f ...`)
-- AFTER activity_log_setup.sql. Safe to re-run.
--
-- Why: on Nov 21, 2026 a post to everyone ("Registration will open on
-- November 21st") was deleted and nothing said who did it. Deleting a post
-- erases the row (and its notifications), and Supabase's request logs only
-- last about a day on the free plan and don't cover the dashboard.
--
-- Now every post to everyone or to a discipline gets a row in activity_log:
--
--   announcement_posted    a new post
--   announcement_edited    title, text, audience, pin or attachments changed
--   announcement_deleted   the post was deleted
--
-- user_id is whoever did it (auth.uid()). Rows done outside the website and
-- the app (the Supabase dashboard's Table Editor or SQL Editor, or a server
-- key) have no user; details.via says which ("dashboard / SQL" or
-- "server key"). details keeps a full copy of the post (title, body,
-- audience, discipline, pinned, attachments, author, created_at), so a
-- deleted post can be read back, and re-posted, from the log.
--
-- Personal notices (one person's "Session cancelled", the admins' sheet and
-- expert-queue notices) are written and cleared by the system all the time,
-- so they are not logged.
--
-- To see who did what (SQL Editor, newest first):
--
--   select at, action, user_name as done_by, details ->> 'via' as via,
--          details ->> 'title' as title, details ->> 'body' as body
--     from public.activity_feed
--    where action like 'announcement_%'
--    order by at desc;
--
-- (activity_feed only returns rows to admins; the dashboard's SQL Editor
-- runs as the owner, so use the underlying table there:)
--
--   select a.at, a.action, p.full_name as done_by, p.email,
--          a.details ->> 'via' as via,
--          a.details ->> 'title' as title, a.details ->> 'body' as body
--     from public.activity_log a
--     left join public.profiles p on p.id = a.user_id
--    where a.action like 'announcement_%'
--    order by a.at desc;

-- How a change reached the database. The website and the app go through the
-- API as `authenticated`; Edge Functions and scripts with the secret key as
-- `service_role`; the dashboard's Table Editor and SQL Editor connect
-- directly (no API role).
create or replace function public.activity_change_via()
returns text
language sql stable as $$
  select case
    when auth.uid() is not null then 'website or app'
    when coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb ->> 'role'
         = 'service_role' then 'server key'
    when nullif(current_setting('request.jwt.claims', true), '') is not null then 'API, signed out'
    else 'dashboard / SQL'
  end;
$$;

revoke all on function public.activity_change_via() from public, anon, authenticated;

-- A post's contents, for the log.
create or replace function public.activity_announcement_snapshot(a public.announcements)
returns jsonb
language sql stable as $$
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
$$;

revoke all on function public.activity_announcement_snapshot(public.announcements) from public, anon, authenticated;

create or replace function public.activity_from_announcements()
returns trigger
language plpgsql security definer set search_path = public as $$
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
$$;

drop trigger if exists activity_log_announcements on public.announcements;
create trigger activity_log_announcements
  after insert or update or delete on public.announcements
  for each row execute function public.activity_from_announcements();
