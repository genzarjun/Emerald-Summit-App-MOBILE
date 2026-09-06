-- Emerald Summit — seed the catalog (six disciplines + sample sessions)
-- Run this in the Supabase dashboard AFTER disciplines_setup.sql and
-- sessions_setup.sql. Safe to re-run: disciplines upsert by id, and each
-- session is inserted only if one with the same title+discipline is absent.
--
-- Ports lib/data/sample_data.dart so the app looks the same after switching to
-- the backend. NOTE: `enrolled` is now a LIVE count of registrations, so every
-- session starts at 0 registered (fully open) instead of the old fixed demo
-- numbers — that's real data, not a bug.

-- 1. Disciplines -------------------------------------------------------------
insert into public.disciplines (id, name, tagline, icon, sort_order) values
  ('techverse',  'TechVerse',  'Coding & software',        'terminal',                 1),
  ('robosphere', 'RoboSphere', 'Robotics & engineering',   'precision_manufacturing',  2),
  ('biosphere',  'BioSphere',  'Life sciences',            'biotech',                  3),
  ('novasphere', 'NovaSphere', 'Space & physics',          'rocket_launch',            4),
  ('artverse',   'ArtVerse',   'Arts & design',            'palette',                  5),
  ('mathverse',  'MathVerse',  'Mathematics & logic',      'functions',                6)
on conflict (id) do update set
  name       = excluded.name,
  tagline    = excluded.tagline,
  icon       = excluded.icon,
  sort_order = excluded.sort_order;

-- 2. Sessions ----------------------------------------------------------------
-- Helper pattern: insert one session unless it already exists.
insert into public.sessions
  (discipline_id, title, track, room, expert_name, start_time, end_time, capacity, description, sponsor)
select 'techverse', 'Intro to App Development', 'Mobile Track', 'Room 204', 'Dr. Priya Rao',
       '10:00', '10:45', 30,
       'Build your first cross-platform app and pitch it to a panel of industry mentors. Laptops provided.',
       'Sponsored by NorCal DevWorks'
where not exists (select 1 from public.sessions
                  where title = 'Intro to App Development' and discipline_id = 'techverse');

insert into public.sessions
  (discipline_id, title, track, room, expert_name, start_time, end_time, capacity, description, sponsor)
select 'techverse', 'Competitive Programming Sprint', 'Algorithms Track', 'Room 208', 'Mr. Alan Chen',
       '13:00', '14:00', 24,
       'A timed problem-solving challenge. Teams race the clock on classic algorithmic puzzles.',
       null
where not exists (select 1 from public.sessions
                  where title = 'Competitive Programming Sprint' and discipline_id = 'techverse');

insert into public.sessions
  (discipline_id, title, track, room, expert_name, start_time, end_time, capacity, description, sponsor)
select 'robosphere', 'Autonomous Robot Showcase', 'Autonomy Track', 'Gym A', 'Ms. Deepa Nair',
       '10:45', '11:45', 40,
       'Demonstrate an autonomous robot navigating an obstacle course. Judged on reliability and design.',
       null
where not exists (select 1 from public.sessions
                  where title = 'Autonomous Robot Showcase' and discipline_id = 'robosphere');

insert into public.sessions
  (discipline_id, title, track, room, expert_name, start_time, end_time, capacity, description, sponsor)
select 'biosphere', 'CRISPR & the Future of Medicine', 'Genomics Track', 'Lab 101', 'Dr. Maria Alvarez',
       '11:00', '11:45', 28,
       'An interactive session on gene editing, its promise, and the ethics that surround it.',
       null
where not exists (select 1 from public.sessions
                  where title = 'CRISPR & the Future of Medicine' and discipline_id = 'biosphere');

insert into public.sessions
  (discipline_id, title, track, room, expert_name, start_time, end_time, capacity, description, sponsor)
select 'novasphere', 'Model Rocketry Challenge', 'Aerospace Track', 'Field 2', 'Capt. John Reeves',
       '13:00', '14:00', 20,
       'Design, build, and launch a model rocket. Prizes for apogee and recovery accuracy.',
       null
where not exists (select 1 from public.sessions
                  where title = 'Model Rocketry Challenge' and discipline_id = 'novasphere');

insert into public.sessions
  (discipline_id, title, track, room, expert_name, start_time, end_time, capacity, description, sponsor)
select 'artverse', 'Digital Illustration Workshop', 'Design Track', 'Art Studio', 'Ms. Lena Park',
       '10:00', '10:45', 25,
       'Learn digital painting fundamentals and leave with a finished piece for your portfolio.',
       null
where not exists (select 1 from public.sessions
                  where title = 'Digital Illustration Workshop' and discipline_id = 'artverse');

insert into public.sessions
  (discipline_id, title, track, room, expert_name, start_time, end_time, capacity, description, sponsor)
select 'mathverse', 'Math Olympiad Relay', 'Problem Solving Track', 'Room 112', 'Dr. Samuel Osei',
       '14:15', '15:00', 32,
       'A fast-paced team relay of olympiad-style problems across algebra, geometry, and combinatorics.',
       null
where not exists (select 1 from public.sessions
                  where title = 'Math Olympiad Relay' and discipline_id = 'mathverse');
