# The music side of LofiScoreKit

This half of the package turns mood readings into music: it decides *when* the
music should change (the director) and makes the change sound good (the player).
It never sees the book's text, only `MoodObservation`s from the text side, and it
never acts on a reading for text the narrator has not reached.

```
MoodObservation ──► MoodDirector ──► MoodDecision ──► LofiScorePlayer ──► AVAudioEngineBackend
 (text side)        smoothing,        (bucket +        two decks, bar-       players → EQ → main mixer
                    confirmation,      gentle/quick)    aligned crossfades,   (inside the narrator's
                    dwell, no lookahead                 bed level, rotation    audio session)
```

## Targets

| Target | What it holds | Runs on |
| --- | --- | --- |
| `LofiDirector` | `MoodDirector`, `DirectorConfig`, `MoodDecision`, clocks, the replay runner and synthetic books | everywhere (pure Swift) |
| `LofiAudio` | `LofiScorePlayer`, `ScoreConfig`, crossfader, ducker, bar grid, `MusicLibrary` / `library.json`, `TrackRotation`, `FakeAudioBackend`; `AVAudioEngineBackend` on Apple platforms | everywhere; the backend on Apple platforms |
| `LofiPlaceholders` | a small lofi synthesiser, BS.1770 loudness meter, WAV writer, and the placeholder library | everywhere |
| `LofiDemoKit` | the demo story, scripted mood source, pretend narrator; SwiftUI demo on Apple platforms | logic everywhere, UI on Apple platforms |
| `lofi-replay` | runs replay scripts and synthetic 10-hour books through the director | everywhere |
| `lofi-placeholders` | writes the placeholder library (WAV + `library.json`) | everywhere |
| `lofi-demo` | the demo as a macOS app | macOS |
| `lofi-render` | the demo story read by the Mac's voice with the music underneath, rendered offline to an `.m4a` | macOS |
| `lofi-import` | measures a music folder and writes its `library.json` | macOS (WAV only elsewhere) |

Music targets build in the Swift 5 language mode because AVFoundation's
callbacks are not annotated for strict concurrency yet. The player keeps all of
its state on one serial queue (`LofiScheduler`) instead.

## The director

`MoodDirector` is pure logic with an injected clock. Every threshold lives in
`DirectorConfig`, which decodes partial JSON overrides.

| Rule | Default |
| --- | --- |
| Evidence per bucket, fading with listening time (frozen while paused) | 60 s time constant |
| Calm is the neutral prior | 0.25 |
| A new leader must beat the current mood by | 0.1 |
| Readings in a row before a change | 2 |
| Big jump: one reading at this confidence, far enough away, changes at once (quick crossfade) | 0.8 confidence, 1.0 distance, after 30 s |
| Minimum time between changes | 90 s |
| Chapter start keeps the previous music until the chapter's first reading, which carries over | 30% of the old evidence |
| A seek waits for the reading of the new place (quick crossfade, dwell waived) | up to 30 s |
| Reading below this confidence after a seek or start is provisional (dwell not reset) | 0.35 |

Spoiler guard, on top of the text side's own: once the host reports the
playhead (`sentenceDidStart(globalSentenceIndex:)`), any reading for a later
sentence is ignored and counted (`ignoredCounts[.aheadOfPlayhead]`). Readings
from before a seek, and out-of-order readings, are ignored too.

### Replays

`Tests/LofiDirectorTests/Replays/*.json` are hand-written timelines with
expectations (`"expect": "tense"` at a time). `swift run lofi-replay` runs them
at full speed; `swift run lofi-replay --synthetic --hours 10 --seeds 1-12` runs
synthetic books with a known mood timeline, noisy readings, seeks and pauses,
and prints changes per hour, agreement and follow delay. On 12 synthetic
10-hour books the defaults give about 6.8 changes an hour (at most 9.3), 96%
agreement allowing two minutes of lag, a median follow delay of about two
minutes, and no dwell violations. The two-minute lag is mostly the text side's
400-word window, so the plan's 10 to 30 second target is not reachable with
that window; shortening the window trades lag for more wrong changes.

## The player

`LofiScorePlayer` takes narrator events from the host, feeds the director, and
moves the music.

| Narrator event | Call | What the music does |
| --- | --- | --- |
| Book opened | `openBook(id:)` | Fresh director state; the old book fades out first if one was playing |
| Play | `narratorDidPlay()` | Fades in over 2 s. On the first play of a book it waits up to 1.5 s for the first reading so it starts in the right mood |
| Pause, sleep timer | `narratorDidPause()` | Fades out over 1 s, stops the decks (remembering where), stops the engine after 2 minutes paused |
| Sentence starts | `sentenceDidStart(globalSentenceIndex:duration:)` | Sets the spoiler playhead; bed level while the voice speaks |
| Sentence ends (if the host knows ends, not durations) | `sentenceDidEnd()` | Silence detection |
| Seek, skip, chapter jump | `narratorDidSeek(toGlobalSentenceIndex:)` | Keeps playing until the new place's reading arrives, then a quick crossfade if the mood differs |
| Rate change | nothing | Nothing: the music never changes speed |
| Book closed | `closeBook()` | Fades out and forgets the book |
| Mood reading | `receive(_:)` | Director input |

Settings: `setEnabled(_:)` (music button or per-book opt-out), `setDucking(_:)`,
`setMusicVolume(_:)`, `setMutedRoutes([.carPlay])` ("music off in the car").
`snapshot(_:)` returns everything the debug overlay needs; `onDecision` and
`onEvent` report changes.

How it sounds:

- **Two decks, equal-power crossfades.** The fader position moves in a straight
  line and the gains follow cos/sin, so loudness stays level, including when a
  crossfade reverses halfway (the listener seeks back). Gentle changes take
  7 s, quick ones (seek, big jump) 3.5 s.
- **On the bar line.** When a track's tempo is known (`bpm` in `library.json`,
  or "72bpm" in the file name) a change starts on the outgoing track's next bar
  line, waiting at most 4 s.
- **Gain automation at 60 Hz** while anything moves; nothing runs at rest.
- **Bed level:** each track is set so it sits 12 dB under a voice at −18 LUFS,
  using its measured loudness (−16 LUFS assumed if unknown). After 1.5 s of
  silence (noticed only once it has happened) the music rises 4 dB over 1.5 s
  and settles back in 0.4 s when the voice returns.
- **Track rotation:** 7 s before a track ends (on a bar line), it crossfades to
  another track of the same mood, avoiding the last three played.
- **Robustness:** an empty mood falls back to the nearest one; broken files are
  skipped; the engine restarts after interruptions, configuration changes and
  media-services resets (reloading the decks); pulled headphones fade the music
  out in 0.1 s and wait for the narrator's next play.

### What it never does

`AVAudioEngineBackend` never sets the audio session's category, mode, options or
activation, never touches Now Playing or the remote commands, and never touches
the engine's input node. The narrator owns all of those; the engine plays inside
the narrator's session. `Tests/LofiAudioTests/BoundaryTests.swift` scans the
music sources and fails if any of those calls (or a time-pitch unit) appear.

## The music library

A library is a folder with one subfolder per mood, or a `library.json`:

```
LofiMusic/
  Calm/        Cozy/      Playful/    Hopeful/
  Melancholy/  Mysterious/ Tense/     Somber/
  library.json   (optional; written by an import tool)
```

Folder names match loosely ("calm", "Sombre"). Every
`m4a/aac/mp3/wav/aif/aiff/caf/flac` file in a mood folder is a track, and a tempo
in the file name is picked up. `library.json` adds measured loudness and the rest;
files it does not list still play, at an assumed −16 LUFS, until the next import:

```json
{
  "version": 1,
  "targetLoudness": -16,
  "tracks": [
    { "id": "calm-1", "file": "Calm/calm-1 72bpm.wav", "bucket": "calm",
      "valence": 0.25, "arousal": 0.15, "intensity": 0.2,
      "bpm": 72, "beatsPerBar": 4, "downbeat": 0, "key": "F major",
      "duration": 40.0, "loudness": -16.0, "truePeak": -3.3,
      "source": "LofiPlaceholders v1", "license": "…", "prompt": "…", "seed": "101" }
  ]
}
```

Paths must stay inside the folder (no `/` prefix, no `..`). Music never goes in
git: the fork is public. `.gitignore` here ignores audio files and the
`/Library/` and `/PlaceholderLibrary/` folders.

**Importing.** `swift run -c release lofi-import ~/Storyteller\ Lofi/LofiMusic`
decodes every track, measures its integrated loudness (BS.1770), true peak and
length, takes the source and license from a `SOURCES.csv` beside the music when
there is one (matched by file name), and writes `library.json` (keeping the old one
as `library.json.bak`). Tempo, key and anything else already in `library.json` are
kept. Run it again after adding music. `--dry-run` only prints.

**Placeholder music.** `swift run -c release lofi-placeholders` synthesises 16
original tracks (two per mood, 30 to 42 s, distinct tempos and keys) normalised
to −16 LUFS, into `PlaceholderLibrary/`. The demo makes them on first launch.
Mo's Mac also has 32 CC0 tracks by HoliznaCC0 from Free Music Archive in
`~/Storyteller Lofi/LofiMusic` (4 per mood, sources and licenses in
`SOURCES.csv`), picked by title and tags, not by ear.

## The demo

`LofiDemoKit` plays a short original story ("The Green Lantern", four chapters
that visit all eight moods) through the real player. A pretend narrator steps
through the sentences (or reads them aloud with the system voice) and sends the
same events Storyteller's narrator will; a scripted mood source reads the
story's hand-written labels over a window that ends at the current sentence and
adds some noise. The screen shows the text mood next to the music mood, both
decks, the director's evidence and dwell, and a log. "Fast demo timings" (on by
default) shortens smoothing to 12 s and dwell to 20 s so the five-minute story
shows several changes.

- **Mac:** `swift run -c release lofi-demo` (needs Xcode or the Command Line Tools).
- **iPhone:** open `Demo/LofiScoreDemo.xcodeproj` in Xcode, choose your team
  under Signing, pick the phone and run. The scheme runs the Release build so
  the first-launch synthesis takes seconds, not minutes. "Choose music folder…"
  opens a folder of real tracks, for example the CC0 set copied to the phone
  with the Files app.

The same narrator and mood source run headless in `Tests/LofiDemoKitTests`,
which plays the whole story on a manual clock and checks that no change is
made before its mood has been narrated.

For unattended runs (the Simulator, screenshots) the app takes launch arguments:
`-LofiDemoAutoplay YES` starts reading once the music is ready, `-LofiDemoSilent YES`
sets the music volume to zero with the voice off, and `-LofiDemoMusicFolder /path`
uses that folder instead of the placeholders.

### Listening without installing anything

`swift run -c release lofi-render --music ~/Storyteller\ Lofi/LofiMusic --out story.m4a`
renders the demo story to a file you can play anywhere, such as on a phone without
Developer Mode. The Mac's voice (`say`) reads each sentence; the story runs
through the real `LofiScorePlayer` on a manual clock (`OfflineStoryRun`) with an
`AVAudioEngineBackend` in offline manual-rendering mode, so the crossfades, bar
alignment, bed level, gap lift, EQ and rotation are the engine's own. The voice is
levelled to −18 LUFS, the bed the player set sits under it, and the whole file is
brought to −16 LUFS with peaks under −1 dBFS. A `.txt` beside it lists the chapters,
the text side's readings and every music change with its time, to read along.
Options: `--voice NAME` (any `say -v '?'` voice), `--rate WPM`, `--real-timings`
(the app's 90 s dwell instead of the demo's 20 s), `--noise`, `--seed`. Nothing
is played out loud.

## Running the tests

`swift test` runs everything that is not Apple-only (122 tests on Linux):
director rules, replays, 10-hour synthetic books, the causality property test,
the player against a fake backend (crossfade power, bar alignment, reversal,
queued changes, pause and engine stop, ducking, rotation, route loss, restarts,
fallbacks), the library loader and importer, loudness against the BS.1770
reference, the end-to-end demo, and the offline run and mix behind `lofi-render`. The AVAudioEngine backend and the SwiftUI demo compile only on
Apple platforms; build them on a Mac with `swift build` or in Xcode.

## For the Expo integration (thread 5)

1. Build a `MusicLibrary` from the folder Mo picks (`MusicLibrary.load(from:)`).
2. Create one `LofiScorePlayer(library:backend: AVAudioEngineBackend())` for the app.
3. Map `AudiobookPlayerActor` events: play → `narratorDidPlay()`, pause and
   sleep → `narratorDidPause()`, clip change → `sentenceDidStart(globalSentenceIndex:duration:)`
   (duration = clip length ÷ playback rate), seek or chapter jump →
   `narratorDidSeek(toGlobalSentenceIndex:)`, book open/close → `openBook`/`closeBook`.
4. Send `MoodTracker`'s observations to `receive(_:)`.
5. Make sure the narrator has activated its session before `narratorDidPlay()`;
   the player starts its engine there and never touches the session itself.
