# Plan

Done: 2 | Last cleanup: none | Podcasts: plan approved, P1a in progress

v1 is done when the sounds feel right on Mo's phone (TestFlight) for Redwood and
"The Strength of the Few". Each milestone fits in one session. Full checks run
in Fork CI from a pushed branch (Mo's choice); `tools/fork/check.sh` runs them
locally too.

## Milestones

- [x] **1. Make the check command green**
  - Fix the 3 lint errors in fork code: use `@/fork.config.ts` in
    `forkConfig.test.ts`, and replace `console.log` in `asc-preflight.mjs` with
    the allowed output (keep its printed text the same).
  - Done when: `tools/fork/check.sh` ends with "all … steps passed".
  - Try it: run `tools/fork/check.sh --no-swift`.
  - Files: `applications/mobile/modules/lofi-score/forkConfig.test.ts`,
    `tools/fork/asc-preflight.mjs`.

- [x] **2a. Sound check: pick the spots** (engine side)
  - `SoundCheck.spots` picks up to 6 spots from a book's track (a quiet room,
    something loud, outdoors, water, weather, travel, a one-off), spread across
    the book, all ending before the sentence playing now (no spoilers), or
    within the book's opening (first chapter with sounds, or about the first 5
    minutes, whichever is longer) when the user is not far in (Mo, 2026-11-15).
    `SpoilerGuard.clip(atGlobalIndex:)` gives each spot's place in the audio.
  - Done when: `SoundCheckTests` and the clip round-trip test pass.
  - Files: `Sources/LofiAtmosphere/Track/SoundCheck.swift`,
    `Sources/LofiText/Guard/SpoilerGuard.swift`, `EPUB/ReadaloudBook.swift`,
    their tests.

- [ ] **2b. Sound check in the app** (Mo's hearing test, replaces the manual
      one). Status: built and passing `check.sh`; waiting for the iOS build in
      CI and Mo's first run on TestFlight.
  - Host: `soundCheckStops()` for the playing book, limited to the sentence
    playing now, each with its audio clip. Module: `getSoundCheckStops`.
  - App: a "Sound check" button in the sounds panel. For each spot it seeks the
    narration there (`Storyteller.seekTo(audioPath, start)`), checks it landed,
    plays up to 20 s (less when the scene ends), then asks how the main sound
    came through under the voice: Too loud / Clear / Faint / Can't hear / Wrong
    sound, or play it again. Then it puts the narration back where it was (also
    after closing the panel, leaving the app, or the app closing). The last 5
    runs are kept on the phone, and "Share results" copies them as text with
    what played at each stop (recording, gain, route) and the run's settings. It
    was reviewed twice. The second pass added: every jump of the check is told
    to the sounds first (`soundCheckWillJump`), a one-off stop starts 5 s of
    listening ahead at any narration speed and records whether its sound played,
    the screen stays on, and leaving the app leaves the narration paused at the
    listener's place.
  - Test first: JS tests for the session logic (next spot, answers, the results
    text), and a host test for the limit.
  - Done when: check.sh passes, the iOS build passes in CI, and Mo runs it once
    on TestFlight and pastes the results.
  - Try it: open Redwood, tap the sounds button, then Sound check.
  - Files: `LofiScoreHost/LofiAtmosphereHost.swift`,
    `modules/lofi-score/ios/LofiScoreModule.swift`,
    `modules/lofi-score/index.ts`, new `modules/lofi-score/soundCheck.ts` (+
    test), new `modules/lofi-score/soundCheckRunner.ts` (+ test), new
    `lofi/LofiSoundCheck.tsx`, `lofi/LofiAtmosphereControls.tsx`.

- [ ] **2c. Fix the levels from the sound check**
  - From Mo's results, change the `AtmosphereConfig` defaults (with a test),
    then a new build and another sound check. Change the global defaults when
    the same level is off across books; a book whose narrator is much louder or
    quieter than -16 LUFS waits for 2d instead.
  - Done when: at the default settings, main sounds at full or loud are Clear,
    soft ones Clear or Faint, faint ones Faint or Clear, and nothing is Can't
    hear or Too loud.
  - Files: `Player/AmbiencePlayer.swift` (AtmosphereConfig), its tests.

- [ ] **2d. Match each book's narrator loudness** (Mo's choice, 2026-11-15)
  - The sounds sit under a voice assumed to be -16 LUFS. Measure each book's
    narration on the Mac when it is scored, store it in the score, and use it in
    place of the default, so one quiet or loud narrator does not need its own
    settings.
  - Done when: a test shows a book with a -20 LUFS narrator gets its bed 4 dB
    quieter, and Redwood's measured value is in its score.
  - Files: the scoring job (owned by the "Make adding music and atmosphere easy"
    thread), `AtmosphereConfig`, the score format.

- [ ] **2e. Import sounds in the background** (Mo's ask, 2026-11-15) Status:
      built and passing `check.sh`; waiting for the iOS build in CI and Mo's
      next import.
  - The first import of the sounds folder (about 500 recordings, 420 MB from
    iCloud) took too long with the app open. Ask iCloud for every file not yet
    on the phone at the start, so iCloud downloads them all together, even with
    the app closed. Copy the files already on the phone first. When the app goes
    to the background with copying unfinished, ask iOS for a background
    processing task that carries on (iOS picks the time; no charger needed, no
    notification). Settings shows how many files are still downloading from
    iCloud as well as the copy count.
  - Test first: Swift tests that `sync` asks for every missing file's download
    before copying, copies the downloaded files first, reports the count still
    downloading, and stops cleanly when asked to (saving its place); a JS test
    for the label.
  - Done when: check.sh passes, the iOS build passes in CI, and Mo's next import
    finishes after the app was closed during it.
  - Try it: Settings > Atmosphere Sounds, import the folder, close the app, open
    it later and look at the count.
  - Files: `LofiScoreHost/SoundsFolderImport.swift`,
    `LofiScoreHost/LofiAtmosphereHost.swift`,
    `modules/lofi-score/ios/LofiScoreModule.swift` (+ an app delegate
    subscriber), `expo-module.config.json`, `fork.config.ts`,
    `modules/lofi-score/status.ts`, `index.ts`, their tests.

- [ ] **3. A reject list for bad recordings**
  - Add `Tools/atmosphere/reject.txt` (one recording id per line, with a
    reason). The `audit` in `fetch_ambience.py` moves listed ids to `rejected`,
    and the fetch never takes them again. Put fs168470 (room noise in
    River.RunningTap) in it.
  - Test first: a Python test that a listed id ends up under `rejected`, and a
    step for it in `check.sh`.
  - Done when: the test passes in `check.sh`, and a dry-run audit on the Mac
    names fs168470.
  - Try it: double-click the fetch `.command` with the dry-run flag and read its
    output.
  - Files: `libraries/LofiScoreKit/Tools/atmosphere/fetch_ambience.py`,
    `reject.txt`, a new `test_fetch_ambience.py`, `tools/fork/check.sh`.

- [ ] **4. Score "The Strength of the Few"**
  - List it in `~/Storyteller Lofi/Books/wanted.txt` and let the Mac job score
    it, after any running sound fetch has finished. Check the track with
    `atmosphere_stats.py` (places, changes per hour).
  - Done when: its score is on the server and the phone panel shows places while
    it plays.
  - Try it: open the book on the phone, play, and watch the panel.
  - Files: none in git (Mac only). Coordinate with the "Make adding music and
    atmosphere easy" thread, which owns `lofi-sync.sh`.

- [ ] **5. Record the scorer's accuracy baseline**
  - Run `lofi-atmosphere eval` on the current prompt against
    `Tools/atmosphere/eval/cases.jsonl` (costs a few dollars, so ask Mo first).
    Write the per-check scores into the "Scoring accuracy" section of
    `Docs/Atmosphere.md`.
  - Done when: the numbers and prompt version are committed.
  - Try it: read the table in `Docs/Atmosphere.md`.
  - Files: `libraries/LofiScoreKit/Docs/Atmosphere.md`.

- [ ] **6. Improve the weakest matching check**
  - Pick the lowest check from milestone 5 and make one prompt or catalogue
    change for it. Re-run the eval (ask Mo first).
  - Done when: that check improves and no other drops by more than 2 points.
  - Try it: compare the two eval tables.
  - Files: `Sources/LofiAtmosphere/Claude/ClaudeScenePrompt.swift` or
    `Scene/SoundCatalog.swift`, plus the doc table.

- [ ] **7. Ship v1 to the phone**
  - Merge everything into main (Mo's OK), get a TestFlight build, and re-score
    Redwood if the prompt changed (ask about cost). Mo listens to both books.
  - Done when: Mo says both books sound right on the new build.
  - Try it: install the build from TestFlight and play both books.
  - Files: none beyond what's merged.

## Podcasts

Mo's ask (2026-11-16): a Podcasts section beside Books with ads skipped on the
phone. Design, risks and Mo's answers are in `docs/PODCASTS-PLAN.md`. Mo
approved the plan on 2026-11-16. These milestones do not wait for the sound
milestones above. Mo's way of working here: Opus 5.5 plans and checks, Sonnet
writes the code.

- [ ] **P1a. Podcasts section: subscribe and browse** Status: built and passing
      `check.sh`; waiting for the iOS build in CI and Mo's first run on
      TestFlight.
  - A menu button at the top left of the Books screen opens a side menu with
    Books and Podcasts. Podcasts lists the shows; "Add" searches Apple's free
    podcast directory or takes an RSS link; a show's page lists its episodes,
    newest first, with date, length and notes.
  - Feeds are read in Swift (`PodcastKit`, Foundation's XML parser) through a
    new Expo module, and kept in a podcasts-only SQLite file. No new JavaScript
    packages; the books database is not touched.
  - Test first: Swift tests reading saved sample feeds (iTunes tags, the three
    duration formats, missing GUIDs, HTML notes, a broken feed); JS tests for
    adding a show twice, refreshing without duplicates, and directory results.
  - Done when: check.sh passes with the new package's tests, the iOS build
    passes in CI, and on TestFlight Mo adds a show by search and by link and
    sees its episodes.
  - Try it: Books, menu (top left), Podcasts, Add, search for a show.
  - Files: new `libraries/PodcastKit` (package, feed target, tests, podspec),
    new `modules/podcasts`, new `podcasts/`, new `app/(root)/podcasts/`,
    `app/(root)/index.tsx` (new touch point), `fork.config.ts`,
    `tools/fork/touchpoints.json`, `check.sh`, `fork-ci.yml`, `testflight.yml`.

- [ ] **P1b. Play an episode**
  - A Swift player in `modules/podcasts` streams an episode: play and pause,
    back 15 s and ahead 30 s, a seek bar, speed (0.8x to 3x), the place kept per
    episode, a player screen and a mini player on the Podcasts screens.
  - Lock screen and headphone buttons control the podcast while it is the active
    player. Starting a podcast pauses the book; starting the book pauses the
    podcast. The book's lock-screen handlers stand aside while a podcast plays
    (new markers in `AudiobookPlayerActor.swift`).
  - Test first: Swift tests for the player's rules (resume place, marking an
    episode played near its end, who owns the lock screen); JS tests for the
    player screen's state.
  - Done when: check.sh passes, the iOS build passes in CI, and on TestFlight a
    podcast plays from the lock screen, and switching between a book and a
    podcast never plays both.
  - Try it: play an episode, lock the phone, use the lock-screen buttons, then
    start a book.
  - Files: `modules/podcasts/ios/*`, `podcasts/` player screens,
    `modules/readium/ios/AudiobookPlayerActor.swift`,
    `tools/fork/touchpoints.json`.

- [ ] **P2a. Download episodes**
  - Download and delete buttons per episode. Downloads use a background session,
    so they finish with the app closed. A downloaded episode plays from the
    file. Each file's SHA-256 becomes its identity.
  - Test first: Swift tests for download bookkeeping (resume after a restart,
    the hash, deleting a file and its side files).
  - Done when: check.sh passes, the iOS build passes in CI, and on TestFlight an
    episode downloaded with the app closed plays in airplane mode.
  - Files: `modules/podcasts/ios` (downloads), `PodcastKit` (file store),
    `podcasts/` (buttons, storage used).

- [ ] **P2b. Up Next**
  - Add to Up Next, play next, reorder and remove. The queue lives in Swift, so
    the next episode starts when one ends, even with the screen locked.
  - Test first: Swift tests for the queue rules (end of episode, removing the
    playing one, a missing file); a JS test for the screen's list.
  - Done when: check.sh passes, the iOS build passes in CI, and on TestFlight
    the next episode starts by itself with the phone locked.
  - Files: `PodcastKit` (queue), `modules/podcasts/ios`, `podcasts/`.

- [ ] **P2c. New episodes by themselves**
  - Feeds refresh when the app opens and in a background refresh task. Each show
    can download its newest episode by itself (Mo's answer to question 4), and
    played downloads are deleted after a day.
  - Test first: Swift or JS tests for what to download and what to delete.
  - Done when: check.sh passes, the iOS build passes in CI, and on TestFlight a
    new episode appears and downloads without opening its show.
  - Files: `modules/podcasts/ios` (background task, like
    `LofiBackgroundImport.swift`), `fork.config.ts` (task id, background fetch),
    `podcasts/` (settings).

- [ ] **P3a. Transcribe downloaded episodes**
  - After a download, `SpeechTranscriber` (with time ranges) writes the episode
    out in the feed's language, while the app is open or playing. It asks iOS
    for the speech model the first time. Saved as `<sha256>.transcript.json`.
    The episode row shows the progress.
  - A Mac `.command` transcribes an audio file with the same Swift code, for
    checks without a new build.
  - Test first: Linux tests for the transcript format and storage (built from a
    fake recogniser); the Apple-only wrapper builds in Fork CI.
  - Done when: check.sh passes, the iOS build passes in CI, the Mac command
    transcribes an episode, and on TestFlight an hour-long episode is
    transcribed (the time it takes is written down here).
  - Files: `PodcastKit` (transcript model, speech target), `modules/podcasts`,
    `podcasts/` (row status), `PodcastKit/Tools/mac`.

- [ ] **P3b. Transcribe with the app closed**
  - A background processing task carries on unfinished transcription and resumes
    where it stopped. Episodes in an unsupported language are marked and
    skipped.
  - Test first: Swift tests for the resume rules.
  - Done when: check.sh passes, the iOS build passes in CI, and on TestFlight an
    episode downloaded before bed is transcribed by morning.
  - Files: `modules/podcasts/ios`, `fork.config.ts` (task id).

- [ ] **P4a. Find ads** (engine)
  - The `AdDetector` interface, the chunker (pieces to the detector's token
    budget, 2 minutes of overlap), the on-device detector (Foundation Models,
    numbered lines in, line ranges out, each marked an ad or the hosts' own
    plug), the clean-up rules and the `<sha256>.ads.<detector>.json` file, as in
    `docs/PODCASTS-PLAN.md`.
  - A Mac `.command` finds the ads in a transcribed episode and prints them
    (needs Apple Intelligence on the Mac).
  - Test first: Linux tests with a fake detector: pieces fit the budget and
    overlap, an ad across a cut is found once, short and long ranges are
    dropped, edges snap to pauses, results load for the same file only.
  - Done when: check.sh passes, the Apple-only detector builds in Fork CI, and
    the Mac command lists the ads in 3 episodes Mo picks.
  - Files: `PodcastKit` (ads target, on-device target, tests),
    `PodcastKit/Tools/mac`.

- [ ] **P4b. Find ads on the phone**
  - After transcription, the app finds the ads while it is open, playing, or in
    a background task that waits for the charger. The row shows "Finding ads",
    "3 ads found" or why not (Apple Intelligence off, model downloading). Each
    episode has an "Ads found" list with a play button per ad.
  - Test first: tests for the status rules (when to run, which reason to show).
  - Done when: check.sh passes, the iOS build passes in CI, and on TestFlight
    the phone finds ads in an episode (the time it takes is written down here).
  - Files: `modules/podcasts/ios`, `podcasts/` (row, ads list, settings).

- [ ] **P4c. Skip ads in the player**
  - The Swift player skips each saved ad when playback reaches it (not when the
    listener seeks into it), also with the screen locked. The app shows "Skipped
    ad (1:05)" with Undo for 6 seconds; Undo goes back to the ad's start, plays
    it, and records the skip as wrong. Ads show on the seek bar. Two switches,
    "Skip ads" and "Skip the hosts' own plugs" (both on by default), in Settings
    and per show.
  - Test first: Swift tests for the skip rules (reaching an ad, seeking into
    one, Undo, speed changes, an ad at the very end, a plug with its switch
    off); a JS test for the note.
  - Done when: check.sh passes, the iOS build passes in CI, and on 3 episodes Mo
    picks most ads (4 in 5) are skipped and at most one skip cuts the show.
  - Try it: play a downloaded episode with ads found and wait for the first ad.
  - Files: `PodcastKit` (skip rules), `modules/podcasts/ios` (player),
    `podcasts/` (note, seek bar, switches).

## Later

- Run lint (`oxlint` on fork paths) in Fork CI too.
- Split the big Swift files (`AmbienceSynth`, `AmbiencePlayer`,
  `LofiAtmosphereHost`).
- Stop building the mood code while the music is shelved.
- Give the fork its own app icon before sharing it with anyone.
- A publish edition and the App Store (see `FORK.md` and the publishing notes).
- Bring the music back (`shelved/lofi-music/README.md`).
- Podcasts: Apple's cloud model and Claude Haiku as other ad detectors, a Mac
  command comparing detectors, OPML import, sleep timer, chapters, CarPlay (see
  `docs/PODCASTS-PLAN.md`).
