# Emerald Summit '27

The companion app for **Emerald Summit '27** — the Tri-Valley's student-run
STEAM summit at Emerald High, Dublin CA (Saturday, January 23, 2027). This repo is the
production app: Flutter, for iOS and Android.

**Website (separate project, on this backend).** The Emerald Summit website
is a different project: React + TypeScript (Vite), in
[dogethecoderr/Emerald-Summit-Website](https://github.com/dogethecoderr/Emerald-Summit-Website),
live at [emerald-summit.vercel.app](https://emerald-summit.vercel.app/). It
now uses this app's Supabase project, so both share accounts and data, and
its signed-in screens are being matched to the app. Anyone working on that:
start with **Website sync** below.

**Not a competition.** The Summit is a day for students to share project
ideas, work on them together, and get feedback from visiting experts. The
website's copy says so and avoids competing, judging, winners and awards.
Some shared names still use the older words, such as the schedule kinds
`competing` and `judging` on the backend; they are not shown as labels.

**One track = one session.** "Track" and "session" name the same thing: a
track is never a group of sessions. Each discipline's sessions are its
tracks, and assigning a volunteer to manage a session is assigning them to
that track.

> **Status: role-driven backend live.** All screens and interactions work, and
> the backend is wired up and verified end-to-end on the dev project (two-device
> testing). **The "dev" project (`dgrskmykbkvphnaasfzl`) is in practice
> production now:** real users are on it through the app and website. The
> plan is to rename it as prod and copy it into a separate test project, so
> treat every write to it as a write to live data. **Auth (passwordless email OTP, plus native Google sign-in)** is
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

The bottom bar is an Uber-style **floating capsule**
([floating_tab_bar.dart](lib/widgets/floating_tab_bar.dart)): inset from the
sides, just above the home indicator, with a pill behind the selected tab.
Pages scroll behind it, so any scrolling list inside a tab pads its end by
`MediaQuery.paddingOf(context).bottom`. It slides away while you scroll down
and comes back when you scroll up (a quick flick brings it back sooner), and it
always shows at the top of a page and on a tab switch
([scroll_aware_bottom_bar.dart](lib/widgets/scroll_aware_bottom_bar.dart)). It
stays put on Ask Archie and for screen-reader users.

- **Home** — the launchpad ([lib/screens/dashboard_screen.dart](lib/screens/dashboard_screen.dart)).
  A greeting + tappable avatar → Profile, a live **countdown** in the header
  (days, hours, minutes, seconds to the Summit's first session; it appears
  once `summit_settings.summit_date` is set and disappears when the Summit
  starts), a **photo slideshow** (a 2:1 band of event photos that
  auto-advances every 5s with page dots, in a fresh random order each load;
  hidden when there are no photos), a daily-rotating quote card with brand
  art, an **Up next** card (the next session in your schedule, or a "plan your
  day" nudge when it's empty), a **Latest announcements** peek, then the
  website's sections in its order: **Support EAF**, **Sponsors**, outbound
  **Links** (Summit website emeraldsummit.ehsacademics.org, Instagram,
  contact) and **About the app** at the very bottom. No Jump to grid and no
  Explore disciplines rail (both gone Nov 14, 2026, like the website's Quick
  access and Explore rows); Discover is the way into the disciplines and
  Profile holds the rest. **Touches:** the greeting is a random mix of
  standard ("Good morning") and playful ("What's cooking", "What's building")
  lines with an animated shimmer sweep; the quote card wipes down on first
  view.
  The three website sections are static text and links, no backend
  ([lib/widgets/home_about_sections.dart](lib/widgets/home_about_sections.dart),
  matching the website's `src/components/home/AboutSections.tsx`):
  - **Support EAF** (the Summit logo beside the text): "This Emerald Summit
    App is brought to you 100% built by students and free for all to use.",
    EAF's support for student-initiated projects, "Please consider
    supporting EAF and its mission.", and **Donate** (EAF's Zeffy form,
    https://www.zeffy.com/en-US/donation-form/be-the-catalyst-for-learning-and-discovery,
    opened in the phone's browser, not embedded) and **Volunteer with EAF**
    (https://www.ehsacademics.org/get-involved/parent-volunteering).
  - **Sponsors**: the five tiers from ehsacademics.org's Emerald Summit '27
    → Sponsor page as a stepped peak, highest first (Capstone $5,000,
    Keystone $2,000, Pillar $1,500, Foundation $1,000, Cornerstone $500,
    each with its perks). Each sponsor's logo sits in its tier and opens
    their website (list in `sponsors` in home_about_sections.dart, logos in
    `assets/sponsors/`). The list still holds last year's sponsors, which
    are out of date and come out (see the to-do **No sponsors on Home**);
    the website's `SPONSORS` is empty until this year's are confirmed. Open spots fill out each tier's row: the first says **Your
    company logo could go here**, the rest are faint dashed slots with a +,
    and all email contact@ehsacademics.org with the tier in the subject.
    Then a note that sponsorships go through EAF and are fully
    tax-deductible, **Become a sponsor** (emails contact@ehsacademics.org)
    and **Sponsorship details**
    (https://www.ehsacademics.org/initiatives/emerald-summit-27/sponsor).
    To add a sponsor (paid ones only), add its logo to `assets/sponsors/`
    and a line to `sponsors`, on both the app and the website.
  - **About the app**: "This app has been 100% built by Emerald High School
    students." with credits: lead developers Arjun Mahajan and Akhil
    Muthyala; developers and testers Nithali Anand, Arush Singh, Guhan Bala
    and Deep Shah.
- **Schedule** — the user's full personal schedule (formerly the "My Day" first
  tab; the in-app header still reads "My Day"). A summary line at the top
  ([day_summary.dart](lib/widgets/day_summary.dart)) gives sessions and time
  booked and how many open sessions still fit (with a
  **Find one** jump to Discover). It doesn't repeat the next session, since Home's
  **Up next** card covers that. The list runs in time order with **"N free"**
  dividers for gaps of 15 minutes or more. On summit day the current and next
  sessions are tagged **Now** / **Next** and finished ones move into a
  collapsed **Past** group at the bottom. It shows **everything they're
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
  `sessions_with_counts` view).
  - **Discover tab:** a **search box** across every session (title, track, room,
    discipline), then one full-width listing per discipline showing a few of
    its real session titles, its start time and how many sessions are open.
  - **Each discipline has its own personality**
    ([discipline_vibe.dart](lib/widgets/discipline_vibe.dart), looked up by
    discipline id, no database column): a palette, a two-tone mark, an animated
    background motif, a band of light that flows around the screen edge, and an
    entrance haptic pattern. **Palettes come from the summit's discipline color
    sheet** (four swatches each; keep them in sync with it): TechVerse
    `#254F93 #119DA4 #6D9DC5 #80DED9`, ImagineX `#DCD6F7 #A6B1E1 #B4869F
    #805D93`, VentureVerse `#FCDE9C #FFA552 #BA5624 #381D2A`, BioSphere
    `#F6FEDB #E6D3A3 #D8D174 #B6C454`, CivicVerse `#DCCCA3 #824C71 #4A2545
    #2B0539`, NovaSphere `#E5C2C0 #8FD5A6 #329F5B #0C8346`. Marks and motifs:
    TechVerse circuit board and circuit pulses; VentureVerse rising chart and a
    climbing chart line; BioSphere DNA and drifting cells with a heartbeat
    border; NovaSphere planet, stars and orbits; CivicVerse scales and gavel
    ripples; ImagineX paint brush and drifting paint. A discipline added later
    gets an emerald default and its stored icon key. Painters and the portal route live in
    [discipline_effects.dart](lib/widgets/discipline_effects.dart). Tapping a
    discipline opens it as a circle of its color growing from the card. The
    effects pause on hidden tabs and turn off under Reduce Motion (a plain
    fade replaces the portal). The page has its own left-edge swipe back,
    since the custom route has none.
  - **Discipline page:** name, topics (the tagline split on commas), a one-line
    count of sessions, open seats and how many are on your day; filter chips
    (All, Open seats, Morning, Afternoon); its sessions (its tracks) grouped
    under start-time headers, each with a seat bar that turns amber when only a
    few seats are left and red when full.
  - The six known disciplines draw their mark from the personality, so the
    `icon` key on their rows only matters for disciplines without one. Keys live
    in `disciplineIcon()` (`gavel`, `lightbulb` and `trending_up` added Oct 2026).
  - **Icons:** two-tone icons come from the Phosphor duotone font, bundled at
    `assets/fonts/Phosphor-Duotone.ttf` (MIT, license beside it) and drawn by
    [duotone_icon.dart](lib/widgets/duotone_icon.dart). The `phosphor_flutter`
    package isn't used because it doesn't build on Flutter 3.47 (`IconData` is a
    final class now). To add an icon, copy its two codepoints into `Duotone`.

  The session page has a **horizontal, permission-gated tab
  bar** at the top:
  - **Session** (everyone) — the rich page: a big **hero photo** on top (the
    explicit hero, or the first gallery photo when none is set), a **photo
    gallery**, the time/room/seats info (the room is hidden for now — see
    [Session rooms: locked](#session-rooms-locked)), an **Expert** line naming
    the approved experts registered for the session (only once at least one
    has; from `session_experts()`, not a typed-in name),
    the description, and any
    **editor-authored content sections** (ordered `{title, body}` blocks). **Add
    to my day** is **role-aware**: it opens a chooser whose options depend on the
    signed-in role — participants & volunteers pick **Participate** or
    **Spectate**; experts pick **Serve as expert** or **Spectate**; admins also
    get **Manage** (a self-assignment into `session_volunteers`, with a "Stop
    managing" toggle); and the **Spectator** role skips the chooser and
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
    from the client. A session can have a **participant deadline** (a date +
    time its editors set): after it, `register_for_session` refuses new
    participants (`participation_closed`), while spectating (and serving as an
    expert) stays open as long as seats are left. People who registered before
    the deadline keep their spot and can still edit their registration. The
    page makes this plain with a card under the session info — *"Register to
    participate by Fri, Jan 15 at 3:00 PM"* while open, a red *"Participant
    registration closed"* (with spectator spots left, or that the session is
    full) afterwards — and the Add-to-my-day chooser greys out **Participate**
    with the closing time. Editors also see a *"No participant deadline"* card
    when none is set. The discipline's session list shows *"N seats left ·
    spectators only"* once it has closed. Admin self-manage uses the `set_session_manage` RPC. At
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
    edge so tapping the row doesn't toggle it. Live on the dev project
    ([roster_profile_details.sql](supabase/roster_profile_details.sql) has been
    run); on a backend without it, the sheet says profile details aren't
    available yet.
  - **Volunteers** (admins, the session's **organizers**, and its **editors**)
    — who's organizing the session: everyone in `session_volunteers` for it
    (admins first, the viewer marked *(you)*), each a card with their role tag;
    tapping one opens the same contact sheet as the Volunteer hub (number,
    copy, **Call** / **Text**). Admins also **assign/unassign** here; for
    organizers and editors it's read-only, so they can see and reach their
    co-workers. Emails stay admin-only.
  - **Metrics** (same gate as Participants)
    ([session_metrics_view.dart](lib/widgets/session_metrics_view.dart)):
    headline counts (registered, schools, marked present), bars by school and
    by grade, and a grades × schools grid. Filters: everyone / participating /
    spectating (experts are left out). Counted on the device from
    `fetch_session_roster`, so it needs no extra SQL.
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
  and the leave-team dialog all use the session's wording. The **Capacity**
  field notes that participants, spectators and experts all count toward it
  and the people managing the session don't. There's no expert
  field: the session page names whoever registered as an expert instead (the
  old `sessions.expert_name` column is left in place but unused). The editor also has a **Teams** dropdown: *Teams of up to 2–8* (default 4) or
  *No teams allowed — solo only*. Lowering the limit or turning teams off
  never removes anyone — full teams just stop taking members, and people
  already on a team in a now-solo-only session can keep it or go solo, but no
  team can be created or joined. The editor says so: picking a setting that
  affects existing teams (turning teams off, or a limit below a current team's
  size) shows an inline warning with the number of teams, and saving asks to
  confirm. A **Deadline to register as a participant** picker (date, then
  time; clearable; local time, stored as `sessions.participant_deadline`)
  sets when participant registration closes, and warns when the chosen time
  has already passed. Photos are **uploaded in-app**
  (`image_picker`) into a per-session folder in the public `session_photos`
  Storage bucket; hero/gallery editing needs the session id, so on a brand-new
  session you save first, then reopen to add photos. The editor ties a
  session to a **room** picked from the admin catalog (locked for now — see
  [Session rooms: locked](#session-rooms-locked)) — and if the needed room
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
  volunteer receives an automatic personal announcement + banner, and the
  session's **other organizers** get *"X is now helping you manage …"* (also
  when an admin self-manages; the assigning admin is skipped). Organizers also
  get a *"New expert"* notice whenever someone signs up for their session as
  an **expert**. *Organizers* means the people assigned to the session (plus a
  self-managing admin) — **not** discipline editors, whose scope is the whole
  discipline rather than one session, so they get neither notice. **Editing a
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
  the app is foregrounded. **Feed cards are previews**: the subject, a two-line
  peek at the message, and an attachment count ("2 photos · 1 file"). **Tapping
  a card opens the full announcement** on its own page
  ([announcement_detail_screen.dart](lib/screens/announcement_detail_screen.dart)):
  audience + pinned chips, sender and full date, the whole (selectable)
  message, photos (tap for a swipeable, pinch-to-zoom full-screen viewer) and
  files (tap to open in the browser/viewer), plus a ⋯ menu to remove it from your
  feed (admins can also delete it for everyone). The Home **Latest news** peek
  opens the same page. **Admins** get a **New announcement** composer
  (subject, message, audience, pin, **photos & files**). Attachments (up to 10,
  10 MB each; photos re-encoded to ≤2000px JPEG) are held locally until
  **Post**, then uploaded to the `announcement_attachments` bucket; if the
  post fails the uploads are removed. The attachment buttons only appear on the
  live backend. **Admin oversight:** admins already receive every discipline
  announcement (broadcast rows are readable by all; only the feed filters by
  audience), and each one carries a line like *"Priya Shah sent an announcement
  to the TechVerse discipline"* on the feed card, the detail page, and the
  in-app banner, so admins can see everything discipline leads post. Personal
  system notices (team joins, assignments…) stay private to their recipient. **Audience targeting:** an announcement aimed
  at a discipline reaches only users who have an **activity in that discipline**
  (plus admins and the volunteers who manage it); "Everyone" reaches all.
  A volunteer with the **post-announcements** capability gets the composer too,
  but scoped: they can only target the discipline(s) they manage. **Personal
  notices** (a `target_user_id`), e.g. *"You have been assigned to manage
  &lt;session&gt; in &lt;discipline&gt;"* when an admin assigns a volunteer,
  go to the bell, not News (see **Notifications** below); their in-app banner
  opens Notifications. Until the bell's table has loaded once, News still
  shows them to their recipient. Filtering is applied to both the feed and the
  banner. **Per-user read state (two-tier, Instagram-style):** opening the
  Announcements tab marks the feed **seen**. The Announcements tab no
  longer shows a count: the bell counts new posts, so a post isn't counted
  twice. Independently, each feed card keeps a green **unread dot**
  until the user taps (opens) that specific card — so dots persist after the red
  badge is gone. Both tiers are private per user, tracked in the
  `announcement_reads` table (a row = seen; `opened_at` = opened), RLS-scoped to
  the owner. The app degrades gracefully: no reads table → "all unseen"; reads
  table but no `opened_at` column → seen/badge work, dots don't persist. Falls
  back to sample data when the backend isn't configured. **Remove from my feed:**
  each card (and the post's own page) has a **⋯** menu with **"Remove this
  announcement from my feed"**, kept out of sight on purpose (there's no swipe
  any more). It asks first, *"Once you remove … you can't get it back in your
  feed. It stays in News for everyone else."*, because it can't be undone (no
  Undo). It's a per-user dismissal in `announcement_dismissals`, RLS-scoped to
  the owner. **Admins** also get **"Delete for everyone"** in the same menu,
  which asks first, **hard-deletes the row** (admin-only DELETE policy) and
  **propagates live over Realtime** so it disappears on every open device.
  Without the dismissals table, a removal doesn't persist across restarts. **OS push** (when the app is closed) is designed but not yet built
  (see Roadmap).
- **Notifications** — the **bell** on Home, beside the avatar
  ([notifications_screen.dart](lib/screens/notifications_screen.dart)), with a
  red count of unread notes. Short notes about you, separate from News: a new
  post that reaches you (*"Priya Shah posted to TechVerse"*, opens the post), a
  personal notice (assignments, team changes, expert approval, the admins'
  sheet and expert-queue notices; opens its session when it has one), and
  *"Coming up at 10:30 AM: AI Playground"* in the hour before a session you're
  in or managing. Each note shows "5m ago" / "2d ago" under it (the website
  shows a date instead once a note is from an earlier day; see the website
  to-do list).
  Tap a note to mark it read; **Mark all as read** clears the
  bell. Rows live in `notifications` and are written only by the backend
  ([notifications_setup.sql](supabase/notifications_setup.sql)): triggers on
  `announcements` fan new posts out to their audience and copy personal
  notices; reminders come from `queue_my_session_reminders()`, which the app
  calls on sign-in and every 5 minutes (they start once `summit_date` is set; a
  pg_cron job can run `queue_session_reminders()` for everyone, for push
  later). Realtime keeps the list live. The website has the same bell and
  list.
- **No notification setting in the app or on the website** (decided Nov 13,
  2026). The in-app banner always shows, in the app and on the website, and
  nothing mutes it. Push, once built, is turned on or off only in the phone's
  own Settings: Profile's **Notifications** row (no switch) opens the app's
  notification settings there (the `app_settings` package; on iPhone, iOS 16
  and up go straight to Notifications). The website has no row at all, since
  it has no browser push. `profiles.notifications_enabled` stays in the table
  (schema changes are additive) but the app's code no longer has the field;
  nothing reads or writes it.
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
  rendering (answers never load images, and only web and email links open,
  since web pages Archie reads can shape its output), **source chips** for the web pages it cited, copy, retry, and New
  chat. The header has **Your chats** (history) flush right; **New chat**
  slides in beside it only once a conversation exists. It follows the app's
  **appearance**: black with a faint emerald glow, green cards and navy chat
  bubbles in dark mode (matching the app's dark theme), a soft mint-white in light
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
    under your control. Written by the organizers: instructions for Archie
    (sources in order: this file and live app data, then the official sites
    and web search, then "I don't know" plus a contact), a table of
    **UNCONFIRMED** items Archie must not guess at, logistics, last year's
    tracks (always labeled as last year's), and an FAQ. It lives in the **private Storage bucket `archie`**
    ([archie_knowledge_setup.sql](supabase/archie_knowledge_setup.sql)): the
    function reads it with the service role, caches it ~5 minutes, strips HTML
    comments (editor notes), and puts it right after the persona, inside the
    cached prefix. **To update: edit the file, upload it to the bucket as
    `knowledge.md` — no redeploy.** From the CLI: `supabase storage rm
    ss:///archie/knowledge.md --linked --experimental`, then `supabase storage
    cp supabase/archie/knowledge.md ss:///archie/knowledge.md --linked
    --experimental` (`cp` refuses to overwrite). (A file bundled with the
    function was avoided because dashboard and CLI deploys handle extra files
    differently.) *(Dev has the 2026-11-14 version: the confirmed date, Saturday,
    January 23, 2027, with the hours still unconfirmed. The function was
    redeployed the same day with the date in the persona.)*
    Don't copy session times/rooms/seats into it; those come live from the app.
  - **The persona** is the `PERSONA` constant in
    [index.ts](supabase/functions/archie-chat/index.ts) (identity, sources and
    their priority, grounding rules, scope, style — contact
    president@ehsacademics.org, no emojis, treat earlier answers as settled).
    A **WRITING** block holds Archie to the app's writing rule (see
    [App writing rule](#app-writing-rule)): no em dashes, no "Great question"
    openers or "let me know" closers, no AI vocabulary, at most one
    exclamation mark. The function's fixed replies (daily limit, off-topic,
    failed answer) follow the same rule. A persona change only takes effect
    after `supabase functions deploy archie-chat --no-verify-jwt --use-api`.
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
- **Profile** (reached from the Home-header avatar) — contact card with role
  badge (volunteers also show their **subtype** and the discipline(s) they
  manage) and a pencil to **Edit profile**
  ([edit_profile_screen.dart](lib/screens/edit_profile_screen.dart), also a
  row under Settings): edit your name and your role's sign-up answers (phone,
  school, grade, expertise, bio…), prefilled, with the same required rules
  and notes as sign-up (school uses the same dropdown, so participants and
  parents/spectators can switch schools, type one under Other, or, for
  parents/spectators, clear it with None); answers from a previous role are kept, a cleared
  optional field is removed, and email + role are shown read-only (role
  changes stay under **Change role**), notifications toggle, an **Appearance** picker (Light / Dark /
  System, saved per device — see Theming below; on narrow screens or large
  text it drops the icons and keeps labels on one line), and role-gated shortcuts: **My sessions**
  (a volunteer's assigned sessions → roster + attendance), **Volunteer hub**
  (volunteers/admins — see below), **Front desk
  check-in** (for front-desk-flagged volunteers/admins — see below), **Manage rooms**
  (admins), **Track volunteer hours** (volunteers/admins only, see below).
  Plus **Change role** (re-runs the gated role picker) and sign-out. Other roles
  see nothing about volunteer hours.

**Metrics** ([metrics_screen.dart](lib/screens/metrics_screen.dart)), admins
only, from Profile → **Metrics**. Filters: participants (default), parents &
spectators, or everyone. Shows headline counts (signed up, schools, in a
session, session sign-ups), sign-ups by school, a **schools × disciplines**
grid (people from each school registered for at least one session in that
discipline; expert registrations are left out), interest by discipline, a
**schools × grades** grid, and sign-ups by grade. Grid cells are shaded by
size, print their number, and show a sentence when tapped. Every count is
distinct people, so someone in two Tech sessions counts once under Tech. Data
comes from `fetch_summit_metrics()`
([summit_metrics.sql](supabase/summit_metrics.sql), admin only): every
onboarded account's role, school and grade (no names or contact details) plus
every registration with its discipline. The counting happens in the app
([metrics.dart](lib/models/metrics.dart)). Grade answers fold into 9–12
("11th" and "Junior" both count as 11), Other, or blank. *(Run on the dev
project 2026-10-20.)*

**Activity log** ([activity_log_setup.sql](supabase/activity_log_setup.sql),
admin only). Database triggers write one `activity_log` row per action, so the
app and the website are both covered and no client can skip it. Recorded:
`account_created`, `signed_up` (onboarding finished, with role, school and
grade), `role_changed`, `profile_edited` (field names only, not values),
`agreed_to_code_of_conduct`, `registered`, `unregistered`,
`removed_from_session` (someone else dropped them), `participation_changed`,
`joined_team` / `left_team` / `switched_team`, `project_edited`,
`answers_edited`, `checked_in` / `check_in_undone`, `summit_checked_in` /
`summit_check_in_undone`, and `volunteer_assigned` / `volunteer_unassigned`.
Since Nov 21, 2026 ([announcement_activity_log.sql](supabase/announcement_activity_log.sql))
also `announcement_posted`, `announcement_edited` and `announcement_deleted`
for posts to everyone or to a discipline (not personal notices, which the
system writes and clears all the time). Each keeps a full copy of the post
(title, text, audience, discipline, pin, attachments), so a deleted post can
be read back and re-posted, and `details.via` says how the change came in:
"website or app" (with the person in `user_id`), "dashboard / SQL" (the
Supabase Table Editor or SQL Editor, no person) or "server key". This was
added after a post was deleted on Nov 21, 2026 with no way to tell who did
it. To check, run the query at the top of that file in the SQL Editor.
Also since Nov 21, 2026 ([activity_log_more.sql](supabase/activity_log_more.sql)),
with old and new values and `details.via`:
`track_created` / `track_edited` / `track_deleted` (a delete keeps a copy of
the track and how many were registered), `summit_setting_changed`
(registration open, session times shown, Summit date), `permissions_changed`
(can edit sessions, can post announcements, front-desk check-in, managed
disciplines, volunteer type, expert status; these follow the Google Sheet, so
most come in with no person and via the sync) and `expert_verified`,
`discipline_created` / `discipline_edited` / `discipline_deleted`,
`hours_logged` / `hours_edited` / `hours_deleted`, and `allowlist_added` /
`allowlist_changed` / `allowlist_removed`. Only real changes are logged: the
sheet sync rewrites the allowlist every 5 minutes, and a rewrite with the same
values logs nothing. The SQL Editor query at the top of that file lists
everything, newest first.
Each row has who did it (`actor_id`), whose record it is (`user_id`), the
session, and a snapshot of the session title so it still reads after the
session is deleted. A logging error never blocks the real action. Deleting an
account deletes that person's rows. Screen views and taps are **not** logged
yet. There is no in-app viewer yet: read the `activity_feed` view (names
joined in) in the Supabase Table Editor or SQL editor. *(Run on the dev project
2026-11-14.)*

**Volunteer hours** ([lib/screens/volunteer_hours_screen.dart](lib/screens/volunteer_hours_screen.dart)),
opened from Profile → Settings → **Track volunteer hours**, for volunteers and
admins only. The total adds up two sources:
- **Summit day (automatic):** every session the person manages (their
  `session_volunteers` rows, which covers both admin-assigned volunteers and
  admin self-manage) counts its end minus its start, but **only once the
  summit date is set and that session has ended on it**. Until then the
  sessions are listed with *Not counted yet*. A note on the screen explains
  this to users. Nothing is stored; the list follows assignments as admins
  change them. Assignments are overlap-guarded, so these never double count.
- **Your logs (manual):** planning meetings, setup, anything else. Each log
  is a date, a start time, an end time, and "What did you do?" (up to 500
  characters); the app computes the length. The end must be after the start
  and not in the future. Tap a log to edit or delete it. Stored in
  `volunteer_hour_logs` ([volunteer_hours_setup.sql](supabase/volunteer_hours_setup.sql)),
  owner-only RLS, writes limited to volunteers and admins.

The total shows as hours (e.g. *4.25*) with a "2.25 logged by you · 2 on
summit day" breakdown. There is no certificate (the old placeholder button was
removed on purpose). The old `profiles.volunteer_hours` column is no longer
read by the app.

> **Summit date: Saturday, January 23, 2027 (set on dev Nov 14, 2026).**
> Summit-day hours count, summit-day sheet rows appear and post-summit feedback
> opens once each session ends that day. Every feature tied to the date is in
> [Summit date: what changes when it's set](#summit-date-what-changes-when-its-set).

**Hours spreadsheet (Google Sheet, synced automatically).** Every volunteer's
and admin's hours go on one Google Sheet in the format of the *Student
Volunteer Timecard 26-27* template, 16 columns. The
[`sync-hours-sheet`](supabase/functions/sync-hours-sheet/index.ts) Edge
Function rewrites the whole hours tab (header row included) from the database,
so edits and deletes in the app show up correctly. Changes mark the sheet
dirty and a once-a-minute cron sends at most one rewrite, so the sheet is at
most about a minute behind; it also rewrites hourly as a safety net
([hours_sheet_sync.sql](supabase/hours_sheet_sync.sql)). Rows:
- **One row per manual log**, and **one row per session managed on summit
  day** (after it ends). Sorted by date and start time; times in Pacific.
- *Timestamp*: when the log was saved (summit rows: the session's end).
  *Email Address* and *Non-DUSD email*: both the account's email. *Name*: the
  profile name. *Student ID*: optional, from sign-up. *Grade*: see below; blank
  for parent volunteers and for admins who skipped it. *Parent name / email /
  phone* and *Board feedback*: always blank. *Date / Start time / End time /
  Volunteer work performed*: from the log (summit rows: `Managed "<session>"
  (<discipline>) on summit day`).
- *External fdbk* (summit rows only): every expert's session feedback for that
  session, one line each, e.g. `John Smith: 5/5. Very well run.`
- *Would like to volunteer for EAF in future?* (summit rows only): Yes / No /
  blank, from the post-summit question.

Status: **live on dev**, writing to
[Emerald Summit App - Student Volunteer Timecard 26-27](https://docs.google.com/spreadsheets/d/1IhGfTqenWUVJhxqt7EZxotpK3YXSePmLqBkqZM-_gwU/edit)
(tab *Volunteer Hours*, pinned with the `HOURS_SHEET_TAB` secret; shared
with the Google service account as Editor). The app owns that tab: anything
typed there by hand is erased on the next sync, so notes go on other tabs.
Renaming the tab means updating `HOURS_SHEET_TAB` too, or syncs fail. See [SUPABASE.md](SUPABASE.md)
step 46.

**After the summit: feedback and "volunteer again?"**
([summit_followup_screen.dart](lib/screens/summit_followup_screen.dart),
[summit_followup_setup.sql](supabase/summit_followup_setup.sql)). Opens once
the summit date is set and the last session of that day has ended (Pacific),
via `summit_feedback_open()`. The app then shows the question once per launch
until it's answered, and keeps a row under Profile → Settings to answer or
change it later:
- **Experts** rate 1 to 5, with an optional comment, three things: the app,
  the summit overall, and each session they served in as an expert
  (`registrations.participation_type = 'expert'`). Stored in
  `expert_feedback`. Session feedback lands in *External fdbk* on the rows of
  every volunteer who managed that session. App and summit feedback are
  stored but not on the hours sheet.
- **Volunteers and admins** answer *Would you like to volunteer for EAF in
  the future?* Yes / No, stored in `eaf_future_interest`.
Writes go through `submit_expert_feedback` / `set_eaf_future_interest`, which
check the role and that feedback is open.

**Archie knows about volunteer hours.** The fact sheet
([knowledge.md](supabase/archie/knowledge.md), "Volunteer hours in the app",
"After the summit", and FAQ entries) explains how tracking works and that it's
for volunteers and admins only. For a volunteer or admin, `archie-chat` also
adds their own hours to the user context (total, each log, each managed session
and whether it counts yet, the summit date, and their "volunteer again?"
answer), counted the same way as the hours screen and read under RLS, so
Archie only ever sees the asker's own hours. Experts get their feedback status
once feedback opens.

**Check-in pass + QR front desk.** Every signed-in user's Profile shows a
**Check-in pass** card right under their contact card
([checkin_pass_card.dart](lib/widgets/checkin_pass_card.dart)): a QR code of
their **user id** (a bare UUID — the same payload as the website's QR pass),
dark-on-white in both themes, a *Checked in · 9:12 AM* / *Not checked in yet*
line (from `my_summit_checkin()`; refreshes on resume and via a refresh button;
hidden if it can't be read), and a full-screen view for scanning. The **Front
desk check-in** screen opens with **live stats**: *Checked in*, *Participants*
and *Volunteers*, each shown as checked-in / total with a progress bar (total
counts every onboarded account, admins included). The stats and the list stay
in sync across every front-desk device through Realtime on `summit_checkins`.
Bursts of changes are debounced, and a 30s poll is the backstop. Then comes
**Scan QR passes**
([front_desk_scanner_screen.dart](lib/screens/front_desk_scanner_screen.dart),
`mobile_scanner`): a scan checks the attendee in **instantly**
(`scan_summit_checkin`) and a result card shows *Checked in* / *Already checked
in* (with the original arrival time) / *No account found* / *Not a check-in
pass*, with **Undo** and **Scan next**. The camera stays live and the same code
is ignored until dismissed, so the next person can be scanned straight away.
Torch toggle; haptics per outcome; camera-denied and no-camera states (Open
Settings on iOS, Try again on Android). The searchable present/absent list stays
below as the fallback for people without their pass. **Camera permission** is
only requested when the scanner opens, which only front-desk volunteers/admins
can reach (`NSCameraUsageDescription`; Android `CAMERA`, with the camera marked
not-required).

**Volunteer hub** ([lib/screens/volunteer_hub_screen.dart](lib/screens/volunteer_hub_screen.dart)),
opened from a Home **Jump to** tile or Profile, for volunteers and admins:
every *other* onboarded volunteer **and admin** (admins listed first) as a
card with their initials and a **Student Volunteer** / **Parent Volunteer** /
**EAF Ambassador** / **Admin** tag, grouped under section headers
(*Admins · 2*, *Student Volunteers · 14*, …), with a search box and filter
chips (All plus one per group, with counts). Tapping a card opens a sheet with their
label and **mobile number** (copy, **Call**, **Text** — `tel:` / `sms:`
links with the number stripped to digits; the Android manifest declares the
`tel`/`sms`/`mailto` intent queries url_launcher recommends, and the iOS
Simulator has no Phone app, so Call only works on a real device). Data comes from the
`fetch_volunteer_hub` RPC ([volunteer_hub.sql](supabase/volunteer_hub.sql)),
which only answers volunteers and admins and returns name + role + subtype +
phone only (no email). Numbers show any time, not only on summit day; the
sign-up note's "the day of" describes what they're for. **Volunteers and
admins must have a mobile number on file:** it's a required sign-up field
for both, and a volunteer or admin who onboarded without one is stopped by
the auth gate at sign-in with an *"Add your number"* screen
([phone_required_screen.dart](lib/screens/auth/phone_required_screen.dart),
`AppState.needsPhoneNumber`) until they save one. *(The first version of the
RPC failed on every call — an unqualified `id` in its role check clashed
with the `id` output column, which PL/pgSQL rejects as ambiguous. The
current file drops and recreates it.)*

**Launch splash.** An animated splash ("Arc Traverse") plays once at app start
([lib/screens/splash_screen.dart](lib/screens/splash_screen.dart)): an emerald
sun rises from behind the left peaks of a mountain range, arcs across a starry
sky and sets behind the right peaks, while the "Emerald Summit '27" wordmark
wipes on as the sun crests. It then fades into the first real screen (auth
gate or, in sample mode, the app). Haptic taps build toward the crest and
settle as it sets; tap to skip. The website's landing intro is modelled on
it: the same sun rises and sets in its hero sky. The brand mark is rebuilt in Flutter as a `CustomPainter`
([lib/widgets/summit_logo.dart](lib/widgets/summit_logo.dart)) — no image asset.
The native iOS launch storyboard and Android launch background are set to the
same deep emerald (`#02100B`) so cold start flows into the burst with no white
flash.

**Design context.** [PRODUCT.md](PRODUCT.md) records the product truth that
design work (the `/impeccable` skill) builds on: student attendees first, the
student-run / hands-on / expert-feedback positioning, and the binding brand
commitments (dragon logo; emerald primary, navy only as a small accent).

**Theming (light & dark).** The app has a light theme and a green-led dark
theme: a true-black background with distinctly green boxes on it (cards,
fills, the nav bar, the Home header), emerald (softened to mint) for actions
and selection, and the logo's navy as a small second accent (`nightBlue` for
secondary/tertiary roles, Archie's chat bubbles) ([lib/theme.dart](lib/theme.dart)); the user picks **Light, Dark,
or System** in Profile → Settings. The choice is a per-device preference kept
in `shared_preferences` ([lib/theme_setting.dart](lib/theme_setting.dart)),
not on the account, and is loaded before `runApp` so there's no flash.
Convention: widgets read `Theme.of(context).colorScheme` roles instead of the
raw `EmeraldTheme` constants — `primary` (emerald / mint in dark),
`secondary` (deepEmerald), `onSurface` (ink), `surfaceContainer` (mist) — so
they follow the mode. The Home hero band is solid (no gradient): emerald in
light mode, deep green in dark (`EmeraldTheme.nightHero`); the launch
splash keeps its fixed brand colors in both modes. [test/theme_contrast_test.dart](test/theme_contrast_test.dart) checks
every text/background role pairing (plus the app bar and outlines) against
WCAG AA in both themes, so a palette tweak can't make text unreadable in one
mode; widgets on the app bar (e.g. the session page's tab bar) take
`appBarTheme.foregroundColor`, not `onPrimary`, since the dark app bar isn't
primary-colored.

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
  an optional mobile; volunteers give a mobile number and an optional
  **student ID** (digits only, goes on the hours sheet); experts give area
  of expertise + a required one-line bio (the placeholder cycles through
  example bios) and an optional mobile, noted as used only to reach them
  day-of; admins give a mobile number (required), an optional student ID and
  an optional grade; parents/spectators give an optional school.
  **School is a dropdown** ([school_picker.dart](lib/widgets/school_picker.dart))
  of Tri-Valley high schools ([schools.dart](lib/models/schools.dart): Dublin,
  Pleasanton, Livermore, San Ramon, Danville) plus **Other**, which opens a
  text box. The saved value is the school's name; an older typed answer like
  "Dublin High" opens on the listed school, and metrics fold variants
  ("Cal High", "DVHS") into the listed name. The participant
  and expert phone fields note the number isn't shown publicly (true:
  `profiles` RLS is own-row only; the one other reader is the organizers of
  sessions the person registered for, via the roster profile sheet). The
  volunteer phone field instead says *"Your phone number will be visible to
  other volunteers the day of for communication with them"*, because the
  **Volunteer hub** shares it; the admin one says it's visible to volunteers
  and other admins. Fields are
  declared per role in [lib/models/user_profile.dart](lib/models/user_profile.dart),
  so the sign-up flow customizes itself. A volunteer's **subtype** (EAF
  ambassador / parent / student) and permissions come from the sheet, not the
  picker. Because the subtype is only known after sign-up, **student volunteers
  and EAF ambassadors** are asked their **grade** (required, for the hours
  sheet) on a screen right after sign-up, like the missing-phone prompt; parent
  volunteers are never asked. Edit profile shows the same field
  (`UserProfile.formFields`). *(Other per-subtype onboarding questions are a
  planned refinement, see Roadmap.)*
- **Expert approval.** Anyone can *pick* Expert, but the account starts
  **pending** and the app shows only an **Awaiting approval** screen
  ([expert_pending_screen.dart](lib/screens/auth/expert_pending_screen.dart)):
  their name, expertise and email; *"If your account isn't approved within 48
  hours, email us at nysha.singhal@ehsacademics.org"* (tap to email); **Check
  again** (also re-checks when the app returns to the foreground); **Sign up as
  something else** (reopens the role picker); and Sign out. Switching to
  Expert from **Change role** lands on that screen right away.
  - **How admins find out:** one rolling personal notice per admin,
    *"Experts waiting for approval"* with the current count (*"2 experts are
    waiting…"*), not one per sign-up. A new waiting expert replaces it so it's
    unread again; a review updates the count; it's deleted once nobody is
    waiting. A **red count on the Home avatar** shows while an expert has
    signed up since the admin last opened Profile (opening Profile clears it,
    stored as `profiles.expert_queue_seen_at`), and a red count **beside
    Expert approvals** shows while anyone is waiting. *(When OS push
    notifications are built, send a push alongside this notice; see Roadmap.)*
  - **Review:** **Profile → Expert approvals**
    ([expert_approvals_screen.dart](lib/screens/expert_approvals_screen.dart)):
    name, expertise, bio, email, phone, sign-up time, **Approve** /
    **Decline**. Approving opens the app for them (with a *"Your expert
    account is approved"* notice). Declining (after a confirm) turns the
    account into a participant, moves its expert sign-ups to spectating (see
    *Role changes* below), and shows a one-time *"Your expert request wasn't
    approved"* note pointing at the same email. Only an
  approved expert can register as an expert for a session
  (`expert_not_approved` otherwise). Experts who signed up before this were
  made pending too. Backend:
  [expert_approval.sql](supabase/expert_approval.sql) and
  [role_change_downgrades.sql](supabase/role_change_downgrades.sql).
- **Role changes move sessions down to spectating.** When someone's role
  changes, any session they're in a way the new role can't be becomes
  **spectating**: participating needs participant, volunteer or admin;
  serving as an expert needs expert; managing needs volunteer or admin. A
  participant leaving their team: a team with other members goes to the
  teammate who joined first (they get the usual owner notice); a team with
  no one else is deleted and its code stops working. Managing a session
  that's full drops it from their day instead; if they were also registered
  for it, they just stop managing. A database trigger on `profiles.role`
  does this, so it covers **Change role**, a declined expert and the
  allowlist sync alike. Before saving, **Change role** shows a box listing
  exactly what will happen to each session (`preview_role_change`, the same
  code with no writes), plus the approval note when switching to Expert; the
  schedule reloads after saving. When someone stops managing sessions this
  way (a volunteer or admin moving to another role), every other admin gets
  one notice, *"A session lost a manager"*, naming the person, the old and
  new roles and the sessions, marking any that now have **nobody managing
  them**, and pointing to the session's Volunteers tab to assign someone.
  The Change role box tells the volunteer the admins will be told.
- **Gated management roles.** Anyone can be a participant/parent (experts need
  an admin's approval, above), but
  **volunteer** and **admin** are verified against an allowlist synced from two
  Google Sheets (see "Roles & permissions" below). Picking a gated role you're
  not listed for is blocked with *"Your email is not on the list of people
  allowed to be a volunteer / an organizer. Please email
  support@ehsacademics.org."* (`SummitRole.notAllowedMessage`, used by
  sign-up and **Change role**; the website says the same since Nov 22, 2026).
  If the list can't be read (offline, server error), it says *"Couldn't
  check the list. Try again. If this keeps happening, please email
  support@ehsacademics.org."* instead (`SummitRoleX.allowlistCheckFailedMessage`),
  so nobody on the list is told they are not.
- **The account is tied to the email**, not the device. The session persists
  across app restarts and auto-refreshes; signing in on another device (or
  after reinstalling) pulls the same profile, role, and data back down. Only
  deleting the app forces a fresh sign-in. This is also what makes the later
  **switch from OTP to Google seamless** — same email → same account.

Brand colors and type follow spec section 03 (Emerald `#0C7A55`, Deep Emerald
`#0A5F43`, Ink `#16211C`, Mist `#EEF5F1`, system fonts).

## Session rooms: locked

**Status: locked** (since 2026-10-18). The owner will say when to turn this
back on; don't flip it without being asked. One switch controls it:
`kSessionRoomsEnabled` in [models.dart](lib/models/models.dart), currently
`false`. While it's off:

- **Session editor:** the room dropdown is disabled (so no inline "Add a
  room…" either) and a lock note sits above it. The room columns are left out
  of the save, so an edit keeps the session's room and a new session starts
  unassigned.
- **Session page** hides the room row.
- **Unchanged:** times stay editable and visible everywhere, time clash checks
  run as before, and the discipline list, Discover, Schedule, Home and the
  organizer screens still show rooms. The lock is in the app only; RLS still
  allows editors to write the room columns.

Setting the constant to `true` restores both the dropdown and the room row.

## Summit date: what changes when it's set

**Status: set to Saturday, January 23, 2027** (confirmed by the organizers;
`summit_date = '2027-01-23'` on dev since Nov 14, 2026). Steps 1 to 4 below
are done on dev. Archie gives the hours as 9 AM to 5 PM (a placeholder set
Nov 14, 2026; change knowledge.md if they move). This section stays as the
reference for what the date drives.

**1. Check session times.** `start_time` / `end_time` are plain text and
everything that compares them assumes 24-hour time (`14:00`, not `2:00`). The
afternoon sessions were corrected on Oct 18, 2026 (Engineering Exhibit
`14:00`–`15:30`, CADathon Workshop `13:30`–`15:00`). Before setting the date,
re-check that nothing new slipped in: `select title, start_time, end_time from
sessions order by end_time;`. Also keep two-digit hours for anything ending
before 10 AM (`09:45`, not `9:45`): Archie compares end times as text when it
works out which summit-day hours count.

**2. Set the date (no app release):**
`update public.summit_settings set summit_date = 'YYYY-MM-DD';` in the SQL
editor or with `supabase db query --linked`. Admins also hold the row's update
policy, but there's no in-app screen for it. The app reads it through
`fetch_summit_status()` at sign-in and when Volunteer hours opens, so relaunch
the app to see it.

**3. These turn on by themselves:**

| Feature | Where | What happens |
|---|---|---|
| Home countdown | `_SummitCountdown` in [dashboard_screen.dart](lib/screens/dashboard_screen.dart) | Appears in the header and counts down to the day's earliest session start from 6 AM on (8 AM if none). Hides once it starts. |
| Home header date | [dashboard_screen.dart](lib/screens/dashboard_screen.dart) | "January 2027" becomes the real day (e.g. "Sat, Jan 23"). |
| My Day on summit day | `_timeline` in [schedule_screen.dart](lib/screens/schedule_screen.dart) | **Now** / **Next** tags; ended sessions move into the collapsed **Past** group. |
| Volunteer hours, summit day | `summitSessionCounted()` in [models.dart](lib/models/models.dart), [volunteer_hours_screen.dart](lib/screens/volunteer_hours_screen.dart) | Each managed session counts once it ends that day. The screen note names the date. |
| Hours sheet | `sync-hours-sheet` function | Adds a summit-day row per managed session once it ends (Pacific). |
| Feedback and "volunteer again?" | `summit_feedback_open()` in [summit_followup_setup.sql](supabase/summit_followup_setup.sql), [summit_followup_screen.dart](lib/screens/summit_followup_screen.dart), Profile → Settings | Opens on summit day once the latest `end_time` across **all** sessions has passed (Pacific); today that's 3:30 PM, set by Engineering Exhibit. Adding a later session moves it. The app re-checks at launch, at sign-in and every time it comes back to the foreground (`didChangeAppLifecycleState` in [root_nav.dart](lib/screens/root_nav.dart)), and the auth gate then asks the question. Planned: a push notification / announcement the moment it opens (see Roadmap). |
| Archie's live context | `archie-chat` function | Tells volunteers and admins the date and which sessions count yet; tells experts whether they've sent feedback once it opens. |

**4. Edit these by hand** (done Nov 14, 2026; they said "January 2027"):
- **Archie's fact sheet** [knowledge.md](supabase/archie/knowledge.md): the
  *When* line, the UNCONFIRMED row about the date and hours, and the FAQ
  answer. Upload it to the `archie` Storage bucket as `knowledge.md` (no
  redeploy). Add the hours there too once they're known.
- **Archie's persona** (`PERSONA` in
  [archie-chat/index.ts](supabase/functions/archie-chat/index.ts)) says "in
  January 2027". Edit it and redeploy the function.
- **`SampleData.eventDate`** in [sample_data.dart](lib/data/sample_data.dart):
  the My Day header banner (`_EventBanner` in schedule_screen.dart) always
  shows this string, and Home falls back to it while the date is unset. Change
  it, or switch the banner to `formatDay(appState.summitStatus.date)` the way
  Home does (either needs an app release).
- The sample-mode Archie reply in
  [sample_archie_repository.dart](lib/backend/sample/sample_archie_repository.dart),
  this README's intro line. The website (a separate project) reads
  `fetch_summit_status()` for its countdown and date line, and its
  "January 2027" copy is still correct, so it needs nothing.

**Not tied to the summit date:** per-session participant deadlines
(`sessions.participant_deadline`, their own timestamps) and front-desk
check-in, which works on any day.

**5. Check:** `select fetch_summit_status();` returns the date. Then in the app:
the Home countdown shows, and Volunteer hours names the date. On summit day,
feedback should open once the last session ends.

## Registration lock and hidden session times

**Status (Nov 20, 2026): registration closed, times hidden. Registration is
scheduled to open at 5:00 AM Pacific on Nov 21, 2026 (see below).** Two switches on
the `summit_settings` row, both `false` by default
([website_switches.sql](supabase/website_switches.sql), already run):

- `website_registration_open`: while false, `register_for_session` refuses
  every new sign-up (participant, spectator or expert, joining a team too)
  with the error `registration_closed`
  ([registration_closed_lock.sql](supabase/registration_closed_lock.sql), run
  after registrations_manage_overlap.sql; already run on Nov 12, 2026). This holds for every caller, the
  app included. Removing a session and editing an existing registration still
  work. The website also greys out "Add to my day" with "Registration will
  open on November 21st". The app has no message for it yet: it shows its
  generic "couldn't update" error. The refusal is an error, not a new outcome,
  because the app reads an outcome it doesn't know as `added`.
- `website_show_session_times`: website only. While false, the website shows
  session times, lengths and deadlines as "TBD". The app ignores it.

**Turning registration on and off.** No app release or website deploy is
needed.

1. Open the Supabase project (`dgrskmykbkvphnaasfzl`) and go to the **SQL
   editor**.
2. Run one of these:

   ```sql
   -- Open registration
   update public.summit_settings set website_registration_open = true;

   -- Close registration
   update public.summit_settings set website_registration_open = false;

   -- See where it stands
   select website_registration_open from public.summit_settings;
   ```

   Or, without SQL: open **Table Editor → summit_settings** and tick or
   untick `website_registration_open`.
3. The server starts accepting or refusing sign-ups as soon as the update
   runs, for the app and the website alike. The website buttons change on
   each person's next page load.

Closing registration doesn't remove anyone. People already on a session stay
on it, and they can still edit or remove their registration. Only new
sign-ups are refused. Session times (website only) work the same way with
`website_show_session_times`. Admins hold the update grant too. If
registration_closed_lock.sql is ever superseded by a newer copy of
`register_for_session`, carry the check over.

**Scheduled opening (set up Nov 20, 2026).** A one-time pg_cron job,
`open-website-registration`, opens registration at 5:00 AM Pacific on Nov 21,
2026. Its schedule is `0 13 21 11 *` because pg_cron on this project runs in
UTC. It runs the same update as above (`website_registration_open = true`),
then unschedules itself, so it runs once and won't fire again next November.
It doesn't touch `website_show_session_times`.

- The switch still works by hand, before and after the job. One catch: if you
  set it back to false before 5 AM, the job sets it to true again at 5 AM. To
  keep registration closed, cancel the job first:
  `select cron.unschedule('open-website-registration');`
- To check that it ran: `website_registration_open` reads true, and the
  Supabase dashboard (Integrations → Cron → Job runs) shows a successful run.
  After it runs, the job no longer appears in `cron.job`.

## App writing rule
Nothing a user reads in the app should sound machine-written. That covers every
on-screen string, sample and seed data, notification text in SQL triggers,
Archie's knowledge base, and Archie's live replies. In practice: plain,
specific, short sentences; no em dashes (use a period, comma, colon, or
parentheses); no filler like "seamless", "unlock", "You're all set!" or
"Oops!"; sentence case. The [avoid-ai-writing](https://github.com/conorbronsdon/avoid-ai-writing)
Claude Code plugin defines the patterns, and `/checkup` enforces them (below).
As of October 2026 about 30 on-screen strings still contain em dashes; the
first `/checkup` runs clean them up.

## Project layout
```
lib/
  main.dart                 App entry + MaterialApp/theme + in-app banner host
  theme.dart                Brand palette & Material 3 light/dark themes
  theme_setting.dart        Light / Dark / System choice, saved on device
  app_state.dart            Catalog, schedule, announcements, profile, roles (talks only to backend/)
  app_navigation.dart       Global selected-tab notifier + tab-index constants (banner/dashboard → tabs)
  models/models.dart        Discipline, Session, Announcement, GalleryPhoto, disciplineIcon()
  models/user_profile.dart  UserProfile + SummitRole + per-role fields + scope helpers
  backend/                  The backend seam — see "Swapping backends" under Backend
    backend.dart              Re-exports the contracts + BackendDescriptor
    auth_service.dart         Abstract AuthService, AuthUser, AuthFailure (neutral)
    repositories.dart         Abstract Catalog/Content/Schedule/Profile/Announcements/Allowlist/Gallery/Archie repos
    service_locator.dart      get_it wiring + configureBackend() (the single switch point)
    supabase/                 The Supabase implementation — ONLY place supabase_flutter is imported
    sample/                   In-memory implementation (standalone/demo mode)
  data/sample_data.dart     Static seed content used by the sample backend
  widgets/in_app_banner.dart  Instagram-style in-app banner (controller + host)
  widgets/summit_logo.dart    Brand mark rebuilt as a CustomPainter (no asset)
  widgets/roster_person_sheet.dart  Organizer-only profile sheet opened from a roster row
  widgets/volunteer_contact.dart  Volunteer card + Call/Text contact sheet (hub + session Volunteers tab)
  widgets/checkin_pass_card.dart  Profile "Check-in pass": the user's QR + front-desk status
  widgets/discipline_vibe.dart  Per-discipline personality: palette, motif, border flow, haptics, theme
  widgets/discipline_effects.dart  Ambient motifs, flowing screen border, portal route
  widgets/day_summary.dart  My Day summary line: sessions and time booked, sessions that still fit
  widgets/duotone_icon.dart  Phosphor duotone icons (bundled font) + DuotoneIcon widget
  screens/
    splash_screen.dart      Animated launch splash (sun arc + wordmark + haptics)
    root_nav.dart           Bottom navigation shell (Home · Schedule · Discover · News · Archie)
    dashboard_screen.dart   Home launchpad (greeting, photo slideshow, quote, up-next, action grid, links; About/Support EAF/Sponsors to come)
    auth/                   auth_gate, sign_in_screen, onboarding_screen (+ role gate), phone_required_screen
    schedule_screen.dart    Schedule tab (personal schedule; header reads "My Day")
    discover_screen.dart    Session search and discipline listings (+ admin "New discipline")
    discipline_screen.dart  A discipline's themed page: filters, time-grouped sessions (+ mentor/admin edit)
    session_detail_screen.dart   Tabbed session page: Session/Participants/Experts/Volunteers (permission-gated)
    session_editor_screen.dart   Create/edit a session (admin/ambassador; room dropdown, hero/gallery, content blocks)
    session_volunteers_screen.dart  SessionVolunteersView — Volunteers tab: co-workers (organizers/editors), assign/unassign (admin)
    session_roster_screen.dart   SessionRosterView + wrapper — roster + attendance (Participants tab / My Assignments)
    my_assignments_screen.dart   A volunteer's assigned sessions
    front_desk_screen.dart       Summit-wide check-in (front-desk capability): Scan button + searchable list
    front_desk_scanner_screen.dart  QR pass scanner — instant check-in, Undo
    volunteer_hub_screen.dart    Volunteer hub: every volunteer + tap for their number
    rooms_manager_screen.dart    Admin rooms catalog CRUD
    discipline_editor_screen.dart  Create a discipline (admin)
    announcement_compose_screen.dart  Post an announcement (admin / scoped volunteer), with photos/files
    announcement_detail_screen.dart   Full announcement page (message, photo viewer, files)
    archie_screen.dart      Archie AI assistant tab (welcome + starters, streamed chat, typing reveal)
    archie_insights_screen.dart  Admin: anonymous recent Archie questions + answers
    announcements_screen.dart, profile_screen.dart
    edit_profile_screen.dart     Edit your name + sign-up answers (from Profile)
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
  - The `announcements` table feeds the Announcements tab (broadcast rows behind a
    public-read RLS policy). Schema in
    [supabase/announcements_setup.sql](supabase/announcements_setup.sql).
  - **Auth + `profiles` table.** Email OTP via Supabase Auth; each account gets
    a `profiles` row (`id` = `auth.users.id`, plus `full_name`, `role`, a
    `details` jsonb bag for role-specific answers, `onboarded`). RLS scopes every
    row to `auth.uid()` so users only ever touch their own profile; a trigger
    auto-creates the row on sign-up. Schema + required dashboard steps in
    [supabase/profiles_setup.sql](supabase/profiles_setup.sql).
    - **Custom SMTP is required** for OTP and is **configured** through
      **Resend** (`smtp.resend.com`, switched 2026-11-14 from Google
      Workspace), the same service that sends bug report emails. Every
      Resend email, sign-in codes included, comes from **Emerald Summit '27
      App** <`app@ehsacademics.org`> (set in the SMTP settings and the
      `BUG_REPORT_FROM` secret, 2026-11-14); steps in
      [SUPABASE.md §3d](SUPABASE.md). The Workspace notes below are kept for
      history. Hard-won setup notes:
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
    routes sign-in → onboarding → app; if the profile can't be read it shows
    *Try again* instead of onboarding, which would overwrite the saved
    answers) against the abstract `AuthService`; the
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
    server-side enforcer of capacity + no-time-overlap (clients have no
    INSERT grant). It locks the session row while it counts seats, and takes
    `p_intent` (`add` / `remove`): the app sends what the button said, so a
    stale screen can't flip a registration the other way. It also records the
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
    [registrations_lockdown.sql](supabase/registrations_lockdown.sql),
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
    stored as the project name. `sessions.participant_deadline` (timestamptz,
    null = none) closes participant registration; `register_for_session`
    returns `participation_closed` for a participant after it. `remove_team_member` (owner only) takes someone
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
    [participant_deadline.sql](supabase/participant_deadline.sql),
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
    `fetch_session_volunteers` (name, subtype, role, phone; email for admins
    only) answers admins, the session's organizers and its discipline editors.
    Triggers post the organizer notices: `after insert` on `session_volunteers`
    (new co-organizer → the other organizers) and on `registrations` (a new
    expert → the organizers). These notices leave `announcements.session_id`
    null so unassigning doesn't sweep them up.
    [session_volunteers_setup.sql](supabase/session_volunteers_setup.sql),
    [session_organizer_notices.sql](supabase/session_organizer_notices.sql),
    [assignment_notifications.sql](supabase/assignment_notifications.sql),
    [unassign_notification.sql](supabase/unassign_notification.sql),
    [session_participation_setup.sql](supabase/session_participation_setup.sql).
    A person does one thing at a time, so managing takes precedence: an admin
    can assign someone who's busy at that time with
    `assign_manager_replacing_conflicts`, which takes their clashing sign-ups
    (this session's included) and managed sessions off their day, after
    `preview_manager_assignment` shows the admin what that removes (website
    only for now):
    [volunteer_conflict_override.sql](supabase/volunteer_conflict_override.sql)
  - `summit_checkins` + attendance RPCs — session rosters
    (`fetch_session_roster`, which also returns each registrant's
    participation type, answers, project/team, whether they own the team, and
    their `profiles.role` + `details` for the profile sheet — added by
    [roster_profile_details.sql](supabase/roster_profile_details.sql), run on
    the dev project; readable by assigned
    volunteers, admins, and the session's discipline editors /
    `mark_session_attendance`, gated by assignment) and
    the summit-wide front-desk directory (`fetch_attendee_directory` /
    `mark_summit_checkin`, gated by the front-desk capability).
    [attendance_setup.sql](supabase/attendance_setup.sql)
    QR check-in adds `scan_summit_checkin` (front-desk gated; atomic; never
    overwrites an earlier arrival), `my_summit_checkin` (own row only),
    `fetch_checkin_stats` (per-role counts), Realtime on `summit_checkins`
    (front-desk read policy), and
    limits the directory + scans to **onboarded** accounts (a blank profile row
    exists for anyone who merely requested a sign-in code).
    [qr_checkin_setup.sql](supabase/qr_checkin_setup.sql) (re-run on the
    live project Nov 22, 2026; it had an older version without the stats,
    the onboarded filter or Realtime)
    Anyone who passes the roster's gate can take someone off a session
    (website only for now): `remove_session_registration` deletes the
    registration, records it in `session_removals`, and sends a personal
    "Removed from a session" notice; a `before insert` trigger on
    `registrations` then refuses that person with `removed_from_session`
    until `allow_back_to_session` lifts it. `fetch_session_removals` lists
    them. [session_participant_removal.sql](supabase/session_participant_removal.sql)
    (run on the dev project Nov 13, 2026)
  - `announcements` gains `created_by` + `discipline_id`, **admin** write
    policies, and **Realtime**. [announcements_write_setup.sql](supabase/announcements_write_setup.sql)
    Later gains `target_user_id` for **personal** announcements (RLS: a targeted
    row is readable only by its recipient) and `session_id` (so an assignment
    notice can be cleaned up on unassign), used by assign/unassign notifications.
    [assignment_notifications.sql](supabase/assignment_notifications.sql),
    [unassign_notification.sql](supabase/unassign_notification.sql)
    Later still gains `attachments` (jsonb `[{url, path, name, type, size}]`)
    backed by the public **`announcement_attachments`** Storage bucket: uploads
    go in the uploader's `<user_id>/` folder and only admins + volunteers with
    `can_post_announcements` may upload; there's no list policy; owners and
    admins can delete (delete-for-everyone also removes the files).
    [announcement_attachments.sql](supabase/announcement_attachments.sql)
    *(run on the dev project)*
  - **Photo sets = public Storage buckets** (no table). Each photo set in the
    app is a public bucket, and **every image in it is shown**; curation is just
    uploading/deleting files. The app **lists** the bucket
    (`SupabaseGalleryRepository.fetchPhotos(bucket)`) and builds a public CDN URL
    per file with `getPublicUrl`. Public read/**list** + **admin** write on the
    bucket's objects (the list policy is intentional here). Different parts of
    the app point at different buckets — the **dashboard slideshow** reads
    `gallery_photos` (`AppState.dashboardGalleryBucket`; the website's Home
    slideshow lists the same bucket); a new section just adds
    a new bucket + a `fetchPhotos` call. This is the **first use of Supabase
    Storage**. [gallery_setup.sql](supabase/gallery_setup.sql)
  - **Session photos = the `session_photos` bucket**, one folder per session id
    (`<session_id>/…`). Unlike the admin-only galleries above, writes are
    allowed for **admins and the session's discipline editors** — the Storage
    RLS derives the owning session from the folder name and checks
    `can_manage_discipline`. The app uploads in-app (`image_picker` →
    `SessionMediaRepository.uploadPhoto`) and lists a session's folder for its
    gallery; the hero image is a `hero_image_url` column pointing at one of these
    files. [session_pages_setup.sql](supabase/session_pages_setup.sql) The
    website's session editor writes the same folders and column (it shrinks
    photos to 2000 px at 85% JPEG like the app and names them `p_<millis>.jpg`),
    so a photo added on either shows on both.
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
- **Roles & permissions.** Five roles: `participant`, `expert` (needs an
  admin's approval: `profiles.expert_status` is `pending` / `approved` /
  `declined`, owned by the same enforcement trigger, so only `review_expert()`
  can approve; see [expert_approval.sql](supabase/expert_approval.sql)),
  `parentSpectator` (open — the "Spectator" role, which auto-spectates
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
    announcements + front-desk are opt-in). It matches on the sign-in email
    from `auth.users` and copies it onto `profiles.email`, because users can
    write their own profile row
    ([role_allowlist_email_fix.sql](supabase/role_allowlist_email_fix.sql)).
    Self-elevation via a crafted API call is impossible.
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
    [SUPABASE.md](SUPABASE.md). Only the `pull-from-sheets` cron can call it:
    it checks an `x-sync-secret` header.
  - **Prune guard:** since removal demotes people, the sync refuses to remove
    anyone from a role when that role's sheet reads back empty, or shrinks to
    under half the table and by at least 5 rows. New and changed rows still
    sync, the other role is handled on its own, and the function returns
    `ok: false` (422). A real big drop goes through with
    `ALLOWLIST_ALLOW_BIG_DROP=true` set for one sync; an empty sheet never
    prunes.
  - **Admin notice:** when the guard refuses, or Google sign-in / a sheet read
    fails (nothing changes then; 500), every admin gets one rolling Personal
    notice, *"Problem with the Google Sheet"*, in News (plus the in-app banner
    if the app is open). It says which sheet, how many would have lost access
    (or that the app couldn't read the Google Sheets), and to tell Arjun to
    check the sheet. It's posted once, not every 5 minutes; its text is kept
    current (edits don't stream live, so open apps see them on the next feed
    load); it's deleted after the next clean sync. Built in the function
    itself, not SQL. *(When OS push is built, push it too; see Roadmap.)*
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

## Website sync: one backend for the app and the website

**Status: at par** (updated Nov 13, 2026; planned Oct 27). The website does
everything the app does except Archie and front-desk check-in. The website
([dogethecoderr/Emerald-Summit-Website](https://github.com/dogethecoderr/Emerald-Summit-Website),
React + TypeScript + Vite, deployed on Vercel at
`https://emerald-summit.vercel.app`) has moved off its own Supabase
project (`spsxfbvamwxsmtjkwxko`) and onto **this app's backend**, the dev
project `dgrskmykbkvphnaasfzl`. An account, a registration, an announcement or
a check-in made on one shows up on the other. The website's signed-in screens
are being matched to the app; **Where it stands** below lists what's done.

### Where it stands (Nov 11, 2026)
Done on the website, against this backend:
- **Phase 1, cut over:** shared URL and publishable key, the website's
  `supabase/` folder deleted, demo/bypass login removed (leftover `bypass_*`
  keys are cleared on load), the old-schema security test deleted.
- **Phase 2, auth:** emailed code, Google through Google's own button (working on the live
  site; see **Google sign-in on the web** below), password-gated test accounts with
  the app's auto-onboarding, the expert waiting screen and one-time declined
  note (`acknowledge_expert_decline`), and Change role with
  `preview_role_change` and the app's wording.
- **Phase 3, read-only:** Home with the `fetch_summit_status()` date line and
  countdown, Discover, News with pinned posts, shared read state
  (`announcement_reads.opened_at`) and "Remove this announcement from my feed"
  (`announcement_dismissals`), and the check-in QR pass.
- **Phase 4:** a session page (`/sessions/:id`) with each role's Add to my
  day choices, the participant form (solo or team, project name, team codes
  through `find_team`, the session's own questions), Edit my registration
  (`update_my_registration`), leave team, transfer ownership and remove a
  member with the owner hand-off, the participant deadline, approved experts
  (`session_experts`), and admin self-manage (`set_session_manage`).
- **Phase 5:** Sessions I'm managing, session rosters grouped by
  project with attendance (`mark_session_attendance`), the volunteer hub,
  volunteer hours (`volunteer_hour_logs` plus summit-day sessions).
  Front-desk check-in is **app-only** (it scans passes with the camera); the
  website's Profile lists it as "Mobile app only".
- **Phase 6:** the announcement composer with the app's audience rule
  (Everyone or a discipline; scoped volunteers with `can_post_announcements`
  post to their disciplines) and photos and files; the session
  editor with the app's fields and the `session_time_conflicts` warning and
  notice; assigning volunteers (`assign_volunteer_to_session`,
  `unassign_volunteer_from_session`); expert approvals; rooms; summit and
  per-session metrics.
- **Phase 7:** expert feedback and "Volunteer for EAF again?".
- **Sign-up:** each role's `onboardingFields` (school list, grade, phone,
  expertise and bio), the phone and grade prompts after sign-in, and Change
  role checking the allowlist before saving.
- **Look:** nav named and ordered like the app (Home · Schedule · Discover ·
  Announcements · Ask Archie), role labels Spectator and Expert, Phosphor duotone
  icons, discipline palettes copied exactly.

Not on the website yet: Archie and Archie insights (phase 8; the website's
Archie tab says "Coming soon", since each chat is a paid Claude call) and
front-desk check-in (app-only on purpose). Push notifications are app-only;
the website shows the app's in-app banner as a toast instead.

**Nothing website-only (checked Nov 11, 2026).** The website had grown a few
things the app doesn't do; they were removed so the two behave the same:
editing or re-pinning a post after it's posted, link attachments, News search
and categories, a per-post "Mark as read" button, the web QR scanner and
front-desk roster, and an About row. Two website-only things stay: test-account
sign-in also stops asking for 15 minutes after five wrong passwords in that
browser (on top of the `dev-login` function's own lockout, see SUPABASE.md
§3b), and the header search also jumps to pages. Both now have the bell's
Notifications list.

**Latest (Nov 12, 2026), both sides:** the bell's Notifications list (see
**Notifications**); personal notices out of News; "Remove this announcement
from my feed" behind each post's ⋯ menu with a can't-be-undone warning; the
`dev-login` lockout. On the website: the phone bottom bar is the app's five
tabs (Home, Schedule, Discover, News, Archie) with Profile as an avatar in the
top bar. (The Profile switch that was here, **Mobile app notifications**,
was removed on Nov 13, 2026 with the app's own switch; see **No notification
setting** above.)

**Latest (Nov 13, 2026), website only:** session photos now match the app.
People who can edit a session (admins and the discipline's session editors)
set the hero photo and add or delete gallery photos in the website's session
editor, against the same `session_photos` folders and `hero_image_url`. The
session page shows the hero (or the first photo when none is set) and the
Gallery strip, and signed-in people get **Sessions similar to this** with each
card's photo, using the app's `suggestedSessions` rule. No backend change was
needed. Details are in the website README's **Sessions** section.

**Also Nov 13, 2026, website only (an app-to-website audit):** Discover now
reads the `disciplines` table in its `sort_order`, like the app, and admins
get **New discipline** (the app's discipline editor: id, name, tagline, icon).
Home has the app's photo slideshow (`gallery_photos`), quote card and Links
card. My Day has the app's day summary line ("N sessions · X booked", "N open
sessions still fit around these. Find one"). A new post that reaches someone
while the site is open shows the app's in-app banner rule as a toast. Phone
numbers in the Volunteer hub and a session's Volunteers tab get the app's
copy, Call and Text, and session rosters show each person's mobile number and
all their sign-up answers, as the app's roster person sheet does. Switching
Discover to the table made the website show the table's subtitles, which are
still the old ones: run [universe_subtitles.sql](supabase/universe_subtitles.sql)
(see the to-do below). The website also orders the disciplines by the table
now (TechVerse, VentureVerse, BioSphere, NovaSphere, CivicVerse, ImagineX);
the public landing page keeps its own order.

**Latest (Nov 13, 2026), website + backend:** managing a session takes
precedence over anything the person was doing at that time. When an admin
assigns a volunteer (or themself) who's busy then, the website lists what
comes off their day (their sign-up for this session, overlapping sign-ups,
overlapping managed sessions, and what happens to their team) and, on
**Assign and replace** / **Manage instead**, removes those and assigns them in
one go. Backend: `preview_manager_assignment` and
`assign_manager_replacing_conflicts` in
[volunteer_conflict_override.sql](supabase/volunteer_conflict_override.sql)
(run on the dev project Nov 13, 2026). The app still refuses every clash; see
the to-do below.
Admins also see which volunteers are already signed up for a session (in
the Volunteers tab and tagged in the Assign picker) and can **Assign to be a
manager instead** in one click, which takes them off the roster; same RPCs, no new SQL.

**Latest (Nov 13, 2026), website only:** a bell note from today still says
"5m ago" / "3h ago", but once it's from an earlier calendar day it shows the
date ("Thu, Nov 12", or "Nov 12, 2025" for another year) instead of "2d ago". The **News** tab is now called **Announcements** on the website.
Both are on the to-do list below.

### Website changes to bring into the app (to-do)
Still open: uploading Archie's edited knowledge file and
redeploying `archie-chat` (see **Archie and the FAQ**). Everything else
below landed in the app on Nov 14, 2026 and is ticked, with a note where the
app does it differently from the website. Checked against the website on
Nov 14, 2026: everything else the website does, the app does too, apart from
the website-only list at the end. Tick an item off here when it lands.

- [x] **8th graders in sessions.** Participating is for high schoolers; an
  8th grader can participate only in sessions whose editors ticked **Let 8th
  graders participate**, and anyone can spectate any session.
  - Backend: [eighth_grade_participation.sql](supabase/eighth_grade_participation.sql)
    (run on the dev project Nov 13, 2026). It adds `sessions.allow_eighth_graders` (default
    false), rebuilds `sessions_with_counts` with it, adds `grade_number(text)`,
    and makes `register_for_session` refuse a new participant whose
    `details.grade` is 8 on a session without the box
    (`eighth_grade_not_allowed`) or 7 and below anywhere
    (`middle_school_not_allowed`). A blank grade isn't blocked (participants
    must give one at sign-up). The rule already holds for the app, but the
    app only shows its generic "couldn't update" error.
  - Session model: read `allow_eighth_graders`.
  - Session editor: a **Let 8th graders participate** checkbox that writes
    `allow_eighth_graders`. Website helper text: "Only high schoolers can
    participate. Anyone can spectate, 8th graders included." / "8th graders
    can register to participate, the same as high schoolers." and, when it's
    unticked on a session that had it, "8th graders who already registered
    stay registered."
  - Add to my day: grey out **Participate** for a grade-8 account on a
    session without the box ("This session isn't open to 8th graders. You can
    spectate it.") and for 7th grade and below everywhere ("Participating is
    for high schoolers. You can spectate."). Where the box is ticked, an 8th
    grader sees the normal sheet. Map the two errors to: "This session isn't
    open to 8th graders for participating. You can still add it as a
    spectator." and "Participating is for high schoolers, and 8th graders in
    some sessions. You can still add this session as a spectator."
  - `gradeLabel` in [metrics.dart](lib/models/metrics.dart): read "eighth" as
    8, like the website and `grade_number`.
  - Sign-up: under the participant's grade, "8th graders can participate in
    some sessions and spectate any of them. Middle schoolers must come with
    an adult." Parent / Spectator sign-up gets a note: "Curious minds of all
    ages are welcome. Middle schoolers and younger need a parent with them."
  - Archie: [knowledge.md](supabase/archie/knowledge.md) still says only high
    schoolers can participate ("Who can attend", the roles table, the FAQ
    answer). Update those lines and re-upload the knowledge file.
  Done in the app: `Session.allowEighthGraders`, the editor's checkbox and
  helper text, Participate greyed out in Add to my day
  (`participationGradeBlock` in metrics.dart), the two error messages,
  `gradeLabel` reads "eighth", and the sign-up notes. Archie's knowledge.md
  is updated but not uploaded yet.
**Latest (Nov 13, 2026), website + backend:** organizers can remove someone
from a session, e.g. an account that looks fake. On the website the
Participants and Experts tabs have **Remove** on every row and a **Removed**
list with **Allow back**, through the new RPCs in
[session_participant_removal.sql](supabase/session_participant_removal.sql)
(run on the dev project Nov 13, 2026, so it's live on the website). The app
has it too since Nov 14, 2026; see below.

- [x] **Remove someone from a session.** Anyone who can see a session's
  roster (admins, the volunteers assigned to it, and session editors for its
  discipline) can take a participant, spectator or expert off it.
  - Backend: [session_participant_removal.sql](supabase/session_participant_removal.sql)
    (run on the dev project Nov 13, 2026). Adds `session_removals (session_id, user_id,
    participation_type, removed_by, removed_at)` (no client grants) and
    `can_see_session_roster(p_session_id)`, which is `fetch_session_roster`'s
    gate. `remove_session_registration(p_session_id, p_user_id)` deletes the
    registration, upserts the `session_removals` row, sends the person a
    personal "Removed from a session" announcement, and returns
    `{outcome: 'removed' | 'not_registered' | 'cannot_remove_self'}`. The
    existing registration triggers handle teams: a team left with nobody on
    it is deleted,
    a removed owner's team goes to the earliest-joined member ("You're now
    the owner"), and the other members get "X was removed from your team".
    A `before insert` trigger on `registrations` raises
    `removed_from_session` for anyone in `session_removals`.
    `allow_back_to_session(p_session_id, p_user_id)` deletes that row (it
    doesn't re-register them). `fetch_session_removals(p_session_id)`
    returns `user_id, full_name, email, participation_type, removed_by_name,
    removed_at`, newest first.
  - Roster screen ([session_roster_screen.dart](lib/screens/session_roster_screen.dart),
    or the person sheet in [roster_person_sheet.dart](lib/widgets/roster_person_sheet.dart)):
    a **Remove** action for each person, with a
    confirm: "They'll be taken off "<session>" and get a notice saying an
    organizer removed them. They can't sign up for it again unless someone
    allows them back." plus, for a team member, "Their teammates will be
    told they were removed.", for an owner, "They own a team, so it passes
    to the teammate who joined first.", or, for the last one on a team,
    "They're the only one on their team, so the team is deleted too." Then
    refresh the roster.
  - A **Removed** section at the bottom: name, type, "Removed by X", date,
    and an **Allow back** button. Hide both while `fetch_session_removals`
    errors (the SQL not run yet).
  - Add to my day: map `removed_from_session` to "An organizer removed you
    from this session, so you can't sign up for it again. If you think this
    was a mistake, contact the summit team." (today the app shows its generic
    error).
  Done in the app: **Remove from this session** is a button in the person
  sheet a roster row opens (rows already carry the attendance switch), with
  the confirm and team lines above; the **Removed** list with **Allow back**
  sits at the bottom of the Participants and Experts tabs, filtered to that
  tab's types; both hide while `fetch_session_removals` fails.
- [x] **Dates on older bell notes.** On the website, a note from today keeps
  the app's relative stamp, and anything older shows its date. The stamp sits
  right-aligned on the title row, in the phone's time zone:
  - today, under a minute: **just now**; under an hour: **5m ago**; earlier
    today: **3h ago** (as the app does now);
  - an earlier calendar day this year: **Thu, Nov 12** (replaces "1d ago",
    "2d ago", …);
  - another year: **Nov 12, 2025**.

  "Today" is the calendar day, not the last 24 hours: at noon, a note from
  11 PM yesterday is **Wed, Nov 11**, not "13h ago", and one from 12:05 AM
  today is **11h ago**. The website shows the full date and time on hover
  ("Thursday, November 12, 2026 at 9:05 AM"); the app can show it on
  long-press or leave it out. The rule and its tests are `notificationStamp`
  / `notificationFullTime` in the website's `src/models/notifications.ts` and
  `src/pages/__tests__/NotificationsPage.test.tsx`.
  **Why the app needs it:** "2d ago" doesn't say which day a note came from,
  so someone checking when a schedule change or team notice arrived has to
  count back, and the same note would read "Wed, Nov 11" on the website and
  "1d ago" on the phone.
  In the app:
  - In `AppNotification.timeAgo` ([models.dart](lib/models/models.dart)), keep
    the minutes/hours branches only while `createdAt.toLocal()` is on today's
    date; otherwise return the date. The app has no `intl` dependency; either
    add it (`DateFormat('EEE, MMM d')` this year, `DateFormat('MMM d, y')`
    otherwise) or use `MaterialLocalizations.formatShortMonthDay` as
    [archie_insights_screen.dart](lib/screens/archie_insights_screen.dart)
    does (that needs a `BuildContext`, so it would move to
    [notifications_screen.dart](lib/screens/notifications_screen.dart)).
  - In notifications_screen.dart (line ~141 joins `item.body` and
    `item.timeAgo` in the subtitle), move the stamp to the right of the
    title, like the website, and drop it from the subtitle.
  - Add tests for each case, including 11 PM yesterday and 12:05 AM today.
  - Only the bell changes; the News feed's own `timeAgo` stays.
  Done in the app: `notificationStamp` / `notificationFullTime` in
  models.dart (no `intl`), the stamp sits right of the title and the full
  time shows on long-press. Tests in test/notification_stamp_test.dart.
- [x] **Rename the News tab to Announcements.** The website calls it
  Announcements everywhere (sidebar, bottom bar, page title, Home shortcut,
  composer hints, remove-from-feed warning). In the app: the tab `label:
  'News'` in [root_nav.dart](lib/screens/root_nav.dart) (it fits; the website's
  bottom bar shows "Announcements" in full at 320 px wide), the warning "It
  stays in News for everyone else." in
  [announcement_detail_screen.dart](lib/screens/announcement_detail_screen.dart),
  and the comments that say "News tab". The feed screen's title already reads
  Announcements. No backend change.
  Done in the app, along with Home's "Latest announcements" and Archie's
  wording.
  **Changed Nov 14, 2026:** the app's bottom bar label is **News** again
  (user's call). In the floating capsule bar every tab gets a fifth of the
  width, and "Announcements" only fits at about 9pt, far smaller than the
  other labels. Everything else (page title, Home shortcut, warnings) still
  says Announcements. The website's bottom bar still says "Announcements".
- [x] **Managing replaces a clash.** A person does one thing at a time, and
  managing wins. On the website an admin can assign someone who's busy at
  that time, and what they were doing comes off their day.
  - Backend: [volunteer_conflict_override.sql](supabase/volunteer_conflict_override.sql)
    (run on the dev project Nov 13, 2026), admin only, both RPCs take
    `(p_session_id, p_user_id)`:
    - `preview_manager_assignment` → `{already_managing, replaces: [...]}`.
      Each item has `session_id`, `title`, `start_time`, `end_time`, `kind`
      (`registered_this` = signed up for this same session, `registered` =
      signed up for an overlapping one, `managing` = manages an overlapping
      one), `participation_type`, `team_name`, `team_owner`, `teammates`
      (others on the team).
    - `assign_manager_replacing_conflicts` deletes those registrations (the
      team triggers pass ownership to the earliest-joined teammate, delete an
      emptied team and tell teammates), removes them from the overlapping
      managed sessions (their old "You're managing" notice for each stays in
      the feed and bell as a dated record), adds them to `session_volunteers`, and sends one "You're managing a
      session" notice that names what was taken off their day. No notice
      when an admin passes their own id. Returns `{outcome: 'assigned',
      replaced: [...]}`. Removed sign-ups aren't blocked from signing up
      again.
  - Volunteers tab: when `assign_volunteer_to_session` returns `conflict`,
    call the preview and show **Replace what they're doing?**: "Sam Lee can
    only do one thing at a time. Managing "X" takes these off their day:",
    one line per item, e.g. "Their sign-up to participate in this session.
    They'll manage it instead.", ""Bio Lab", where they're signed up to
    spectate.", ""Drone Lab", which they manage. They'll stop managing it.",
    plus the team line ("They own "Rover"; it passes to the teammate who
    joined first." / "Their teammates on "Rover" are told." / "Their team
    "Rover" has no one else, so it's deleted."), then "They'll get a notice
    listing these changes." with **Cancel** and **Assign and replace**.
    Wording is `describeReplacement` in the website's `src/services/organizer.ts`.
  - Add to my day → Manage: on a `set_session_manage` conflict, the same
    dialog in the second person ("Replace what you're doing?") with
    **Manage instead**, calling the RPC with the admin's own id.
  Done in the app: `previewManagerAssignment` /
  `assignManagerReplacingConflicts` on `AssignmentRepository`, the dialogs
  in lib/widgets/manager_replace_dialogs.dart (`describeReplacement` matches
  the website), and **Manage instead** from the session page.
- [x] **See and convert signed-up volunteers.** On the website, an admin
  sees which volunteers are already signed up for a session and can assign one
  to manage it in a click. No new backend: it uses the two RPCs from
  **Managing replaces a clash** above (do that first) plus
  `fetch_session_roster`.
  - Volunteers tab, admins only: under the managers, a **Volunteers signed up
    for this session** list, from `fetch_session_roster` filtered to
    `role = 'volunteer'` and minus anyone already managing. Each row: name,
    "Signed up as participant" / "spectator" / "expert", email, and an **Assign
    to be a manager instead** button. Hidden when empty; don't fetch the roster for
    non-admins.
  - Assign picker: those volunteers sort first with the same "Signed up as …"
    tag, and tapping one opens the dialog below instead of calling
    `assign_volunteer_to_session`.
  - Dialog: call `preview_manager_assignment`, then show **Assign Sam Lee to be a
    manager instead?** with "This will make them a manager of this session, and they
    will no longer be a participant of this session." ("a spectator" / "an
    expert" for those types), the team line for the `registered_this` item
    if they're on a team, and "It also takes these off their day, since they
    overlap:" with any other items, then "They'll get a notice about the
    change." **Cancel** / **Assign to be a manager instead**, which calls
    `assign_manager_replacing_conflicts`. Toast: "Sam Lee now manages this
    session and is off its roster. They've been told." Website code:
    `src/components/session/MakeManagerDialog.tsx`.
  - Volunteers tab wording (the app's session_volunteers_screen.dart): "The
    people managing this session.", **Assign a volunteer to manage** (button
    and picker title), empty state "No volunteers assigned yet. Assign
    volunteers so they can manage this session." (non-admins: "No one has
    been assigned to manage this session yet."), and for admins a note:
    "Managers can see everyone signed up for this session (participants,
    spectators and experts) with their contact details, mark attendance, and
    remove someone from the session. They can't edit the session's details,
    like its description, time, room or photos."
  Done in the app, with the Volunteers tab wording below.
- [x] **Registration closed message.** While `website_registration_open` is
  off, the website says "Registration will open on November 21st" for the
  `registration_closed` error; the app shows its generic error (see
  **Registration lock and hidden session times**).
  Done in the app (`registrationRefusalMessage` in repositories.dart).
- [x] **Universe subtitles.** The website renamed four: ImagineX "Arts,
  Literature, Music, Drama & Improv", NovaSphere "Core Sciences, Climate
  Change & Sustainability", VentureVerse "Entrepreneurship & Marketing",
  CivicVerse "Mock Trial, Government Policy & Rights". The app and now the
  website show each discipline's `tagline` from the database. Neither client
  can edit a discipline (the app's editor only creates one), so run
  [universe_subtitles.sql](supabase/universe_subtitles.sql) in the SQL Editor
  (run Nov 14, 2026). No code change.
- [ ] **Archie and the FAQ.** The website's FAQ added why the Summit is in
  January, whether a project needs to be perfect, and why there are no awards
  (every participant gets a certificate of participation). Add them to
  Archie's knowledge if Archie should answer them.
  knowledge.md now has the three FAQ answers, 8th graders, the sponsor tiers
  and ehsacademics.org links, and the `archie-chat` persona and `web_fetch`
  domains point at ehsacademics.org. **Not live yet:** upload the knowledge
  file and redeploy `archie-chat`.
- [x] **Home: smaller slideshow, no Tracks or Explore rows, three new sections.** The
  website's dashboard slideshow is now 2:1 (was 16:9) and takes less of the
  row beside the quote card. The Tracks strip under Your day, with its
  Browse sessions button, is gone, and so is the **Explore the verses** row
  of verse cards (the app's **Explore disciplines** rail on Home: remove it;
  Discover stays the way into the disciplines). New sections, all static
  text and links, no backend (`src/components/home/AboutSections.tsx`).
  Their current text, order and links are in the Home description near the
  top of this README and in **Home sections and wording, Nov 14** below.
  When sponsors sign on, their logos could come from a `sponsors` bucket
  like `gallery_photos`.
  Done in the app; see **Home** near the top of this README.
- [x] **New "How are you joining the Summit?" sign-in screen** (website,
  Nov 14, 2026). One screen replaces the role list: the Summit logo in a
  large white circle, "Organized by EHS Academic Foundation" with the EAF
  seal (website `public/brand/eaf-logo.png`), and role cards grouped under
  **Attending the Summit** (Participant "Build your schedule and follow your
  Summit day.", Spectator "Attend tracks and stay in the loop. Curious minds
  of all ages are welcome.", Expert "Evaluate tracks and join panel
  discussions to share insights with attendees.") and **Helping run the
  Summit** (Volunteer "Parent and student volunteers."). Each card has
  **Sign in** and **Sign up** (see the next item). Admin has no card: **Organizer sign in** at the
  bottom is for admins and test accounts, and **Not sure? Contact the EAF
  team** emails contact@ehsacademics.org. No backend change.
  Done in the app: lib/screens/auth/welcome_screen.dart, which opens the
  sign-in screen in place for the picked role.
- [x] **Sign in and Sign up are different paths** (website, Nov 14, 2026).
  Sign up creates the account and runs the sign-up steps (profile
  questions, then the code of conduct) before the app opens. Sign in checks
  who you are and goes straight in: an email code goes only to an email
  that already has an account (`shouldCreateUser: false`). A new email
  gets "Let's create you an account! There's no account for … yet. Press
  Continue to enter some information and create your … account." and
  **Continue** switches to sign-up and emails the code. A new
  Google account from Sign in is treated as a sign-up. An existing account
  that taps Sign up just signs in and skips the steps it has done. The
  screens link to each other ("New to the Summit? Sign up" / "Already have
  an account? Sign in").
  Done in the app: `sendEmailOtp(createAccount:)` throws `NoAccountFailure`
  for a new email on Sign in; the picked role is
  `appState.pendingSignUpRole`, which onboarding starts on ("Signing up as
  …" with a Change link). Google sign-in from either mode makes the account
  if it's new and onboarding runs, as on the website.
- [x] **Code of Conduct and Guest Expert Policy** (app and website, Nov
  14-15, 2026; live on dev since Nov 15, 2026). Every account agrees once by
  ticking a box; no signatures. **Experts agree to the Guest Expert
  Policy**; participants, spectators, volunteers and admins agree to the
  **Code of Conduct** (`agreementFor(role)`). Someone who changes role to or
  from Expert is asked to agree to the other one.
  - **Word for word, nothing summarized** (the user's rule, Nov 15, 2026):
    the Code of Conduct is EAF's "Emerald Summit 2026 Code of Conduct" (EAF
    Field Trip Waiver Form Version 11.02.2025.1) and the expert one is
    "Guest Expert Policy: Emerald Summit '27" (Nov 14, 2026), both as
    written, titles and footer included. Since Nov 20, 2026 the Code of
    Conduct's title reads "Emerald Summit 2027 Code of Conduct" on both
    the app and the website (title only; the version stayed
    `conduct-2026-11-15`, so nobody agrees again). The only changes: the signature
    lines are replaced by the checkbox, and the two media options say "of
    me" instead of "of my child", because the account holder answers, not
    a parent. No parent or guardian consent (the user's call). They live in
    [code_of_conduct.dart](lib/models/code_of_conduct.dart) and the
    website's `src/models/codeOfConduct.ts`, each with a version
    (`conduct-2026-11-15`, `guest-expert-2026-11-14`) stored in
    `profiles.code_of_conduct_version`. Change a text in both and bump its
    version to have everyone agree again.
  - **Photo permission is a radio button** on the Code of Conduct: "I
    GRANT permission…" or "I DO NOT GRANT permission…", required, chosen by
    the account holder and saved as `profiles.photo_consent`. Experts have
    no such question; their policy covers recording and photos.
  - It shows in a scrollable window with **Expand** (full screen in the app,
    a large popup on the website), then the photo question (Code of Conduct
    only) and the checkbox.
  - New accounts: the app's auth gate shows it right after the sign-up
    questions; the website puts it under the questions on the profile page.
    Existing accounts get it ("One last step") the next time they open
    either, before anything else.
  - Backend: [code_of_conduct.sql](supabase/code_of_conduct.sql) adds
    `profiles.code_of_conduct_version`, `code_of_conduct_agreed_at` and
    `photo_consent`, and `agree_to_code_of_conduct(p_version,
    p_photo_consent)`. Run on the dev project Nov 15, 2026 (through `supabase
    db query --linked`). Three test accounts had agreed to an earlier,
    summarized draft; their old versions don't match, so they are asked
    again. Run it on prod too when prod exists.
  - **Admins see who did not allow photos** (app and website, Nov 15,
    2026): Profile → **Photo permission** in the app
    ([photo_permission_screen.dart](lib/screens/photo_permission_screen.dart)),
    `/admin/photo-permission` on the website (Profile → Photo permission).
    Three lists, searchable by name, email or school: **Did not allow
    photos** first (with Copy names, for photographers), **Not answered
    yet** (has not agreed to the current Code of Conduct), and **Allowed
    photos** collapsed. Experts are not listed; they are not asked. Reads
    `fetch_photo_permissions()` in
    [photo_permission_list.sql](supabase/photo_permission_list.sql), admin
    only (run on the dev project Nov 15, 2026).
  - Not built yet: the Guest Expert Policy says expert profiles show title
    and organization, a LinkedIn link and a headshot on a Summit experts
    page. The app's expert sign-up asks for area of expertise, a bio and a
    phone number only, and there is no experts page.
- [x] **Grade is a dropdown for participants** (app and website, Nov 14,
  2026). 8th grade to 12th grade, saved as "8" to "12", on sign-up and Edit
  profile ([grade_picker.dart](lib/widgets/grade_picker.dart), the website's
  `GradePicker` in ProfileFieldInput.tsx). An older typed answer ("11th",
  "Junior") opens on its grade; anything else has to be picked again.
  Volunteer and admin grades stay typed.
- [x] **8th graders see which tracks they can participate in** (app and
  website, Nov 14, 2026). For a participant whose grade is 8, tracks with
  `allow_eighth_graders` carry an **Open to 8th grade** badge on the
  discipline page (with a note under **Tracks**), in the app's Discover
  search, and on the session page; the session page of any other track says
  "Not open to 8th graders for participating. You can spectate it."
  (`AppState.isEighthGradeParticipant`, the website's
  `isEighthGradeParticipant` in registration.ts).
- [x] **Role names: Spectator and Expert.** The website renamed "Parent /
  Spectator" to **Spectator** and "Expert / Speaker" to **Expert**
  everywhere, and every role's blurb is now the sign-in screen's (see the
  first item). Update `SummitRole` labels and blurbs in `user_profile.dart`.
  Stored role values don't change.
  Done in the app.
- [x] **Phone numbers are digits only.** On the website the mobile number
  field drops anything that isn't a digit as you type or paste ("(925)
  555-0100" becomes 9255550100), keeps at most 10 digits (was 15 until
  Nov 14, 2026, on both), and opens the
  number pad. Do the same in the app's phone fields (sign-up and the
  add-your-number gate).
  Done in the app (`ProfileField.phoneFormatters`).
- [x] **Change role in a popup.** Signed in, Change role (Profile, the
  pending expert's "Sign up as something else") opens a sheet listing the
  four roles with the current one marked; picking one shows the existing
  preview-and-confirm step in the sheet, then the new role's profile
  questions. It no longer sends people to the sign-in role list.
  Done in the app: lib/widgets/change_role_sheet.dart; Confirm opens the new
  role's questions (`OnboardingScreen(startOnDetails: true)`), which save
  the change.
- [x] **"Room TBD" in session lists** (website, Nov 14, 2026). While rooms
  are locked (`SESSION_ROOMS_ENABLED` is false), the website's session lists
  (discipline pages, My Schedule, Home, search results) show "Room TBD"
  instead of the stored room. The session page still hides the room. The
  app's lists still show the stored room.
  Done in the app (`Session.roomLabel`).
- [x] **Tracks are sessions** (website, Nov 14, 2026). A discipline page
  lists its sessions under a **Tracks** heading (was "Sessions") with no row
  of track chips, and there are no separate track pages (Format, What you
  can do, More in this discipline). Track chips on Discover use each
  session's exact title. Schedule cards have no track tag. A session opens
  inside its discipline's world without reloading it: the list swaps for
  the session, which grows out of the tap point while the background, motif
  and flowing border carry on, and Back returns to the list. Opened from
  anywhere else, the session page is its own full screen in its
  discipline's world (no tab bar or app bar), growing in like the
  discipline portal.
  Done in the app: the discipline page lists sessions under **TRACKS** with
  no track chips or track text (its All / Open seats / Morning / Afternoon
  filters stay). The session page is drawn in its discipline's world (theme,
  `AmbientMotif`, `FlowingBorder`) and every place that opens a session uses
  `openSession`, which grows it out of the tapped card with the discipline
  portal route. From the discipline page that reads as the list swapping for
  the session; it is a new route, not the same page.
- [x] **No grey square behind +, −, ✓ and ×** (website, Nov 14, 2026).
  Phosphor's duotone draws a faint square or rectangle behind bare marks
  (plus, minus, check, double check, x, three dots, left-right arrows,
  list/menu, download, scan, terminal, math operations). The website draws
  those at the regular weight instead; check `duotone_icon.dart` for the
  same box.
  Checked: the app's duotone set (duotone_icon.dart) has no bare marks; +,
  ✓, × and the rest are Material icons. Nothing to change.
- [x] **Report a bug or send feedback** (website, Nov 14, 2026). Two
  categories of ticket, from two rows on Profile: **Report a bug** and
  **Send feedback**. Each opens the same form, titled for its category (a
  switch at the top moves it to the other one): name (filled in,
  required), description (required), up to 5 screenshots (10 MB each,
  images only) and **Email me a copy** (on by default). A "What else is
  sent with your report" list says what's attached, that phone number,
  student ID, school, grade and emergency contact aren't, and "Only Summit
  app developers can read reports." The app's form should say the same. After sending it shows the ticket, e.g. "Bug #12"
  or "Feedback #13". Admins get **Bug reports and feedback**
  (`/admin/reports` on the website): Bugs and Feedback tabs with open
  counts, open / resolved, screenshots, the attached data, and **Copy as
  Markdown** for pasting a ticket to whoever fixes it.
  - Backend: [bug_reports_setup.sql](supabase/bug_reports_setup.sql) (run
    Nov 14, 2026) and the
    [bug-report-email](supabase/functions/bug-report-email/index.ts) Edge
    Function (deployed Nov 14, 2026; sends through Resend as
    Emerald Summit '27 App <`app@ehsacademics.org`>, every ticket to
    `support@ehsacademics.org`); SUPABASE.md step 63 and §3d. Upload screenshots to
    the private `bug_report_screenshots` bucket at
    `<user_id>/<report_id>/<n>.<ext>` (the app picks `report_id`, a UUID),
    then call `submit_bug_report(p_id, p_kind, p_name, p_description,
    p_screenshots, p_client, p_email_copy)`, then invoke
    `bug-report-email` with `{ report_id }`. The server adds the account
    snapshot itself, so the app only sends `p_client`.
  - `p_client` from the app: `app: "ios"` or `"android"`, `page` (the
    current screen), `route_history` (last 15 screens, `{path, at}`),
    `errors` (last 25 `FlutterError`/zone errors, `{level, message, at}`),
    `failed_requests` (last 15 failed Supabase calls, `{method, url, status,
    message, at}`), `build` (`{version, build_number, commit}`), and
    `device` (model, OS version, locale, timezone, screen size, theme). The
    website's version is `collectClientContext` in `src/lib/diagnostics.ts`.
  - Error codes to word: `name_required`, `description_required`,
    `too_long`, `too_many_reports` (10 an hour), `not_signed_in`. A failed
    email doesn't fail the report.
  Done in the app: lib/screens/report_screen.dart (Profile → Report a bug /
  Send feedback), lib/screens/bug_reports_screen.dart (admins),
  `BugReportsRepository`, and lib/backend/diagnostics.dart, which records
  screens, Flutter errors and failed Supabase requests (through
  `RecordingHttpClient`) and reads the build (`package_info_plus`, plus
  `--dart-define=GIT_COMMIT=…` when given) and device (`device_info_plus`).
- [x] **"are not", never "aren't"** (website and app, Nov 15, 2026). App
  text writes "are not" in full ("Your email is not on the list of people
  allowed to be a volunteer.", "Teams are not allowed."), the same as the website. Other
  contractions ("You're", "can't", "Let's") stay. The Home greetings ("What's
  up", "What's poppin'", "Let's build something") are now on the website too.
  - Still open: redeploy `archie-chat` (its prompt now says to write "are
    not", never "aren't") with
    `supabase functions deploy archie-chat --no-verify-jwt --use-api`, and
    upload the edited `supabase/archie/knowledge.md`.
- [x] **Home sections and wording, Nov 14** (website, Nov 14, 2026).
  - The Archie tab is labeled **Ask Archie** (sidebar and bottom bar; the
    website's `NAV_ITEMS` in `src/components/AppShell.tsx`).
  - "Summit" is always capitalized in app text ("Summit day", "the Summit
    team", "questions about the Summit", role blurbs, the phone-number
    helper, volunteer hours, the follow-up screens).
  - Never "Explore the verses"; it's always **Explore the disciplines**.
  - Home's **Quick access** row (Resources, Announcements, Profile, Volunteer
    hub) is gone on the website. Decide whether the app's action grid follows.
  - Support EAF, Sponsors and About the app use the new text and layout
    described under Home above (tiered sponsors, credits in About, About at
    the bottom).
  - **Donate opens Zeffy outside the app**: the Zeffy page above, in the
    browser, not embedded.
  - **No Resources tab**: the website took Resources out of its sidebar
    (the page still exists, unlinked). Done in the app: the Resources screen
    and the Home **Campus map** / **Resources** tiles are gone.
  - Never "universes" either: the website's landing page now says
    Disciplines, "Which discipline is yours?" and "What are the six
    disciplines?".
  - **EAF's real site is ehsacademics.org**; the Summit page is
    https://emeraldsummit.ehsacademics.org. The old Google Sites page
    (sites.google.com/view/ehs-academic-foundation) is out of date. The app
    still links it: the Summit website link in
    [dashboard_screen.dart](lib/screens/dashboard_screen.dart), the sample
    Archie source in
    [sample_archie_repository.dart](lib/backend/sample/sample_archie_repository.dart),
    and three places in [knowledge.md](supabase/archie/knowledge.md) (redeploy
    Archie after editing it). The website switched on Nov 14, 2026.
  Done in the app. The Jump to grid went with the website's Quick access,
  and the Resources screen is gone.
- [x] **Code of Conduct: back to the checkbox** (website, Nov 20, 2026; no
  app work). On Nov 17, 2026 Akhil replaced the website's agreement
  checkbox with a draw-it-yourself signature pad (website commit
  `1eae9a4`), and this item asked the app to copy it. It has been taken
  out again. The drawn signature was never saved
  (`agree_to_code_of_conduct` only records the version and the photo
  choice), and it contradicted the agreements: the Guest Expert Policy
  ends with "Continue once you have read it; no signature is needed", and
  both documents had their signature lines replaced by the checkbox. The
  website deleted `SignaturePad.tsx` and went back to the checkbox ("I
  have read the … and agree to it."), the same as the app's
  `CheckboxListTile` in
  [code_of_conduct_screen.dart](lib/screens/auth/code_of_conduct_screen.dart),
  so the two match again. No backend change, and nobody agrees again. The
  website kept the rest of that change (headed sections **Your Info**,
  **Media Rights and Consent**, then the agreement, in a wider layout);
  the app's screen does not need those to match.
- [ ] **Sign in only reaches finished accounts** (website, Nov 17, 2026).
  After any Sign in (Google or email code), the website checks the account
  has finished sign-up (`signedInAccountNeedsSignUp`: the profile still
  needs setup). If it hasn't, it signs out again and shows **Couldn't sign
  you in**: "There's no Summit account for <email> yet. Sign up to create
  your <role> account." with **Go to sign up**, instead of starting the
  sign-up steps. Sign up and Organizer sign in skip the check. The app
  still runs onboarding when a new Google account comes in through Sign in
  (see **Sign in and Sign up are different paths** above). Also, a new email
  on Sign in is now headed **No account found** ("There's no account for …
  yet. Press Continue to enter some information and create your …
  account."), not "Let's create you an account!".
- [ ] **Delete account** (website, Nov 17, 2026). Profile has **Delete
  account** under **Sign out**, for every role. Step one, "Delete your
  account?": "This deletes your Summit account for good, on the website and
  the app. It can't be undone." and a list (profile and QR pass deleted,
  taken off every session on your day and any team, to come back you sign
  up again), with **Yes, delete my account**. Step two: "To confirm, type
  your email: …", which unlocks **Delete account forever**. It calls
  `delete_my_account()`, signs out and goes Home with "Your account was
  deleted." If the function is missing: "Deleting accounts isn't turned on
  yet. Contact the Summit team to delete your account."; any other failure:
  "Couldn't delete your account. Nothing was changed."
  - **Backend: live.** Akhil ran it on the shared project (confirmed Nov
    20, 2026: the function exists and anonymous calls are refused). The
    SQL is the website's `scripts/delete_my_account.sql`; it isn't in
    `supabase/` here yet, so copy it in to keep the record. It deletes only
    the caller's `auth.users` row; the foreign keys decide what goes with
    it, and any reference with no `ON DELETE` rule makes the whole delete
    fail. The app only needs the Profile button and the two-step dialog.
  - The app needs it before launch anyway: the App Store and Google Play
    both require apps that create accounts to let people delete them.
- [ ] **No sponsors on Home** (website, Nov 17, Nov 20 and Nov 22, 2026;
  live on the website). The organizers don't want unpaid sponsors getting
  free advertising, so sponsors are off the public site, with no "past
  sponsors" list either, and off Home: they're only on the signed-in
  **Summit '27** tab's Sponsors subtab (see the next item). Remove
  `SponsorsSection` from the app's Home
  ([dashboard_screen.dart](lib/screens/dashboard_screen.dart)); Home is then
  Support EAF, Links and About the app, like the website. Last year's
  sponsors are not needed: empty `sponsors` in
  [home_about_sections.dart](lib/widgets/home_about_sections.dart) and
  delete their logos from `assets/sponsors/` (the website already did).
- [ ] **Summit '27 tab** (website, Nov 22, 2026, from the Nov 20 meeting).
  A signed-in **Summit '27** section with three subtabs, **Keynote**,
  **Team** and **Sponsors**, and **Support EAF** (Donate and Volunteer
  with EAF) under each. Keynote and Team say "Coming soon" ("This year's
  keynote speaker will be announced soon." / "About Me pages for the
  students and organizers working on Emerald Summit '27 are coming soon.")
  until their details come in. Sponsors shows one card per tier, highest
  first, with its price, perks and logos ("Open" while it has none), then
  **Become a sponsor** and **Sponsorship details**. The header line is
  "Saturday, January 23, 2027 · 9 AM to 5 PM · Emerald High School,
  Dublin, CA". On the website it's one **Summit '27** sidebar tab (since
  Nov 22, 2026; it was a group of three) with the three as tabs across the
  top of the page. On phones it's a sixth tab at the end of the bottom bar
  (Home's phone-only Summit '27 card is gone). The app's bottom bar is
  already full, so in the app reach it from Home, or decide whether it
  earns a tab.
  - **Sponsor ranking** (website, Nov 22, 2026): the tiers are one column,
    Capstone on top, so the order reads as a ranking. Each card has a
    square emerald badge with its rank (1 to 5), a "Tier n of 5" line with
    a five-bar meter filled to its level (Capstone five bars, Cornerstone
    one), and Capstone also says "Top tier" and has an emerald border.
  - **Heading** (website, Nov 22, 2026): the screen's one heading is a big
    **Summit '27** with the date line under it; no per-tab title
    ("Keynote", "Who's running the Summit?" and "Who helps make the
    Summit happen?" are gone).
  - **Intro** (website, Nov 22, 2026): the first time Summit '27 is opened
    in a session, an intro plays before the page shows. The screen you're
    on blurs out (no colour fill) and a sun comes up at the bottom centre
    (bright core, soft light pouring out, no rays) and expands a little.
    The Summit logo rises into the middle and rests, Summit '27 opens
    under the blur, then the logo glides into its place in the
    Support EAF card as the blur clears and the **Summit '27** heading
    rolls in letter by letter (about 1.8 s; a tap or Escape skips it;
    skipped under reduced motion). After that it just opens, until the app
    is restarted. In the app, play it when the Summit '27 screen opens
    from Home, e.g. a route transition that blurs the old screen with a
    BackdropFilter and flies the logo with a Hero (website:
    `src/components/Summit27Intro.tsx`).
  - Backend: none.
  - App: a Summit '27 screen with a segmented control or tab bar for the
    three subtabs, reached from Home (the bottom bar is already full),
    reusing the Sponsors tier list and Support EAF from
    home_about_sections.dart (website: `src/pages/Summit27Page.tsx`).
- [ ] **Spelling: Nihtahli Anand** (website, Nov 17, 2026). About the app
  lists "Nihtahli Anand", not "Nithali Anand". Fix `_developersAndTesters`
  in [home_about_sections.dart](lib/widgets/home_about_sections.dart).
- [ ] **Say "track" and "organizer" on screen** (website, Nov 20, 2026;
  live on the website). After the Nov 20
  meeting, everything people read says **track**, not "session", and
  **Organizer**, not "Admin" (the role label too: "Organizer"). Examples
  from the website: "Browse tracks", "Add the tracks you want to watch",
  "View assigned tracks", "Tracks assigned by an organizer", "Tracks I'm
  managing", "An organizer will assign your tracks.", "No tracks yet", and
  the FAQ's "8th graders can in some tracks". Only on-screen words change:
  code names, tables, columns and role keys stay (`Session`, `sessions`,
  `SummitRole.admin`). The Code of Conduct text still says "Sessions",
  because changing it makes everyone agree again. In the app, start with
  `SummitRole.admin => 'Admin'` in
  [user_profile.dart](lib/models/user_profile.dart), `admin('Admin',
  'Admins')` in [volunteer_contact.dart](lib/widgets/volunteer_contact.dart),
  then every visible "session" string.
- [ ] **New Zeffy donation form** (website, Nov 20, 2026; live
  on the website). Donate uses the form the
  organizers sent on Nov 20, id `6938c617-88ca-483d-ab7d-997e94ed8b6c`
  ("Fuel the Journey of Learning and Discovery"). The app's `eafDonateUrl`
  in [home_about_sections.dart](lib/widgets/home_about_sections.dart) still
  points at `be-the-catalyst-for-learning-and-discovery`. Donating happens
  only from the dashboard's Support EAF section; the website's landing
  page no longer has a donate button.
- [ ] **Become a sponsor opens the sponsor Zeffy form** (website, Nov 22,
  2026; live on the website once pushed). The organizers sent a second
  Zeffy form just for sponsors, "Become the Catalyst for Learning and
  Discovery"
  (https://www.zeffy.com/en-US/donation-form/be-the-catalyst-for-learning-and-discovery,
  the one the app's Donate uses today). On the website, **Become a sponsor**
  on the Summit '27 Sponsors subtab opens it in a popup like Donate (a new
  tab on phones), instead of emailing contact@ehsacademics.org; the header
  search's "Become a sponsor" opens it in a new tab. In the app, point
  Become a sponsor at that URL (opened in the phone's browser) and Donate
  at the new donation form from the item above. Website:
  `SPONSOR_FORM_URL` in `src/models/sponsors.ts`, `ZeffyFormButton` in
  `src/components/home/AboutSections.tsx`.
- [ ] **Edit your own announcements** (website, Nov 20, 2026). Admins and
  track organizers (volunteers with `can_post_announcements`) get **Edit**
  in the ⋯ menu of a post they wrote. It changes the subject, message and
  files; the audience and pin stay as posted, and personal notices are never
  editable. Readers see the new text in the same spot with a small
  "· edited" after the date, and nothing else: no banner, no notification,
  no "New" dot (those only fire on insert, and read state is keyed by the
  post's id). A file taken off is deleted from the bucket only once the edit
  saves.
  - Backend: [announcement_edits.sql](supabase/announcement_edits.sql) adds
    `announcements.edited_at`, the "Authors update own announcements" policy
    and the `announcement_edit_guard` trigger (see SUPABASE.md step 65).
    Run on the dev project Nov 20, 2026.
  - App: read `edited_at` in the Announcement model and show "· edited" in
    the News feed; add Edit (own posts only, same rule as the website's
    `canEditAnnouncement`) reusing announcement_compose_screen with the
    audience and pin locked. Updates must send only `title`, `body` and
    `attachments`.
- [ ] **Organizer metrics: experts, and only people in a track**
  (website, Nov 20, 2026). Profile → Metrics now opens with an **Experts**
  part: expert accounts, approved, waiting for approval (with a link to
  Expert approvals), experts serving in at least one track, expert sign-ups,
  tracks with no expert yet (a list linking to each, keynotes left out), and
  experts by discipline. Below it, **Who is registered** counts only people
  registered for at least one track (experts serving are left out): an
  account that finished sign-up but never joined a track is not counted in
  any chart. Headline tiles are now registered for a track, schools and
  track sign-ups, and the school and grade captions say so.
  - Backend: none. Waiting-for-approval is the length of
    `fetch_expert_requests()`; everything else comes from the existing
    `fetch_summit_metrics()` plus the sessions list.
  - App: in metrics_screen.dart, filter people to those with a non-expert
    registration before counting, and add the expert section (website:
    `registeredPeople` and `expertSummary` in `src/models/metrics.ts`).
- [ ] **Expert BeAMentor clearance** (website, Nov 21, 2026). Expert sign-up
  now also asks for a job title, company or organization, and an optional
  photo (the bio is now "Short bio"). After the Guest Expert Policy comes a
  BeAMentor step: the steps from the organizers' slides, **Open BeAMentor**
  (DUSD's page) and a link to the slides (since Nov 22, 2026 the published
  slideshow: https://docs.google.com/presentation/d/e/2PACX-1vS0p-Dqo0bWk4kFiCM-GU1aWB1LRQ1KKdniPMGiZ9LeZHtT_LJxnYJa_w9tGwdAHrP5f8Mok0L0DVMe/pub?start=true&loop=true&delayms=3000&slide=id.p),
  and the box "I have submitted my
  BeAMentor application". Ticking it gives full access, so the old "awaiting
  approval" screen no longer shows; a banner ("BeAMentor submitted. It is
  waiting to be verified by a Summit organizer…") stays at the top with an
  X; once closed it never comes back on any device (the website saves
  `beamentor_banner_dismissed: true` in the account's auth user_metadata;
  the app should read the same flag). Admins' **Expert approvals** became
  **Expert verification**, with two tabs, Not verified and Verified (only
  experts who ticked BeAMentor, so every expert in the app is one or the
  other), the photo, title and company,
  and **Verify**, which sends the expert the notice "Your BeAMentor
  clearance is verified".
  - Backend: `supabase/expert_beamentor.sql`. New profile columns
    `beamentor_submitted_at`, `beamentor_verified_at`, `beamentor_verified_by`
    (only the RPCs can set them); `mark_beamentor_submitted()` (sets
    `expert_status = 'approved'`, so `register_for_session` and
    `session_experts` work unchanged); `review_expert` now verifies;
    `fetch_expert_dashboard()`; the admins' queue notice counts experts
    waiting for verification; the public `expert_photos` bucket. Title,
    company and `photo_url` are keys in `details`.
  - App: after the policy, route experts with no `beamentor_submitted_at` to
    a BeAMentor screen; swap `expert_pending_screen.dart` for the banner; add
    the new fields and photo upload to onboarding and Edit profile; rebuild
    expert_approvals_screen.dart on `fetch_expert_dashboard()` (website:
    `src/pages/BeAMentorPage.tsx`, `src/components/BeamentorBanner.tsx`,
    `src/pages/ExpertApprovalsPage.tsx`, `src/models/beamentor.ts`). Until
    then, `fetch_expert_requests()` misses experts who ticked BeAMentor,
    because their status is already `approved`.
- [ ] **LinkedIn for experts** (website, Nov 21, 2026). The expert sign-in
  has **Continue with LinkedIn** first, above Google and email (Supabase
  provider `linkedin_oidc`, turned on Nov 21, 2026, with manual linking on).
  Supabase joins a LinkedIn sign-in to an existing account with the same
  verified email. The expert photo field has **Connect LinkedIn**
  (`linkIdentity`) for someone who signed up another way, and **Use LinkedIn
  photo** once it's connected; on sign-up the LinkedIn photo is brought in by
  itself. The photo is downloaded from LinkedIn and uploaded to
  `expert_photos`, because LinkedIn's links expire. The name is filled in
  from LinkedIn too. LinkedIn does not share title, company or bio.
  - Backend: none (provider settings only). For the app's own LinkedIn
    sign-in, add its deep-link redirect to the Supabase redirect URLs if it
    isn't there already.
  - App: a LinkedIn button on the expert sign-in
    (`signInWithOAuth(OAuthProvider.linkedinOidc)`), Connect LinkedIn and the
    photo copy in onboarding and Edit profile (website:
    `src/components/LinkedInSignInButton.tsx`,
    `src/components/ExpertPhotoInput.tsx`, `linkedInDetails` and
    `importLinkedInPhoto` in `src/services/auth.ts`).
- [ ] **Tracks in each discipline's description order** (website, Nov 20,
  2026, from Akhil's branch). A discipline's tracks are no longer listed
  purely by start time: they're grouped the way the discipline's description
  reads, then by start time within a group. TechVerse: computer science,
  then the other tech tracks (Product Design, AI Playground), then
  engineering. VentureVerse: Entrepreneurship Shark Tank before Marketing.
  Groups match on words in the track title, and a track that matches none
  goes last. The website does this on the discipline page, the Discover
  cards and the landing orbit; on wide screens the discipline page's grid
  fills down the first column, then the second, so TechVerse's tech and
  engineering tracks each read as a column. The discipline header counts
  "tracks", not "sessions".
  - Backend: none.
  - App: port `orderTracks` and its `GROUPS` table (website
    `src/models/trackOrder.ts`, tests in
    `src/models/__tests__/trackOrder.test.ts`) and use it wherever the app
    lists a discipline's sessions, instead of sorting by `start_time`.
- [ ] **Registration, account and expert wording** (website PR #18 from
  badrandumbs, Nov 21, 2026). The website changed these labels and messages:
  - "Discover" is now **Explore** in the sidebar and phone tab bar (it was
    "Explore & Register" for a few hours on Nov 21), and the "Browse
    tracks" / "Explore the disciplines" buttons (Home, and the empty
    schedule) say **Explore** too.
    The catalog page title is just **Disciplines**.
  - Bug report and feedback: **Your name** comes from the profile and can't
    be edited. With no profile name, sending says "Add your name in your
    profile before sending a report."
  - Expert pending screen: "Your expert account is pending approval", then
    "To help ensure a trusted and safe experience for our students, every
    expert registration is reviewed by the Emerald Summit organizing team."
    and "Once your account is approved, you'll be able to access the app and
    participate as an Expert." The button is **Sign up with a different
    role**. The contact email (pending screen and the declined-request
    dialog) is now `support@ehsacademics.org` instead of
    `nysha.singhal@ehsacademics.org`. The role-change note says "pending
    approval" too.
  - Delete account: "You are taken off every track on your day and any team
    you are on."
  - Backend: none.
  - App: `app_navigation.dart`, `root_nav.dart` and `discover_screen.dart`
    (tab and title), `report_screen.dart` (read-only name),
    `expert_pending_screen.dart` (`contactEmail`, wording, button) (website:
    `src/components/AppShell.tsx`, `src/components/ReportDialog.tsx`,
    `src/components/ExpertStatus.tsx`, `src/components/DeleteAccountDialog.tsx`).
- [ ] **Explore: no New discipline, no icon above a discipline's name**
  (website, Nov 21, 2026). The website removed the admins' **New
  discipline** button and dialog from Explore, and the discipline icon
  square above the name at the top of each discipline's page (the Explore
  panels keep their icons).
  - Backend: none.
  - App: ask the user whether the app should match. If so, take the
    **New discipline** button off `discover_screen.dart` (the
    `discipline_editor_screen.dart` route can go too) and drop the badge
    above the name on the discipline page.
- [ ] **One row for bugs and feedback** (website, Nov 22, 2026). Profile's
  **Report a bug** and **Send feedback** rows are now one row, **Report a
  bug/send feedback** ("Something broken, an idea, or something confusing?
  Tell us, with screenshots"). It opens the same form as a bug report; the
  Bug report / Feedback switch at the top still moves it to feedback.
  - Backend: none.
  - App: merge the two Profile rows into one that opens `report_screen.dart`
    as a bug report (website: `src/pages/SettingsPage.tsx`).
- [ ] **No page for reading reports** (website, Nov 22, 2026). The website
  removed the admins' **Bug reports and feedback** row on Profile and its
  page (`/admin/reports`, the old `BugReportsPage.tsx`); unknown addresses
  go to the start page, so that address does too. Reports are still saved
  and emailed; they're read in the team email and in Supabase.
  - Backend: done Nov 22, 2026. `bug-report-email` no longer puts an
    "Open in Reports" link in the team email (deployed as version 9;
    `SITE_URL` is no longer read). `set_bug_report_status` has no caller
    on the website now.
  - App: ask the user whether the app should match. If so, take the admin
    row off Profile and remove `lib/screens/bug_reports_screen.dart`.
- [ ] **Participants must give a real school** (website, Nov 22, 2026).
  School was already required at sign-up, but "." got through the **Other**
  box and accounts finished before Nov 11 had none. Now a school typed in
  Other needs at least 3 characters, 2 of them letters, and is not "none",
  "n/a" and the like ("Type your school's full name."). A finished
  participant whose school is blank or junk gets an **Add your school** step
  (just the school) on their next sign-in, like the phone and grade steps.
  - Backend: none.
  - App: add a school step to the auth gate for participants and the same
    check on the Other box in the school picker (website:
    `isRealSchoolName` and `missingGateField` in
    `src/models/profileFields.ts`, `src/pages/ProfileSetupPage.tsx`).
- [ ] **Team card wording** (website, Nov 22, 2026). On a participant's
  team card, "Members" is now **Team members**, the size note reads "Your
  team can have up to 4 members." (with the track's limit), and the button
  is **Leave team and continue solo**. The "can't remove yourself" error
  names the new button.
  - Backend: none.
  - App: the same three strings in `_ProjectCard`
    (`lib/screens/session_detail_screen.dart`), and the
    `cannot_remove_self` message in
    `lib/backend/supabase/supabase_repositories.dart` and
    `lib/backend/sample/sample_repositories.dart` (website:
    `src/components/session/ProjectCard.tsx`,
    `src/services/sessionRegistration.ts`).
- [ ] **Photo question after the Code of Conduct** (website, Nov 22, 2026).
  At sign-up, and on the agreement-only "One last step" page, the **Media
  Rights and Consent** question now comes after the agreement window and
  its checkbox, not before, so people read the Code of Conduct first. If
  both are missing, the error asks for the checkbox first. Experts are
  still not asked.
  - Backend: none.
  - App: in
    [code_of_conduct_screen.dart](lib/screens/auth/code_of_conduct_screen.dart),
    move the photo `RadioListTile`s below the `CheckboxListTile` (website:
    `src/pages/ProfileSetupPage.tsx`).
- [ ] **Solo comes first in the project question** (website, Nov 22, 2026).
  The registration form now asks *"Are you participating solo, or in a
  team?"*, matching the Solo / Team button order.
  - Backend: none.
  - App: `soloOrTeam` in [models.dart](lib/models/models.dart), and the
    quote in the registration form description above (website:
    `src/models/registration.ts`).
- [ ] **Switch a track's questions off** (website, Nov 22, 2026). For
  tracks like workshops, the track editor's **Participant questions** box
  now has a switch (on by default). Off, participants register with no
  questions at all: no solo/team, no project, none of the track's own
  questions. The **Project question** has its own switch (on by default).
  Off, solo or team is still asked but not a project name, and a new team is
  named after the person who creates it ("Alex's team", or "Team TV1234"
  when they have no name on file).
  - Backend: [participant_question_switches.sql](supabase/participant_question_switches.sql)
    (run Nov 22, 2026) adds `sessions.ask_participant_questions` and
    `sessions.ask_project_name` (both default true), rebuilds
    `sessions_with_counts`, and changes `register_for_session` (questions
    off: ignores the project choice and answers, saves `project_mode` null)
    and `update_my_registration` (no name needed when the track does not
    ask one). Old app builds keep working: they send a project, and the
    server drops it on a track with questions off.
    [activity_log_question_switches.sql](supabase/activity_log_question_switches.sql)
    makes the activity log record either switch flipping.
  - App: read both columns in the session model; two switches in
    `session_editor_screen.dart` (hide the team size, project wording and
    the track's questions while the first is off, and the wording while the
    second is off); in the registration screen, skip the sheet entirely when
    questions are off (or when a solo-only track asks no name and has no
    questions of its own), hide the name field when the name is off, and
    show "Is this your team?" with the team's name when joining; hide **Edit
    my registration** and the empty project card on a no-questions track,
    and the name field in "Leave team?" where no name is asked. The roster
    lists a no-questions track's participants as **Participants** and an
    unnamed solo project under the person's name (website:
    `registrationAsksAnything` in `src/models/registration.ts`,
    `src/components/verse/SharedSessionForm.tsx`,
    `src/components/session/RegistrationForm.tsx`, `SessionView.tsx`,
    `SessionRoster.tsx`).
- [ ] **Summit logo home link on discipline and track pages** (website,
  Nov 22, 2026). Discipline pages and track pages are full screen with no
  sidebar, so next to **Back** at the top there is now a pill with the
  Summit logo and **Emerald Summit ’27** that goes to the home page.
  - Backend: none.
  - App: the discipline and session screens already sit inside the bottom
    bar, so Home is one tap away; add the same logo pill to their top bar
    only if the full-screen discipline view hides the bar (website:
    `src/components/verse/SummitHomeLink.tsx`).
- [ ] **Faster close on the discipline portal** (website, Nov 22, 2026).
  Closing a discipline (Back or Escape) shrinks the circle in 300ms with an
  ease-out, `cubic-bezier(0.16, 1, 0.3, 1)`, instead of 420ms with an
  ease-in, so the screen reacts the moment Back is tapped. Opening is
  unchanged (620ms, `cubic-bezier(0.65, 0, 0.35, 1)`).
  - Backend: none.
  - App: the portal's reverse animation in the discipline screen (the
    timings came from `discipline_effects.dart`): 300ms with
    `Cubic(0.16, 1, 0.3, 1)` (website: `close()` in
    `src/components/verse/useCircleReveal.ts`).
  - Same pass on the website, no app work: buttons dip 1px when pressed (Flutter's ink
    ripple already does this job), hover effects only on devices with a mouse,
    the dashboard gradient moved onto a transform layer, and loaded pages
    fade in over 200ms after their loading skeleton. Check whether the
    app's loading shimmer cuts straight to content; if it does, a 200ms
    `AnimatedSwitcher` fade would match.
  - Also Nov 22, no app work: the website's QR pass no longer shows the
    user id with a Copy button under the code, which matches the app's
    Check-in pass card.

Website-only on purpose, no app work: the public landing page (hero, the
arrival, the Summit figure, the FAQ, the universes orbit, and since Nov 17,
2026 role rows that link to each role's sign-up, with badges beside them
that scrolling swings out one by one and that can't be clicked since Nov
22, the Summit figure's terraces stepping the same way, and the date line's
"Dublin, CA"; the Nov 17 sponsor terraces and Support EAF corner seal were
removed again on Nov 20, along with the stats reorder, the "Frequently
Asked Questions" heading and the new favicon files), the profile setup page's wider layout, the Google button resetting after a
sign-in that gets sent to Sign up, the
`website_show_session_times` switch, the header search jumping to pages,
disciplines and the donate and sponsor links (Nov 22, 2026; the app's
Discover search stays sessions-only, with the disciplines listed under it), the
browser's 15-minute pause after five wrong test passwords, the "your QR
pass is also in the mobile app" note, and the "Better in the app" banner
phones see on the website (Nov 14, 2026). **At launch:** that banner stays
hidden until the website knows the store links, so when the app goes live,
paste its App Store and Google Play links into the website's
`src/lib/appStores.ts` and push. The Play link is
`https://play.google.com/store/apps/details?id=com.emeraldsummit.emerald_summit`;
the App Store one has the numeric id from App Store Connect.

**Shipping the website.** Every push to the website repo's `main` deploys to
production on Vercel (a free plan run by a teammate, Production environment
only), so website settings live in code rather than Vercel variables where
they can; only the two `VITE_SUPABASE_*` values are set there. Open website
PR #14 (an admin user-management page, volunteers limited to checking in
their own discipline, track-deletion notices) was written against the
website's old database (`users`, `summit_tracks`, `session_registrations`)
and its own migrations, so it can't be merged. Its ideas belong in the
admin-tools work above: add the RPCs here first, then build the website page
on them. PRs #8 (already in `main`) and #12 (fake volunteer counts; volunteers
are assigned by an admin) aren't needed either.

This section is written for the person (or coding agent) doing that work in
the website repo. Read all of it before changing code. The website repo's own
README links here; this file is the source of truth for the backend.

### Read first, in this order
1. This section.
2. **Backend** above: the data model, roles and permissions, and the
   gotchas. Every table, RPC, trigger and policy the website will use is
   described there.
3. [SUPABASE.md](SUPABASE.md): the SQL run order, the Edge Functions, and
   §3b (test accounts).
4. **App writing rule**, **Session rooms: locked** and **Summit date** above.
   All three apply to the website too.
5. The app's Supabase code, which is the reference implementation to port:
   [supabase_repositories.dart](lib/backend/supabase/supabase_repositories.dart)
   (every query and RPC call, with the parameters it sends and how it reads
   the result), [supabase_auth_service.dart](lib/backend/supabase/supabase_auth_service.dart),
   and [supabase_archie_repository.dart](lib/backend/supabase/supabase_archie_repository.dart).
   The contracts they implement are in
   [repositories.dart](lib/backend/repositories.dart) (including the
   `RegistrationResult` codes).
6. The models: [models.dart](lib/models/models.dart) and
   [user_profile.dart](lib/models/user_profile.dart). Their `fromMap` /
   `toMap` give the exact column names and value formats. Port these to
   TypeScript types first and build everything else on them.

When this README and the code disagree, the code wins; say so in your PR so
the README gets fixed.

### Rules (don't break these)
- **The app repo owns the schema.** Don't create, alter or drop tables,
  views, policies, functions, triggers or buckets from the website repo.
  - Delete the website's `supabase/migrations/`, `supabase/seed.sql` and
    `supabase/config.toml` in the first PR (keep them in git history). Never
    run `supabase db push`, `db reset` or `link` from the website repo against
    `dgrskmykbkvphnaasfzl`: `db push` would create the website's old `users`
    and `announcements` tables next to the app's, and `seed.sql` would write
    sample rows into the live catalog.
  - If the website needs a schema change, add a new `.sql` file to this repo's
    [`supabase/`](supabase/), add it to SUPABASE.md's run order and to the data
    model above, and ask Arjun to run it on dev. The SQL here is run by hand in
    the SQL editor; there is no migrations history.
  - **Additive only.** The app on people's phones (TestFlight) reads these
    columns. Never rename or drop a column, change a type, or change what an
    RPC returns. Add a new column or a new RPC instead, and only remove the old
    one after every app build that reads it is gone.
- **Only the publishable key in the browser** (`sb_publishable_…`). Never the
  secret or `service_role` key, in code, in `.env*`, or in Vercel's env vars.
  Everything in a Vite `VITE_*` variable ships to every visitor.
- **RLS and the RPCs are the security.** Hiding a button is not. If a call
  fails with a permission error, the website is doing something the app doesn't
  allow either: match what the app does, don't ask for a looser policy.
- **Write through the same RPCs the app uses.** Several tables have no direct
  write grant on purpose: `registrations` (use `register_for_session` /
  `update_my_registration`), `teams` (only reached through RPCs),
  `session_volunteers` (`assign_volunteer_to_session` /
  `unassign_volunteer_from_session` / `set_session_manage`),
  attendance and check-in (`mark_session_attendance`, `mark_summit_checkin`,
  `scan_summit_checkin`). Send the same parameters the app sends, including
  `p_intent` (`add` / `remove`) on `register_for_session`.
- **Server-owned columns.** The website never decides a user's power. `role`
  is forced back to `participant` by a trigger unless the email is on the
  Google Sheet allowlist; `volunteer_subtype`, `managed_disciplines` and the
  three `can_*` flags come only from the sheet; `expert_status` changes only
  through `review_expert`. Write `role` the way the app does (onboarding), then
  **re-read the profile** to see what the server kept.
- **Same words as the app.** The App writing rule covers every string a user
  reads on the website. Reuse the app's labels and error messages rather than
  writing new ones (see "Copy" below).
- **No new backend features from the website alone.** If the website needs
  something the app doesn't have (a public directory, judging), talk to Arjun
  first; it gets designed once for both.

### The website today vs. the shared backend
The website was built against its own schema. Most of its data layer gets
replaced, not adapted.

| Website now | Shared backend |
|---|---|
| `public.users` table | `public.profiles` (`id` = `auth.users.id`). A trigger creates the row at sign-up; the client reads it and updates its own row, it never inserts one. RLS: your own row only. |
| `name` | `full_name` |
| `profile_setup_complete` | `onboarded` |
| `phone`, `bio`, school, grade… | `details` jsonb. The keys per role are the `RoleQuestion` lists in [user_profile.dart](lib/models/user_profile.dart) (`school`, `grade`, `phone`, `student_id`, `expertise`, `bio`). |
| `org`, `directory_visible`, `*_visible` | Don't exist. Drop them. |
| Roles `participant`, `attendee`, `volunteer`, `expert`, `ambassador`, `admin` | Stored ids `participant`, `expert`, `parentSpectator`, `volunteer`, `admin`. Labels: Participant, Expert, Spectator, Volunteer, Admin. |
| `attendee` | `parentSpectator` (adding a session always spectates). |
| `ambassador` | Not a role. A `volunteer` whose `volunteer_subtype` is `eaf_ambassador` (others: `parent_volunteer`, `student_volunteer`), set from the sheet. Nobody picks it. |
| Expert signs in and is an expert | Picking Expert makes `expert_status = pending` until an admin approves (`review_expert`). Handle pending and declined the way the app does. |
| `checked_in_at` on `users` | `summit_checkins` via `my_summit_checkin`, `scan_summit_checkin`, `mark_summit_checkin`, `fetch_attendee_directory`, `fetch_checkin_stats`. |
| QR pass encodes the user id | Same in the app: the QR is the bare `auth.users.id`. Keep it, so a pass on a laptop scans at the app's front desk and the reverse. |
| Its own `announcements` (category enum, `author_id`, `author_name`) | The app's `announcements` (see `Announcement.fromMap` in [models.dart](lib/models/models.dart)): `audience`, `pinned`, `discipline_id`, `created_by`, `target_user_id` (personal notices), `session_id`, `attachments`. Read state in `announcement_reads`, hides in `announcement_dismissals`. |
| `announcement-media` bucket (100 MB) | `announcement_attachments` bucket, uploads under `<user_id>/`, admins and volunteers with `can_post_announcements` only. Size limits in [storage_upload_limits.sql](supabase/storage_upload_limits.sql). |
| Tracks | One track = one session. Sessions under disciplines (`disciplines`, `sessions_with_counts` view for reads, `sessions` for writes). |
| Directory page (everyone, with visibility settings) | No equivalent; `profiles` is own-row-only. `fetch_volunteer_hub` lists volunteers for the people allowed to see it. Drop the directory or turn it into the volunteer hub. |
| Judging page | No backend. Leave it hidden (the route already redirects). |
| Resources page | The app no longer has one. Leave it unlinked or delete it. |
| "Bypass Login (Local Demo Mode)" | Remove it. A fake local session against a real backend shows screens whose data never loads. Use password-gated test accounts (below). |
| `src/test/databaseSecurity.adversarial.test.ts` | Tests the old schema. Rewrite it against the RPC behaviour described in **Backend**, or delete it. |

### Hooking the website up
**Env vars** (local `.env.local` and Vercel, Production + Preview):
```
VITE_SUPABASE_URL=https://dgrskmykbkvphnaasfzl.supabase.co
VITE_SUPABASE_PUBLISHABLE_KEY=sb_publishable_…   # same key as the app's env.json
```
(Test accounts aren't an env var any more: the website switches them on in
code, `isDevLoginEnabled` in `src/lib/devLogin.ts`, so Vercel needs only the
two values above.)
Rename `VITE_SUPABASE_ANON_KEY` to `VITE_SUPABASE_PUBLISHABLE_KEY` in
`src/lib/supabase.ts` and `.env.example`. Ask Arjun for the key.

**Supabase dashboard (Arjun does these on the dev project; list them in your
PR so they aren't missed):**
- Auth → URL Configuration: **Site URL** `https://emerald-summit.vercel.app`,
  with `https://emerald-summit.vercel.app/**` in **Redirect URLs**. Done
  Nov 11, 2026. The email link and the website's fallback Google redirect
  need them. (`http://localhost:5173/**` is no longer on the list; add it back
  to test the redirect locally.)
- **Google sign-in on the web** (done Nov 11, 2026) uses Google's own sign-in
  button (Google Identity Services): the popup returns a Google ID token and
  the website calls `signInWithIdToken({ provider: 'google', token, nonce })`,
  the same check as this app's native sign-in. Google's popup names the
  website, not the Supabase project URL. Same project, same accounts:
  Supabase links identities by verified email, so Google on the phone, Google
  on the web and the emailed code all land on one profile.
  - It uses the **Web** client (`GOOGLE_WEB_CLIENT_ID`, `665674617320-97u…`).
    All three clients (Android `igtl…`, iOS `khls…`, Web `97u…`) are in Google
    Cloud project `inspiring-chess-491023-g8` (number `665674617320`).
  - Google Cloud, Web client: `https://emerald-summit.vercel.app` is under
    *Authorized JavaScript origins* (add any new website domain there), and
    `https://dgrskmykbkvphnaasfzl.supabase.co/auth/v1/callback` is under
    *Authorized redirect URIs* for the website's fallback redirect flow.
  - Supabase → Sign In / Providers → Google: *Client IDs* read Web, Android,
    iOS, in that order, with the Web client's secret. **Keep all three.** The
    phone's tokens need the Android and iOS IDs on the list, and the website's
    fallback redirect always sends the **first** ID to Google, which must be
    the Web one. (Before Nov 11 the Android ID was first, so the web redirect
    failed with `redirect_uri_mismatch` while the phone still worked.)
  - If the OAuth consent screen is ever put back in Testing, only listed test
    users can sign in.
- Consider turning on Auth CAPTCHA (Turnstile or hCaptcha). A public page that
  sends sign-in codes will get bots, and the emails go out through the org's
  Google Workspace SMTP. If it's turned on, the app needs an update too, so
  agree on it first.

**Auth flow** (port of [auth_gate.dart](lib/screens/auth/auth_gate.dart) and
[sign_in_screen.dart](lib/screens/auth/sign_in_screen.dart)):
1. Email: `signInWithOtp({ email, options: { shouldCreateUser: true } })`,
   then `verifyOtp({ email, token, type: 'email' })`. Accept up to 10 digits.
   Or Google.
2. Load `profiles` for `auth.uid()`. **If the read fails, show "Try again",
   never onboarding**: onboarding saves the profile and would wipe the
   person's answers.
3. Not `onboarded` → onboarding (role picker, then that role's questions from
   `RoleQuestion`), saved the way `SupabaseProfileRepository.save` does it,
   then re-read. Roles that need a phone get the phone step
   ([phone_required_screen.dart](lib/screens/auth/phone_required_screen.dart)).
4. Expert pending or declined: same screens and one-time note as the app
   (`acknowledge_expert_decline`).
5. Changing role later goes through `preview_role_change` first, as in the app
   (sessions move down to spectating).

**Test accounts on the website.** The password check lives in the shared
`dev-login` function ([SUPABASE.md](SUPABASE.md) §3b, and "Dev-testing build vs.
production build" below), so the website only needs the form and the call.
- **On in Production** (decided Nov 10, 2026): the Vercel project has only a
  Production environment, the site isn't marketed widely yet, and every test
  account still needs the shared password. The switch is in the website's
  code (`isDevLoginEnabled` in `src/lib/devLogin.ts`), not a Vercel setting:
  set it to `false` and push once that changes. This needs the `dev-login` function's `DEV_LOGIN_ENABLED=true`
  secret on the shared project, which the app's dev builds use anyway.
- Same flow as the app, no separate form. Only when `isDevLoginEnabled` is
  on: when someone submits the normal
  email box, first call
  `supabase.functions.invoke('dev-login', { body: { email, check: true } })`.
  `{ test: true }` → show a password box instead of sending a code;
  `{ test: false }` or any error → send the normal code.
- With the password, call
  `supabase.functions.invoke('dev-login', { body: { email, password } })`.
  On `200 { otp, type }`, finish with
  `verifyOtp({ email, token: otp, type: type === 'magiclink' ? 'magiclink' : 'email' })`.
  `401` → "Wrong email or password." `403` → "Test accounts are turned off on
  this server."
- Never store the password (no `localStorage`, no URL), and never put it in
  the repo or a Vercel variable. People type it.
- After sign-in, skip the role picker like the app does
  (`_autoOnboardTestAccount` in [app_state.dart](lib/app_state.dart)): admin if
  allowlisted, else volunteer if allowlisted, else infer from the email
  (`expert`, `spectator`/`parent`, otherwise participant).

**Reads and realtime**
- Catalog: `disciplines` and `sessions_with_counts` (it adds `enrolled` and the
  discipline name; `enrolled` is never stored). Always pass `ascending`
  explicitly to `.order()`: disciplines and rooms by `sort_order`, sessions by
  start time. (The JS client defaults to ascending, the Dart one doesn't; being
  explicit keeps the two lists in the same order.)
- `start_time` / `end_time` are 24-hour text (`09:45`, `14:00`). Compare them as
  text and show them in 12-hour form like the app (`to12HourTime` in
  [models.dart](lib/models/models.dart)). When the website writes a time, keep
  two-digit hours.
- `fetch_summit_status()` gives the summit date (`2027-01-23`) and whether
  feedback is open. Use it for the countdown and the date line; don't hard-code
  a date.
- Realtime: subscribe to `announcements` (the app's channel is
  `public:announcements`) once signed in, and to `summit_checkins` only on the
  front-desk screen. Unsubscribe on sign-out and unmount. Apply an
  announcement from the message's own row instead of re-fetching the feed
  (since Nov 22, 2026, in the app and on the website), so a post doesn't send
  every open device to the database at once; re-fetch only when the message
  has `errors` (Realtime cut a too-big row short). The free plan allows
  200 concurrent connections across the app and every open website tab.

**Storage egress (read this before showing any photo).** Storage downloads
count against the free plan's 5 GB/month cached egress. The app went over it
once (see the `CachedNetworkImage` note in **Backend**); the grace period ended
Oct 26, 2026, so new overage can now fail with `402`, and that breaks the
**app's** photos too.
- Lazy-load every Storage image (`loading="lazy"`, explicit width and height)
  and never load a whole bucket on the public landing page.
- Don't use Supabase image transformations (paid plan) or autoplay video from
  Storage. Landing-page media (`public/sky`, `public/gallery`) stays on Vercel.
- Uploads from the website should set a long `cacheControl` so browsers keep
  them.

**Archie** (optional, later). `archie-chat` calls the Claude API, billed per
question, with a per-user daily cap. It checks the caller's session itself, so
send the user's JWT. If the website gets Archie, port the streaming client
from [supabase_archie_repository.dart](lib/backend/supabase/supabase_archie_repository.dart)
and the app's chat screen; don't add a second function.

### What to build, in order
Do one phase per PR. After each, test with the same account on the website and
on the app (two devices), using test accounts for each role.

1. **Cut over.** New env vars, delete the website's `supabase/` folder, remove
   bypass login, add the TypeScript models. Signed-in pages may be empty.
2. **Auth and onboarding**, including test accounts, Google, the phone step,
   expert pending/declined.
3. **Read-only screens:** Home, Discover → discipline → session page
   (Session tab), News (with read state and pinned), Profile with the check-in
   pass.
4. **Schedule writes:** add / remove / spectate / manage via
   `register_for_session` and `set_session_manage`, Edit my registration
   (`update_my_registration`), participant questions, teams (`find_team`,
   `fetch_my_project`, `transfer_team_ownership`, `remove_team_member`),
   time clash checks (`session_time_conflicts`). Show every result code the
   app handles.
5. **Volunteer tools:** My assignments, the session Participants tab (roster +
   attendance), front desk + QR scanner, the volunteer hub, volunteer hours
   (`volunteer_hour_logs`).
6. **Admin tools:** announcement composer with attachments, session and
   discipline editors, rooms, assigning volunteers, the expert queue
   (`fetch_expert_requests`, `review_expert`), summit metrics, Archie insights.
7. **Summit follow-up:** expert feedback and "volunteer again?"
   (`submit_expert_feedback`, `set_eaf_future_interest`), opened by
   `fetch_summit_status().feedback_open`.
8. **Archie**, if wanted.

Every RPC the app calls is listed in **Backend**; the call sites are in
`supabase_repositories.dart`. A phase is done when the website and the app
agree on the same data for the same account, and every state the app shows
(empty, loading, error, full, closed, pending) exists on the website.

### UI and UX: match the app
The app is the reference for every **signed-in** screen. The public landing
page (WelcomePage, the sky video, the showcase) keeps its own look, with the
same brand colors.

- **Navigation.** The app's tabs are Home · Schedule · Discover · News ·
  Archie, with Profile behind the avatar
  ([root_nav.dart](lib/screens/root_nav.dart)). Use the same names, the same
  order and the same grouping in the website's sidebar and in its mobile
  bottom bar. "Announcements" becomes **News**; the Schedule page header reads
  **My Day**; Settings lives under Profile. Volunteer and admin tools appear in
  the same places the app puts them (Home action grid, Profile, the session
  page tabs).
- **Screens.** Each app screen in [lib/screens/](lib/screens/) gets a website
  page with the same sections in the same order, the same empty states and the
  same confirmations (deletes ask you to type the name:
  [type_to_confirm_dialog.dart](lib/widgets/type_to_confirm_dialog.dart)). The
  session page keeps the app's tabs: Session / Participants / Experts /
  Volunteers, each shown only to the people the app shows it to. A wider
  screen can show more at once (two columns, a side rail), but not different
  content.
- **Color.** [theme.dart](lib/theme.dart) is the palette. Light: Emerald
  `#0C7A55`, Deep Emerald `#0A5F43`, Ink `#16211C`, Mist `#EEF5F1`; the website's
  Navy `#101C36` stays for the sidebar. The app also has a dark theme (Light /
  Dark / System, chosen in Profile); give the website the same three choices
  using the app's dark tokens (`night`, `nightSurface`, `nightMist`,
  `nightBorder`, `nightText`, `mint` for primary). Put them in the CSS
  variables in `src/index.css`, not in components.
- **Disciplines.** Each discipline has its own palette and animated motif in
  [discipline_vibe.dart](lib/widgets/discipline_vibe.dart) (TechVerse circuit,
  VentureVerse ticker, BioSphere cells, NovaSphere stars, CivicVerse ripples,
  ImagineX paint). Copy the hex values exactly into a shared map and use them
  on discipline pages, session cards and pills. The motifs can be simpler on
  the web (CSS or canvas), but must stop under `prefers-reduced-motion`.
- **Icons.** The app uses Phosphor duotone
  ([duotone_icon.dart](lib/widgets/duotone_icon.dart)). Switch the website
  from lucide to `@phosphor-icons/react` with `weight="duotone"` and use the
  same icon for the same thing (each discipline's icon is `disciplineIcon()` in
  [models.dart](lib/models/models.dart)).
- **Type.** The app uses the platform font, so there is nothing to copy; the
  website keeps Satoshi for headings and Instrument Sans for text.
- **Copy.** Same labels, button text and messages as the app, word for word.
  Search the app for a string before writing a new one. Error text for RPC
  result codes is in `supabase_repositories.dart` and the screens; reuse it.
  Write any new strings by the App writing rule (no em dashes, no filler,
  sentence case), and add the same string to the app if it's a shared state.
- **Rooms.** While rooms are locked, the website's session page hides the
  room and its session editor can't change it. Discover, Schedule and Home
  still show rooms, as in the app.
- **When the app changes.** A UI change to the app that affects a shared
  screen should get a matching website issue. Note it in the PR.

### Checklist before each website PR
- `npm run build` and `npm test` pass.
- Nothing from `supabase/` in the website repo, and no `service_role` key or
  test-account password anywhere.
- Tried as a participant, a parent/spectator, an expert (pending and
  approved), a volunteer and an admin, using test accounts.
- The same action on the app and the website gives the same result, and the
  other side sees it (refresh or realtime).
- New strings checked against the App writing rule.
- Any schema change is a new file in this repo's `supabase/`, not in the
  website.

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
> `flutter run` (or the IDE's default run) boots in sample mode — Discover
> shows the sample disciplines and News the sample announcements (with no
> attachment buttons in the composer). Relaunch with the flag (or the VS Code "Supabase" config).

### Dev-testing build vs. production build (the `DEV_LOGIN` bypass)
The **code-email login bypass** (sign in as a test account without an OTP — see
[SUPABASE.md](SUPABASE.md) §3b) is controlled by the `DEV_LOGIN` compile-time
flag, injected from `env.json` like the Supabase keys. Because it's a login
backdoor, it is **off by default** and must be enabled in **two** places at once
— either alone does nothing.

**It's password-gated.** In a `DEV_LOGIN` build, *Email me a code* first asks
the `dev-login` function whether the email is a test account. If it is, the
screen shows a password box instead of sending a code, and the function checks
that password against its `DEV_LOGIN_PASSWORD` secret. Real emails get the
normal code. The website shares this backend and this function, so the
password (not the build flag, and not the publishable key, which anyone can
read from a web page) is what keeps strangers out. The screen is
[sign_in_screen.dart](lib/screens/auth/sign_in_screen.dart); the calls are
`isTestAccount` and `signInWithTestAccount` in
[supabase_auth_service.dart](lib/backend/supabase/supabase_auth_service.dart).

**To build for DEV testing** (your dev Supabase project only):
1. In your **dev** `env.json`, add `"DEV_LOGIN": true` alongside the dev
   project's URL + publishable key. (`env.json` is gitignored, so this flag never
   reaches source control or another machine.)
2. On that **dev** project, set the `DEV_LOGIN_ENABLED=true` and
   `DEV_LOGIN_PASSWORD` secrets, deploy the `dev-login` Edge Function, and run
   `test_accounts_setup.sql` (full steps in [SUPABASE.md](SUPABASE.md) §3b).
3. Run/build as usual with `--dart-define-from-file=env.json`. Testers type a
   code email in the normal email box, then the password when it's asked for;
   everyone else uses normal OTP.

**To build for PRODUCTION** (never ship the bypass):
1. Use your **production** `env.json` — the prod URL + publishable key — with
   **`DEV_LOGIN` absent or `false`**. The committed [env.example.json](env.example.json)
   ships `false`; keep it that way for any prod/TestFlight build. With the flag
   off the app never even calls the bypass function.
2. On the **production** project, **do not** deploy `dev-login`, **do not** set
   `DEV_LOGIN_ENABLED` or `DEV_LOGIN_PASSWORD`, and **do not** run
   `test_accounts_setup.sql`. That is the
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
> attendees); use a different, stronger password than dev's
> (`DEV_LOGIN_PASSWORD`, already required) and consider re-enabling Verify-JWT with a caller check;
> rate-limit and log every use; and gate the app path behind its own prod flag
> so it can be shipped dark and flipped on only when needed. Treating it as
> "flip `DEV_LOGIN_ENABLED` on prod" would be unsafe. Revisit when we actually
> need prod demo accounts.

## Test & analyze
```bash
flutter test
flutter analyze
```

## Code health: `/checkup` and the code map
Claude Code tooling for keeping the codebase in shape. Lives in
`.claude/skills/checkup/` (local, not committed).

- **`/checkup`** looks at what changed since files were last checked and
  routes the work to installed Claude Code plugins: agent-skills (review,
  tests, security, simplification), Context7 (current package docs),
  avoid-ai-writing, impeccable and taste-skill (UI), and `/update-readme`. It
  fixes what's safe, verifies with `flutter analyze` + `flutter test`, asks
  about larger changes once at the end, and commits locally. It never writes
  to Supabase.
- **Per-file tracking.** When a checkup reviews a file it saves a fingerprint
  (a SHA-1 hash of the file's contents) in `.claude/skills/checkup/state.json`
  (gitignored). Next run, any file whose contents no longer match is
  reviewed again; files never checked are picked up a few per run, most
  connected first, until all ~117 files in `lib/`, `test/` and `supabase/` are
  covered. `/checkup all` covers everything at once.
- **graphify** builds a code graph (`graphify update .`, ~3 s, no AI cost) of
  `lib/`, `test/` and `supabase/` (scope set in `.graphifyignore`) into
  `graphify-out/` (gitignored). `/checkup` uses it to find the files that
  depend on whatever changed. SQL files are not parsed yet (needs
  `graphifyy[sql]`).
- **3D code map.** `python3 .claude/skills/checkup/scripts/graph3d.py` turns
  the graph into `graphify-out/graph3d.html`: a draggable, searchable 3D view
  where each color is a group of related code. It contains only names and
  file paths from this (public) repo, no keys or data. Planned: publish it on
  GitHub Pages from a `gh-pages` branch.
- **Supabase CLI** is set up locally and linked to the dev project
  (`supabase link --project-ref dgrskmykbkvphnaasfzl`; link state in
  `supabase/.temp/`, gitignored). Schema dumps (`db pull` / `db dump`) need
  Docker, which isn't installed yet.

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
  attendance marking are implemented but not yet live-tested. **QR check-in**
  (Profile pass, front-desk scanner, live stats + realtime sync) is unit-tested
  and its SQL ([qr_checkin_setup.sql](supabase/qr_checkin_setup.sql)) is **run
  on the dev project**. It hasn't been live-tested on devices yet; it ships in
  TestFlight build 1.0.0+10. Run the SQL files
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
- **Activity log, next steps.** The log itself is built (see Metrics). Still to
  do: an admin screen to browse it, optional screen-view events from the app,
  and, **before release**, saying we log activity in the privacy policy, the
  App Store privacy label and the Google Play data safety form (many users are
  minors).
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
  - **When building it, in the app** (decided Nov 13, 2026; see **No
    notification setting** above):
    - [ ] Ask the phone for permission once, the first time the app opens
      after push ships. iOS: `FirebaseMessaging.requestPermission()`.
      Android 13 and up: the `POST_NOTIFICATIONS` runtime permission (add it
      to `AndroidManifest.xml`); older Android needs no prompt. If they say
      no, don't ask again.
    - [ ] Keep Profile's **Notifications** row as it is: no switch, and it
      opens the phone's notification settings for the app
      (`AppSettings.openAppSettings(type: AppSettingsType.notification)`).
      It's how someone who said no turns push on later. On iPhone the app's
      Settings page only gets a Notifications entry once the app has asked,
      which is why the first step comes first.
    - [ ] Send to every device token in the audience. Don't filter by a
      profile column (there isn't one: `notifications_enabled` is unused);
      the phone drops pushes the person turned off.
    - [ ] While the app is open, show the in-app banner instead of a system
      notification, so nothing shows twice
      (`FirebaseMessaging.onMessage` → `inAppBanner.show`). The banner
      always shows; nothing mutes it.
    - [ ] Tapping a push opens the post in Announcements, or the bell's list
      for a personal notice, the same places the banner goes.
    - [ ] Delete the device's token on sign-out, so the next person on that
      phone doesn't get the last one's pushes.
    - [ ] Nothing on the website: it has no browser push and no setting.
  - **Expert approvals:** also push the admins' *"Experts waiting for
    approval"* notice (posted by `refresh_expert_queue_notice` in
    [role_change_downgrades.sql](supabase/role_change_downgrades.sql)). The
    webhook on `announcements` INSERT covers it, since a new waiting expert
    re-inserts the notice; it only needs to send to `target_user_id`.
  - **Google Sheet problems:** also push the admins' *"Problem with the Google
    Sheet"* notice from `sync-allowlist`, so they hear about it with the app
    closed. The INSERT webhook covers it too: the function inserts it once
    when the problem starts and only updates it after that, so admins get one
    push per problem, not one every 5 minutes.
  - Also planned: per-user "next session" reminders; email fan-out; and a
    push / announcement to experts, volunteers and admins **when post-summit
    feedback opens** (on summit day once the last session ends, i.e. when
    `summit_feedback_open()` turns true). Until then the app finds out on its
    own at launch or when it comes back to the foreground.
- Per-session **attendance roster marking stays toggle-based** (no QR) — QR
  is only for summit-wide front-desk check-in.
- **Per-subtype volunteer onboarding** — tailor the sign-up questionnaire to the
  volunteer subtype (EAF ambassador / parent / student). Deferred: the subtype
  currently arrives from the sheet *after* sign-up, so all volunteers share one
  questionnaire for now (see [user_profile.dart](lib/models/user_profile.dart)).
- **Set the summit date** once the organizers confirm it. Follow the checklist
  in [Summit date: what changes when it's set](#summit-date-what-changes-when-its-set).
- Team formation; spectator seats; check-in dashboard; pre-summit milestone
  reminders; sponsor blocks; post-event social posts. (Volunteer certificates
  were dropped: not needed.)

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
