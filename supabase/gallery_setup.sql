-- Emerald Summit — photo sets (bucket-driven galleries)
-- Run AFTER role_allowlist_v2.sql (it uses public.is_admin()).
--
-- MODEL: each photo set in the app is a public Storage bucket, and EVERY image
-- in that bucket is shown. Curation = uploading/deleting files; there is no
-- table. Different parts of the app read different buckets:
--   * gallery_photos — the dashboard slideshow (SupabaseGalleryRepository,
--     via AppState.dashboardGalleryBucket).
--   * (future) a second bucket per new section — copy the block below with a
--     new name and point that UI's fetchPhotos() at it.
--
-- The app LISTS the bucket (storage.list) and builds a public CDN URL per file
-- with getPublicUrl(name). Listing requires a public SELECT policy on
-- storage.objects — so unlike a pure download-only public bucket, that policy
-- is intentional here (it lets clients enumerate the bucket's photos).

-- 1. Bucket ------------------------------------------------------------------
-- Public → stable, cacheable CDN URLs (no signing).
insert into storage.buckets (id, name, public)
values ('gallery_photos', 'gallery_photos', true)
on conflict (id) do update set public = true;

-- 2. Storage RLS -------------------------------------------------------------
-- Public read/LIST (the app lists the bucket to discover its photos); admin-only
-- upload/replace/delete.
drop policy if exists "Public read gallery_photos objects" on storage.objects;
create policy "Public read gallery_photos objects"
  on storage.objects for select
  to anon, authenticated
  using (bucket_id = 'gallery_photos');

drop policy if exists "Admins write gallery_photos objects" on storage.objects;
create policy "Admins write gallery_photos objects"
  on storage.objects for all
  to authenticated
  using (bucket_id = 'gallery_photos' and public.is_admin())
  with check (bucket_id = 'gallery_photos' and public.is_admin());

-- 3. Clean up the old table-driven design ------------------------------------
-- Earlier this feature used a public.gallery_photos TABLE to curate photos; the
-- bucket-driven model replaces it. Safe to drop (the app no longer reads it).
drop table if exists public.gallery_photos;

-- 4. Migrating from the old 'gallery' bucket ---------------------------------
-- If you have photos in an earlier 'gallery' bucket, Supabase can't rename a
-- bucket, so re-upload them into 'gallery_photos' (Storage → gallery_photos →
-- Upload), then delete the old 'gallery' bucket and its policies:
--
--   drop policy if exists "Public read gallery objects"  on storage.objects;
--   drop policy if exists "Admins write gallery objects" on storage.objects;
--   -- then remove the empty 'gallery' bucket from the Storage UI.
