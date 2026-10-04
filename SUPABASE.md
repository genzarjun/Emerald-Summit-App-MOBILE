# Connecting the Supabase backend (connectivity test)

Goal: prove the app pulls live data from your Supabase project. We use the
`announcements` table as the test — the **News** tab reads it live and shows a
banner telling you whether the data is live or local sample data.

## What you do in Supabase

### 1. Create the table + sample data
1. Open your project at https://supabase.com/dashboard.
2. Left sidebar → **SQL Editor** → **New query**.
3. Open [`supabase/announcements_setup.sql`](supabase/announcements_setup.sql)
   from this repo, copy all of it, paste into the editor, and click **Run**.
   - This creates `announcements`, enables Row Level Security with a
     **public read** policy, and inserts three sample rows.
4. Confirm it worked: left sidebar → **Table Editor** → `announcements` should
   show three rows.

### 2. Copy your project credentials
1. Left sidebar → **Project Settings** (gear) → **API**.
2. Copy two values:
   - **Project URL** — looks like `https://abcdefgh.supabase.co`
   - **Project API keys → `anon` `public`** (may be labeled **Publishable
     key**) — a long token.
3. ⚠️ Do **not** copy the `service_role` / **secret** key. That one bypasses
   security and must never go in the app. I only need the anon/public one.

### 3. Give me the two values
Paste the **Project URL** and the **anon/public key** into
[`lib/supabase_config.dart`](lib/supabase_config.dart) (replace the two
`PASTE_...` placeholders), or just paste them to me in chat and I'll drop them
in. The anon key is designed to live in client apps, so this is safe.

## What happens next (my side)
Once the credentials are in, I'll rebuild and run the app. On the **News** tab
you'll see:
- a green **"Live from Supabase · N announcements"** banner, and
- the three rows served from your database (not the bundled sample data).

Edit or add a row in the Supabase Table Editor, tap **refresh** in the app, and
the change shows up — that's the end-to-end proof the backend is connected.

## How this maps to the real app
`announcements` matches the table in the spec (section 05). The same pattern
extends to the rest of the schema below.

---

# Full backend setup (catalog, schedule, roles, announcements)

This activates the role-driven backend the app code already targets. Do it in
your **dev** project first.

## 1. Run the SQL (in this order)
Dashboard → **SQL Editor** → New query → paste each file → **Run**. Order
matters (later files reference earlier tables/functions):

1. `supabase/profiles_setup.sql` — *(already run if auth works)*
2. `supabase/profiles_extend.sql`
3. `supabase/announcements_setup.sql` — *(already run for the News test)*
4. `supabase/disciplines_setup.sql`
5. `supabase/sessions_setup.sql`
6. `supabase/registrations_setup.sql` — creates the `sessions_with_counts`
   view + the `register_for_session` RPC
7. `supabase/role_allowlist_setup.sql` — allowlist + enforcement triggers +
   `is_admin()`/`can_manage_discipline()` + manager write policies
8. `supabase/announcements_write_setup.sql` — admin write policies + Realtime
9. `supabase/announcement_reads_setup.sql` — per-user read state (unread badge)
10. `supabase/announcement_reads_opened.sql` — adds `opened_at` (per-card dot)
11. `supabase/seed_catalog.sql` — six disciplines + sample sessions

**Volunteers upgrade** (renames `mentor`→`volunteer`, adds per-volunteer
permissions, rooms, session assignments, and attendance). Run these in order,
**after** the eleven above:

12. `supabase/rename_mentor_to_volunteer.sql` — migrates the role string
    `mentor`→`volunteer` in `role_allowlist` + `profiles` (run FIRST of the
    upgrade, before the new trigger).
13. `supabase/profiles_capabilities.sql` — adds `volunteer_subtype` +
    `can_edit_sessions` / `can_post_announcements` / `can_check_in_front_desk`.
14. `supabase/role_allowlist_v2.sql` — adds the sheet's new columns, rewrites the
    enforcement trigger to set subtype + capabilities (with subtype defaults),
    updates `can_manage_discipline()`, adds `can_post_to_discipline()` /
    `can_check_in_front_desk()`, and lets scoped volunteers post announcements.
15. `supabase/rooms_setup.sql` — the admin rooms catalog + `sessions.room_id`;
    **auto-seeds rooms from the existing sessions' room strings and backfills
    room_id** (so current sessions keep their room with no admin work).
16. `supabase/session_volunteers_setup.sql` — volunteer↔session assignments +
    the admin-only, overlap-guarded `assign_volunteer_to_session` RPC + the
    admin `fetch_volunteers` / `fetch_session_volunteers` RPCs.
17. `supabase/attendance_setup.sql` — session-roster attendance
    (`fetch_session_roster` / `mark_session_attendance`, gated by assignment) and
    front-desk check-in (`fetch_attendee_directory` / `mark_summit_checkin`,
    gated by the front-desk capability).
18. `supabase/rooms_editor_insert.sql` — lets admins **and** session-editing
    ambassadors INSERT rooms (so a missing room can be added inline from the
    session editor); UPDATE/DELETE stay admin-only.
19. `supabase/assignment_notifications.sql` — adds `announcements.target_user_id`
    (personal announcements, RLS-scoped to the recipient) and upgrades
    `assign_volunteer_to_session` to (a) drop a personal "you're managing X"
    notification into the volunteer's feed on assignment and (b) return
    `registered_confirm` when the volunteer is already registered for that
    session, so the admin can confirm before assigning.
20. `supabase/unassign_notification.sql` — adds `announcements.session_id`, tags
    the "you're managing X" notice with it, and adds the
    `unassign_volunteer_from_session` RPC: removing a volunteer deletes the
    assignment, deletes that stale "managing" notice from their feed, and posts a
    "you're no longer managing X" notice (feed item + in-app banner).
21. `supabase/session_pages_setup.sql` — the vibrant session page: adds
    `sessions.hero_image_url` + `sessions.page_blocks` (both flow through
    `sessions_with_counts` automatically) and the public `session_photos` Storage
    bucket (one folder per session id) whose writes are gated to admins and the
    session's discipline editors. **Run this to activate hero photos, galleries,
    and content blocks — without it the session editor's photo/section edits fail.**
22. `supabase/announcement_dismissals_setup.sql` — the `announcement_dismissals`
    table backing the News feed's swipe-left **"delete from my view"** (a
    per-user hide, RLS-scoped to the owner, that leaves the announcement in place
    for everyone else). Admins additionally get **"delete for everyone"**, which
    hard-deletes the row via the DELETE policy already in
    `announcements_write_setup.sql` (step 8) and propagates live over Realtime —
    no extra migration needed for that path. Without this migration the app
    degrades gracefully: swipe-to-hide just won't persist across restarts.
23. `supabase/rename_parent_to_parent_spectator.sql` — one-line data migration
    renaming the stored role string `parent` → `parentSpectator` (the app's
    SummitRole member was renamed for clarity; it's the role that auto-spectates).
24. `supabase/session_participation_setup.sql` — the **participation model**:
    adds `registrations.participation_type` (`participant`/`spectator`/`expert`)
    + `registrations.answers`, and `sessions.participant_questions` (both flow
    through `sessions_with_counts`). Redefines `register_for_session` (records the
    type + answers; capacity still counts every registration) and
    `fetch_session_roster` (now returns the type + answers for the Participants
    tab), and adds `set_session_manage` (admin self-manage a session),
    `session_time_conflicts` + `notify_session_time_conflicts` (warn the editor
    and notify affected people when a session's time change creates a clash), and
    **rebuilds the `sessions_with_counts` view** so the session-page columns
    (`hero_image_url`, `page_blocks`, `participant_questions`) are actually
    exposed — a `select s.*` view does NOT pick up columns added later, so without
    this rebuild the hero, content sections, and questions all read back null.
    **Run this to activate Participate/Spectate/Manage, per-session questions, the
    session-page fields, and edit-time conflict alerts — without it "Add to my
    day" still works but everyone registers as a plain participant, the
    Participants tab won't show project answers, and hero/sections/questions won't
    save.** Supersedes the `register_for_session` + view in step 6 and the
    `fetch_session_roster` in step 17.
25. `supabase/archie_setup.sql` — *(optional)* the **Archie daily question
    cap**: `archie_usage` (per user per Pacific-time day, owner-read RLS) + the
    `archie_bump_usage(limit)` SECURITY DEFINER RPC the `archie-chat` function
    calls before answering. Without it Archie is uncapped. See §3c.
26. `supabase/archie_history_setup.sql` — **Archie saved chats**:
    `archie_chats` + `archie_messages` (owner-only RLS; users read, add to, and
    delete only their own chats). Limits live in triggers: **10 chats per user**
    (creating an 11th deletes the least-recently-used) and **15 questions per
    chat** (`archie_chat_full` error). Adds the admin-only
    `archie_recent_exchanges()` RPC — recent question/answer pairs with **no
    user identity** — behind Profile → *Archie insights*. The app saves via
    the `archie_save_exchange()` RPC, which writes the chat and both messages
    in **one transaction** (an earlier version used a client-side bulk insert
    that failed silently and left empty chats; re-running this file installs
    the RPC and deletes those empty chats). Safe to re-run. Without it, Archie
    still chats but nothing is saved and the history sheet can't load.
27. `supabase/registration_answers_edit.sql` — adds the
    `update_registration_answers(session_id, answers)` SECURITY DEFINER RPC so a
    participant can **edit the answers they gave when registering** ("Edit my
    answers" on the session page). It only updates the caller's own
    registration's `answers`. Without it, saving edited answers fails with an
    error snackbar (registering still works).
28. `supabase/teams_setup.sql` — **solo/team projects**: the `teams` table
    (RPC-only, no client grants), `registrations.project_mode` /
    `project_name` / `team_id`, team-code helpers (`team_code_prefix` — TV, VV,
    BS, NS, CV, IX — and `new_team_code`), an empty-team cleanup trigger, and
    the RPCs `find_team`, `update_my_registration`, `fetch_my_project`.
    **Redefines `register_for_session`** (drops the older overloads; adds the
    project params) and **`fetch_session_roster`** (adds project/team columns
    and lets the session's discipline editors read it). **Required by the
    current app: until it's run, participating fails** (the app sends the new
    project parameters). Safe to re-run.
29. `supabase/teams_ownership_setup.sql` — **team owners + size limits**:
    `teams.owner_id` (backfilled from the creator), `sessions.max_team_size`
    (default 4; **rebuilds `sessions_with_counts`** so it's exposed), an
    internal `team_hand_off` helper, the `transfer_team_ownership` RPC, and new
    versions of `find_team`, `register_for_session`, `update_my_registration`
    (both gain `p_new_owner_id`; the old signatures are dropped),
    `fetch_my_project` (owner + member details), `fetch_session_roster` (adds
    `is_team_owner`), and the empty-team trigger. **Run before shipping the
    current app: until then, saving a session in the editor fails (it writes
    `max_team_size`), and owner hand-off, team-full checks, and the roster's
    owner marker don't work.** Safe to re-run.
30. `supabase/team_size_limits.sql` — narrows `sessions.max_team_size` to
    **1–8** (1 = **solo only**, no teams; anything above 8 is clamped to 8) and
    redefines `find_team`, `register_for_session`, and `update_my_registration`
    (same signatures) to refuse creating or joining a team in a solo-only
    session (`teams_not_allowed`). People already on a team keep it. **Run
    before shipping the current app** — without it, saving "No teams allowed"
    in the editor fails the old 2–50 check. Safe to re-run.
31. `supabase/project_prompt_setup.sql` — adds `sessions.project_prompt`
    (nullable; null = the default "What is your project name?") so editors can
    **reword the built-in project question** per session, and **rebuilds
    `sessions_with_counts`** to expose it. **Run before shipping the current
    app** — without it, saving a session in the editor fails (it writes
    `project_prompt`). Safe to re-run.
32. `supabase/team_members_setup.sql` — **teammate notices + removing
    members**: a trigger on `registrations` posts a personal *"X joined your
    team"* announcement to every other member when someone joins a team; the
    owner-only `remove_team_member` RPC takes someone off a team (they stay
    registered, with no project answer) and notifies them; `teams.removed_user_ids`
    + a `before` trigger stop removed people rejoining; `find_team` reports
    `removed`. Team notices leave `announcements.session_id` null so
    volunteer-unassign cleanup never deletes them. Safe to re-run.
33. `supabase/team_leave_notices.sql` — more team notices, all via triggers
    (no app change): *"X left your team"* to remaining members when someone
    leaves (solo, switching teams, or unregistering); *"X was removed from your
    team"* to the other members when the owner removes someone; and *"You're
    now the owner"* to whoever takes over a team. Silent while a session is
    being deleted or when the last member leaves. Notices set `created_by` only
    to the acting user, so account deletions are never blocked. Safe to re-run.
34. `supabase/session_delete_admin_only.sql` — splits the sessions write
    policy so **only admins can delete sessions**; session-editing volunteers
    keep insert + update. Safe to re-run.
35. `supabase/session_cancel_notices.sql` — a `before delete` trigger on
    `sessions` that sends everyone who had the session on their schedule
    (registrants + its assigned volunteers, minus whoever deleted it) a personal
    *"Session cancelled"* announcement with its title and time. Also fires for
    sessions removed by deleting their discipline. Safe to re-run.
36. `supabase/discipline_delete_dashboard_only.sql` — **disciplines can only be
    deleted from the Supabase dashboard**: replaces the admin `for all` policy
    with insert + update policies and revokes DELETE from app roles, so no app
    user (admins included) can delete one. A dashboard delete (Table Editor or
    `delete from public.disciplines where id = '…'`) still cascades to its
    sessions and sends each session's "Session cancelled" notices — use DELETE,
    not TRUNCATE, which skips triggers. Safe to re-run.

37. `supabase/archie_knowledge_setup.sql` — creates the **private** Storage
    bucket `archie` that holds Archie's knowledge base (`knowledge.md`, see
    §3c). No policies: the function reads it with the service role and admins
    upload it from the dashboard. Without it (or without the file) Archie works,
    just without the fact sheet.

38. `supabase/roster_profile_details.sql` — `fetch_session_roster` also returns
    each registrant's `role` and `details` (school, grade, phone, expertise,
    bio), so session organizers can tap a person on the Participants / Experts
    tabs to see their profile. Same gate as before (assigned volunteer, admin,
    or editor of the session's discipline); `profiles` RLS stays own-row only.
    Until it's run, the sheet says profile details aren't available yet.
    Safe to re-run.

After this, sign in and build a schedule — it should persist across restarts
and devices. Everyone is a `participant` until the allowlist sync runs.

## 2. The two Google Sheets (volunteer/admin allowlist) — kept PRIVATE
Create two Google Sheets (leave them unpublished/private):

- **Volunteers** — columns, in order: `email`, `subtype`, `disciplines`,
  `can_edit_sessions`, `can_post_announcements`, `can_check_in_front_desk`.
  - `subtype`: `eaf_ambassador`, `parent_volunteer`, or `student_volunteer`.
  - `disciplines`: a comma/semicolon list of discipline ids
    (e.g. `techverse, robosphere`) or `all`/`*` (= every discipline) — mainly
    for EAF ambassadors who edit sessions.
  - the three capability columns take `TRUE`/`FALSE`/**blank**. Blank uses the
    subtype default (ambassadors get `can_edit_sessions` on; everything else
    off), so most rows only need `email` + `subtype` (+ `disciplines` for
    ambassadors). Set a cell `TRUE` to grant that capability to that person.
  - rooms and session assignments are **not** in the sheet — admins manage them
    in the app.
- **Admins** — column `email`.

From each sheet's URL note its **spreadsheet id** — the long token in
`https://docs.google.com/spreadsheets/d/<THIS>/edit`.

## 2b. Create a Google service account (read-only, private)
So the function can read the private sheets without any public link:
1. [Google Cloud Console](https://console.cloud.google.com) → create/pick a
   project → **APIs & Services → Enable APIs** → enable **Google Sheets API**.
2. **APIs & Services → Credentials → Create credentials → Service account.**
   Name it (e.g. `emerald-allowlist`); no roles needed. Create.
3. Open the service account → **Keys → Add key → Create new key → JSON.** A JSON
   file downloads — it contains `client_email` and `private_key`.
4. **Share both sheets** with that `client_email` as **Viewer** (the normal
   Share button). That's the only access it gets — read-only, just these sheets.

## 3. Deploy the sync Edge Function
Requires the [Supabase CLI](https://supabase.com/docs/guides/cli). The project
ref is the subdomain of `SUPABASE_URL` in your `env.json` (currently
`dgrskmykbkvphnaasfzl`). You can also deploy via the dashboard editor
(Edge Functions → Deploy a new function → Via editor → paste
`supabase/functions/sync-allowlist/index.ts`), set the secrets under
Edge Functions → Secrets, and **turn OFF "Verify JWT"** for the function so the
header-less cron can call it.

```bash
supabase link --project-ref dgrskmykbkvphnaasfzl
supabase functions deploy sync-allowlist --no-verify-jwt   # matches the header-less cron
supabase secrets set \
  GOOGLE_SERVICE_ACCOUNT_EMAIL="<client_email from the JSON>" \
  GOOGLE_PRIVATE_KEY="<private_key from the JSON, keep the \n escapes>" \
  VOLUNTEERS_SHEET_ID="<volunteers spreadsheet id>" \
  ADMINS_SHEET_ID="<admins spreadsheet id>"
```

> The legacy secret names `MENTORS_SHEET_ID` / `MENTORS_RANGE` are still accepted
> as fallbacks, so an existing deployment keeps working; prefer the
> `VOLUNTEERS_*` names going forward.

Nothing here is public — the sheets stay private and only the service account
reads them. `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are injected into the
function automatically (the service-role key is never in `env.json`; the app
only carries the publishable key). Optional overrides: `VOLUNTEERS_RANGE`
(default `A:F`), `ADMINS_RANGE` (default `A:A`).

Trigger it once to verify (Dashboard → Edge Functions → sync-allowlist → Invoke,
or `curl` its URL); it returns `{ ok: true, volunteers: N, admins: M }` and fills
`role_allowlist`. Then **schedule it** every ~5 min (Dashboard → Integrations →
Cron, or a `pg_cron` job POSTing the function URL — see below).

> **A repeating `404` in the function logs means the function isn't deployed at
> that URL** (the cron is firing, but there's nothing to hit). Deploy it, then
> the 404s stop.

To become an admin: add your email to the Admins sheet, wait for the next sync
(or Invoke it), then sign up / re-open onboarding and pick **Admin**.

## 3b. Test/dev login — "code emails" that bypass OTP (DEV PROJECT ONLY)
So you can test each privilege level without a real inbox, a **code email**
(e.g. `student-frontdesk@ehsacademics.org`) can sign in **without an emailed
OTP** and simulate that account. It still gets a **real Supabase session**, so
RLS, the role trigger, and every RPC behave exactly like production — the only
shortcut is the login. Permissions come from the Google Sheets as usual: put the
same mock emails in the Volunteers/Admins sheet with the roles/capabilities you
want to test. Make **one code email per scenario** to cover unique permissions.

> ⚠️ This is a login backdoor. Deploy it to your **dev project only** and never
> enable it in production. It is guarded twice — see below.

1. **Create the table.** Run [`supabase/test_accounts_setup.sql`](supabase/test_accounts_setup.sql)
   and add your code emails (in the SQL, or in Table Editor → `test_accounts`).
   Add the **same emails** to the Volunteers/Admins sheets (and re-sync).
2. **Deploy the function** (dashboard editor, like sync-allowlist, or CLI):
   paste [`supabase/functions/dev-login/index.ts`](supabase/functions/dev-login/index.ts),
   deploy with **Verify JWT OFF**, and set the secret **`DEV_LOGIN_ENABLED=true`**
   (guard #1 — omit it in prod and the function refuses).
   ```bash
   supabase functions deploy dev-login --no-verify-jwt
   supabase secrets set DEV_LOGIN_ENABLED=true
   ```
3. **Build the app with the dev flag** (guard #2): add `"DEV_LOGIN": true` to
   your dev `env.json`, then run as usual
   (`flutter run --dart-define-from-file=env.json`). Without this flag the app
   never calls the function, so production builds are unaffected.
4. **Test:** on the sign-in screen, type a code email and tap *Email me a code* —
   you're signed straight in as that account. Non-code emails fall through to the
   normal OTP flow untouched.

## 3c. Archie — the AI assistant (`archie-chat`)
The **Archie** tab streams answers from the
[`archie-chat`](supabase/functions/archie-chat/index.ts) Edge Function, which
calls Claude (Anthropic API) with server-side web search/fetch and grounds it in
the live catalog, News feed, and the caller's own schedule (read with the
caller's JWT, so RLS applies). Without it deployed, the tab shows *"Archie isn't
set up on this server yet."*

1. **Get an Anthropic API key** (console.anthropic.com → API keys). It lives
   only in the function's secrets — never in `env.json` or the app.
2. *(Recommended)* run [`supabase/archie_setup.sql`](supabase/archie_setup.sql)
   — a per-user **daily question cap** (`archie_usage` + `archie_bump_usage`
   RPC). Without it Archie works but is uncapped.
   Also run [`supabase/archie_history_setup.sql`](supabase/archie_history_setup.sql)
   for **saved chats** (step 26).
3. **Deploy + set secrets:**
   ```bash
   supabase functions deploy archie-chat --no-verify-jwt   # the function checks the session itself
   supabase secrets set ANTHROPIC_API_KEY="sk-ant-..."
   # optional: ARCHIE_MODEL (default claude-sonnet-5-5), ARCHIE_EFFORT (default medium),
   #           ARCHIE_DAILY_LIMIT (default 50)
   ```
   Or via the dashboard editor (paste `index.ts`, turn **Verify JWT OFF**, add
   the secrets under Edge Functions → Secrets).
4. **Upload the knowledge base** (the organizers' fact sheet Archie answers
   from before touching the web): run
   [`supabase/archie_knowledge_setup.sql`](supabase/archie_knowledge_setup.sql),
   then Dashboard → **Storage** → bucket **archie** → **Upload file** →
   [`supabase/archie/knowledge.md`](supabase/archie/knowledge.md), named
   exactly `knowledge.md`. **To update it:** edit the file in the repo, delete
   the old `knowledge.md` in the bucket (or upload with overwrite), and upload
   the new one. Archie picks it up within ~5 minutes — no redeploy. The
   function logs `archie_knowledge` with the size it loaded. HTML comments
   (`<!-- … -->`) in the file are editor notes and are stripped before Archie
   sees them.
5. **Test:** sign in, open the Archie tab, tap a starter. You should see
   "Searching the web…"/"Reading …" steps for web questions, the answer typing
   out, and source chips under it. Questions the knowledge base covers should
   answer with no web steps.

Cost note: every question is a paid model call (plus web searches). Prompt
caching is built in (see the function header); the daily cap and the
`ARCHIE_EFFORT` / `ARCHIE_MODEL` secrets are the remaining levers. Each model
call logs one `archie_usage` line (input / cache_read / cache_write / output
tokens, web searches) — check Edge Functions → archie-chat → Logs to see real
costs and confirm cache hits (`cache_read` > 0 from the second question on).

**After changing `index.ts`, redeploy** (secrets persist across deploys):
`supabase functions deploy archie-chat --no-verify-jwt`.

## 4. Verify Realtime
Dashboard → Database → Replication → ensure `announcements` is in the
`supabase_realtime` publication (step 8's SQL adds it). With two devices signed
in, an admin posting an announcement should update the other's News feed live
and show the in-app banner.

## Deferred: OS push notifications
Not built yet (banner-when-closed). The planned pipeline — `device_tokens`
table, Firebase/APNs, a `send-announcement-push` Edge Function on an
`announcements` INSERT webhook via FCM HTTP v1 — is described in the README
Roadmap. Nothing here needs to change to add it later.
