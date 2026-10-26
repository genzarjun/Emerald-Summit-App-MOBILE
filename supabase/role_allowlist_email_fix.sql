-- Emerald Summit — allowlist check uses the sign-in email
-- Run in the Supabase dashboard AFTER expert_approval.sql. Safe to re-run.
--
-- enforce_role_allowlist matched the volunteer/admin allowlist on
-- profiles.email. "Users update own profile" lets anyone write every column of
-- their own row, so a signed-in user could set that email to an admin's
-- address, ask for role 'admin', and keep it. The trigger now reads the email
-- from auth.users and copies it onto profiles.email, so the copy shown on
-- rosters and check-in can't be faked either. Everything else is unchanged
-- from expert_approval.sql.

create or replace function public.enforce_role_allowlist()
returns trigger language plpgsql security definer set search_path = public as $function$
declare
  v_auth_email text;
  v_email text;
  v_allow public.role_allowlist%rowtype;
  v_is_ambassador boolean;
begin
  -- Match the allowlist on the email the account signed in with. A user can
  -- write their own profiles row, including its email copy, so that copy is
  -- never trusted and is pinned to the sign-in email on every write.
  select email into v_auth_email from auth.users where id = new.id;
  if v_auth_email is not null then
    new.email := v_auth_email;
  end if;
  v_email := lower(v_auth_email);

  -- Default: clear all volunteer state; specific branches re-populate it.
  new.managed_disciplines    := '{}';
  new.volunteer_subtype      := null;
  new.can_edit_sessions      := false;
  new.can_post_announcements := false;
  new.can_check_in_front_desk := false;

  if new.role in ('volunteer', 'admin') then
    select * into v_allow from public.role_allowlist
      where lower(email) = v_email and role = new.role;

    if not found then
      new.role := 'participant';
    elsif new.role = 'volunteer' then
      new.volunteer_subtype   := v_allow.subtype;
      new.managed_disciplines := coalesce(v_allow.disciplines, '{}');
      v_is_ambassador := (v_allow.subtype = 'eaf_ambassador');
      -- Subtype default: only ambassadors edit sessions; parents/students don't.
      -- Announcements + front-desk are opt-in per person (default false).
      new.can_edit_sessions       := coalesce(v_allow.can_edit_sessions, v_is_ambassador);
      new.can_post_announcements  := coalesce(v_allow.can_post_announcements, false);
      new.can_check_in_front_desk := coalesce(v_allow.can_check_in_front_desk, false);
    end if;
    -- admin: everything stays cleared (global; app grants implicitly).
  end if;

  -- Expert approval. Only review_expert() and acknowledge_expert_decline()
  -- change expert_status on purpose: they turn app.expert_review on for their
  -- own update. Any other write (sign-up, Edit profile, a crafted API call)
  -- keeps the status or resets it here, so nobody can approve themselves.
  if coalesce(current_setting('app.expert_review', true), '') <> 'on' then
    if new.role = 'expert' then
      if tg_op = 'UPDATE' and old.role = 'expert'
         and old.expert_status in ('pending', 'approved') then
        new.expert_status       := old.expert_status;
        new.expert_requested_at := old.expert_requested_at;
      else
        new.expert_status       := 'pending';
        new.expert_requested_at := now();
      end if;
    else
      -- Not an expert. A 'declined' status stays until the person has seen
      -- the note about it (acknowledge_expert_decline); anything else clears.
      new.expert_status := case
        when tg_op = 'UPDATE' and old.expert_status = 'declined' then 'declined'
      end;
      new.expert_requested_at := null;
    end if;
  end if;

  return new;
end;
$function$;
