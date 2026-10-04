-- Emerald Summit — profile details on the session roster
-- Run in the Supabase dashboard AFTER teams_ownership_setup.sql. Safe to re-run.
--
-- Session organizers (the session's assigned volunteers, admins, and editors of
-- its discipline) can tap anyone on the Participants / Experts tabs to see that
-- person's profile: their account role and the onboarding answers in
-- profiles.details (school, grade, phone, area of expertise, bio).
--
-- profiles RLS stays own-row only — nobody else can read a profile directly.
-- This only widens fetch_session_roster, which already checks the caller may
-- see this session's roster, and only returns people registered for it. So a
-- phone number is visible to the organizers of sessions that person signed up
-- for, and to no one else in the app.
--
-- Supersedes teams_ownership_setup.sql's version (adds role + details). Same
-- gate. Older app builds ignore the extra columns.

drop function if exists public.fetch_session_roster(uuid);

create or replace function public.fetch_session_roster(p_session_id uuid)
returns table (user_id uuid, full_name text, email text,
               attended boolean, attended_at timestamptz,
               participation_type text, answers jsonb,
               project_mode text, project_name text,
               team_id uuid, team_code text, is_team_owner boolean,
               role text, details jsonb)
language plpgsql stable security definer set search_path = public as $$
begin
  if not (public.is_assigned_to_session(p_session_id)
          or public.is_admin()
          or public.can_manage_discipline(
               (select discipline_id from public.sessions
                 where id = p_session_id))) then
    raise exception 'Not authorized for this session roster';
  end if;
  return query
    select p.id, p.full_name, p.email, r.attended, r.attended_at,
           r.participation_type, r.answers,
           r.project_mode, coalesce(t.project_name, r.project_name),
           t.id, t.code, coalesce(t.owner_id = r.user_id, false),
           p.role, coalesce(p.details, '{}'::jsonb)
      from public.registrations r
      join public.profiles p on p.id = r.user_id
      left join public.teams t on t.id = r.team_id
     where r.session_id = p_session_id
     order by p.full_name;
end;
$$;

grant execute on function public.fetch_session_roster(uuid) to authenticated;
