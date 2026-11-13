-- Two switches for the website (dogethecoderr/Emerald-Summit-Website), kept on
-- the one summit_settings row so organizers can flip them in Supabase without
-- a deploy. The mobile app doesn't read them. Additive only; safe to re-run.
--
--   website_registration_open    false: the website greys out "Add to my day"
--                                (hover: "Registration will open on November
--                                21st"). Signing in and browsing still work.
--   website_show_session_times   false: the website shows session times,
--                                lengths and participant deadlines as "TBD",
--                                and hides Home's countdown.
--
-- Both start false. To turn one on, in the SQL editor:
--   update public.summit_settings set website_registration_open = true;
--   update public.summit_settings set website_show_session_times = true;
-- (or flip the box in Table Editor → summit_settings). Visitors pick up the
-- change on their next page load.

alter table public.summit_settings
  add column if not exists website_registration_open  boolean not null default false,
  add column if not exists website_show_session_times boolean not null default false;

-- Anyone may already read summit_settings ("Anyone reads summit settings" in
-- summit_followup_setup.sql, plus a table-wide select grant), so signed-out
-- visitors see the same switches. Let admins flip them too, like summit_date.
grant update (website_registration_open, website_show_session_times)
  on public.summit_settings to authenticated;
