-- Emerald Summit: access rules check who you are once per query, not per row.
-- Run AFTER every other file in SUPABASE.md (it rewrites their policies).
-- Safe to re-run.
--
-- Postgres runs a policy's auth.uid(), auth.email(), is_admin(),
-- is_volunteer_or_admin() and can_create_rooms() again for every row it
-- checks. None of them depend on the row, so wrapping each in (select ...)
-- lets Postgres run it once per query and reuse the answer. Who can see or
-- change what is exactly the same; only the speed changes (Supabase's
-- performance advisor flags the unwrapped form as auth_rls_initplan).
--
-- alter policy keeps each policy's name, command and roles and replaces only
-- its expressions. If an older file that creates one of these policies is
-- re-run, run this file again afterwards. New policies should use the
-- (select ...) form from the start.

alter policy "Admins read activity" on public.activity_log
  using ((select public.is_admin()));

alter policy "Users delete own dismissals" on public.announcement_dismissals
  using (((select auth.uid()) = user_id));

alter policy "Users insert own dismissals" on public.announcement_dismissals
  with check (((select auth.uid()) = user_id));

alter policy "Users read own dismissals" on public.announcement_dismissals
  using (((select auth.uid()) = user_id));

alter policy "Users delete own read-state" on public.announcement_reads
  using (((select auth.uid()) = user_id));

alter policy "Users insert own read-state" on public.announcement_reads
  with check (((select auth.uid()) = user_id));

alter policy "Users read own read-state" on public.announcement_reads
  using (((select auth.uid()) = user_id));

alter policy "Users update own read-state" on public.announcement_reads
  using (((select auth.uid()) = user_id))
  with check (((select auth.uid()) = user_id));

alter policy "Admins delete announcements" on public.announcements
  using ((select public.is_admin()));

alter policy "Admins update announcements" on public.announcements
  using ((select public.is_admin()))
  with check ((select public.is_admin()));

alter policy "Authors update own announcements" on public.announcements
  using (((created_by = (select auth.uid())) AND (discipline_id IS NOT NULL) AND (target_user_id IS NULL) AND (session_id IS NULL) AND can_post_to_discipline(discipline_id)))
  with check (((created_by = (select auth.uid())) AND (discipline_id IS NOT NULL) AND (target_user_id IS NULL) AND (session_id IS NULL) AND can_post_to_discipline(discipline_id)));

alter policy "Managers insert announcements" on public.announcements
  with check (((created_by = (select auth.uid())) AND ((select public.is_admin()) OR ((discipline_id IS NOT NULL) AND (target_user_id IS NULL) AND (session_id IS NULL) AND can_post_to_discipline(discipline_id)))));

alter policy "Read announcements" on public.announcements
  using (((target_user_id IS NULL) OR (target_user_id = (select auth.uid()))));

alter policy "Own archie chats" on public.archie_chats
  using ((user_id = (select auth.uid())))
  with check ((user_id = (select auth.uid())));

alter policy "Add to own archie chats" on public.archie_messages
  with check (((user_id = (select auth.uid())) AND (EXISTS ( SELECT 1
   FROM archie_chats c
  WHERE ((c.id = archie_messages.chat_id) AND (c.user_id = (select auth.uid())))))));

alter policy "Read own archie messages" on public.archie_messages
  using ((user_id = (select auth.uid())));

alter policy "Read own archie usage" on public.archie_usage
  using ((user_id = (select auth.uid())));

alter policy "Read own reports, admins read all" on public.bug_reports
  using (((user_id = (select auth.uid())) OR (select public.is_admin())));

alter policy "Admins insert disciplines" on public.disciplines
  with check ((select public.is_admin()));

alter policy "Admins update disciplines" on public.disciplines
  using ((select public.is_admin()))
  with check ((select public.is_admin()));

alter policy "Read own EAF interest" on public.eaf_future_interest
  using (((user_id = (select auth.uid())) OR (select public.is_admin())));

alter policy "Experts read own feedback" on public.expert_feedback
  using (((expert_id = (select auth.uid())) OR (select public.is_admin())));

alter policy "Users read own notifications" on public.notifications
  using ((user_id = (select auth.uid())));

alter policy "Users insert own profile" on public.profiles
  with check (((select auth.uid()) = id));

alter policy "Users read own profile" on public.profiles
  using (((select auth.uid()) = id));

alter policy "Users update own profile" on public.profiles
  using (((select auth.uid()) = id))
  with check (((select auth.uid()) = id));

alter policy "Users delete own registrations" on public.registrations
  using (((select auth.uid()) = user_id));

alter policy "Users read own registrations" on public.registrations
  using (((select auth.uid()) = user_id));

alter policy "Read own allowlist" on public.role_allowlist
  using ((lower(email) = lower((select auth.email()))));

alter policy "Admins write rooms" on public.rooms
  using ((select public.is_admin()))
  with check ((select public.is_admin()));

alter policy "Session editors add rooms" on public.rooms
  with check ((select public.can_create_rooms()));

alter policy "Admins delete assignments" on public.session_volunteers
  using ((select public.is_admin()));

alter policy "Read own or admin assignments" on public.session_volunteers
  using (((user_id = (select auth.uid())) OR (select public.is_admin())));

alter policy "Admins delete sessions" on public.sessions
  using ((select public.is_admin()));

alter policy "Admins edit summit settings" on public.summit_settings
  using ((select public.is_admin()))
  with check ((select public.is_admin()));

alter policy "Add own hour logs" on public.volunteer_hour_logs
  with check (((user_id = (select auth.uid())) AND (select public.is_volunteer_or_admin())));

alter policy "Delete own hour logs" on public.volunteer_hour_logs
  using ((user_id = (select auth.uid())));

alter policy "Edit own hour logs" on public.volunteer_hour_logs
  using ((user_id = (select auth.uid())))
  with check (((user_id = (select auth.uid())) AND (select public.is_volunteer_or_admin())));

alter policy "Read own hour logs" on public.volunteer_hour_logs
  using ((user_id = (select auth.uid())));
