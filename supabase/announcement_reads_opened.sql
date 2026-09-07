-- Emerald Summit — announcement "opened" state (two-tier read model)
-- Run this in the Supabase dashboard AFTER announcement_reads_setup.sql.
--
-- Adds a second tier to per-user read state:
--   * a ROW existing  = the user has SEEN the announcement (it scrolled past in
--     the News feed) — clears the red unread count.
--   * opened_at set   = the user OPENED that specific card — clears its unread
--     dot. Dots persist after the red badge is gone, Instagram-style.

-- 1. Column ------------------------------------------------------------------
alter table public.announcement_reads
  add column if not exists opened_at timestamptz;

-- 2. Allow the owner to UPDATE their row (to set opened_at via upsert) --------
drop policy if exists "Users update own read-state" on public.announcement_reads;
create policy "Users update own read-state"
  on public.announcement_reads for update
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

grant update on public.announcement_reads to authenticated;
