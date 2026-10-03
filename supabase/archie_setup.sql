-- Emerald Summit — Archie (AI assistant) usage cap
--
-- The archie-chat Edge Function calls a paid model API on every question, so
-- each user gets a daily question budget. The function calls
-- archie_bump_usage(limit) AS THE CALLER before answering; it atomically counts
-- the question and returns false once today's count is over the limit.
--
-- Optional: without this file the function still works, just uncapped (it
-- fails open when the RPC is missing). Safe to re-run.

-- 1. Table ------------------------------------------------------------------
create table if not exists public.archie_usage (
  user_id  uuid not null references auth.users (id) on delete cascade,
  day      date not null default ((now() at time zone 'America/Los_Angeles')::date),
  count    int  not null default 0,
  primary key (user_id, day)
);

-- 2. Row Level Security -------------------------------------------------------
-- Users may read their own counters; nobody writes directly — only through the
-- SECURITY DEFINER RPC below, so the count can't be reset from the client.
alter table public.archie_usage enable row level security;

drop policy if exists "Read own archie usage" on public.archie_usage;
create policy "Read own archie usage"
  on public.archie_usage
  for select
  to authenticated
  using (user_id = auth.uid());

grant select on public.archie_usage to authenticated;

-- 3. RPC: archie_bump_usage ----------------------------------------------------
-- Counts one question for the caller (Pacific-time day) and returns whether it
-- is within p_limit. Over-limit questions are still counted, which is harmless.
create or replace function public.archie_bump_usage(p_limit int)
returns boolean
language plpgsql
security definer set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_day   date := (now() at time zone 'America/Los_Angeles')::date;
  v_count int;
begin
  if v_uid is null then
    return false;
  end if;

  insert into public.archie_usage (user_id, day, count)
  values (v_uid, v_day, 1)
  on conflict (user_id, day)
    do update set count = public.archie_usage.count + 1
  returning count into v_count;

  return v_count <= greatest(p_limit, 0);
end;
$$;

revoke all on function public.archie_bump_usage(int) from public, anon;
grant execute on function public.archie_bump_usage(int) to authenticated;
