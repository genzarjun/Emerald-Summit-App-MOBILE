-- Emerald Summit — role allowlist + enforcement (Phase 2)
-- Run this in the Supabase dashboard AFTER profiles_extend.sql,
-- disciplines_setup.sql and sessions_setup.sql.
--
-- WHY: mentor/admin are management roles. If users could self-select them we'd
-- have no gate. Instead the source of truth is two Google Sheets (mentors,
-- admins), published as CSV and copied into role_allowlist by the sync-allowlist
-- Edge Function. This file makes role_allowlist the thing the database ENFORCES:
-- a trigger on profiles refuses to grant mentor/admin unless the email is
-- allow-listed, so even a crafted API call can't self-elevate.

-- 1. Table -------------------------------------------------------------------
-- Composite PK (email, role) lets one person be listed as both a mentor and an
-- admin. `disciplines` is the mentor's scope: a list of discipline ids, or the
-- single sentinel '*' meaning "every discipline". Admins are global (ignored).
create table if not exists public.role_allowlist (
  email       text not null,
  role        text not null check (role in ('mentor', 'admin')),
  disciplines text[] not null default '{}',
  updated_at  timestamptz not null default now(),
  primary key (email, role)
);

-- 2. Row Level Security ------------------------------------------------------
-- An authenticated user may read only their OWN allowlist rows, so the app can
-- show the "you aren't eligible" message and learn its scope — without exposing
-- the whole roster. Only the sync Edge Function (service role, bypasses RLS)
-- writes; there is deliberately no write policy.
alter table public.role_allowlist enable row level security;

drop policy if exists "Read own allowlist" on public.role_allowlist;
create policy "Read own allowlist"
  on public.role_allowlist for select
  to authenticated
  using (lower(email) = lower(auth.email()));

grant select on public.role_allowlist to authenticated;
-- The sync Edge Function writes via the service role. service_role bypasses RLS
-- but still needs table privileges, and this project's "auto-expose new tables"
-- is OFF, so grant them explicitly (otherwise the sync gets "permission denied").
grant select, insert, update, delete on public.role_allowlist to service_role;

-- 3. Authorization helpers ---------------------------------------------------
-- SECURITY DEFINER so they can read profiles from inside RLS policies without
-- tripping recursive RLS. is_admin() = caller is a global admin.
create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.profiles
     where id = auth.uid() and role = 'admin'
  );
$$;

-- can_manage_discipline(id) = caller may manage content in that discipline:
-- any admin, or a mentor scoped to it (or holding the '*' wildcard).
create or replace function public.can_manage_discipline(p_discipline_id text)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.profiles
     where id = auth.uid()
       and (
         role = 'admin'
         or (role = 'mentor'
             and (managed_disciplines @> array['*']
                  or managed_disciplines @> array[p_discipline_id]))
       )
  );
$$;

grant execute on function public.is_admin() to authenticated;
grant execute on function public.can_manage_discipline(text) to authenticated;

-- 4. Enforcement trigger on profiles ----------------------------------------
-- The real gate. On every insert/update of a profile it validates the role
-- against role_allowlist and owns managed_disciplines:
--   * mentor/admin NOT allow-listed  → forced back to 'participant', scope cleared
--   * mentor allow-listed            → scope set from the sheet (or '*')
--   * admin allow-listed             → scope cleared (admins are global)
--   * any non-elevated role          → scope cleared
-- Because it recomputes on UPDATE too, re-touching a profile (see the reconcile
-- trigger) is enough to demote someone who was removed from a sheet.
create or replace function public.enforce_role_allowlist()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_email text;
  v_allow public.role_allowlist%rowtype;
begin
  v_email := lower(coalesce(new.email,
                            (select email from auth.users where id = new.id)));

  if new.role in ('mentor', 'admin') then
    select * into v_allow from public.role_allowlist
      where lower(email) = v_email and role = new.role;
    if not found then
      new.role := 'participant';
      new.managed_disciplines := '{}';
    elsif new.role = 'mentor' then
      new.managed_disciplines := coalesce(v_allow.disciplines, '{}');
    else
      new.managed_disciplines := '{}';   -- admin: global
    end if;
  else
    new.managed_disciplines := '{}';
  end if;

  return new;
end;
$$;

drop trigger if exists profiles_enforce_role on public.profiles;
create trigger profiles_enforce_role
  before insert or update on public.profiles
  for each row execute function public.enforce_role_allowlist();

-- 5. Reconcile trigger on role_allowlist ------------------------------------
-- When the sync changes/removes an allowlist row, re-touch any existing profile
-- with that email so the enforcement trigger re-runs — promoting scope changes
-- and DEMOTING anyone dropped from a sheet on the next sync.
create or replace function public.reconcile_profiles_from_allowlist()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_email text := lower(coalesce(new.email, old.email));
begin
  update public.profiles set updated_at = now()
    where lower(email) = v_email;
  return null;
end;
$$;

drop trigger if exists allowlist_reconcile on public.role_allowlist;
create trigger allowlist_reconcile
  after insert or update or delete on public.role_allowlist
  for each row execute function public.reconcile_profiles_from_allowlist();

-- 6. Manager write policies (now that the helpers exist) ---------------------
-- Admins manage the discipline catalog.
drop policy if exists "Admins write disciplines" on public.disciplines;
create policy "Admins write disciplines"
  on public.disciplines for all
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());
grant insert, update, delete on public.disciplines to authenticated;

-- Admins (any) or mentors scoped to the discipline manage its sessions.
drop policy if exists "Managers write sessions" on public.sessions;
create policy "Managers write sessions"
  on public.sessions for all
  to authenticated
  using (public.can_manage_discipline(discipline_id))
  with check (public.can_manage_discipline(discipline_id));
grant insert, update, delete on public.sessions to authenticated;
