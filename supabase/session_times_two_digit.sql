-- Emerald Summit — two-digit hours in session times
-- Safe to re-run.
--
-- start_time / end_time are text, so "9:30" sorts after "14:00" wherever the
-- database orders by them (the app's catalog query, Archie's catalog). The
-- editor always saves two digits; rows typed by hand or seeded did not. This
-- pads a single-digit hour with a zero and leaves everything else alone.
update public.sessions
   set start_time = '0' || start_time
 where start_time ~ '^[0-9]:';

update public.sessions
   set end_time = '0' || end_time
 where end_time ~ '^[0-9]:';
