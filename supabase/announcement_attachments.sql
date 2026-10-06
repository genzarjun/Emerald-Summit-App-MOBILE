-- Emerald Summit — photos & files on announcements
-- Run AFTER role_allowlist_v2.sql (uses public.is_admin()) and
-- announcements_write_setup.sql.
--
-- Lets anyone who can post an announcement (admins, and volunteers with
-- can_post_announcements) attach photos and files to it. The files live in a
-- public `announcement_attachments` Storage bucket under the uploader's own
-- folder (`<user_id>/<file>`); the announcement row lists them in a jsonb
-- `attachments` column ([{url, path, name, type, size}, …]) that the detail
-- page renders. Safe to run more than once.

-- 1. Column --------------------------------------------------------------------
alter table public.announcements
  add column if not exists attachments jsonb not null default '[]'::jsonb;

-- 2. Bucket --------------------------------------------------------------------
-- Public → stable CDN URLs the app caches on disk (same as session_photos).
-- Announcements themselves are readable by everyone (broadcasts), so public
-- attachment URLs don't widen who can see them. 10 MB cap per file.
insert into storage.buckets (id, name, public, file_size_limit)
values ('announcement_attachments', 'announcement_attachments', true, 10485760)
on conflict (id) do update set public = true, file_size_limit = 10485760;

-- 3. Who may upload --------------------------------------------------------------
-- Admins, or a volunteer granted can_post_announcements (the same people the
-- composer is shown to; posting is still scoped by the announcements policy).
create or replace function public.can_post_announcements()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.profiles
     where id = auth.uid()
       and (role = 'admin'
            or (role = 'volunteer' and can_post_announcements))
  );
$$;

grant execute on function public.can_post_announcements() to authenticated;

-- 4. Storage RLS -------------------------------------------------------------------
-- Reads go through the public URL, so no SELECT/list policy is needed (nobody
-- can enumerate the bucket). Uploads must land in the uploader's own folder.
-- The uploader can remove their own files (cleanup when a post fails); admins
-- can remove any (cleanup when an announcement is deleted for everyone).
drop policy if exists "Posters upload announcement attachments" on storage.objects;
create policy "Posters upload announcement attachments"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'announcement_attachments'
    and (storage.foldername(name))[1] = auth.uid()::text
    and public.can_post_announcements()
  );

drop policy if exists "Owners and admins read announcement attachment rows" on storage.objects;
create policy "Owners and admins read announcement attachment rows"
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'announcement_attachments'
    and ((storage.foldername(name))[1] = auth.uid()::text or public.is_admin())
  );

drop policy if exists "Owners and admins delete announcement attachments" on storage.objects;
create policy "Owners and admins delete announcement attachments"
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'announcement_attachments'
    and ((storage.foldername(name))[1] = auth.uid()::text or public.is_admin())
  );
