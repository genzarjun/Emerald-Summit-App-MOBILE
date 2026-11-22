-- Emerald Summit: the 5-minute sheet sync stops rewriting unchanged rows.
-- Run AFTER role_allowlist_setup.sql, role_allowlist_v2.sql and
-- activity_log_more.sql. Safe to re-run.
--
-- sync-allowlist upserts every row from both Google Sheets every 5 minutes,
-- each with a fresh updated_at. Before this file, every one of those rewrites
-- fired allowlist_reconcile, which touched the matching profile, which ran
-- the profile triggers (enforce_role_allowlist, activity log, hours sheet,
-- expert queue...). With ~40 rows that was ~80 row writes and a few hundred
-- trigger calls every 5 minutes, all of them no-ops, and it was the costliest
-- thing our own code did in the database.
--
-- This BEFORE UPDATE trigger drops an update when nothing that matters
-- changed (only updated_at differs). The row is left as it was, so no AFTER
-- trigger runs and nothing is written. A real change from the sheet (subtype,
-- disciplines or a permission column) still goes through exactly as before,
-- and inserts and deletes are untouched. updated_at now means "last real
-- change" instead of "last sync".

create or replace function public.role_allowlist_skip_unchanged()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if (old.email, old.role, old.subtype, old.disciplines, old.can_edit_sessions,
      old.can_post_announcements, old.can_check_in_front_desk)
     is not distinct from
     (new.email, new.role, new.subtype, new.disciplines, new.can_edit_sessions,
      new.can_post_announcements, new.can_check_in_front_desk) then
    return null; -- skip this row's update
  end if;
  return new;
end;
$$;

drop trigger if exists role_allowlist_skip_unchanged on public.role_allowlist;
create trigger role_allowlist_skip_unchanged
  before update on public.role_allowlist
  for each row execute function public.role_allowlist_skip_unchanged();
