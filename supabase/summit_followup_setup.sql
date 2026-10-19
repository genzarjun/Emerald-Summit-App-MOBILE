-- Emerald Summit — summit date, expert feedback, and "volunteer for EAF again?"
-- Run AFTER volunteer_hours_setup.sql and session_participation_setup.sql.
-- Safe to re-run.
--
-- 1. summit_settings: one row holding the summit date. Null until the
--    organizers confirm it. Summit-day volunteer hours only count once the
--    date is set and each session has ended, and feedback only opens after the
--    summit. Set it with:
--      update public.summit_settings set summit_date = '2027-01-23';
-- 2. expert_feedback: after the summit, each expert rates (1 to 5, plus an
--    optional comment) the app, the summit overall, and each session they
--    served in as an expert. Session feedback goes on the volunteer hours
--    sheet next to the volunteers who managed that session.
-- 3. eaf_future_interest: after the summit, volunteers and admins answer
--    "Would you like to volunteer for EAF in the future?" (yes / no).
--
-- Writes go through SECURITY DEFINER RPCs that check the role and that
-- feedback is open. Everyone reads only their own answers.

-- 1. Summit date -------------------------------------------------------------
create table if not exists public.summit_settings (
  id          boolean primary key default true check (id),
  summit_date date,
  updated_at  timestamptz not null default now()
);

insert into public.summit_settings (id) values (true) on conflict do nothing;

alter table public.summit_settings enable row level security;

drop policy if exists "Anyone reads summit settings" on public.summit_settings;
create policy "Anyone reads summit settings"
  on public.summit_settings for select
  to anon, authenticated
  using (true);

drop policy if exists "Admins edit summit settings" on public.summit_settings;
create policy "Admins edit summit settings"
  on public.summit_settings for update
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());

grant select on public.summit_settings to anon, authenticated;
grant update (summit_date) on public.summit_settings to authenticated;

-- Feedback opens once the last session of summit day has ended (Pacific time).
create or replace function public.summit_feedback_open()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((
    select (now() at time zone 'America/Los_Angeles') >=
           st.summit_date
             + coalesce((select max(s.end_time::time) from public.sessions s),
                        time '23:59')
      from public.summit_settings st
     where st.summit_date is not null
  ), false);
$$;

grant execute on function public.summit_feedback_open() to anon, authenticated;

-- One call for the app: the date (or null) and whether feedback is open.
create or replace function public.fetch_summit_status()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'summit_date', (select summit_date from public.summit_settings),
    'feedback_open', public.summit_feedback_open()
  );
$$;

grant execute on function public.fetch_summit_status() to anon, authenticated;

-- 2. Expert feedback ---------------------------------------------------------
create table if not exists public.expert_feedback (
  id          uuid primary key default gen_random_uuid(),
  expert_id   uuid not null references auth.users (id) on delete cascade,
  kind        text not null check (kind in ('app', 'summit', 'session')),
  session_id  uuid references public.sessions (id) on delete cascade,
  rating      smallint not null check (rating between 1 and 5),
  comment     text not null default '' check (char_length(comment) <= 1000),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  constraint expert_feedback_session check ((kind = 'session') = (session_id is not null))
);

-- One answer per expert per kind (and per session for session feedback).
create unique index if not exists expert_feedback_one_each
  on public.expert_feedback (
    expert_id, kind,
    coalesce(session_id, '00000000-0000-0000-0000-000000000000'::uuid));

alter table public.expert_feedback enable row level security;

drop policy if exists "Experts read own feedback" on public.expert_feedback;
create policy "Experts read own feedback"
  on public.expert_feedback for select
  to authenticated
  using (expert_id = auth.uid() or public.is_admin());

grant select on public.expert_feedback to authenticated;

-- Saves the caller's feedback. p_items is a json array of
--   { "kind": "app"|"summit"|"session", "session_id": uuid|null,
--     "rating": 1..5, "comment": text }
-- Replaces any earlier answer for the same kind/session, so experts can edit.
create or replace function public.submit_expert_feedback(p_items jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_item    jsonb;
  v_kind    text;
  v_session uuid;
begin
  if not exists (select 1 from public.profiles
                  where id = auth.uid() and role = 'expert') then
    raise exception 'Only experts give summit feedback';
  end if;
  if not public.summit_feedback_open() then
    raise exception 'Feedback opens after the summit';
  end if;

  for v_item in select * from jsonb_array_elements(p_items) loop
    v_kind := v_item->>'kind';
    v_session := nullif(v_item->>'session_id', '')::uuid;
    if v_kind = 'session' and not exists (
      select 1 from public.registrations r
       where r.user_id = auth.uid() and r.session_id = v_session
         and r.participation_type = 'expert'
    ) then
      raise exception 'You can only rate sessions you served in as an expert';
    end if;

    delete from public.expert_feedback
     where expert_id = auth.uid() and kind = v_kind
       and session_id is not distinct from v_session;
    insert into public.expert_feedback (expert_id, kind, session_id, rating, comment)
      values (auth.uid(), v_kind, v_session,
              (v_item->>'rating')::smallint,
              trim(coalesce(v_item->>'comment', '')));
  end loop;
end;
$$;

revoke execute on function public.submit_expert_feedback(jsonb) from public, anon;
grant execute on function public.submit_expert_feedback(jsonb) to authenticated;

-- 3. Volunteer for EAF again? ------------------------------------------------
create table if not exists public.eaf_future_interest (
  user_id            uuid primary key references auth.users (id) on delete cascade,
  wants_to_volunteer boolean not null,
  answered_at        timestamptz not null default now()
);

alter table public.eaf_future_interest enable row level security;

drop policy if exists "Read own EAF interest" on public.eaf_future_interest;
create policy "Read own EAF interest"
  on public.eaf_future_interest for select
  to authenticated
  using (user_id = auth.uid() or public.is_admin());

grant select on public.eaf_future_interest to authenticated;

create or replace function public.set_eaf_future_interest(p_yes boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_volunteer_or_admin() then
    raise exception 'Only volunteers and admins answer this';
  end if;
  if not public.summit_feedback_open() then
    raise exception 'This opens after the summit';
  end if;
  insert into public.eaf_future_interest (user_id, wants_to_volunteer)
    values (auth.uid(), p_yes)
  on conflict (user_id) do update
    set wants_to_volunteer = excluded.wants_to_volunteer,
        answered_at = now();
end;
$$;

revoke execute on function public.set_eaf_future_interest(boolean) from public, anon;
grant execute on function public.set_eaf_future_interest(boolean) to authenticated;
