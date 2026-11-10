# Atmosphere sounds

Steady sounds of the scene under the narration, the whole time: rain while it rains, a fire
in the inn, the sea on the shore, a murmuring crowd in a school hallway, the quiet of an
ordinary room. It is what the app plays ("Atmosphere sounds" in the player's panel and in
Settings), on by default, with its own volume and a dial for how much is going
on. The words stay clear through all of it.

## What it does

- **Follows the story's place, not single words.** Claude reads the book once, off the phone,
  and writes an *atmosphere track*: for every ~250 words (and every chapter start), where the
  story is, whether it is inside or outside, what state it is in, and up to five steady
  sounds at `faint`, `soft`, `full` or (rarely) `loud`.
- **Every place has a sound.** A listener in a quiet room hears the room; a ship creaks and
  has water around it; a packed corridor has a crowd. Claude infers the sound even when the
  text does not mention it, so the bed never falls silent just because the author did not
  describe the weather. It answers with no sounds only when it cannot tell where the
  characters are.
- **A place changes with its state.** The same corridor sounds different after hours (an
  empty hall), between lessons (a crowd), when everyone is whispering about you (the
  whispers come forward, the hall sits under them) and when a fight breaks out (the crowd at
  `loud`). Claude reports the state with the scene, and the place remembers it.
- **Places keep their sounds.** Each place gets an id (`p1`, `p2`, …) and Claude is shown
  the places met so far with the sounds they had. When the story returns to a place it
  reuses that place's sounds, changed only where the text says something changed (the fire
  has died down, rain on the windows now). On the phone, a place also keeps the same
  recording each visit, and the book's rain is the same rain everywhere.
- **Weather carries over.** Rain, thunder, wind and snow stay with the story when it moves
  indoors (as rain on the windows) until the text says it stopped.
- **A crowd replaces the music, when there is music.** When a scene has a crowd at `soft`
  or louder (a busy hallway, a tavern full of people, a market), the player asks the music
  to fade out over 4 s and come back when the scene moves on. Music and a crowd together
  are too much under a voice. With the music shelved nothing answers that request; it
  stays so the music can come back (`shelved/lofi-music/README.md`).
- **Changes are calm.** A new scene crossfades over 6 s, a level change over 4 s, and two
  changes are at least 20 s apart unless the listener seeks. When a new chapter starts and
  has not said where it is yet, the last scene drops 8 dB until it does.
- **A catalogue of sounds.** 38 sound families (rain, fireplace, crowd, murmur, room tone,
  an empty hall, a kitchen, a workshop, a farmyard, an engine, a spaceship, …) with 288 more
  specific kinds under them (a drizzle, a school corridor between lessons, hallway whispers,
  a hushed library, a hospital ward at night, a submarine, …) and a guide to what 31 kinds
  of place sound like in each of their states. Claude asks for a new kind when a place
  clearly calls for one, the Mac fetches recordings for every kind, and until they are
  imported the phone plays the family it is a kind of.
- **A steady bed, kept clear of the voice.** The sounds play under the narration the whole
  time, 24 dB under it by default, with the voice's band dipped and the voices in a crowd
  blurred. A scene with many sounds is trimmed so that together they are no louder than one
  sound alone; the dial turns the quieter sounds down and off before the main one. In the
  gaps between sentences (a paragraph, a chapter end, a breath) the bed comes forward a
  little and drops back the moment the voice returns.
- **Short pauses for big moments.** When a sentence is the moment a scene arrives
  (stepping into a crowded hall) or falls silent (a door shutting on the noise), the
  narrator can stop for under a second while the sound swells or hushes, then carry on.
  It's a setting ("Short pauses for big scene changes"), on by default, and rare.
- **One-off sounds, if you want them.** A single sound on the sentence that says it
  happens: a knock at the door, a clap of thunder, a clock striking. Off by default
  ("One-off sounds" in Settings), rare, and well under the voice.

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

- **Where they come from.** The built-in catalogue (`SoundCatalog`, 288 kinds, below) is
  always offered, in the cached system prompt. `Atmosphere/variants.json` on the Mac adds
  every variant a scored book asked for, with the books that asked; those that are not in
  the catalogue go into the system prompt too, so they cost almost nothing per request.
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

## The catalogue and the place guide

`Sources/LofiAtmosphere/Scene/SoundCatalog.swift` is the one source of truth for what the
scorer may use and what the Mac fetches:

- **Families** (`AmbientSound`, 38) in groups: weather (rain, heavy rain, rain on the
  windows, thunder, wind, strong wind, snow), fire (fireplace, campfire), water (sea shore,
  open sea, river, dripping), nature (forest, birdsong, night insects, night forest, swamp,
  farmyard), rooms (room tone, hushed room, empty hall, electric hum, clock, kitchen,
  workshop), people (murmur, crowd), places (city, old town), travel (horses, train, ship,
  machinery, motor vehicle, aircraft, spaceship) and elsewhere (deep drone). A family
  decides behaviour: weather carries over between places, `crowd` replaces the music,
  `crowd` and `murmur` are the only sounds made of voices (filtered so no word can be made
  out), each has its own level offset, and each has a synthesised stand-in.
- **Kinds** (`SoundCatalog.variants`, 288), each a kind of one family with a line on what it
  is and words to search a sound library with: `crowd.schoolCorridor`,
  `murmur.hallwayWhispers`, `emptyHall.schoolHallwayEmpty`, `hushedRoom.library`,
  `electricHum.office`, `motorVehicle.car`, `aircraft.airliner`, `kitchen.restaurantKitchen`,
  `roomTone.bedroomNight`, `deepDrone.magicalHush`, … Ids are unique across families, so a
  kind can move to a better family (an office is now a kind of electric hum, not of
  machinery) and its recordings still play.
- **The people ladder.** `roomTone` (nobody else heard), `hushedRoom` (people keeping quiet,
  no voices), `murmur` (a few low voices; the music stays), `crowd` (many voices right
  around the characters; the music pauses). Claude climbs or descends it as a place fills
  or empties.
- **The place guide** (`SoundCatalog.placeGuide`, 31 places, 118 states): what a school
  corridor, a classroom, a hospital ward, a tavern, a ship's cabin, a forest, a battlefield,
  a spaceship bridge … sound like in each state they can be in, e.g. the corridor after
  hours (`emptyHall.schoolHallwayEmpty soft`), between lessons (`crowd.schoolCorridor
  full`), everyone whispering (`murmur.hallwayWhispers soft, emptyHall.schoolHallwayEmpty
  faint`), an uproar (`crowd.schoolCorridor loud`). It is typical, the text decides.
- **Consistency.** A place keeps its sounds and its recordings across visits, and its last
  state is shown to Claude with it, so the corridor that was whispering is still whispering
  when the story comes back to it unless the text says otherwise.

The whole catalogue and the guide are in the system prompt (about 9,000 tokens, cached, so
it costs about a cent a request on Opus after the first). To add or move a kind, edit
`SoundCatalog.swift`, then write the JSON the fetch script reads:
`swift run lofi-atmosphere catalog --out Tools/atmosphere/catalog.json` (`CatalogTests` fails
until the committed file matches). `lofi-atmosphere catalog --prompt` prints the system
prompt. Tracks scored with an older prompt (engine id `…/a3`) still play; a book is rescored
only when its track is moved aside (`make-atmosphere.sh --rescore`), since a rescore costs
plan usage.

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
paused or already holding). `LofiAtmosphereHost.Environment.holdNarration` is the app's side;
the app calls `narrationHold(began:)` when the hold starts and ends.

## One-off sounds

15 single sounds (`OneShotSound`): thunder clap, door knock, door slam, door creak,
doorbell, telephone ring, bell toll, clock chime, breaking glass, dog bark, owl hoot, wolf
howl, horse neigh, train whistle, ship's horn. Loud, startling sounds (gunshots,
explosions, screams) are left out on purpose.

- **Scoring.** Each answer may name one (`oneShot`: the sound and up to eight words copied
  from the passage that say it happens), only when the text says the sound itself happens
  right then where the characters are: not remembered, expected, compared to or talked
  about. The builder finds the sentence the words are in. On the passage's last sentence it
  is kept as it is. On an earlier one the answer had seen text after that sentence, so the
  sentence is scored again with a window that ends on it, and the cue is kept only if that
  answer puts the same sound there (`OneShotTests` checks a knock that only the next
  sentence explains is dropped). These checks are capped at a fifth of the planned entries.
- **Track.** `cues` in the atmosphere track: sentence, digest, sound, and where in the
  sentence it falls (the quote's last word), so it lands when its words are read.
- **Playback**, only with the setting on: when the narration reaches the sentence the sound
  waits for its place in it (sentence duration × position, at most 8 s; if the next
  sentence starts first, it plays then). It plays 10 dB above a sound at `full`, still well
  under the voice, with the same presence dip. At most one every 30 s, none in the first
  3 s after play or a seek, never on a jump, and never while reading on screen (sentences
  with no duration). Pausing, seeking or turning it off drops a waiting one.
- **Sounds.** `Atmosphere/OneShots/<Sound>/` with `OneShots/sounds.json`, the same
  personal and publish rules as the beds. Ten have synthesised stand-ins (thunder, knock,
  slam, doorbell, telephone, bell, clock, owl, train whistle, ship's horn); the animals,
  the creaking door and breaking glass stay silent until recordings are imported.

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

- Every sound is a steady, seamless loop. One-off sounds are a separate extra, off by
  default (see "One-off sounds").
- A crowd and a murmur are the only sounds made of voices. They are filtered so words can't
  be made out (1 to 4 kHz taken down 12 dB, the top rolled off above 6 kHz), and a crowd
  pushes the music out.
- Everything sits well under the voice: a sound at `full` is 24 dB under the narrator (the
  shelved music's bed was 16 dB under), and the slider goes from 40 to 14 dB under, never closer. Each
  sound also has its own offset (a ticking clock -8 dB, room tone -6, an electric hum -5, a
  hushed room, a murmur or a deep drone -4, a crowd -3, heavy rain +1 dB), and `loud` is
  only 4 dB over `full`.
- A scene is never louder than one sound. Its sounds are ranked loudest first and trimmed
  together so their sum is no louder than the main one alone (two sounds at the same level
  each lose 3 dB), so a rich scene adds texture, not level.
- The dial ("How much is going on", `AtmosphereConfig.intensity`, 0 to 1, 0.75 by default)
  decides how many of the scene's sounds play (one at 0, all five at 1) and how far the
  quieter ones sit behind the main one (6 dB further at 0). It never changes the main
  sound's level: that is the volume slider's job.
- In the gaps between sentences the bed lifts 4 dB at full intensity (3 at the default),
  starting 0.7 s after the sentence should have ended so a sentence that follows at once
  gets no lift, rising over 0.6 s and dropping back in 0.25 s when the next sentence starts.
  Pausing, seeking and a narration hold end it too. Reading on screen has no sentence
  timing, so no lift.
- Each sound gets a presence dip around 2.5 kHz, where speech is clearest.

The 38 families: rain, heavy rain, rain on the windows, thunder, wind, strong wind, snow,
fireplace, campfire, sea shore, open sea, river, dripping, forest, birdsong, night insects,
night forest, swamp, crowd, city, old town, horses, train, ship, machinery, clock, room
tone, hushed room, murmur, empty hall, electric hum, kitchen, workshop, farmyard, motor
vehicle, aircraft, spaceship, deep drone.

## The pieces

| Piece | Where |
|---|---|
| Scene model, sounds, the catalogue and place guide, place memory, track file | `Sources/LofiAtmosphere/Scene`, `Track` |
| Claude prompt and engine (`ClaudeSceneEngine`) | `Sources/LofiAtmosphere/Claude` |
| Track builder (order, memory, refinement) | `Track/AtmosphereTrackBuilder.swift` |
| Director (which scene now) and player (fades, slots, crowd yield) | `Sources/LofiAtmosphere/Player` |
| Audio: its own `AVAudioEngine`, 12 looping slots | `Player/AVAmbienceBackend.swift` |
| Synthesised stand-ins for every sound | `Sound/AmbienceSynth.swift` |
| App host: settings, finding the track, the sounds folder | `Sources/LofiScoreHost/AtmosphereSupport.swift`, `LofiAtmosphereHost.swift` |
| CLI: `lofi-atmosphere track / show / score / synth / library / catalog` | `Sources/lofi-atmosphere` |
| The catalogue as the fetch script reads it | `Tools/atmosphere/catalog.json` |

The atmosphere's engine never touches the audio session, Now Playing, the remote commands
or the microphone (`AtmosphereBoundaryTests` scans for it).

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

**Sounds**, an `Atmosphere` folder inside the sounds folder (still called `LofiMusic` on
the Mac and in iCloud Drive, from when it held the music):

```
LofiMusic/
  Calm/ Cozy/ …              the shelved music's folders, if still there: the import skips them
  Atmosphere/
    Rain/ rain-fs123.m4a …   one folder per sound family (names match loosely: "HeavyRain", "heavy rain")
    Crowd.SchoolCorridor/ …  one folder per more specific kind: <Family>.<Kind>
    sounds.json              loudness, duration, title, author, source, licence, variant, use
    variants.json            the more specific sounds known on the Mac
    OneShots/DoorKnock/ …    one-off sounds, with OneShots/sounds.json
    SOURCES.csv  CREDITS.md
  tracks/                    *.track.json, *.atmosphere.json, *.score.json
```

Importing the sounds folder in Settings copies all of it. Sounds with no recording play the
synthesised stand-ins, rendered on the phone into Caches the first time. Settings shows how
many sounds are imported and has a "Sound credits" button for `Atmosphere/CREDITS.md`.
Published builds play only CC0, CC BY and CC BY-SA recordings (see "Personal and published
sounds"), and audio is never committed (the fork is public).

## On the Mac

From the clone in `~/Storyteller Lofi`, in `libraries/LofiScoreKit`:

The easy way: double-click `Tools/mac/install-automatic-scoring.command` once. It fetches
and builds the tools into `~/Storyteller Lofi/scoring-tools`, asks for the Storyteller
server's address and login (optional; the password goes into the login keychain), and
installs a launchd job that runs `Tools/mac/lofi-sync.sh` whenever a book lands in
`~/Storyteller Lofi/Books` and every half hour. From then on a book synced in Storyteller
gets its atmosphere by itself: the job fetches newly synced read-aloud books
(`Tools/mac/fetch-books.sh`), scores each unscored one through the Claude plan (its
atmosphere, written as `<book>.score.json`; the shelved music's mood track,
`Tools/mac/make-tracks.sh --engine claude --prompt 3`, only with `--with-mood-tracks` or
`LOFI_MOOD_TRACKS=1`), fetches any new sounds, copies everything into
`~/Storyteller Lofi/LofiMusic` and its iCloud Drive copy, and puts the score inside the
book on the server (`Tools/mac/push-scores.sh`, the fork's `lofi-score` route). The phone's
linked sounds folder and the book itself bring the score to the reader. Each step is capped
per book at API list prices (25 dollars for the atmosphere, 20 for a mood track; edit
`lofi-sync.sh` to change them), so a run that goes wrong can't use up the plan; the next
run carries on. Logs are in `~/Storyteller Lofi/logs`; `stop-automatic-scoring.command`
turns the job off. `~/Storyteller Lofi/Score atmosphere.command` (a copy of
`Tools/mac/score-atmosphere.command`) runs the same sync once, in a window, for books
dropped into `Books/` by hand. The atmosphere steps it runs:

1. **Recordings.** `python3 -I Tools/atmosphere/fetch_ambience.py [--edition personal|publish]`.
   - `personal` (the default) searches Freesound with the API key in
     `~/Storyteller Lofi/.freesound-key` (free at https://freesound.org/apiv2/apply),
     allowing CC0, CC BY and CC BY-NC, and falls back to Wikimedia Commons. Every
     Freesound recording is marked `use: personal`. It writes `~/Storyteller Lofi/Atmosphere`.
   - `publish` uses Wikimedia Commons only, with commercial-safe licences, and writes
     `~/Storyteller Lofi/AtmospherePublish`.

   What it fetches comes from `Tools/atmosphere/catalog.json` (`--catalog FILE`), the
   catalogue the app itself uses, so the two never drift. It keeps up to `--per-sound 4`
   recordings per sound family, `--per-variant 2` per more specific kind (the catalogue's
   288 plus those the tracks in `--tracks` asked for; `--no-variants` skips them,
   `--sound Crowd.SchoolCorridor` fetches only that; a kind the catalogue has moved to
   another family is moved along with its credits) and
   `--per-one-shot 2` per one-off sound (`--no-one-shots` skips them; each is trimmed of
   silence, cut to a few seconds and faded out, not looped). It keeps only recordings
   whose title (or Freesound tags) names the sound, because search also matches long
   descriptions (a pier's creaks recorded on a rainy day came up under rain). It checks
   each licence on the recording's own record, cuts a seamless 60 s loop from the steadiest
   part (encoded with Apple's AAC encoder so the phone loops it without a tick), measures
   loudness, and writes `sounds.json`, `variants.json`, `SOURCES.csv`, `CREDITS.md` and
   `skipped.csv`, saving as it goes so a stopped run resumes. It waits out rate limits
   (Wikimedia answers HTTP 429 to quick searches) rather than skipping sounds, and downloads
   through `.part` files. Only one run writes a folder
   at a time (a second one waits), and at the end it lists audio files that `sounds.json`
   doesn't know: the app plays those too, without credits. `--dry-run` lists what it
   would fetch.
2. **Tracks.** `Tools/mac/make-atmosphere.sh --dry-run BOOK.epub` prints the cost estimate.
   `Tools/mac/make-atmosphere.sh [--via plan|api] [--cap DOLLARS] [--model …] [--parallel N] [--rescore] [--no-fetch] [--no-copy] BOOK.epub …`
   writes `~/Storyteller Lofi/tracks/<book>.atmosphere.json` and, once the track is
   finished, `<book>.score.json` (with the shelved music's mood track in it when
   `<book>.track.json` is there too), offering the catalogue and the variants in
   `Atmosphere/variants.json`. A book with a track is left alone; `--rescore` moves its
   track and score to `tracks/old/` first, for a book scored before the catalogue grew.
   `--via plan` (the default) runs through Claude Code on the signed-in plan; `--via api`
   uses the key file and needs `--cap`. Runs resume. Afterwards it fetches recordings for
   new variants (unless `--no-fetch`; needs ffmpeg) and copies the tracks and `Atmosphere/`
   into `~/Storyteller Lofi/LofiMusic` (unless `--no-copy`).
   `lofi-atmosphere show FILE --places` prints the scenes, places and variants, and
   `lofi-atmosphere library DIR [--edition publish]` lists what a build would play.
3. **Phone.** Put `LofiMusic` in iCloud Drive and import it in Settings once. The folder
   stays linked: the app checks it for new scores and sounds when it starts, comes to the
   front or opens a book without a score, and Settings has "Check for new files now". A
   book whose score is inside it (the server route) needs no sounds folder at all for its
   atmosphere track, only for the recordings.

Rough cost: one request per ~250 words plus probes, so a 100,000-word novel is ~650
requests: about $9 with Opus 5.5 at list prices, $4.50 with Sonnet 5.5, $0.25 with Haiku 5.5.
The first pass takes about 6 s a request (it runs in order), so a long novel takes most of an
hour; `--parallel` scores several books at once.

## Testing

`swift test --filter "LofiAtmosphereTests|LofiScoreHostTests"` (Linux in Docker or the Mac).
The player is tested against `FakeAmbienceBackend` with a manual clock: scenes follow the
narration, places keep their recordings, crowd yield on and off, pauses, muted routes,
headphones pulled, media reset, the level slider. `IntensityTests` covers the dial, the
scene trim and the lift in the gaps; `CatalogTests` the catalogue, the place guide, the
committed `catalog.json`, the prompt and moved kinds. `VariantTests` covers variant ids and
folders, the catalog's spoiler rule, editions, Claude's new variants and moments, and the
narration holds (swell, hush, too early, refused, dropped, setting off). The synth tests check every sound renders
at -23 LUFS and loops without a seam.
