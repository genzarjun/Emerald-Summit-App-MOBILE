-- Emerald Summit — size and file-type limits on the public Storage buckets
-- Run AFTER session_pages_setup.sql, gallery_setup.sql and
-- announcement_attachments.sql. Safe to re-run.
--
-- All three buckets are public, so whatever lands in them is served from the
-- project's domain to anyone with the link. Storage checks these limits on
-- every upload, the dashboard's included.
--
--  * session_photos and gallery_photos: photos only, 10 MB each. The app
--    shrinks session photos to 2000 px at 85% quality before upload (today's
--    largest is about 1.3 MB) and tags them JPEG, PNG, WebP or HEIC.
--  * announcement_attachments: keeps its 10 MB cap and now takes only the
--    types the app's compose screen labels (contentTypeForFileName in
--    lib/models/models.dart), plus application/octet-stream, which the app
--    uses for any other extension and browsers download rather than display.
--    HTML, SVG and script types, which a browser would run, are refused.
--
-- If the app starts uploading a new type, add it here too, or the upload
-- fails.

update storage.buckets
   set file_size_limit = 10485760,
       allowed_mime_types = array[
         'image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif',
         'image/gif']
 where id in ('session_photos', 'gallery_photos');

update storage.buckets
   set file_size_limit = 10485760,
       allowed_mime_types = array[
         'image/jpeg', 'image/png', 'image/gif', 'image/webp', 'image/heic',
         'application/pdf',
         'application/msword',
         'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
         'application/vnd.ms-excel',
         'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
         'application/vnd.ms-powerpoint',
         'application/vnd.openxmlformats-officedocument.presentationml.presentation',
         'text/plain', 'text/csv',
         'application/zip',
         'video/mp4', 'video/quicktime',
         'application/octet-stream']
 where id = 'announcement_attachments';
