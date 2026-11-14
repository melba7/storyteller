# CLAUDE.md

Storyteller Lofi is Mo's personal fork of Storyteller. It plays spoiler-safe
scene sounds under audiobook narration on iOS. The scenes are scored ahead of
time by Claude on a Mac.

## Commands

- Setup in the cloud: `corepack enable`, then
  `COREPACK_NPM_REGISTRY=https://registry.npmjs.org yarn install --immutable --mode=skip-build`
- Check everything: `tools/fork/check.sh`. Add `--no-swift` to skip the Swift
  tests (they run in Docker `swift:6.2` when there's no `swift`).
- Swift only: `cd libraries/LofiScoreKit && swift test`
- Mobile tests only: `yarn test:mobile`
- iOS build: Fork CI only (macOS). Push the branch and read its checks.
- Long runs go to GitHub CI from a pushed branch (Mo's choice).

## Conventions

- Fork code lives only in fork-owned paths (`tools/fork/touchpoints.json`
  `forkPaths`). Upstream files change only at the registered `LOFI-FORK` touch
  points. Run `node tools/fork/check-fork.mjs` after touching anything outside
  them.
- Swift: follow the existing LofiScoreKit style and tests (XCTest and
  swift-testing). It must still compile with Swift 6.2 (Xcode 26).
- Docs and comments in plain English sentences.
- Branches: work on `claude/*` branches and open PRs into this fork's `main`
  (never upstream). Merging into main needs Mo's OK. A push to main under
  `applications/mobile` or `libraries/LofiScoreKit` starts a TestFlight build.

## Always / never

- Never commit audio, keys or `.env` files. The repo is public.
- Never open anything upstream (merge requests, issues or comments). See
  `FORK.md`.
- Never reformat upstream code or `libraries/LofiScoreKit/Docs/Atmosphere.md` in
  a feature PR.
- Ask Mo before anything that costs money: Claude scoring or eval runs,
  rescoring a book, or paid services.
- Score only books Mo names, never the whole server library.
- On Mo's Mac, auto mode refuses `swift test`, `swift run` and fetch scripts.
  Leave a double-clickable `.command` instead of bypassing it.

## Docs (read only when needed)

- What we're building: `docs/SPEC.md`
- How it's built, decisions, known problems, glossary: `docs/ARCHITECTURE.md`
- Milestones: `docs/PLAN.md`
- Lessons: `docs/LESSONS.md`
- Fork rules, syncing, TestFlight: `FORK.md`
- Engine details: `libraries/LofiScoreKit/Docs/Atmosphere.md`
- Mac scripts: `libraries/LofiScoreKit/Tools/mac/README.md`

## Fork notes

- Original: https://gitlab.com/storyteller-platform/storyteller (MIT). This fork
  is https://github.com/melba7/storyteller, based on upstream `mobile-v2.12.0`.
- Changed: added atmosphere sounds (LofiScoreKit, Expo module, UI, server
  route), the fork's identity, CI, and the shelved music.
- Touch points: `README.md`, `applications/mobile/app.config.ts`,
  `app/(root)/settings.tsx`, `components/Toolbar.tsx`, `store/store.ts`,
  `modules/readium/ios/AudiobookPlayerActor.swift`.

## WORKFLOW (tech-lead v3)

When I say "next":

1. Open docs/PLAN.md. If there's a Handoff note, resume it; otherwise take the
   next unchecked milestone. Only that one. If it's too big for one session,
   split it in PLAN.md and take the first part.
2. Search first. Read only the files and doc sections it needs.
3. State the plan and your assumptions in 3-5 lines. If it touches 3+ files,
   changes how data is stored, or the request can be read two ways, wait for my
   OK; otherwise go.
4. Build the simplest thing that works. Follow existing patterns. No extra
   features, nothing built "for later". Every changed line must trace to the
   milestone: remove only what your change made unused, and note other problems
   under "Later". Handle errors and bad input where data comes in (user input,
   network, files). Keep files under about 300 lines. Add a dependency only with
   a one-line reason, and check its current docs before using an API you're
   unsure of.
5. Test first: write a test for the milestone's main behavior, see it fail, then
   write the least code that passes. For purely visual changes, check a
   screenshot instead. Run the check command and fix causes, not symptoms. Never
   weaken, skip or delete a test to make it pass. No placeholders, TODOs or fake
   data in work marked done.
6. If it touches data, accounts, payments, or deletes anything: have a subagent
   review the diff against "done when" before committing. Fix correctness issues
   only.
7. Tick it, update the status line, log changed decisions in ARCHITECTURE.md. If
   something went wrong, took two tries, or I corrected you, add a one-line
   lesson to docs/LESSONS.md (or to CLAUDE.md if it applies to every session).
   Commit.
8. Reply in at most 6 lines: what changed in plain English, proof (command +
   last few lines of output), how I try it myself, what's next. Tell me to
   /clear.
9. If 5+ milestones are done since the last cleanup, suggest I say "cleanup".

When I say "next N" (a number): do N milestones in a row, each in a fresh
subagent told to read CLAUDE.md and follow the steps above for one milestone.
Give me one line per milestone. Stop early on a failed check, a question for me,
or anything on the ask-before list. When I say "add: [idea]": ask up to 5
questions with suggested answers (check the code before asking me), update
SPEC.md, add milestones to PLAN.md. Don't build until I say "next". When I say
"bug: [what happened]": search docs/LESSONS.md, reproduce it, write a test that
fails because of it, find the root cause with evidence before changing code (no
guess-fixes), fix it, run the check command, add a lesson, commit. If it needs
more than one session, make it a milestone. When I say "cleanup": read
.claude/skills/cleanup/SKILL.md and follow it. When I say "status": answer in at
most 5 lines from PLAN.md only (done count, next 3 milestones, anything waiting
on me).

Always:

- Never say something is done unless the check command ran and passed in this
  session.
- Same fix failed twice, or the conversation is getting long: write a 3-line
  Handoff note at the top of PLAN.md (where you stopped, next step, open
  question), commit, and tell me to /clear and say "next".
- New idea mid-milestone: park it under "Later" and keep going.
- Ask before anything that's hard to undo or costs money: bulk deletes, changing
  the database structure, force-push or reset, deploying or publishing, paid
  services.
- Never commit secrets. Keys go in .env (gitignored). Never print them.
- In a fork: never reformat or remove original-project code; keep changes
  minimal so upstream updates merge cleanly.
