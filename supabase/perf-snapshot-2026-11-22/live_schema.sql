create table private.allowlist_sync (
  id boolean not null default true,
  function_url text not null,
  secret text not null,
  constraint allowlist_sync_id_check CHECK (id),
  constraint allowlist_sync_pkey PRIMARY KEY (id)
);
-- indexes
CREATE UNIQUE INDEX allowlist_sync_pkey ON private.allowlist_sync USING btree (id);

create table private.hours_sheet_sync (
  id boolean not null default true,
  function_url text not null,
  secret text not null,
  dirty boolean not null default true,
  last_sent_at timestamp with time zone,
  constraint hours_sheet_sync_id_check CHECK (id),
  constraint hours_sheet_sync_pkey PRIMARY KEY (id)
);
-- indexes
CREATE UNIQUE INDEX hours_sheet_sync_pkey ON private.hours_sheet_sync USING btree (id);

create table private.team_code_misses (
  user_id uuid not null,
  missed_at timestamp with time zone not null default now()
);
-- indexes
CREATE INDEX team_code_misses_user_time ON private.team_code_misses USING btree (user_id, missed_at);

create table public.activity_log (
  id bigint not null,
  at timestamp with time zone not null default now(),
  actor_id uuid,
  user_id uuid,
  action text not null,
  session_id uuid,
  details jsonb not null default '{}'::jsonb,
  constraint activity_log_pkey PRIMARY KEY (id)
);
-- indexes
CREATE UNIQUE INDEX activity_log_pkey ON public.activity_log USING btree (id);
CREATE INDEX activity_log_at_idx ON public.activity_log USING btree (at DESC);
CREATE INDEX activity_log_user_idx ON public.activity_log USING btree (user_id, at DESC);
CREATE INDEX activity_log_session_idx ON public.activity_log USING btree (session_id, at DESC);
CREATE INDEX activity_log_action_idx ON public.activity_log USING btree (action, at DESC);
-- policies
policy "Admins read activity" permissive for select to authenticated using (is_admin()) with check ();

create table public.announcement_dismissals (
  user_id uuid not null,
  announcement_id uuid not null,
  dismissed_at timestamp with time zone not null default now(),
  constraint announcement_dismissals_announcement_id_fkey FOREIGN KEY (announcement_id) REFERENCES announcements(id) ON DELETE CASCADE,
  constraint announcement_dismissals_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE,
  constraint announcement_dismissals_pkey PRIMARY KEY (user_id, announcement_id)
);
-- indexes
CREATE UNIQUE INDEX announcement_dismissals_pkey ON public.announcement_dismissals USING btree (user_id, announcement_id);
CREATE INDEX announcement_dismissals_user_idx ON public.announcement_dismissals USING btree (user_id);
-- policies
policy "Users read own dismissals" permissive for select to authenticated using ((auth.uid() = user_id)) with check ();
policy "Users insert own dismissals" permissive for insert to authenticated using () with check ((auth.uid() = user_id));
policy "Users delete own dismissals" permissive for delete to authenticated using ((auth.uid() = user_id)) with check ();

create table public.announcement_reads (
  user_id uuid not null,
  announcement_id uuid not null,
  read_at timestamp with time zone not null default now(),
  opened_at timestamp with time zone,
  constraint announcement_reads_announcement_id_fkey FOREIGN KEY (announcement_id) REFERENCES announcements(id) ON DELETE CASCADE,
  constraint announcement_reads_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE,
  constraint announcement_reads_pkey PRIMARY KEY (user_id, announcement_id)
);
-- indexes
CREATE UNIQUE INDEX announcement_reads_pkey ON public.announcement_reads USING btree (user_id, announcement_id);
CREATE INDEX announcement_reads_user_idx ON public.announcement_reads USING btree (user_id);
-- policies
policy "Users read own read-state" permissive for select to authenticated using ((auth.uid() = user_id)) with check ();
policy "Users insert own read-state" permissive for insert to authenticated using () with check ((auth.uid() = user_id));
policy "Users delete own read-state" permissive for delete to authenticated using ((auth.uid() = user_id)) with check ();
policy "Users update own read-state" permissive for update to authenticated using ((auth.uid() = user_id)) with check ((auth.uid() = user_id));

create table public.announcements (
  id uuid not null default gen_random_uuid(),
  title text not null,
  body text not null,
  author text not null default 'Summit Admin'::text,
  audience text not null default 'Everyone'::text,
  pinned boolean not null default false,
  created_at timestamp with time zone not null default now(),
  created_by uuid,
  discipline_id text,
  target_user_id uuid,
  session_id uuid,
  attachments jsonb not null default '[]'::jsonb,
  edited_at timestamp with time zone,
  constraint announcements_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL,
  constraint announcements_discipline_id_fkey FOREIGN KEY (discipline_id) REFERENCES disciplines(id) ON DELETE SET NULL,
  constraint announcements_session_id_fkey FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE SET NULL,
  constraint announcements_target_user_id_fkey FOREIGN KEY (target_user_id) REFERENCES auth.users(id) ON DELETE CASCADE,
  constraint announcements_pkey PRIMARY KEY (id)
);
-- indexes
CREATE UNIQUE INDEX announcements_pkey ON public.announcements USING btree (id);
-- policies
policy "Admins update announcements" permissive for update to authenticated using (is_admin()) with check (is_admin());
policy "Admins delete announcements" permissive for delete to authenticated using (is_admin()) with check ();
policy "Read announcements" permissive for select to authenticated,anon using (((target_user_id IS NULL) OR (target_user_id = auth.uid()))) with check ();
policy "Managers insert announcements" permissive for insert to authenticated using () with check (((created_by = auth.uid()) AND (is_admin() OR ((discipline_id IS NOT NULL) AND (target_user_id IS NULL) AND (session_id IS NULL) AND can_post_to_discipline(discipline_id)))));
policy "Authors update own announcements" permissive for update to authenticated using (((created_by = auth.uid()) AND (discipline_id IS NOT NULL) AND (target_user_id IS NULL) AND (session_id IS NULL) AND can_post_to_discipline(discipline_id))) with check (((created_by = auth.uid()) AND (discipline_id IS NOT NULL) AND (target_user_id IS NULL) AND (session_id IS NULL) AND can_post_to_discipline(discipline_id)));
-- triggers
activity_log_announcements: CREATE TRIGGER activity_log_announcements AFTER INSERT OR DELETE OR UPDATE ON public.announcements FOR EACH ROW EXECUTE FUNCTION activity_from_announcements();
announcement_author_from_profile: CREATE TRIGGER announcement_author_from_profile BEFORE INSERT ON public.announcements FOR EACH ROW EXECUTE FUNCTION announcement_author_from_profile();
announcement_edit_guard: CREATE TRIGGER announcement_edit_guard BEFORE UPDATE ON public.announcements FOR EACH ROW EXECUTE FUNCTION announcement_edit_guard();
notify_from_announcement: CREATE TRIGGER notify_from_announcement AFTER INSERT ON public.announcements FOR EACH ROW EXECUTE FUNCTION notify_from_announcement();
notify_from_announcement_update: CREATE TRIGGER notify_from_announcement_update AFTER UPDATE OF title, body ON public.announcements FOR EACH ROW EXECUTE FUNCTION notify_from_announcement_update();

create table public.archie_chats (
  id uuid not null default gen_random_uuid(),
  user_id uuid not null default auth.uid(),
  title text not null default ''::text,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  constraint archie_chats_title_check CHECK ((char_length(title) <= 120)),
  constraint archie_chats_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE,
  constraint archie_chats_pkey PRIMARY KEY (id)
);
-- indexes
CREATE UNIQUE INDEX archie_chats_pkey ON public.archie_chats USING btree (id);
CREATE INDEX archie_chats_user_recent_idx ON public.archie_chats USING btree (user_id, updated_at DESC);
-- policies
policy "Own archie chats" permissive for all to authenticated using ((user_id = auth.uid())) with check ((user_id = auth.uid()));
-- triggers
archie_chats_prune: CREATE TRIGGER archie_chats_prune AFTER INSERT ON public.archie_chats FOR EACH ROW EXECUTE FUNCTION archie_prune_chats();

create table public.archie_messages (
  id bigint not null,
  chat_id uuid not null,
  user_id uuid not null default auth.uid(),
  role text not null,
  content text not null,
  sources jsonb not null default '[]'::jsonb,
  steps jsonb not null default '[]'::jsonb,
  created_at timestamp with time zone not null default now(),
  constraint archie_messages_content_check CHECK ((char_length(content) <= 20000)),
  constraint archie_messages_role_check CHECK ((role = ANY (ARRAY['user'::text, 'assistant'::text]))),
  constraint archie_messages_chat_id_fkey FOREIGN KEY (chat_id) REFERENCES archie_chats(id) ON DELETE CASCADE,
  constraint archie_messages_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE,
  constraint archie_messages_pkey PRIMARY KEY (id)
);
-- indexes
CREATE UNIQUE INDEX archie_messages_pkey ON public.archie_messages USING btree (id);
CREATE INDEX archie_messages_chat_idx ON public.archie_messages USING btree (chat_id, id);
-- policies
policy "Read own archie messages" permissive for select to authenticated using ((user_id = auth.uid())) with check ();
policy "Add to own archie chats" permissive for insert to authenticated using () with check (((user_id = auth.uid()) AND (EXISTS ( SELECT 1
   FROM archie_chats c
  WHERE ((c.id = archie_messages.chat_id) AND (c.user_id = auth.uid()))))));
-- triggers
archie_messages_limit: CREATE TRIGGER archie_messages_limit BEFORE INSERT ON public.archie_messages FOR EACH ROW EXECUTE FUNCTION archie_enforce_chat_length();

create table public.archie_usage (
  user_id uuid not null,
  day date not null default ((now() AT TIME ZONE 'America/Los_Angeles'::text))::date,
  count integer not null default 0,
  constraint archie_usage_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE,
  constraint archie_usage_pkey PRIMARY KEY (user_id, day)
);
-- indexes
CREATE UNIQUE INDEX archie_usage_pkey ON public.archie_usage USING btree (user_id, day);
-- policies
policy "Read own archie usage" permissive for select to authenticated using ((user_id = auth.uid())) with check ();

create table public.bug_reports (
  id uuid not null,
  ticket_no bigint not null,
  user_id uuid,
  kind text not null default 'bug'::text,
  reporter_name text not null,
  description text not null,
  screenshots text[] not null default '{}'::text[],
  email_copy boolean not null default false,
  client jsonb not null default '{}'::jsonb,
  snapshot jsonb not null default '{}'::jsonb,
  status text not null default 'open'::text,
  resolved_at timestamp with time zone,
  emailed_at timestamp with time zone,
  email_error text,
  created_at timestamp with time zone not null default now(),
  constraint bug_reports_description_check CHECK (((length(btrim(description)) >= 1) AND (length(btrim(description)) <= 5000))),
  constraint bug_reports_kind_check CHECK ((kind = ANY (ARRAY['bug'::text, 'feedback'::text]))),
  constraint bug_reports_reporter_name_check CHECK (((length(btrim(reporter_name)) >= 1) AND (length(btrim(reporter_name)) <= 120))),
  constraint bug_reports_screenshots_check CHECK ((cardinality(screenshots) <= 5)),
  constraint bug_reports_status_check CHECK ((status = ANY (ARRAY['open'::text, 'resolved'::text]))),
  constraint bug_reports_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE SET NULL,
  constraint bug_reports_pkey PRIMARY KEY (id),
  constraint bug_reports_ticket_no_key UNIQUE (ticket_no)
);
-- indexes
CREATE UNIQUE INDEX bug_reports_pkey ON public.bug_reports USING btree (id);
CREATE UNIQUE INDEX bug_reports_ticket_no_key ON public.bug_reports USING btree (ticket_no);
CREATE INDEX bug_reports_user_idx ON public.bug_reports USING btree (user_id, created_at DESC);
CREATE INDEX bug_reports_status_idx ON public.bug_reports USING btree (status, created_at DESC);
-- policies
policy "Read own reports, admins read all" permissive for select to authenticated using (((user_id = auth.uid()) OR is_admin())) with check ();

create table public.dev_login_failures (
  id bigint not null,
  ip text not null,
  email text not null default ''::text,
  at timestamp with time zone not null default now(),
  constraint dev_login_failures_pkey PRIMARY KEY (id)
);
-- indexes
CREATE UNIQUE INDEX dev_login_failures_pkey ON public.dev_login_failures USING btree (id);
CREATE INDEX dev_login_failures_ip_at ON public.dev_login_failures USING btree (ip, at DESC);
CREATE INDEX dev_login_failures_at ON public.dev_login_failures USING btree (at DESC);

create table public.disciplines (
  id text not null,
  name text not null,
  tagline text not null default ''::text,
  icon text not null default 'category'::text,
  sort_order integer not null default 0,
  created_by uuid,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  constraint disciplines_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL,
  constraint disciplines_pkey PRIMARY KEY (id)
);
-- indexes
CREATE UNIQUE INDEX disciplines_pkey ON public.disciplines USING btree (id);
-- policies
policy "Public read disciplines" permissive for select to authenticated,anon using (true) with check ();
policy "Admins insert disciplines" permissive for insert to authenticated using () with check (is_admin());
policy "Admins update disciplines" permissive for update to authenticated using (is_admin()) with check (is_admin());
-- triggers
activity_log_disciplines: CREATE TRIGGER activity_log_disciplines AFTER INSERT OR DELETE OR UPDATE ON public.disciplines FOR EACH ROW EXECUTE FUNCTION activity_from_disciplines();
disciplines_touch_updated_at: CREATE TRIGGER disciplines_touch_updated_at BEFORE UPDATE ON public.disciplines FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

create table public.eaf_future_interest (
  user_id uuid not null,
  wants_to_volunteer boolean not null,
  answered_at timestamp with time zone not null default now(),
  constraint eaf_future_interest_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE,
  constraint eaf_future_interest_pkey PRIMARY KEY (user_id)
);
-- indexes
CREATE UNIQUE INDEX eaf_future_interest_pkey ON public.eaf_future_interest USING btree (user_id);
-- policies
policy "Read own EAF interest" permissive for select to authenticated using (((user_id = auth.uid()) OR is_admin())) with check ();
-- triggers
hours_sheet_dirty: CREATE TRIGGER hours_sheet_dirty AFTER INSERT OR DELETE OR UPDATE ON public.eaf_future_interest FOR EACH STATEMENT EXECUTE FUNCTION private.mark_hours_sheet_dirty();

create table public.expert_feedback (
  id uuid not null default gen_random_uuid(),
  expert_id uuid not null,
  kind text not null,
  session_id uuid,
  rating smallint not null,
  comment text not null default ''::text,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  constraint expert_feedback_comment_check CHECK ((char_length(comment) <= 1000)),
  constraint expert_feedback_kind_check CHECK ((kind = ANY (ARRAY['app'::text, 'summit'::text, 'session'::text]))),
  constraint expert_feedback_rating_check CHECK (((rating >= 1) AND (rating <= 5))),
  constraint expert_feedback_session CHECK (((kind = 'session'::text) = (session_id IS NOT NULL))),
  constraint expert_feedback_expert_id_fkey FOREIGN KEY (expert_id) REFERENCES auth.users(id) ON DELETE CASCADE,
  constraint expert_feedback_session_id_fkey FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE,
  constraint expert_feedback_pkey PRIMARY KEY (id)
);
-- indexes
CREATE UNIQUE INDEX expert_feedback_pkey ON public.expert_feedback USING btree (id);
CREATE UNIQUE INDEX expert_feedback_one_each ON public.expert_feedback USING btree (expert_id, kind, COALESCE(session_id, '00000000-0000-0000-0000-000000000000'::uuid));
-- policies
policy "Experts read own feedback" permissive for select to authenticated using (((expert_id = auth.uid()) OR is_admin())) with check ();
-- triggers
hours_sheet_dirty: CREATE TRIGGER hours_sheet_dirty AFTER INSERT OR DELETE OR UPDATE ON public.expert_feedback FOR EACH STATEMENT EXECUTE FUNCTION private.mark_hours_sheet_dirty();

create table public.notifications (
  id uuid not null default gen_random_uuid(),
  user_id uuid not null,
  kind text not null,
  title text not null,
  body text not null default ''::text,
  announcement_id uuid,
  session_id uuid,
  created_at timestamp with time zone not null default now(),
  read_at timestamp with time zone,
  constraint notifications_kind_check CHECK ((kind = ANY (ARRAY['announcement'::text, 'notice'::text, 'reminder'::text]))),
  constraint notifications_announcement_id_fkey FOREIGN KEY (announcement_id) REFERENCES announcements(id) ON DELETE CASCADE,
  constraint notifications_session_id_fkey FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE,
  constraint notifications_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE,
  constraint notifications_pkey PRIMARY KEY (id)
);
-- indexes
CREATE UNIQUE INDEX notifications_pkey ON public.notifications USING btree (id);
CREATE INDEX notifications_user_idx ON public.notifications USING btree (user_id, created_at DESC);
CREATE UNIQUE INDEX notifications_one_per_announcement ON public.notifications USING btree (user_id, announcement_id) WHERE (announcement_id IS NOT NULL);
CREATE UNIQUE INDEX notifications_one_reminder ON public.notifications USING btree (user_id, session_id) WHERE (kind = 'reminder'::text);
-- policies
policy "Users read own notifications" permissive for select to authenticated using ((user_id = auth.uid())) with check ();

create table public.profiles (
  id uuid not null,
  email text,
  full_name text not null default ''::text,
  role text not null default 'participant'::text,
  details jsonb not null default '{}'::jsonb,
  onboarded boolean not null default false,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  notifications_enabled boolean not null default true,
  volunteer_hours numeric not null default 0,
  managed_disciplines text[] not null default '{}'::text[],
  volunteer_subtype text,
  can_edit_sessions boolean not null default false,
  can_post_announcements boolean not null default false,
  can_check_in_front_desk boolean not null default false,
  expert_status text,
  expert_requested_at timestamp with time zone,
  expert_queue_seen_at timestamp with time zone,
  code_of_conduct_version text,
  code_of_conduct_agreed_at timestamp with time zone,
  photo_consent boolean,
  beamentor_submitted_at timestamp with time zone,
  beamentor_verified_at timestamp with time zone,
  beamentor_verified_by uuid,
  constraint profiles_expert_status_check CHECK ((expert_status = ANY (ARRAY['pending'::text, 'approved'::text, 'declined'::text]))),
  constraint profiles_beamentor_verified_by_fkey FOREIGN KEY (beamentor_verified_by) REFERENCES auth.users(id) ON DELETE SET NULL,
  constraint profiles_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE,
  constraint profiles_pkey PRIMARY KEY (id)
);
-- indexes
CREATE UNIQUE INDEX profiles_pkey ON public.profiles USING btree (id);
-- policies
policy "Users read own profile" permissive for select to authenticated using ((auth.uid() = id)) with check ();
policy "Users insert own profile" permissive for insert to authenticated using () with check ((auth.uid() = id));
policy "Users update own profile" permissive for update to authenticated using ((auth.uid() = id)) with check ((auth.uid() = id));
-- triggers
activity_log_profile_permissions: CREATE TRIGGER activity_log_profile_permissions AFTER UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION activity_from_profile_permissions();
activity_log_profiles: CREATE TRIGGER activity_log_profiles AFTER INSERT OR DELETE OR UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION activity_from_profiles();
hours_sheet_dirty: CREATE TRIGGER hours_sheet_dirty AFTER UPDATE ON public.profiles FOR EACH ROW WHEN ((((old.role = ANY (ARRAY['volunteer'::text, 'admin'::text])) OR (new.role = ANY (ARRAY['volunteer'::text, 'admin'::text]))) AND ((old.full_name IS DISTINCT FROM new.full_name) OR (old.email IS DISTINCT FROM new.email) OR (old.details IS DISTINCT FROM new.details) OR (old.role IS DISTINCT FROM new.role) OR (old.volunteer_subtype IS DISTINCT FROM new.volunteer_subtype)))) EXECUTE FUNCTION private.mark_hours_sheet_dirty();
profiles_enforce_role: CREATE TRIGGER profiles_enforce_role BEFORE INSERT OR UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION enforce_role_allowlist();
profiles_expert_queue_notice: CREATE TRIGGER profiles_expert_queue_notice AFTER INSERT OR UPDATE OF role, expert_status, beamentor_submitted_at, beamentor_verified_at ON public.profiles FOR EACH ROW EXECUTE FUNCTION profiles_expert_queue_notice();
profiles_guard_beamentor: CREATE TRIGGER profiles_guard_beamentor BEFORE INSERT OR UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION profiles_guard_beamentor();
profiles_role_downgrade: CREATE TRIGGER profiles_role_downgrade AFTER UPDATE OF role ON public.profiles FOR EACH ROW EXECUTE FUNCTION profiles_role_downgrade();
profiles_touch_updated_at: CREATE TRIGGER profiles_touch_updated_at BEFORE UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

create table public.registrations (
  id uuid not null default gen_random_uuid(),
  user_id uuid not null,
  session_id uuid not null,
  created_at timestamp with time zone not null default now(),
  attended boolean not null default false,
  attended_at timestamp with time zone,
  marked_by uuid,
  participation_type text not null default 'participant'::text,
  answers jsonb not null default '{}'::jsonb,
  project_mode text,
  project_name text,
  team_id uuid,
  constraint registrations_participation_type_check CHECK ((participation_type = ANY (ARRAY['participant'::text, 'spectator'::text, 'expert'::text]))),
  constraint registrations_project_mode_check CHECK (((project_mode IS NULL) OR (project_mode = ANY (ARRAY['solo'::text, 'team'::text])))),
  constraint registrations_marked_by_fkey FOREIGN KEY (marked_by) REFERENCES auth.users(id) ON DELETE SET NULL,
  constraint registrations_session_id_fkey FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE,
  constraint registrations_team_id_fkey FOREIGN KEY (team_id) REFERENCES teams(id) ON DELETE SET NULL,
  constraint registrations_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE,
  constraint registrations_pkey PRIMARY KEY (id),
  constraint registrations_user_id_session_id_key UNIQUE (user_id, session_id)
);
-- indexes
CREATE UNIQUE INDEX registrations_pkey ON public.registrations USING btree (id);
CREATE UNIQUE INDEX registrations_user_id_session_id_key ON public.registrations USING btree (user_id, session_id);
CREATE INDEX registrations_user_idx ON public.registrations USING btree (user_id);
CREATE INDEX registrations_session_idx ON public.registrations USING btree (session_id);
CREATE INDEX registrations_team_idx ON public.registrations USING btree (team_id);
-- policies
policy "Users read own registrations" permissive for select to authenticated using ((auth.uid() = user_id)) with check ();
policy "Users delete own registrations" permissive for delete to authenticated using ((auth.uid() = user_id)) with check ();
-- triggers
activity_log_registrations: CREATE TRIGGER activity_log_registrations AFTER INSERT OR DELETE OR UPDATE ON public.registrations FOR EACH ROW EXECUTE FUNCTION activity_from_registrations();
registrations_block_removed: CREATE TRIGGER registrations_block_removed BEFORE INSERT ON public.registrations FOR EACH ROW EXECUTE FUNCTION block_removed_registration();
registrations_block_removed_rejoin: CREATE TRIGGER registrations_block_removed_rejoin BEFORE INSERT OR UPDATE OF team_id ON public.registrations FOR EACH ROW EXECUTE FUNCTION block_removed_rejoin();
registrations_cleanup_team: CREATE TRIGGER registrations_cleanup_team AFTER DELETE OR UPDATE OF team_id ON public.registrations FOR EACH ROW EXECUTE FUNCTION cleanup_empty_team();
registrations_notify_expert: CREATE TRIGGER registrations_notify_expert AFTER INSERT OR UPDATE OF participation_type ON public.registrations FOR EACH ROW EXECUTE FUNCTION notify_organizers_of_expert();
registrations_notify_team_join: CREATE TRIGGER registrations_notify_team_join AFTER INSERT OR UPDATE OF team_id ON public.registrations FOR EACH ROW EXECUTE FUNCTION notify_team_join();
registrations_notify_team_leave: CREATE TRIGGER registrations_notify_team_leave AFTER DELETE OR UPDATE OF team_id ON public.registrations FOR EACH ROW EXECUTE FUNCTION notify_team_leave();

create table public.role_allowlist (
  email text not null,
  role text not null,
  disciplines text[] not null default '{}'::text[],
  updated_at timestamp with time zone not null default now(),
  subtype text,
  can_edit_sessions boolean,
  can_post_announcements boolean,
  can_check_in_front_desk boolean,
  constraint role_allowlist_role_check CHECK ((role = ANY (ARRAY['volunteer'::text, 'admin'::text]))),
  constraint role_allowlist_pkey PRIMARY KEY (email, role)
);
-- indexes
CREATE UNIQUE INDEX role_allowlist_pkey ON public.role_allowlist USING btree (email, role);
-- policies
policy "Read own allowlist" permissive for select to authenticated using ((lower(email) = lower(auth.email()))) with check ();
-- triggers
activity_log_role_allowlist: CREATE TRIGGER activity_log_role_allowlist AFTER INSERT OR DELETE OR UPDATE ON public.role_allowlist FOR EACH ROW EXECUTE FUNCTION activity_from_role_allowlist();
allowlist_reconcile: CREATE TRIGGER allowlist_reconcile AFTER INSERT OR DELETE OR UPDATE ON public.role_allowlist FOR EACH ROW EXECUTE FUNCTION reconcile_profiles_from_allowlist();

create table public.rooms (
  id uuid not null default gen_random_uuid(),
  name text not null,
  sort_order integer not null default 0,
  created_at timestamp with time zone not null default now(),
  constraint rooms_pkey PRIMARY KEY (id),
  constraint rooms_name_key UNIQUE (name)
);
-- indexes
CREATE UNIQUE INDEX rooms_pkey ON public.rooms USING btree (id);
CREATE UNIQUE INDEX rooms_name_key ON public.rooms USING btree (name);
-- policies
policy "Public read rooms" permissive for select to authenticated,anon using (true) with check ();
policy "Admins write rooms" permissive for all to authenticated using (is_admin()) with check (is_admin());
policy "Session editors add rooms" permissive for insert to authenticated using () with check (can_create_rooms());

create table public.session_removals (
  session_id uuid not null,
  user_id uuid not null,
  participation_type text,
  removed_by uuid,
  removed_at timestamp with time zone not null default now(),
  constraint session_removals_removed_by_fkey FOREIGN KEY (removed_by) REFERENCES auth.users(id) ON DELETE SET NULL,
  constraint session_removals_session_id_fkey FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE,
  constraint session_removals_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE,
  constraint session_removals_pkey PRIMARY KEY (session_id, user_id)
);
-- indexes
CREATE UNIQUE INDEX session_removals_pkey ON public.session_removals USING btree (session_id, user_id);

create table public.session_volunteers (
  id uuid not null default gen_random_uuid(),
  session_id uuid not null,
  user_id uuid not null,
  assigned_by uuid,
  created_at timestamp with time zone not null default now(),
  conflict_override boolean not null default false,
  constraint session_volunteers_assigned_by_fkey FOREIGN KEY (assigned_by) REFERENCES auth.users(id) ON DELETE SET NULL,
  constraint session_volunteers_session_id_fkey FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE,
  constraint session_volunteers_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE,
  constraint session_volunteers_pkey PRIMARY KEY (id),
  constraint session_volunteers_session_id_user_id_key UNIQUE (session_id, user_id)
);
-- indexes
CREATE UNIQUE INDEX session_volunteers_pkey ON public.session_volunteers USING btree (id);
CREATE UNIQUE INDEX session_volunteers_session_id_user_id_key ON public.session_volunteers USING btree (session_id, user_id);
CREATE INDEX session_volunteers_session_idx ON public.session_volunteers USING btree (session_id);
CREATE INDEX session_volunteers_user_idx ON public.session_volunteers USING btree (user_id);
-- policies
policy "Read own or admin assignments" permissive for select to authenticated using (((user_id = auth.uid()) OR is_admin())) with check ();
policy "Admins delete assignments" permissive for delete to authenticated using (is_admin()) with check ();
-- triggers
activity_log_session_volunteers: CREATE TRIGGER activity_log_session_volunteers AFTER INSERT OR DELETE ON public.session_volunteers FOR EACH ROW EXECUTE FUNCTION activity_from_session_volunteers();
hours_sheet_dirty: CREATE TRIGGER hours_sheet_dirty AFTER INSERT OR DELETE OR UPDATE ON public.session_volunteers FOR EACH STATEMENT EXECUTE FUNCTION private.mark_hours_sheet_dirty();
session_volunteers_notify_coworkers: CREATE TRIGGER session_volunteers_notify_coworkers AFTER INSERT ON public.session_volunteers FOR EACH ROW EXECUTE FUNCTION notify_organizers_of_coworker();

create table public.sessions (
  id uuid not null default gen_random_uuid(),
  discipline_id text not null,
  title text not null,
  track text not null default ''::text,
  room text not null default ''::text,
  expert_name text not null default ''::text,
  start_time text not null,
  end_time text not null,
  capacity integer not null default 0,
  description text not null default ''::text,
  sponsor text,
  created_by uuid,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  room_id uuid,
  hero_image_url text,
  page_blocks jsonb not null default '[]'::jsonb,
  participant_questions jsonb not null default '[]'::jsonb,
  max_team_size integer not null default 4,
  project_prompt text,
  participant_deadline timestamp with time zone,
  allow_eighth_graders boolean not null default false,
  ask_participant_questions boolean not null default true,
  ask_project_name boolean not null default true,
  constraint sessions_max_team_size_check CHECK (((max_team_size >= 1) AND (max_team_size <= 8))),
  constraint sessions_project_prompt_check CHECK (((project_prompt IS NULL) OR ((length(btrim(project_prompt)) >= 1) AND (length(btrim(project_prompt)) <= 200)))),
  constraint sessions_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL,
  constraint sessions_discipline_id_fkey FOREIGN KEY (discipline_id) REFERENCES disciplines(id) ON DELETE CASCADE,
  constraint sessions_room_id_fkey FOREIGN KEY (room_id) REFERENCES rooms(id) ON DELETE SET NULL,
  constraint sessions_pkey PRIMARY KEY (id)
);
-- indexes
CREATE UNIQUE INDEX sessions_pkey ON public.sessions USING btree (id);
CREATE INDEX sessions_discipline_idx ON public.sessions USING btree (discipline_id);
CREATE INDEX sessions_room_idx ON public.sessions USING btree (room_id);
-- policies
policy "Public read sessions" permissive for select to authenticated,anon using (true) with check ();
policy "Managers insert sessions" permissive for insert to authenticated using () with check (can_manage_discipline(discipline_id));
policy "Managers update sessions" permissive for update to authenticated using (can_manage_discipline(discipline_id)) with check (can_manage_discipline(discipline_id));
policy "Admins delete sessions" permissive for delete to authenticated using (is_admin()) with check ();
-- triggers
activity_log_sessions: CREATE TRIGGER activity_log_sessions AFTER INSERT OR UPDATE ON public.sessions FOR EACH ROW EXECUTE FUNCTION activity_from_sessions();
activity_log_sessions_delete: CREATE TRIGGER activity_log_sessions_delete BEFORE DELETE ON public.sessions FOR EACH ROW EXECUTE FUNCTION activity_from_sessions();
hours_sheet_dirty: CREATE TRIGGER hours_sheet_dirty AFTER DELETE OR UPDATE OF title, start_time, end_time, discipline_id ON public.sessions FOR EACH STATEMENT EXECUTE FUNCTION private.mark_hours_sheet_dirty();
sessions_notify_cancelled: CREATE TRIGGER sessions_notify_cancelled BEFORE DELETE ON public.sessions FOR EACH ROW EXECUTE FUNCTION notify_session_cancelled();
sessions_touch_updated_at: CREATE TRIGGER sessions_touch_updated_at BEFORE UPDATE ON public.sessions FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

create table public.summit_checkins (
  attendee_id uuid not null,
  present boolean not null default false,
  checked_in_at timestamp with time zone,
  marked_by uuid,
  constraint summit_checkins_attendee_id_fkey FOREIGN KEY (attendee_id) REFERENCES auth.users(id) ON DELETE CASCADE,
  constraint summit_checkins_marked_by_fkey FOREIGN KEY (marked_by) REFERENCES auth.users(id) ON DELETE SET NULL,
  constraint summit_checkins_pkey PRIMARY KEY (attendee_id)
);
-- indexes
CREATE UNIQUE INDEX summit_checkins_pkey ON public.summit_checkins USING btree (attendee_id);
-- triggers
activity_log_summit_checkins: CREATE TRIGGER activity_log_summit_checkins AFTER INSERT OR DELETE OR UPDATE ON public.summit_checkins FOR EACH ROW EXECUTE FUNCTION activity_from_summit_checkins();

create table public.summit_settings (
  id boolean not null default true,
  summit_date date,
  updated_at timestamp with time zone not null default now(),
  website_registration_open boolean not null default false,
  website_show_session_times boolean not null default false,
  constraint summit_settings_id_check CHECK (id),
  constraint summit_settings_pkey PRIMARY KEY (id)
);
-- indexes
CREATE UNIQUE INDEX summit_settings_pkey ON public.summit_settings USING btree (id);
-- policies
policy "Admins edit summit settings" permissive for update to authenticated using (is_admin()) with check (is_admin());
policy "Anyone reads summit settings" permissive for select to authenticated,anon using (true) with check ();
-- triggers
activity_log_summit_settings: CREATE TRIGGER activity_log_summit_settings AFTER INSERT OR UPDATE ON public.summit_settings FOR EACH ROW EXECUTE FUNCTION activity_from_summit_settings();
hours_sheet_dirty: CREATE TRIGGER hours_sheet_dirty AFTER INSERT OR DELETE OR UPDATE ON public.summit_settings FOR EACH STATEMENT EXECUTE FUNCTION private.mark_hours_sheet_dirty();

create table public.teams (
  id uuid not null default gen_random_uuid(),
  session_id uuid not null,
  code text not null,
  project_name text not null,
  created_by uuid,
  created_at timestamp with time zone not null default now(),
  owner_id uuid,
  removed_user_ids uuid[] not null default '{}'::uuid[],
  constraint teams_project_name_check CHECK ((length(btrim(project_name)) > 0)),
  constraint teams_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL,
  constraint teams_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES auth.users(id) ON DELETE SET NULL,
  constraint teams_session_id_fkey FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE,
  constraint teams_pkey PRIMARY KEY (id),
  constraint teams_code_key UNIQUE (code)
);
-- indexes
CREATE UNIQUE INDEX teams_pkey ON public.teams USING btree (id);
CREATE UNIQUE INDEX teams_code_key ON public.teams USING btree (code);
CREATE INDEX teams_session_idx ON public.teams USING btree (session_id);
-- triggers
teams_notify_owner: CREATE TRIGGER teams_notify_owner AFTER UPDATE OF owner_id ON public.teams FOR EACH ROW EXECUTE FUNCTION notify_team_owner();

create table public.test_accounts (
  email text not null,
  label text,
  created_at timestamp with time zone not null default now(),
  constraint test_accounts_pkey PRIMARY KEY (email)
);
-- indexes
CREATE UNIQUE INDEX test_accounts_pkey ON public.test_accounts USING btree (email);

create table public.volunteer_hour_logs (
  id uuid not null default gen_random_uuid(),
  user_id uuid not null default auth.uid(),
  started_at timestamp with time zone not null,
  ended_at timestamp with time zone not null,
  description text not null,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  constraint volunteer_hour_logs_description CHECK (((char_length(TRIM(BOTH FROM description)) >= 1) AND (char_length(TRIM(BOTH FROM description)) <= 500))),
  constraint volunteer_hour_logs_max_length CHECK (((ended_at - started_at) <= '24:00:00'::interval)),
  constraint volunteer_hour_logs_order CHECK ((ended_at > started_at)),
  constraint volunteer_hour_logs_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE,
  constraint volunteer_hour_logs_pkey PRIMARY KEY (id)
);
-- indexes
CREATE UNIQUE INDEX volunteer_hour_logs_pkey ON public.volunteer_hour_logs USING btree (id);
CREATE INDEX volunteer_hour_logs_user_idx ON public.volunteer_hour_logs USING btree (user_id, started_at DESC);
-- policies
policy "Delete own hour logs" permissive for delete to authenticated using ((user_id = auth.uid())) with check ();
policy "Read own hour logs" permissive for select to authenticated using ((user_id = auth.uid())) with check ();
policy "Add own hour logs" permissive for insert to authenticated using () with check (((user_id = auth.uid()) AND is_volunteer_or_admin()));
policy "Edit own hour logs" permissive for update to authenticated using ((user_id = auth.uid())) with check (((user_id = auth.uid()) AND is_volunteer_or_admin()));
-- triggers
activity_log_volunteer_hours: CREATE TRIGGER activity_log_volunteer_hours AFTER INSERT OR DELETE OR UPDATE ON public.volunteer_hour_logs FOR EACH ROW EXECUTE FUNCTION activity_from_volunteer_hours();
hours_sheet_dirty: CREATE TRIGGER hours_sheet_dirty AFTER INSERT OR DELETE OR UPDATE ON public.volunteer_hour_logs FOR EACH STATEMENT EXECUTE FUNCTION private.mark_hours_sheet_dirty();
volunteer_hour_logs_touch: CREATE TRIGGER volunteer_hour_logs_touch BEFORE UPDATE ON public.volunteer_hour_logs FOR EACH ROW EXECUTE FUNCTION touch_volunteer_hour_log();
