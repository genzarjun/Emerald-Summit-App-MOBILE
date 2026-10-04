-- Emerald Summit — "session cancelled" notices
-- Run in the Supabase dashboard AFTER team_leave_notices.sql. Safe to re-run.
--
-- When a session is deleted — directly, or because its whole discipline was
-- deleted — everyone who had it on their schedule gets a personal announcement
-- (+ in-app banner) that it was cancelled: everyone registered for it
-- (participants, spectators, experts) and the volunteers assigned to manage it.
-- The person doing the deleting isn't notified. Runs BEFORE the delete, while
-- the registrations still exist; the per-teammate "left your team" notices stay
-- silent for a deleted session (see team_leave_notices.sql), so this is the
-- one notice people get.
-- Notices leave announcements.session_id null (the session is going away).
-- They carry discipline_id only when the discipline still exists: when a whole
-- discipline is deleted, its row is already gone by the time its sessions are
-- (cascade), and pointing at it would fail the foreign key and block the
-- delete. Personal notices reach their recipient either way.

create or replace function public.notify_session_cancelled()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_disc text;
  v_when text;
begin
  -- Null when the discipline itself is being deleted (see above).
  select name into v_disc from public.disciplines where id = old.discipline_id;
  v_when := to_char(old.start_time::time, 'FMHH12:MI AM') || ' – '
         || to_char(old.end_time::time, 'FMHH12:MI AM');

  insert into public.announcements
    (title, body, author, audience, pinned, discipline_id, created_by,
     target_user_id)
  select 'Session cancelled',
         format('"%s" (%s%s) has been cancelled, so it was removed from your '
                || 'schedule.',
                old.title, v_when,
                case when v_disc is null then '' else ', ' || v_disc end),
         'Emerald Summit', 'Personal', false,
         case when v_disc is not null then old.discipline_id end, auth.uid(),
         people.user_id
    from (select user_id from public.registrations
           where session_id = old.id
          union
          select user_id from public.session_volunteers
           where session_id = old.id) people
   where people.user_id is distinct from auth.uid();
  return old;
end;
$$;

drop trigger if exists sessions_notify_cancelled on public.sessions;
create trigger sessions_notify_cancelled
  before delete on public.sessions
  for each row execute function public.notify_session_cancelled();
