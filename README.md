# Emerald Summit '27

The companion mobile app (iOS + Android) for **Emerald Summit '27** — the
Tri-Valley's student-run STEAM summit at Emerald High, Dublin CA
(January 2027). Built with Flutter.

> **Status: role-driven backend live.** All screens and interactions work, and
> the backend is wired up and verified end-to-end on the dev project (two-device
> testing). **Auth (passwordless email OTP)** is live. The **catalog
> (disciplines + sessions), the personal schedule, the News feed, and per-user
> settings are all Supabase-backed**, with the schema shipped as SQL migrations
> in [`supabase/`](supabase/) (see [SUPABASE.md](SUPABASE.md) to reproduce on a
> fresh project). On top of that: **admins
> post announcements in-app** (live to every device via **Realtime** + an
> in-app banner), **mentors create/edit sessions** in the disciplines they own,
> and **mentor/admin roles are gated by a Google-Sheet allowlist** the database
> enforces. Without `env.json` the app still runs standalone on **sample data**.
> **OS push notifications** (banner when the app is closed) and server-side PDF
> generation are the main things still to come (see Roadmap).

## What's implemented
Five-tab app matching the spec's core participant features:

- **My Day** — the participant's personal schedule. Backed by the
  `registrations` table (RLS-scoped to the user), so it follows the account
  across devices and reinstalls. Empty-state → browse flow.
- **Discover** — catalog of the disciplines → each discipline's sessions → a
  rich session "marketing page." Reads live from Supabase (`disciplines` +
  `sessions_with_counts` view). **Add to my day** enforces the real rules via a
  server-side RPC (`register_for_session`): no double-booking (time-conflict
  dialog) and capacity caps (full/waitlist), so they can't be bypassed from the
  client. Mentors/admins get **New session / Edit** controls (scoped to their
  disciplines); admins get **New discipline**.
- **News** — the announcements feed (pinned items, audience tags). Reads live
  from Supabase and stays **live via Realtime** — a new announcement appears the
  instant an admin posts it, alongside an **Instagram-style in-app banner** when
  the app is foregrounded. **Admins** get a **New announcement** composer
  (title, message, audience, pin). **Audience targeting:** an announcement aimed
  at a discipline reaches only users who have an **activity in that discipline**
  (plus admins and mentors who manage it); "Everyone" reaches all. Filtering is
  applied to both the feed and the banner. Falls back to sample data when the
  backend isn't configured. **OS push** (when the app is closed) is designed but
  not yet built (see Roadmap).
- **Resources** — searchable document hub.
- **Profile** — contact card with role badge (mentors also show the
  discipline(s) they manage), notifications toggle, **Change role** (re-runs the
  gated role picker), sign-out, and volunteer hours with a "Download
  certificate" action.

**Accounts & sign-in** (live when Supabase is configured):
- **Passwordless email OTP.** A user enters their email, gets a numeric code,
  and types it in — no password is ever created or stored. First-time sign-in
  creates the account. In sample mode (no backend) the app skips auth and opens
  straight to the demo data.
- **Role-based onboarding.** First run collects name + **role**, then asks
  **role-specific** details. The five roles are **participant**, **expert**,
  **parent / spectator** (open to anyone — the last covers non-participating
  middle-schoolers), and the two management roles **mentor** and **admin**.
  Mentors get the full contact/emergency-contact questionnaire; experts are kept
  light (org + expertise only); admins need nothing extra. Fields are declared
  per role in [lib/models/user_profile.dart](lib/models/user_profile.dart), so
  the sign-up flow customizes itself.
- **Gated management roles.** Anyone can be a participant/expert/parent, but
  **mentor** and **admin** are verified against an allowlist synced from two
  Google Sheets (see "Roles & permissions" below). Picking a gated role you're
  not listed for is blocked with *"You aren't eligible to sign up as a
  mentor/admin."*
- **The account is tied to the email**, not the device. The session persists
  across app restarts and auto-refreshes; signing in on another device (or
  after reinstalling) pulls the same profile, role, and data back down. Only
  deleting the app forces a fresh sign-in. This is also what makes the later
  **switch from OTP to Google seamless** — same email → same account.

Brand colors and type follow spec section 03 (Emerald `#0C7A55`, Deep Emerald
`#0A5F43`, Ink `#16211C`, Mist `#EEF5F1`, system fonts).

## Project layout
```
lib/
  main.dart                 App entry + MaterialApp/theme + in-app banner host
  theme.dart                Brand palette & Material 3 theme
  app_state.dart            Catalog, schedule, announcements, profile, roles, Realtime
  app_navigation.dart       Global selected-tab notifier (banner → News)
  models/models.dart        Discipline, Session, Announcement, ResourceDoc, disciplineIcon()
  models/user_profile.dart  UserProfile + SummitRole + per-role fields + scope helpers
  data/sample_data.dart     Standalone fallback content (no-backend mode)
  data/profile_repository.dart      Signed-in user's profile row (+ patch)
  data/disciplines_repository.dart  Catalog read + admin create discipline
  data/sessions_repository.dart     Mentor/admin session create/update/delete
  data/registrations_repository.dart  Schedule read + register_for_session RPC
  data/announcements_repository.dart  Feed read + admin create
  data/allowlist_repository.dart    Own-email eligibility check (advisory)
  widgets/in_app_banner.dart  Instagram-style in-app banner (controller + host)
  screens/
    root_nav.dart           Bottom navigation shell
    auth/                   auth_gate, sign_in_screen, onboarding_screen (+ role gate)
    schedule_screen.dart    My Day
    discover_screen.dart    Disciplines grid (+ admin "New discipline")
    discipline_screen.dart  Sessions in a discipline (+ mentor/admin edit)
    session_detail_screen.dart   Marketing page + add/remove
    session_editor_screen.dart   Create/edit a session (mentor/admin)
    discipline_editor_screen.dart  Create a discipline (admin)
    announcement_compose_screen.dart  Post an announcement (admin)
    announcements_screen.dart, resources_screen.dart, profile_screen.dart
supabase/                   SQL migrations + Edge Functions (see Backend)
test/widget_test.dart       Widget tests
```

## Backend
- **Supabase** (hosted Postgres + auth + storage) is the chosen backend
  (Firebase was considered; Supabase won). Client via `supabase_flutter`.
- **Live now:**
  - The `announcements` table feeds the News tab (read-only, behind a
    public-read RLS policy). Schema in
    [supabase/announcements_setup.sql](supabase/announcements_setup.sql).
  - **Auth + `profiles` table.** Email OTP via Supabase Auth; each account gets
    a `profiles` row (`id` = `auth.users.id`, plus `full_name`, `role`, a
    `details` jsonb bag for role-specific answers, `onboarded`). RLS scopes every
    row to `auth.uid()` so users only ever touch their own profile; a trigger
    auto-creates the row on sign-up. Schema + required dashboard steps in
    [supabase/profiles_setup.sql](supabase/profiles_setup.sql).
    - **Custom SMTP is required** for OTP and is **configured** (Google
      Workspace, sending from the org address). Hard-won setup notes:
      - New free-tier projects can only edit email templates once custom SMTP
        is on (also needed for production — the built-in email service is
        test-only and rate-limited).
      - Gmail/Workspace SMTP needs an **App Password** (2-Step Verification on),
        pasted **without spaces**, and the **sender address must equal the
        authenticated account** or Gmail rejects with a `535`/sender error.
      - **Edit BOTH email templates** to include `{{ .Token }}`: **"Confirm
        signup"** is what *new* users get on first sign-in; **"Magic Link"** is
        what *returning* users get. Editing only one leaves the other path
        emailing a bare link with no code.
      - Set **Email OTP Length** (Auth → Providers → Email) to **6**; the app's
        code field tolerates up to 10 so a mismatch never truncates silently.
  - App-side auth lives in [lib/screens/auth/](lib/screens/auth/) (`auth_gate`
    routes sign-in → onboarding → app) with [lib/data/profile_repository.dart](lib/data/profile_repository.dart).
- **Data model (SQL in [`supabase/`](supabase/)).** Run the files in
  [SUPABASE.md](SUPABASE.md)'s order to create these:
  - `disciplines` — the catalog categories (public read; **admin** write).
    [disciplines_setup.sql](supabase/disciplines_setup.sql)
  - `sessions` — activities under a discipline (public read; **admin or mentor
    scoped to the discipline** write). `enrolled` is never stored — the
    `sessions_with_counts` **view** derives it live from `registrations` and adds
    the discipline name. [sessions_setup.sql](supabase/sessions_setup.sql)
  - `registrations` — the personal schedule (RLS: each user only their own).
    Adds/removes go through the **`register_for_session` RPC**, the single
    server-side enforcer of capacity + no-time-overlap.
    [registrations_setup.sql](supabase/registrations_setup.sql)
  - `profiles` gains `notifications_enabled`, `volunteer_hours`, and
    `managed_disciplines` (a mentor's scope; `{'*'}` = all).
    [profiles_extend.sql](supabase/profiles_extend.sql)
  - `announcements` gains `created_by` + `discipline_id`, **admin** write
    policies, and **Realtime**. [announcements_write_setup.sql](supabase/announcements_write_setup.sql)
  - Seed the six disciplines + sample sessions with
    [seed_catalog.sql](supabase/seed_catalog.sql).
- **Roles & permissions.** Five roles: `participant`, `expert`, `parent`
  (open), `mentor`, `admin` (gated). Enforcement lives in
  [role_allowlist_setup.sql](supabase/role_allowlist_setup.sql):
  - `role_allowlist(email, role, disciplines[])` is the synced source of truth.
    A user may read only their **own** row.
  - A **`profiles` BEFORE INSERT/UPDATE trigger** is the real gate: it refuses
    to set `role` to mentor/admin unless the email is allow-listed, forcing
    `participant` otherwise, and it **owns** `managed_disciplines` (set from the
    sheet for mentors; empty for global admins). Self-elevation via a crafted
    API call is impossible.
  - Helpers `is_admin()` and `can_manage_discipline(id)` back the write policies
    on disciplines/sessions/announcements.
  - The allowlist is filled by the **`sync-allowlist` Edge Function**
    ([supabase/functions/sync-allowlist](supabase/functions/sync-allowlist)),
    which reads two **private Google Sheets** (mentors, admins) via the **Google
    Sheets API using a service account** — the sheets stay unpublished, so no
    mentor/admin emails are ever exposed on a public link — and upserts/prunes
    rows on a cron. A reconcile trigger re-applies changes to existing profiles
    (including demoting anyone removed from a sheet). Setup in [SUPABASE.md](SUPABASE.md).
- Note the dev project has "auto-expose new tables" **off**, so every table's
  SQL must `grant` privileges to the right role explicitly (`anon` for public
  reads, `authenticated` for per-user tables).
- **Keys:** use the **publishable** key (`sb_publishable_…`), not the deprecated
  anon key; never the secret / `service_role` key in the app.
- Separate Supabase projects for **dev/testing** and **production** (prod added
  later; the free tier allows two).

## Configuration (Supabase keys)
Secrets are **not** stored in source. Real values live in a gitignored
`env.json`, injected at build time. To set up:

```bash
cp env.example.json env.json     # then edit env.json with your real values
```

Fill in your **Project URL** and **publishable key** (Supabase → Settings →
API). `env.json` is gitignored; `env.example.json` is the committed template.
Never put a `secret` / `service_role` key in either file — it must not ship in
a client app.

Without `env.json` (or the flag below) the app runs on local **sample data**.

## Run it locally
```bash
flutter pub get
flutter run --dart-define-from-file=env.json      # choose a device when prompted
```

> The `--dart-define-from-file=env.json` flag applies to **every** build/run
> command that should talk to the backend — `flutter run`, `flutter build apk`,
> `flutter build ipa`, etc. Omit it and the app falls back to sample data.
> In Android Studio/VS Code, add it under the run configuration's
> "Additional args" so it's automatic.

## Test & analyze
```bash
flutter test
flutter analyze
```

## Deploy to TestFlight
See [TESTFLIGHT.md](TESTFLIGHT.md). Bundle ID: `com.emeraldsummit.emeraldSummit`.

## Milestones
- ✅ **UI skeleton** — all five tabs and interactions on sample data.
- ✅ **First backend read** — News feed live from Supabase.
- ✅ **Auth & accounts** — passwordless email OTP + role-based onboarding.
- ✅ **Per-user data in Supabase** — catalog (disciplines/sessions) + personal
  schedule (`registrations`) + per-user settings, all behind RLS; capacity and
  time-conflict rules enforced server-side. *(code done; run the SQL to activate)*
- ✅ **Role-driven management** — gated mentor/admin roles from a Google-Sheet
  allowlist the DB enforces; admins post announcements in-app (live via Realtime
  + in-app banner); mentors create/edit sessions in their disciplines; admins
  create disciplines. *(code done; needs the SQL + Edge Function deployed)*
- ⏳ **Next: OS push notifications** — deliver announcements as real push even
  when the app is closed (see Roadmap for the planned pipeline).

## Roadmap (later, from the spec)
- **Google sign-in** — add the **native** flow (`google_sign_in` →
  `supabase.auth.signInWithIdToken`) alongside the existing OTP. Native avoids
  custom URL schemes/deep links; it needs Google Cloud OAuth client IDs (iOS
  bundle ID, Android package + SHA-1) and the Supabase Google provider enabled.
  Because accounts are keyed to email, users keep the same profile/data when
  they switch from OTP to Google — Supabase auto-links identities that share a
  confirmed email (OTP and Google both produce one), so no extra config needed.
- **OS push notifications (deferred — designed, not built).** Announcements are
  already "instant" while the app is open (Realtime + in-app banner); this adds
  delivery when the app is **closed/backgrounded**. Planned pipeline:
  - A `device_tokens` table (per-user FCM tokens, RLS-scoped) written on sign-in.
  - Flutter `firebase_core` + `firebase_messaging`; a **Firebase project** with
    an **APNs auth key** (.p8) from the Apple Developer account uploaded to
    Firebase Cloud Messaging, so iOS pushes route through APNs — one FCM code
    path for both platforms. iOS also needs the Push Notifications + Background
    Modes capabilities.
  - A `send-announcement-push` **Edge Function** triggered by a **Database
    Webhook on `announcements` INSERT**, which loads the target device tokens
    (all, or by `discipline_id` audience) and sends via **FCM HTTP v1** (service
    account stored as a function secret).
  - Foreground messages reuse the existing in-app banner
    ([lib/widgets/in_app_banner.dart](lib/widgets/in_app_banner.dart)).
  - Also planned: per-user "next session" reminders; email fan-out.
- Team formation; spectator seats; check-in dashboard; pre-summit milestone
  reminders; sponsor blocks; post-event social posts; server-rendered
  certificate / feedback PDFs.

## Android (later)
The `android/` project is scaffolded. Building it needs the Android SDK
(install Android Studio, then `flutter doctor`). Then `flutter run -d android`.
