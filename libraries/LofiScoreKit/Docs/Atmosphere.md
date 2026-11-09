# Atmosphere sounds

Quiet sounds of the scene under the narration: rain while it rains, a fire in the inn, the sea
on the shore, a murmuring crowd in a school hallway. It's an option next to the music
("Atmosphere sounds" in the player's music panel and in Settings), on by default, with its
own volume.

## What it does

- **Follows the story's place, not single words.** Claude reads the book once, off the phone,
  and writes an *atmosphere track*: for every ~250 words (and every chapter start), where the
  story is, whether it is inside or outside, and up to four steady sounds at `faint`, `soft`
  or `full`.
- **Places keep their sounds.** Each place gets an id (`p1`, `p2`, …) and Claude is shown
  the places met so far with the sounds they had. When the story returns to a place it
  reuses that place's sounds, changed only where the text says something changed (the fire
  has died down, rain on the windows now). On the phone, a place also keeps the same
  recording each visit, and the book's rain is the same rain everywhere.
- **Weather carries over.** Rain, thunder, wind and snow stay with the story when it moves
  indoors (as rain on the windows) until the text says it stopped.
- **A crowd replaces the music.** When a scene has a crowd at `soft` or louder (a busy
  hallway, a tavern full of people, a market), the music fades out over 4 s and comes back
  when the scene moves on. Music and a crowd together are too much under a voice. Nothing
  else makes the music step aside.
- **Changes are calm.** A new scene crossfades over 6 s, a level change over 4 s, and two
  changes are at least 20 s apart unless the listener seeks. When a new chapter starts and
  has not said where it is yet, the last scene drops 8 dB until it does.

## Spoiler safety

The same rules as the mood track:

- Each entry is judged from the narrated text up to and including its own sentence
  (`SpoilerGuard.window(at:)`) plus the memory of places from *earlier* entries only. The
  builder's first pass runs in book order for that reason, one request at a time.
- Scene changes are pinned to within 3 sentences by bisecting between entries that disagree.
  A probe sees only the text up to its own sentence and the places before it.
- On the phone, the sound at sentence *n* comes from the newest entry at or before *n*,
  never a later one. Entries Claude was unsure of (confidence under 0.35) are skipped.
- The status screen shows only the scene playing now.

`BuilderTests`, `DirectorTests` and `AtmosphereHostTests` check these rules.

## Why these sounds, and how loud

The irrelevant-sound effect: background sound that changes from moment to moment (speech
above all, then intermittent events) disrupts listening and reading far more than steady
sound. So:

- Every sound is a steady, seamless loop. There are no one-shot effects (no door slams,
  no single thunderclap, no footsteps).
- A crowd is the only sound made of voices. It is filtered so words can't be made out
  (1 to 4 kHz taken down 12 dB, the top rolled off above 6 kHz), and it pushes the music out.
- Everything sits far under the voice: a sound at `full` is 28 dB under the narrator
  (the music bed is 16 dB under), and the slider goes from 40 to 16 dB under. Each sound
  also has its own offset (a ticking clock -8 dB, a crowd -3 dB, heavy rain +1 dB).
- Each sound gets the music's presence dip around 2.5 kHz, where speech is clearest.

The 26 sounds: rain, heavy rain, rain on the windows, thunder, wind, strong wind, snow,
fireplace, campfire, sea shore, open sea, river, dripping, forest, birdsong, night insects,
night forest, swamp, crowd, city, old town, horses, train, ship, machinery, clock.

## The pieces

| Piece | Where |
|---|---|
| Scene model, sounds, place memory, track file | `Sources/LofiAtmosphere/Scene`, `Track` |
| Claude prompt and engine (`ClaudeSceneEngine`) | `Sources/LofiAtmosphere/Claude` |
| Track builder (order, memory, refinement) | `Track/AtmosphereTrackBuilder.swift` |
| Director (which scene now) and player (fades, slots, crowd yield) | `Sources/LofiAtmosphere/Player` |
| Audio: its own `AVAudioEngine`, 8 looping slots | `Player/AVAmbienceBackend.swift` |
| Synthesised stand-ins for every sound | `Sound/AmbienceSynth.swift` |
| App host: setting, finding the track, music fade | `Sources/LofiScoreHost/AtmosphereSupport.swift`, `LofiMusicHost.swift` |
| CLI: `lofi-atmosphere track / show / score / synth / library` | `Sources/lofi-atmosphere` |

The atmosphere's engine never touches the audio session, Now Playing, the remote commands
or the microphone (`AtmosphereBoundaryTests` scans for it), like the music.

## Files

**Atmosphere track**, `<book>.atmosphere.json`: format 1, the engine id, the book, one entry
per scored sentence (chapter, sentence, global index, a digest of the sentence, the scene,
and the world note). The app uses a track only when its first entries' digests match the
book's sentences.

**Book score**, `<book>.score.json` or inside the book at
`META-INF/storyteller-lofi/score.json`: `{"format":1,"mood":<mood track>,"atmosphere":<atmosphere track>}`.
`lofi-atmosphere score --mood A.track.json --atmosphere A.atmosphere.json --out A.score.json`
writes one. The app looks for a book's atmosphere in the score inside the book, then in
imported scores, then in imported atmosphere tracks.

**Sounds**, an `Atmosphere` folder inside the music folder:

```
LofiMusic/
  Calm/ Cozy/ …              the music
  Atmosphere/
    Rain/ rain-fs123.m4a …   one folder per sound (names match loosely: "HeavyRain", "heavy rain")
    sounds.json              loudness, duration, title, author, source, licence
    SOURCES.csv  CREDITS.md
  tracks/                    *.track.json, *.atmosphere.json, *.score.json
```

Importing the music folder in Settings copies all of it. Sounds with no recording play the
synthesised stand-ins, rendered on the phone into Caches the first time. Settings shows how
many sounds are imported and has a "Sound credits" button for `Atmosphere/CREDITS.md`.
Only CC0, CC BY and CC BY-SA recordings are used, and audio is never committed (the fork is
public).

## On the Mac

From the clone in `~/Storyteller Lofi`, in `libraries/LofiScoreKit`:

1. **Recordings.** `python3 -I Tools/atmosphere/fetch_ambience.py`. With a Freesound API key
   in `~/Storyteller Lofi/.freesound-key` (free at https://freesound.org/apiv2/apply) it
   searches Freesound; without one it uses Wikimedia Commons. It keeps two steady recordings
   per sound, checks each licence on the recording's own record, cuts a seamless 60 s loop
   from the steadiest part (encoded with Apple's AAC encoder so the phone loops it without a
   tick), measures loudness, and writes `~/Storyteller Lofi/Atmosphere` with
   `sounds.json`, `SOURCES.csv`, `CREDITS.md` and `skipped.csv`. `--dry-run` lists what it
   would fetch.
2. **Tracks.** `Tools/mac/make-atmosphere.sh --dry-run BOOK.epub` prints the cost estimate.
   `Tools/mac/make-atmosphere.sh [--via plan|api] [--cap DOLLARS] [--model …] [--parallel N] BOOK.epub …`
   writes `~/Storyteller Lofi/tracks/<book>.atmosphere.json` (and `<book>.score.json` when
   the mood track is there too). `--via plan` (the default) runs through Claude Code on the
   signed-in plan; `--via api` uses the key file and needs `--cap`. Runs resume.
   `lofi-atmosphere show FILE --places` prints the scenes and places.
3. **Phone.** Copy `Atmosphere/` and `tracks/` into the music folder, put it in iCloud Drive,
   and import it in Settings.

Rough cost: one request per ~250 words plus probes, so a 100,000-word novel is ~650
requests: about $9 with Opus 5.5 at list prices, $4.50 with Sonnet 5.5, $0.25 with Haiku 5.5.
The first pass takes about 6 s a request (it runs in order), so a long novel takes most of an
hour; `--parallel` scores several books at once.

## Testing

`swift test --filter "LofiAtmosphereTests|LofiScoreHostTests"` (Linux in Docker or the Mac).
The player is tested against `FakeAmbienceBackend` with a manual clock: scenes follow the
narration, places keep their recordings, crowd yield on and off, pauses, muted routes,
headphones pulled, media reset, the level slider. The synth tests check every sound renders
at -23 LUFS and loops without a seam.
