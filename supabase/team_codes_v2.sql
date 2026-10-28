-- Emerald Summit — harder-to-guess team codes, and a cap on wrong guesses
-- Run AFTER teams_ownership_setup.sql and hours_sheet_sync.sql (it reuses the
-- `private` schema). Needs pgcrypto (in the `extensions` schema on Supabase).
-- Safe to re-run.
--
--  1. new_team_code: the discipline prefix plus 6 characters from
--     gen_random_bytes, drawn from 31 letters and digits that can't be
--     misread (no 0, O, 1, I or L). About 887 million codes per prefix,
--     against 10,000 before, and the old ones came from random(), which isn't
--     meant for secrets. Codes already issued keep working.
--  2. find_team counts lookups that match no team. After 10 in 15 minutes it
--     answers 'too_many_tries' until older misses age out. Codes that exist
--     (even for another session) don't count, so a typo or two never locks
--     anyone out. Older app builds show 'too_many_tries' as "not found".
--     find_team becomes VOLATILE because it now writes; the app calls it with
--     POST, which is what supabase_flutter's rpc() does.
--
-- normalize_team_code (strip spaces, upper-case) already accepts the new codes,
-- and so does the app's code field (free text, upper-cased as you type).

-- 1. New codes --------------------------------------------------------------
create or replace function public.new_team_code(p_prefix text)
returns text
language plpgsql volatile security definer set search_path = public as $$
declare
  c_chars constant text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  c_len   constant int  := 6;
  v_code  text;
  v_bytes bytea;
  v_b     int;
begin
  loop
    v_code := p_prefix;
    while length(v_code) < length(p_prefix) + c_len loop
      v_bytes := extensions.gen_random_bytes(16);
      for i in 0..15 loop
        v_b := get_byte(v_bytes, i);
        -- 248 = 31 * 8. Skipping 248..255 keeps every character equally likely.
        if v_b < 248 and length(v_code) < length(p_prefix) + c_len then
          v_code := v_code || substr(c_chars, v_b % 31 + 1, 1);
        end if;
      end loop;
    end loop;
    exit when not exists (select 1 from public.teams where code = v_code);
  end loop;
  return v_code;
end;
$$;

-- 2. Wrong-guess cap --------------------------------------------------------
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create table if not exists private.team_code_misses (
  user_id   uuid        not null,
  missed_at timestamptz not null default now()
);
create index if not exists team_code_misses_user_time
  on private.team_code_misses (user_id, missed_at);
-- Second lock behind the unexposed schema; find_team runs as the owner.
alter table private.team_code_misses enable row level security;

-- Same as teams_ownership_setup.sql, plus the miss check at the top and the
-- miss record on not_found.
create or replace function public.find_team(p_session_id uuid, p_code text)
returns jsonb
language plpgsql
volatile security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_team   public.teams%rowtype;
  v_count  int;
  v_max    int;
  v_misses int;
begin
  if v_uid is null then
    raise exception 'Not authenticated';
  end if;
  select count(*) into v_misses from private.team_code_misses
   where user_id = v_uid and missed_at > now() - interval '15 minutes';
  if v_misses >= 10 then
    return jsonb_build_object('outcome', 'too_many_tries');
  end if;
  select * into v_team from public.teams
   where code = public.normalize_team_code(p_code);
  if not found then
    insert into private.team_code_misses (user_id) values (v_uid);
    delete from private.team_code_misses
     where user_id = v_uid and missed_at < now() - interval '1 day';
    return jsonb_build_object('outcome', 'not_found');
  end if;
  if v_team.session_id <> p_session_id then
    return jsonb_build_object(
      'outcome', 'wrong_session',
      'session_title',
      (select title from public.sessions where id = v_team.session_id));
  end if;
  if v_uid = any(v_team.removed_user_ids) then
    return jsonb_build_object('outcome', 'removed',
                              'project_name', v_team.project_name);
  end if;
  select count(*) into v_count from public.registrations
   where team_id = v_team.id;
  select max_team_size into v_max from public.sessions where id = p_session_id;
  if v_max < 2 then
    return jsonb_build_object('outcome', 'teams_not_allowed');
  end if;
  return jsonb_build_object(
    'outcome', case when v_count >= v_max then 'full' else 'found' end,
    'project_name', v_team.project_name,
    'member_count', v_count,
    'max_team_size', v_max);
end;
$$;
