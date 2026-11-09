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
- `applications/mobile/fork.config.ts`: the fork's app name and bundle ID.
- Planned: `libraries/LofiScoreKit/` (the Swift music engine),
  `applications/mobile/modules/lofi-score/` (its Expo module),
  `applications/mobile/lofi/` (the React Native UI) and `tools/lofi-library/`
  (music library scripts).

Touch points are the only edits to upstream files. Each one carries `LOFI-FORK`
markers, and `tools/fork/touchpoints.json` lists them with their marker counts:

- `applications/mobile/app.config.ts` (3 markers): passes upstream's config
  through `withForkIdentity` from `fork.config.ts`, so the fork installs beside
  the official app.

Wiring in the music adds four more, each a line or two: making the narrator's
play, track and sleep-timer observers public in
`modules/readium/ios/AudiobookPlayerActor.swift`, one import in
`store/store.ts`, a toolbar button in `components/Toolbar.tsx` and a settings
link in `app/(root)/settings.tsx` (all under `applications/mobile/`).

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

- **Fork checks** (Ubuntu, under a minute): `tools/fork/check-fork.mjs`.
- **Mobile typecheck, tests and format** (Ubuntu): `yarn install`, a typecheck
  of the mobile app and the packages it uses, upstream's mobile tests, and the
  formatting of the fork's own files.
- **iOS simulator build** (macOS): `expo prebuild` with the fork's identity and
  an unsigned simulator build with `xcodebuild`, to catch native breakage. It
  also runs `swift test` for `libraries/LofiScoreKit` once that exists. Before
  `pod install` it fetches Sentry's prebuilt framework with retries
  (`tools/fork/prefetch-sentry-xcframework.rb`), because `pod install` tries
  that GitHub download only once. On pull requests it only runs when the mobile
  app, the root package files or this workflow change.

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
arrives like an app update and keeps working for 90 days. Until the secrets
below exist, the workflow only reports which ones are missing.

One-time setup, with a paid Apple Developer Program membership:

1. On developer.apple.com, under Certificates, Identifiers & Profiles →
   Identifiers, register an App ID with the explicit bundle ID from
   `applications/mobile/fork.config.ts` (`io.github.melba7.storytellerlofi`).
2. In App Store Connect → Apps, add a new iOS app with that bundle ID. Any name
   and SKU will do.
3. In App Store Connect → Users and Access → Integrations → App Store Connect
   API, create a team key with the Admin role, which Xcode needs to manage
   signing in the cloud. Download the `.p8` file (it can only be downloaded
   once) and note the key ID and the issuer ID.
4. In this repository's Settings → Secrets and variables → Actions, add the
   repository secrets `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8` (the whole
   text of the `.p8` file) and `APPLE_TEAM_ID` (from Membership details on
   developer.apple.com).
5. Run the TestFlight workflow from the Actions tab. When App Store Connect has
   processed the build, add yourself as an internal tester under TestFlight and
   accept the invitation on the iPhone.

The workflow signs with Apple-managed certificates through the API key, so no
certificates or profiles are stored in this public repository. Each run uses its
run number as the build number.

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
