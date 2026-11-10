# The shelved lofi music

The fork began as lofi music that followed the mood of what had already been
narrated. On 10 November 2026 the atmosphere sounds became the app's focus and
the music was shelved: every file that was only for the music moved here,
unchanged apart from what "What changed in the kept code" lists, so it can come
back without being written again. Nothing in this folder is built, tested or
shipped. `tools/fork/touchpoints.json` lists `shelved/` as a fork-owned path,
so the `LOFI-FORK` markers in these files are allowed and no audio may be
committed here either.

## What is here

| Folder | What it is |
| --- | --- |
| `LofiScoreKit/Sources/LofiDirector` | Turns noisy mood readings into calm music decisions; the replay runner and synthetic books. |
| `LofiScoreKit/Sources/LofiAudio` | The two-deck player: mixer automation, ducking, bar grid, crossfades, track rotation, `library.json`, per-book themes, the `AVAudioEngine` backend and the fake backend for tests. |
| `LofiScoreKit/Sources/LofiPlaceholders` | The synthesised placeholder tracks and the library importer. |
| `LofiScoreKit/Sources/LofiDemoKit`, `lofi-demo`, `Demo/` | The demo story, scripted mood source and narrator; the SwiftUI demo app for Mac and iPhone. |
| `LofiScoreKit/Sources/lofi-replay`, `lofi-placeholders`, `lofi-render`, `lofi-import` | The music's command-line tools. |
| `LofiScoreKit/Sources/LofiScoreHost`, `Tests/LofiScoreHostTests` | A snapshot of the app host and its tests as they were with the music in: `LofiMusicHost`, `MusicSettings`, `MusicFolderImport` and `MusicFolderSync`, `MoodFeedbackLog` (the wrong-mood button), `NarrationFollower` with its fan-out to the mood tracker, `AtmosphereSupport` with the music yield. A reference for the merge described below, not a drop-in. |
| `LofiScoreKit/Tests/LofiDirectorTests`, `LofiAudioTests`, `LofiPlaceholdersTests`, `LofiDemoKitTests` | The music's tests, with the director's replay fixtures. |
| `LofiScoreKit/LofiDirector.podspec`, `LofiAudio.podspec`, `LofiPlaceholders.podspec` | The CocoaPods specs the app built the music with; they now also depend on `LofiAudioCore`. |
| `LofiScoreKit/Package.swift` | The kit's manifest with the music targets back in (see "Bringing the music back"). |
| `LofiScoreKit/Docs/MusicEngine.md` | How the music engine worked. |
| `LofiScoreKit/Tools/library` | The scripts that built the 90-track, 11-mood placeholder library (analysis, picks, samplers, install). |
| `mobile/lofi` | The app's music panel, settings section, toolbar button, hook and the page-following and book-score helpers as they were. |
| `mobile/modules/lofi-score` | The Expo module as it was: `LofiScoreModule.swift` with the music functions, its podspec, `index.ts`, `status.ts` and the status tests. |

The music itself was never in git. It is still on the Mac in
`~/Storyteller Lofi/LofiMusic` (one folder per mood, `library.json`,
`SOURCES.csv`, `CREDITS.md`, the samplers and `Retired/`), in the iCloud Drive
copy of that folder, and in the project's library folder. The Mac's scoring
pipeline keeps using the `LofiMusic` folder name for the sounds, so nothing
there needs moving.

## What changed in the kept code

- **`LofiAudioCore` is new.** The clock (`LofiClock`), the serial scheduler
  that is also the player's lock (`LofiScheduler`), gain and ramp maths,
  `OutputRoute` and `BackendRestartReason`, `StereoBuffer` with the loudness
  meter, the WAV writer and `SplitMix64` moved out of `LofiAudio` and
  `LofiDirector` into it, because the atmosphere uses them too. Each archived
  module has a `Reexports.swift` with `@_exported import LofiAudioCore`, so its
  files and everything that imports it compile unchanged.
- **`LofiAtmosphere` no longer depends on the music targets.** Its imports are
  `LofiAudioCore` now, and it has its own `AmbienceError` where it used
  `LofiAudioError` (which stays in `LofiAudio` with its `Deck` case). The
  player still reports `.musicYield` when a crowd should push the music out;
  the host ignores it until there is music to yield.
- **The app host is `LofiAtmosphereHost`** (`Sources/LofiScoreHost`), the
  music host without the music: `NarrationFollower` drives one sink (the
  ambience player) instead of fanning out to the mood tracker as well;
  `AtmosphereSettings` keeps the same `UserDefaults` keys under `LofiScore.`
  (the music's `enabled` and `musicLevelDB` are left in place, untouched);
  `SoundsFolderImport` copies only scores, atmosphere tracks and the
  `Atmosphere` folder, skipping the mood folders, `library.json` and the
  models, and on launch tidies those out of the app's own copy once;
  `AppAtmosphereHost` keeps the app's folder at `Application Support/LofiScore/Music`
  so an update keeps the imported sounds. `BookScore.contents(of:)` reads the
  score's keys without decoding a mood track, so a score with both parts still
  installs and the mood part is kept for later.
- **The Expo module and the app** (`applications/mobile/modules/lofi-score`,
  `applications/mobile/lofi`) show only the atmosphere: `LofiAtmosphereToolbarItem`,
  `LofiAtmosphereControls`, `LofiAtmosphereSettings`, `useLofiAtmosphere`. The
  native functions are `importSoundsFolder`, `syncSoundsFolder`,
  `unlinkSoundsFolder`, `installBookScore`, the atmosphere setters,
  `getAtmosphereCredits`, `removeImportedSounds`, `setFollowsReading`,
  `readerReached` and `readerStopped`. `fork.config.ts` lists the pods without
  `LofiDirector`, `LofiAudio` and `LofiPlaceholders`.
- **The Mac tools** (`libraries/LofiScoreKit/Tools/mac`) score the atmosphere
  alone: `make-atmosphere.sh` writes `<book>.score.json` from the finished
  atmosphere track, adding the mood track when `<book>.track.json` is there,
  and `lofi-sync.sh` makes mood tracks only with `--with-mood-tracks` or
  `LOFI_MOOD_TRACKS=1`.
- **Mood detection stayed.** `LofiMood` (engines, `MoodTracker`, the Claude
  transport, the per-book mood tracks), `lofi-eval`, `lofi-train` and
  `Docs/MoodDetection.md` are unchanged; the atmosphere's scorer shares the
  transport, and `make-tracks.sh` still makes a book's mood track.
- **The server route** (`/api/v2/books/{id}/lofi-score`) and the score format
  (`{"format":1,"mood":…,"atmosphere":…}`) are unchanged.

## Bringing the music back

1. **Sources and tests.** Move `LofiScoreKit/Sources/{LofiDirector,LofiAudio,LofiPlaceholders,LofiDemoKit,lofi-demo,lofi-import,lofi-placeholders,lofi-render,lofi-replay}`
   and `LofiScoreKit/Tests/{LofiDirectorTests,LofiAudioTests,LofiPlaceholdersTests,LofiDemoKitTests}`
   into `libraries/LofiScoreKit/`, with `Demo/`, `Docs/MusicEngine.md`,
   `Tools/library/` and the three podspecs. Copy `LofiScoreKit/Package.swift`
   over `libraries/LofiScoreKit/Package.swift`: it is the kept manifest plus
   the music targets, each depending on `LofiAudioCore`. Keep the
   `Reexports.swift` files. `swift build` should pass at this point; this
   manifest was checked that way, with the music targets and their tests, on
   the day the music was shelved.
2. **The host.** Merge the snapshot in `LofiScoreKit/Sources/LofiScoreHost`
   into `libraries/LofiScoreKit/Sources/LofiScoreHost`, keeping the atmosphere
   as it is now: the music player and its start and stop from `LofiMusicHost`,
   the `enabled` and `musicLevelDB` settings from `MusicSettings`, the mood
   folder, `library.json` and model rules from `MusicFolderImport` (and drop
   the one-time tidy in `SoundsFolderImport`), the fan-out follower and the
   mood tracker from the old `NarrationFollower` and `AtmosphereSupport`, the
   `MusicYield` that answers the player's `.musicYield`, `MoodFeedbackLog`,
   and the music's status fields. Add `LofiDirector`, `LofiAudio` and
   `LofiPlaceholders` to `LofiScoreHost.podspec`. The archived
   `LofiMusicHostTests` and `HostFeatureTests` say what the music's behaviour
   was.
3. **The app.** From `mobile/`, bring back the music functions in
   `LofiScoreModule.swift` and `index.ts`, the music lines of `status.ts`, the
   panel, settings section and toolbar button (`LofiMusicControls`,
   `LofiMusicSettings`, `LofiMusicToolbarItem`, `useLofiMusic`), beside the
   atmosphere's. Add the three pods back to `lofiScorePods` in
   `applications/mobile/fork.config.ts` and to `forkConfig.test.ts`.
4. **The Mac.** Make `--with-mood-tracks` the default in `lofi-sync.sh`, or
   set `LOFI_MOOD_TRACKS=1` in the launchd job that
   `install-automatic-scoring.command` writes.
5. **Docs and the fork check.** `libraries/LofiScoreKit/README.md`,
   `Docs/Atmosphere.md`, `FORK.md` and the purposes in
   `tools/fork/touchpoints.json` name the atmosphere alone; put the music back
   in them.
6. **Check.** `swift test` in `libraries/LofiScoreKit` (in Docker with
   `swift:6.2` off a Mac), `yarn tsc --build applications/mobile`,
   `yarn test:mobile`, `node tools/fork/check-fork.mjs`, then a build in
   Xcode. On the phone, import the `LofiMusic` folder again: the music folders
   the app tidied away are copied back from it.
