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
