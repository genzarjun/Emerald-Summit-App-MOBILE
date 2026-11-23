-- Expert cards on a track page (website, Nov 23, 2026).
--
-- When an approved expert signs up for a track, the track page shows a card
-- for them: photo, name, title, company and area of expertise, with "See more"
-- opening the whole profile (bio too). Students can't read other people's
-- profiles row by row (RLS), so this security-definer function hands back only
-- those public fields, for one track.
--
-- LinkedIn: when an expert signs up to serve in a track (and in Edit profile)
-- they choose whether to attach their LinkedIn so students can connect. The choice is saved in
-- profiles.details as linkedin_visible ('yes' or 'no') with the address in
-- details.linkedin_url. The address only comes back when the expert chose
-- 'yes'; otherwise linkedin_url is null.
--
-- session_experts (expert_approval.sql, names only) stays for the app, which
-- still reads it.
--
-- public_experts() (same day) is the Experts page: every approved expert who
-- serves in at least one track, with the same fields and the tracks they
-- serve in. Experts are told this when they pick a track ("Your profile will
-- be visible to students on the <track> page and on the Experts page").
-- The Experts page is on the public landing site, so both functions can be
-- called signed out (anon) too.
--
-- Run in the SQL editor or with `supabase db query --linked -f`. Safe to re-run.

-- The return columns gained `tracks` (every track the expert serves in, for
-- See more), so the old shape is dropped first.
drop function if exists public.session_expert_profiles(uuid);
create function public.session_expert_profiles(p_session_id uuid)
returns table (
  id uuid,
  name text,
  photo_url text,
  title text,
  company text,
  expertise text,
  bio text,
  linkedin_url text,
  tracks jsonb
)
language sql stable security definer set search_path = public as $$
  select p.id,
         btrim(p.full_name),
         nullif(btrim(coalesce(p.details->>'photo_url', '')), ''),
         nullif(btrim(coalesce(p.details->>'title', '')), ''),
         nullif(btrim(coalesce(p.details->>'company', '')), ''),
         nullif(btrim(coalesce(p.details->>'expertise', '')), ''),
         nullif(btrim(coalesce(p.details->>'bio', '')), ''),
         case when p.details->>'linkedin_visible' = 'yes'
              then nullif(btrim(coalesce(p.details->>'linkedin_url', '')), '')
         end,
         (select jsonb_agg(jsonb_build_object('id', s.id, 'title', s.title, 'discipline', s.discipline_id)
                           order by s.start_time, s.title)
            from public.registrations r2
            join public.sessions s on s.id = r2.session_id
           where r2.user_id = p.id and r2.participation_type = 'expert')
    from public.registrations r
    join public.profiles p on p.id = r.user_id
   where r.session_id = p_session_id
     and r.participation_type = 'expert'
     and p.role = 'expert' and p.expert_status = 'approved'
     and btrim(coalesce(p.full_name, '')) <> ''
   order by r.created_at;
$$;

revoke all on function public.session_expert_profiles(uuid) from public;
grant execute on function public.session_expert_profiles(uuid) to anon, authenticated;

create or replace function public.public_experts()
returns table (
  id uuid,
  name text,
  photo_url text,
  title text,
  company text,
  expertise text,
  bio text,
  linkedin_url text,
  tracks jsonb
)
language sql stable security definer set search_path = public as $$
  select p.id,
         btrim(p.full_name),
         nullif(btrim(coalesce(p.details->>'photo_url', '')), ''),
         nullif(btrim(coalesce(p.details->>'title', '')), ''),
         nullif(btrim(coalesce(p.details->>'company', '')), ''),
         nullif(btrim(coalesce(p.details->>'expertise', '')), ''),
         nullif(btrim(coalesce(p.details->>'bio', '')), ''),
         case when p.details->>'linkedin_visible' = 'yes'
              then nullif(btrim(coalesce(p.details->>'linkedin_url', '')), '')
         end,
         jsonb_agg(jsonb_build_object('id', s.id, 'title', s.title, 'discipline', s.discipline_id)
                   order by s.start_time, s.title)
    from public.profiles p
    join public.registrations r on r.user_id = p.id and r.participation_type = 'expert'
    join public.sessions s on s.id = r.session_id
   where p.role = 'expert' and p.expert_status = 'approved'
     and btrim(coalesce(p.full_name, '')) <> ''
   group by p.id
   order by lower(btrim(p.full_name));
$$;

revoke all on function public.public_experts() from public;
grant execute on function public.public_experts() to anon, authenticated;
