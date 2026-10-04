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
> **Archie**, an AI assistant tab (Claude Sonnet 5.5 via a Supabase Edge
> Function, grounded in the live catalog + web search), replaces the old
> Resources tab and is **live on the dev project**. Saved chat history is
> code-complete; run `archie_history_setup.sql` to activate it (see
> [SUPABASE.md](SUPABASE.md) §3c).
> **OS push notifications** (banner when the app is closed) and server-side PDF
> generation are the main things still to come (see Roadmap).

## What's implemented
Five-tab app (**Home · Schedule · Discover · News · Archie**) matching the
spec's core participant features. **Profile is reached from the avatar in the
Home header** (Uber-style), not a bottom-bar tab.

- **Home** — the launchpad ([lib/screens/dashboard_screen.dart](lib/screens/dashboard_screen.dart)).
  A greeting + tappable avatar → Profile, a **photo slideshow** (a 16:9 band of
  event photos that auto-advances every 5s with a cross-fade + page dots, in a
  fresh random order each load; hidden when there are no photos), a
  daily-rotating quote card with brand
  art, an **Up next** card (the next session in your schedule, or a "plan your
  day" nudge when it's empty), a grid of Uber-style **Jump to** action tiles
  (schedule, browse, news with an unread badge, campus map, resources, profile —
  campus map/resources push the Resources screen, which is no longer a tab),
  a horizontal **Explore disciplines** rail into the catalog, a **Latest news**
  peek, and outbound **Links** (website, Instagram, contact) opened via
  `url_launcher`. Exists so the app has an interesting home even before anything
  is added to the schedule. **Touches:** the greeting is a random mix of standard
  ("Good morning") and playful ("What's cooking", "What's building") lines with
  an animated shimmer sweep (echoing the website wordmark); the quote card wipes
  down on first view.
- **Schedule** — the user's full personal schedule (formerly the "My Day" first
  tab; the in-app header still reads "My Day"). Shows **everything they're
  committed to**, each tagged with **how they joined**: sessions they registered
  for (from `registrations`) show **Participating**, **Spectating**, or
  **Expert** (the `participation_type`), and sessions they're **Managing**
  (assignments from `session_volunteers`) show a Managing chip — merged and
  sorted by time (managing wins if both). Each role gets its own chip color.
  RLS-scoped, so it follows the account across devices. A volunteer **assigned to
  manage shows no "Add/Remove to my day"** — it's on their schedule by admin
  action and only an admin can unassign it; the detail page shows a "You're
  managing this session" status instead. An **admin who self-managed** a session
  (see Discover) gets a **"Stop managing"** action there instead. The profile
  entry to the managing list + attendance is labeled **"Sessions I'm managing"**.
  Empty-state → browse flow.
- **Discover** — catalog of the disciplines → each discipline's sessions → a
  **vibrant, tabbed session page.** Reads live from Supabase (`disciplines` +
  `sessions_with_counts` view). The page has a **horizontal, permission-gated tab
  bar** at the top:
  - **Session** (everyone) — the rich page: a big **hero photo** on top (the
    explicit hero, or the first gallery photo when none is set), a **photo
    gallery**, the time/room/expert/seats info, the description, and any
    **editor-authored content sections** (ordered `{title, body}` blocks). **Add
    to my day** is **role-aware**: it opens a chooser whose options depend on the
    signed-in role — participants & volunteers pick **Participate** or
    **Spectate**; experts pick **Serve as expert** or **Spectate**; admins also
    get **Manage** (a self-assignment into `session_volunteers`, with a "Stop
    managing" toggle); and the **Parent / Spectator** role skips the chooser and
    auto-joins as **Spectating**. Volunteers see a note that an admin will assign
    them if they're to *manage* a session. Choosing **Participate** opens a
    full-screen **registration form** ([session_registration_screen.dart](lib/screens/session_registration_screen.dart))
    that always asks the app's **built-in project question** — *"Are you
    participating in a team, or solo?"* — with a note that anyone unsure can
    register solo and change it later. **Solo** requires a project name.
    **Team** offers **Create** (enter the project name → get a **team code** to
    share, shown in a copyable dialog and on the session page) or **Join** (enter
    a teammate's code → the app asks *"Is your project name X?"* → Yes registers
    them under that team). Each team has an **owner** — its creator until they
    hand it over — and a **size limit** the session's editors set (2–8,
    default **4**); a full team can't be joined. Editors can instead make a
    session **solo only** ("No teams allowed"): the form then skips the
    solo/team question and just asks for the project name. Team codes are the discipline's two-letter prefix +
    digits — **TV** TechVerse, **VV** VentureVerse, **BS** BioSphere, **NS**
    NovaSphere, **CV** CivicVerse, **IX** ImagineX (other disciplines use the
    capitals of their name) — e.g. `TV4821`, and only work for the session they
    were created in. The form then collects the session's own **participant
    questions**, if any (answers stored on the registration keyed by question
    id). Joining a team is a normal registration: the session lands on the
    schedule and still counts toward capacity/conflicts. Once registered, a
    **project card** shows the solo project or the team (code, members with the
    owner starred, and a note of the team's max size), with **Leave team / go
    solo** (asks for a solo project name; they stay registered) and, for an
    owner with teammates, **Transfer ownership** and a **remove** button per
    member. A removed member stays registered for the session but is taken off
    the team with no project answer (the page asks them to add their project
    details), is notified, and **can't rejoin that team** with its code. When
    someone **joins a team**, every other member gets a personal *"X joined
    your team"* announcement + banner. Leaving (going solo, switching teams,
    or removing the session from your day, which also takes you off your team)
    sends the remaining members *"X left your team"*; an owner's removal sends
    the other members *"X was removed from your team"*; and whoever becomes
    owner (hand-off, transfer, or the backstop) gets *"You're now the owner"*.
    No team notices fire while a session is being deleted, or when the last
    member leaves. Instead, **deleting a session** (directly, or by deleting
    its discipline in the dashboard) sends everyone who had it on their
    schedule — registrants and its assigned volunteers, except whoever deleted
    it — a personal *"Session cancelled"* notice naming the session and its
    time.
    **Edit my registration** lets them switch solo ↔
    team, create/join another team, rename their team's project, or revise
    answers. An **owner who leaves** their team (going solo, switching teams, or
    removing the session) while teammates remain must first **pick a new
    owner**; if nobody else is on it, the team is deleted (its code stops
    working). All of it goes through
    the server-side `register_for_session` RPC, which records the participation
    type + answers + project and
    still enforces no double-booking (time-conflict dialog) and capacity caps
    (every registration type counts toward capacity), so they can't be bypassed
    from the client. Admin self-manage uses the `set_session_manage` RPC. At
    the bottom, a **"Sessions similar to this"** horizontal rail suggests other
    sessions in the same discipline the user could still add — only ones with
    seats left that **fit an open slot** on their schedule (no time overlap with
    what they've already got), each a photo card with a one-tap **Add**
    (`AppState.suggestedSessions`). The whole rail is hidden when nothing fits.
  - **Participants** (admins, volunteers *assigned* to the session, and the
    session's **editors** — read-only for editors who aren't assigned, since
    marking attendance stays assignment-gated) — the roster
    of people attending (participants + spectators) with attendance toggles (same
    server gate as before). Each row also shows the person's **participation
    type** and, for participants, their **answers** to the session's questions.
    Participants are **grouped by project**: teammates sit under one team header
    (project name, code, *members/limit*, present count, and the **owner**,
    who's listed first and tagged "Team owner"), each solo participant
    gets their own header, then anyone who hasn't shared a project yet, then
    spectators.
  - **Experts** (same gate as Participants — admins, assigned volunteers, and
    the session's editors) — the people who joined this session as **experts**
    ("serving as an expert"), with the same attendance toggles.
  - On both tabs, **tapping a person opens their profile** in a sheet
    ([roster_person_sheet.dart](lib/widgets/roster_person_sheet.dart)): role,
    email + mobile (tap to email / call), their onboarding answers (school,
    grade, expertise, bio…), and their registration here (attendance,
    project/team, answers). The attendance switch sits at the row's trailing
    edge so tapping the row doesn't toggle it. Needs
    `roster_profile_details.sql`; before it's run the sheet says profile
    details aren't available yet.
  - **Volunteers** (admins) — assign/unassign volunteers.
  A plain participant sees only the Session tab. Admins and EAF ambassadors who
  can edit the session's discipline get **Edit** controls (an AppBar pencil + an
  inline button) that open the editor for the whole page — base fields plus the
  hero photo, gallery, content sections, and the **participant questions** asked
  of anyone who joins as a participant — shown below the app's **default
  questions** (solo/team, project name, team code). Editors can't change those,
  except that they can **reword the project question** per session (e.g. *"What
  will you be presenting?"*). It stays a required default question, and blank
  or reset falls back to *"What is your project name?"*. The form, the
  join-team confirmation (which then shows the question + the team's answer)
  and the leave-team dialog all use the session's wording. The editor also has a **Teams** dropdown: *Teams of up to 2–8* (default 4) or
  *No teams allowed — solo only*. Lowering the limit or turning teams off
  never removes anyone — full teams just stop taking members, and people
  already on a team in a now-solo-only session can keep it or go solo, but no
  team can be created or joined. The editor says so: picking a setting that
  affects existing teams (turning teams off, or a limit below a current team's
  size) shows an inline warning with the number of teams, and saving asks to
  confirm. Photos are **uploaded in-app**
  (`image_picker`) into a per-session folder in the public `session_photos`
  Storage bucket; hero/gallery editing needs the session id, so on a brand-new
  session you save first, then reopen to add photos. The editor still ties a
  session to a **room** picked from the admin catalog — and if the needed room
  isn't listed, an **"Add a room…"** option in that dropdown creates it inline
  (admins and session-editing ambassadors; INSERT-only, backend-enforced)
  without leaving the page. Admins also get **New discipline** and **New
  session**. **Disciplines can't be deleted in the app** — not even by admins
  (the API refuses it); the project owner deletes one in the Supabase
  dashboard, which cascades to its sessions, registrations and teams and sends
  each session's "Session cancelled" notices.
  **Only admins can delete sessions** — ambassadors can create and edit but
  get no delete button, and the `sessions` DELETE policy is admin-only.
  **Deleting a session requires typing its exact name**
  (case-sensitive) before the red Delete button enables — a shared
  `confirmByTypingName` dialog, so a big delete can't happen from a stray tap. Assigning a volunteer to a session is overlap-guarded server-side
  (an admin sees *"This person has a schedule conflict…"* if it clashes with
  their other assignments or registrations). If the volunteer is already
  **registered** for that very session, the admin gets an *"…is registered for
  this session. Assign them to manage it?"* confirm first. On assignment the
  volunteer receives an automatic personal announcement + banner. **Editing a
  session's time** is conflict-aware: if the new time would clash with sessions
  people registered for it already have, the editor warns *"…N people will have a
  schedule clash — save anyway?"* (via the `session_time_conflicts` RPC), and on
  save each affected person gets a personal announcement + banner telling them
  the session moved and now overlaps another of theirs
  (`notify_session_time_conflicts`). Editors type times in **12-hour form with
  an AM/PM toggle** (a typed "pm" also works); the app converts them to the
  24-hour `HH:mm` stored in `start_time`/`end_time` (`to24HourTime` /
  `to12HourTime` in `models.dart`), and the end must be after the start.
  *(Track and sponsor are no longer editable
  fields — a "track" is just a session — but existing values are preserved.)*
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
  back to sample data when the backend isn't configured. **Swipe-to-delete:**
  every user can **swipe a card left** to remove it. A plain user's swipe hides
  it **from their own feed only** (a per-user dismissal in
  `announcement_dismissals`, RLS-scoped to the owner, with an **Undo** snackbar);
  the announcement stays in place for everyone else. An **admin's** swipe opens a
  choice sheet: **"Remove from my feed"** (the same per-user hide) or **"Delete
  for everyone"**, which **hard-deletes the row** (admin-only DELETE policy) and
  **propagates live over Realtime** so it disappears on every open device.
  Without the dismissals table, swipe-to-hide simply doesn't persist across
  restarts. **OS push** (when the app is closed) is designed but not yet built
  (see Roadmap).
- **Archie** — the in-app **AI assistant**
  ([lib/screens/archie_screen.dart](lib/screens/archie_screen.dart)), a dragon
  mascot in shades (`assets/branding/archie.png`), replacing the old Resources
  tab. Modeled on FTC Bonfire's **Sparky** (FTCScoutingConsole/Server, kept only
  as reference): a Gemini-style screen with a *"Hi {name}, what's the
  move?"* greeting and three tappable **conversation starters** (one tailored
  to the user's schedule, one evergreen, one about a random discipline — edit
  them in `_starters()`), a pill composer with
  Send/Stop, live **progress steps** while it works ("Searching the web for …",
  "Reading ehs.dublinusd.org"), the answer streamed in with a ChatGPT-style
  **typing reveal** (a ticker paces the text and speeds up when behind) with
  matching **haptics** (a light tap as it starts and ends, soft throttled ticks
  while it types), markdown
  rendering, **source chips** for the web pages it cited, copy, retry, and New
  chat. The header has **Your chats** (history) flush right; **New chat**
  slides in beside it only once a conversation exists. It follows the app's
  **appearance**: a deep emerald night in dark mode, a soft mint-white in light
  mode (`_ArchieColors.dark` / `.light`), and the bottom bar takes Archie's
  backdrop while the tab is open.
  - **Saved chats.** Each finished question + answer is saved to the user's
    account ([archie_history_setup.sql](supabase/archie_history_setup.sql));
    the header's **history** button opens *Your chats* to reopen or delete
    them. Each exchange is saved with one atomic RPC, `archie_save_exchange`
    (chat + question + answer in a single transaction); a failed save shows a
    one-time *"Couldn't save this chat"* snackbar instead of failing silently.
    *(An earlier build saved with a client-side bulk insert: the Supabase
    client's `defaultToNull` filled the question row's missing `sources` /
    `steps` with NULL, the NOT NULL check rejected it, and the error was
    swallowed — leaving empty chats that opened blank. Fixed by the RPC; the
    migration deletes the empty chats.)* Limits are enforced in the database,
    not just the UI: **10 chats per user** (starting an 11th drops the
    least-recently-used) and **15 questions per chat**. At the limit the composer is replaced by *"This conversation is
    too long. Please start a new chat."* (the hint counts down the last 3). A
    notice under the composer and in *Your chats* says chats are saved and
    reviewed **anonymously** to improve Archie. The server still keeps no chat
    state for the model — the app resends the visible transcript each turn.
  - **Archie insights** (admins, Profile → *Archie insights*): recent
    question/answer pairs across all users with **no identity attached**
    (`archie_recent_exchanges` RPC), to spot content gaps and check answers.
  - **Backend:** the [`archie-chat`](supabase/functions/archie-chat/index.ts)
    Edge Function calls **Claude Sonnet 5.5** (`claude-sonnet-5-5`; override
    with the `ARCHIE_MODEL` secret — adaptive thinking at `ARCHIE_EFFORT`
    `medium`, server-side refusal fallback) and streams **SSE** events
    (`status` / `delta` / `sources` / `done` / `error`). Every request sends
    the full persona + data + conversation (the API is stateless). **Web
    search/fetch are Anthropic *server tools*:** the function only declares
    them; Anthropic runs the searches/fetches and feeds results back to the
    model inside the same API call (capped at 3 searches / 3 fetches per
    answer, billed on the Anthropic account). The function just watches the
    stream — turning tool calls into `status` steps and citations into
    `sources` — and resumes a long turn if the API returns `pause_turn`.
    (Unlike Sparky, whose Spring AI tools run on its own server.) Grounding,
    in priority
    order: the **live app data** (disciplines, sessions + seats left, rooms,
    recent announcements, and the caller's own profile + schedule — read with
    the **caller's JWT** so RLS applies), then the **knowledge base** (below),
    then the **official sites** (summit / EHS Academic Foundation,
    ehs.dublinusd.org, dublinusd.org) via `web_fetch`, then general
    **`web_search`** (located to Dublin, CA). Which source to use is Claude's
    judgment, steered by that priority list in the persona; the web is meant
    for what the app data and knowledge base don't cover. Scope is the summit,
    EHS, and summit-related topics; off-topic requests are politely declined.
    A per-user **daily question cap** (default 50,
    [archie_setup.sql](supabase/archie_setup.sql)) guards cost. Each call logs
    an `archie_usage` line (model, input / cache-read / cache-write / output
    tokens, web searches) in the function's Logs. The Anthropic key lives only
    in the function's secrets. Sample mode uses a canned, catalog-aware
    stand-in so the UI works offline.
  - **Prompt caching** (cache reads cost ~10% of normal input on Sonnet 5.5;
    a cache matches only an *exact* prefix and is reusable only at marked
    breakpoints). The request is laid out from least to most likely to change,
    using all 4 breakpoints the API allows:
    `[persona][knowledge base][sessions ◆][announcements ◆][seats left ◆][user's own info][conversation ◆]`.
    The three shared blocks are byte-identical for every user (fully ordered
    queries; personal notices live in the per-user block), so one cached copy
    serves everyone. A registration only re-caches the short seats block, a
    new announcement re-caches announcements + seats, and automatic caching
    re-reads earlier turns of a conversation from cache. Entries live ~5
    minutes, so savings are largest on busy days and within a conversation.
  - **Knowledge base** —
    [supabase/archie/knowledge.md](supabase/archie/knowledge.md), an
    organizer-maintained fact sheet (summit logistics, disciplines/tracks, past
    summits, the EHS Academic Foundation, Emerald High, Dublin USD, FAQ) so
    common questions are answered without web search — faster, cheaper, and
    under your control. Seeded from the official sites with `TODO` comments for
    what only organizers know (exact date/times, check-in, parking, food,
    eligibility). It lives in the **private Storage bucket `archie`**
    ([archie_knowledge_setup.sql](supabase/archie_knowledge_setup.sql)): the
    function reads it with the service role, caches it ~5 minutes, strips HTML
    comments (editor notes), and puts it right after the persona, inside the
    cached prefix. **To update: edit the file, upload it to the bucket as
    `knowledge.md` — no redeploy.** (A file bundled with the function was
    avoided because dashboard and CLI deploys handle extra files differently.)
    Don't copy session times/rooms/seats into it; those come live from the app.
  - **The persona** is the `PERSONA` constant in
    [index.ts](supabase/functions/archie-chat/index.ts) (identity, sources and
    their priority, grounding rules, scope, style — contact
    president@ehsacademics.org, no emojis, treat earlier answers as settled).
    **Edit it in the repo and deploy with the CLI**, not in the dashboard
    editor: a CLI deploy overwrites dashboard edits (this happened once and
    was merged back by hand).
  - **Cost** (rough estimates on Sonnet 5.5; check the `archie_usage` logs for
    real numbers): ~1–2¢ for a question answered from app data, ~6–8¢ when it
    searches the web (search results are large and carry a per-search fee),
    roughly half of Opus 5.5. Usage is bounded by the daily cap, not the
    10-chat limit (which only bounds storage). Set a monthly spend limit in
    the Anthropic Console as the hard ceiling.
  - **Supabase storage & egress.** Chat history is tiny next to photos: a
    question + answer is ~1–3 KB, so even a user who maxes out 10 chats × 15
    questions stores well under 1 MB, and realistic totals are a few MB for
    the whole summit (free plan: 500 MB database). Egress per question is the
    function's catalog read (now only the columns Archie uses) plus the
    streamed answer — tens of KB — and opening a saved chat is similar.
    Thousands of questions stay well inside the free plan's egress; Storage
    photos remain the egress risk (see the `CachedNetworkImage` note).
- **Resources** — searchable document hub (sample documents). No longer a tab;
  opened from the Home **Campus map** / **Resources** tiles.
- **Profile** (reached from the Home-header avatar) — contact card with role
  badge (volunteers also show their **subtype** and the discipline(s) they
  manage), notifications toggle, an **Appearance** picker (Light / Dark /
  System, saved per device — see Theming below; on narrow screens or large
  text it drops the icons and keeps labels on one line), and role-gated shortcuts: **My sessions**
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

**Theming (light & dark).** The app has a light theme and an emerald-night
dark theme ([lib/theme.dart](lib/theme.dart)); the user picks **Light, Dark,
or System** in Profile → Settings. The choice is a per-device preference kept
in `shared_preferences` ([lib/theme_setting.dart](lib/theme_setting.dart)),
not on the account, and is loaded before `runApp` so there's no flash.
Convention: widgets read `Theme.of(context).colorScheme` roles instead of the
raw `EmeraldTheme` constants — `primary` (emerald / mint in dark),
`secondary` (deepEmerald), `onSurface` (ink), `surfaceContainer` (mist) — so
they follow the mode. The Home hero band and the launch splash keep their
fixed brand colors in both modes.

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
  Collection is kept minimal: participants give school + grade (required) and
  an optional mobile; volunteers give a mobile number only; experts give area
  of expertise + a required one-line bio (the placeholder cycles through
  example bios) and an optional mobile, noted as used only to reach them
  day-of; parents/spectators and admins give nothing extra. Every phone field
  notes the number isn't shown publicly (true: `profiles` RLS is own-row
  only; the one other reader is the organizers of sessions the person
  registered for, via the roster profile sheet). Fields are
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
  theme.dart                Brand palette & Material 3 light/dark themes
  theme_setting.dart        Light / Dark / System choice, saved on device
  app_state.dart            Catalog, schedule, announcements, profile, roles (talks only to backend/)
  app_navigation.dart       Global selected-tab notifier + tab-index constants (banner/dashboard → tabs)
  models/models.dart        Discipline, Session, Announcement, GalleryPhoto, ResourceDoc, disciplineIcon()
  models/user_profile.dart  UserProfile + SummitRole + per-role fields + scope helpers
  backend/                  The backend seam — see "Swapping backends" under Backend
    backend.dart              Re-exports the contracts + BackendDescriptor
    auth_service.dart         Abstract AuthService, AuthUser, AuthFailure (neutral)
    repositories.dart         Abstract Catalog/Content/Schedule/Profile/Announcements/Allowlist/Gallery/Archie repos
    service_locator.dart      get_it wiring + configureBackend() (the single switch point)
    supabase/                 The Supabase implementation — ONLY place supabase_flutter is imported
    sample/                   In-memory implementation (standalone/demo mode)
  data/sample_data.dart     Static seed content used by the sample backend + resources hub
  widgets/in_app_banner.dart  Instagram-style in-app banner (controller + host)
  widgets/summit_logo.dart    Brand mark rebuilt as a CustomPainter (no asset)
  widgets/roster_person_sheet.dart  Organizer-only profile sheet opened from a roster row
  screens/
    splash_screen.dart      Animated launch splash (warp burst + logo + haptics)
    root_nav.dart           Bottom navigation shell (Home · Schedule · Discover · News · Archie)
    dashboard_screen.dart   Home launchpad (greeting, photo slideshow, quote, up-next, action grid, links)
    auth/                   auth_gate, sign_in_screen, onboarding_screen (+ role gate)
    schedule_screen.dart    Schedule tab (personal schedule; header reads "My Day")
    discover_screen.dart    Disciplines grid (+ admin "New discipline")
    discipline_screen.dart  Sessions in a discipline (+ mentor/admin edit)
    session_detail_screen.dart   Tabbed session page: Session/Participants/Experts/Volunteers (permission-gated)
    session_editor_screen.dart   Create/edit a session (admin/ambassador; room dropdown, hero/gallery, content blocks)
    session_volunteers_screen.dart  SessionVolunteersView — assign/unassign (Volunteers tab, admin)
    session_roster_screen.dart   SessionRosterView + wrapper — roster + attendance (Participants tab / My Assignments)
    my_assignments_screen.dart   A volunteer's assigned sessions
    front_desk_screen.dart       Summit-wide check-in (front-desk capability)
    rooms_manager_screen.dart    Admin rooms catalog CRUD
    discipline_editor_screen.dart  Create a discipline (admin)
    announcement_compose_screen.dart  Post an announcement (admin / scoped volunteer)
    archie_screen.dart      Archie AI assistant tab (welcome + starters, streamed chat, typing reveal)
    archie_insights_screen.dart  Admin: anonymous recent Archie questions + answers
    announcements_screen.dart, resources_screen.dart, profile_screen.dart
  widgets/type_to_confirm_dialog.dart  confirmByTypingName — type-the-name confirm for deletes
supabase/                   SQL migrations + Edge Functions (sync-allowlist, dev-login, archie-chat)
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
    volunteer who can edit sessions and is scoped to the discipline**, insert +
    update; **admin-only** delete).
    `enrolled` is never stored — the `sessions_with_counts` **view** derives it
    live from `registrations` and adds the discipline name. Gains a `room_id`
    (→ `rooms`) in the volunteers upgrade, and `hero_image_url` + `page_blocks`
    (jsonb `[{title, body}]`) for the vibrant session page, plus
    `participant_questions` (jsonb `[{id, prompt}]`) for the questions asked of
    participants — all flow through the view automatically.
    [sessions_setup.sql](supabase/sessions_setup.sql),
    [session_pages_setup.sql](supabase/session_pages_setup.sql),
    [session_participation_setup.sql](supabase/session_participation_setup.sql)
  - `registrations` — the personal schedule (RLS: each user only their own).
    Adds/removes go through the **`register_for_session` RPC**, the single
    server-side enforcer of capacity + no-time-overlap; it also records the
    `participation_type` (`participant`/`spectator`/`expert`) and the
    participant's `answers` (jsonb, keyed by question id), plus their project:
    `project_mode` (`solo`/`team`; null for spectators/experts and older
    registrations), `project_name` (solo) and `team_id` (→ `teams`).
    Participants revise answers + project ("Edit my registration") via the
    **`update_my_registration` RPC**, which only touches the caller's own
    row (`registrations` has no direct UPDATE grant; the older
    `update_registration_answers` is superseded). Gains `attended` /
    `attended_at` / `marked_by` for session attendance.
    [registrations_setup.sql](supabase/registrations_setup.sql),
    [session_participation_setup.sql](supabase/session_participation_setup.sql),
    [registration_answers_edit.sql](supabase/registration_answers_edit.sql),
    [teams_setup.sql](supabase/teams_setup.sql)
  - `teams` — one row per project team: `session_id`, unique `code`
    (discipline prefix via `team_code_prefix()` + 4 random digits),
    `project_name`, `created_by`, `owner_id`. **No client grants** — reached
    only through SECURITY DEFINER RPCs: `find_team` (code lookup for the "Is
    your project name X?" confirm; reports `full`), `register_for_session` /
    `update_my_registration` (create/join/stay/leave; refuse `team_full`, and
    refuse `choose_new_owner` when an owner with teammates leaves without a
    `p_new_owner_id`), `transfer_team_ownership`, and `fetch_my_project` (the
    caller's project, code, owner flag, size limit, and teammates). The size
    limit lives on `sessions.max_team_size` (1–8, default 4; **1 = solo
    only**, where creating/joining a team is refused with `teams_not_allowed`
    and `find_team` reports it). `sessions.project_prompt` holds a session's
    rewording of the project question (null = default); answers are still
    stored as the project name. `remove_team_member` (owner only) takes someone
    off the team and records them in `teams.removed_user_ids`; a trigger on
    `registrations` refuses their rejoining (error `removed_from_team`, also
    reported by `find_team` as `removed`). Triggers post the team notices
    (joined / left / removed on `registrations`, new owner on `teams`). A trigger
    deletes a team when its last registration leaves, and — as a backstop for
    account deletion — promotes the earliest-joined member if the owner
    vanishes without a hand-off.
    [teams_setup.sql](supabase/teams_setup.sql),
    [teams_ownership_setup.sql](supabase/teams_ownership_setup.sql),
    [team_size_limits.sql](supabase/team_size_limits.sql),
    [project_prompt_setup.sql](supabase/project_prompt_setup.sql),
    [team_members_setup.sql](supabase/team_members_setup.sql),
    [team_leave_notices.sql](supabase/team_leave_notices.sql),
    [session_cancel_notices.sql](supabase/session_cancel_notices.sql)
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
    list update live. An **admin can self-manage** a session via the
    **`set_session_manage` RPC** (overlap-guarded, admin-only), which is the
    "Manage" option in the Add-to-my-day chooser and its "Stop managing" toggle.
    [session_volunteers_setup.sql](supabase/session_volunteers_setup.sql),
    [assignment_notifications.sql](supabase/assignment_notifications.sql),
    [unassign_notification.sql](supabase/unassign_notification.sql),
    [session_participation_setup.sql](supabase/session_participation_setup.sql)
  - `summit_checkins` + attendance RPCs — session rosters
    (`fetch_session_roster`, which also returns each registrant's
    participation type, answers, project/team, whether they own the team, and
    — after [roster_profile_details.sql](supabase/roster_profile_details.sql) —
    their `profiles.role` + `details` for the profile sheet; readable by assigned
    volunteers, admins, and the session's discipline editors /
    `mark_session_attendance`, gated by assignment) and
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
  - **Session photos = the `session_photos` bucket**, one folder per session id
    (`<session_id>/…`). Unlike the admin-only galleries above, writes are
    allowed for **admins and the session's discipline editors** — the Storage
    RLS derives the owning session from the folder name and checks
    `can_manage_discipline`. The app uploads in-app (`image_picker` →
    `SessionMediaRepository.uploadPhoto`) and lists a session's folder for its
    gallery; the hero image is a `hero_image_url` column pointing at one of these
    files. [session_pages_setup.sql](supabase/session_pages_setup.sql)
  - **Always load Storage images with `CachedNetworkImage`, never
    `Image.network`.** Storage downloads count against the free plan's
    **Cached Egress** quota (5 GB/month). `Image.network` only caches in memory,
    so photos re-downloaded on every launch and the Aug 29 – Sep 29 2026 cycle
    hit 9.16 GB. That started a grace period that ends **Oct 26 2026**, after
    which overage gets 402s. `cached_network_image` keeps a disk copy, so each
    photo downloads once per device; set `memCacheWidth` to roughly the display
    size so the in-memory cache doesn't thrash while the slideshow loops.
  - Seed the six disciplines + sample sessions with
    [seed_catalog.sql](supabase/seed_catalog.sql).
- **Roles & permissions.** Five roles: `participant`, `expert`,
  `parentSpectator` (open — the "Parent / Spectator" role, which auto-spectates
  any session it adds), `volunteer`, `admin` (gated). *(The `parentSpectator`
  stored value was renamed from `parent` — see
  [rename_parent_to_parent_spectator.sql](supabase/rename_parent_to_parent_spectator.sql).)*
  Base enforcement is in
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
- **Sorting gotcha:** in the Dart client (`postgrest-dart`), `.order(col)`
  sorts **descending** unless you pass `ascending: true` — the opposite of
  the JavaScript client (used in the Edge Functions). Always pass `ascending`
  explicitly — every `.order()` in the app now does. (The bare form had
  reversed reopened Archie chats, the Discover discipline order, each
  discipline's session list, and the rooms list; all fixed. Disciplines and
  rooms now appear in ascending `sort_order` — lowest number first — and
  sessions earliest-first.)
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
- ✅ **Archie AI assistant** — a Claude-backed chat tab (live-data grounding +
  web search, streamed with a typing reveal + haptics) replacing Resources.
  *(`archie-chat` deployed and **working end-to-end on the dev project**.
  Saved chats + Archie insights are code-complete and unit-tested but need
  `archie_history_setup.sql` run and the function redeployed — SUPABASE.md
  §3c.)*
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
