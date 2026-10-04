# Product

<!-- impeccable:product-schema 1 -->

## Platform

android

## Users

**Primary: student attendees.** Middle and high schoolers at Emerald Summit '27, using their phones to plan the day, find and join sessions, and get around summit day. Design decisions favor them first.

Secondary roles share the same app, each with extra tools: **experts** (who join sessions to serve as experts), **parents / spectators**, **volunteers** (EAF ambassadors, parent and student volunteers, who run session rosters, attendance, and front-desk check-in), and **admins** (who manage the catalog, rooms, and announcements).

## Product Purpose

The companion app for **Emerald Summit '27**: the Tri-Valley's student-run STEAM summit at Emerald High, Dublin CA, in January 2027. It lets students browse disciplines and sessions, build a personal schedule, register to participate, spectate, or serve as an expert, follow live announcements, and ask Archie (an AI assistant grounded in the live catalog and the user's schedule) about the summit. Success: a student opens the app on summit day and always knows where to be next, and has a reason to open it before the day too.

## Positioning

- **Student-run and local.** Built and run by Emerald High students for the Tri-Valley STEAM community, not a generic conference product.
- **Hands-on sessions.** Students take part in real sessions as participants (solo or team projects), spectators, or experts. It isn't a static agenda.
- **Expert feedback on student projects.** Experts in the room give feedback on what students build. This is part of why a student comes.

## Operating Context

- Used mostly on phones, before the summit (browsing, registering, onboarding) and heavily on summit day (schedule, rooms, check-in, announcements).
- Accounts use passwordless email OTP or native Google sign-in. The backend is Supabase, and a Google Sheet allowlist gates the volunteer and admin roles.
- The app runs on sample data when no backend config is present.

## Capabilities and Constraints

- Ships to **both iOS and Android with one shared design** (Flutter, Material 3), with only small native touches such as sign-in sheets. The user chose not to adapt the design per OS. `Platform` is recorded as `android` because Material is the shared design language; iPhone is an equal shipping target (TestFlight).
- Has light and dark themes plus a Light / Dark / System choice saved per device.
- Five tabs: Home, Schedule, Discover, News, Archie. Profile opens from the Home avatar.
- The in-app flow for expert feedback on student projects is not built yet; certificate / feedback PDFs are on the roadmap. Future work must not present this as already available.
- OS push notifications are not built yet.

## Brand Commitments

- **Logo:** the Emerald Summit dragon roundel (`assets/branding/logo.png`, source `logo_source.png`).
- **Palette:** emerald green is primary, in both themes. The logo's navy is a small accent only, never the dominant color. Silver supports.

## Evidence on Hand

- Event photos used in the Home slideshow, plus brand assets in `assets/branding/` (logo, Archie mascot art).
- The live session catalog (disciplines and sessions) in Supabase.
- No testimonials, attendance figures, sponsor names, or press are on hand. Future work must not invent them.

## Product Principles

1. **Students first.** When attendee and organizer needs conflict on a shared screen, the student's path wins. Organizer tools stay out of the student's way.
2. **Always know what's next.** On summit day, finding your next session and its room should never take more than a glance.
3. **Real participation, not a brochure.** Lead with what students can do (participate, build, get expert feedback), not with information about the event.
4. **Student-made, community-local.** It should feel like it came from Emerald High students for the Tri-Valley, not from a generic event-app template.
