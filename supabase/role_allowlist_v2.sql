-- Emerald Summit — volunteer allowlist columns + enforcement rewrite
-- Run AFTER rename_mentor_to_volunteer.sql and profiles_capabilities.sql.
-- Supersedes the enforcement trigger + helpers from role_allowlist_setup.sql.
--
-- The Google "Volunteers" sheet now carries, per email:
--   subtype                 eaf_ambassador | parent_volunteer | student_volunteer
--   disciplines             edit scope (ids, or '*') — mainly ambassadors
--   can_edit_sessions       TRUE/FALSE/blank  (blank = subtype default)
--   can_post_announcements  TRUE/FALSE/blank
--   can_check_in_front_desk TRUE/FALSE/blank
-- These land in role_allowlist and the trigger copies them onto the profile,
-- applying subtype defaults where the sheet left a cell blank (NULL).

-- 1. New allowlist columns ---------------------------------------------------
-- Booleans are NULLABLE on purpose: NULL = "sheet cell blank, use the subtype
-- default"; TRUE/FALSE = an explicit override.
alter table public.role_allowlist
  add column if not exists subtype                  text,
  add column if not exists can_edit_sessions        boolean,
  add column if not exists can_post_announcements   boolean,
  add column if not exists can_check_in_front_desk  boolean;

-- 2. Enforcement trigger (rewrite) -------------------------------------------
-- On every insert/update of a profile it validates role against role_allowlist
-- and OWNS the volunteer columns:
--   * volunteer/admin NOT allow-listed → forced to 'participant', all cleared
--   * volunteer allow-listed → subtype + scope + capabilities set from the sheet
--     (blank capability cells fall back to the subtype default)
--   * admin allow-listed → global: scope + subtype cleared, capability flags
--     cleared (the app grants admins everything implicitly)
--   * any non-elevated role → everything cleared
create or replace function public.enforce_role_allowlist()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_email text;
  v_allow public.role_allowlist%rowtype;
  v_is_ambassador boolean;
begin
  v_email := lower(coalesce(new.email,
                            (select email from auth.users where id = new.id)));

  -- Default: clear all volunteer state; specific branches re-populate it.
  new.managed_disciplines    := '{}';
  new.volunteer_subtype      := null;
  new.can_edit_sessions      := false;
  new.can_post_announcements := false;
  new.can_check_in_front_desk := false;

  if new.role in ('volunteer', 'admin') then
    select * into v_allow from public.role_allowlist
      where lower(email) = v_email and role = new.role;

    if not found then
      new.role := 'participant';
    elsif new.role = 'volunteer' then
      new.volunteer_subtype   := v_allow.subtype;
      new.managed_disciplines := coalesce(v_allow.disciplines, '{}');
      v_is_ambassador := (v_allow.subtype = 'eaf_ambassador');
      -- Subtype default: only ambassadors edit sessions; parents/students don't.
      -- Announcements + front-desk are opt-in per person (default false).
      new.can_edit_sessions       := coalesce(v_allow.can_edit_sessions, v_is_ambassador);
      new.can_post_announcements  := coalesce(v_allow.can_post_announcements, false);
      new.can_check_in_front_desk := coalesce(v_allow.can_check_in_front_desk, false);
    end if;
    -- admin: everything stays cleared (global; app grants implicitly).
  end if;

  return new;
end;
$$;

-- Trigger definition is unchanged (still BEFORE INSERT/UPDATE); recreate for
-- idempotency in case this file is run on its own.
drop trigger if exists profiles_enforce_role on public.profiles;
create trigger profiles_enforce_role
  before insert or update on public.profiles
  for each row execute function public.enforce_role_allowlist();

-- 3. Authorization helpers (rewrite / add) -----------------------------------
-- can_manage_discipline(id): admin (any), or a VOLUNTEER who can edit sessions
-- AND is scoped to the discipline (or holds the '*' wildcard).
create or replace function public.can_manage_discipline(p_discipline_id text)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.profiles
     where id = auth.uid()
       and (
         role = 'admin'
         or (role = 'volunteer' and can_edit_sessions
             and (managed_disciplines @> array['*']
                  or managed_disciplines @> array[p_discipline_id]))
       )
  );
$$;

-- can_post_to_discipline(id): admin (any), or a VOLUNTEER who may post
-- announcements AND is scoped to the discipline (or the '*' wildcard).
create or replace function public.can_post_to_discipline(p_discipline_id text)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.profiles
     where id = auth.uid()
       and (
         role = 'admin'
         or (role = 'volunteer' and can_post_announcements
             and (managed_disciplines @> array['*']
                  or managed_disciplines @> array[p_discipline_id]))
       )
  );
$$;

-- can_check_in_front_desk(): admin (any), or a volunteer granted the flag.
create or replace function public.can_check_in_front_desk()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.profiles
     where id = auth.uid()
       and (role = 'admin'
            or (role = 'volunteer' and can_check_in_front_desk))
  );
$$;

grant execute on function public.can_manage_discipline(text) to authenticated;
grant execute on function public.can_post_to_discipline(text) to authenticated;
grant execute on function public.can_check_in_front_desk() to authenticated;

-- 4. Announcement write: allow scoped volunteers, not just admins -------------
-- Admins post anything; a volunteer with can_post_announcements may INSERT only
-- announcements targeting a discipline they're scoped to. Update/delete stay
-- admin-only (see announcements_write_setup.sql).
drop policy if exists "Admins insert announcements" on public.announcements;
drop policy if exists "Managers insert announcements" on public.announcements;
create policy "Managers insert announcements"
  on public.announcements for insert
  to authenticated
  with check (
    public.is_admin()
    or (discipline_id is not null
        and public.can_post_to_discipline(discipline_id))
  );
