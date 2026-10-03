-- Emerald Summit — let participants edit their registration answers later
-- Run in the Supabase dashboard AFTER session_participation_setup.sql. Safe to
-- re-run.
--
-- registrations has no UPDATE policy/grant (rows are only inserted/deleted via
-- register_for_session), so editing answers goes through this RPC. It only ever
-- touches the CALLER's own registration for the session, and only the answers
-- column — capacity, type, and attendance are untouched.
--   returns { "outcome": "updated" | "not_registered" }
create or replace function public.update_registration_answers(
  p_session_id uuid, p_answers jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'Not authenticated';
  end if;
  if p_answers is null or jsonb_typeof(p_answers) <> 'object' then
    raise exception 'Answers must be a JSON object';
  end if;

  update public.registrations
     set answers = p_answers
   where user_id = v_uid and session_id = p_session_id;
  if not found then
    return jsonb_build_object('outcome', 'not_registered');
  end if;
  return jsonb_build_object('outcome', 'updated');
end;
$$;

grant execute on function
  public.update_registration_answers(uuid, jsonb) to authenticated;
