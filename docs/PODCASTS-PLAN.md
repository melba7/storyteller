# Podcasts plan

Status: plan only, waiting for Mo's OK. Nothing is built yet. The milestones are
P1a to P4c in `docs/PLAN.md`.

## Goal

Mo asked (2026-11-16) for a Podcasts section next to Books, with its own
library, episode list and player, and with ads skipped automatically. Finding
the ads happens on the phone (iPhone 15 Pro, iOS 26 or later):

1. When an episode downloads, Apple's speech recogniser (SpeechAnalyzer with
   SpeechTranscriber) writes it out with the time of each word.
2. Apple's on-device model (Foundation Models, 4,096 tokens at a time) reads the
   transcript in overlapping pieces and says where the ads start and end.
3. The ads are saved for that exact downloaded file, because ads inserted by the
   podcast's host change from one download to the next.
4. The player skips each ad by itself, shows a short "Skipped ad" note and
   offers Undo.

The ad finder sits behind a swappable interface so Apple's cloud model or Claude
Haiku can be tried and compared later. The base version uses no paid service,
and the app keeps reaching TestFlight the way it does now.

## What the code check found

- **Storyteller's app is React Native** (Expo, TypeScript) in
  `applications/mobile`, with Swift where iOS needs it: upstream's audiobook
  player (`modules/readium`), the fork's sounds module (`modules/lofi-score`)
  and the Swift package `libraries/LofiScoreKit`.
- **Pocket Casts iOS is a native Swift app**, so the two cannot be merged. It is
  used only as a reference for what the features do (subscriptions, downloads,
  Up Next, speed, the player). No code, artwork, names or screen designs are
  copied from it.
- **There is no left menu on the iPhone today.** The Books screen has a top bar
  with the logo, the search field and a "⋯" menu (Import book, Settings). The
  plan adds a menu button at the top left that opens a side menu with Books and
  Podcasts (question 1 below).
- **The book player owns the lock screen.** Upstream's `AudiobookPlayerActor`
  registers the lock-screen and headphone buttons once when the app starts. Its
  Play button would start the book even while a podcast plays, so it needs one
  small registered change (a touch point) to stand aside while a podcast plays.
- **No new Apple permissions (entitlements) are needed.** Background downloads,
  background tasks, the speech recogniser and the on-device model need none.
  This matters because the TestFlight workflow archives the app unsigned, which
  only works while the app has no entitlements.
- **No new JavaScript packages.** The app already has SQLite (op-sqlite) and
  file access. Feeds are read with the XML parser built into Swift, so
  upstream's `package.json` and `yarn.lock` stay untouched.

## How it fits together

The screens and the library are React Native, like the rest of Storyteller.
Everything that must keep working with the screen locked or the app closed is
Swift, because the JavaScript side stops running in the background (the sounds
engine is native for the same reason).

| Piece                                                                | Where                                                 | Language   |
| -------------------------------------------------------------------- | ----------------------------------------------------- | ---------- |
| Side menu, podcast library, show page, episode list, player screen   | `applications/mobile/podcasts/`                       | React (TS) |
| Routes for those screens                                             | `applications/mobile/app/(root)/podcasts/`            | React (TS) |
| Library data: shows, episodes, played state                          | its own SQLite file, `podcasts.db`                    | TS         |
| Player, Up Next, downloads, background tasks, the bridge to the app  | `applications/mobile/modules/podcasts/` (Expo module) | Swift      |
| Feed reading, transcripts, chunking, ad finder interface, skip rules | new Swift package `libraries/PodcastKit`              | Swift      |
| Speech recogniser and on-device model wrappers                       | `PodcastKit` (Apple-only targets)                     | Swift      |

All new folders are fork-owned (added to `forkPaths` in
`tools/fork/touchpoints.json`). The upstream files that change are only these
touch points:

- `app/(root)/index.tsx` (new): the menu button on the Books screen.
- `modules/readium/ios/AudiobookPlayerActor.swift` (already a touch point): the
  book's lock-screen handlers do nothing while a podcast is the active player.

`PodcastKit` is a separate package from `LofiScoreKit`, built the same way (a
podspec per target, listed in `fork.config.ts`). Its pure logic is tested on
Linux in `check.sh` (Docker `swift:6.2`) and on macOS in Fork CI. Fork CI's and
`testflight.yml`'s path lists gain `libraries/PodcastKit/**`, so a change there
also starts the iOS build and TestFlight.

### Data and files

- **Library** (`podcasts.db`, a separate SQLite file): shows, episodes, played
  and position. The books database and upstream's migrations are not touched.
- **Downloads**: `Application Support/Podcasts/<episode>/<sha256>.<ext>`. The
  SHA-256 of the downloaded bytes is the file's identity.
- **Transcript**: `<sha256>.transcript.json` next to the file: lines of words,
  each word with its start and end time, plus the locale and recogniser version.
- **Ads**: `<sha256>.ads.<detector>.json`: the ad ranges in seconds, the
  detector's name and version, the iOS version, and which ads the listener
  undid. One file per detector, so two detectors can be compared on the same
  file.
- Deleting a download deletes its transcript and ads too. A new download of the
  same episode is a new file with a new hash, so it is transcribed and checked
  again.

### From subscribing to skipping

1. **Subscribe**: search Apple's free podcast directory by name or paste an RSS
   link. The Swift side fetches and reads the feed; the library stores it.
2. **Download**: a background download (it carries on with the app closed).
3. **Transcribe**: `SpeechTranscriber` with time ranges on, in the feed's
   language. iOS downloads the speech model once, the first time.
4. **Find ads**: the transcript is split into pieces, each piece goes to the ad
   finder, and the answers are joined and cleaned up.
5. **Play**: the player loads the ads for that file and skips them.

Each episode row shows where it is: Downloading, Transcribing 40%, Finding ads,
"3 ads found", or why not ("Apple Intelligence is off").

## Finding ads

### The interface

```swift
protocol AdDetector: Sendable {
  var id: String { get }            // "apple-on-device"
  var version: String { get }       // prompt version, model and OS version
  var tokenBudget: Int { get }      // transcript tokens per request
  func findAds(in piece: TranscriptPiece) async throws -> [AdRange]
}
```

The chunker cuts pieces to the detector's own budget, so a model with a big
window (Apple's cloud model, Claude) gets fewer, larger pieces with no change
elsewhere. The base version ships one detector, `apple-on-device`. A hidden
setting picks the detector, and each result is saved under the detector's id.

### The on-device detector

- **Window**: 4,096 tokens for the instructions, the transcript piece and the
  answer together. The plan keeps about 2,500 tokens for transcript, which is
  about 10 minutes of speech. Pieces overlap by 2 minutes so an ad that crosses
  a cut is seen whole at least once. An hour-long episode takes about 7
  requests. On iOS 26.4 and later the app measures each piece with Apple's
  `tokenCount(for:)` and the model's `contextSize` instead of guessing; a piece
  that is still too long is split in two.
- **Prompt shape**: the piece is sent as numbered lines (about one sentence
  each). The model answers in a fixed shape (Apple's guided generation): a list
  of line ranges, each with the advertiser's name. Line numbers map back to word
  times, so the model never has to copy timestamps.
- **Clean-up** (pure Swift, tested on Linux): join answers from overlapping
  pieces, merge ads less than 5 seconds apart, drop anything under 10 seconds,
  do not skip anything over 5 minutes (likely a mistake), and move each edge to
  the nearest pause between words.
- **When unsure, do not skip.** A missed ad costs a tap on "skip 30 s"; a wrong
  skip loses part of the show.

### Comparing detectors later

Undo records that a skip was wrong in the ads file, and each episode has an "Ads
found" list (time, length, first words, advertiser) with a play button, so Mo
can check a few by ear. A later Mac command can run two detectors on the same
transcripts and compare them with those marks. Apple's cloud model and Claude
Haiku are in "Later" below; neither is built in the base version.

## Playing with books and sounds

- **One thing plays at a time.** Starting a podcast pauses the book (the
  ambience follows the narration, so it stops too). Starting a book pauses the
  podcast; the podcast module watches the book's play state through the existing
  `LofiNarratorBridge.lofiObserve`.
- **Lock screen**: the podcast player sets the Now Playing card and handles the
  buttons while it is the active player. The book's handlers stand aside (the
  touch point above) until the book plays again.
- **Audio session**: both use `.playback` with spoken audio, so nothing changes
  for the book, the sounds or calls. Each player handles its own interruptions.
- **Skipping with the screen locked**: the Swift player sets a time marker at
  each ad's start and jumps to its end, so skipping does not depend on
  JavaScript running. The "Skipped ad" note with Undo shows in the app for 6
  seconds; on the lock screen the skip just happens.
- **Up Next** lives in Swift for the same reason: when an episode ends with the
  screen locked, the next one starts without the app open.
- **Streamed episodes play without ad skipping**, because a streamed copy can
  carry different ads than any download.

## Pocket Casts licence

Pocket Casts iOS is under the Mozilla Public License 2.0, which applies file by
file: a copied file, and changes to it, must stay under MPL 2.0 with its notice,
and its source must stay available. The rest of the app could stay MIT. The plan
avoids this entirely by reimplementing the features and copying nothing. If a
file is ever copied, it stays a separate file with its MPL header and is listed
in `FORK.md`. The Pocket Casts name, icons and look are not used.

## Risks

| Risk                                                                                       | What the plan does                                                                                                                                                                                                                 |
| ------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Apple Intelligence is off, its model is still downloading, or the language isn't supported | The detector reports the reason; the episode plays without skipping and its row says why. Settings > Podcasts shows the model's state.                                                                                             |
| The small on-device model misses ads or marks the show as an ad                            | Skip only clear ads; the clean-up rules; Undo; an "Ads found" list per episode; a per-show off switch. P4c's done-when sets the bar.                                                                                               |
| A piece is too long for 4,096 tokens                                                       | Budgeted pieces, measured with `tokenCount(for:)` on iOS 26.4+, split and retried when too long.                                                                                                                                   |
| Apple's safety rules refuse some pieces (crime or war podcasts)                            | That piece is marked "not checked" and nothing in it is skipped. iOS 26.4 made these rules less strict.                                                                                                                            |
| The on-device model changes with iOS updates (26.4 and 27 both did)                        | Each result records the model and iOS version; the prompt is rechecked on the Mac after a major update.                                                                                                                            |
| Apple slows the on-device model in the background on battery                               | Ads are found while the app is open, while it plays audio, or in a background task that waits for the charger. A freshly downloaded episode can start before its ads are found; skipping starts as soon as they are.               |
| iOS limits work with the app closed                                                        | Downloads use a background download session. Transcription runs while the app is open or playing, and otherwise in a background processing task (iOS picks the time, often overnight on the charger). It resumes where it stopped. |
| Word times are only roughly per word                                                       | Ads need about one second of precision; edges snap to pauses.                                                                                                                                                                      |
| Two players and one lock screen                                                            | One player at a time; the touch point; tests for the hand-over both ways on the phone.                                                                                                                                             |
| Storage: about 30 to 100 MB per hour of audio                                              | Delete played downloads (setting), auto-download only the newest episodes, show storage used. Transcripts are under 1 MB. iOS keeps the speech and Apple Intelligence models in system storage.                                    |
| Battery and heat while transcribing                                                        | One episode at a time, preferring the charger; P3a measures the time per hour of audio on the phone.                                                                                                                               |
| TestFlight stops working                                                                   | No entitlements; the new Swift folder is added to the workflow's paths; Fork CI builds the app on every PR.                                                                                                                        |
| Upstream updates conflict                                                                  | New folders are fork-owned; only two touch points; `check-fork.mjs` enforces it.                                                                                                                                                   |
| Private feed links hold a password                                                         | Stored only on the phone, never logged.                                                                                                                                                                                            |

## How each milestone is checked

| Milestone             | In the cloud (`check.sh`)                       | Fork CI (macOS)            | Mo's Mac                                                                 | Only on Mo's phone                              |
| --------------------- | ----------------------------------------------- | -------------------------- | ------------------------------------------------------------------------ | ----------------------------------------------- |
| P1a Subscribe         | Feed parser (Swift, Linux), library logic (JS)  | iOS build                  |                                                                          | Side menu, search, a real feed's episodes       |
| P1b Play              | Player rules (Swift), player state (JS)         | iOS build                  |                                                                          | Lock screen, speed, hand-over with a book       |
| P2a Downloads         | Download bookkeeping, file identity             | iOS build                  |                                                                          | Download with the app closed, play offline      |
| P2b Up Next           | Queue rules                                     | iOS build                  |                                                                          | Next episode starts with the screen locked      |
| P2c New episodes      | Refresh and clean-up rules                      | iOS build                  |                                                                          | New episodes appear and download by themselves  |
| P3a Transcribe        | Transcript format and storage                   | Builds the Apple-only code | `.command` transcribes an episode                                        | Speed, battery, the first model download        |
| P3b In the background | Resume rules                                    | iOS build                  |                                                                          | Transcribed after the app was closed            |
| P4a Ad finder         | Chunker, clean-up, saving, with a fake detector | Builds the Apple-only code | `.command` finds ads in an episode (needs Apple Intelligence on the Mac) |                                                 |
| P4b Ads on the phone  | Status rules                                    | iOS build                  |                                                                          | Ads found on the iPhone's model, time taken     |
| P4c Skipping          | Skip rules (seek into an ad, Undo, speed)       | iOS build                  |                                                                          | Skip, note and Undo while listening, locked too |

The Mac commands are double-clickable `.command` files, because the Mac's auto
mode refuses `swift run`.

## Questions for Mo (suggested answers in bold)

1. **Where does the switch to Podcasts go?** **A menu button at the top left of
   the Books screen opens a side menu with Books and Podcasts.** (Bottom tabs
   would mean reshaping upstream's screens, which makes upstream updates
   harder.)
2. **When should this start?** **Now, alongside the sound work: the sound
   milestones left are waiting on your tests or on cost decisions.** After your
   OK, "next" takes P1a.
3. **How do you find shows?** **Search Apple's free podcast directory by name,
   or paste an RSS link.** Importing your current app's subscriptions (an OPML
   file) goes under Later unless you want it now.
4. **New episodes**: **each show can download its newest episode by itself (on
   by default), and played downloads are deleted after a day**, so ads are found
   before you listen and storage stays small.
5. **What counts as an ad?** **Sponsor reads and promos for other shows are
   skipped; the hosts' own plugs (Patreon, merch, their other shows) are not.**
   When the model is unsure, it does not skip.

Assumed: the podcasts are in English (other languages the recogniser and model
support can follow), and Apple Intelligence is on on the phone.

## Later

- Try Apple's cloud model (Private Cloud Compute, iOS 27). It is reported to be
  free for small developers, but it needs a managed entitlement from Apple,
  which means signing the archive and changing the TestFlight workflow first.
- Try Claude Haiku (a paid API, so Mo's OK first; the key stays on the phone and
  out of git). iOS 27's Foundation Models can also wrap other providers' models
  behind the same session API.
- A Mac command that compares two detectors on the same transcripts.
- Import subscriptions from another app (OPML), a sleep timer, chapters,
  CarPlay.
- Open on Podcasts when that was the last section used.
