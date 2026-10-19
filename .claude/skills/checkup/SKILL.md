---
name: checkup
description: >-
  Change-aware improvement pass over the Emerald Summit Flutter app. Tracks
  every file it has checked (by content hash), measures what changed since,
  uses the graphify code graph to find what those changes affect, then routes
  the work to the installed tools: agent-skills (review, tests, security,
  simplification), Context7 (current package docs), avoid-ai-writing (no
  AI-sounding text anywhere in the app), impeccable and taste-skill (UI),
  update-readme. Fixes what is safe, asks about larger changes once at the end,
  verifies with flutter analyze + flutter test, and commits. Use when the user
  says /checkup, "run a checkup", "tune up the app", "improve my code", "check
  what I changed", or "clean things up since last time".
argument-hint: "[light|standard|deep|all] [focus area or path]"
user-invocable: true
---

# /checkup

One command that looks at **what changed since files were last checked** and
**which files have never been checked**, then runs the tools that fit, at a
depth matching the size of the change.

Helper scripts (run from the repo root):

```bash
python3 .claude/skills/checkup/scripts/checkup.py scan [tier|all]   # the plan for this run → JSON
python3 .claude/skills/checkup/scripts/checkup.py impact FILE...    # who depends on these files (graphify)
python3 .claude/skills/checkup/scripts/checkup.py mark --note "…" FILE...   # record FILE... as checked
python3 .claude/skills/checkup/scripts/checkup.py coverage          # checked / changed / never-checked, per file
python3 .claude/skills/checkup/scripts/checkup.py declined add "…" | list
node .claude/skills/checkup/scripts/copy_scan.js FILE_OR_DIR...     # AI-writing scan of user-facing strings
```

## How files are tracked

`state.json` (gitignored) records a content hash for every file a checkup has
reviewed. It covers `lib/`, `test/`, `supabase/*.sql` and `supabase/functions/`. Each tracked file is:

- **current**: checked, unchanged since.
- **changed**: checked before, edited since. Always reviewed next run.
- **never**: no checkup has read it yet.

Every run reviews all *changed* files plus a slice of *never* files, picked
most-connected first using graphify. The slice size depends on the tier, so
coverage grows until the whole app is current. `/checkup all` reviews every
file that isn't current in one run. Only files actually reviewed are passed to
`mark`; a file that was skipped stays "never".

## Arguments

- `light` / `standard` / `deep` / `all` override the computed tier.
- Any other text is a focus (e.g. `auth`, `lib/screens/schedule_screen.dart`):
  review just that, plus its graphify dependents.

## Step 1: Measure

1. `checkup.py scan`. The fields that matter: `tier`, `reason`, `review_files`
   (= `changed_files` + `never_checked_slice`), `areas`,
   `lib_changed_without_test_change`, `packages_used_in_review_files`,
   `dirty_worktree`, `coverage`, `declined`.
2. Tell the user in two lines: the tier and why, what will be reviewed, and
   coverage so far (`n/117 files current`).
3. **Tier `none`** (nothing changed, every file current): run the Step 3
   baseline and stop.

| Tier | When | Never-checked files added |
|---|---|---|
| `light` | ≤ 5 changed files and ≤ 150 lines | 3 |
| `standard` | ≤ 25 files and ≤ 1000 lines | 6 |
| `deep` | more than that, ≥ 30 days since the last run, or first run | 12 |
| `coverage` | no code changes, but files still never checked | 8 |
| `all` | only when asked | every file not current |

## Step 2: Map the blast radius (graphify)

The code graph rebuilds in about 3 seconds, with **no LLM and no cost**.

1. `graphify update .` (scoped by `.graphifyignore`). If it refuses because
   the graph shrank (code was deleted on purpose), rerun with `--force`. If
   graphify is missing, skip this step.
2. `checkup.py impact <changed_files>`. Dependents of changed files get a
   lighter read: check they still match what changed (renamed fields, changed
   signatures, new required params). They are **not** marked as checked unless
   they were fully reviewed.
3. On `deep`/`all`, read `graphify-out/GRAPH_REPORT.md` → *God Nodes*,
   *Import Cycles*, *Surprising Connections*. Skip god nodes named `_` and
   nodes that come from Markdown docs; both are extraction noise.
4. Mid-checkup "what calls X / how does Y work" → `graphify explain "<path>"`
   or `graphify path "A" "B"` instead of grepping.

Never run the full `/graphify` pipeline here. It's for exploring the architecture,
not for checkups.

## Step 3: Baseline

```bash
flutter analyze
flutter test
```

Record both results before changing anything. As of 2026-10-17: analyze clean,
228 tests passing in about 9 s. Failures here are pre-existing: report them,
and fix them first if they're in the review files.

## Step 4: Route the work

Run the rows whose signal fires, in this order. Fixes per run: light ≤ 5,
standard ≤ 10, deep ≤ 15, all = no cap. AI-writing fixes don't count toward
the cap.

| Signal | Tool | What to do |
|---|---|---|
| always | `agent-skills:code-review-and-quality` | Review `review_files` (diff since `base_sha` for changed files, whole file for never-checked ones). Correctness first. |
| always | **avoid-ai-writing** (see Step 4a) | No AI-sounding text anywhere in the app. |
| `lib_changed_without_test_change`, or logic changed in backend/models | `agent-skills:test-driven-development` | Focused tests in `test/` using the sample backend, like the existing tests. |
| `packages_used_in_review_files` non-empty, or `deps` area | **Context7** + `agent-skills:source-driven-development` | Version from `pubspec.lock` → `resolve-library-id` → `query-docs` for the APIs the code calls. Fix deprecated/wrong usage. Watch `supabase_flutter`, `google_sign_in` (v7 API changed a lot), `mobile_scanner`, `file_picker`, `image_picker`. |
| `auth`, `backend`, `sql`, `edge_functions` | `agent-skills:security-and-hardening` | RLS in the SQL, auth/session handling, input validation, no secrets in code, edge functions. With the Supabase CLI linked, compare against the live dev schema (Step 4b). |
| `ui` area or UI file in the slice | **impeccable** (`Skill impeccable`, args `audit <files>`) + `taste-skill:redesign-existing-projects` checklist | impeccable is the main UI audit (Flutter-aware). From taste-skill, use only the *Content*, *Interactivity and States*, and *Strategic Omissions* checklists; skip its CSS/Tailwind/GSAP advice, this is Flutter. Fix a11y, contrast, overflow, missing loading/empty/error states. |
| long or tangled files | `agent-skills:code-simplification` | Within review files only; no behavior change. |
| `deep` / `all` | GRAPH_REPORT + `agent-skills:performance-optimization` | God nodes, import cycles, the largest screens. Flutter hot spots: rebuild-heavy `setState` near the root, non-builder lists, uncached network images, undisposed realtime subscriptions. |
| `deep` / `all` | agents `agent-skills:code-reviewer`, `agent-skills:security-auditor`, `agent-skills:test-engineer` | Dispatch all three in one message as read-only reviewers of `review_files`. Merge their findings, then apply them yourself. |
| features / schema / conventions changed | `update-readme` (project skill) | Last, after fixes land. |

### Step 4a: No AI writing, anywhere

The rule: nothing a user reads in the app may sound machine-written. That
covers every string on screen (buttons, titles, empty states, errors, snackbars,
dialogs, onboarding), sample/seed data in `lib/data/` and `supabase/seed_*.sql`,
notification text in SQL triggers, and **Archie's replies**.

1. `node .claude/skills/checkup/scripts/copy_scan.js <review_files that are .dart>`.
   This runs the avoid-ai-writing plugin's detector on user-facing string
   literals and flags **every** em dash.
2. Then invoke `avoid-ai-writing:avoid-ai-writing` and read the user-facing
   strings in the review files against its rules (references/patterns.md),
   because the regex can't judge tone. Typical catches in app copy: chirpy
   filler ("You're all set!", "Oops!"), exclamation marks on success messages,
   "seamless/effortless/unlock/elevate", Title Case Headings, "Let's…",
   rule-of-three padding, and sentences explaining what the UI already shows.
3. Rewrite in plain, specific, short English. Keep the meaning, keep proper
   names. "Robot Showcase" is an event name, not a tell. Replace em dashes with
   a period, comma, colon, or parentheses. If a test asserts the old copy,
   update the test.
4. **Archie:** whenever `supabase/functions/archie-chat/index.ts` is reviewed
   (and on every `deep`/`all` run), check that its system prompt contains
   plain-writing rules: no em dashes, no AI vocabulary or filler, no "Great
   question", no closing offers, sentence case, short direct answers. Add them
   if they're missing. Keep the prompt byte-stable apart from that change, since
   it's cached. Redeploying Archie is the user's call: tell them the command
   (`supabase functions deploy archie-chat --no-verify-jwt`), don't run it.
5. The same rule applies to what the checkup itself writes: commit messages,
   code comments, README edits, and the final report.

### Step 4b: Supabase (read-only)

If `supabase` is on PATH and the repo is linked (`supabase/.temp/project-ref`
exists), you may use **read-only** inspection to check the SQL files against
what's actually live on dev, e.g. `supabase db dump --linked --schema-only` or
`supabase inspect db …`. If a command needs Docker or a password you don't
have, skip it and say so. **Never** `db push`, `db reset`, `migration up`,
`functions deploy`, `secrets set`, or anything else that writes to a project.

### How to call each tool

- **agent-skills**: Skill tool, `agent-skills:<name>`. If it isn't listed,
  Read `~/.claude/plugins/marketplaces/addy-agent-skills/skills/<name>/SKILL.md`
  and follow it. Skip web-only parts (Core Web Vitals, DevTools, DOM).
- **Context7**: ToolSearch `context7` → `resolve-library-id`, `query-docs`.
  If they're unavailable (needs sign-in via `/mcp`), fall back to WebFetch on
  `https://pub.dev/packages/<pkg>/changelog` and
  `https://pub.dev/documentation/<pkg>/latest/`, and say which source you used.
- **avoid-ai-writing**, **taste-skill**: Skill tool
  (`avoid-ai-writing:avoid-ai-writing`, `taste-skill:redesign-existing-projects`, also listed as `taste-skill:redesign-skill`).
- **impeccable**, **update-readme**: project skills.

## Step 5: Fix policy

**Fix directly:** analyzer issues; bugs with a concrete failing scenario;
missing tests for changed behavior; package API misuse confirmed by docs;
AI-sounding copy; a11y/contrast/overflow; dead code; simplifications that
don't change behavior.

**Ask first** (Step 7). Don't do these on your own:
- anything that changes product behavior, flows, or features
- package upgrades
- refactors that cross several files, especially god nodes (`models.dart`,
  `app_state.dart`, `repositories.dart`)
- UI redesigns beyond fixing what's broken
- new SQL (schema, RLS, triggers)

Skip anything listed in `declined`.

**Never:**
- Run SQL or write anything to Supabase.
- Touch `env.json`, the version/build number, or signing.
- Weaken a check to get green: no `// ignore:`, no skipped or deleted tests, no
  loosened assertions.
- Mix the user's uncommitted work into checkup commits.

## Step 6: Verify

After each group of fixes, run `flutter analyze` and `flutter test`. The result
must be **no worse than the baseline**. If a fix breaks something and can't be
resolved quickly, revert it and mention it in the report. Don't launch the app
to verify; builds need `--dart-define-from-file=env.json` (live Supabase).

## Step 7: Ask about the larger changes

Once the safe fixes are verified, gather every "ask first" item and ask
**once**, with AskUserQuestion (up to 4 questions per call, one item each; call
again if there are more). For each one, give the file, the problem, the
proposed change, and the risk. Options: *Do it now* / *Not now* / *Never*
(→ `checkup.py declined add "…"`, so it isn't asked again). Do the approved
ones in this run, then repeat Step 6 for them.

## Step 8: Commit, record, report

1. **If `dirty_worktree` was true at the start:** leave all checkup edits
   uncommitted and say so. **Otherwise:** one local commit per theme
   (`Checkup: fix …`, `Checkup: plain-English copy in …`, `Checkup: tests for
   …`). Plain commit messages, no AI-isms. Don't push; offer to (this repo
   pushes straight to `main`).
2. `graphify update .` so the graph matches the new HEAD, then
   `python3 .claude/skills/checkup/scripts/graph3d.py` to rebuild the 3D map
   (`graphify-out/graph3d.html`).
3. `checkup.py mark --note "<tier>: <n> fixes" <every file fully reviewed this run>`.
4. Report, in plain English:
   - tier and why; coverage before → after (`23 → 38 of 117 files current`)
   - tools that ran, and any skipped (not installed or not signed in)
   - fixes, grouped, with `file:line` links
   - before/after: analyze issues, test count
   - what was approved or declined in Step 7
   - anything the user must do: SQL to run on dev, Archie redeploy, push
