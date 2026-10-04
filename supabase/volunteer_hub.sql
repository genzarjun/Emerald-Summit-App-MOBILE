-- Emerald Summit — the volunteer hub
-- Run in the Supabase dashboard AFTER session_volunteers_setup.sql. Safe to re-run.
--
-- Volunteers and admins open "Volunteer hub" to see everyone else on the team:
-- each person's name, whether they're a student volunteer, parent volunteer,
-- EAF ambassador or admin, and the mobile number they gave at sign-up — so
-- they can reach each other on summit day. Volunteer and admin sign-up both
-- say their number is shared this way (and both require one).
--
-- profiles RLS stays own-row only. This SECURITY DEFINER function is the one
-- way in: it only answers volunteers and admins, only lists volunteers and
-- admins who finished onboarding, and only returns name + role + subtype +
-- phone (no email or other details).

-- The return type changed (role column added), so drop the first version.
drop function if exists public.fetch_volunteer_hub();

create or replace function public.fetch_volunteer_hub()
returns table (id uuid, full_name text, role text, subtype text, phone text)
language plpgsql stable security definer set search_path = public as $$
begin
  -- Qualify every column: the OUT params (id, role, …) share their names, and
  -- an unqualified reference is ambiguous in PL/pgSQL.
  if not exists (
    select 1 from public.profiles me
     where me.id = auth.uid() and me.role in ('volunteer', 'admin')
  ) then
    raise exception 'Only volunteers and admins may open the volunteer hub';
  end if;
  return query
    select p.id, p.full_name, p.role::text, p.volunteer_subtype,
           nullif(trim(p.details->>'phone'), '')
      from public.profiles p
     where p.role in ('volunteer', 'admin')
       and p.onboarded
       and p.id <> auth.uid()
     order by (p.role = 'admin') desc, p.full_name;
end;
$$;

revoke execute on function public.fetch_volunteer_hub() from public, anon;
grant execute on function public.fetch_volunteer_hub() to authenticated;
