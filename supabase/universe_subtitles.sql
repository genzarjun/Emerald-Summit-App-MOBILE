-- Emerald Summit — the four renamed discipline subtitles
-- Run in the Supabase dashboard (SQL Editor). Safe to re-run.
--
-- The website renamed four disciplines' subtitles. The app and, since
-- Nov 13, 2026, the website both show `disciplines.tagline`, so this puts
-- the new wording in the table both read. The app's discipline editor only
-- creates disciplines, and the API lets admins update a row but nothing in
-- either client edits one, so it's done here.

update public.disciplines set tagline = 'Arts, Literature, Music, Drama & Improv'
 where id = 'imaginex';
update public.disciplines set tagline = 'Core Sciences, Climate Change & Sustainability'
 where id = 'novasphere';
update public.disciplines set tagline = 'Entrepreneurship & Marketing'
 where id = 'ventureverse';
update public.disciplines set tagline = 'Mock Trial, Government Policy & Rights'
 where id = 'civicverse';
