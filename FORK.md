# Storyteller Lofi

This is a personal fork of
[Storyteller](https://gitlab.com/storyteller-platform/storyteller). It adds lofi
background music that follows the mood of what has already been narrated, and it
keeps taking upstream's mobile releases through small, reviewed merges.

Upstream code stays as upstream wrote it. The fork's own code lives in new
folders, and the few edits to upstream files are marked `LOFI-FORK` so that
every sync keeps them.

## Ground rules

- **Nothing goes upstream from here.** Storyteller's
  [contributing guidelines](CONTRIBUTING.md) ask for merge requests whose code
  the author can explain without an LLM, and for no LLM-written text in
  conversations with maintainers. Never open a merge request, issue or comment
  upstream with code or text from this fork's automation or from an AI
  assistant. If a change here deserves to go upstream, the fork's owner writes
  it and proposes it in their own words.
- **Pull requests stay in this fork.** GitHub suggests the original repository
  as the base of a pull request from a fork. Check that the base is this fork's
  `main`, and pass `--repo` to `gh pr create` (`tools/fork/setup-clone.sh` makes
  this fork the default for `gh`).
- **No music in git.** This repository is public and the music is for personal
  listening. Keep tracks in git-ignored folders; CI fails if the fork commits an
  audio file.
- **Keep the license.** Storyteller is MIT licensed, Copyright (c) 2023 Shane
  Friedman. `LICENSE` stays as it is.

## What the fork changes

Files and folders that belong to the fork, which upstream never touches:

- `FORK.md`: this file.
- `.github/workflows/`: fork CI and the upstream sync.
- `tools/fork/`: the fork checks and the sync scripts.
- `applications/mobile/fork.config.ts`: the fork's app name and bundle ID, and
  the pods for the music engine.
- `libraries/LofiScoreKit/`: the Swift music engine. Next to its
  `Package.swift`, one podspec per target lets CocoaPods build it from source
  for the app.
- `applications/mobile/modules/lofi-score/`: its Expo module (iOS only), with
  the JavaScript binding and its tests.
- `applications/mobile/modules/readium/ios/LofiNarratorBridge.swift`: hooks on
  upstream's audiobook player. It is a new file inside upstream's Readium
  module, because the player's observers and `Track` are internal to it. It adds
  observers and reads state, and holds the narration for a moment when the
  atmosphere swells at a big scene change (see the touch point below). It also
  looks up the clip at the top of the page, so the music can follow the pages
  while you read with the narration stopped.
- `applications/mobile/lofi/`: the React Native UI.
- Planned: `tools/lofi-library/` (music library scripts).

Touch points are the only edits to upstream files. Each one carries `LOFI-FORK`
markers, and `tools/fork/touchpoints.json` lists them with their marker counts:

- `applications/mobile/app.config.ts` (3 markers): passes upstream's config
  through `withForkIdentity` from `fork.config.ts`, so the fork installs beside
  the official app.
- `applications/mobile/components/Toolbar.tsx` (2 markers): the music button in
  the player's toolbar for readaloud books, in the read-along and listening
  screens. It opens a panel with on and off, the music's volume and the car
  setting.
- `applications/mobile/app/(root)/settings.tsx` (2 markers): the music's section
  in Settings, which also imports a music folder.
- `applications/mobile/store/store.ts` (1 marker): imports
  `lofi/readerFollow.ts` for its listeners. With the narration stopped, it finds
  the clip at the top of each page you turn to, the same way the app keeps the
  audio in step with the page, and hands it to the music, which judges the mood
  from there and never from further down the page.
- `applications/mobile/modules/readium/ios/AudiobookPlayerActor.swift` (8
  markers): the narration hold. When the atmosphere swells at a big scene
  change, the bridge stops the narrator at the end of the sentence for under a
  second (0.8 s by default, switchable in Settings) and then carries on. These
  one-line hooks keep that invisible: `getIsPlaying()` and the remote play and
  toggle commands count a hold as playing, the play state observer ignores it,
  pause and the sleep timer end it and report the pause, and play ends it early
  without the automatic rewind. The real code, and an access extension at the
  end of the file for the player's private state, live in the bridge.

The Expo module needs no touch point: it starts with the app and follows the
narrator through `LofiNarratorBridge.swift`.

To add a touch point, keep the edit to a line or two and put the real code in a
fork-owned folder. Mark each changed line or block with a `LOFI-FORK` comment,
and register the file in `touchpoints.json` and in the list above in the same
commit.

`node tools/fork/check-fork.mjs` enforces all of this. It fails when a marker
disappears, when an unregistered file carries a marker, when the fork commits an
audio file, and when the fork changes an upstream file that isn't a registered
touch point. Add `--list` to see every file the fork changes compared with the
upstream release it is based on.

## Fork identity

`applications/mobile/fork.config.ts` gives the app:

- the name "Storyteller Lofi", or "Storyteller Lofi (dev)" for development
  builds;
- its own bundle ID, with `.dev` appended for development builds;
- no EAS account or project, because upstream's belong to upstream.

Change these in `fork.config.ts`, not in `app.config.ts`. The URL scheme stays
`storyteller`, because Storyteller servers send the login callback to
`storyteller://settings`. iOS returns that callback to the app that started the
login, so sharing the scheme with the official app is fine. The icon is still
upstream's; give the fork its own before sharing the app with anyone.

## Remotes and branches

- `origin` is this fork on GitHub.
- `upstream` is https://gitlab.com/storyteller-platform/storyteller.git, the
  canonical repository. The GitHub repository this fork was made from is a
  read-only mirror of it.
- `main` is the newest upstream mobile release the fork has merged, plus the
  fork's own commits.
- `sync/mobile-vX.Y.Z` branches hold upstream releases waiting for review.
- `feat/*` branches hold fork work in progress.

After cloning, run `tools/fork/setup-clone.sh` once. It adds the `upstream`
remote without upstream's thousand-plus tags, fetches upstream's `main` and this
fork's tags, turns on `git rerere` so resolved conflicts are remembered, and
points `gh` at this fork.

`main` follows upstream releases (the `mobile-v*` tags), not upstream's `main`
branch, so the fork only moves to versions upstream actually shipped. The fork
doesn't need to carry upstream's tags: `node tools/fork/upstream-base.mjs` names
the newest release `main` contains by reading upstream's tags directly, and
`node tools/fork/check-fork.mjs --list` lists every file the fork changes since
then.

Don't press GitHub's **Sync fork** button: it merges upstream's unreleased
`main` instead of a release.

## Upstream updates

`.github/workflows/upstream-sync.yml` runs every day at 06:17 UTC, and on demand
from the Actions tab. When upstream has published a stable `mobile-vX.Y.Z` tag
newer than the one `main` contains, it:

1. branches `sync/mobile-vX.Y.Z` from `main` and merges the tag;
2. if only `yarn.lock` conflicts, takes upstream's lockfile and reruns
   `yarn install` to add the fork's dependencies back;
3. pushes the branch and the tag, opens a pull request with upstream's release
   notes, and starts fork CI on it;
4. if anything else conflicts, opens an issue that lists the files and the
   commands to finish the merge by hand.

The workflow only reads from upstream. It rewrites upstream's release notes so
that no one upstream is mentioned or linked back from this fork.

To review a sync pull request:

- Wait for fork CI to pass. The fork check fails if the merge dropped a hook.
- Skim upstream's changes to the touch-point files.
- Merge with **Create a merge commit**. Never squash or rebase a sync pull
  request: `main` has to contain upstream's own commits, or the next sync and
  the fork check lose track of what was merged.

To finish a conflicted sync by hand:

```sh
git fetch origin
tools/fork/sync-upstream.sh --tag mobile-vX.Y.Z   # stops at the conflicts
# resolve the conflicts, keeping every LOFI-FORK hook, then:
git add -A && git commit --no-edit
node tools/fork/check-fork.mjs
git push -u origin sync/mobile-vX.Y.Z
gh pr create --repo OWNER/REPO --base main --head sync/mobile-vX.Y.Z
```

For a `yarn.lock` conflict, take upstream's file
(`git checkout --theirs yarn.lock`), run `yarn install`, and commit the result.
`tools/fork/sync-upstream.sh --dry-run` reports whether the newest release would
merge cleanly without changing anything.

## CI

`.github/workflows/fork-ci.yml` runs on every pull request, on pushes to `main`,
and when the upstream sync starts it:

- **Fork checks** (Ubuntu, under a minute): `tools/fork/check-fork.mjs`, and the
  tests of the fork's tools (`node --test 'tools/fork/*.test.mjs'`).
- **Mobile typecheck, tests and format** (Ubuntu): `yarn install`, a typecheck
  of the mobile app and the packages it uses, upstream's mobile tests, and the
  formatting of the fork's own files.
- **iOS simulator build** (macOS): `expo prebuild` with the fork's identity and
  an unsigned simulator build with `xcodebuild`, to catch native breakage. It
  also runs `swift test` for `libraries/LofiScoreKit` once that exists. Before
  `pod install` it fetches Sentry's prebuilt framework with retries
  (`tools/fork/prefetch-sentry-xcframework.rb`), because `pod install` tries
  that GitHub download only once. On pull requests it only runs when the mobile
  app, the root package files or this workflow change. It runs on GitHub's
  Apple-silicon Macs (`macos-26`). When those are too busy, the job is cancelled
  after 15 minutes with "The job was not acquired by Runner"; run Fork CI by
  hand on the same branch from the Actions tab and pick `macos-15-intel` under
  "macOS runner". Intel Macs are slower, and GitHub is phasing them out, so keep
  `macos-26` as the default.

## One-time GitHub settings

- **Actions**: enable workflows for this fork on the Actions tab if GitHub asks.
- **Issues**: forks start with Issues turned off. Turn them on under Settings →
  General → Features, so the sync can report conflicts.
- **Pull requests from Actions**: under Settings → Actions → General → Workflow
  permissions, tick "Allow GitHub Actions to create and approve pull requests".
  Without it, the sync opens an issue with a link to create the pull request
  instead.
- **Optional `SYNC_TOKEN` secret**: a fine-grained personal access token for
  this repository with read and write access to contents, issues, pull requests
  and workflows. With it, sync pull requests start CI like any other pull
  request, and pushes that GitHub refuses from the workflow token go through.

## Building on an iPhone

There are three ways to run the app. TestFlight is the one that needs no
Developer Mode on the phone.

### TestFlight

`.github/workflows/testflight.yml` builds an App Store build of `main` after
every change to the app, and on demand from the Actions tab, and uploads it to
TestFlight. Install the TestFlight app on the iPhone once; each new build then
arrives like an app update and keeps working for 90 days. It needs no Developer
Mode, no registered device and no certificates: the archive is built unsigned,
and Xcode signs it during the upload with a distribution certificate that Apple
keeps (cloud signing), using an App Store Connect API key.

Until the secrets below exist, a push only reports which ones are missing, and a
run started by hand from the Actions tab builds the App Store archive without
signing or uploading it, which shows the build itself works.

One-time setup, with a paid Apple Developer Program membership:

1. On developer.apple.com → Account → Certificates, IDs & Profiles →
   Identifiers, click +, choose App IDs, then App. Enter the description
   `Storyteller Lofi` and the explicit bundle ID from
   `applications/mobile/fork.config.ts` (`io.github.melba7.storytellerlofi`).
   Tick no capabilities, then Continue and Register.
2. In App Store Connect → Apps, click + → New App. Tick iOS, pick that bundle
   ID, and give it any name nobody else on the App Store uses (it is never
   published, so `Storyteller Lofi` plus your initials is fine) and any SKU,
   such as `storytellerlofi`.
3. In App Store Connect → Users and Access → Integrations → App Store Connect
   API, request access if asked, then add a team key with Admin access. Admin is
   what cloud signing needs. Download the `.p8` file (Apple offers it only once)
   and note the key ID and the issuer ID shown above the key list.
4. In this repository's Settings → Secrets and variables → Actions, add four
   repository secrets: `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8` (the whole
   text of the `.p8` file) and `APPLE_TEAM_ID` (the Team ID under Membership
   details on developer.apple.com).
5. On the Actions tab, run the TestFlight workflow. Its first job checks the
   setup in about a minute and names the fix if a step was missed
   (`tools/fork/asc-preflight.mjs`; it registers the App ID itself if step 1 was
   skipped). The build and upload then take about an hour.
6. In App Store Connect → your app → TestFlight, add an internal testing group
   with yourself in it. Install TestFlight on the iPhone, signed in with your
   Apple Account, and accept the invitation. New builds then show up there by
   themselves.

Each run uses the workflow's run number as the build number, so renaming the
workflow file would restart the numbering and Apple would refuse the uploads.

If the build job is cancelled after 15 minutes with "The job was not acquired by
Runner", GitHub had no Apple-silicon Mac free. Run the workflow by hand and pick
`macos-15-intel` under "macOS runner". That works while the Intel image's Xcode
still meets Apple's minimum SDK for uploads (it has Xcode 26, which Apple will
likely accept until spring 2027).

If the upload step fails:

- "Cloud signing permission error" or a certificate error: the API key does not
  have Admin access. Make a new Admin key and replace the three `ASC_` secrets.
- "No profiles for 'io.github.melba7.storytellerlofi' were found": the App ID or
  the App Store Connect app is missing, or `APPLE_TEAM_ID` names another team.
- An agreement error: accept the pending agreement on developer.apple.com or in
  App Store Connect, then run the workflow again.
- "The app now needs entitlements": something added an entitlement, such as
  iCloud or push notifications. An unsigned archive can't carry it, so the
  archive has to be signed. That needs a development certificate kept in the
  secrets, because letting Xcode create one per run soon hits Apple's limit on
  certificates.

### iOS Simulator

On a Mac with Xcode and its iOS platform, Node 24 (upstream's version; 22.18 or
newer also works), CocoaPods, and Homebrew's `cmake` and `pkg-config`
(upstream's iOS builds install them):

```sh
corepack enable
(cd applications/mobile && ./scripts/pre-install.mjs)
yarn workspaces focus @storyteller-platform/mobile
cd applications/mobile
yarn expo run:ios --configuration Release
```

### Straight from Xcode

Add an Apple ID under Xcode → Settings → Accounts, connect the iPhone by cable,
turn on Developer Mode (Settings → Privacy & Security), and run the commands
above with `--device`. `APP_VARIANT=development` without
`--configuration Release` makes a development build that loads its JavaScript
from the Metro server on the Mac. With a free Apple ID the app stops opening
after 7 days and has to be installed again.
