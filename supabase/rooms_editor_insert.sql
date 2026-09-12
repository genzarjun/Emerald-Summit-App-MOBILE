-- Emerald Summit — let session editors add rooms inline
-- Run AFTER rooms_setup.sql and role_allowlist_v2.sql.
--
-- WHY: when an admin OR an EAF ambassador is creating a session and the room
-- they need isn't in the catalog yet, they can add it from the room dropdown
-- without leaving the page. Admins already have full rooms write access; this
-- grants INSERT-only to volunteers who can edit sessions. UPDATE/DELETE stay
-- admin-only (the Manage rooms screen is admin-only), so an ambassador can add a
-- missing room but not rename or remove existing ones.

-- Helper: may the caller create rooms? (admin, or a session-editing volunteer)
create or replace function public.can_create_rooms()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.profiles
     where id = auth.uid()
       and (role = 'admin'
            or (role = 'volunteer' and can_edit_sessions))
  );
$$;

grant execute on function public.can_create_rooms() to authenticated;

-- Additive INSERT policy (RLS policies are OR'd, so this sits alongside the
-- admin "Admins write rooms" FOR ALL policy from rooms_setup.sql).
drop policy if exists "Session editors add rooms" on public.rooms;
create policy "Session editors add rooms"
  on public.rooms for insert
  to authenticated
  with check (public.can_create_rooms());
