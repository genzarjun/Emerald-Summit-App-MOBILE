-- Emerald Summit — the volunteer hub
-- Run in the Supabase dashboard AFTER session_volunteers_setup.sql. Safe to re-run.
--
-- Volunteers open "Volunteer hub" to see every other volunteer — their name,
-- whether they're a student volunteer, parent volunteer or EAF ambassador, and
-- the mobile number they gave at sign-up — so they can reach each other on
-- summit day. Volunteer sign-up tells them their number is shared this way.
--
-- profiles RLS stays own-row only. This SECURITY DEFINER function is the one
-- way in: it only answers volunteers and admins, only lists volunteers who
-- finished onboarding, and only returns name + subtype + phone (no email or
-- other details).

create or replace function public.fetch_volunteer_hub()
returns table (id uuid, full_name text, subtype text, phone text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not exists (
    select 1 from public.profiles
     where id = auth.uid() and role in ('volunteer', 'admin')
  ) then
    raise exception 'Only volunteers may open the volunteer hub';
  end if;
  return query
    select p.id, p.full_name, p.volunteer_subtype,
           nullif(trim(p.details->>'phone'), '')
      from public.profiles p
     where p.role = 'volunteer'
       and p.onboarded
       and p.id <> auth.uid()
     order by p.full_name;
end;
$$;

revoke execute on function public.fetch_volunteer_hub() from public, anon;
grant execute on function public.fetch_volunteer_hub() to authenticated;
