# Emerald Summit '27

The companion mobile app (iOS + Android) for **Emerald Summit '27** — the
Tri-Valley's student-run STEAM summit at Emerald High, Dublin CA
(January 2027). Built with Flutter.

> **Status: role-driven backend live.** All screens and interactions work, and
> the backend is wired up and verified end-to-end on the dev project (two-device
> testing). **Auth (passwordless email OTP, plus native Google sign-in)** is
> live. The **catalog
> (disciplines + sessions), the personal schedule, the News feed, and per-user
> settings are all Supabase-backed**, with the schema shipped as SQL migrations
> in [`supabase/`](supabase/) (see [SUPABASE.md](SUPABASE.md) to reproduce on a
> fresh project). On top of that: **admins
> post announcements in-app** (live to every device via **Realtime** + an
> in-app banner), and **volunteer/admin roles are gated by a Google-Sheet
> allowlist** the database enforces. The **Volunteer** role (EAF ambassadors,
> parent & student volunteers) carries **fine-grained, per-person permissions**
> from the sheet: EAF ambassadors **create/edit sessions** (and optionally post
> announcements) in the disciplines they own; any volunteer an admin **assigns
> to a session** can pull its **roster and mark attendance**; and volunteers
> flagged for the **front desk** can check in *any* attendee summit-wide. Admins
> manage a **rooms catalog** that sessions are tied to. *(All the volunteer
> features are code-complete; run the SQL in [SUPABASE.md](SUPABASE.md) to
> activate them.)* Without `env.json` the app still runs standalone on
> **sample data**.
> **OS push notifications** (banner when the app is closed) and server-side PDF
> generation are the main things still to come (see Roadmap).

## What's implemented
Five-tab app (**Home · Schedule · Discover · News · Resources**) matching the
spec's core participant features. **Profile is reached from the avatar in the
Home header** (Uber-style), not a bottom-bar tab.

- **Home** — the launchpad ([lib/screens/dashboard_screen.dart](lib/screens/dashboard_screen.dart)).
  A greeting + tappable avatar → Profile, a **photo slideshow** (a 16:9 band of
  event photos that auto-advances every 5s with a cross-fade + page dots, in a
  fresh random order each load; hidden when there are no photos), a
  daily-rotating quote card with brand
  art, an **Up next** card (the next session in your schedule, or a "plan your
  day" nudge when it's empty), a grid of Uber-style **Jump to** action tiles
  (schedule, browse, news with an unread badge, campus map, resources, profile),
  a horizontal **Explore disciplines** rail into the catalog, a **Latest news**
  peek, and outbound **Links** (website, Instagram, contact) opened via
  `url_launcher`. Exists so the app has an interesting home even before anything
  is added to the schedule. **Touches:** the greeting is a random mix of standard
  ("Good morning") and playful ("What's cooking", "What's building") lines with
  an animated shimmer sweep (echoing the website wordmark); the quote card wipes
  down on first view.
- **Schedule** — the user's full personal schedule (formerly the "My Day" first
  tab; the in-app header still reads "My Day"). Shows **everything they're
  committed to**, each tagged with the role: sessions they're **Attending**
  (from `registrations`) and sessions they're **Managing** (volunteer
  assignments from `session_volunteers`), merged and sorted by time (managing
  wins if both). RLS-scoped, so it follows the account across devices. A session
  a volunteer is **assigned to manage shows no "Add/Remove to my day"** — it's
  on their schedule by admin action and only an admin can unassign it; the detail
  page shows a "You're managing this session" status instead. The profile entry
  to the managing list + attendance is labeled **"Sessions I'm managing"**.
  Empty-state → browse flow.
- **Discover** — catalog of the disciplines → each discipline's sessions → a
  rich session "marketing page." Reads live from Supabase (`disciplines` +
  `sessions_with_counts` view). **Add to my day** enforces the real rules via a
  server-side RPC (`register_for_session`): no double-booking (time-conflict
  dialog) and capacity caps (full/waitlist), so they can't be bypassed from the
  client. Admins and EAF ambassadors who can edit sessions get **New session /
  Edit** controls (scoped to their disciplines); the editor ties a session to a
  **room** picked from the admin catalog — and if the needed room isn't listed,
  an **"Add a room…"** option in that dropdown creates it inline (admins and
  session-editing ambassadors; INSERT-only, backend-enforced) without leaving the
  page. Admins get **New discipline** and, on
  each session, **Manage volunteers** — assigning a volunteer to a session is
  overlap-guarded server-side (an admin sees *"This person has a schedule
  conflict…"* if it clashes with their other assignments or registrations). If
  the volunteer is already **registered** for that very session, the admin gets
  an *"…is registered for this session. Assign them to manage it?"* confirm
  first. On assignment the volunteer receives an automatic personal
  announcement + banner.
- **News** — the announcements feed (pinned items, audience tags). Reads live
  from Supabase and stays **live via Realtime** — a new announcement appears the
  instant an admin posts it, alongside an **Instagram-style in-app banner** when
  the app is foregrounded. **Admins** get a **New announcement** composer
  (title, message, audience, pin). **Audience targeting:** an announcement aimed
  at a discipline reaches only users who have an **activity in that discipline**
  (plus admins and the volunteers who manage it); "Everyone" reaches all.
  A volunteer with the **post-announcements** capability gets the composer too,
  but scoped: they can only target the discipline(s) they manage. **Personal
  announcements:** the feed also carries per-user items (a `target_user_id`) —
  e.g. when an admin assigns a volunteer to a session, that volunteer gets an
  automatic *"You have been assigned to manage &lt;session&gt; in
  &lt;discipline&gt;"* item (and in-app banner), visible only to them (RLS-scoped).
  Filtering is
  applied to both the feed and the banner. **Per-user read state (two-tier,
  Instagram-style):** the News tab and Home "What's new" tile show a red count
  of *unseen* announcements; opening the News tab marks the feed **seen** and
  clears that count. Independently, each feed card keeps a green **unread dot**
  until the user taps (opens) that specific card — so dots persist after the red
  badge is gone. Both tiers are private per user, tracked in the
  `announcement_reads` table (a row = seen; `opened_at` = opened), RLS-scoped to
  the owner. The app degrades gracefully: no reads table → "all unseen"; reads
  table but no `opened_at` column → seen/badge work, dots don't persist. Falls
  back to sample data when the backend isn't configured. **OS push** (when the
  app is closed) is designed but not yet built (see Roadmap).
- **Resources** — searchable document hub.
- **Profile** (reached from the Home-header avatar) — contact card with role
  badge (volunteers also show their **subtype** and the discipline(s) they
  manage), notifications toggle, and role-gated shortcuts: **My sessions**
  (a volunteer's assigned sessions → roster + attendance), **Front desk
  check-in** (for front-desk-flagged volunteers/admins), **Manage rooms**
  (admins). Plus **Change role** (re-runs the gated role picker), sign-out, and
  volunteer hours with a "Download certificate" action.

**Launch splash.** An animated splash plays once at app start
([lib/screens/splash_screen.dart](lib/screens/splash_screen.dart)): an emerald
"warp field" of sparks bursts from behind the brand mark while the summit logo
scales in, holds, then recedes, cross-fading into the first real screen (auth
gate or, in sample mode, the app). Duolingo-style haptics pulse through the
burst; tap to skip. The brand mark is rebuilt in Flutter as a `CustomPainter`
([lib/widgets/summit_logo.dart](lib/widgets/summit_logo.dart)) — no image asset.
The native iOS launch storyboard and Android launch background are set to the
same deep emerald (`#02100B`) so cold start flows into the burst with no white
flash.

**Accounts & sign-in** (live when Supabase is configured):
- **Passwordless email OTP.** A user enters their email, gets a numeric code,
  and types it in — no password is ever created or stored. First-time sign-in
  creates the account. In sample mode (no backend) the app skips auth and opens
  straight to the demo data.
  - **Dev/test login (dev project only).** A `test_accounts` table + `dev-login`
    Edge Function let designated "code emails" sign in **without an OTP** and
    simulate that account — with a *real* session, so permissions/RLS behave for
    real. Make one code email per privilege scenario. Guarded twice (a
    `DEV_LOGIN_ENABLED=true` function secret **and** an app built with
    `--dart-define DEV_LOGIN=true`) and must never be enabled in production. See
    [SUPABASE.md](SUPABASE.md) §3b.
- **Google sign-in (native).** A "Continue with Google" button sits alongside
  the OTP flow, using `google_sign_in` → `supabase.auth.signInWithIdToken` (no
  custom URL scheme / deep-link redirect). Because accounts are keyed to a
  confirmed email, signing in with Google links to an existing OTP account with
  the same address — **same user, same profile and data** — and vice versa;
  Supabase's automatic identity-linking handles this (both OTP and Google
  produce a confirmed email). The button only appears when a Web client ID is
  configured (`GOOGLE_WEB_CLIENT_ID` in `env.json`), so OTP-only builds are
  unaffected. Config it needs: Google Cloud OAuth clients (**Web** — the
  `serverClientId` on both platforms and the value pasted into Supabase's Google
  provider; **iOS** — its reversed client ID is in `ios/Runner/Info.plist`;
  **Android** — package `com.emeraldsummit.emerald_summit` + signing SHA-1),
  and the **Google provider enabled** in Supabase Auth. Client IDs are injected
  from `env.json` (see `env.example.json`), never committed.
- **Role-based onboarding.** First run collects name + **role**, then asks
  **role-specific** details. The five roles are **participant**, **expert**,
  **parent / spectator** (open to anyone — the last covers non-participating
  middle-schoolers), and the two gated roles **volunteer** and **admin**.
  Volunteers get the full contact/emergency-contact questionnaire; experts are
  kept light (org + expertise only); admins need nothing extra. Fields are
  declared per role in [lib/models/user_profile.dart](lib/models/user_profile.dart),
  so the sign-up flow customizes itself. A volunteer's **subtype** (EAF
  ambassador / parent / student) and permissions come from the sheet, not the
  picker. *(Per-subtype onboarding questions are a planned refinement — see
  Roadmap.)*
- **Gated management roles.** Anyone can be a participant/expert/parent, but
  **volunteer** and **admin** are verified against an allowlist synced from two
  Google Sheets (see "Roles & permissions" below). Picking a gated role you're
  not listed for is blocked with *"You aren't eligible to sign up as a
  volunteer/admin."*
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
  app_state.dart            Catalog, schedule, announcements, profile, roles (talks only to backend/)
  app_navigation.dart       Global selected-tab notifier + tab-index constants (banner/dashboard → tabs)
  models/models.dart        Discipline, Session, Announcement, GalleryPhoto, ResourceDoc, disciplineIcon()
  models/user_profile.dart  UserProfile + SummitRole + per-role fields + scope helpers
  backend/                  The backend seam — see "Swapping backends" under Backend
    backend.dart              Re-exports the contracts + BackendDescriptor
    auth_service.dart         Abstract AuthService, AuthUser, AuthFailure (neutral)
    repositories.dart         Abstract Catalog/Content/Schedule/Profile/Announcements/Allowlist/Gallery repos
    service_locator.dart      get_it wiring + configureBackend() (the single switch point)
    supabase/                 The Supabase implementation — ONLY place supabase_flutter is imported
    sample/                   In-memory implementation (standalone/demo mode)
  data/sample_data.dart     Static seed content used by the sample backend + resources hub
  widgets/in_app_banner.dart  Instagram-style in-app banner (controller + host)
  widgets/summit_logo.dart    Brand mark rebuilt as a CustomPainter (no asset)
  screens/
    splash_screen.dart      Animated launch splash (warp burst + logo + haptics)
    root_nav.dart           Bottom navigation shell (Home · Schedule · Discover · News · Resources)
    dashboard_screen.dart   Home launchpad (greeting, photo slideshow, quote, up-next, action grid, links)
    auth/                   auth_gate, sign_in_screen, onboarding_screen (+ role gate)
    schedule_screen.dart    Schedule tab (personal schedule; header reads "My Day")
    discover_screen.dart    Disciplines grid (+ admin "New discipline")
    discipline_screen.dart  Sessions in a discipline (+ mentor/admin edit)
    session_detail_screen.dart   Marketing page + add/remove (+ admin "Manage volunteers")
    session_editor_screen.dart   Create/edit a session (admin/ambassador; room dropdown)
    session_volunteers_screen.dart  Assign/unassign volunteers to a session (admin)
    session_roster_screen.dart   A session's roster + mark attendance (assigned volunteer)
    my_assignments_screen.dart   A volunteer's assigned sessions
    front_desk_screen.dart       Summit-wide check-in (front-desk capability)
    rooms_manager_screen.dart    Admin rooms catalog CRUD
    discipline_editor_screen.dart  Create a discipline (admin)
    announcement_compose_screen.dart  Post an announcement (admin / scoped volunteer)
    announcements_screen.dart, resources_screen.dart, profile_screen.dart
supabase/                   SQL migrations + Edge Functions (see Backend)
test/widget_test.dart       Widget tests
```

## Backend
- **Supabase** (hosted Postgres + auth + storage) is the chosen backend
  (Firebase was considered; Supabase won). Client via `supabase_flutter`.
- **The app is backend-agnostic behind a seam** (`lib/backend/`). All app code
  (screens, `app_state`) depends only on abstract contracts —
  [auth_service.dart](lib/backend/auth_service.dart) and
  [repositories.dart](lib/backend/repositories.dart) — never on a backend SDK.
  Supabase is one implementation of those contracts, living entirely under
  [lib/backend/supabase/](lib/backend/supabase/) (the only place `supabase_flutter`
  is imported); an in-memory [sample/](lib/backend/sample/) implementation powers
  standalone/demo mode. Wiring is via **get_it**, registered once in
  [service_locator.dart](lib/backend/service_locator.dart). See **Swapping
  backends** below.
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
    routes sign-in → onboarding → app) against the abstract `AuthService`; the
    Supabase implementation is
    [lib/backend/supabase/supabase_auth_service.dart](lib/backend/supabase/supabase_auth_service.dart).
- **Data model (SQL in [`supabase/`](supabase/)).** Run the files in
  [SUPABASE.md](SUPABASE.md)'s order to create these:
  - `disciplines` — the catalog categories (public read; **admin** write).
    [disciplines_setup.sql](supabase/disciplines_setup.sql)
  - `sessions` — activities under a discipline (public read; **admin, or a
    volunteer who can edit sessions and is scoped to the discipline**, write).
    `enrolled` is never stored — the `sessions_with_counts` **view** derives it
    live from `registrations` and adds the discipline name. Gains a `room_id`
    (→ `rooms`) in the volunteers upgrade. [sessions_setup.sql](supabase/sessions_setup.sql)
  - `registrations` — the personal schedule (RLS: each user only their own).
    Adds/removes go through the **`register_for_session` RPC**, the single
    server-side enforcer of capacity + no-time-overlap. Gains `attended` /
    `attended_at` / `marked_by` for session attendance.
    [registrations_setup.sql](supabase/registrations_setup.sql)
  - `profiles` gains `notifications_enabled`, `volunteer_hours`,
    `managed_disciplines` (a volunteer's scope; `{'*'}` = all), and the
    server-owned volunteer columns `volunteer_subtype` + `can_edit_sessions` /
    `can_post_announcements` / `can_check_in_front_desk`.
    [profiles_extend.sql](supabase/profiles_extend.sql),
    [profiles_capabilities.sql](supabase/profiles_capabilities.sql)
  - `rooms` — the room catalog (public read; **admin** manage — rename/reorder/
    delete; **admins + session-editing volunteers** may INSERT so a missing room
    can be added inline from the session editor). `sessions.room_id` references
    it; auto-seeded from existing sessions.
    [rooms_setup.sql](supabase/rooms_setup.sql),
    [rooms_editor_insert.sql](supabase/rooms_editor_insert.sql)
  - `session_volunteers` — volunteer↔session assignments. Assigning goes through
    the admin-only, overlap-guarded **`assign_volunteer_to_session` RPC**; being
    assigned is what unlocks a session's roster + attendance. The RPC also posts
    the assignee a personal notification and returns `registered_confirm` if the
    volunteer is already registered for that session (so the admin can confirm).
    **Unassigning** goes through **`unassign_volunteer_from_session`**, which
    removes the row, deletes the stale "you're managing X" notice, and posts a
    "you're no longer managing X" notice — both assign and unassign reach the
    volunteer as a feed item + live in-app banner, and their Schedule/managing
    list update live.
    [session_volunteers_setup.sql](supabase/session_volunteers_setup.sql),
    [assignment_notifications.sql](supabase/assignment_notifications.sql),
    [unassign_notification.sql](supabase/unassign_notification.sql)
  - `summit_checkins` + attendance RPCs — session rosters
    (`fetch_session_roster` / `mark_session_attendance`, gated by assignment) and
    the summit-wide front-desk directory (`fetch_attendee_directory` /
    `mark_summit_checkin`, gated by the front-desk capability).
    [attendance_setup.sql](supabase/attendance_setup.sql)
  - `announcements` gains `created_by` + `discipline_id`, **admin** write
    policies, and **Realtime**. [announcements_write_setup.sql](supabase/announcements_write_setup.sql)
    Later gains `target_user_id` for **personal** announcements (RLS: a targeted
    row is readable only by its recipient) and `session_id` (so an assignment
    notice can be cleaned up on unassign), used by assign/unassign notifications.
    [assignment_notifications.sql](supabase/assignment_notifications.sql),
    [unassign_notification.sql](supabase/unassign_notification.sql)
  - **Photo sets = public Storage buckets** (no table). Each photo set in the
    app is a public bucket, and **every image in it is shown**; curation is just
    uploading/deleting files. The app **lists** the bucket
    (`SupabaseGalleryRepository.fetchPhotos(bucket)`) and builds a public CDN URL
    per file with `getPublicUrl`. Public read/**list** + **admin** write on the
    bucket's objects (the list policy is intentional here). Different parts of
    the app point at different buckets — the **dashboard slideshow** reads
    `gallery_photos` (`AppState.dashboardGalleryBucket`); a new section just adds
    a new bucket + a `fetchPhotos` call. This is the **first use of Supabase
    Storage**. [gallery_setup.sql](supabase/gallery_setup.sql)
  - Seed the six disciplines + sample sessions with
    [seed_catalog.sql](supabase/seed_catalog.sql).
- **Roles & permissions.** Five roles: `participant`, `expert`, `parent`
  (open), `volunteer`, `admin` (gated). Base enforcement is in
  [role_allowlist_setup.sql](supabase/role_allowlist_setup.sql); the volunteer
  upgrade is in [role_allowlist_v2.sql](supabase/role_allowlist_v2.sql):
  - `role_allowlist(email, role, disciplines[], subtype, can_edit_sessions,
    can_post_announcements, can_check_in_front_desk)` is the synced source of
    truth. A user may read only their **own** row.
  - A **`profiles` BEFORE INSERT/UPDATE trigger** is the real gate: it refuses
    to set `role` to volunteer/admin unless the email is allow-listed (forcing
    `participant` otherwise), and it **owns** every volunteer column —
    `managed_disciplines`, `volunteer_subtype`, and the three capability flags —
    setting them from the sheet (applying subtype defaults for blank capability
    cells: EAF ambassadors edit sessions by default; parents/students don't;
    announcements + front-desk are opt-in). Self-elevation via a crafted API
    call is impossible.
  - Capabilities are the levers: `can_edit_sessions` (session CRUD, scoped to
    `managed_disciplines`), `can_post_announcements` (post to a managed
    discipline), `can_check_in_front_desk` (summit-wide check-in). Being
    **assigned to a session** (admin action, not a sheet flag) is what unlocks
    that session's roster + attendance — for any subtype.
  - Helpers `is_admin()`, `can_manage_discipline(id)`, `can_post_to_discipline(id)`,
    `can_check_in_front_desk()`, and `is_assigned_to_session(id)` back the write
    policies and the SECURITY DEFINER RPCs.
  - The allowlist is filled by the **`sync-allowlist` Edge Function**
    ([supabase/functions/sync-allowlist](supabase/functions/sync-allowlist)),
    which reads two **private Google Sheets** (volunteers `A:F`, admins) via the
    **Google Sheets API using a service account** — the sheets stay unpublished,
    so no volunteer/admin emails are ever exposed on a public link — and
    upserts/prunes rows on a cron. A reconcile trigger re-applies changes to
    existing profiles (including demoting anyone removed from a sheet). Setup in
    [SUPABASE.md](SUPABASE.md).
- Note the dev project has "auto-expose new tables" **off**, so every table's
  SQL must `grant` privileges to the right role explicitly (`anon` for public
  reads, `authenticated` for per-user tables).
- **Keys:** use the **publishable** key (`sb_publishable_…`), not the deprecated
  anon key; never the secret / `service_role` key in the app.
- Separate Supabase projects for **dev/testing** and **production** (prod added
  later; the free tier allows two).

### Swapping backends
The seam is designed so that moving off Supabase touches **only the new
backend's folder plus one line** — no screen, `app_state`, or model changes:

1. Add `lib/backend/<name>/` with a class per contract
   (`<Name>AuthService implements AuthService`, `<Name>CatalogRepository
   implements CatalogRepository`, …) and a `<Name>Backend.register(getIt)`
   composition root (model it on
   [supabase_backend.dart](lib/backend/supabase/supabase_backend.dart)). Register
   a `BackendDescriptor` with the backend's display name.
2. Put its credentials in a config under that folder (mirroring
   [supabase_config.dart](lib/backend/supabase/supabase_config.dart)), injected
   via `--dart-define`.
3. Point [configureBackend()](lib/backend/service_locator.dart) at the new
   `register()`.

**The row contract:** repositories return the app's models, whose
`fromMap`/`toMap` in [models/](lib/models/) expect specific keys (snake_case, as
Supabase returns them). A new backend's adapter is responsible for shaping its
rows to those keys — that (plus the `register_for_session`-style capacity/overlap
enforcement, which the sample backend shows how to do in-process) is the whole
porting surface. Everything in the "Data model" section above is Supabase's
*implementation* of the contract, not part of the app.

## Configuration (backend keys)
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
> In **VS Code / Cursor**, a committed [.vscode/launch.json](.vscode/launch.json)
> carries the flag automatically: pick **"Emerald Summit (Supabase)"** from the
> Run menu (or **"Emerald Summit (sample data)"** for the offline/demo build). In
> Android Studio, add the flag under the run configuration's "Additional args".

> **Seeing sample data when you expected the backend?** The launch is missing the
> flag. `SupabaseConfig`'s credentials are *compile-time* constants, so a plain
> `flutter run` (or the IDE's default run) boots in sample mode — the News tab
> shows "Sample data — no backend configured yet" and Discover shows the sample
> disciplines. Relaunch with the flag (or the VS Code "Supabase" config).

### Dev-testing build vs. production build (the `DEV_LOGIN` bypass)
The **code-email login bypass** (sign in as a test account without an OTP — see
[SUPABASE.md](SUPABASE.md) §3b) is controlled by the `DEV_LOGIN` compile-time
flag, injected from `env.json` like the Supabase keys. Because it's a login
backdoor, it is **off by default** and must be enabled in **two** places at once
— either alone does nothing.

**To build for DEV testing** (your dev Supabase project only):
1. In your **dev** `env.json`, add `"DEV_LOGIN": true` alongside the dev
   project's URL + publishable key. (`env.json` is gitignored, so this flag never
   reaches source control or another machine.)
2. On that **dev** project, deploy the `dev-login` Edge Function and set its
   `DEV_LOGIN_ENABLED=true` secret, and run `test_accounts_setup.sql` (full steps
   in [SUPABASE.md](SUPABASE.md) §3b).
3. Run/build as usual with `--dart-define-from-file=env.json`. Code emails now
   bypass OTP; everyone else uses normal OTP.

**To build for PRODUCTION** (never ship the bypass):
1. Use your **production** `env.json` — the prod URL + publishable key — with
   **`DEV_LOGIN` absent or `false`**. The committed [env.example.json](env.example.json)
   ships `false`; keep it that way for any prod/TestFlight build. With the flag
   off the app never even calls the bypass function.
2. On the **production** project, **do not** deploy `dev-login`, **do not** set
   `DEV_LOGIN_ENABLED`, and **do not** run `test_accounts_setup.sql`. That is the
   second guard: even a mis-flagged app can't bypass a project that has no
   enabled function.
3. Sanity check before a release: `grep DEV_LOGIN env.json` should show `false`
   (or nothing). Because `DEV_LOGIN` is a compile-time constant, a release built
   without it has the bypass path dead-stripped.

Keeping separate dev and production Supabase projects (below) is what makes this
clean: the bypass lives entirely on dev.

> **Reusing this in production later (deferred).** The same `dev-login` mechanism
> can double as a *production* testing/demo login (e.g. reviewer or judge
> accounts) — it's the same table + function + flag. **Do not just turn it on**:
> in production it's a real login backdoor, so before enabling it we'd want to
> harden it — at minimum: keep `test_accounts` to a tiny, known set (never real
> attendees); require a shared secret/header on the function call (not just the
> publishable key) and consider re-enabling Verify-JWT with a caller check;
> rate-limit and log every use; and gate the app path behind its own prod flag
> so it can be shipped dark and flipped on only when needed. Treating it as
> "flip `DEV_LOGIN_ENABLED` on prod" would be unsafe. Revisit when we actually
> need prod demo accounts.

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
- ✅ **Role-driven management** — gated volunteer/admin roles from a Google-Sheet
  allowlist the DB enforces; admins post announcements in-app (live via Realtime
  + in-app banner); EAF ambassadors create/edit sessions in their disciplines;
  admins create disciplines. *(code done; needs the SQL + Edge Function deployed)*
- ✅ **Volunteer permissions, rooms & attendance** — the Volunteer role (EAF
  ambassador / parent / student) with per-person capabilities from the sheet;
  an admin rooms catalog that sessions tie to; admin assignment of volunteers to
  sessions (overlap-guarded); per-session roster + attendance for assigned
  volunteers; and summit-wide front-desk check-in. *(code done + **verified
  end-to-end on the dev backend** in the iOS simulator: dev-login + role
  auto-assign for admin/volunteer/expert/spectator; admin session create; the
  rooms dropdown + auto-seeded catalog + inline add-a-room; volunteer assignment
  and the assignment schedule-conflict guard; EAF-ambassador **scoped session
  editing** (edit in own discipline, blocked in others) and **scoped
  announcements** (composer limited to the managed discipline, post allowed by
  RLS); and the sign-out-to-sign-in fix. Front-desk check-in and per-session
  attendance marking are implemented but not yet live-tested. Run the SQL files
  in [SUPABASE.md](SUPABASE.md) + deploy the Edge Functions to activate on a
  fresh project.)*
- ⏳ **Next: OS push notifications** — deliver announcements as real push even
  when the app is closed (see Roadmap for the planned pipeline).

## Roadmap (later, from the spec)
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
- **QR-based front-desk check-in** — the front-desk screen currently checks
  attendees in via a searchable list with a present/absent toggle each; the plan
  is to replace/augment that with a **QR-code scan** (each attendee shows a code;
  the front desk scans to mark arrival). Deferred. Per-session **attendance
  roster marking stays toggle-based** (no QR).
- **Per-subtype volunteer onboarding** — tailor the sign-up questionnaire to the
  volunteer subtype (EAF ambassador / parent / student). Deferred: the subtype
  currently arrives from the sheet *after* sign-up, so all volunteers share one
  questionnaire for now (see [user_profile.dart](lib/models/user_profile.dart)).
- Team formation; spectator seats; check-in dashboard; pre-summit milestone
  reminders; sponsor blocks; post-event social posts; server-rendered
  certificate / feedback PDFs.

## Android
Builds and runs on Android; a release APK has been verified against live
Supabase on-device. Build one with:

```bash
flutter build apk --release --dart-define-from-file=env.json
```

> **Release builds need the `INTERNET` permission declared explicitly.** Flutter
> only auto-injects it into the `debug`/`profile` manifests, so a release APK
> that lacks it fails at runtime with `Failed host lookup … (errno = 7)` on any
> network call (e.g. Supabase auth) — even though debug builds and iOS work
> fine. It's declared in
> [android/app/src/main/AndroidManifest.xml](android/app/src/main/AndroidManifest.xml);
> keep it there.

Release signing isn't configured yet — the APK is currently signed with the
debug key (fine for sideloading to testers, not for Play Store upload).
