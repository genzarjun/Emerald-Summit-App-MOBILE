-- Emerald Summit — expert BeAMentor clearance (Nov 21, 2026)
--
-- Run after role_change_downgrades.sql and code_of_conduct.sql. Safe to re-run.
--
-- The new expert flow (website first; the app is on its to-do list):
--   sign in → details (photo, title, company, expertise, bio) → Guest Expert
--   Policy → BeAMentor step: the expert ticks "I have submitted my BeAMentor
--   application" → full access, with a "waiting to be verified" banner →
--   an admin checks BeAMentor and presses Verify → the expert gets a notice.
--
-- What the columns mean from here on:
--   expert_status = 'approved'   the expert can use the app (they ticked
--                                BeAMentor, or an admin verified them)
--   beamentor_submitted_at       when they ticked the BeAMentor box
--   beamentor_verified_at        when an admin verified their clearance
--   beamentor_verified_by        which admin
-- So register_for_session and session_experts (which check 'approved') need
-- no change: ticking the box gives full access, as decided on Nov 20, 2026.
--
-- Title, company and photo_url are keys in profiles.details, like expertise
-- and bio. Photos go in the public expert_photos bucket, one folder per user.

-- 1. Columns ------------------------------------------------------------------
alter table public.profiles
  add column if not exists beamentor_submitted_at timestamptz,
  add column if not exists beamentor_verified_at timestamptz,
  add column if not exists beamentor_verified_by uuid references auth.users(id) on delete set null;

-- 2. Nobody sets these on their own profile -------------------------------------
-- Only mark_beamentor_submitted() and review_expert() change them; they turn
-- app.expert_review on for their own update (the same switch the role trigger
-- uses for expert_status). Any other write keeps the old values.
create or replace function public.profiles_guard_beamentor()
returns trigger language plpgsql as $$
begin
  if coalesce(current_setting('app.expert_review', true), '') <> 'on' then
    if tg_op = 'INSERT' then
      new.beamentor_submitted_at := null;
      new.beamentor_verified_at  := null;
      new.beamentor_verified_by  := null;
    else
      new.beamentor_submitted_at := old.beamentor_submitted_at;
      new.beamentor_verified_at  := old.beamentor_verified_at;
      new.beamentor_verified_by  := old.beamentor_verified_by;
    end if;
  end if;
  -- Someone who stops being an expert starts over if they come back.
  if new.role is distinct from 'expert' then
    new.beamentor_submitted_at := null;
    new.beamentor_verified_at  := null;
    new.beamentor_verified_by  := null;
  end if;
  return new;
end;
$$;

drop trigger if exists profiles_guard_beamentor on public.profiles;
create trigger profiles_guard_beamentor
  before insert or update on public.profiles
  for each row execute function public.profiles_guard_beamentor();

-- 3. The expert ticks the box ----------------------------------------------------
create or replace function public.mark_beamentor_submitted()
returns timestamptz language plpgsql security definer set search_path = public as $$
declare
  v_row public.profiles%rowtype;
  v_at  timestamptz := now();
begin
  if auth.uid() is null then
    raise exception 'not_signed_in';
  end if;
  select * into v_row from public.profiles where id = auth.uid() for update;
  if not found or v_row.role <> 'expert'
     or v_row.expert_status not in ('pending', 'approved') then
    raise exception 'not_an_expert';
  end if;
  if v_row.beamentor_submitted_at is not null then
    return v_row.beamentor_submitted_at;
  end if;

  perform set_config('app.expert_review', 'on', true);
  update public.profiles
     set beamentor_submitted_at = v_at,
         expert_status = 'approved'
   where id = auth.uid();
  perform set_config('app.expert_review', '', true);
  return v_at;
end;
$$;

revoke all on function public.mark_beamentor_submitted() from public, anon;
grant execute on function public.mark_beamentor_submitted() to authenticated;

-- 4. review_expert: Verify (approve) or Decline -----------------------------------
-- Same name and arguments as before, so the app's approvals screen keeps
-- working. Verifying sets beamentor_verified_at and sends the expert a notice.
-- Works on any expert not yet verified, whether or not they ticked the box.
create or replace function public.review_expert(p_user_id uuid,
                                                p_approve boolean)
returns text language plpgsql security definer set search_path = public as $$
declare
  v_row public.profiles%rowtype;
begin
  if not public.is_admin() then
    raise exception 'Only admins can review experts';
  end if;
  select * into v_row from public.profiles where id = p_user_id for update;
  if not found or v_row.role <> 'expert'
     or v_row.expert_status not in ('pending', 'approved')
     or v_row.beamentor_verified_at is not null then
    return 'not_pending';
  end if;

  perform set_config('app.expert_review', 'on', true);
  if p_approve then
    update public.profiles
       set expert_status = 'approved',
           beamentor_verified_at = now(),
           beamentor_verified_by = auth.uid()
     where id = p_user_id;
    insert into public.announcements
      (title, body, author, audience, pinned, discipline_id, created_by,
       target_user_id)
    values ('Your BeAMentor clearance is verified',
            'A Summit organizer checked your BeAMentor clearance. You are all set for Emerald Summit ''27.',
            'Emerald Summit', 'Personal', false, null, auth.uid(), p_user_id);
  else
    -- The role change moves any expert sign-ups to spectating.
    update public.profiles
       set role = 'participant', expert_status = 'declined',
           expert_requested_at = null
     where id = p_user_id;
  end if;
  perform set_config('app.expert_review', '', true);

  return case when p_approve then 'approved' else 'declined' end;
end;
$$;

grant execute on function public.review_expert(uuid, boolean) to authenticated;

-- 5. The admin dashboard ----------------------------------------------------------
-- Every expert in the app (ticked BeAMentor), for the website's Not verified /
-- Verified tabs.
create or replace function public.fetch_expert_dashboard()
returns table (
  user_id uuid,
  full_name text,
  email text,
  details jsonb,
  onboarded boolean,
  requested_at timestamptz,
  beamentor_submitted_at timestamptz,
  beamentor_verified_at timestamptz,
  verified_by_name text
) language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then
    raise exception 'Only admins can see the expert dashboard';
  end if;
  return query
    select p.id, p.full_name, p.email, coalesce(p.details, '{}'::jsonb),
           coalesce(p.onboarded, false), p.expert_requested_at,
           p.beamentor_submitted_at, p.beamentor_verified_at, v.full_name
      from public.profiles p
      left join public.profiles v on v.id = p.beamentor_verified_by
     where p.role = 'expert' and p.expert_status in ('pending', 'approved')
       -- Only experts in the app: they ticked BeAMentor (or were verified).
       -- Two states on the dashboard: verified or not.
       and (p.beamentor_submitted_at is not null or p.beamentor_verified_at is not null)
     order by coalesce(p.beamentor_submitted_at, p.expert_requested_at) desc nulls last;
end;
$$;

revoke all on function public.fetch_expert_dashboard() from public, anon;
grant execute on function public.fetch_expert_dashboard() to authenticated;

-- 6. The admins' rolling notice now counts experts waiting for verification -------
create or replace function public.refresh_expert_queue_notice(p_new boolean)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_old_title constant text := 'Experts waiting for approval';
  v_title constant text := 'Experts waiting for verification';
  v_count int;
  v_body  text;
begin
  delete from public.announcements
   where title = v_old_title and audience = 'Personal';

  select count(*) into v_count from public.profiles
   where role = 'expert' and beamentor_submitted_at is not null
     and beamentor_verified_at is null;

  if v_count = 0 then
    delete from public.announcements
     where title = v_title and audience = 'Personal';
    return;
  end if;

  v_body := case when v_count = 1
    then '1 expert submitted BeAMentor and is waiting to be verified.'
    else format('%s experts submitted BeAMentor and are waiting to be verified.', v_count)
  end || ' Verify them in Profile, under Expert verification.';

  if p_new or not exists (select 1 from public.announcements
                           where title = v_title and audience = 'Personal') then
    delete from public.announcements
     where title = v_title and audience = 'Personal';
    insert into public.announcements
      (title, body, author, audience, pinned, discipline_id, created_by,
       target_user_id)
    select v_title, v_body, 'Emerald Summit', 'Personal', false, null, null,
           a.id
      from public.profiles a
     where a.role = 'admin';
  else
    update public.announcements set body = v_body
     where title = v_title and audience = 'Personal';
  end if;
end;
$$;

revoke execute on function public.refresh_expert_queue_notice(boolean)
  from public, anon, authenticated;

create or replace function public.profiles_expert_queue_notice()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_was boolean := tg_op = 'UPDATE' and old.role = 'expert'
                   and old.beamentor_submitted_at is not null
                   and old.beamentor_verified_at is null;
  v_is  boolean := new.role = 'expert'
                   and new.beamentor_submitted_at is not null
                   and new.beamentor_verified_at is null;
begin
  if v_is and not v_was then
    perform public.refresh_expert_queue_notice(true);
  elsif v_was and not v_is then
    perform public.refresh_expert_queue_notice(false);
  end if;
  return null;
end;
$$;

drop trigger if exists profiles_expert_queue_notice on public.profiles;
create trigger profiles_expert_queue_notice
  after insert or update of role, expert_status, beamentor_submitted_at,
    beamentor_verified_at on public.profiles
  for each row execute function public.profiles_expert_queue_notice();

select public.refresh_expert_queue_notice(false);

-- 7. Expert photos -----------------------------------------------------------------
-- Public read (the photo shows on the experts list); each person writes only
-- their own folder: expert_photos/<user id>/<file>.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('expert_photos', 'expert_photos', true, 5242880,
        array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update
  set public = true,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Own folder write expert_photos" on storage.objects;
create policy "Own folder write expert_photos"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'expert_photos'
              and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "Own folder update expert_photos" on storage.objects;
create policy "Own folder update expert_photos"
  on storage.objects for update to authenticated
  using (bucket_id = 'expert_photos'
         and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "Own folder delete expert_photos" on storage.objects;
create policy "Own folder delete expert_photos"
  on storage.objects for delete to authenticated
  using (bucket_id = 'expert_photos'
         and (storage.foldername(name))[1] = auth.uid()::text);

-- Listing your own folder, so an old photo can be removed when you replace it.
drop policy if exists "Own folder read expert_photos" on storage.objects;
create policy "Own folder read expert_photos"
  on storage.objects for select to authenticated
  using (bucket_id = 'expert_photos'
         and (storage.foldername(name))[1] = auth.uid()::text);
