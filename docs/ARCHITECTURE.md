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

| Path                                                                     | What                                                                                            |
| ------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------- |
| `libraries/LofiScoreKit/Sources/LofiAtmosphere`                          | Scene model, catalogue, Claude scorer, track builder, director and player                       |
| `libraries/LofiScoreKit/Sources/LofiScoreHost`                           | App host: settings, finding a book's track, importing the sounds folder, following the narrator |
| `libraries/LofiScoreKit/Sources/LofiAudioCore`                           | Clock, gains, loudness, WAV and other audio basics                                              |
| `libraries/LofiScoreKit/Sources/LofiText`                                | Reads EPUB sentences without looking ahead                                                      |
| `libraries/LofiScoreKit/Sources/lofi-atmosphere`                         | CLI: track, show, score, synth, library, catalog, eval                                          |
| `libraries/LofiScoreKit/Sources/LofiMood`, `LofiEvalCLI`, `LofiTrainCLI` | Mood detection the shelved music used (still built)                                             |
| `libraries/LofiScoreKit/Tools/`                                          | Mac scripts, the fetch script, the eval set, data tools                                         |
| `applications/mobile/modules/lofi-score/`                                | Expo module (Swift and JS binding)                                                              |
| `applications/mobile/lofi/`                                              | React UI: toolbar button, panel, settings, reader follow                                        |
| `applications/mobile/modules/readium/ios/LofiNarratorBridge.swift`       | Hooks on upstream's audiobook player                                                            |
| `applications/web/src/app/api/v2/books/[bookId]/lofi-score/`             | `GET`/`PUT` the book's score                                                                    |
| `tools/fork/`                                                            | Fork checks, sync scripts, `check.sh`                                                           |
| `shelved/lofi-music/`                                                    | The shelved music, not built                                                                    |

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

## Decisions log

| Date       | Decision                                                                         | Why                                 |
| ---------- | -------------------------------------------------------------------------------- | ----------------------------------- |
| 2026-11-09 | Fork code lives in new folders; upstream edits only at marked touch points       | Upstream syncs stay clean           |
| 2026-11-09 | No audio in git; personal (CC BY-NC) and publish (Commons) sound editions        | The repo is public; licences differ |
| 2026-11-10 | Music shelved; ambience is the app's focus                                       | Mo's direction                      |
| 2026-11-10 | Scoring with Claude Opus through the plan, spoiler-safe windows                  | Accuracy; no look-ahead             |
| 2026-11-11 | Bed at -10 dB under the voice, quiet loops boosted up to maxGain 6               | Mo couldn't hear the sounds         |
| 2026-11-11 | Fetch gates on title, loudness range and loudness; poor loops listed as rejected | Drips and room noise slipped in     |
| 2026-11-12 | Score only books Mo names (`Books/wanted.txt`), never the whole library          | Cost; Mo's choice                   |
| 2026-11-14 | Long runs go to GitHub CI from a pushed branch                                   | Mo's choice                         |
| 2026-11-14 | `tools/fork/check.sh` is the one check command                                   | One command for every check         |

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
