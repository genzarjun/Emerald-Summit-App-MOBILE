-- Expert cards on a track page (website, Nov 23, 2026).
--
-- When an approved expert signs up for a track, the track page shows a card
-- for them: photo, name, title, company and area of expertise, with "See more"
-- opening the whole profile (bio too). Students can't read other people's
-- profiles row by row (RLS), so this security-definer function hands back only
-- those public fields, for one track.
--
-- LinkedIn: at sign-up (and in Edit profile) an expert chooses whether students
-- may see their LinkedIn profile to connect with them. The choice is saved in
-- profiles.details as linkedin_visible ('yes' or 'no') with the address in
-- details.linkedin_url. The address only comes back when the expert chose
-- 'yes'; otherwise linkedin_url is null.
--
-- session_experts (expert_approval.sql, names only) stays for the app, which
-- still reads it.
--
-- Run in the SQL editor or with `supabase db query --linked -f`. Safe to re-run.

create or replace function public.session_expert_profiles(p_session_id uuid)
returns table (
  id uuid,
  name text,
  photo_url text,
  title text,
  company text,
  expertise text,
  bio text,
  linkedin_url text
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
         end
    from public.registrations r
    join public.profiles p on p.id = r.user_id
   where r.session_id = p_session_id
     and r.participation_type = 'expert'
     and p.role = 'expert' and p.expert_status = 'approved'
     and btrim(coalesce(p.full_name, '')) <> ''
   order by r.created_at;
$$;

revoke all on function public.session_expert_profiles(uuid) from public, anon;
grant execute on function public.session_expert_profiles(uuid) to authenticated;
