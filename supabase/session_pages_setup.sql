-- Emerald Summit — vibrant session pages (hero + gallery + content blocks)
-- Run AFTER role_allowlist_v2.sql (uses public.is_admin() and
-- public.can_manage_discipline(text)) and sessions_setup.sql.
--
-- Adds the fields that back the redesigned, tabbed session page:
--   * hero_image_url — the page's hero banner (a public Storage URL)
--   * page_blocks    — ordered editor-authored sections [{title, body}, …]
-- plus a `session_photos` Storage bucket (one folder per session) that admins
-- and the session's discipline editors may write to.

-- 1. Session page columns ----------------------------------------------------
-- The sessions_with_counts view is `select s.*, …`, so these flow through it
-- automatically — no view change needed. Existing UPDATE policy on
-- public.sessions (can_manage_discipline) already governs these columns.
alter table public.sessions
  add column if not exists hero_image_url text,
  add column if not exists page_blocks jsonb not null default '[]'::jsonb;

-- 2. Storage bucket ----------------------------------------------------------
-- Public → stable, cacheable CDN URLs. Photos live under a per-session prefix
-- `<session_id>/<file>`, so the folder name identifies the owning session.
insert into storage.buckets (id, name, public)
values ('session_photos', 'session_photos', true)
on conflict (id) do update set public = true;

-- 3. Write authorization helper ----------------------------------------------
-- True when the caller may manage the session that owns a given object. The
-- session id is the first path segment of the object name.
create or replace function public.can_manage_session_photo(object_name text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_admin() or public.can_manage_discipline(
    (select s.discipline_id
       from public.sessions s
      where s.id = ((storage.foldername(object_name))[1])::uuid)
  )
$$;

grant execute on function public.can_manage_session_photo(text) to authenticated;

-- 4. Storage RLS -------------------------------------------------------------
-- Public read/LIST (the app lists a session's folder to show its gallery);
-- admins and the session's discipline editors may upload/replace/delete.
drop policy if exists "Public read session_photos objects" on storage.objects;
create policy "Public read session_photos objects"
  on storage.objects for select
  to anon, authenticated
  using (bucket_id = 'session_photos');

drop policy if exists "Editors write session_photos objects" on storage.objects;
create policy "Editors write session_photos objects"
  on storage.objects for all
  to authenticated
  using (
    bucket_id = 'session_photos'
    and public.can_manage_session_photo(name)
  )
  with check (
    bucket_id = 'session_photos'
    and public.can_manage_session_photo(name)
  );
