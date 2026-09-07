---
name: update-readme
description: >-
  Keep README.md as the living source of truth for everything understood about
  the Emerald Summit app. Use this whenever you learn something significant
  about the app — a new or changed feature, an architecture or backend
  decision, a data model / Supabase schema, a naming or workflow convention, a
  roadmap change, or any fact the user tells you to "keep in mind," "remember,"
  or "track." Invoke it when the user says /update-readme, "update the readme,"
  "add this to the readme," or "note this down," AND proactively — on your own,
  without being asked — the moment you realize you've learned something about
  the app that a future contributor would need in the README. Bias toward
  running it: a README that drifts out of date is worse than one updated a
  little too often.
---

# Update README

The README is the one place a new teammate (or a future session with no memory
of this conversation) should be able to read to understand what the Emerald
Summit app *is*, what's built, how it's put together, and what's planned. Your
job with this skill is to keep it accurate and current as understanding grows.

## When something is "significant" enough to record

Record it if a contributor arriving tomorrow would be wrong or slowed down
without it. Concretely:

- **Features** — a screen/flow added, removed, or meaningfully changed; a rule
  the app enforces (e.g. schedule conflict detection, capacity caps).
- **Behavior the spec implies** — e.g. "each announcement also fires a push
  notification." These are easy to forget because they aren't visible in the
  current UI yet.
- **Architecture & backend** — the chosen stack, what's wired vs. mocked,
  Supabase tables/columns, RLS policies, auth approach.
- **Conventions** — how secrets are handled, build/run flags, bundle IDs,
  naming schemes, anything a contributor must follow to not break things.
- **Roadmap changes** — something moved from planned to built, or a plan
  changed.

Skip the transient and the trivial: a one-off debugging step, a temporary
workaround you already reverted, exact line numbers, or anything already
obvious from the code itself.

## How to update — surgically, not by rewriting

1. **Read the current README first.** Understand its existing structure and
   tone before touching anything. Match them.
2. **Find the right home.** Put the fact in the section it belongs to (Status,
   feature list, architecture, configuration, roadmap, etc.). If no section
   fits and the fact is important, add a small new section rather than wedging
   it somewhere wrong.
3. **Edit in place; don't duplicate.** If a related statement already exists,
   revise it rather than appending a second version. Contradictions are worse
   than gaps.
4. **Keep planned vs. built honest.** Only describe something as implemented if
   it actually is. If a feature is designed but not built (e.g. push
   notifications, PDF generation), record it under the roadmap / "not yet
   built" area, or clearly mark it as planned — never imply it works when it
   doesn't. This truthfulness is the whole point; a README that overclaims is
   actively harmful.
5. **When a roadmap item ships, move it.** Delete it from the "planned" list
   and describe it in the relevant built section, so the two never disagree.
6. **Stay concise.** The README is a map, not the territory. Prefer a tight
   sentence over a paragraph. Don't paste code or duplicate what the code says
   clearly on its own.

## After updating

Tell the user in one or two lines what you changed and where, so they can see
the README stayed in sync. If you updated it proactively (without being asked),
say so explicitly — e.g. "I also noted X in the README's roadmap section," so
the update is never silent.

## Commit and push to GitHub

Whenever this skill runs and the README actually changed, commit and push it to
GitHub as the final step — don't leave the update sitting in the working tree.
This repo pushes straight to `main` (solo repo, no PRs).

1. Stage **only** the README (and any other files this skill legitimately
   touched) — never blanket `git add -A`, which could sweep up unrelated work in
   progress. Verify with `git status` / `git diff --staged` first.
2. Commit with a short, specific message describing the doc change, e.g.
   `Update README: document Android INTERNET permission fix`. End the message
   with the required co-author trailer:

   ```
   Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
   ```
3. `git push origin main`.
4. Report the result — the commit hash and that it pushed — in the same summary.
   If the push fails (auth, non-fast-forward, offline), say so plainly and leave
   the commit in place rather than force-pushing or discarding it.

If the README ended up unchanged (nothing significant to record), skip the
commit entirely — don't create empty commits.

## Relationship to memory

Persistent cross-session memory files may also hold project facts. The README
is the *public, in-repo* source of truth a contributor reads; memory is your
private working context. When a fact belongs in both, keep them consistent, but
the README is what ships with the code — prioritize getting it right.
