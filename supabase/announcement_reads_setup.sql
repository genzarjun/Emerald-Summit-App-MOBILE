-- Emerald Summit — per-user announcement read state
-- Run this in the Supabase dashboard: SQL Editor → New query → paste → Run.
-- Run AFTER announcements_setup.sql (it references public.announcements).
--
-- One row = "this user has read this announcement". Drives the per-user unread
-- badge on the News tab and the dashboard's "What's new" tile. Read state is
-- private to each user, so RLS scopes every row to its owner.

-- 1. Table -------------------------------------------------------------------
create table if not exists public.announcement_reads (
  user_id          uuid not null references auth.users (id) on delete cascade,
  announcement_id  uuid not null references public.announcements (id) on delete cascade,
  read_at          timestamptz not null default now(),
  primary key (user_id, announcement_id)
);

create index if not exists announcement_reads_user_idx
  on public.announcement_reads (user_id);

-- 2. Row Level Security ------------------------------------------------------
-- A user may only ever see and change their OWN read markers.
alter table public.announcement_reads enable row level security;

drop policy if exists "Users read own read-state" on public.announcement_reads;
create policy "Users read own read-state"
  on public.announcement_reads for select
  to authenticated
  using (auth.uid() = user_id);

drop policy if exists "Users insert own read-state" on public.announcement_reads;
create policy "Users insert own read-state"
  on public.announcement_reads for insert
  to authenticated
  with check (auth.uid() = user_id);

drop policy if exists "Users delete own read-state" on public.announcement_reads;
create policy "Users delete own read-state"
  on public.announcement_reads for delete
  to authenticated
  using (auth.uid() = user_id);

-- 3. Expose to the Data API --------------------------------------------------
-- "Automatically expose new tables" is OFF on this project, so grant access
-- explicitly. RLS above still governs WHICH rows each user can touch.
grant select, insert, delete on public.announcement_reads to authenticated;
