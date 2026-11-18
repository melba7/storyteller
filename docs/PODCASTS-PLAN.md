# Podcasts plan

Status: approved by Mo on 2026-11-16 with the suggested answers below, except
that the hosts' own plugs are skipped too, under a separate switch (question 5).
On 2026-11-17 Mo asked for Pocket Casts' look and features as well (see
"Matching Pocket Casts"). The milestones are P1a to P5o in `docs/PLAN.md`.

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
  used only as a reference for what the features do and, since 2026-11-17 (Mo's
  ask), for how the screens are laid out. No code, name, logo, icons or artwork
  are copied from it.
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

- **Library** (`podcasts.db`, a separate SQLite file): shows (with their
  categories from P1d), episodes, played and position, and a small cache for
  Apple's charts. The books database and upstream's migrations are not touched.
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

### Following Apple Podcasts (Mo's choice, 2026-11-16)

iOS does not let other apps see Apple Podcasts' library, and Apple Podcasts has
no export. Two ways in, both one way (nothing is written back to Apple
Podcasts):

- **Share links** (P2d): a link copied from Apple Podcasts goes into Add;
  Apple's free lookup turns its id into the feed.
- **The Mac** (P2e): with library sync on, Apple Podcasts on the Mac has the
  same shows. An hourly job reads a copy of its library file and writes the
  followed shows and finished episodes to `Podcasts/apple-podcasts.json` in the
  iCloud folder the phone already links for the sounds. The phone adds new shows
  and marks finished episodes as played. It only adds: an unfollowed show stays,
  and a show unsubscribed in Storyteller is not added again.

### Explore and search (Mo's ask, 2026-11-16)

Mo chose to build these right after playback, as P1d (Discover, first called
Explore) and P1e, after the Pocket Casts layout (P1c). Everything uses Apple's
free, keyless addresses; nothing is paid.

- **Top charts**: Apple's US top chart, overall and for each of Apple's main
  categories, fetched when Explore opens and kept for a day. Chart entries carry
  Apple ids, so one lookup call turns them into feed links.
- **For you**: Apple has no public "shows like this" list, so suggestions go by
  category. The categories come from the feeds of the shows you follow (the
  `itunes:category` tag), so shows added by link count too. The most common
  categories come first, shows you already follow are left out, and each
  suggestion names the show of yours it comes from.
- **Preview**: a show from Explore or search opens a preview read from its feed
  without saving it, with Follow and Play.
- **Episode search**: in your shows, on the phone, by words in titles and notes;
  across all podcasts, through Apple's episode search.
- The cloud can't reach Apple's chart addresses, so the tests use saved answers,
  and the first build checks them on the phone.

## Matching Pocket Casts (Mo's ask, 2026-11-17)

Mo asked for the Podcasts section to have Pocket Casts' look and its features.
Pocket Casts is still only a reference: the features are rebuilt in this app's
React Native screens and Swift module, and nothing is copied (see "Pocket Casts
licence"). The checks below come from Pocket Casts' App Store page and its
support pages (November 2026).

### The look

- A bottom tab bar inside the Podcasts section: Podcasts and Discover, then
  Profile (P2a), Up Next (P2b) and Playlists (P5d), each when it has something
  in it. The mini player sits above the tabs. expo-router's native tabs (in the
  app already) give iOS 26's glass tab bar; if they can't sit inside the
  section, the bar is drawn in React. The side menu button stays, to get back to
  Books.
- Podcasts: a grid of artwork with a badge for unplayed episodes (large grid,
  small grid or list), sortable, with drag to reorder.
- A show's page: a large header, then episode rows with a play button that shows
  progress. An episode opens as a card.
- The player: large artwork on a background tinted from the artwork, the seek
  bar, big skip and play buttons, and a row of small buttons for speed and,
  later, the sleep timer, star, share and more. Show notes, chapters, bookmarks
  and the transcript sit under or beside it.
- Own icons (lucide, already in the app), colours and theme names. Pocket Casts'
  name, logo, icons and artwork are not used.

### Features

| Pocket Casts feature                                                               | Where                                              | Size      |
| ---------------------------------------------------------------------------------- | -------------------------------------------------- | --------- |
| Follow by search, link, Apple link, OPML                                           | P1a, P2d, P5m                                      | done or S |
| Discover: charts, categories, suggestions                                          | P1d (Apple's charts)                               | M         |
| Search shows and episodes                                                          | P1a, P1e                                           | S         |
| Player: speed 0.5x-3x, skip 10/45 s, lock screen, mini player                      | P1b                                                | M         |
| The Pocket Casts layout (tabs, grid, show page, episode card)                      | P1c, P1c2, P1c3                                    | M         |
| Downloads, storage, Wi-Fi only                                                     | P2a                                                | M         |
| Up Next (tab, swipe actions, reorder, clear)                                       | P2b                                                | M         |
| New episodes and auto-download                                                     | P2c                                                | M         |
| Transcripts                                                                        | P3a (made on the phone), P3c (shown in the player) | M         |
| Per-show settings: skip intro and outro, speed, auto-download, auto-add to Up Next | P5a                                                | S         |
| Archive, auto archive, episode limit, sort, group by season                        | P5b                                                | S         |
| Star, mark played, listening history, multi-select                                 | P5c                                                | M         |
| Smart playlists (formerly filters) and playlists                                   | P5d, P5e                                           | M, S      |
| Sleep timer                                                                        | P5f                                                | S         |
| Chapters (feed, M4A, MP3), chapter artwork, skip a chapter                         | P5g                                                | M to L    |
| Bookmarks                                                                          | P5h                                                | S to M    |
| Skip amounts, headphone actions, smart resume                                      | P5i                                                | S         |
| Volume boost and trim silence                                                      | P5j                                                | L         |
| Listening stats and time saved                                                     | P5k                                                | S to M    |
| Themes: Light, Dark, Extra Dark and colour themes                                  | P5l                                                | M         |
| Share shows, episodes and the place playing                                        | P5m                                                | S         |
| AirPlay, new-episode notifications                                                 | P5n                                                | S         |
| Your own audio files                                                               | P5o                                                | M         |
| Ad skipping (not in Pocket Casts)                                                  | P3a-P4c                                            | L         |

Why the big ones are big:

- **Volume boost and trim silence** were planned as a second player built on
  Apple's audio engine. They were built on the one player instead (2026-11-17),
  so ad skipping, the sleep timer and Up Next keep working: an audio tap makes
  voices louder, and the player jumps over silent gaps it measured once in the
  downloaded file. Trimming works on downloads; streams get the boost when the
  tap attaches, and otherwise keep speed only.
- **Chapters in MP3 files** are stored in ID3 tags that Apple's frameworks don't
  read, so PodcastKit gets its own small reader (tested on Linux).

### Left out for now, and why

- **Sync with other devices and the web**: Pocket Casts keeps this on its own
  servers and accounts. Here everything stays on the phone (the Mac sync in P2e
  is one way, from Apple Podcasts).
- **Pocket Casts' own Discover lists, networks, curated lists, Clips, What's New
  and the yearly review**: these are Pocket Casts' own content and service.
  Discover uses Apple's free charts instead.
- **CarPlay**: needs a CarPlay permission (entitlement) that Apple grants on
  request, and the app must stay free of entitlements for the unsigned
  TestFlight build. Possible later, with a change to how builds are signed.
- **Apple Watch, widgets, Live Activities and Siri Shortcuts**: each needs an
  extra app target or extension, with its own build and signing setup. Big lifts
  for later.
- **Chromecast and Sonos**: need Google's or Sonos's SDK (new native packages)
  and the local network permission. AirPlay (P5n) covers Apple TVs and AirPlay
  speakers.
- **Video podcasts**: need a video view and picture in picture. Later.
- **iPad layout and app icons**: Mo uses an iPhone, and the fork has no icon of
  its own yet.
- **Plus and Patron**: there are no subscriptions here; every feature is free.

### Order

P1 (play, the layout, Discover, search) comes first, then downloads and Up Next
(P2), which ad skipping needs. Ad skipping (P3-P4) comes next, then the Pocket
Casts features (P5): Mo's choice, 2026-11-17.

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
  of line ranges, each with the advertiser's name and its kind: an ad (a sponsor
  read or a promo for another show) or the hosts' own plug (Patreon, merch,
  their other shows). Line numbers map back to word times, so the model never
  has to copy timestamps.
- **Clean-up** (pure Swift, tested on Linux): join answers from overlapping
  pieces, merge sure ads of one kind that have less than 4 seconds of speech
  between them (12 seconds when every line between reads as the ad; one ad
  break, at most 5 minutes in all), drop anything under 10 seconds, do not skip
  anything over 5 minutes (likely a mistake), carry a sure ad's end on by at
  most 2 lines while the next lines still read as the ad (a web address, a promo
  code, or its sponsor's name), stop at words that bring the show back ("we're
  back"), and land each edge a quarter second before the next word (an ad that
  begins in the first 6 seconds begins at 0:00). The carried end comes from
  MinusPod (see "Open-source code we use"), shortened in the ad-accuracy round
  (docs/PODCASTS-ADS-ACCURACY-PLAN.md).
- **How sure**: the model says how sure it is. Sure and unsure ads are both
  skipped, and "Ads found" marks the unsure ones "Not sure"; guesses are
  dropped.
- **Unsure ads are skipped too, with Undo** (Mo, 2026-11-18, after build 29.1
  marked an ad only as unsure). Undo on the "Skipped ad" note plays it, and an
  undone ad is not skipped again.
- **Two switches**: "Skip ads" and "Skip the hosts' own plugs", both on by
  default (Mo, 2026-11-16), in Settings and per show.

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
- **Streamed episodes** that play through the app's own download are checked
  while they play: the first minutes are read from the stream's own bytes (quick
  text rules at 15 s, the model at 30 s and later), and a skip lands where that
  stream's ad ends. A plain web-address stream (no download) plays without ad
  skipping, and is never swapped for a download, because its ads can differ from
  any download's.

## Pocket Casts licence

Pocket Casts iOS is under the Mozilla Public License 2.0, which applies file by
file: a copied file, and changes to it, must stay under MPL 2.0 with its notice,
and its source must stay available. The rest of the app could stay MIT. The plan
avoids this entirely by reimplementing the features and copying nothing. If a
file is ever copied, it stays a separate file with its MPL header and is listed
in `FORK.md`. The screens follow Pocket Casts' layout (Mo's ask), but its name,
logo, icons, artwork and theme names are not used.

## Open-source code we use (Mo's ask, 2026-11-17)

Checked for licences that fit this MIT app and TestFlight. Code is copied in
(vendored) with its licence notice and listed in `FORK.md`, instead of adding
packages, so upstream's `package.json` and `yarn.lock` stay untouched.

| What                                                                      | Licence    | Used in | What it saves                                                                                                        |
| ------------------------------------------------------------------------- | ---------- | ------- | -------------------------------------------------------------------------------------------------------------------- |
| [MinusPod](https://github.com/ttlequals0/MinusPod)                        | MIT        | P4a-P4c | Tried rules for ad finding: windows with overlap, joining an ad break, carrying the end on, how sure to be to skip   |
| [Podly](https://github.com/jdrbc/podly_pure_podcasts)                     | MIT        | P4a     | A second reference for transcript-then-model ad finding (its prompts, read before writing ours)                      |
| [Transcriptator](https://github.com/stevencrader/transcriptator)          | MIT        | P3c     | Readers for SRT, WebVTT, HTML and JSON podcast transcripts, with speakers; copied in if it needs no other packages   |
| [OutcastID3](https://github.com/CrunchyBagel/OutcastID3)                  | MIT        | P5g     | Chapter tags (CHAP, CTOC) in MP3 files; M4A chapters come from Apple's own AVFoundation                              |
| [swift-audio-marker](https://github.com/atelier-socle/swift-audio-marker) | Apache 2.0 | P5g     | The alternative for chapters: MP3, M4A and Podcasting 2.0 JSON chapters with artwork, but iOS 17+ and no Linux tests |

Already covered, so nothing is added: feeds (PodcastKit's own reader is built),
background downloads (URLSession), swipe rows and dragging
(`react-native-gesture-handler` and `react-native-reanimated` are in the app),
and transcription (Apple's `SpeechTranscriber`, free; WhisperKit, MIT, stays in
"Later" in case it disappoints). Pocket Casts (MPL 2.0) and AntennaPod (GPL 3)
stay references only. No open database of podcast ad times was found.

As built (2026-11-17): MinusPod's rules and part of MinusPod's and Podly's
wording are used (credited in `FORK.md`), and only Transcriptator's time reading
was adapted. OutcastID3 could not be fetched, so the MP3 chapter reader was
written from the ID3 spec in PodcastKit `PodcastChapters`.

## Chart sources checked (2026-11-18)

The cloud container can't reach Apple's or Spotify's hosts, so
`tools/fork/probe-podcast-sources.mjs` checks them from a GitHub runner
(workflow "Podcast sources probe", run on a `claude/**` push that changes the
script). Its second run, on 2026-11-18, found:

1. **Cover sizes: yes.** Rewriting a chart cover's last segment from
   `100x100bb.png` to `640x640bb.jpg` or `1280x1280bb.jpg` returns a real JPEG
   at that size (36 KB and 100 KB).
2. **Top episodes: yes, through the show.**
   `.../podcasts/top/50/podcast-episodes.json` answers with 50 entries (the
   singular `podcast-episode.json` is a 404). A lookup of the episode ids gives
   nothing, but each entry's link carries its show's id, and a lookup of the
   show ids gives the feed link. So a row opens its show, and the episode is
   found in the feed by its title.
3. **Spotify: no.** `top` and `top_episodes` answered "no healthy upstream"
   (503) or "Internal Server Error" (500), plain or browser-like, in both runs;
   `trending` answered only some of the time. Spotify is left out of this round.
4. **Overall chart with 100 entries and the genre tree: yes.**

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
| Apple changes its private library file, or macOS stops the Mac job reading it              | The job reads a copy, checks the columns it needs and says plainly what changed; share links keep working meanwhile. macOS asks Mo once to allow the read.                                                                         |
| Apple changes or retires its free chart addresses                                          | Explore says plainly that a chart couldn't be loaded; search, links and the library keep working. The addresses live in one file.                                                                                                  |
| Private feed links hold a password                                                         | Stored only on the phone, never logged.                                                                                                                                                                                            |

## How each milestone is checked

| Milestone                     | In the cloud (`check.sh`)                              | Fork CI (macOS)            | Mo's Mac                                                                 | Only on Mo's phone                              |
| ----------------------------- | ------------------------------------------------------ | -------------------------- | ------------------------------------------------------------------------ | ----------------------------------------------- |
| P1a Subscribe                 | Feed parser (Swift, Linux), library logic (JS)         | iOS build                  |                                                                          | Side menu, search, a real feed's episodes       |
| P1b Play                      | Player rules (Swift), player state (JS)                | iOS build                  |                                                                          | Lock screen, speed, hand-over with a book       |
| P1c to P1c3 Layout            | Grid sorting, badges, row states                       | iOS build                  |                                                                          | Tabs, grid, show page, episode card             |
| P1d Discover                  | Feed categories, charts, lookup, For you, cache        | iOS build                  |                                                                          | Charts load, suggestions, follow from a preview |
| P1e Search episodes           | Search words and order, Apple's episode answer         | iOS build                  |                                                                          | Find by a word in notes, play a found episode   |
| P2a Downloads                 | Download bookkeeping, file identity                    | iOS build                  |                                                                          | Download with the app closed, play offline      |
| P2b Up Next                   | Queue rules                                            | iOS build                  |                                                                          | Next episode starts with the screen locked      |
| P2c New episodes              | Refresh and clean-up rules                             | iOS build                  |                                                                          | New episodes appear and download by themselves  |
| P2d Share links               | Reading Apple links and the lookup                     | iOS build                  |                                                                          | A link from Apple Podcasts adds the show        |
| P2e Mac sync                  | Library file reader (Python), what the phone adds (JS) | iOS build                  | Job writes the file from the real library                                | A followed show appears within the hour         |
| P3a Transcribe                | Transcript format and storage                          | Builds the Apple-only code | `.command` transcribes an episode                                        | Speed, battery, the first model download        |
| P3b In the background         | Resume rules                                           | iOS build                  |                                                                          | Transcribed after the app was closed            |
| P3c Moving transcript         | Transcript readers, the line playing at a time         | iOS build                  |                                                                          | Follows the audio, tap a line to play there     |
| P4a Ad finder                 | Chunker, clean-up, saving, with a fake detector        | Builds the Apple-only code | `.command` finds ads in an episode (needs Apple Intelligence on the Mac) |                                                 |
| P4b Ads on the phone          | Status rules                                           | iOS build                  |                                                                          | Ads found on the iPhone's model, time taken     |
| P4c Skipping                  | Skip rules (seek into an ad, Undo, speed)              | iOS build                  |                                                                          | Skip, note and Undo while listening, locked too |
| P5a-P5o Pocket Casts features | Each step's rules                                      | iOS build                  |                                                                          | The feature named in the step                   |

The Mac commands are double-clickable `.command` files, because the Mac's auto
mode refuses `swift run`.

## Questions for Mo (answered 2026-11-16: the answers in bold, except 5)

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
5. **What counts as an ad?** Sponsor reads and promos for other shows are
   skipped. Mo's answer: the hosts' own plugs (Patreon, merch, their other
   shows) are skipped too, under their own switch, separate from ads. Unsure ads
   are skipped too, with Undo (Mo, 2026-11-18).

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
- Suggestions ranked by how alike the shows' descriptions are (on-device model),
  and charts for other countries. (Searching the spoken words is P6a.)
- Import subscriptions from another app (OPML), a sleep timer, chapters,
  CarPlay. Sending what you play in Storyteller back to Apple Podcasts is not
  possible (no API).
- Open on Podcasts when that was the last section used.
