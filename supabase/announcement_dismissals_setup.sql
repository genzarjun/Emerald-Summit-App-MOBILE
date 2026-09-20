-- Emerald Summit — per-user announcement dismissals ("delete from my view")
-- Run this in the Supabase dashboard: SQL Editor → New query → paste → Run.
-- Run AFTER announcements_setup.sql (it references public.announcements).
--
-- One row = "this user has hidden this announcement from their OWN feed". This
-- is the swipe-left "delete from my view" action available to every user. It is
-- purely local to the user — the announcement stays in place for everyone else.
-- (Admins additionally get "delete for everyone", which hard-deletes the row via
-- the DELETE policy in announcements_write_setup.sql — no dismissal row needed.)
--
-- Read state is private to each user, so RLS scopes every row to its owner,
-- exactly like announcement_reads.

-- 1. Table -------------------------------------------------------------------
create table if not exists public.announcement_dismissals (
  user_id          uuid not null references auth.users (id) on delete cascade,
  announcement_id  uuid not null references public.announcements (id) on delete cascade,
  dismissed_at     timestamptz not null default now(),
  primary key (user_id, announcement_id)
);

create index if not exists announcement_dismissals_user_idx
  on public.announcement_dismissals (user_id);

-- 2. Row Level Security ------------------------------------------------------
-- A user may only ever see and change their OWN dismissals.
alter table public.announcement_dismissals enable row level security;

drop policy if exists "Users read own dismissals" on public.announcement_dismissals;
create policy "Users read own dismissals"
  on public.announcement_dismissals for select
  to authenticated
  using (auth.uid() = user_id);

drop policy if exists "Users insert own dismissals" on public.announcement_dismissals;
create policy "Users insert own dismissals"
  on public.announcement_dismissals for insert
  to authenticated
  with check (auth.uid() = user_id);

drop policy if exists "Users delete own dismissals" on public.announcement_dismissals;
create policy "Users delete own dismissals"
  on public.announcement_dismissals for delete
  to authenticated
  using (auth.uid() = user_id);

-- 3. Expose to the Data API --------------------------------------------------
-- "Automatically expose new tables" is OFF on this project, so grant access
-- explicitly. RLS above still governs WHICH rows each user can touch.
grant select, insert, delete on public.announcement_dismissals to authenticated;
