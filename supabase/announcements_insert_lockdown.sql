-- Emerald Summit — announcements are posted as yourself
-- Run AFTER announcement_attachments.sql. Safe to re-run.
--
-- The "Managers insert announcements" policy from role_allowlist_v2.sql only
-- checked who may post to which discipline. A volunteer who can post could
-- also, with a crafted request:
--   * set target_user_id and drop a personal notice into anyone's feed,
--   * set session_id, which the unassign RPC uses to find notices to delete,
--   * set created_by to someone else's id, and
--   * type any name into author.
--
--  1. The policy now requires created_by = auth.uid(). Personal notices
--     (target_user_id) and session-tagged notices (session_id) are admin
--     only. The app never sets either; the RPCs and triggers that post them
--     run as SECURITY DEFINER, so RLS doesn't apply to them.
--  2. A trigger sets author from the poster's profile name on every insert
--     that comes straight from the API. Inserts made inside SECURITY DEFINER
--     functions (which run as the function owner, not `authenticated`) keep
--     the author they chose, e.g. 'Summit Admin'.

-- 1. Insert policy --------------------------------------------------------------
drop policy if exists "Managers insert announcements" on public.announcements;
create policy "Managers insert announcements"
  on public.announcements for insert
  to authenticated
  with check (
    created_by = auth.uid()
    and (
      public.is_admin()
      or (discipline_id is not null
          and target_user_id is null
          and session_id is null
          and public.can_post_to_discipline(discipline_id))
    )
  );

-- 2. Author from the profile ----------------------------------------------------
-- Not SECURITY DEFINER on purpose: current_user has to be the caller's role.
-- The profile read goes through RLS, which allows a user's own row.
create or replace function public.announcement_author_from_profile()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_name text;
  v_role text;
begin
  if current_user <> 'authenticated' then
    return new;
  end if;
  select nullif(btrim(full_name), ''), role into v_name, v_role
    from public.profiles where id = auth.uid();
  new.author := coalesce(
    v_name,
    case when v_role = 'admin' then 'Summit Admin' else 'Summit Volunteer' end);
  return new;
end;
$$;

drop trigger if exists announcement_author_from_profile on public.announcements;
create trigger announcement_author_from_profile
  before insert on public.announcements
  for each row execute function public.announcement_author_from_profile();
