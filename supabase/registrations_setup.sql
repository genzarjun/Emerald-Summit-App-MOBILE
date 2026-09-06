-- Emerald Summit — registrations (the personal schedule) + the view + the RPC
-- Run this in the Supabase dashboard AFTER disciplines_setup.sql and
-- sessions_setup.sql.
--
-- One row = "this user added this session to their day". Replaces the in-memory
-- AppState._mySessionIds set, so a schedule now follows the account across
-- devices and restarts. RLS scopes every row to its owner.

-- 1. Table -------------------------------------------------------------------
create table if not exists public.registrations (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users (id) on delete cascade,
  session_id  uuid not null references public.sessions (id) on delete cascade,
  created_at  timestamptz not null default now(),
  unique (user_id, session_id)
);

create index if not exists registrations_user_idx
  on public.registrations (user_id);
create index if not exists registrations_session_idx
  on public.registrations (session_id);

-- 2. Row Level Security ------------------------------------------------------
-- A user may only ever see and change their OWN registrations. Adds/removes go
-- through the register_for_session() RPC below (which enforces capacity and
-- no time overlap), but these policies also cover direct reads and are the
-- backstop if the client ever writes directly.
alter table public.registrations enable row level security;

drop policy if exists "Users read own registrations" on public.registrations;
create policy "Users read own registrations"
  on public.registrations for select
  to authenticated
  using (auth.uid() = user_id);

drop policy if exists "Users insert own registrations" on public.registrations;
create policy "Users insert own registrations"
  on public.registrations for insert
  to authenticated
  with check (auth.uid() = user_id);

drop policy if exists "Users delete own registrations" on public.registrations;
create policy "Users delete own registrations"
  on public.registrations for delete
  to authenticated
  using (auth.uid() = user_id);

grant select, insert, delete on public.registrations to authenticated;

-- 3. View: sessions + live enrolled count + discipline name ------------------
-- The app reads THIS, not the base table, so `enrolled` is always the true
-- count (for capacity / "full" / "seats left") and the discipline name comes
-- along for display.
--
-- security_invoker = FALSE (runs as the view owner) is REQUIRED here: the count
-- subquery reads `registrations`, which is RLS-scoped per user. As an invoker
-- view, anon gets "permission denied" and an authenticated user would only
-- count their OWN registration (0/1) instead of the real total. Running as
-- owner makes the count see every registration — and the view still exposes
-- only a NUMBER, never who registered. Catalog columns are public anyway.
create or replace view public.sessions_with_counts
with (security_invoker = false) as
  select
    s.*,
    d.name as discipline_name,
    (select count(*) from public.registrations r where r.session_id = s.id)
      as enrolled
  from public.sessions s
  join public.disciplines d on d.id = s.discipline_id;

grant select on public.sessions_with_counts to anon, authenticated;

-- 4. RPC: register_for_session ----------------------------------------------
-- Server-side port of AppState.toggle(): the single trusted place that decides
-- whether a user can join a session. Toggles the caller's registration and
-- enforces the two rules from spec section 04 — no double-booking (time
-- overlap) and capacity caps — so they can't be bypassed from the client.
--
-- Returns jsonb: { "outcome": "added" | "removed" | "full" | "conflict",
--                  "conflicting_title": <text|null> }
-- mapping 1:1 to the app's AddOutcome enum.
create or replace function public.register_for_session(p_session_id uuid)
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_sess   public.sessions%rowtype;
  v_count  int;
  v_clash  text;
begin
  if v_uid is null then
    raise exception 'Not authenticated';
  end if;

  -- Already registered → toggle OFF.
  if exists (select 1 from public.registrations
             where user_id = v_uid and session_id = p_session_id) then
    delete from public.registrations
      where user_id = v_uid and session_id = p_session_id;
    return jsonb_build_object('outcome', 'removed');
  end if;

  select * into v_sess from public.sessions where id = p_session_id;
  if not found then
    raise exception 'Session not found';
  end if;

  -- Capacity cap.
  select count(*) into v_count
    from public.registrations where session_id = p_session_id;
  if v_count >= v_sess.capacity then
    return jsonb_build_object('outcome', 'full');
  end if;

  -- No double-booking: reject if it overlaps a session already in the plan.
  -- Overlap = this.start < other.end AND other.start < this.end.
  select s.title into v_clash
    from public.registrations r
    join public.sessions s on s.id = r.session_id
   where r.user_id = v_uid
     and v_sess.start_time::time < s.end_time::time
     and s.start_time::time     < v_sess.end_time::time
   limit 1;
  if v_clash is not null then
    return jsonb_build_object('outcome', 'conflict',
                              'conflicting_title', v_clash);
  end if;

  insert into public.registrations (user_id, session_id)
    values (v_uid, p_session_id);
  return jsonb_build_object('outcome', 'added');
end;
$$;

grant execute on function public.register_for_session(uuid) to authenticated;
