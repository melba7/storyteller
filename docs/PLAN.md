# Plan

Done: 0 | Last cleanup: none

v1 is done when the sounds feel right on Mo's phone (TestFlight) for Redwood and
"The Strength of the Few". Each milestone fits in one session. Full checks run
in Fork CI from a pushed branch (Mo's choice); `tools/fork/check.sh` runs them
locally too.

## Milestones

- [ ] **1. Make the check command green**
  - Fix the 3 lint errors in fork code: use `@/fork.config.ts` in
    `forkConfig.test.ts`, and replace `console.log` in `asc-preflight.mjs` with
    the allowed output (keep its printed text the same).
  - Done when: `tools/fork/check.sh` ends with "all … steps passed".
  - Try it: run `tools/fork/check.sh --no-swift`.
  - Files: `applications/mobile/modules/lofi-score/forkConfig.test.ts`,
    `tools/fork/asc-preflight.mjs`.

- [ ] **2. Confirm the sounds are loud enough on the phone** (riskiest unknown)
  - Check that TestFlight has a build containing main's level changes (PR #27
    and #28). If it doesn't, push to main for a build (Mo's OK needed). Give Mo
    a 3-spot listening check: Redwood Prologue 2:27 (running water), ch5 18:35
    (train), ch6 30:19 (crowd), at default sliders.
  - If they're too quiet, change `AtmosphereConfig` levels using the measured
    narrator loudness (-15 to -16 LUFS), with a test on the new defaults.
  - Done when: Mo says all three are audible at the default settings.
  - Try it: play those spots with headphones and with the speaker.
  - Files:
    `libraries/LofiScoreKit/Sources/LofiAtmosphere/Player/AmbiencePlayer.swift`
    (AtmosphereConfig), its tests.

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

## Later

- Run lint (`oxlint` on fork paths) in Fork CI too.
- Split the big Swift files (`AmbienceSynth`, `AmbiencePlayer`,
  `LofiAtmosphereHost`).
- Stop building the mood code while the music is shelved.
- Give the fork its own app icon before sharing it with anyone.
- A publish edition and the App Store (see `FORK.md` and the publishing notes).
- Bring the music back (`shelved/lofi-music/README.md`).
