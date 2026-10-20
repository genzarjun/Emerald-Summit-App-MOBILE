-- Emerald Summit: admin metrics
-- Run in the Supabase dashboard AFTER role_allowlist_setup.sql (is_admin),
-- session_participation_setup.sql, and profiles_setup.sql. Safe to re-run.
--
-- fetch_summit_metrics() feeds Profile → Metrics: how many people signed up
-- from each school, their grades, and which disciplines they registered for.
-- It returns every onboarded account's role, school, and grade (no names,
-- emails, or phone numbers) plus every registration with its discipline. The
-- app does the counting.
--
-- Admins only. profiles and registrations RLS stay own-row; this runs as the
-- owner so it can count everyone, and checks is_admin() first.
--
-- Session metrics (the Metrics tab on a session) need nothing new: they use
-- fetch_session_roster, which already returns each registrant's details.

create or replace function public.fetch_summit_metrics()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then
    raise exception 'Only admins can see summit metrics';
  end if;

  return jsonb_build_object(
    'people', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', p.id,
               'role', p.role,
               'school', p.details ->> 'school',
               'grade', p.details ->> 'grade'))
        from public.profiles p
       where p.onboarded), '[]'::jsonb),
    'registrations', coalesce((
      select jsonb_agg(jsonb_build_object(
               'user_id', r.user_id,
               'session_id', r.session_id,
               'discipline_id', s.discipline_id,
               'discipline_name', d.name,
               'participation_type', r.participation_type))
        from public.registrations r
        join public.sessions s on s.id = r.session_id
        join public.disciplines d on d.id = s.discipline_id), '[]'::jsonb)
  );
end;
$$;

revoke all on function public.fetch_summit_metrics() from public, anon;
grant execute on function public.fetch_summit_metrics() to authenticated;
