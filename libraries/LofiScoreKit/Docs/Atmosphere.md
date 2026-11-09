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
- **More specific sounds.** Besides the 26 built-in sounds, a scene can use a more specific
  kind of one: church bells across a town, a waterfall, a café, a train station. Claude asks
  for a new one when a place clearly calls for it, the Mac fetches recordings for it, and
  until they are imported the phone plays the built-in sound it is a kind of.
- **Short pauses for big moments.** When a sentence is the moment a scene arrives
  (stepping into a crowded hall) or falls silent (a door shutting on the noise), the
  narrator can stop for under a second while the sound swells or hushes, then carry on.
  It's a setting ("Short pauses for big scene changes"), on by default, and rare.

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

## More specific sounds (variants)

A variant is a kind of a built-in sound (`of`) with its own recordings, e.g. `churchBells`
of `oldTown`, `waterfall` of `river`, `cafe` of `crowd`. It behaves exactly like that sound
(weather or place, crowd yield, level, filter) and only the recording differs. The scene
stores it on the layer (`{"sound":"oldTown","level":"soft","variant":"churchBells"}`) and the
track lists the book's variants with the entry that first asked for each (`firstIndex`).

- **Where they come from.** `Atmosphere/variants.json` on the Mac: the fetch script's 32
  starter variants (drizzle, blizzard, waterfall, harbour, café, tavern, feast hall, train
  station, church bells, library, spaceship, …) plus every variant a scored book asked for,
  with the books that asked. Shared variants go into the cached system prompt, so they cost
  almost nothing per request.
- **New ones.** Claude may add at most one new variant per answer, only when no built-in
  sound or listed variant fits and the place clearly calls for it, with words to search a
  sound library with. The CLI reports them, and the next fetch pulls recordings for them.
- **Spoiler-safe.** A book's own variants are offered only after the entry that first asked
  for them. A variant from the catalog that only this same book asked for (in an earlier
  run) is left out, since it may come from a later chapter. Starter variants and other
  books' variants say nothing about this book and are always offered.
- **On the phone.** Recordings live in `Atmosphere/<Sound>.<Variant>/`, e.g.
  `OldTown.ChurchBells/`. Without them the built-in sound plays, so a track never depends on
  a fetch having run.

## Short pauses for big moments

Claude marks a scene with a `moment` when the passage's last sentence *is* the moment the
sound arrives or falls silent, and refinement pins that change to the exact sentence:

- **swell**: walking into a crowded hall, a market or an inn; stepping out into a storm,
  or a storm breaking; reaching a beach, a cliff edge or a ship's deck; a train, coach or
  ship setting off, an engine starting; coming upon a waterfall, a river or a bonfire.
- **hush**: a door shutting on the noise, the rain stopping, an engine cutting out,
  walking into a silent church or out onto a snowy field.

When the narration reaches that sentence, the player asks the app to hold the narrator for
0.8 s at the end of the clip being read. While it holds, a swell brings the new sounds in
over 0.5 s and lifts them 8 dB, released over 3 s once the voice goes on; a hush cuts the
old sounds over 0.3 s. A moment also waives the 20 s gap between changes.

It stays rare and never surprises: at most one pause every 2 minutes, none in the first
10 s after play or a seek, never while seeking, only when the moment's sound is actually
heard, and only when the setting is on and the app's narrator accepts (it refuses while
paused or already holding). `LofiMusicHost.Environment.holdNarration` is the app's side;
the app calls `narrationHold(began:)` when the hold starts and ends.

## Personal and published sounds

Each recording's `use` in `sounds.json` says where it may play:

- **personal**: licensed for personal use only (CC BY-NC, or anything fetched through the
  Freesound API, whose terms are non-commercial). Only Mo's own builds play these.
- **publish**: a commercial-safe stand-by (CC0, CC BY, CC BY-SA from Wikimedia Commons).
  Mo's build skips a sound's stand-bys when it has other recordings.

The app's Info.plist key `LofiScoreSoundEdition` picks the edition. `fork.config.ts` sets it
from `LOFI_SOUND_EDITION`: `personal` by default, `publish` for an App Store build, which
then plays only commercial-safe recordings. A published build should import the publishing
set (`~/Storyteller Lofi/AtmospherePublish`) instead of Mo's own.

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
    OldTown.ChurchBells/ …   one folder per more specific sound: <Sound>.<Variant>
    sounds.json              loudness, duration, title, author, source, licence, variant, use
    variants.json            the more specific sounds known on the Mac
    SOURCES.csv  CREDITS.md
  tracks/                    *.track.json, *.atmosphere.json, *.score.json
```

Importing the music folder in Settings copies all of it. Sounds with no recording play the
synthesised stand-ins, rendered on the phone into Caches the first time. Settings shows how
many sounds are imported and has a "Sound credits" button for `Atmosphere/CREDITS.md`.
Published builds play only CC0, CC BY and CC BY-SA recordings (see "Personal and published
sounds"), and audio is never committed (the fork is public).

## On the Mac

From the clone in `~/Storyteller Lofi`, in `libraries/LofiScoreKit`:

The easy way: put read-aloud EPUBs in `~/Storyteller Lofi/Books` and double-click
`~/Storyteller Lofi/Score atmosphere.command` (a copy of `Tools/mac/score-atmosphere.command`).
It updates the tools clone in `~/Storyteller Lofi/atmosphere-tools`, scores every book
through the Claude plan, fetches any new sounds and copies everything into
`~/Storyteller Lofi/LofiMusic`. The steps it runs:

1. **Recordings.** `python3 -I Tools/atmosphere/fetch_ambience.py [--edition personal|publish]`.
   - `personal` (the default) searches Freesound with the API key in
     `~/Storyteller Lofi/.freesound-key` (free at https://freesound.org/apiv2/apply),
     allowing CC0, CC BY and CC BY-NC, and falls back to Wikimedia Commons. Every
     Freesound recording is marked `use: personal`. It writes `~/Storyteller Lofi/Atmosphere`.
   - `publish` uses Wikimedia Commons only, with commercial-safe licences, and writes
     `~/Storyteller Lofi/AtmospherePublish`.

   It keeps up to `--per-sound 4` recordings per built-in sound and `--per-variant 2` per
   more specific sound (the starter set plus those the tracks in `--tracks` asked for;
   `--no-variants` skips them, `--sound OldTown.ChurchBells` fetches only that). It checks
   each licence on the recording's own record, cuts a seamless 60 s loop from the steadiest
   part (encoded with Apple's AAC encoder so the phone loops it without a tick), measures
   loudness, and writes `sounds.json`, `variants.json`, `SOURCES.csv`, `CREDITS.md` and
   `skipped.csv`, saving as it goes so a stopped run resumes. `--dry-run` lists what it
   would fetch.
2. **Tracks.** `Tools/mac/make-atmosphere.sh --dry-run BOOK.epub` prints the cost estimate.
   `Tools/mac/make-atmosphere.sh [--via plan|api] [--cap DOLLARS] [--model …] [--parallel N] [--no-fetch] [--no-copy] BOOK.epub …`
   writes `~/Storyteller Lofi/tracks/<book>.atmosphere.json` (and `<book>.score.json` when
   the mood track is there too), offering the variants in `Atmosphere/variants.json`.
   `--via plan` (the default) runs through Claude Code on the signed-in plan; `--via api`
   uses the key file and needs `--cap`. Runs resume. Afterwards it fetches recordings for
   new variants (unless `--no-fetch`; needs ffmpeg) and copies the tracks and `Atmosphere/`
   into `~/Storyteller Lofi/LofiMusic` (unless `--no-copy`).
   `lofi-atmosphere show FILE --places` prints the scenes, places and variants, and
   `lofi-atmosphere library DIR [--edition publish]` lists what a build would play.
3. **Phone.** Put `LofiMusic` in iCloud Drive and import it in Settings.

Rough cost: one request per ~250 words plus probes, so a 100,000-word novel is ~650
requests: about $9 with Opus 5.5 at list prices, $4.50 with Sonnet 5.5, $0.25 with Haiku 5.5.
The first pass takes about 6 s a request (it runs in order), so a long novel takes most of an
hour; `--parallel` scores several books at once.

## Testing

`swift test --filter "LofiAtmosphereTests|LofiScoreHostTests"` (Linux in Docker or the Mac).
The player is tested against `FakeAmbienceBackend` with a manual clock: scenes follow the
narration, places keep their recordings, crowd yield on and off, pauses, muted routes,
headphones pulled, media reset, the level slider. `VariantTests` covers variant ids and
folders, the catalog's spoiler rule, editions, Claude's new variants and moments, and the
narration holds (swell, hush, too early, refused, dropped, setting off). The synth tests check every sound renders
at -23 LUFS and loops without a seam.
