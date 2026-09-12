-- Emerald Summit — volunteer↔session assignments (roster + attendance gate)
-- Run AFTER rooms_setup.sql (needs sessions/registrations + is_admin()).
--
-- Admins assign volunteers (any subtype) to sessions. Being assigned to a
-- session is what lets a volunteer see that session's roster and mark its
-- attendance (attendance_setup.sql). Some volunteers are assigned to no session
-- — that's fine.

-- 1. Table -------------------------------------------------------------------
create table if not exists public.session_volunteers (
  id          uuid primary key default gen_random_uuid(),
  session_id  uuid not null references public.sessions (id) on delete cascade,
  user_id     uuid not null references auth.users (id) on delete cascade,
  assigned_by uuid references auth.users (id) on delete set null,
  created_at  timestamptz not null default now(),
  unique (session_id, user_id)
);

create index if not exists session_volunteers_session_idx
  on public.session_volunteers (session_id);
create index if not exists session_volunteers_user_idx
  on public.session_volunteers (user_id);

-- 2. Row Level Security ------------------------------------------------------
-- A volunteer may read their OWN assignments; admins read all. Writes go through
-- the admin-only RPC below (SECURITY DEFINER), so there is no direct write policy
-- for regular users — but admins keep a direct-delete path for "unassign".
alter table public.session_volunteers enable row level security;

drop policy if exists "Read own or admin assignments" on public.session_volunteers;
create policy "Read own or admin assignments"
  on public.session_volunteers for select
  to authenticated
  using (user_id = auth.uid() or public.is_admin());

drop policy if exists "Admins delete assignments" on public.session_volunteers;
create policy "Admins delete assignments"
  on public.session_volunteers for delete
  to authenticated
  using (public.is_admin());

grant select, delete on public.session_volunteers to authenticated;

-- 3. Helper: is the caller assigned to this session? -------------------------
create or replace function public.is_assigned_to_session(p_session_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.session_volunteers
     where session_id = p_session_id and user_id = auth.uid()
  );
$$;

grant execute on function public.is_assigned_to_session(uuid) to authenticated;

-- 4. RPC: assign a volunteer to a session (admin-only, conflict-guarded) ------
-- Mirrors register_for_session's overlap rule: refuse if the target session's
-- time overlaps anything the volunteer is already committed to — another
-- assignment OR their own personal registration. Returns jsonb:
--   { "outcome": "assigned" | "conflict", "conflicting_title": <text|null> }
create or replace function public.assign_volunteer_to_session(
  p_session_id uuid, p_user_id uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_sess  public.sessions%rowtype;
  v_clash text;
begin
  if not public.is_admin() then
    raise exception 'Only admins may assign volunteers';
  end if;

  -- Idempotent: already assigned → report success.
  if exists (select 1 from public.session_volunteers
             where session_id = p_session_id and user_id = p_user_id) then
    return jsonb_build_object('outcome', 'assigned');
  end if;

  select * into v_sess from public.sessions where id = p_session_id;
  if not found then
    raise exception 'Session not found';
  end if;

  -- Overlap against the volunteer's OTHER session assignments.
  select s.title into v_clash
    from public.session_volunteers sv
    join public.sessions s on s.id = sv.session_id
   where sv.user_id = p_user_id
     and s.id <> p_session_id
     and v_sess.start_time::time < s.end_time::time
     and s.start_time::time     < v_sess.end_time::time
   limit 1;

  -- Overlap against the volunteer's own personal registrations.
  if v_clash is null then
    select s.title into v_clash
      from public.registrations r
      join public.sessions s on s.id = r.session_id
     where r.user_id = p_user_id
       and s.id <> p_session_id
       and v_sess.start_time::time < s.end_time::time
       and s.start_time::time     < v_sess.end_time::time
     limit 1;
  end if;

  if v_clash is not null then
    return jsonb_build_object('outcome', 'conflict',
                              'conflicting_title', v_clash);
  end if;

  insert into public.session_volunteers (session_id, user_id, assigned_by)
    values (p_session_id, p_user_id, auth.uid());
  return jsonb_build_object('outcome', 'assigned');
end;
$$;

grant execute on function public.assign_volunteer_to_session(uuid, uuid) to authenticated;

-- 5. RPC: list volunteers assigned to a session (admin-only) ------------------
-- Joins profiles for display names — regular RLS wouldn't let an admin read
-- other users' profile rows, so this SECURITY DEFINER function does it, gated to
-- admins.
create or replace function public.fetch_session_volunteers(p_session_id uuid)
returns table (user_id uuid, full_name text, email text, subtype text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then
    raise exception 'Only admins may view session volunteers';
  end if;
  return query
    select p.id, p.full_name, p.email, p.volunteer_subtype
      from public.session_volunteers sv
      join public.profiles p on p.id = sv.user_id
     where sv.session_id = p_session_id
     order by p.full_name;
end;
$$;

grant execute on function public.fetch_session_volunteers(uuid) to authenticated;

-- 6. RPC: the volunteer directory for the assignment picker (admin-only) ------
create or replace function public.fetch_volunteers()
returns table (id uuid, full_name text, email text, subtype text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then
    raise exception 'Only admins may list volunteers';
  end if;
  return query
    select p.id, p.full_name, p.email, p.volunteer_subtype
      from public.profiles p
     where p.role = 'volunteer'
     order by p.full_name;
end;
$$;

grant execute on function public.fetch_volunteers() to authenticated;
