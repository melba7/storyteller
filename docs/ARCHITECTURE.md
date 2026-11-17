# Architecture (the fork's own part)

How it works today. The deeper details live in
`libraries/LofiScoreKit/Docs/Atmosphere.md`. Fork rules and upstream syncing are
in `FORK.md`.

## Stack

- **App:** upstream's Expo / React Native app (TypeScript) in
  `applications/mobile`, iOS only for the fork. The fork's UI is React; its
  engine is Swift, reached through an Expo module.
- **Engine and tools:** the Swift package `libraries/LofiScoreKit` (Swift 6.2,
  Xcode 26). It also runs on Linux for tests, with Docker image `swift:6.2`.
- **Server:** upstream's Next.js app. The fork adds one route that stores a
  book's score inside its read-aloud EPUB.
- **Mac scripts:** bash and Python in `libraries/LofiScoreKit/Tools/mac` and
  `Tools/atmosphere`. They score books with Claude and fetch recordings.
- **CI:** GitHub Actions. `fork-ci.yml` runs the checks plus an iOS simulator
  build. `testflight.yml` uploads builds. `upstream-sync.yml` merges upstream
  releases.

## Folder map (fork-owned)

| Path                                                                     | What                                                                                                                          |
| ------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------- |
| `libraries/LofiScoreKit/Sources/LofiAtmosphere`                          | Scene model, catalogue, Claude scorer, track builder, director and player                                                     |
| `libraries/LofiScoreKit/Sources/LofiScoreHost`                           | App host: settings, finding a book's track, importing the sounds folder, following the narrator                               |
| `libraries/LofiScoreKit/Sources/LofiAudioCore`                           | Clock, gains, loudness, WAV and other audio basics                                                                            |
| `libraries/LofiScoreKit/Sources/LofiText`                                | Reads EPUB sentences without looking ahead                                                                                    |
| `libraries/LofiScoreKit/Sources/lofi-atmosphere`                         | CLI: track, show, score, synth, library, catalog, eval                                                                        |
| `libraries/LofiScoreKit/Sources/LofiMood`, `LofiEvalCLI`, `LofiTrainCLI` | Mood detection the shelved music used (still built)                                                                           |
| `libraries/LofiScoreKit/Tools/`                                          | Mac scripts, the fetch script, the eval set, data tools                                                                       |
| `applications/mobile/modules/lofi-score/`                                | Expo module (Swift and JS binding)                                                                                            |
| `applications/mobile/lofi/`                                              | React UI: toolbar button, panel, settings, reader follow                                                                      |
| `applications/mobile/modules/readium/ios/LofiNarratorBridge.swift`       | Hooks on upstream's audiobook player                                                                                          |
| `applications/mobile/modules/readium/ios/LofiRemoteHandoff.swift`        | Lets a playing podcast own the lock screen; the book's remote handlers ask it first                                           |
| `libraries/PodcastKit/`                                                  | Swift package for podcasts: feed reader, player rules, downloads, tests, podspecs                                             |
| `applications/mobile/modules/podcasts/`                                  | Expo module that fetches feeds and plays episodes (Swift), plus the library in `podcasts.db`, directory search and rules (JS) |
| `applications/mobile/podcasts/`                                          | React UI: side menu, library grid, discover, show, episode and player screens, mini player                                    |
| `applications/mobile/app/(root)/podcasts/`                               | The routes: a tab bar (Podcasts, Discover, Up Next, Profile), a stack per tab, the player pushed                              |
| `applications/web/src/app/api/v2/books/[bookId]/lofi-score/`             | `GET`/`PUT` the book's score                                                                                                  |
| `tools/fork/`                                                            | Fork checks, sync scripts, `check.sh`                                                                                         |
| `shelved/lofi-music/`                                                    | The shelved music, not built                                                                                                  |

## Data flow

1. **Mac:** `lofi-sync.sh`, run by launchd or `Score atmosphere.command`,
   fetches new read-aloud books, then `lofi-atmosphere track` asks Claude about
   every ~250 words. Each question sees only the text so far.
2. The answers become an **atmosphere track**, wrapped in a **book score**. The
   score is copied to `LofiMusic` and iCloud, and `PUT` into the book on the
   server.
3. `fetch-sounds.sh` and `fetch_ambience.py` fetch recordings for each kind into
   `LofiMusic/Atmosphere`, with `sounds.json` listing loudness, licence and
   rejected files.
4. **Phone:** the app imports the sounds folder. While a book plays,
   `LofiNarratorBridge` reports the position, the host finds the scene, and
   `AmbiencePlayer` crossfades looping slots under the voice.

## Data model

- **Atmosphere track** (`*.atmosphere.json`, format 1): one entry per scored
  sentence, holding the place id, inside or outside, the state, up to five
  sounds with levels, a one-off and a transition. It also stores sentence
  digests so a track only plays with its own book.
- **Book score** (`*.score.json`, or `META-INF/storyteller-lofi/score.json` in
  the EPUB): `{format:1, atmosphere, mood?}`.
- **Catalogue:** 48 families and about 360 kinds in `SoundCatalog.swift` (the
  single source), exported to `Tools/atmosphere/catalog.json`.
- **Sounds folder:** `Atmosphere/<Family>[.<Kind>]/*.m4a`, `sounds.json`
  (including `rejected`), and `OneShots/`.
- **Podcast library** (`podcasts.db`, its own SQLite file next to the books'
  database, schema version 4 in `PRAGMA user_version`): `shows` (id, unique feed
  address, title, author, description, picture, link, language, when it was
  added and last refreshed) and `episodes` (id, show, the feed's guid, title,
  date, length, plain-text notes, audio address, type and size, picture, season,
  number; one row per guid and show). Dates are milliseconds since 1970. A
  refresh adds new episodes and updates changed ones, and never deletes an
  episode that left the feed. Removing a show removes its episodes. Version 2
  (P1b, upgraded in place from version 1 with `ALTER TABLE ADD COLUMN`; the
  steps are in `modules/podcasts/schema.ts`) adds where each episode was left
  (`position_seconds`), whether it was played (`played`), when it was last
  played (`last_played_at`) and the show's artwork colour (`artwork_color`,
  worked out once by the player and used to tint the full-screen player).
  Version 3 (P1c3, same way) adds where the listener put each show in "Your
  order" (`shows.own_position`, null until placed; placed shows come first, the
  rest after them, oldest first). Version 4 (P1d, same way) adds the feed's
  category names (`shows.categories`, a JSON list: each top-level name, then
  "Top › Sub" ones; shows followed before get them at their next refresh) and a
  `cache` table (key, value, saved at) that keeps Apple's chart answers for a
  day. Version 6 (P5a) adds the show settings on `shows` (skip intro and outro,
  speed, download, Up Next, notify, ads, plugs) and version 7 (P5b) adds
  `episodes.archived` and the archive and view columns.

## Decisions log

| Date       | Decision                                                                                                                                   | Why                                                        |
| ---------- | ------------------------------------------------------------------------------------------------------------------------------------------ | ---------------------------------------------------------- |
| 2026-11-09 | Fork code lives in new folders; upstream edits only at marked touch points                                                                 | Upstream syncs stay clean                                  |
| 2026-11-09 | No audio in git; personal (CC BY-NC) and publish (Commons) sound editions                                                                  | The repo is public; licences differ                        |
| 2026-11-10 | Music shelved; ambience is the app's focus                                                                                                 | Mo's direction                                             |
| 2026-11-10 | Scoring with Claude Opus through the plan, spoiler-safe windows                                                                            | Accuracy; no look-ahead                                    |
| 2026-11-11 | Bed at -10 dB under the voice, quiet loops boosted up to maxGain 6                                                                         | Mo couldn't hear the sounds                                |
| 2026-11-11 | Fetch gates on title, loudness range and loudness; poor loops listed as rejected                                                           | Drips and room noise slipped in                            |
| 2026-11-12 | Score only books Mo names (`Books/wanted.txt`), never the whole library                                                                    | Cost; Mo's choice                                          |
| 2026-11-14 | Long runs go to GitHub CI from a pushed branch                                                                                             | Mo's choice                                                |
| 2026-11-14 | `tools/fork/check.sh` is the one check command                                                                                             | One command for every check                                |
| 2026-11-14 | Sound check in the app replaces hunting for spots by hand; spots end before the sentence playing now                                       | Mo's ask; no spoilers                                      |
| 2026-11-14 | Sound check stops are steady scenes (8+ sentences, one main sound and level); results carry what played                                    | Fable review: answers must be traceable to a level         |
| 2026-11-14 | Level fixes from the check are global; per-book narrator loudness is proposed as 2d                                                        | One quiet narrator should not move every book              |
| 2026-11-14 | The sound check tells the follower of each jump; its stops follow what the director plays, not dipped                                      | Second review: a near jump is a rewind otherwise           |
| 2026-11-14 | Scenes failed on the plan's usage limit are retried by later runs (`.retry`)                                                               | A limit left 161 scenes silent                             |
| 2026-11-15 | The sounds import asks iCloud for every file up front and finishes in a BGProcessingTask (`<bundle id>.soundsImport`)                      | Mo's ask: the import took too long with the app open       |
| 2026-11-15 | Level fixes stay global; each book's narrator loudness is measured at scoring and used in place of -16 LUFS (2d)                           | Mo's choice on the review card                             |
| 2026-11-15 | The sound check may use the book's opening (first chapter with sounds, or about 5 minutes, whichever is longer) before the user gets there | Mo's ask: check the levels before hearing most of the book |
| 2026-11-16 | The section switch is a side menu opened from the Books screen's top bar, not bottom tabs                                                  | Tabs would reshape upstream's screens; Mo's choice         |
| 2026-11-16 | Podcasts keep their library in their own SQLite file (`podcasts.db`), not in Storyteller's database or Redux store                         | Upstream's migrations and store stay untouched             |
| 2026-11-16 | Feeds are fetched and read in Swift (Foundation's XML parser), so no JavaScript package is added                                           | `package.json` and `yarn.lock` stay upstream's             |
| 2026-11-16 | PodcastKit is its own Swift package, not a target of LofiScoreKit                                                                          | Podcasts and sounds change separately; its tests run alone |
| 2026-11-16 | Apple Podcasts is followed one way only: share links in Add, and an hourly Mac job that reads a copy of its library file                   | iOS gives other apps no access; Mo's choice                |
| 2026-11-16 | Explore uses Apple's free charts; "For you" goes by the categories in the followed shows' feeds (P1d)                                      | Apple has no public "similar shows" list; Mo's choice      |
| 2026-11-17 | Native tabs in the Podcasts section; the mini player sits in the bar's accessory. Profile joins with P2a                                   | Mo's ask: the Pocket Casts layout, inside Podcasts         |
| 2026-11-17 | An episode opens as a form sheet in the tab's stack, not a full screen; links in notes come from a tested splitter                         | Mo's ask: the episode card; no new package                 |
| 2026-11-17 | The Podcasts section follows Pocket Casts' layout and features, rebuilt here; no code, name, icons or artwork copied                       | Mo's ask                                                   |
| 2026-11-17 | The podcast player is one Swift `AVPlayer`; a playing podcast owns the lock screen through `LofiRemoteHandoff`                             | The book's handlers stay registered and stand aside        |
| 2026-11-17 | Downloads: one background URLSession made at launch; Swift files each download and writes the index first                                  | Finishes with the app closed, even when iOS relaunches it  |
| 2026-11-17 | A swipe-away stops downloads until the app opens; then they resume or start again. Wi-Fi only is native                                    | iOS never relaunches a swiped-away app; no stray data use  |
| 2026-11-17 | Up Next is a queue of the episodes after the current one, kept in Swift and saved to `Podcasts/up-next.json`                               | The next one starts when one ends, screen locked or not    |
| 2026-11-17 | Playing from a list puts the episode that was playing back at the top of Up Next, unless it had finished                                   | Pocket Casts' rule (Mo's ask); nothing is lost             |
| 2026-11-17 | Background refresh runs in JS through `expo-background-task` (defined from `store/store.ts`); no new Swift task                            | Reuses the refresh code; iOS picks when it runs            |
| 2026-11-17 | Automatic downloads are the newest new episode per show and always wait for Wi-Fi, whatever the switch says                                | No surprise data use; a deleted episode is not new again   |
| 2026-11-17 | The Mac writes the Apple Podcasts follow list to a JSON file in the linked sounds folder; the phone reads it                               | One way; a seen list stops an unsubscribed show returning  |
| 2026-11-17 | A transcript is saved per audio file as `<sha256>.transcript.json`, with lines and words, the locale and the recogniser                    | Goes with the download; a new file is transcribed again    |
| 2026-11-17 | Transcribing goes in pieces of 5 minutes; a partial file is saved after each, and a restart begins 2 s before it                           | Overlap words are dropped, so none is doubled              |
| 2026-11-17 | The Speech code (SpeechAnalyzer, iOS 26) is one small target behind `canImport(Speech)`; the rest is tested on Linux                       | Only Fork CI compiles it; tests use a fake recogniser      |
| 2026-11-17 | Transcribing runs while the app is open or a podcast plays, and in a background task `<bundle id>.podcastTranscribe`                       | iOS picks the time; the task resumes from the partial file |
| 2026-11-17 | `podcasts.db` is at schema version 5: each episode keeps one feed transcript (`transcript_url`, `transcript_type`), chosen by type         | JSON, then WebVTT, SRT, HTML; plain text skipped           |
| 2026-11-17 | Transcript readers are written for the fork; only Transcriptator's time reading is adapted (MIT, in `FORK.md`)                             | Its HTML reader needs a package this app lacks             |
| 2026-11-17 | The transcript shown is the feed's when it has one, else the phone's own, else the reason; the feed's file is cached for a week            | Works while streaming; a bad file falls back               |
| 2026-11-17 | `podcasts.db` is at schema version 7: per-show settings are columns on `shows` (v6), archive and the show page's view are columns (v7)     | The view is kept per show in the DB, not AsyncStorage      |
| 2026-11-17 | The Swift player reads `Podcasts/show-settings.json`, written by JS in full at startup and on every change; `showId` rides on queue items  | Intro, outro and speed work with the screen locked         |
| 2026-11-17 | A show's own speed is temporary: the player's chosen speed comes back for a show with none; the outro ends the episode so Up Next goes on  | Listener's speed is not overwritten                        |
| 2026-11-17 | Archiving deletes the download and sets `episodes.archived`; rules run in `runAutomatic` and skip the loaded episode and Up Next           | Pure rules in `archive.ts`; search and badges skip it      |
| 2026-11-17 | Ads are found by a swappable `AdDetector`; the on-device one is Foundation Models (`apple-on-device`, version 1) on 4,096-token pieces     | No paid API; a new version re-checks an episode            |
| 2026-11-17 | Ads are `sure`, `unsure` or `guess`: only sure ones are skipped, unsure ones are listed, guesses are dropped (MinusPod's levels, MIT)      | A wrong skip costs more than a missed ad                   |
| 2026-11-17 | Finding ads runs in its own background task `<bundle id>.podcastAds`, only on the charger; the transcribing task is untouched              | The model is heavy and rate limited in the background      |
| 2026-11-17 | The player skips ads with boundary time observers in Swift; a seek into an ad never skips it, an undone ad is recorded and kept            | Works locked; Undo is never undone again                   |
| 2026-11-17 | "Skip ads" and "Skip the hosts' own plugs" are in `UserDefaults`; a show's own choice (P5a columns, in the mirror) wins over them          | The player reads them with no JavaScript                   |
| 2026-11-17 | The sleep timer is a wall-clock deadline in Swift with an alarm task; the last 10 s fade the volume; "end of episode" stops Up Next        | Works locked; the clock runs while paused                  |
| 2026-11-17 | Playback settings (skips, headphones' next, played early, rewind) are a `UserDefaults` dictionary in Swift; JS only shows and saves them   | The lock screen uses them with no JavaScript               |
| 2026-11-17 | New-episode notifications are local (`UNUserNotificationCenter`), one per show per refresh, from `runAutomatic`; switch in AsyncStorage    | No push service or `expo-notifications` needed             |
| 2026-11-17 | OPML is read and written by a small hand-written reader in `opml.ts`; files go through the document picker and share sheet                 | No new package                                             |
| 2026-11-17 | Voice boost is an `MTAudioProcessingTap` on the one AVPlayer item (pure DSP in `VoiceBoost`), not a second `AVAudioEngine` player          | Ads, sleep timer, Up Next keep working                     |
| 2026-11-17 | Silent gaps are measured once per download (`<sha256>.silence.json`); the player jumps over them with boundary observers in 120 s windows  | An ad skip wins; a seek into a gap plays it                |
| 2026-11-17 | Trimmed seconds are counted divided by the speed in `UserDefaults` (`podcasts.trim.savedSeconds`) for the stats step                       | Counted in Swift, also while locked                        |
| 2026-11-17 | `podcasts.db` is at schema version 9: a show's own voice boost and trim (v8), and each episode's feed chapters address (v9)                | Builders' steps renumbered at merge                        |
| 2026-11-17 | Chapters live in Swift for the loaded episode: feed JSON wins over the file's (ID3 reader of our own, else AVFoundation); JS gets events   | Work locked and with Up Next                               |
| 2026-11-17 | Chapter skips are kept per episode in `UserDefaults` (`podcasts.chapterSkips`) and run on the 0.5 s tick; a seek into one plays it         | Up to 0.5 s heard before the jump                          |
| 2026-11-17 | Listening stats are counted in Swift (`StatsStore`, rules in `ListeningStats`) and saved to `Podcasts/stats.json` every 30 s and on pause  | Counts while locked; 90 days kept                          |
| 2026-11-17 | Time saved by a jump (intro, outro, ad, chapter, silence) is the audio skipped divided by the speed; an undone ad takes its skip back      | One rule for every saving                                  |
| 2026-11-17 | Own audio files are copied, hashed and installed by `DownloadStore.install` as `file-<sha256 prefix>`, in the local show `local-files`     | Transcripts, ads, chapters work unchanged                  |
| 2026-11-17 | The local show's feed address is `local:files`: refresh, OPML, the Apple Podcasts sync and Discover skip it                                | No schema change                                           |
| 2026-11-17 | Stars and history are episode columns (`starred_at`, `history_at`); history is kept apart from `last_played_at`                            | Clearing history leaves auto-delete as is                  |
| 2026-11-17 | Rule playlists filter in SQL for what the database knows and in JS for "downloaded", which lives in Swift                                  | SQL tested on `node:sqlite`                                |
| 2026-11-17 | The three starter playlists are made by schema step 11, once, so deleting one sticks                                                       | No re-creation on launch                                   |
| 2026-11-17 | A playlist with auto-download gets its first 5 episodes once each, on Wi-Fi only; hand-filled playlists never auto-download                | Bounded downloads                                          |
| 2026-11-17 | Hand-filled playlist items keep a snapshot; a library episode is read live and wins over its snapshot                                      | Any episode, followed or not                               |
| 2026-11-17 | Headphone bookmarks wait in a Swift file until the app saves them, then are removed by id; two presses within 5 s count once               | Bookmarks work while locked                                |
| 2026-11-17 | A bookmark belongs to a library episode (foreign key, deleted with it); previews cannot be bookmarked                                      | No orphan bookmarks                                        |
| 2026-11-17 | Podcasts themes are Uniwind extra themes in `podcasts/themes.css`, with one `@import` in `global.css` and `extraThemes` in Metro           | Two small touch points                                     |
| 2026-11-17 | The Podcasts section sits in one `ScopedTheme`; "Like the app" passes the app's own light or dark name                                     | Sheets and mini player follow                              |
| 2026-11-17 | The Discover tab's stack is anchored on `discover` (`unstable_settings.anchor`); a test checks every tab's first screen                    | Shared screens sort first                                  |
| 2026-11-17 | Spoken search matches in PodcastKit `TranscriptSearch`: normalised words, the phrase first, else all words in one line; 3 hits an episode  | Tested on Linux                                            |
| 2026-11-17 | Spoken search reads the finished transcript files on each search, off the main thread, with no index; feed-only transcripts are skipped    | No schema change                                           |
| 2026-11-17 | `podcast:person` (show and episode) and `podcast:funding` (show) are parsed in PodcastKit, at most 20 and 5, links kept only if http(s)    | Safe links from feeds                                      |
| 2026-11-17 | Schema v14 keeps them as JSON text in `shows.people`, `shows.funding` and `episodes.people`; an episode's own people replace the show's    | Podcasting 2.0 spec rule                                   |
| 2026-11-17 | A new episode is one newer than the show's newest stored episode; undated ones and a first refresh add nothing new                         | Feeds that change guids don't flood                        |
| 2026-11-17 | Apple Podcasts finished episodes are marked played once each, remembered in AsyncStorage `podcasts.apple.played`                           | Mark unplayed sticks                                       |
| 2026-11-17 | Refreshes of one show run one at a time; pull-to-refresh downloads, queues and notifies like the automatic run                             | No duplicate inserts                                       |
| 2026-11-17 | The cache table drops rows older than 7 days on each write; a "Not downloaded" playlist can't auto-download                                | Bounded storage and downloads                              |
| 2026-11-17 | An own audio file is never deleted by archive or a download delete; only "Delete file" removes it                                          | It is the only copy                                        |
| 2026-11-17 | The player remembers Up Next items by id and follows one the library lacks; `nativeId` keeps a followed preview's Swift id                 | Up Next never freezes the player                           |
| 2026-11-17 | Marks go through `playerInstance.markPlayed`, so the loaded episode keeps them through the next save; unplayed seeks to 0                  | Marks were undone                                          |
| 2026-11-17 | The player's gradient is built in TypeScript (`artworkTint.ts`): saturation lifted, top darkened to 4.6:1 for white text                   | Swift colour code unchanged                                |
| 2026-11-17 | The player has pages (Now Playing, Notes, Chapters, Transcript) as tabs and a five-slot toolbar with "…"; speed is a sheet                 | Fewer controls, nothing jumps                              |
| 2026-11-17 | The outro start comes only from the loaded item's own length; an app-chosen start is not a listener seek                                   | Episodes ended early                                       |
| 2026-11-17 | Ads that start within 0.5 s of the one before are skipped as one stretch; failed ad scans are retried when the app opens                   | An ad then a plug, rate limits                             |
| 2026-11-17 | Episode, chapter and artwork links on plain http are fetched over https; a finished download refuses to return after a delete              | iOS blocks http outside media                              |
| 2026-11-17 | While a podcast owns the lock screen the book doesn't resume after a call (`LofiRemoteHandoff.podcastIsActive`)                            | The book took over                                         |
| 2026-11-17 | `ScreenBar` draws `Stack.Title` and `Stack.Toolbar`; toolbar items are direct children, so the show page builds them with a function       | iOS draws the header; the toolbar finds items by type      |
| 2026-11-17 | Headers are transparent with a minimal back button and the status bar from the Podcasts theme; non-list states sit in `BelowBar`           | Large titles need a scroll view first                      |
| 2026-11-17 | The tab bar shrinks on scroll; the player is a modal sheet (chevron kept for VoiceOver) with no top safe-area padding                      | Swipe down to close                                        |
| 2026-11-17 | A show's wash is the artwork colour at the strongest alpha from 0.15 to 0.45 that keeps the theme's text at 4.5:1                          | Readable in every theme                                    |
| 2026-11-17 | `ensureArtworkColor` (shared by the player and the show page) measures a show's colour once and saves it                                   | Tinted on the first visit                                  |
| 2026-11-17 | Episode rows have "…" and play only; downloading moved into "…" and the card's action strip, never for previews or own files               | Two controls per row                                       |
| 2026-11-17 | Search is the native `Stack.SearchBar`; a pasted link shows "Follow this link" (`isFollowLink` in `followLinkText.ts`)                     | One search field, system look                              |
| 2026-11-17 | Artwork corners follow its size (`artworkRadius`) with a hairline edge; a caller's `className` still wins                                  | Light artwork keeps an edge                                |
| 2026-11-17 | Hero cards put white text on blurred artwork under 60% black                                                                               | 4.5:1 even on white artwork                                |
| 2026-11-17 | Profile groups are `SettingsGroup` cards; rows split by `border-foreground/10`, controls in cards use `bg-foreground/10`                   | Dark's border equals its card colour                       |
| 2026-11-17 | `rulePills` is the one source of a smart playlist's rule words; `DragList` gets `onDrop` for the drop haptic                               | No second copy of the words                                |
| 2026-11-17 | Apple Podcasts finished episodes come from the play state (0) with a sign of listening; `ZHASBEENPLAYED` is empty in today's library       | Following a show marks its old episodes played             |
| 2026-11-17 | The episode loaded in the player is urgent in the transcript and ad queues; the one at work stops at its next piece (QueueOrder)           | Progress kept in the partial file                          |
| 2026-11-17 | With Skip ads on, a new episode plays through its own download: a `lofistream(s)://` asset fed by `PodcastStreamDownload`                  | Ads are found only in the exact file                       |
| 2026-11-17 | Play-through only off Wi-Fi only or on Wi-Fi; a download not whole when another episode starts is dropped, never resumed                   | A new request may bring other ads                          |
| 2026-11-17 | The loader keeps reading its open staging file after the file is filed, and hands at most 4 MB per turn of its queue                       | A rename keeps the handle; cancels are seen                |
| 2026-11-17 | Ads are asked per piece of the playing episode's transcript, only for pieces ending 20 s before its edge, keyed by lines and text          | Greedy chunks: a prefix gives the same pieces              |
| 2026-11-17 | `.ads.<det>.progress.json` keeps answers by piece key and detector version; `.partial.json` feeds the player; the final file removes both  | The final pass asks only the rest                          |
| 2026-11-17 | A transcript being made shows its saved lines (`getPartialTranscript`); the feed's own transcript still wins                               | Reloads once per five-minute piece                         |
| 2026-11-17 | Podcasts screens return their list first with no wrapping View; bar, status bar and overlays come after it                                 | iOS tracks the first scroll view only                      |
| 2026-11-17 | The selection bar is drawn over the list under the header, with a 48 pt spacer at the top of the list                                      | The list has to stay first                                 |
| 2026-11-17 | Bottom-pinned controls use `pb-safe-offset-3`, never `pb-safe` with another bottom padding                                                 | A later `pb-N` overrides the inset                         |
| 2026-11-17 | App Transport Security sets only `NSAllowsArbitraryLoads`; https is tried first, a download falls back once to the feed's http address     | Apple ignores it next to the media/web/local keys          |
| 2026-11-17 | The downloads list is a shared route (`downloadsHref`); the Library has a Downloaded row and Profile keeps its row                         | Mo could not find Downloads                                |
| 2026-11-17 | Podcasts has Apple Podcasts' tabs (Home, New, Library, Search) over one shared route group; Profile is the modal stack `/podcasts/account` | Mo asked for Apple's look and structure                    |
| 2026-11-17 | Home's Up Next: in progress by last played, then the newest unplayed of each show, at most 20; Top Shows rank by recent plays              | The stats keep no listening time per show                  |
| 2026-11-17 | One cadence rule (`cadence.ts`, the median gap of the six newest dates) for Home's "Updated …" and the show page                           | Both pages said different things                           |
| 2026-11-17 | The episode menu is a pure layout (`episodeMenuModel`) drawn on iOS by an `@expo/ui` SwiftUI Menu with Save and Share on top               | The community menu can't draw that top row                 |
| 2026-11-17 | The episode page is a plain push in the tab stack; View Transcript shows only for the episode loaded in the player                         | A sheet hid the pages pushed from it                       |
| 2026-11-17 | The player sheet takes the artwork's colour (`playerSheet.ts`) with white or black ink; it remembers the last tab for its links            | Light artwork needs black text; a modal names no tab       |
| 2026-11-17 | The volume slider is a second Expo module (`PodcastsVolumeModule`); show tiles zoom into the show page, the mini player doesn't            | One native view per module; the accessory is off-stack     |
| 2026-11-17 | Play-through resumes a dropped connection with Range + If-Range on the redirected address, taking only a 206 at the bytes on disk          | Never join two versions of a file                          |
| 2026-11-17 | Play-through falls back to the plain address before its first byte or without a length; an unfinished entry is dropped at launch           | Playback first; no stale "Stopped" rows                    |
| 2026-11-17 | The Apple follow list is read with a file coordinator on its own queue, again after 20, 30 and 60 s, with its status in Profile            | An iCloud placeholder reads as nothing                     |
| 2026-11-17 | Ads found in a transcript so far count as found for the player, the ads list and the status line until the full pass is done               | Skipping starts while transcribing                         |
| 2026-11-17 | Play-through waits for a missing network (up to 20 waits of 30 s, not counted as resume tries); old task reports are ignored               | A tunnel must not end the episode                          |
| 2026-11-17 | The background session ignores a cancel the app asked for (-999 with no iOS reason); iOS's own cancels are still handled                   | A replaced download read as failed                         |

## Known problems

- `River.RunningTap` still holds a room-noise recording (fs168470) that passes
  the gates. There is no manual reject list.
- Sound levels were set by judgment. Mo hasn't confirmed them on a build since
  11.1.
- Big files: `AmbienceSynth.swift` (~1,260 lines), `AmbiencePlayer.swift`
  (~1,000), `LofiAtmosphereHost.swift` (~960).
- Mood code is still built although the music is shelved.
- The Mac's auto mode refuses `swift test`/`swift run` and scripts on downloaded
  code, so Mo double-clicks `.command` files instead.
- `Docs/Atmosphere.md` isn't formatted with oxfmt. Don't reformat it in a
  feature PR.
- Scoring through the Claude plan shares Mo's 5-hour usage allowance with the
  project's threads, so a daytime run can stall for an hour or more and leave
  scenes to the retry runs.

## Glossary

- **Scene:** where the story is now, with its state and sounds.
- **Place:** a location with an id (`p1`…) that keeps its sounds across visits.
- **Family / kind:** a broad sound (Rain) and a more specific one under it
  (Rain.Drizzle).
- **Bed:** the steady sounds under the voice.
- **One-off:** a single sound on one sentence (a knock).
- **Atmosphere track / book score:** the scorer's output, and the file that
  carries it with the book.
- **Touch point:** a marked edit to an upstream file (`LOFI-FORK`).
- **Sounds folder:** `LofiMusic` on the Mac and in iCloud; the phone imports it.
