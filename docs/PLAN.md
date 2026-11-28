# Plan

Done: 2 | Last cleanup: none | Podcasts: P1 to P6b, the bug check and the design
(D1 to D5) merged (TestFlight 27.1); the Apple Podcasts sync fix, R1 to R8 from
Mo's first try, the Apple Podcasts redesign (A1 to A6) and a second bug check
(B2) merged in PR #48 (TestFlight 29.1, with the Books look) | Books look: B1 to
B7 merged (PR #49), B8 (look check) next | Covers and more lists: C0 to C9 and
C12 done, Spotify dropped; Mo's 29.1 bugs fixed; ad skipping I0 to I2 and the
iPhone Duo fit done (PR #51); I3 waits on Mo's Mac test | Ad skipping accuracy
(start and end, two Fable plans, built by Sonnet, checked twice by Opus): all
milestones built (PR #52, TestFlight 31.1) | Player, ads and smoothness (S1 to
S15, from Mo's 31.1 report): all built and checked, waiting on the iOS build and
the phone | The Mac teaches, the phone skips alone (T1 to T9, Mo's ask
2026-11-22): all built, checked by Opus and fixed (PR #54); waiting on Mo's
first teaching run, the merge and the phone (TestFlight 33.1) | The phone learns
by itself (U1 to U11, Mo's ask 2026-11-23): all built, checked by Opus and fixed
(PR #55, whole check green); waiting on the Fable final check, the merge and the
TestFlight build | Ad skipping to 95%, round A (V1 to V8, Mo's ask 2026-11-23):
V1 to V7 built, checked by Opus and fixed (PR #56 merged, TestFlight 35.1); on
the 63 shelf episodes 125 of 219 ad breaks pass Mo's bar (was 101) with 13 skips
where there is no ad (was 75); waiting on Mo's double-click on the Mac for the
run and the exam (V8) | Timing fixes and the skip tap (X1 to X6, Mo's ask
2026-11-26): X1 to X6 done (PR #58 merged, TestFlight 37.1; Mo taught the phone
again on 2026-11-27); on the shelf 152 of 219 breaks pass (was 142), 138 of 222
with the exact labels (was 129); X7 (one tap leaves the whole break) merged (PR
#60), shipped in TestFlight 39.1 | Prepared episodes (Y1 to Y8, Mo's pick
2026-11-27): all done (PR #61 merged, TestFlight 39.1, the hourly job installed
on Mo's Mac 2026-11-28); the phone's folder link fixed (PR #62, TestFlight 40.1;
the phone's first files reached the Mac 2026-11-28) | After prepared episodes
(Z1 to Z23, Mo's picks 2026-11-28): part 1, the map and the ad-end check built
and checked three times (PR #63); the Mac's tests run by themselves after the
merge

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

## The Apple look for Books

Mo's ask (2026-11-17): give everything outside Podcasts the Apple Podcasts look,
with no feature changes. Mo chose "Every Books screen". The plan, the colours
and the screen-by-screen table are in `docs/BOOKS-APPLE-DESIGN.md`. One pull
request with all of it, merged before PR #48, then one TestFlight build carries
both.

- [x] **B1. Colours and font.** Apple's colours in `global.css`, headings in the
      system font.
- [x] **B2. Shared pieces and Home.**
- [x] **B3. Book page.**
- [x] **B4. Grids and search.**
- [x] **B5. Settings and sheets.**
- [x] **B6. Players.**
- [x] **B7. Reader chrome.**
- [ ] **B8. Look check.** Every screen against the table and Mo's screenshots,
      the iOS build in CI, then Mo's look on TestFlight.
  - Done when: `tools/fork/check.sh` passes, every restyled upstream file is in
    `allowedChanges`, the iOS build passes, and a review of the diff finds no
    handler, menu item, label or screen removed.
  - Try it: install the TestFlight build and open Books, a book, Settings, the
    player and the reader in light and dark.

## Podcasts

Mo's ask (2026-11-16): a Podcasts section beside Books with ads skipped on the
phone. Design, risks and Mo's answers are in `docs/PODCASTS-PLAN.md`. Mo
approved the plan on 2026-11-16. These milestones do not wait for the sound
milestones above. Mo's way of working here: Opus 5.5 plans and checks, Sonnet
writes the code. Since 2026-11-17 the section follows Pocket Casts' look and
features (Mo's ask; reference only, see "Matching Pocket Casts" in
`docs/PODCASTS-PLAN.md`). Mo gave a standing OK (2026-11-17) to merge these PRs
once reviewed and green.

- [ ] **P1a. Podcasts section: subscribe and browse** Status: merged into main
      on 2026-11-16 (PR #37; the iOS build passed on an Intel Mac); in
      TestFlight build 20.1, waiting for Mo's first run.
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
    back 10 s and ahead 45 s (Pocket Casts' defaults), a seek bar, speed 0.5x to
    3x in 0.1 steps, and the place kept per episode.
  - The full-screen player is laid out like Pocket Casts': large artwork, the
    background tinted with the artwork's main colour (worked out in Swift and
    kept per show), title and show, the seek bar with time played and time left,
    the big play button between the skip buttons, and the speed button. Show
    notes sit below. A mini player at the bottom of the Podcasts screens shows
    the artwork, title, time left and play button, and opens the player.
  - Lock screen and headphone buttons control the podcast while it is the active
    player. Starting a podcast pauses the book; starting the book pauses the
    podcast. The book's lock-screen handlers stand aside while a podcast plays
    (new markers in `AudiobookPlayerActor.swift`).
  - Many episode links are plain http, which iOS blocks by default: set
    `NSAllowsArbitraryLoadsForMedia` in the Info.plist through `fork.config.ts`
    (a plist key, not an entitlement). P1a's feed fetch already tries https
    first.
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
  - Status: merged into main on 2026-11-17 (PR #40); in TestFlight build 20.1,
    waiting for Mo's first run.

- [ ] **P1c. Tabs and the library grid** (Mo's ask, 2026-11-17; the Pocket Casts
      layout, part 1 of 3)
  - The Podcasts section gets a bottom tab bar like Pocket Casts': Podcasts and
    Discover to start. Each tab joins with the feature that fills it, so no tab
    is ever empty: Profile with P2a (Downloads), Up Next with P2b, Playlists
    with P5d. Use expo-router's native iOS tabs (`expo-router/native-tabs`, the
    iOS 26 glass bar, no new package), each tab with its own stack so a show's
    page keeps the bar. The mini player sits in the tab bar's accessory slot
    (`NativeTabs.BottomAccessory`), as in Pocket Casts.
  - Podcasts tab: a grid of artwork (large grid, small grid or list) with a
    badge for unplayed episodes, sorted by name, date added or newest episode.
    The layout and the order are picked from a menu in the top bar and kept on
    the phone. The side menu button stays at the top left; the add button opens
    Discover.
  - Discover tab: the directory search and RSS link from today's Add screen,
    which it replaces. P1d adds the charts below the search.
  - The badge counts the unplayed episodes released since you followed the show,
    plus the newest episode if it is unplayed (so a show you just followed shows
    1), shown as "99+" past 99.
  - Own icons (SF Symbols for the tabs, lucide in the screens) and colours:
    nothing is copied from Pocket Casts.
  - Test first: JS tests for the three orders, the badge count and the saved
    layout choice.
  - Done when: check.sh passes, the iOS build passes in CI, and on TestFlight
    the two tabs, the three layouts, the orders, the badges and the mini player
    above the tabs work.
  - Try it: Podcasts, the menu at the top right, then Discover.
  - Files: `app/(root)/podcasts/` (the tab and stack layouts and routes),
    `podcasts/` (grid, Discover, mini player), `modules/podcasts/library.ts` and
    `db.ts` (orders and counts, with tests).
  - Status: built and passing `check.sh`; waiting for the iOS build in CI.

- [ ] **P1c2. A show's page and the episode card** (part 2 of 3)
  - A show's page: a large header (artwork, title, author, Follow or Following,
    a description that expands), then episode rows with date, title, length or
    time left, a play button with a progress ring, and played episodes dimmed.
  - An episode opens as a card (a sheet): artwork, title, date, length, play,
    and notes with working links.
  - Test first: JS tests for the row states (unplayed, in progress, played) and
    the ring's fraction.
  - Done when: check.sh passes, the iOS build passes in CI, and on TestFlight a
    show's page and the episode card look and work as described.
  - Files: `podcasts/` (show page, episode card, progress ring),
    `app/(root)/podcasts/` (the card's route).
  - Status: built and passing `check.sh`; waiting for the iOS build in CI.

- [ ] **P1c3. Your own order** (part 3 of 3)
  - A fourth order for the Podcasts tab: your own, set by dragging artwork in
    the grid or rows in the list, kept in `podcasts.db` (version 3).
  - Test first: JS tests for moving a show and for new shows going last.
  - Done when: check.sh passes, the iOS build passes in CI, and on TestFlight a
    dragged order stays after a restart.
  - Files: `podcasts/` (the grid), `modules/podcasts` (`schema.ts`, `db.ts`,
    `library.ts`).
  - Status: built and passing `check.sh`; waiting for the iOS build in CI.
    Dragging is on a separate Arrange screen (a handle on each row, plus
    VoiceOver Move up and Move down), not in the grid itself.

- [ ] **P1d. Discover** (Mo's ask, 2026-11-16, planned as "Explore")
  - The Discover tab shows Apple's free US top chart, Apple's main categories
    (each with its own top chart), and "For you".
  - "For you" takes the categories of the shows you follow (each feed's
    `itunes:category`), most common first, and lists the top shows in up to
    three of them, leaving out shows you already follow. Each one says "Because
    you follow" and names one of your shows in that category.
  - Tapping a show opens a preview: picture, notes and episodes read from its
    feed without saving it, a Follow button, and Play (P1b's player; the place
    is kept only once you follow). Search results in Add open this preview too,
    instead of following at once.
  - The charts are fetched when Discover opens and kept for a day. Chart entries
    carry Apple ids, not feeds, so one lookup call
    (`https://itunes.apple.com/lookup?id=<ids>`) gets their feed links.
  - The feed reader keeps each show's categories. `podcasts.db` goes to version
    4 (P1b and P1c3 took 2 and 3), upgraded in place: a categories column on
    shows and a small cache table. Shows followed before get their categories at
    their next refresh.
  - The cloud can't reach Apple's chart addresses, so the tests use saved
    answers and the first build tries them on the phone. Overall:
    `https://rss.marketingtools.apple.com/api/v2/us/podcasts/top/50/podcasts.json`.
    Per category:
    `https://itunes.apple.com/us/rss/toppodcasts/limit=50/genre=<id>/json`.
  - Test first: Swift tests for categories in sample feeds (nested, missing); JS
    tests reading both chart answers and the lookup, the category list, "For
    you" (most common categories first, followed shows left out, the "because"
    show) and the one-day cache.
  - Done when: check.sh passes, the iOS build passes in CI, and on TestFlight Mo
    opens Discover, browses a category, sees suggestions from the shows already
    followed, and follows one from its preview.
  - Try it: Podcasts, Discover.
  - Files: `PodcastKit` (categories), `modules/podcasts` (`charts.ts`,
    `categories.ts`, `db.ts` version 4, with tests), `podcasts/` (Discover, show
    preview, `AddPodcast.tsx`), `app/(root)/podcasts/` (discover and preview
    routes).
  - Status: built and passing `check.sh`; waiting for the iOS build in CI and
    for the chart addresses to be tried on the phone.

- [ ] **P1e. Search episodes** (Mo's ask, 2026-11-16)
  - Search on the Podcasts screen has two tabs. "Your shows" finds episodes of
    the shows you follow by words in the title or show notes, on the phone (it
    works offline), title matches first, then newest. "All podcasts" uses
    Apple's free episode search
    (`https://itunes.apple.com/search?media=podcast&entity=podcastEpisode&term=`).
  - A result from your shows opens the episode. A result from all podcasts opens
    its show's preview (P1d) at that episode, found by guid or else by its audio
    link, where it can be played.
  - Test first: JS tests for the search words (`%` and `_` taken literally,
    every word required), the order of results, and reading Apple's episode
    answer (saved).
  - Done when: check.sh passes, the iOS build passes in CI, and on TestFlight Mo
    finds an episode of a followed show by a word in its notes, and plays an
    episode found in all podcasts.
  - Try it: Podcasts, Search.
  - Files: `modules/podcasts` (`search.ts`, `directory.ts`, `db.ts`, with
    tests), `podcasts/` (search screen, `PodcastsHome.tsx`),
    `app/(root)/podcasts/search.tsx`.
  - Status: built and passing `check.sh`; waiting for the iOS build in CI. The
    search is a button in the Podcasts top bar (`(tabs)/(library)/search.tsx`).
    The saved Apple answer for the episode search is hand-written.

- [ ] **P2a. Download episodes**
  - Download and delete buttons per episode. Downloads use a background session,
    so they finish with the app closed. A downloaded episode plays from the
    file. Each file's SHA-256 becomes its identity.
  - Like Pocket Casts: a Downloads list in Profile with the storage used,
    "Download only on Wi-Fi", and the download state on each episode row.
  - Test first: Swift tests for download bookkeeping (resume after a restart,
    the hash, deleting a file and its side files).
  - Done when: check.sh passes, the iOS build passes in CI, and on TestFlight an
    episode downloaded with the app closed plays in airplane mode.
  - Files: `modules/podcasts/ios` (downloads), `PodcastKit` (file store),
    `podcasts/` (buttons, storage used).
  - Status: built and passing `check.sh`; waiting for the iOS build in CI. After
    a swipe-away in the app switcher the downloads continue the next time the
    app opens, because iOS stops them until then; left or locked, they carry on
    by themselves. Wi-Fi only is off by default. Not tried on a phone yet: a
    download with the app closed, a swipe-away and resume, airplane-mode
    playback.

- [ ] **P2b. Up Next**
  - Add to Up Next, play next, reorder and remove. The queue lives in Swift, so
    the next episode starts when one ends, even with the screen locked.
  - Like Pocket Casts: Up Next becomes a tab with the number of episodes on it,
    with swipe actions (play next, play last, remove), drag to reorder, and
    "Clear Up Next".
  - Test first: Swift tests for the queue rules (end of episode, removing the
    playing one, a missing file); a JS test for the screen's list.
  - Done when: check.sh passes, the iOS build passes in CI, and on TestFlight
    the next episode starts by itself with the phone locked.
  - Files: `PodcastKit` (queue), `modules/podcasts/ios`, `podcasts/`.
  - Status: built and passing `check.sh`; waiting for the iOS build in CI. The
    queue is saved by Swift in `Application Support/Podcasts/up-next.json`; when
    an episode ends Swift starts the next one itself and JS follows along
    (`onPlaybackAdvanced`). Not tried on a phone yet: the next episode with the
    screen locked, swipe actions and drag to reorder.

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
  - Status: built and passing `check.sh`; waiting for the iOS build in CI. It
    ran as JavaScript, not Swift: `modules/podcasts/background.ts` defines an
    `expo-background-task` task (imported from `store/store.ts`, a second marker
    there) and refreshes when the app comes to the front, at most every 30
    minutes. New episodes download by themselves (newest per show, on Wi-Fi
    only, whatever the Wi-Fi switch says); played downloads go a day after they
    were played, never the one loaded in the player. Both are switches in
    Profile, on by default. iOS decides when the background task runs (often
    overnight), so "a new episode appears without opening the app" can only be
    checked over a night.

- [ ] **P2d. Apple Podcasts share links** (Mo's choice, 2026-11-16)
  - Add also takes a link copied from Apple Podcasts
    (`https://podcasts.apple.com/.../id<number>`, with or without an episode
    `?i=`). The app asks Apple's free lookup
    (`https://itunes.apple.com/lookup?id=<number>&entity=podcast`) for the feed
    and subscribes to it.
  - Test first: JS tests reading the id from show and episode links in different
    countries, rejecting other links, and reading the lookup's answer.
  - Done when: check.sh passes, the iOS build passes in CI, and on TestFlight a
    link shared from Apple Podcasts adds that show.
  - Files: `modules/podcasts/directory.ts` (+ test), `podcasts/AddPodcast.tsx`.
  - Status: built and passing `check.sh`; waiting for the iOS build in CI. The
    link field in Discover takes an Apple Podcasts link or an RSS link ("Paste a
    link"). A link with `?i=` opens that episode's card over the show when the
    feed has it (matched through Apple's episode lookup), else the show. No
    "paste from clipboard" button: `expo-clipboard` is not an app dependency,
    and the brief said to skip it then.

- [ ] **P2e. Follow Apple Podcasts from the Mac** (Mo's choice, 2026-11-16)
  - One way only, from Apple Podcasts to Storyteller. An hourly launchd job on
    the Mac copies Apple Podcasts' library file
    (`~/Library/Group Containers/243LU875E5.groups.com.apple.podcasts/Documents/MTLibrary.sqlite`),
    reads the followed shows (feed links) and the finished episodes (guids) from
    the copy, and writes `Podcasts/apple-podcasts.json` into `LofiMusic` and its
    iCloud copy. It never writes to Apple's files.
  - The phone reads that file through the sounds folder link it already has (no
    new setup), when the app opens and in P2c's background refresh. It
    subscribes to shows it has not seen in the file before and marks finished
    episodes as played, so they are not downloaded. A show unfollowed in Apple
    Podcasts stays; a show unsubscribed in Storyteller is not added again.
  - Mo installs the job once with a double-clickable `.command` (the Mac's auto
    mode refuses scripts) and allows the macOS prompt to read Apple Podcasts'
    data.
  - Test first: Python tests on a small library file built in the test (shows,
    finished episodes, a missing column says what changed in Apple's format); JS
    tests for what the phone adds and marks (seen shows, unsubscribed shows,
    unknown guids).
  - Done when: check.sh passes, the iOS build passes in CI, the Mac job writes
    the file from Mo's real library, and a show followed in Apple Podcasts
    appears in Storyteller within the hour.
  - Files: new `libraries/PodcastKit/Tools/mac/` (export script, launchd
    installer, `.command` files, README), `modules/podcasts` (reading the file,
    with tests), `LofiScoreHost` or `modules/lofi-score` (handing over the
    linked folder), `tools/fork/check.sh` (the Python tests).
  - Status: built and passing `check.sh`; the Mac job has not run on a real Mac
    and the iOS build has not run yet. Mo's one-time Mac step: double-click
    `Install Apple Podcasts sync.command` in `libraries/PodcastKit/Tools/mac/`
    and allow the macOS prompt (or add `/bin/bash` to Full Disk Access; the
    README says where). The names of Apple's tables and columns come from other
    tools that read the same file, not from Mo's Mac, so the first run is the
    real test: if Apple's format differs, the script says which name is missing.
    The phone reads the file on every app open and in the background refresh;
    the first read subscribes to everything followed but downloads nothing.
    First real run on Mo's Mac (2026-11-17): 64 followed shows, but 0 finished
    episodes, because `ZHASBEENPLAYED` is empty in today's library. Finished
    episodes now come from `ZPLAYSTATE` with a sign of listening. The phone did
    not add the shows within a few minutes; that is being looked into.

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
  - Status: built and passing `check.sh`; the Apple-only part has never been
    compiled (Fork CI's macOS and iOS builds are its first compile) and nothing
    has run on a Mac or iPhone. Transcribing runs in pieces of 5 minutes, one
    episode at a time, while the app is open or a podcast plays; it needs iOS 26
    (older iOS says "Needs iOS 26"). Rows say "Transcribing 40%", "Transcript
    ready" or the reason. `Transcribe an episode.command` in
    `libraries/PodcastKit/Tools/mac` does one file on a Mac. How long an
    hour-long episode takes on the phone is not measured: that needs TestFlight,
    and the number goes here once Mo has it.

- [ ] **P3b. Transcribe with the app closed**
  - A background processing task carries on unfinished transcription and resumes
    where it stopped. Episodes in an unsupported language are marked and
    skipped.
  - Test first: Swift tests for the resume rules.
  - Done when: check.sh passes, the iOS build passes in CI, and on TestFlight an
    episode downloaded before bed is transcribed by morning.
  - Files: `modules/podcasts/ios`, `fork.config.ts` (task id).
  - Status: built with P3a, passing `check.sh` and not yet run on a phone. The
    resume rules are tested on Linux with a fake recogniser (a stop after any
    piece, a restart 2 s before the saved time, a broken partial file starting
    over). The app asks iOS for the background task
    `<bundle id>.podcastTranscribe` when it goes to the background with work
    left; iOS decides when it runs (often overnight, on the charger), so
    "transcribed by morning" is for Mo to check on TestFlight. When iOS ends a
    turn, the piece in progress is finished and saved first, so a very slow
    piece can still be cut off by iOS; only that piece is lost.

- [ ] **P3c. Moving transcript** (Mo's ask, 2026-11-17; replaces the old P5p)
  - Like the books' read-along: the player shows the episode's transcript. It
    scrolls with the audio, highlights the line playing now, and plays from a
    line when you tap it. You can search in it.
  - The feed's own transcript (`podcast:transcript`, as WebVTT, SRT or JSON) is
    used when there is one, so it also works while streaming. Otherwise the
    on-device transcript from P3a is used. Without either, the player says why.
  - Test first: tests reading WebVTT, SRT and JSON transcripts (times, speakers,
    a broken file), choosing the source, and finding the line playing at a given
    time.
  - Done when: check.sh passes, the iOS build passes in CI, and on TestFlight
    the transcript follows a playing episode and a tap on a line plays from
    there.
  - Files: `PodcastKit` (the feed's `podcast:transcript` tag),
    `modules/podcasts` (transcript readers, with tests, adapted from
    Transcriptator, MIT), `podcasts/` (the transcript in the player).
  - Status: built and passing `check.sh`; not yet compiled in CI or run on a
    phone. The feed's `podcast:transcript` tags are read in PodcastKit; the best
    one per episode (JSON, then WebVTT, SRT, HTML; plain text skipped) is kept
    in `podcasts.db` (schema version 5) and filled at the next refresh for
    episodes saved before. Transcriptator was read: its WebVTT, SRT and JSON
    readers need no packages, but its HTML reader needs `node-html-parser`, so
    only its time reading is adapted (`transcriptFormats/timestamp.ts`, notice
    in `FORK.md`) and the readers are written for the fork. HTML transcripts are
    not read yet: the screen says so and uses the phone's own transcript when
    there is one. The player screen has a "Transcript" button: a full-height
    list that follows the playing line (about a third from the top), stops
    following when scrolled by hand ("Follow along" brings it back), plays from
    a tapped line, shows speakers when they change, and searches with next and
    previous. The feed's file is fetched when the transcript opens and cached
    for a week. Plain `http` transcript links may be blocked by iOS (the app's
    exception covers media, not `fetch`); the screen then says it can't load it.

- [ ] **P4a. Find ads** (engine)
  - The `AdDetector` interface, the chunker (pieces to the detector's token
    budget, 2 minutes of overlap), the on-device detector (Foundation Models,
    numbered lines in, line ranges out, each marked an ad or the hosts' own
    plug, with how sure it is), the clean-up rules (adapted from MinusPod, MIT)
    and the `<sha256>.ads.<detector>.json` file, as in `docs/PODCASTS-PLAN.md`.
  - A Mac `.command` finds the ads in a transcribed episode and prints them
    (needs Apple Intelligence on the Mac).
  - Test first: Linux tests with a fake detector: pieces fit the budget and
    overlap, an ad across a cut is found once, short and long ranges are
    dropped, edges snap to pauses, results load for the same file only.
  - Done when: check.sh passes, the Apple-only detector builds in Fork CI, and
    the Mac command lists the ads in 3 episodes Mo picks.
  - Files: `PodcastKit` (ads target, on-device target, tests),
    `PodcastKit/Tools/mac`.
  - Status: built; the Linux tests pass. The Foundation Models detector is
    compiled for the first time in Fork CI. Still open: the Mac command on 3
    episodes Mo picks. MinusPod's rules (12 s of speech, 5 minutes, carrying the
    end on) and part of MinusPod's and Podly's wording are credited in
    `FORK.md`.

- [ ] **P4b. Find ads on the phone**
  - After transcription, the app finds the ads while it is open, playing, or in
    a background task that waits for the charger. The row shows "Finding ads",
    "3 ads found" or why not (Apple Intelligence off, model downloading). Each
    episode has an "Ads found" list with a play button per ad.
  - Test first: tests for the status rules (when to run, which reason to show).
  - Done when: check.sh passes, the iOS build passes in CI, and on TestFlight
    the phone finds ads in an episode (the time it takes is written down here).
  - Files: `modules/podcasts/ios`, `podcasts/` (row, ads list, settings).
  - Status: built and passing `check.sh`. Still open: the iOS build in CI and
    the time it takes on the phone. Finding ads waits for the charger in the
    background (`<bundle id>.podcastAds`); a failed run is not retried until the
    app opens again.

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
  - Status: built and passing `check.sh`. Still open: the iOS build in CI and
    the TestFlight check on 3 episodes. Only "sure" ads are skipped; a show's
    own switches (P5a) win over the ones in Profile.

### Pocket Casts features (Mo's ask, 2026-11-17)

The rest of Pocket Casts' features, one session each, after ad skipping (P3-P4;
Mo's choice, 2026-11-17). Each step's "done when" is: check.sh passes, the iOS
build passes in CI, and the behaviour named works on TestFlight. Each one starts
with tests of its rules (JS or Swift, run in `check.sh`). Size: S is small, M
medium, L a big lift. Details and what is left out, with the reasons, are in
"Matching Pocket Casts" in `docs/PODCASTS-PLAN.md`.

- [ ] **P5a. Per-show settings** (S): skip the first and last N seconds of every
      episode (intros and outros), the show's own speed, auto-download on or
      off, and add new episodes to Up Next (top, bottom or off).
  - Status: built and passing `check.sh` (schema version 6); not yet compiled in
    CI or run on a phone. Not built: the time-saved counter (not trivial).
- [ ] **P5b. Archive and tidy** (S): archive and unarchive episodes, archive by
      itself after playing or after N days, keep only the newest N episodes,
      sort episodes (newest, oldest, shortest, longest), group by season, and
      show or hide archived episodes.
  - Status: built and passing `check.sh` (schema version 7); not yet compiled in
    CI or run on a phone. The sort and group choice is kept in `shows` columns,
    not AsyncStorage.
- [ ] **P5c. Star, history and bulk actions** (M): star episodes, mark played or
      unplayed, a listening history in Profile, and multi-select with bulk
      actions (download, mark played, archive, star, add to Up Next).
  - Status: built and passing `check.sh` (schema version 10): star, mark played,
    a Listening history in Profile, and multi-select with bulk actions on the
    show page and in the history.
- [ ] **P5d. Smart playlists** (M): the Playlists tab, with playlists built from
      rules (shows, played state, release date, length, downloaded, starred),
      sorted and with auto-download. It starts with New Releases, In Progress
      and Starred.
  - Status: built and passing `check.sh` (schema version 11): a Playlists tab
    with rule playlists, the three starters, and auto-download of each
    playlist's first 5 episodes on Wi-Fi.
- [ ] **P5e. Your own playlists** (S): playlists you fill by hand, with any
      episode (also from shows you don't follow), drag to reorder, and "Play
      all" into Up Next.
  - Status: built and passing `check.sh` (schema version 12): hand-filled
    playlists with any episode, drag to reorder, and Play all (the first plays,
    the rest go to the top of Up Next).
- [ ] **P5f. Sleep timer** (S): 5 to 60 minutes or your own time, end of
      episode, end of chapter once P5g is in, add 5 minutes, and a fade-out at
      the end.
  - Status: built and passing `check.sh` (Swift timer, 10 s fade-out, moon
    button in the player). "End of chapter" came with P5g.
- [ ] **P5g. Chapters** (M to L): chapters from the feed (`podcast:chapters`),
      from M4A files (Apple's own reader) and from MP3 files (ID3 chapter tags,
      read by our own reader), a chapter list in the player, previous and next
      chapter, chapter artwork, and skipping a chapter.
  - Status: built and passing `check.sh` (schema version 9,
    `episodes.chapters_url`): chapters from the feed's JSON file, MP3 ID3 tags
    (a reader written from the ID3 spec in PodcastKit `PodcastChapters`) and M4A
    chapter tracks, kept in Swift so they work locked and with Up Next. The
    player has a Chapters list with a skip switch per chapter, a chapter bar
    with previous and next, and chapter artwork. The sleep timer's "End of
    chapter" and the headphones' "Next chapter" are in. Not built: chapter
    titles on the lock screen.
- [ ] **P5h. Bookmarks** (S to M): a bookmark at the place playing now, with a
      title you can edit, from the player and as a headphone action; listed per
      episode and in Profile; tap to play from there.
  - Status: built and passing `check.sh` (schema version 13): bookmarks from the
    player and from the headphones (kept in Swift while locked, saved by the app
    later), listed per episode and in Profile.
- [ ] **P5i. Playback settings** (S): skip back and ahead amounts, what the
      headphones' next and previous buttons do (skip, next chapter or bookmark),
      mark an episode played when N seconds are left, and going back a few
      seconds after a long pause.
  - Status: built and passing `check.sh`: a Playback section in Profile, kept in
    Swift. "Next chapter" came with P5g and "bookmark" with P5h.
- [ ] **P5j. Volume boost and trim silence** (L): a second Swift player
      (AVAudioEngine) for downloaded episodes that makes voices louder and cuts
      silent gaps, in three strengths, per show or for everything. Streamed
      episodes keep speed only.
  - Status: built and passing `check.sh`, with the one AVPlayer instead of a
    second player (decision 2026-11-17, so ads, the sleep timer, Up Next and the
    lock screen keep working): voice boost is an audio tap on the player item
    (downloads, and streams where the tap attaches), and trim silence jumps over
    the silent gaps of a download, measured once per file. Both are set in
    Profile and per show. The tap and the file reader are compiled for the first
    time in Fork CI.
- [ ] **P5k. Stats** (S to M): total time listened, time saved by speed,
      skipping, intro and outro skipping, trimmed silence and skipped ads, and
      listening by day, in Profile.
  - Status: built and passing `check.sh`: Swift counts the time listened and the
    time saved by speed, intro and outro skipping, trimmed silence, skipped ads
    and skipped chapters in `Podcasts/stats.json` (also locked); Profile > Stats
    shows them with a 30-day bar chart and a reset. No schema change.
- [ ] **P5l. Themes** (M): Light, Dark, Extra Dark (true black) and a few colour
      themes with names and colours of our own, following iOS light and dark
      mode if you like, for the Podcasts section.
  - Status: built and passing `check.sh`: Light, Dark, Extra Dark, Midnight,
    Paper and Forest in Profile > Appearance, as "Like the app", one theme, or
    "Follow iOS" with a light and a dark choice. The section sits in one Uniwind
    `ScopedTheme`. The iOS 26 tab bar glass and the status bar follow iOS, not
    the theme.
- [ ] **P5m. Share and OPML** (S): share a show, an episode or the place playing
      now (the feed's own links); import and export your shows as an OPML file
      (with the document picker and share sheet the app already has).
  - Status: built and passing `check.sh`. An episode is shared by its audio
    address (the feed's episode web link is not stored).
- [ ] **P5n. AirPlay and notifications** (S): the AirPlay button in the player,
      and a notification when a followed show has a new episode (per show, from
      P2c's background refresh).
  - Status: built and passing `check.sh`: the AirPlay button and one local
    notification per show per refresh, with one switch in Profile (off by
    default). Per-show switches are not built.
- [ ] **P5o. Your own audio files** (M): add audio files from the Files app,
      play them like episodes, and put them in Up Next. They are transcribed and
      ad-checked like downloads.
  - Status: built and passing `check.sh`, no schema change: "Add audio files" in
    the Podcasts menu and Profile copies files from the Files app into the app
    and installs them like downloads (`file-<sha256 prefix>`), so they play
    offline, go in Up Next, and are transcribed and checked for ads. They live
    in a local "Your files" show (`local-files`) that feeds, OPML, the Apple
    Podcasts sync and Discover skip. Rename and delete from the episode menu.

### Features from other podcast apps (Mo's ask, 2026-11-17)

Mo picked these from a list of ideas taken from other podcast apps. Each is
rebuilt here with nothing copied.

- [ ] **P6a. Search inside episodes** (S to M): search the words spoken in every
      episode the phone has transcribed (downloads and your own files), as a
      third choice in the episode search ("Spoken"). A result shows the episode,
      the time and the line around the words, and a tap plays the episode from
      that line.
  - Swift does the search: PodcastKit `PodcastTranscripts` gets the matching
    rules (case and accents ignored, the words as a phrase first, then all the
    words in one line; a few hits per episode, a cap in all), tested on Linux.
    The module reads the finished `<sha256>.transcript.json` files off the main
    thread. No schema change. Feed transcripts that were never downloaded are
    not searched.
  - Done when: a phrase said in a downloaded episode is found, and the tap plays
    from that line.
  - Status: built and passing `check.sh`, no schema change: "Spoken" in the
    episode search, results grouped by episode (newest first) with the time and
    the lines around the words, whole words only. Each search reads every
    transcript file; no index is kept.
- [ ] **P6b. Hosts, guests and support links** (S): the feed's own
      `podcast:person` (show and episode) and `podcast:funding` (show) tags,
      shown in the episode's description: "Support the show" links and the hosts
      and guests with their pictures and links. An episode's own people replace
      the show's, as the Podcasting 2.0 spec says.
  - The feed parser reads the tags (tested on Linux); one schema step keeps them
    as JSON text (`shows.funding`, `shows.people`, `episodes.people`), filled at
    the next refresh. Only `http` and `https` links open.
  - Done when: a feed with these tags shows them in its episodes' descriptions
    after a refresh, and a feed without them shows nothing new.
  - Status: built and passing `check.sh` (schema version 14): the parser keeps
    at most 20 people and 5 support links, http(s) only; the episode's
    description shows "Support the show" and "Hosts and guests". An existing
    show shows them after its next refresh.

### Bug check (Mo's ask, 2026-11-17)

Three Opus reviewers traced the data layer, the screens and the Swift side and
found 31 bugs; all were fixed with tests where the rule could run on Linux, and
`check.sh` passes. The worst: archiving an imported file deleted the only copy,
Profile didn't scroll, Up Next could freeze the player, Apple sync undid "Mark
unplayed", a "Not downloaded" playlist downloaded the library, the outro skip
used the previous episode's length, http episodes couldn't download, and the
book resumed instead of the podcast after a call. The Swift module and screen
fixes wait for Fork CI and TestFlight.

### A modern podcast app look (Mo's ask, 2026-11-17)

The plan is `docs/PODCASTS-DESIGN.md`: native iOS 26 bars, colour from the
artwork, one main action per screen, fewer controls, motion and haptics, and
every theme readable. Pocket Casts stays the structure; other apps give patterns
only. No new npm packages and no new CSS variables.

- [x] **D1. Native iOS 26 bars** (M to L): `ScreenBar` becomes the native header
      (large titles on the tab roots, SF Symbol toolbar buttons and menus), the
      tab bar shrinks on scroll, the player opens as a sheet, and the status bar
      follows the Podcasts theme.
  - Done when: `check.sh` passes, Fork CI builds, and on TestFlight every screen
    has the native bar, tab titles shrink on scroll, the player swipes down,
    Profile scrolls, and VoiceOver reads every toolbar button.
  - Status: built and passing `check.sh`: `ScreenBar` draws `Stack.Title` and
    `Stack.Toolbar` (large titles on the tab roots, SF Symbol buttons and
    menus), the tab bar shrinks on scroll, the player is a modal sheet, the
    status bar follows the theme, and the mini player has skip-ahead. The look
    and feel wait for TestFlight.
- [x] **D2. The player** (M to L): a gradient from the artwork colour, page
      pills (Now Playing, Notes, Chapters, Transcript), artwork that shrinks
      when paused, a seek bar that grows under the finger, a five-slot toolbar
      with "…", speed in a sheet, and haptics.
  - Done when: a test shows white text at 4.5:1 on both gradient ends for 10
    sample colours, nothing jumps when speed opens, the artwork shrinks when
    paused (not with Reduce Motion), VoiceOver reads the pages as tabs, and
    nothing clips at the largest text size.
  - Status: built and passing `check.sh` (a test checks 16 colours): gradient,
    page pills as tabs, artwork spring, growing seek bar, five-slot toolbar,
    speed sheet and haptics. The feel and VoiceOver wait for TestFlight.
- [x] **D3. Show page, episode rows and the episode card** (L): a wash from the
      artwork behind the show header, rows with two trailing controls and
      readable played rows, and an episode card with one main button and an
      action strip.
  - Done when: the header wash, row text and artwork colour tests pass, and on
    TestFlight a show is tinted on its first visit and the card has one main
    button.
  - Status: built and passing `check.sh` (tests: header wash in six themes, row
    text, artwork colour once per show): show page wash, rows with "…" and play
    (downloads moved to "…"), and a card with one main button and a five-button
    strip. The look waits for TestFlight.
- [x] **D4. Discover, search and the Podcasts grid** (M): the native search bar
      (a pasted RSS or Apple link follows the show), hero cards that snap,
      category tiles that grow with the text, and empty states with a next step.
  - Done when: the follow-link tests pass, hero cards snap, and category tiles
    don't clip.
  - Status: built and passing `check.sh` (`isFollowLink` tested): the native
    search bar on Discover and episode search with "Follow this link", a
    snapping hero carousel, a category grid with icons, artwork corners by size,
    and empty states. The look waits for TestFlight.
- [x] **D5. Up Next, Playlists, Profile and Stats** (M): grouped cards with
      separators, title-case headers, icons on swipe buttons, a bigger "Time
      listened", and an empty state with a next step on every empty screen.
  - Done when: `check.sh` passes and the cards show separators in all six
    themes.
  - Status: built and passing `check.sh` (progress, playlist line and rule pills
    tested): Profile in grouped cards under a stats card, Up Next with progress
    lines and icon swipe buttons, playlist icon tiles and rule pills, a bigger
    Stats, empty states, and no uppercase headers. The look waits for
    TestFlight.

### Mo's first try of build 27.1 (2026-11-17)

Mo: "the ad skip doesn't seem to work. There is no place to see downloaded
podcasts. The transcript takes way too long. There seem to be interface glitches
like the top bar covering parts of text. Doesn't look like a modern app." What
the code shows: Downloads exists but only under Profile; episodes are
transcribed one at a time in download order, the one playing does not go first,
nothing shows until the whole episode is done, and ads are looked for only after
that, so a fresh download is usually past its ads before they are known.

- [x] **R1. Downloaded episodes in the Library** (S): a "Downloaded" row at the
      top of the Library (with how many) opens the downloads list inside the
      Library tab; Profile keeps its row.
  - Done when: `check.sh` passes and the row opens the list without switching
    tabs.
  - Status: built. The downloads list is a shared route (`downloadsHref`), so it
    opens in the tab you are in; the Library's "Downloaded" row sits above the
    shows and Profile uses the same link. The look waits for TestFlight.
- [x] **R2. The playing episode first** (M): the transcriber and the ad finder
      put the playing episode at the front of their queues and pause another
      episode at its next piece; playing an episode that is not downloaded
      starts its download when "Skip ads" is on, so it can be transcribed.
  - Done when: `check.sh` passes (queue order tested in PodcastKit), and the iOS
    build passes in CI.
  - Status: built (QueueOrder in PodcastKit, tested): the episode loaded in the
    player goes first in the transcript and ad queues, and the one at work stops
    at its next piece. Waiting for the iOS build in CI.
- [x] **R3. Lines as they are transcribed** (M): the transcript shows the lines
      saved so far with "Transcribing, N%" under them and grows after each
      five-minute piece, instead of a wait for the whole episode.
  - Done when: `check.sh` passes and the iOS build passes in CI.
  - Status: built: the transcript shows the saved lines with "Transcribing, N%"
    under them and reads again after each piece; its buttons sit above the home
    indicator. Waiting for the iOS build in CI.
- [x] **R2b. Play waits for the download** (M, Mo's card, recommended option):
      with Skip ads on, playing an episode that is not downloaded downloads it
      first and plays the file; it streams when the download fails, nothing
      arrives under Wi-Fi only, a minute passes, or the listener taps "Stream
      now". A card in the mini player's place shows the percent.
  - Done when: `check.sh` passes (the wait rules tested) and the iOS build
    passes in CI.
  - Status: built, then replaced by R8 in the same pull request (Mo wanted ads
    skipped while streaming): the wait, its card and the polling are removed.
- [x] **R8. Skip ads while streaming: play the download as it arrives** (L, Mo
      2026-11-17: "If you can find a way to skip ads while streaming would be
      better"): with Skip ads on, an episode that is not downloaded starts at
      once from its own download as the bytes arrive (an
      `AVAssetResourceLoaderDelegate` that feeds the player from a foreground
      download of the episode's address and waits for bytes not there yet), so
      what is heard is the exact file that is then saved, transcribed and
      checked for ads. It replaces R2b's wait; with Wi-Fi only on and no Wi-Fi
      the episode streams as before.
  - Test first: PodcastKit rules for which byte ranges can be answered now,
    content length and type from the response, and handing the finished file to
    the download store (same sha256 and folder as a normal download).
  - Done when: `check.sh` passes, the iOS build passes in CI, and on TestFlight
    a new episode starts at once with Skip ads on and appears in Downloaded when
    its bytes are all in.
  - Status: built (rules in PodcastKit's StreamRules, tested): a custom-scheme
    asset fed by `PodcastStreamDownload` from one foreground download into the
    staging folder, shown in Downloads with progress and filed like any download
    when whole, then transcribed and checked. Up Next plays the same way. A seek
    past the bytes so far waits for them; ads before the first finished piece
    are heard. Waiting for the iOS build in CI and TestFlight.
- [x] **R4. Ads found as the transcript grows** (L): the ad finder works on the
      playing episode's transcript after each five-minute piece instead of after
      the whole episode. Pieces that end before the transcript's edge are asked
      once (the chunking is greedy, so a prefix gives the same pieces); their
      answers are kept in a progress file, a partial ads file covers what is
      done, the player skips from it, and the final run reuses the answers.
  - Test first: PodcastKit tests that pieces from a prefix match the full
    transcript's pieces up to the edge, that kept answers are reused, and that
    the partial file only covers finished pieces.
  - Done when: `check.sh` passes, the iOS build passes in CI, and on TestFlight
    a mid-roll in a just-started episode is skipped.
  - Status: built (15 PodcastKit tests): after each saved piece of the playing
    episode its finished pieces are asked, answers kept in a progress file, a
    partial ads file feeds the player, and the full pass reuses the answers.
    Another episode's full pass makes way. Waiting for CI and TestFlight.
- [x] **R5. The top bar over text, and controls off the edge** (M): Mo's
      screenshots (Profile scrolled, the player's transcript) show the large
      title staying large over the content, the page pills running off the right
      edge, and the transcript's buttons under the home indicator. Every
      screen's list or scroll view becomes the screen's first child (no wrapping
      View, the bar and status bar after it), so iOS tracks it: the large title
      shrinks and the bar blurs what passes under it. The player's pills fit the
      width, and every control pinned to the bottom sits above the home
      indicator. Then a pass over every Podcasts screen for the same faults.
  - Done when: `check.sh` passes, the iOS build passes in CI, and on TestFlight
    the Profile title shrinks on scroll and nothing is clipped in the player.
  - Status: built: every Podcasts screen but episode search returns its list
    first, the stack draws the theme background, the selection bar is drawn over
    the list with a spacer, the player pills share the width, and bottom
    controls use the safe inset plus 12. Waiting for CI and TestFlight.
- [x] **R7. Feeds and episodes over plain http** (S): 12 of Mo's 64 shows failed
      with "only works over plain http". The app allows plain http (like other
      podcast apps), keeps trying https first, and a download whose https
      address fails falls back to the feed's http address. Marketplace's 403 is
      looked at separately.
  - Done when: `check.sh` passes, the iOS build passes in CI, and on TestFlight
    the Bloomberg feeds subscribe.
  - Status: built: plain http is allowed, https is still tried first, and a
    download keeps the feed's http address (optional `plainURL`, older indexes
    read fine) to try once if https cannot connect. Marketplace's 403 is not
    looked at yet.
- [x] **R6. A more modern look**: Mo named Apple Podcasts; it became the
      redesign below (A1 to A6).

### The Apple Podcasts look (Mo's ask, 2026-11-17)

Mo: "Redesign the whole thing to look like apple podcast app with all the
features we have. Same animations, look and everything." Plan, structure and
look in `docs/PODCASTS-APPLE-DESIGN.md`, from Mo's screenshots (kept in the
project files, not the repository). One pull request with R1 to R8, one
TestFlight build.

- [x] **B2. Second bug check of the whole Podcasts section** (Mo's ask): Opus
      reads the Swift side and the data and logic side; Sonnet fixes what holds
      up; the screens are checked after the redesign (A6).
  - Done when: every finding is fixed or noted with a reason, `check.sh` passes
    and the iOS build passes in CI.
  - Status: S1 to S8 and D1 to D16 fixed 2026-11-17 (ATS, resuming and falling
    back play-through, the downloader knowing about it, Up Next language, the
    Apple follow list read with retries and a status row in Profile, pending
    Apple-played episodes, serial subscribe); Fable 5.2 reviews the fixes.
- [x] **A1. Tabs and rooms** (L): Home, New, Library and Search (the system
      search tab); the account button and Profile as a sheet; the Library list
      and Recently Updated; Shows as its own screen; the Up Next page with the
      queue; nothing lost from the old Profile, Playlists and Up Next tabs.
  - Done when: `check.sh` passes, route tests cover every tab's home screen and
    the shared detail routes, and the iOS build passes in CI.
  - Status: built 2026-11-17 (four tabs, one shared route group
    `(home,new,library,search)`, Profile at `/podcasts/account`, Library rows
    with counts); `check.sh` passes; the iOS build in CI is still to run.
- [x] **A2. Home** (L): the Up Next cards (in progress, then the newest unplayed
      episode per show), the shared episode "…" menu, Your Top Shows, You Might
      Like, Saved and Latest Episodes.
  - Done when: the shelf's SQL and order are tested and `check.sh` passes.
  - Status: built 2026-11-17; the card's "…" is white and tints its menu with
    the card's colour. Top Shows rank by recent plays (the stats keep no time
    per show).
- [x] **A3. Rows, show page and episode page** (L) in Apple's look, with the
      purple accent and the system font.
  - Done when: `check.sh` passes; the look is checked on TestFlight.
  - Status: built 2026-11-17 (rows, native menu with Save and Share on top, show
    and episode headers in the artwork's colour, zoom targets); the purple and
    the system font come from the app-wide theme of the Books restyle.
- [x] **A4. Player and mini player** (L): the screenshot's layout, the queue and
      transcript in place of the artwork, the "…" menu, the zoom from the mini
      player where it works.
  - Done when: `check.sh` passes and nothing the old player did is lost.
  - Status: built 2026-11-17 (sheet in the artwork's colour, volume slider as a
    second native module, six panels in place of the artwork). No zoom from the
    mini player: it lives in the tab bar's accessory, outside the stack.
- [x] **A5. Search and New** (M): category tiles, scopes, featured cards and
      ranked Top Shows.
  - Done when: `check.sh` passes.
  - Status: built 2026-11-17 (paging featured cards, ranked Top Shows, For You
    shelves, gradient category tiles, scope chips, a shared `SectionHeader`).
- [x] **A6. Look and motion check** (M): every screen against the screenshots in
      each theme, animations with Reduce Motion, VoiceOver and large text.
  - Done when: the Opus check's findings are fixed and `check.sh` passes.
  - Status: the check found 27 items (L1 to L27, 2026-11-17); all fixed but the
    mini player's title fade (the glass has no colour to fade into) and the
    episode artwork's zoom (no tile opens an episode). Fable 5.2's final check
    of the whole pull request (Mo, 2026-11-17) found no serious issue and seven
    smaller ones, all fixed, plus the player's full-width artwork, SF Symbol
    buttons and a thick volume bar. A last Fable check of those fixes and of
    main's Books look merged in found six small issues, all fixed: the mini
    player's symbols in the theme's colour, the player artwork as wide as the
    iPad sheet, a fingertip-wide clear thumb on the volume bar, the "Episodes"
    heading for VoiceOver, the Light and Dark swatches in the new colours, and
    the swipe actions' padding and colours under the new buttons. Left for a
    device: pulling down on a show page opened by the zoom may close it instead
    of refreshing, and dragging the volume bar.

### Covers and more lists (Mo's ask, 2026-11-18)

Mo, after build 29.1: covers that look too small for their square, blurry
covers, and a first page with many more lists ("top podcasts ... on Spotify,
Apple Podcasts ... a bunch of different lists"). Fable planned it in
`docs/PODCASTS-LISTS-PLAN.md` (findings, design and every milestone's files,
first test and risks); Sonnet builds, Opus checks. One pull request, one
TestFlight build.

- [x] **C0. Check the real addresses from a GitHub runner** (S): the cloud can't
      reach Apple's or Spotify's hosts, so a probe workflow does. Results in
      `docs/PODCASTS-PLAN.md` ("Chart sources checked"): sharp covers and Top
      Episodes yes, Spotify no.
- [x] **C1. A rule that picks a sharp picture address** (S): size buckets and
      Apple's image size rewrite, the original as a fallback.
- [x] **C2. Covers use the rule** (S): `Artwork` loads the sharp address first.
- [x] **C3. Featured cards filled by their cover** (S): the cover edge to edge
      with its title on a fade, no small square in a coloured box.
- [x] **C4. Charts in groups, with yesterday's list as a fallback** (M).
- [x] **C5. Which lists, in which order** (S).
- [x] **C6. Shelves that draw only what is near the screen** (S), with a loading
      shelf.
- [x] **C7. Home gets the lists** (M): Top Shows and eight "Top in ..." shelves,
      then the categories.
- [x] **C8. New gets every category as a shelf** (S).
- [x] **C9. Top Episodes** (M), if C0 says the source works.
- ~~C10. Spotify's chart, read and matched~~ and ~~C11. "Top on Spotify"~~:
  dropped, because Spotify's chart service failed on its own side in both probe
  runs (`docs/PODCASTS-LISTS-PLAN.md`, decision 4).
- [x] **C12. Docs and the Opus check** (S).
  - Done when (each): the first test from the plan fails then passes, `check.sh`
    passes, and for screens the iOS build passes in CI.

### Mo's 29.1 bugs, ad skipping and the iPhone Duo (2026-11-18)

Mo, trying build 29.1: the player's "..." menu was cut off, a tap on the play
bar crashed the app, Bloomberg Businessweek's transcript was out of time, and
ads were never skipped ("the third time"); an ad was marked only after it
played. Then: skip unsure ads too (with Undo), skip a stream's ads "even in the
first 5 seconds", and full support for the foldable iPhone Duo. Fable reviewed
every part; Sonnet built; Opus checked.

- [x] **Menu, play bar and transcript**: the menu has at most 10 rows (Share,
      Chapters and Bookmarks are submenus); the seek bar's helper is a worklet
      (a test now checks every worklet file); the phone's transcript wins over a
      feed's when it is done or covers the playhead.
- [x] **Ads found sooner**: work starts at download, playing episode first;
      pieces of 60, 120, then 300 s; a growing partial pass; unsure ads skipped
      with Undo; a status line in the player; a refused piece no longer blocks
      an episode; a Mac check (`Check ad skipping on an episode.command`).
- [x] **I0. Mac timing and two-download probe**: `podcast-ads --head` runs the
      phone's stream path; "Compare two downloads" has a one-click "Test my
      shows".
- [x] **I1. Heads first, and leave an ad already playing**: every episode's
      first 3 minutes before any rest; an ad found while it plays is left when 3
      s or more remain.
- [x] **I2. A stream's first minutes checked while it downloads**: cuts at MP3
      frames in 30 s steps, quick text rules, a prewarmed model at 60 s.
- [ ] **I3. Spot inserted ads with a second quick download** (Mo said yes, once
      the Mac test proves it): waits on Mo's "Test my shows" result.
- [x] **iPhone Duo, landscape and small phones**: pages size from the window and
      the safe-area insets; wide grids get more columns without a remount; the
      player sits side by side when short and wide, with a whole cover on the
      Duo's centred sheet; sheets turn with the phone.
  - Needs Mo's phone or the Duo simulator: first-skip timing on a stream, the
    fold and unfold, and how SpeechTranscriber writes web addresses.

### Ad skipping: starts and ends (Mo's ask, 2026-11-18)

Mo: "ad skipping doesn't skip ads in the first few seconds, and when it does it
skips too far". Fable planned it twice (`docs/PODCASTS-ADS-ACCURACY-PLAN.md`:
sections 1 to 6 and then 16 more ideas in section 7), Sonnet built it in
parallel worktrees, Opus checked it twice (first review found three ways a skip
could run into the show, a layout bug and a few hang and storage risks; all were
fixed). Everything that touches the iOS module compiles only in Fork CI.

- [x] **E1 Safe landing**: a skip lands 0.25 s before the next word; an ad that
      begins in the first 6 s begins at 0:00. **E2** a short, strict carry-on (2
      lines, stops at "we're back"). **E3** a stricter merge of ads of one
      break. **E4** tighter quick rules for a stream's head.
- [x] **M1 Measure the edges** (`Check ad edges on an episode.command`): waits
      on Mo to run it on 3 episodes where a skip went too far and send the
      `.ad-edges.txt` files.
- [x] **F1 "Too far" is one tap**: "Back 10 s" on the note shortens the ad for
      good; three counters in the stats file. **E5a** a downloaded file opens
      with precise timing (the stream half waits on M1's numbers).
- [x] **S1 A faster first look** (rules at 15 s, model at 30/60/120/180 s, warm
      speech model), **S2 remember ads by their words** (`KnownAds`), **S3 the
      phone uses that memory** (whole match, opening, Undo forgets), **S4 a 3 s
      wait before a never-checked stream starts** (Mo approved), **S5 download
      the next 2 Up Next episodes on Wi-Fi** (Mo approved).
- [x] **N1 Shared frames between episodes**
      (`Compare two episodes of a show     .command`, "Compare my shows"): waits
      on Mo's one file; **N2** sponsor names from the notes reach the rules;
      **N3** compare our words with the feed's transcript (pure part and a Mac
      count; the fetch is not wired); **N4** the show's opening words; **N5**
      cut inside the edge line; **N6** an evidence check on "sure" ads; **N7**
      cues of produced spots; **N8** a skip log on the phone with a "Send skip
      log" row in Profile; **N9** chapters that name a sponsor.
- [x] **The Duo player**: a small cover shows when the room is 100 pt or more,
      the open Duo's sheet is split in two columns, the two columns have fixed
      widths; Search's category tiles fit the page; Up Next cards stay above the
      mini player.
- [ ] **Waits on Mo or on measurements**: E6 (the model checks each end and new
      instructions), I3 (a second quick download), N10 to N16 (see section 7.5
      of the plan: the fetch of the feed's transcript, offering unsure ads, a
      heads-only download, frame memory, per-show caution from the skip log),
      and the phone checks: first-skip timing, the wait, "Back 10 s", the
      stream's last seeks.

### The player, ad finding and smoothness (Mo's ask, 2026-11-18, after build 31.1)

Mo's 31.1 report: ads not skipped on an episode, "Finding ads" takes a long time
and finds nothing, swiping the player down shows another copy (three swipes,
then it cannot be opened until the app is quit), the mini player needs several
taps, scrolling stutters. Fable planned it (`docs/PODCASTS-STABILITY-PLAN.md`)
and walked the flows the first plan did not
(`docs/PODCASTS-STABILITY-SWEEP.md`), Sonnet built it in parallel worktrees,
Opus checked it at extra effort (one SHOULD-FIX per half, all fixed).

- [x] **S1 The player opens once, on the first tap**: the player screen is
      singular, one gate (`playerGate.ts`) opens it, the mini player has a
      pressed look and a haptic. **S6** a playing episode no longer reloads
      every list every 15 s. **S7** rows draw again only when what they show
      changes. **S8** lists and the episode page stop drawing on every tick.
- [x] **S2 A model refusal no longer stops the ad search**, **S3** a refused
      piece is asked again in halves, **S4** a failed episode shows the ads
      found and "Ad check paused. Trying again soon", **S5** the ad finder's
      diary (`ad-diary.jsonl`, sent with "Send skip log").
- [x] **S9 Simulator checks** (`tools/fork/ui-checks`, Maestro): flows for the
      player opening once, a tap during the slide away, scrolling; run on Mo's
      Mac first (`Run the UI checks.command`), GitHub second.
- [x] **S10 The player knows its place while a seek is on its way**, **S11**
      Play starts a failed episode again, **S12** a loading stream can be
      paused, **S13** a feed refresh tells the screens only when something
      changed, **S14** an episode stopped near its end resumes there, **S15**
      the end-of-chapter sleep survives an ad skip.
- [ ] **Waits on the phone or Mac**: TestFlight 32.1 phone steps 1 to 6
      (`docs/PODCASTS-STABILITY-PLAN.md`, "On Mo's phone"), M1 (the real model
      on The Daily "Finally, a Vaccine for Cancer", before and after S2 and S3),
      the S9 flows run once on main and then on this branch, and the
      first-seconds question (H1, not this round).

### The Mac teaches, the phone skips alone (Mo's ask, 2026-11-22)

Mo's report on build 32.1: an ad has played "a big chunk" before it is skipped,
the show's own promos ("come to a show") are missed, "generally not functional".
Mo's rule: the phone must skip ads alone, and the Mac may only teach it. Fable
planned it (the Claude Doc "Podcast ad skipping rethink",
https://claude.ai/artifact/VNrsKHbqDXvyijXHBdoZ4s), Sonnet builds it in parallel
worktrees, Opus checks it at extra effort, Fable does the final check. The
design and the contracts are in `docs/PODCASTS-ADS-TEACHING.md`.

- [x] **T1 The Mac's teaching tools**: gather the newest episodes of the
      followed shows, transcribe them, have Claude mark four sorts of stretch
      (through `claude -p`, after a typed "yes"), work out each show's start
      habits (`Tools/mac/teach_*.py`). Opus found 3 serious and 7 smaller
      problems; all fixed with tests.
- [x] **T2 The backups in PodcastKit**: four sorts with their own switches (ad,
      own plug, promo, credits), word rules for promos (`AdPromoRules`), the
      small word model and its trainer (`AdWordModel`, `teach_train.py`), the
      library of known ads (`AdLibrary`, `teach_library.py`), start habits
      (`ShowHabits`, a 5 second wait for shows that open with an ad).
- [x] **T3 Finders that never wait for Apple's model**: `LocalAds` (rules and
      the small model), the kind-aware `AdJoin`, `LocalAdsFile` (adds local ads
      to an episode's files, or saves them as its result), `TeachingFiles`.
- [x] **T4 The scorecard**: `podcast-teach score` runs the local finders over
      the marked episodes and prints what was caught, heard and cut, per sort
      and per show, what each layer adds, and what changed since the last run.
- [x] **T5 Matching by sound**: `podcast-teach sounds` makes prints of the
      marked ads from the MP3 frames, and `AdSoundScanner` finds them in a file
      as it arrives, with no decoding.
- [x] **T6 The Mac side of the extras**: the phone's notes become a list of
      episodes to gather first (`teach_feedback.py`), a weak model is not
      published, `teaching.json` lists what was published, one finish script,
      files to double-click, and a weekly launchd job.
- [x] **T7 The app**: the finder and the stream's first minutes run the local
      layers first and keep their ads whatever Apple's model does; the wait
      before the audio follows the show's habits; four switches; a Skip ad
      button; notes and the diary go to the linked folder; the teaching files
      come from it; an "Ad skipping results" page.
  - Status: built and passing `check.sh`; compiled in Fork CI (PR #54); not yet
    run on a phone.
- [x] **T8 Opus check of the round**, then fixes. Opus read the Mac tools twice
      and the new package code once: 13 serious problems (the promo rules cut
      ordinary talk, credits were skipped as part of an ad, an Undo and a trim
      were lost when an episode was checked again, a sound match cut the sound's
      full length after one second, the scorecard scored episodes against their
      own ads) and 25 smaller ones. All fixed with tests.
- [x] **T9 Opus bug check of the whole Podcasts section** (Mo's ask), then
      fixes. Five parts (player, finder, data, playback and ads, screens): 2
      serious problems (known ads from the Mac never reached a downloaded
      episode; new teaching never reached an episode already checked), about 20
      medium and 25 small ones. Fixed in six passes, then Opus checked the fixes
      themselves (no compile error, 3 medium and 5 small problems, all fixed).
      Left as they are: skips on a stream of a variable-rate MP3 after the first
      seek (cannot be confirmed without a phone), one lock for the three writers
      of an episode's unfinished ads file, and a one-frame flicker after a drop
      in a hand-filled playlist.
- [ ] **Waits on Mo**: the phone steps after the TestFlight build. Mo started
      the first teaching run on the Mac on 2026-11-22 and asked for the marking
      to start by itself when the gathering is done ("Mark ads when the
      gathering is done"), and gave the OK for the merge.

### The phone learns by itself (Mo's ask, 2026-11-23)

After build 33.1 Mo asked for more ways to make ad skipping accurate and fast,
was sent eight ranked ideas, and said "do 1-8": all eight in one pull request
and one TestFlight build. Fable planned it, Sonnet builds it in parallel
worktrees in three waves, Opus checks each part at extra effort, Fable does the
final check. Two ideas are built smaller than listed: a repeat only asks (it
skips only where the Mac's settings say so), and per-show settings are three
levels, not thresholds, because a show has about four marked episodes.

- [x] **U1 Seams and the finder guard**: `FoundAd.source`, `AdsFile.asks`, the
      note kinds `confirmed` and `denied`, and `FinderGuard`, which switches off
      a new finder that crashed or was undone twice. The scorecard gains
      "seconds of an ad heard before the skip" and per-show totals for every
      row.
- [x] **U2 The phone's own sound prints**: `OwnAdSounds` keeps a print of each
      sure ad of a downloaded MP3 (`own-ad-sounds.json`, 40 a show, 400 in all,
      60 days). The head scan and the download pass look for them with the Mac's
      sounds.
- [x] **U3 Repeats**: `EpisodePrints` and `RepeatScanner` (sound) and
      `RepeatedWords` (words) find what a show's last three episodes share. A
      repeat asks; it skips only where the Mac's settings say so.
- [x] **U4 The one-tap question**: guesses become questions (`AdAsks`,
      `AdAsking`, `AskAdNote.tsx`, `onAdAsk`, `answerAdQuestion`). Yes teaches
      the memory, the prints and the Mac; no stops the asking.
- [x] **U5 A second download on the Mac**: `teach_copies.py` and `teach_snap.py`
      write `labels-snapped/` from `CopyTruth`, and the teaching run uses it
      when it is there.
- [x] **U6 Borders from joints**: `JointSnap` moves a start or an end onto a
      joint of the file within a few seconds.
- [x] **U7 The phone's own habits**: `show-starts.json` version 2 keeps where
      each opening ad ended and stands in for `show-habits.json` for shows the
      Mac never sampled.
- [x] **U8 Per-show settings**: `teach_settings.py` writes `show-settings.json`
      from the scorecard and the phone's notes; `ShowTuning` applies skip, ask
      or off.
- [x] **U9 The meaning model**: `podcast-teach meaning` trains weights over
      Apple's sentence embedding (`ad-meaning.json`); the phone runs it in the
      background when it was published.
- [x] **U10 Scorecard rows and the round's test**: one row for each new finder,
      the questions line, the habits note, and a three-episode test of the whole
      round.
- [x] **U11 Docs**: `PODCASTS-ADS-TEACHING.md`, the Mac README, ARCHITECTURE and
      LESSONS.
- [ ] **Waits on Mo**: the limits card (about 20 MB of new data, questions only
      for dropped guesses, joints moving a skip up to 3 s earlier and 4 s later,
      second downloads capped at 40 episodes and 3 GB), the merge, installing
      the TestFlight build, double-clicking "Teach the phone again.command" and
      "Score the ad skipping.command", and reading the new rows. A finder whose
      row is under 0.85 precision stays at ask or off.

### Ad skipping to 95%, round A (Mo's ask, 2026-11-23)

Mo set the aim: 95% of ad breaks skipped by itself while streaming, and the skip
must not land more than 5 seconds past the ad. The plan and the measurements are
in the Claude Doc "Ad skipping to 95%: the test and the plan". Mo chose "Round
A, exam and 500 more episodes": the test (parts 1, 3 and 5), the three fixes
that cost nothing to run, about 500 more marked episodes and a sealed exam of
about 60 newer ones with 15 marked twice (about $110 of his Claude plan, marked
at night). One pull request, one TestFlight build, and Mo sees the numbers
before anything reaches his phone. Fable plans and does the final check, Sonnet
builds, Opus checks each part at extra effort.

The bar: an ad break (marked ads within 1 second of each other, counted once, 10
seconds or longer) passes when the phone skips it with no tap, at most 5 seconds
of it are heard, and the skip cuts at most 5 seconds of show before it and after
it. Today 101 of 219 breaks on the 63 shelf episodes pass (46%), with 75 skips
where there is no ad.

- [x] **V1 The scorecard measures the bar**: `AdBar` and a bar block under the
      scorecard for every row, one cause for each failed break, skips with no
      ad, `--dump`, the sealed exam (`exam.json`, `score --exam`) and
      `podcast-teach agree` for two markings of one episode.
  - Done when: the last row on the shelf reads 101 of 219, with starts late 59,
    stops early 16, gap inside 16, missed 14, starts early 9, lands too far 4.
- [x] **V2 Mac tools for the new episodes**: `teach_exam.py` and the rule that
      an exam episode teaches nothing, `teach_collect.py --exam`,
      `teach_label.py --only-exam --between 23-7 --wait-hours`, second downloads
      that take the exam first, and three launchers: "Gather more episodes for
      teaching", "Mark the new episodes at night", "Gather the exam episodes".
  - Done when: the tools' tests pass. The first run on the Mac is part of V8
    (the cloud cannot start a launcher on the Mac, see LESSONS).
- [x] **V3 A word model that does not memorise** (fix 1): model file version 2
      with the word pairs of the neighbouring lines, a trainer with real
      regularisation that drops words seen fewer than 3 times, and a decoder
      whose ad score leaves credits out and whose start widens back.
  - Done when: on the shelf the row "Plus the trained model" passes at least 115
    of 219 with at most 20 skips with no ad (the prototype: 122 of 226 and 10).
  - Result: 115 of 219 with 15 skips with no ad (was 95 and 75). Without
    `podcast-teach` the trainer still writes a version 1 file.
- [x] **V4 Remembered ads are found whole** (fix 2): the library keeps an ad's
      first 600 words and a remembered ad is found from any of its word runs.
      The rule that cut a word-model skip back to a remembered ad's edges was
      built, measured and removed: it fixed 6 breaks and broke 6.
  - Done when: the row "Plus the library" passes more breaks than the row before
    it and adds no skip with no ad.
  - Result: 121 of 219 against 115 in the row before, both with 15 skips with no
    ad.
- [x] **V5 Joints pull a late start back** (fix 3): in steady files too, a skip
      starts at the nearest joint up to 60 seconds before it, but only when a
      word finder gave that start (`JointPull`), never inside a stretch the
      listener judged, and never in the head scan of a stream.
  - Done when: the joints row on the scorecard (it reads the joints kept in
    `joints.json`) passes more breaks than the row before it.
  - Result: 111 of 219 against 102 with the old word model; with the new word
    model 125 against 121, and 13 skips with no ad against 15. Mo approved 3
    seconds for a joint in the round before and the 60 seconds on 2026-11-23,
    knowing that two skips on the test started 12 and 26 seconds too early.
- [x] **V6 Stream replay on the Mac** (test part 3): the shelf or exam episodes
      go down the phone's own path for a playing stream, Apple's model included,
      and are scored by the bar counting only skips known in time.
  - Result: `score --stream`. At the assumed standard pace 100 of 219 breaks
    pass (21 of 58 in the first 3 minutes); an episode that is ready before it
    is played passes 124 (45 of 58). The phone's real pace is not measured yet,
    and Apple's row needs its answers gathered on the Mac (V8).
- [x] **V7 Pass rate from real listening** (test part 5): the results page says
      how many skips Mo neither took back nor trimmed, against skips plus ads he
      marked as missed.
- [ ] **V8 The run**: gather and mark the 500 and the exam on the Mac, teach
      again, score the shelf, then the exam once, and bring Mo the numbers.
  - Mo chose on 2026-11-23 to merge and build first, on the shelf numbers (PR
    #56, TestFlight 35.1). The round A tools are on the Mac. The run starts with
    his double-click on "Second downloads then gather more"; "Gather the exam
    episodes" comes some days later, so the exam's inserted ads are not the same
    day's.

### Ad skipping to 95%, round B (2026-11-24)

Mo's order (his card, 2026-11-24): "Do 1, 2 then 3": the free steps, then the
Mac reading his next episodes at night, then the sealed exam. One pull request,
one TestFlight build from the Mac, numbers before the merge, Mo's OK to merge.
Sonnet builds (one or two at a time), Opus checks, Fable does the final check.

Where the shelf stands (counted again from a `--dump`, within 3 breaks of the
scorecard): 140 of 219 breaks pass (64%); as a stream at the assumed pace 109,
ready before play 137, and the whole difference of 28 is in the first 3 minutes.
Produced spots are 147 breaks and 106 pass (20 start late, 10 stop early, 8 land
too far, 3 other). Host-read paid ads are 27 and 12 pass. The hosts' own promos
and asks are 34 and 17 pass (9 missed). Half of the 34 late starts are late by
18 to 97 seconds (an ad that opens with a story). On the exact labels (242
breaks, 131 pass) 19 breaks are stretches that only the second download found
and nobody marked, all missed, and 22 skips land too far, mostly by 5 to 19
seconds. No single step below reaches 95%.

The rule for every step: it is measured first on the shelf with the scorecard,
on both label sets. A step that does not raise the bar score by its number, or
adds skips where there is no ad, is not built into the app; its result is
written here and the idea goes under Later.

**1. Free steps**

- [x] **W1 Measure real plays** (phone, small): one diary line for every play
      that starts ("play: ready", "play: partly, transcript to N s" or "play:
      stream") and one for every finished transcription ("N s of audio in M s",
      front or background), kept apart from the 500-line trim. They reach the
      linked folder as `Podcasts/phone-diary.jsonl` already. A new
      `teach_pace.py` on the Mac reads the iCloud copy and prints the share of
      plays that were ready and the speech pace, and `score --stream --speech N`
      replays the shelf at that pace. Mo does nothing. First I look for 35.1's
      diary on the Mac; if it is missing, the way back from the phone is broken
      and is fixed here.
  - Files: `ios/PodcastTimeline.swift`, the player's start, the transcriber,
    `AdDiary.swift`, `StreamPace.swift`, `AdScoreCommand.swift`,
    `Tools/mac/teach_pace.py`.
  - Done when: the tests pass and, after three days on the phone, the Mac prints
    both numbers. It cannot change a skip, so it has no bar number.
  - Result: built (`PlayDiary`, `play-diary.jsonl`, `teach_pace.py`,
    `score --stream --speech N`). The way back from the phone has no break (the
    notes sync runs at app start and when the app comes to the front). Only
    plays that start in the first minute count, and not the listener's own
    files. The numbers wait for a build on the phone. The speech pace is the
    largest lever on a stream: at 6, 12 and 25 times real time the shelf passes
    99, 112 and 136 of 219 as a stream.
- [x] **W2 Read ahead when Wi-Fi comes back** (phone, small): the look that
      fetches the next two of Up Next runs only when Up Next changes or an
      episode starts or ends, so episodes queued away from Wi-Fi are not fetched
      when the phone comes home. It also runs when Wi-Fi returns, when the app
      comes to the front and in the background refresh. More than two ahead
      waits for W1's numbers.
  - Files: `ios/PodcastDownloadAhead.swift`, `ios/PodcastNetwork.swift`,
    `automaticRun.ts`; the rule stays `DownloadAhead.plan`.
  - Done when: a test shows a queued episode starts after Wi-Fi returns. Worth
    up to 28 breaks (13 points) on plays that would have been streams, nothing
    on the finished number.
  - Result: built. Nothing looked at Up Next on a Wi-Fi return, on the app
    coming to the front or in the background refresh before (`automaticRun.ts`
    did not call it at all); `DownloadAhead.NetworkWatch` and a native
    `lookAhead` do now. The rule and the limit of two are as they were.
- [x] **W3 Apple's row and the unmarked stretches** (cloud, free): when
      `apple-model.json` is done on the Mac I score the shelf with both label
      sets and `--stream`. Apple's model is already on in the app, so its row is
      what today's phone really does. It stays as it is when the row passes at
      least 3 more breaks than the row before with at most 1 more skip with no
      ad. When it passes 3 fewer or adds 3 skips, a small milestone turns its
      answers into questions through the per-show settings. I also read the 19
      unmarked stretches: if they are ads, the exact labels become the headline.
  - Done when: both tables and the decision are written here.
  - Result (Apple's answers for all 63 shelf episodes, scored 2026-11-24): the
    model makes the phone worse. On Claude's labels (219 breaks) the row before
    passes 140 with 20 skips with no ad, with Apple's answers 118 with 183 (3.5
    an hour). On the snapped labels (242 breaks) 131 and 19 against 109 and 181.
    As a stream at the assumed pace 109 and 19 against 95 and 188; ready 137
    against 115. Keeping only its sure answers gives 122 and 70, only sure ads
    of the kind `ad` 126 and 53, sure ads and promos 122 and 68, so no part of
    it helps. Of its 144 unsure answers of the kind `ad` 124 are wrong (under
    20% of the stretch is a marked ad), and 121 of 129 unsure credits. Decision:
    its answers become questions by default (W3b below). The head scan's wait
    for the model costs 3 breaks as a stream (112 against 109 without the wait).
    The 19 unmarked stretches are not read yet.
- [x] **W3b Apple's model asks and does not skip** (phone and Mac settings,
      small): a finder `apple-model` in `ShowTuning` with the built-in default
      `ask`, applied to Apple's list before the join as for the other finders,
      the head scan not waiting for the model unless it may skip, the
      scorecard's Apple row applying the same settings, and `teach_settings.py`
      choosing it per show by the same rule as the other finders.
  - Done when: under the built-in default the Apple row equals the row before it
    (140 of 219 on Claude's labels, 20 skips with no ad), and a show whose
    setting is `skip` still gets the old behaviour.
- [x] **W4 Sound at the edges, measured first** (built in the cloud, run on the
      Mac's audio by an RC session or one double-click, free, about an hour):
      `podcast-teach edges` works out, for every half second of each shelf MP3,
      the loudness, a 24-band spectrum and whether it is a pause. A change score
      compares the 3 seconds before a point with the 3 seconds after, at the
      starts and ends of the exactly placed spots and at as many random points.
  - Go: the strongest change within 10 seconds lies within 1 second of at least
    70% of exact edges, and of at most 10% of random points. Then a scorecard
    row "Plus the sound at the edges" moves found edges onto it, and it is built
    into the app (beside the joint snap) only when that row passes at least 8
    more breaks on the exact labels with no more skips with no ad. It can win at
    most the 41 failing spot breaks.
  - Files: `PodcastAudioMatch/EdgeSound.swift`, `podcast-teach`, one launcher.
  - Result (2026-11-24, 43 shelf episodes, 232 exact edges, the same number of
    random points): the strongest change is within 1 second of 84 exact edges
    (36%), within 2 seconds of 117 (50%), within 5 seconds of 167 (72%); for
    random points 14%, 18% and 40% (chance is about 10%, 20% and 50% inside 10
    seconds). Verdict: no go. The sound does point at the edges, but not near
    enough to the 70% in 1 second, so nothing of it goes into the app. The
    change score's weights were a first guess; a trained one is the one more
    try, but half of the late starts are 18 to 97 seconds late, out of any
    snap's reach.
- [x] **W5 A small language model, tried first** (Mac, free, some hours at
      night): `teach_passage.py` runs in the Mac's `python-mood` environment
      (MiniLM-L6, about 23 MB once shrunk). It reads five lines at a time and
      says what the middle line is. It learns from the 651 marked episodes off
      the shelf and answers for the shelf. The answers go through the word
      model's decoder and are saved like Apple's (`passage-model.json`, no
      words), so the scorecard gets a row "Plus the passage model".
  - Go: the row passes at least 10 more breaks than the last finder row on both
    label sets and adds at most 2 skips with no ad. Then it becomes a Core ML
    model in the app (about 25 MB, an hour of episode in under 10 seconds), in
    the whole-file pass only. It can win at most the 32 failing host-read breaks
    and the 17 long late starts. The meaning model, a close relative, failed its
    gate (68% right), so this has even odds.
  - Files: `Tools/mac/teach_passage.py`, a launcher, `AppleScoreRow.swift` made
    general; on a go `PodcastAdsOnDevice` and `modules/podcasts/ios`.
  - Result (2026-11-24, trained on 651 episodes, answering for the shelf): line
    accuracy 90%, any ad line by line precision 56% and recall 81%. The row
    "Plus the passage model" passes 103 of 219 (47%) against 140 on Claude's
    labels, with 370 skips with no ad (7.0 an hour) against 20, and 93 of 242
    against 131 on the snapped labels. Verdict: no go. A small model that reads
    five lines is wrong about as often as Apple's much larger one: host-read ads
    are not told from the show by their words alone.

**2. The Mac reads ahead** (about $0.19 an episode of Mo's Claude plan)

- [x] **W6 The phone tells the Mac what is next** (phone, small):
      `Podcasts/phone-queue.json` in the linked folder: Up Next in order, then
      the newest unplayed episode of each show played in the last 14 days, 12 at
      most, each with feed, guid, title and audio address.
  - Files: `modules/podcasts/phoneQueue.ts` with tests, `phoneNotesSync.ts`.
- [x] **W7 The nightly job** (Mac): `teach-ahead.sh`, made like
      `teach-weekly.sh`: a launchd job at 2:00 at night reads the queue,
      downloads at most 8 episodes it has not marked, writes them down, has
      Claude mark them (budget `ahead-<year>-W<week>`, a hard stop at the weekly
      cap) and publishes `ahead-ads.json`: for each episode (feed and guid) each
      ad's kind and the 40 words at its start and at its end, kept 14 days. The
      marked episodes also join the teaching set, never the shelf or the exam.
  - Mo: one double-click on "Install nightly read-ahead.command" and a typed
    yes. I ask before I leave it for him.
  - Files: `Tools/mac/teach-ahead.sh`, `teach_ahead.py`, two launchers (install,
    stop), `teach_publish.py`, the Mac README.
- [x] **W8 The phone uses the marks, tested on the bar**: `AheadAds`, a finder
      named "ahead", looks for an episode's start and end words in its
      transcript (the whole file and the head of a stream) and gives the ad with
      Claude's edges. Words, not times, because the phone's copy can carry other
      inserted ads. With no file or no entry nothing changes: the phone still
      skips alone.
  - Go: `score --ahead` adds a row "Plus the Mac's marks from the night before",
    which knows an episode's own marks but not its spots that differ between two
    downloads (with no second download, none of its spots). At least 20 more
    breaks pass with at most 1 more skip with no ad.
  - Honest value: on the shelf the marks are also the truth, so this row only
    proves the matching. The real number is the exam's 15 episodes marked twice,
    with the second marking as the night's marks (W9). Only episodes that were
    in the queue the night before are helped.
  - Result (2026-11-24, shelf, `score --ahead`): on Claude's labels 140 to 166
    of 219 breaks pass (75.8%) with no more skips with no ad (20); on the
    snapped labels 131 to 149 of 242 (the go rule's 20 more is missed by 2); as
    a stream at the standard pace 112 to 137 of 219 (ready: 163). Marks of low
    confidence only ask; they never skip. As said above, the shelf's marks are
    also its truth, so this is the matching's ceiling, not a measured gain: the
    exam says what the phone gets from a second marking.
  - Files: `PodcastAds/AheadAds.swift`, `AdScoreCommand.swift`,
    `teachingSync.ts`, `ios/PodcastAdFinder+Ahead.swift`,
    `ios/PodcastAdFinder+New.swift` and `ios/PodcastStreamHead+Local.swift`.
- Review fixes to W6 to W8 (branch `round-b/fixes`, nothing ticked):
  1. Lock (W7): `teach-ahead.sh` runs under `teach_store.py hold` for the whole
     night, ends quietly with exit 0 when another run holds the lock, and does
     nothing on Sunday, so it never meets the weekly run at 3:00. `hold` tells
     the tools it starts that the lock is theirs (`TEACH_LOCK_HELD`); a first
     version without that refused every tool and the night did nothing, found by
     the second review.
  2. Up Next always in the table (W6, W8): `aheadEpisodesText` always adds the
     episodes of `phone-queue.json` to the phone's lookup table, older ones
     included, besides the newest 12 of each show.
  3. Low marks only ask (W8): a mark Claude gave "low" gives a question (at most
     3 an episode), never a skip, and is not in a stream's head scan; high and
     medium work as before.
  4. The exam's "newer than" rule (W6, W7): the phone puts each episode's
     published time in `phone-queue.json`, `teach_ahead.py` keeps it, and a
     read-ahead episode with no time blocks exam picks from its feed.
  5. The weekly cap (W7): a call that timed out or printed no cost counts as one
     expected call (19 cents), and every call is written in the budget file at
     once, not after the episode.

- Mo's asks of 2026-11-25 (Mac tools, no phone change):
  1. Marking at any hour: `Gather deeper and mark now.command` is the "tonight"
     launcher with `TEACH_BETWEEN=0-24`; it is on the Mac and has its copy and
     test in this pull request.
  2. Free the disk, learn first then free (Mo chose this 2026-11-25):
     `podcast-teach sounds` saves each learned episode's ad-sound material in
     `sound-bank/<id>.json` and rebuilds `ad-sounds.json` the same from audio or
     from the bank. `Free up space from the teaching audio.command`
     (`teach_free.py`) then deletes the audio of an MP3 episode only when its
     transcript, marks, sound bank and second-download truth are kept (not the
     shelf, the exam or the read-ahead), after a checked backup and a typed yes;
     typing `all` also frees those still waiting for a second download. Done
     when: the Swift and Python tests pass (a library rebuilt after deleting an
     audio file is byte-identical), an independent check finds nothing wrong,
     and Mo has run "Teach the phone again" so the banks exist.
  3. Marking sooner (Mo, 2026-11-25: "usage is the same"): the big-run launchers
     write down every episode before any is marked, so the marking waited hours.
     `Write down and mark together.command` writes down 20, marks them at any
     hour, and repeats.
  4. Automatic big runs while they keep improving the ad skipping and the other
     model (not built; the limits wait on Mo's answers: how much to spend in
     all, what counts as improving, and whether to stop at night only).
  5. Transcripts from outside (Mo, 2026-11-25: "find episodes with transcripts
     already available online", for his own shows and for podcasts in general).
     `Count publisher transcripts in my shows.command` counts the shows of his
     63 that carry a publisher's transcript. No public set of podcasts has ad
     marks that anyone may use; the biggest public transcripts (SPoRC, over a
     million episodes, research use only, behind a Hugging Face login) have no
     ad marks either, so they would need Claude's marking to be used. Mo chose
     "Yes, small sample first" (card, 2026-11-25):
     `Fetch a sample of public transcripts.command` (`sporc_sample.py`) writes
     about 200 episodes as a teaching folder of its own after Mo makes a free
     Hugging Face account and agrees to the terms. The sample is made (200
     English episodes, 200 shows, 186 hours). Mo chose "Bigger: 100 episodes, up
     to $20" (card, 2026-11-25), then said up to $100 and asked to test whether
     ad detection improved significantly afterwards. So the fetch takes 500
     episodes and `Mark the public transcripts.command` marks up to 500 under
     the budget `sporc-1` (cap
     $100). `Test the public marks.command` trains the
     word model with and without them and compares the held-out shelf. Mo asked
     for one click ("can you make it one click?"), so
     `Fetch, mark and test the public transcripts.command` runs the three in
     order after one typed yes. Mo then asked for another $100
     pull ("so it is
     $200"), so `Fetch and mark 500 more public transcripts.command`
     fetches up to 1000 episodes and marks under the budget `sporc-2` (cap $100),
     leaving the running test alone. Done when: the word model's held-out
     precision and recall and the whole pipeline's breaks passing
     (`podcast-teach score`, 140/131/109 before) are measured with and without,
     and Mo has the answer. "Significantly" means the round's own gate: 10 more
     breaks passing and at most 2 more wrong skips. Result (2026-11-26, cloud
     score on the 63-episode shelf): the public marks did not help and made it
     slightly worse (the model with the library 142 to 132 breaks passing,
     per-show settings streamed 115 to 107, skips with no ad 15 to 18), so the
     gate failed and the public set stays out of training (it is research-use
     only anyway). Mo then asked to free the disk and prepare another run on his
     own shows, so `Free space and start the next run.command` runs the audio
     cleanup and then starts a new $95 budget with the newest 30 of each show,
     marking at any hour.

**3. The exam**

- [ ] **W9 Gather, mark and score the exam** (Mac, up to $18 of the plan, Mo's
      typed yes): not before 2026-11-27. Mo double-clicks "Gather the exam
      episodes" and types yes; the marking runs from 11 at night to 7. Then
      "Check ads with a second download" (free) and Apple's model with `--exam`.
      I score it twice and never tune on it: today's app (35.1) and the round B
      branch, each with `score --exam`, the exact labels and `--stream`.
      `podcast-teach agree` says how often two markings agree within 5 seconds,
      which is the ceiling for any phone.
  - Done when: Mo has the fair number, the ceiling and W8's real number.
- [ ] **W10 One pull request, one build**: the parts that passed their gates,
      the tables of W3 to W9 in the pull request, Fork CI green, the Fable
      check, Mo's OK, then one TestFlight build from the Mac through RC.

Order: today the cloud builds W1, W2 and the tools of W4 and W5, and I score W3
when the Mac's Apple run ends. Tonight the Mac runs W4 and W5. Tomorrow the
gates are read and the cloud builds W6 to W8, and the phone parts of W4 and W5
only on a go. From 2026-11-27 the exam runs at night; W10 follows its score.

What this can honestly reach. The finished number is 64% today. W1 and W2 move
only the stream number (50%) toward the ready number (63%). Sound at the edges
is worth 5 to 10 points if its measurement passes, and the passage model 0 to 7.
So the phone alone ends near 65% to 78%, most likely the low 70s; the earlier
"75% to 85%" was too hopeful. With the Mac's marks, queued episodes may reach
80% to 90% against Claude's own marks, and never more than Claude agrees with
itself, which the exam will say. 95% of all streamed breaks is unlikely in this
round. The largest thing left is exact edges for inserted spots: the second
download moved 159 of the shelf's 326 paid spots, so a second copy on the phone
(idea 5, not on Mo's card) is the next candidate.

The second copy, measured (Mo, 2026-11-26: "test it and tell me if the 2
downloads is worth it"). A trial scorecard row skipped the stretches where the
Mac's second download differs (5 s or longer, as sure ads, outside the ads the
row stands on), using the Mac's second downloads of the 63 shelf episodes, made
about a day after the first, so it is the best case. With Claude's labels it
passed 142 to 147 of 219 alone and 162 to 167 with the night-before marks; with
the exact labels 129 to 133 and 147 to 151 of 222. Never a wrong skip more, but
4 or 5 breaks where the gate needs 10, so no go: the finders already skip most
inserted spots, and what fails is edges. Trimming the found ads to the differing
stretches' edges made Claude's labels worse (142 to 126: breaks also hold a
lead-in or a promo that is the same in both copies), and its +19 on the exact
labels is circular, because `teach_snap.py` moved those labels' borders onto the
same stretches. One re-edited episode (The Daily, `b97026c08408`, 86% differing)
is two versions, not other ads, so the rows leave out an episode whose stretches
cover more than half of it. The trial code is not kept; the patch and both
scorecards are in the project files (`podcast-bar/trials/second-copy/`). Not
built, and the phone test "Test two quick downloads of my shows" is not needed.

Why breaks fail, and quick trials of timing fixes (Mo, 2026-11-26: "how can we
improve this timing. Think of creative ways"). Without host reads the same row
passes 122 of 161 breaks (76%), streamed 98 (61%). Of the 77 breaks that fail
with Claude's labels, 26 are off by 10 s or less, 9 are missed (all hosts' plugs
for their own things), and 42 are bigger: in 35 of them a piece of the break of
10 to 100 s is not recognised (sponsored content that reads like news, a
story-style spot after a handoff, a host read that starts as normal talk).
Replays of the bar on `score --dump` (Python, not in the repo; the scripts are
in the project files, `podcast-bar/trials/timing/`) gave: moving every start or
end by a fixed 1 to 5 s, and joining skips that lie close together, make it
worse; pulling a skip's start back to a learned opening line (a line prefix that
starts a marked segment in 5 or more training episodes, 9 times in 10) passes
142 to 147 (exact labels 129 to 133) with no wrong skip more at any setting
tried; filling a hole of up to 60 s between two skips that shares a rare word
with them and few words with the show passes 4 more, but its limits were picked
on the shelf; both together 151 of 219 and 137 of 222. The test is also too
harsh at ad ends: the Mac's transcripts hold only line starts, so a line ends at
the next line's start, while the phone's lines end at their last word. Exact ad
starts lie within 1 s of a line start 86 times in 100, exact ends 46, and 13 of
the 25 "lands too far" breaks on the exact labels lose no spoken line. Nothing
is built; Mo's card asks whether to build the two fixes.

Mo's answers (2026-11-24): the nightly cap is
$10 a week (about 50 episodes), 8
a night, a hard stop. He chose "Two big runs, then $10
a week": two big teaching runs of up to
$95 each a few days apart, then the nightly marking as
maintenance. The exam (W9, up to $18,
his typed yes) moves to about 2026-12-03, after the second run plus three days.

Questions only Mo can answer:

1. (answered) The nightly cap.
2. May I leave "Install nightly read-ahead.command" for his double-click when W7
   is checked? Recommended: yes.
3. Do end-of-show "subscribe, rate us" count as ads? Open since round A.
   Recommended: no.
4. One tap on "Send skip log" in 35.1, only if W1 finds no diary on the Mac.

### Ad skipping: timing fixes and the skip tap (Mo's ask, 2026-11-26)

Mo: "Build 1-3. If I skip at a part of an ad, skip the whole ad not just the 15
seconds. Also if not sure and I skip, skip the whole ad then. It's probably an
ad then". Fixes 1 to 3 are the trials above: learned opening lines (1), handoff
lines (2) and filled holes (3). Handoff lines learned on their own (the show's
line just before a break) add nothing on top of the opening lines (147 of 219
either way), because Claude marks most handoffs as the first line of the break,
so they are learned as opening lines and have no list of their own. Fable
planned it, Sonnet builds, Opus checks, Fable checks last. One pull request
(#58) and one TestFlight build.

How I read the ask (Mo was away, so these are my choices):

- "Skip" is the skip-forward button, in the app, on the lock screen and on
  headphones. The Skip ad button, skip back and the seek bar stay as they are.
- "Not sure" is one of three things: a question the phone would ask, a stretch
  the word model gives a weak chance of being an ad (a "maybe", new), or a hole
  of a minute or less between two ads.
- A stretch the listener took back with Undo is never left this way.

**The file `ad-cues.json`** (the Mac writes it, the phone and the scorecard read
it; it goes the way `ahead-ads.json` goes and holds words of transcripts, so it
is never committed):

    {"version": 1, "writtenAt": 1700000000, "episodes": 1170,
     "starts": ["this episode is brought", "..."], "returns": ["..."],
     "shows": [{"feed": "<feed address>", "starts": ["..."], "returns": ["..."]}],
     "common": ["about", "..."], "usual": ["..."]}

- A cue is the first 3 to 6 words of a transcript line, as
  `teach_features.tokens` and `AdWordModel.tokens` make words, joined by one
  space. A line matches a list when one of its own first 3, 4, 5 or 6 words,
  joined the same way, is in the list.
- It is learned from the marked episodes that have a transcript and are not on
  the shelf, not on the exam and not a repeat of one (the episodes
  `teach_train.py` learns from). The marked segments are those of the sorts
  sponsor, network_promo and host_ask with confidence high or medium; segments
  that lie within 1 s of each other are one break.
- A line "opens" when it starts within 1 s of a marked segment's start. A line
  is "in an ad" when it starts from 0.3 s before a break's start to 0.5 s before
  its end. A line is a "return" when it is not in an ad and the line before it
  is.
- `starts`: a cue that opens in 5 or more episodes, where 9 in 10 or more of all
  the lines that begin with it open. A show's `starts`: the same within the
  show, with 3 or more of its episodes. `returns` and a show's `returns`: the
  same for return lines. Only the shortest cue that qualifies is written (a
  longer one that begins with a written cue of the same list, or with a general
  one, matches nothing more).
- `common`: the words of 4 letters or more that occur in more than 15 in 100 of
  those episodes. `usual`: those in more than 5 and at most 15 in 100.
- It is about 150 KB. The phone refuses a file over 5 MB.

**Opening lines** (finder `opening-lines`, `CueAds.openings`). Given the lines
of the whole transcript and the skips so far (the ads that are skipped, joined
into stretches whatever their kind): for each line in order of time that is not
inside a stretch and matches a start cue (a general one or its show's), take the
stretch with the nearest start after the line, at most 60 s after it. When no
return line starts between the two, the stretch from the line's start to that
start is added as an ad of the kind of the stretch's first ad, unsure, with the
finder's name. A stretch is pulled back once. The reach was 120 s in the first
build; one of the seven pulls on the shelf went back 83 s over the show to a
line that only sounded like an opening, and no right pull was longer than 50 s,
so it is a minute now (see the results below).

**Filled holes** (finder `filled-holes`, `CueAds.holes`). Given the same, after
the opening lines are added: for two stretches next to each other with a hole of
more than 0 and at most 60 s between them and no return line starting in the
hole, look at the lines that start in the hole (from 0.2 s before it to 0.2 s
before its end). A content word is a word of 4 letters or more that is not
common; a rare word is a content word that is not usual. The hole is filled when
both hold: (echo) at least one rare word of the hole also occurs in a line of
one of the two stretches and in no line of the show outside the hole and the
stretches; (topic) at most a quarter of the hole's content words (counted as
often as they occur) occur in a line of the show outside the hole and outside
every stretch. A hole with no content word is not filled. A filled hole is added
as an ad of the kind of the stretch before it, unsure, with the finder's name;
the two stretches and the hole then count as one stretch (for the echo) and the
next hole is looked at. The lines of the show are counted once, from the skips
as they were given, so the lines of a filled hole still count as the show's for
the holes after it (as in the trial that was measured).

Both add stretches that touch the ads they stand next to, on purpose: the other
new finders keep 0.6 s away from every ad, which would leave a blip of the ad to
hear. On the phone they run last in the whole-transcript pass, after the borders
were put on the joints, under the finder guard, at the level `skip` by default
(`show-settings.json` can switch them off for a show; "ask" reads as off, they
ask nothing). They never add over a stretch the listener undid or said no to,
and only kinds the listener skips. With no `ad-cues.json` they add nothing.

**The skip tap** (`AdSkipTap.decide`, a rule next to `AdSkipNow.decide`, used by
`PodcastPlayer.skip(by:)` for a move forward). In this order:

1. Right after an automatic skip (as `AdSkipNow` defines it) the tap is a plain
   move (taken to the end of a skipped ad it would land in, as in case 6).
2. The playhead is in a known ad (from 2 s before its start, any kind, cut by
   the listener's trims, not undone): leave it and the ads that follow it at
   once, like the Skip ad button, with the note and Undo. The tap also carries
   over holes of 15 s or less to the ads that follow (see X7).
3. The playhead is in an open question: the tap is the answer yes.
4. The playhead is in a maybe (from 2 s before its start, as for a known ad): it
   becomes a confirmed ad (as a yes does) and is left, with the ads that follow
   it at once.
5. The playhead is in a hole of 60 s or less between two ads that are skipped:
   go to the end of the ads after the hole, and note a miss for the hole.
6. Otherwise move ahead by the button's seconds; when that lands inside an ad
   that is skipped, go on to its end (today the ad then plays).

**Undo and the two finders** (`AdSkip.takenBack`, found by the Opus check). A
stretch of the opening lines or the filled holes is skipped in one jump with the
ads it touches. An Undo of such a skip takes back only those stretches: the
playhead goes to the first of them, and the other ads are skipped again when it
reaches them, with an Undo of their own. So a pull that started too early costs
the listener no ad to hear, and the finder that found the ad is not blamed (two
Undos turn a finder to "ask" for a show). A skip with none of these stretches,
or of them alone, is taken back whole, as before.

A maybe is a stretch kept in the ads file (`maybes`, a new optional list, so old
files and old builds read on): the word model's spans at a start chance of 0.30
and a stay chance of 0.15, of the three ad sorts, the parts of 8 s or more that
lie outside every ad and question of the file, plus the finders' stretches that
were not sure enough to skip and did not become one of the three questions. At
most 20 an episode. A maybe is never shown or asked; it is made only by the
whole-transcript pass; one that a tap confirmed is kept through later writes of
the file the way an answered question is. On the 60 breaks of the shelf that
fail with ad left to hear, a listener who taps skip 3 s into each piece needs 5
taps a break today and about 2 with this, and 24 breaks instead of 3 are left
with one tap.

**The gate**, as for every finder: on the 63 shelf episodes the two rows
together must pass 10 more breaks than the row they stand on, with at most 2
more skips with no ad. The Python trial (the app's own way of making words) gave
152 of 219 (+10) with Claude's labels and 138 of 222 (+9) with the exact ones,
no wrong skip more. The skip tap has no bar number (the bar counts skips with no
tap); its proof is the rule's tests and the phone.

**Results** (2026-11-27, `podcast-teach score` on the 63 shelf episodes, with
the cues `teach_cues.py` learned from the 1,162 teaching episodes of the cloud's
copy: 202 opening and 21 return lines for every show, 233 and 30 more for 57
shows):

| Row                            | Claude's labels | Exact labels    |
| ------------------------------ | --------------- | --------------- |
| The row they stand on          | 142 of 219      | 129 of 222      |
| Plus opening lines             | 147             | 133             |
| Plus filled holes              | 152 (+10, go)   | 138 (+9)        |
| The same as a stream           | 114 to 123      | 102 to 110      |
| On the Mac's marks (`--ahead`) | 162 to 169 (+7) | 147 to 153 (+6) |

- The exact labels miss the gate by one break. Mo asked for the build knowing
  the trials' +9, the skips with no ad do not rise, and every skip of these
  stretches has an Undo, so both finders ship at the level skip.
- "Skips with no ad" reads 16 (was 17) and 15 (was 16). That is no gain: in one
  episode an opening line joins a skip of credits to the skip of the break after
  it, and the pair counts once. The same show time is cut as before.
- The first build reached back 120 s and gave 151 and 137. One of its seven
  pulls went back 83 s over the show to a line that only began like an opening
  (a show's own cue of three words), in front of an ad whose start was already
  right. No right pull was longer than 50 s, so the reach is 60 s now. That was
  chosen knowing these episodes, so the +10 flatters a little.
- A cross-check on the teaching episodes only (cues learned on four fifths, the
  lines of the last fifth looked at, five times): of 4,506 matching lines 4,260
  open an ad, 163 lie inside one, 64 have no ad near, and 19 lie in the show
  within 120 s before an ad, 5 of them more than 60 s before it. So about 1
  matching line in 250 can pull wrongly, which is about one pull in 60 episodes,
  as on the shelf. Stricter cues (more episodes, 19 in 20) lose more right lines
  than wrong ones.
- The trial said 152 and 138 at 120 s. It joined stretches only when they touch;
  the scorer and the player chain ads within half a second, which is the one
  break of difference.

- [x] **X1 The Mac learns the opening lines** (Mac): `teach_cues.py` writes
      `<folder>/ad-cues.json` by the rules above (`--folder`, `--labels`);
      `teach-finish.sh` runs it after the model is trained (the shelf is then up
      to date) and `teach_publish.py` copies it like the other files, with no
      gate but its shape (version 1 and the lists).
  - Done when: its tests pass (made-up lines only), and on the cloud's copy of
    the teaching folder it writes the opening lines of the 1,162 episodes that
    teach (202 for every show and 233 for single shows; only the shortest cue
    that qualifies is written, so far fewer than the trial's count of all).
- [x] **X2 The two finders** (PodcastAds): `AdCues` reads the file (a show by
      its feed, as `ShowTuning` does; a damaged file reads as empty) and
      `CueAds` holds the two rules.
  - Done when: tests pin each rule on made-up transcripts (the return line that
    stops a pull, the two 60 s limits, echo and topic, a chain of two holes) and
    bad input adds nothing.
- [x] **X3 The scorecard rows**: "Plus opening lines" and "Plus filled holes",
      last in the scorecard, standing on the Mac's marks row when `--ahead` is
      given and on the last finder row otherwise, with the verdict line of the
      gate and a stream number with `--stream`.
  - Done when: `podcast-teach score` on the shelf prints both rows for both
    label sets and the numbers are written here.
- [x] **X4 The phone runs them**: `ad-cues.json` is synced, checked and loaded
      with the other teaching files; the two finders run as said above.
  - Done when: Fork CI builds the app, and the timeline of an episode says how
    many stretches each finder added.
- [x] **X5 The skip tap**: `AdSkipTap`, the maybes (`AdMaybes`, `AdsFile`), the
      player's `skip(by:)`.
  - Done when: tests pin each of the six cases and the carrying of a confirmed
    maybe, and Fork CI builds the app.
- [x] **X6 One pull request, one build**: the whole check, the Opus check, the
      Fable check, Fork CI green, the merge, one TestFlight build from the Mac,
      and the Mac's teaching tools brought up to date so its next "Teach the
      phone again" writes and publishes `ad-cues.json`.
  - Done 2026-11-27: PR #58 merged as b10119d, TestFlight 37.1 uploaded from the
    Mac. The Mac wrote `ad-cues.json` from 1,581 episodes; publishing it from
    here was refused by the Mac's permission check, so it reaches the phone with
    Mo's next "Teach the phone again" or the weekly run.
- [x] **X7 One tap leaves the whole break** (Mo's ask, 2026-11-27: "if two ads
      back to back, one click should skip both"): a tap on Skip ad or skip
      forward inside a known ad also takes the ads that follow after a hole of
      15 s or less (`AdSkipNow.carryHole`), when the switches skip them, they
      were not undone, and nothing the listener keeps lies in the hole: an
      undone or "no" stretch, an ad of a kind whose switch is off, or what a
      trim cut off an ad (`AdsFile.carryBlocks`). It stays one jump with one
      Undo. Automatic skips do not carry.
  - Why 15 s: on the 63 shelf episodes 12 of the 14 holes of 15 s or less
    between two skipped stretches were ad for three quarters of their length or
    more (16 s of show in 114 s); of the 16 holes of 15 to 30 s, 9 held more
    than 5 s of show.
  - The Undo of a carried skip is about the carry, since the listener chose to
    leave the ad: the playhead goes to the first hole (`AdSkip.carriedFrom`), no
    ad is saved as undone and no finder is blamed. The ads behind the hole are
    skipped again when the playhead reaches them, with an Undo of their own.
  - Not carried into: a maybe or an open question. The phone is unsure there,
    and a second tap inside it confirms it and carries on.
  - A carried hole leaves no note. A miss would count against the phone on the
    tally for a tap the listener made inside an ad the phone knew.
  - Done when: tests pin the carry (the 15 s limit, several holes in a row, the
    switches, what stops it, both buttons) and its Undo, and Fork CI builds the
    app.

Left for later: the two finders in the first minutes of a stream (they need the
whole transcript), an own pass for episodes whose ads file was final before the
cues arrived, per-show levels for them from `teach_settings.py`, and a tap's
carry into a maybe or an open question (the shelf labels hold no maybes, so
nothing says how often that would take show).

### Prepared episodes: the Mac prepares, the phone plays its copy (Mo's pick, 2026-11-27)

Mo: "ad skipping is pretty disappointing for me. I need more ideas. Even ones
that would cost money to have a more sure better way to skip ads. Is the work on
the computer currently looking at all the recent shows across my podcasts? If
not, it should." On the card "Have the Mac prepare new episodes so the phone
plays its copy?" he picked "All new episodes, all shows" (about $32 a week of
Claude usage and 8 GB a week through iCloud). Fable planned it, Sonnet builds,
Opus checks, Fable checks last. One pull request and one TestFlight build.

Why this is surer: a host puts other ads into every download, so marks made on
the Mac's copy do not hold on the phone's copy. On the shelf the nightly
read-ahead could use 260 marks and had to leave 244 out. When the phone plays
the very file the Mac marked, the Mac's times hold to the frame. Played on the
same copy, Claude's marks pass 190 of 242 exact breaks with no skip where there
is no ad, before any border is moved to where two downloads differ; the phone's
own finders pass 132 of those 242.

How I read the pick (my choices, told to Mo):

- A hard weekly limit of
  $35 of Claude usage. The last 7 days had 181 new episodes over 63 feeds, and at $0.19
  each that is about $34. The phone's list of next episodes goes first, so the
  limit cuts what is least likely to be played.
- Prepared audio stays in iCloud for 7 days and takes 10 GB at most (Mo is asked
  on a card; the installer says how much iCloud space is free when macOS tells
  it).
- The phone takes the Mac's copy for the episodes it expects to play next (its
  list of 12) and for episodes it has downloaded and not started, on Wi-Fi only.
  Everything else streams and is skipped as before.
- An episode that was started is never swapped. Its position and its ads stay on
  the copy it was started on.
- On a prepared copy only the Mac's marks skip by themselves. The phone's own
  finders leave that copy alone. The listener's taps, the Undo and the Skip ad
  button work as on any episode.
- The hourly job takes the place of the nightly read-ahead (W7), which was never
  installed. Nothing on the Mac spends anything before Mo double-clicks the
  installer and types yes.

**The contract** between the Mac and the phone is `ahead-ads.json`, still
version 1, so an older build reads it as before. An entry may carry a copy:

```json
{
  "feed": "…",
  "guid": "…",
  "title": "…",
  "marked": 1700000000,
  "ads": [],
  "copy": {
    "file": "prepared/0123456789ab.mp3",
    "sha256": "<64 hex>",
    "bytes": 48123456
  }
}
```

`file` is relative to `Podcasts/` in the linked folder and is always
`prepared/<a plain name>`. With a copy, `start` and `end` of the entry's ads are
seconds in that very file, taken from `labels-snapped` when the second download
was compared and from `labels` when it was not. An entry with a copy is kept
when it has no ads, because that says the episode has none. When the Mac removes
the audio the entry loses its `copy` and is a words-only entry again. The phone
trusts a copy only when its size and its SHA-256 match.

- [x] **Y1 The Mac picks new episodes of every show** (Mac):
      `teach_prepare.py pick --budget NAME [--cap 35] [--most 6] [--hours 72]`.
      First the phone's list, as `teach_ahead.py pick` reads it, whatever the
      episodes' age. Then the episodes of every followed show
      (`probe_shows.load_shows`, `teach_feed.feed_episodes`) that came out in
      the last 72 hours, newest first. Known episodes are left out by the rule
      of `teach_ahead.choose`, which is used and not copied. At most `--most` a
      run, and no more than the weekly budget `prepare-<ISO year>-W<ISO week>`
      has room for (`teach_budget.py`, the rule of `teach_ahead.choosing`). A
      feed that cannot be read is said in one line and passed over. What is
      picked goes into `ahead.json` and `episodes.json` as the nightly pick's
      does, so the download, the writing down and the marking run unchanged with
      `--only-ahead`.
  - Done when: tests pin the order (the phone's list, then the newest), the 72
    hours, that known episodes are left out, the limit a run and the weekly
    limit, a feed that fails, and exit 3 with one plain line when there is
    nothing to do.
  - Done 2026-11-27. Added after the check: an episode of a feed that states a
    language other than English is passed over and counted in the pick's line,
    because the Mac writes down in English only and the phone would trust marks
    made on a garbled transcript.
- [x] **Y2 The copy and its exact times** (Mac):
  - `teach_copies.py --only-ahead` compares only the episodes of `ahead.json`
    that have no truth file yet. `teach_snap.py` runs as it is.
  - `teach_prepared.py publish` copies the audio of each marked episode of
    `ahead.json` into `Podcasts/prepared/<id>.<ext>` of the iCloud copy of the
    phone's folder (a clone with `cp -c` where the disk can, written as `.part`
    and then renamed) and notes it in `prepared.json` in the teaching folder:
    id, file, SHA-256, bytes and when. It publishes nothing when the iCloud
    folder is missing, when the Mac's disk has under 15 GB free, or when macOS
    says (`brctl quota`) that iCloud has under 2 GB left, and says which in one
    line.
  - `teach_ahead_ads.py` gives an entry its `copy` when `prepared.json` lists
    the audio and the file is there, takes the times from
    `labels-snapped/<id>.json` when there is one, and keeps an entry with a copy
    and no ads.
  - `teach_prepared.py clean` removes prepared audio older than `--keep-days 7`
    and then, oldest first, what is over `--max-gb 10`, from the iCloud folder
    and from `audio/`. It removes only files that `prepared.json` lists and
    whose names are `<12 hex>.<ext>`, and never a transcript, a label or
    anything else.
  - Done when: tests pin the copy block and its hash, an entry with no ads, the
    times from the snapped labels, the clone written as `.part` first, cleaning
    by age and by size, that nothing outside `prepared.json` is ever removed,
    and the three stops for low space.
  - Done 2026-11-27. Changed while building: a copy is published only once the
    second download is settled (a truth file, given up on, or not an MP3), so
    the times the phone gets with a copy never change, and an episode that is
    not settled waits for a later hour. An episode that was picked and never
    published is listed in `prepared.json` too, so its audio on the Mac goes
    after the keep days, and a leftover `.part` of a listed id goes after a day.
- [x] **Y3 The hourly job and its installer** (Mac): `teach-prepare.sh`, made
      like `teach-ahead.sh` and held under `teach_store.py hold`: pick,
      download, write down, mark (under the weekly limit), second download and
      compare, snap, publish the audio, write `ahead-ads.json`,
      `teach_publish.py`, clean. A step that fails for one episode does not keep
      the others from the phone. "Install episode preparing.command" says what
      it does in plain words (every hour, at most $35 a week of Claude usage, at
      most 10 GB of iCloud for 7 days, the Mac must be awake), asks for a typed
      `yes`, removes the nightly read-ahead job when it is loaded, and loads
      `com.storyteller-lofi.podcast-prepare` with a `StartCalendarInterval` once
      an hour. "Stop episode preparing.command" unloads it. The README gets a
      section.
  - Done when: shell tests with stand-ins (as `test_teach_ahead_shell.py` has
    them) pin the order of the steps, that an episode that failed does not stop
    the rest, that another run in the folder makes the hour pass quietly, and
    that nothing is installed without the typed yes.
  - Done 2026-11-27. Changed while building and after the check: marking keeps 1
    dollar in reserve (`TEACH_PREPARE_RESERVE`), so it stops at about 34 dollars
    and one dear call cannot pass the limit. The installer removes the nightly
    job's file whether the job is loaded or not, and takes its own file away
    again when loading fails. The stopper asks whether the prepared episodes
    should also go from iCloud (a typed yes), says so only when they did, and
    then removes leftover `.part` files too. Found in the last read and fixed:
    the job first checks with a real write that audio can reach iCloud and that
    this Mac and iCloud have room (`teach_prepared.py ready`), and spends
    nothing in an hour when it cannot; the pick knows the marking's reserve, so
    it picks nothing the marking would refuse; the download limit counts only
    the job's own audio (`--own-gb`), because Mo's teaching folder already holds
    75 GB and a limit over all audio would have stopped every hour.
- [x] **Y4 The phone's rules for a prepared copy** (PodcastKit, plain Swift):
  - `AheadEntry.copy` (`PreparedCopy`: file, SHA-256, bytes). A copy whose file
    is not `prepared/<plain name>` or whose hash is not 64 hex digits reads as
    no copy, and the entry is still read.
  - `PreparedAds.file(for:duration:)` makes the ads file of that copy: its
    SHA-256 is the copy's, it is marked `prepared`, and its ads sit at the
    marks' times with the source `prepared`. High and medium marks skip, a low
    mark asks, as the ahead marks do. Marks are cut to the length and put in
    order.
  - `AdsFile.prepared` is an optional key, so older files still read.
    `AdsRules.status` says finished for a prepared file. Everything that writes
    found ads leaves a prepared file alone: the finder's scan, the new finders,
    the ahead pass, the stream's head and a change of the teaching. What the
    listener does still writes: the Undo, a "no", the Skip ad button.
  - `prepared` is a source the notes carry and the tally can count. It is not a
    finder the guard can switch off (`FinderGuard` keeps 8 a show).
  - `PreparedCopies.plan` says which copies the phone takes and which it gives
    back: take a listed copy when the episode is on the phone's list of next
    episodes or has a download, was not started, is not in the player and does
    not have that copy yet; give back a copy that was taken only for the list
    once the episode has left the whole list (not just its first 12 places) and
    was not started. At most 12 a run.
  - Done when: tests pin the reading (with a copy, without, a bad one), the ads
    file made from an entry, the status, each writer leaving it alone, the Undo
    of a prepared ad (saved as undone, no finder blamed), and the plan's every
    rule.
  - Done 2026-11-27. Changed while building: 12 a run and not 3, so a day's
    copies come in one run; a download that the listener or a rule asks for
    takes the "only for the list" mark off (`DownloadStore.clearCopyForList`),
    so it is never given back.
- [x] **Y5 The phone installs the Mac's copy** (phone, native):
  - LofiScore gets `copyLinkedFolderFile(path, to)`, made like
    `LinkedFolderFile.fetch`: copied, waiting (iCloud is still bringing it and
    was asked), or missing. After a copy the iCloud download is given back to
    iCloud so the audio is not kept twice.
  - Podcasts gets `preparedPlan(candidates)` (the entries with a copy matched to
    the app's episodes through the ahead table, then `PreparedCopies.plan`) and
    `installPreparedCopy(episodeId, uri)`: it checks the size and the SHA-256,
    refuses when the episode is in the player, installs the file as the
    episode's download (the entry keeps its address), writes the prepared ads
    file and tells the transcriber as a download does. A download entry gets an
    optional flag for a copy taken only for the list.
  - Done when: Fork CI builds the app, and what can be decided without the phone
    is decided in PodcastKit and tested there.
  - Done 2026-11-27 (`PodcastPrepared.swift`, `LofiLinkedCopy.swift`). After the
    check: the partial finder leaves a prepared file alone too, an episode of a
    show with ad skipping off still reaches the plan so its copy is given back,
    a file that iCloud has not brought up to date answers waiting, and copies
    are taken on Wi-Fi and not in Low Data Mode (`PodcastNetwork.allowsCopies`,
    which waits a second for the first report of the network).
- [x] **Y6 The phone asks for the copies** (phone, TypeScript):
      `preparedSync.ts` runs after the teaching sync in `automaticRun.ts`. It
      hands the candidates to `preparedPlan` (the phone's list of next episodes
      and the episodes with a download, each with whether it was started), and
      on Wi-Fi copies and installs what the plan says, and removes what the plan
      gives back. Where the app shows an episode's ad status it says "Prepared
      by your Mac". Notes of a prepared ad carry `by: "prepared"`.
  - Done when: jest tests pin Wi-Fi only, that a waiting copy is tried again on
    the next run and a failed one does not stop the others, that nothing is
    asked for without a linked folder, and the sign's words.
  - Done 2026-11-27. Changed while building: the step runs in `teachingRun.ts`
    after the teaching files and the phone's notes. No copy is started after 20
    seconds of a run, and when a copy was left waiting one more pass runs 45
    seconds later. After the check: one run at a time (`singleRun`), and the
    episode's position is read again after the copy and before the install, so
    an episode that was started meanwhile is not swapped. A miss on a prepared
    copy carries `by: "prepared"` too.
- [x] **Y7 How it is measured**: the scorecard gets the row "Prepared copy"
      (`podcast-teach score --prepared`): the snapped labels of the shelf are
      made into prepared ads files by `PreparedAds` and played on the same copy
      against the exact labels, so the row tests the phone's own rules.
      `teach_feedback.py` adds a summary of prepared episodes from the phone's
      notes: ads skipped, skips taken back, and taps on Skip ad. Mo's week of
      listening is the real exam, and that summary is its result.
      `docs/PODCASTS-ADS-TEACHING.md` gets the section "Prepared episodes" and
      loses the stale line that the phone does not read `ahead-ads.json`;
      `docs/ARCHITECTURE.md` gets the decision.
  - Done when: the row is printed for the shelf in the cloud and its number
    stands here, and a test pins the summary.
  - Done 2026-11-27. The row "Prepared copy" passes 222 of 222 breaks with the
    snapped labels and 219 of 219 with Claude's own, with no skip where there is
    no ad (the phone's finders on a stream: 138 of 222 with 15 wrong skips, and
    152 of 219). That is the ceiling and no exam: the marks are the truth here,
    so the row only says that the phone's rules lose none of them. The first run
    said 159 of 222 because the row passed the feed's stated length, which is
    short for 50 of the 63 episodes (see `docs/LESSONS.md`). The summary counts
    skips, Undos and misses by the notes' `by: "prepared"`
    (`teach_feedback_prepared.py`).
- [x] **Y8 Check and ship**: the Opus check against every "done when" above,
      with a close look at what deletes (the Mac's clean, the phone's give-back)
      and at the swap of a download; fixes test first; the whole check; one pull
      request; Fork CI; the merge; one TestFlight build; the Mac's tools copy
      updated; "Install episode preparing.command" left for Mo's double-click.
  - Done when: the pull request is merged, the build is on TestFlight, and Mo
    has the installer and knows what it costs.
  - Done 2026-11-28: PR #61 merged, TestFlight 39.1 uploaded (it also carries
    X7, because 38.1 was never built), and Mo ran "Install episode preparing".

Left for later: cutting the ads out of the prepared file so that nothing has to
be skipped; the app not downloading the publisher's copy at all when the Mac's
copy is on its way; skipping the phone's own writing down of a prepared copy; a
show the Mac should not prepare (an ad-free feed); learning from the Undo of a
prepared ad.

### After prepared episodes: taps, sooner, second look and a clear Mac link (Mo's picks, 2026-11-28)

Mo: "Do all except last one. do it at 11 today". And later the same evening:
"the mac to iphone thing needs to be smoother. Right now I have no idea if the
mac episode is playing." He asked why a started episode is never swapped
("Shouldnt it?") and tapped "Also on mobile data". Fable planned it, Sonnet
builds, Opus checks, Fable checks last. One pull request and one TestFlight
build for the round.

What changed tonight: until build 40.1 the phone's link to the Mac's folder
failed silently, so nothing the Mac made ever reached the phone and no tap ever
reached the Mac. 40.1 is on Mo's phone and Settings says "Kept up to date with
LofiMusic". Everything below runs on a real phone for the first time, so each
milestone that moves a file says how the move is proven.

How I read the picks (my choices, told to Mo):

- "All except last one" is: learn from his taps, prepare sooner, and Claude's
  second look at break edges. Cutting the ads out of the file is not built.
- The second look costs about $10 to $15 a week more, which Mo accepted. Its
  test has a small spend that Mo is told before it runs. Mo is asked again when
  a week would clearly pass $15.
- Mobile data is for the phone's next 3 episodes only (about 50 MB each).
- On the card with seven more ideas Mo tapped "All seven" (Z13 to Z17, Z21 and
  Z22). Six are free. The show playbook costs about $10 to $15 of Claude usage
  once, which that tap approved. Each is measured first and kept only if it
  helps.
- Notes from taps and the per-show notes made from them hold transcript words.
  They stay on the Mac and are never committed.
- The sealed exam rule holds: anything that changes what is skipped is measured
  on the answer key first, with its limits picked on the training episodes only.
  The bar for keeping a change: more breaks pass on the exact labels (138 of 222
  as a stream, 152 of 219 on Claude's labels), and no more skips where there is
  no ad. The exam episodes stay unseen.
- On Mo's Mac, auto mode refuses `swift test`, `swift run`, fetch scripts and
  the build start. Every Mac step that needs one is a double-clickable
  `.command` launcher.
- The round is split. Part 1 is useful by itself and is built tonight, and it
  holds the map's test, so we know tonight whether the map works. Part 2 (the
  map in the app, the swap of a started episode, the voice print and the show
  playbook) may slip to the next round, and Z23 ships whatever is finished.

**Part 1 (tonight)**

- [x] **Z1 When the phone last heard from the Mac** (H): Podcasts, profile, "Ad
      skipping results" and Settings get one plain line, "Last exchange with
      your Mac: today 9:42 PM", with what came (marks, copies, teaching files)
      and what went (the list, the notes). When nothing ever moved it says so
      and names the step to take.
  - Done when: tests pin the line's words for never, today and older than a day,
    and `phone-queue.json` in the Mac's iCloud folder proves the phone wrote.
  - Built 2026-11-28 (builder A, joined by builder G): `macExchange.ts` words,
    kept in AsyncStorage; the copies count comes from `runPrepared`. The phone's
    first `phone-queue.json` reached the Mac at 11:10 PM Eastern on build 40.1.
- [x] **Z2 "Your Mac's marks" in the player** (G): an episode that plays with
      the Mac's marks shows the line "Your Mac's marks" with a Mac symbol, for a
      prepared copy and for marks placed on a stream. An episode without them
      shows nothing new. It takes the place of "Prepared by your Mac".
  - Done when: jest tests pin when the line shows, and a screenshot shows it.
  - Built: `MAC_MARKS` with a laptop symbol; `macMarks` from Swift for prepared
    copies, ahead marks and streams (the stream flag in `PodcastPlayer.swift` is
    not compiled in the cloud; Fork CI compiles it).
- [x] **Z3 Look for Mac work at Play and in the background** (G): the phone
      reads the Mac's files when Play is pressed and in its background refresh,
      not only when the app opens. Marks that arrive for the episode that is
      playing are used from the next ad on.
  - Done when: tests pin both moments and that a read at Play never delays the
    start by more than a second.
  - Built: at Play at most once a minute (`dueForPlay`), and the background task
    waits at most 25 s for the exchange (`waitAtMost`).
- [x] **Z4 The episode map, tested tonight** (G; free): Mo: "This should be a
      much smoother process with the map you're doing tonight right?" The Mac
      makes a small map of an episode (about 100 KB): a fingerprint of its
      file's show audio and Claude's marks. A phone would line its own stream or
      download up against it as the audio arrives: what matches carries the
      marks over, what does not match is an ad that differs. The test runs on
      the Mac's 161 twice-downloaded episodes, map from copy A played on copy B,
      as a scorecard row. No app change here.
  - Done when: the row's number stands here, with how much audio the phone needs
    before it is lined up and how many episodes do not line up at all. The map
    goes into the app (Z19) only when the row passes at least 20 more exact
    breaks than the stream row with no more wrong skips.
  - Result (simulation, `/home/user/scratch-z/z4.py`, `z4b.py`): on the shelf's
    copy B, 125 of 142 breaks with the map against 61 for the finders alone; 18
    wrong skips (finders 20) once carried pieces under 5 s are dropped (49
    without that rule). On 97 other twice-downloaded episodes the rule holds:
    140 of 158, 22 wrong skips (58 without). Most of the gain is Claude's marks
    themselves; exact carry adds up to about 16 breaks over placing them by
    words. 1 of 160 episodes never lines up (a re-edit); 150 or more line up
    within 10 s. Go for Z19.
- [x] **Z5 Prepare sooner, and the phone waits** (pick 2): the Mac's job runs
      every 20 minutes instead of every hour. As soon as it picks an episode it
      writes a "coming" entry to `ahead-ads.json`, before the marking. The phone
      does not download the publisher's copy of a coming episode by itself; it
      waits for the Mac's copy, for 2 hours at most. Pressing Play never waits.
      The file stays version 1, so an older build ignores the new field.
  - Done when: Python tests pin the 20 minutes, the coming entry and its removal
    when the copy is ready or the marking failed; jest tests pin the wait, its 2
    hour end and that Play streams at once. A new installer launcher is left for
    Mo.
  - Mac part done (round Z, builder C): the job runs at minutes 5, 25 and 45
    (the same $35 weekly cap and per-run limits; the budget is one for the week
    and is checked before every call, so three times the runs cannot pass it).
    The pick writes `coming` to `ahead-ads.json` (both folders) before marking;
    the run closes it before the last write. Mo double-clicks "Install episode
    preparing" again. The phone part is done too (builder B): the phone holds
    its own automatic downloads of a coming episode for up to 2 hours; Play and
    a download by hand never wait.
- [x] **Z6 Copies on mobile data** (D): with Mo's switch on, the phone takes the
      Mac's copy on mobile data too, for its next 3 episodes only.
  - Done when: jest tests pin 3 on mobile data, 12 on Wi-Fi, and nothing with
    the switch off.
- [x] **Z7 Learn from Mo's taps** (pick 1): every hour the Mac reads the phone's
      notes of prepared episodes (Undo, Skip ad, skip forward inside an ad). It
      keeps per-show notes that Claude gets when it marks that show's next
      episodes. Mac only, never committed. A tap moves no skip by itself.
  - Done when: Python tests pin how a note becomes a per-show line, that a show
    gets 20 lines at most, and that the folder is in `.gitignore`; the Mac's log
    names the notes it read.
  - Found on the Mac (2026-11-28): every preparing run since the phone's first
    files arrived said the phone's notes and its list of next episodes "could
    not be read ([Errno 11] Resource deadlock avoided)". The phone's files reach
    the Mac as files iCloud has not downloaded yet, and a program's default on
    macOS is not to download them (EDEADLK, Apple's TN3150). The readers now let
    their process download them first (`setiopolicy_np`, in
    `teach_feedback.find_notes`). Done on the Mac once a run reads the notes.
- [ ] **Z8 Find why the Mac's "Score" step fails**: it has failed silently since
      2026-11-23, so `scorecard.json` and the per-show settings made from it are
      stale. The step logs its exit code and its last error lines. A launcher
      "Score the ad skipping and show the error" is left for Mo, and the cause
      is fixed test first.
  - Done when: the cause stands here, a test pins the fix, and a finish on the
    Mac writes a new `scorecard.json`.
  - So far (builder D): every failed finish step now prints its exit code and
    signal. In the cloud the scorer ran 12 minutes and exited 0 on a copy
    without audio; every non-zero exit in it prints a line, so the Mac's silent
    failure is a signal (killed or a crash) in the audio steps. The next Mac run
    shows the code.
  - Found (round Z on the Mac, 2026-11-28): exit code 137, killed by macOS
    (signal 9) before it printed anything. The score has read every teaching
    episode's audio since the sound rows came in (PR #55, 2026-11-23, the day it
    started failing): 1,585 files, 76 GB, some read several times. On Apple's
    systems each chunk a FileHandle reads is also held by the thread's
    autorelease pool, which a command-line program never empties, so all of it
    can stay in memory (Linux has no such pool, which is why the cloud runs
    passed). Each chunk read now has its own pool (`ChunkRead`, as `Sha256`
    already did), and the score prints its memory every 100 episodes. Done once
    a run on the Mac writes a new `scorecard.json`.
- [x] **Z9 Teach the phone again every night by itself** (B): a nightly job runs
      the finish steps (habits, model, library, sounds, cues, score, settings,
      publish) on what was marked that day. It spends nothing. It comes after
      Z8, so that it never publishes stale settings: when the score fails, the
      settings are not published and the log says so.
  - Done when: Python tests pin the order, the lock shared with preparing, and
    the stop on a failed score. An installer launcher is left for Mo.

**Free measurements (the app changes only where the bar is passed)**

- Built: `teach-nightly.sh` at 3:30 AM under the shared lock, no Claude calls; a
  failed score leaves the settings out. Installed by the round's Mac script.
- [ ] **Z10 This week's ad sounds every hour** (A): the sounds of the ads in
      prepared episodes go to the phone hourly. Measured first with a scorecard
      row that gives each test episode only sounds from the week before it.
  - Done when: the row's number stands here. Kept when the stream row passes at
    least 3 more breaks and no more wrong skips.
- [ ] **Z11 The Mac's marks on a streamed prepared episode** (C): when the phone
      streams the publisher's copy of an episode the Mac prepared, the Mac's
      marks are placed by matching words. Check that this works on the
      twice-downloaded episodes, marks from copy A played on copy B.
  - Done when: the share of marks placed within 5 s stands here, and what is not
    placed falls back to the phone's own finders (a test pins it).
- [x] **Z12 Edge tricks from MinusPod** (F): the silence snap (the nearest
      silence within 2 s), the ad-end check (the end moves on while the next
      lines still sell) and the per-show break sound snap. Each is tried alone
      against the answer key.
  - Done when: three numbers stand here. A trick is kept only when it passes
    more breaks with no more wrong skips.
  - Results (`/home/user/scratch-z/n`, against the dumps from before round X:
    142/219 and 129/222): silence snap 136 and 124, not kept; the ad-end check
    144 and 131 with no more wrong skips (limits picked on 1,170 training
    episodes: promo code, web address, "com slash", terms apply; one line
    bridged; reach 15 s), kept and built into the phone's finders; break sound
    snap no change (needs other episodes' audio), not kept. After the final
    check the cues no longer fire on a sentence's end or on "the code": still +2
    on both keys, 6 ends moved instead of 7, no more wrong skips.
- [ ] **Z13 Word-exact ends in the Mac's marks** (Mo's pick "All seven"; free):
      the Mac's transcripts keep each word's time, and a mark ends at the ad's
      last word. Today exact ends lie within 1 s of a line start 46 times in 100
      and within 5 s 91 times, so the Mac's marks cannot reach 95 at the ends.
      Needs Mo's double-click to write the 63 shelf episodes down again.
  - Done when: Claude's own edges are scored against the places where two
    downloads differ, before and after. Kept when ends within 5 s reach 95.
- [x] **Z14 Ad harvest by repeat downloads** (Mo's pick "All seven"; free): the
      Mac downloads a new episode 3 times over the day. What differs is an
      inserted ad with exact edges and no Claude call, and its sound joins Z10's
      sounds. It adds to the publishers' download counts; Mo is told.
  - Done when: on the twice-downloaded episodes, split by week, the share of
    inserted ads with a sound twin from earlier stands here. Built only at 50 in
    100 or more, then held to Z10's bar.
  - Result: 26 in 100 of inserted stretches (43 in 100 of the testable ones)
    have a sound twin from 1 to 7 days before. Below the 50 bar: not built.
- [x] **Z15 The ad-length ruler** (Mo's pick "All seven"; free): 41 in 100
      inserted stretches are within 1 s of a multiple of 15 s. A skip that
      starts at a joint or a known sound and ends near such a multiple is moved
      to it, and a hole exactly one ad long is filled.
  - Done when: the replay's numbers stand here. Kept by the round's bar.
  - Result: no gain (142 to 142, 129 to 129; only 2 of 290 skips start at a
    joint near a multiple of 15 s). Not kept.
- [x] **Z16 The lightest copy** (Mo's pick "All seven"; free): of the Mac's
      downloads of an episode (Z14), the shortest becomes the prepared copy,
      because some downloads carry fewer ads. Nothing is cut out of a file.
  - Done when: the ad seconds of the shorter and the longer copy of the
    twice-downloaded episodes stand here. Built only when the shorter copy has
    at least 20 in 100 fewer ad seconds.
  - Result: the lighter download has at least 20 in 100 fewer ad seconds in 97
    of 160 episodes, but it is the later download in 106 of 111, so it is the
    episode's age, not chance. Not built: it needs repeat downloads (Z14
    failed), and the map (Z19) already lets the phone play its own, later copy
    with the Mac's marks.
- [x] **Z17 Walk a host read back to the brand's first mention** (Mo's pick "All
      seven"; free): when a host read is known by its code, its web address or a
      sponsor name from the notes, its start moves back to the first earlier
      mention of that brand within 2 minutes. It is for the host reads that
      begin as normal talk (9 of the 77 failing breaks).
  - Done when: the replay's numbers stand here. Kept by the round's bar.

**The paid test**

- Result: web addresses only, reach 90 s (picked on training): 13 skips move, no
  break changes (142, 129). Not kept.
- [x] **Z18 Claude's second look at every break's start and end** (pick 3):
      Claude reads the lines around each edge once more and may move it. Tested
      first on the twice-downloaded episodes, where the answer key does not come
      from Claude. Mo is told the test's spend before it runs (about $3).
      Switched on only if it helps.
  - Done when: edges within 5 s, before and after, stand here with the cost for
    each episode. Kept when 5 in 100 more edges land within 5 s, none of the
    kinds gets worse, and a week stays under $15.
  - Result (Mac, 2026-11-28, 112 twice-downloaded episodes until the
    $5 cap,
    $4.80, $0.04 an episode): within 5 s of the exact edge 300 of 454
    before and 294 after (within 1 s 192 and 189); sponsor edges got worse. Not
    kept, so it stays off.

**Part 2 (may slip to the next round)**

- [ ] **Z19 The episode map in the app** (G): the phone reads the Mac's map and
      lines up what it plays, in the middle of an episode and on mobile data
      too. The copy stays as the backup. Built only when the test (Z4) passed;
      it goes into this build if time allows.
  - Done when: Swift tests pin the lining up on a stream that arrives in pieces,
    that no match means the phone's own finders work as before, and that the
    player line of Z2 shows.
  - Found on the Mac (2026-11-28): the preparing job wrote no map at all. Run on
    the copy in iCloud Drive and told to write there, `podcast-ads --map`
    printed nothing for five minutes and was stopped, for every copy (six in the
    first run, 30 minutes of the lock). The same tool read the Mac's own copies
    fine in the same job (the second downloads), and made the map of one of
    those very files on Linux in 0.04 s. So the map is now made of the Mac's own
    copy of the audio (checked by its SHA-256) into a temporary folder, and
    `teach_maps.py` copies it into iCloud as the other files are copied there.
    Done on the Mac: the 7:25 AM run (2026-11-28) wrote 31 maps in about a
    minute, none failed, and `ahead-ads.json` names all 31.
- [ ] **Z20 Swap a started episode** (E): the phone finds the listener's place
      in the Mac's copy by matching the show's own audio around it, then goes on
      in the copy at that place. No match means no swap.
  - Done when: tests pin the place within 1 s on the twice-downloaded episodes,
    that an unsure match never swaps, and that the Undo list and the played time
    move with the swap.
- [ ] **Z21 The voice print** (Mo's pick "All seven"; free): the Mac learns the
      voices of each show's hosts. A short stretch in a voice the show does not
      use is likely an ad, and the change of voice is its edge. Tried on the Mac
      first, on the shelf's audio, with a launcher for Mo. Guests are the risk.
  - Done when: it stands here how many of the 35 pieces the finders do not know
    are in a voice that is not a host's, and how often a guest sets it off.
    Built (first into the Mac's marks) only when it passes at least 5 more
    breaks and no more wrong skips.
- [ ] **Z22 The show playbook** (Mo's pick "All seven"; about $10 to $15 once,
      approved): Claude reads each show's marked training episodes once and
      writes its handoff and return lines, its named sponsored pieces and the
      hosts' own plugs. The phone uses them as cue rules. The file holds
      transcript words, so it is published like `ad-cues.json` and never
      committed. Mo's tap approved the cost; he is told when the run starts, and
      it runs under its own budget with a hard stop at $15.
  - Done when: playbooks made from the training episodes only are replayed on
    the shelf and the numbers stand here. Kept when at least 4 more breaks pass
    (it aims at the 9 missed breaks) and no more wrong skips.

**Ship**

- [ ] **Z23 Check and ship**: the Opus check against every "done when" above,
      with a close look at what waits (Z5), what uses mobile data (Z6) and what
      swaps (Z20); fixes test first; the whole check; one pull request; Fork CI;
      the merge with Mo's OK; one TestFlight build through the launcher; the
      Mac's tools copy updated, never over a copy a run is using; installers
      left for Mo's double-click.
  - Done when: the pull request is merged, the build is on TestFlight, Mo has
    the launchers and knows what each costs, and the lines of Z1 and Z2 are seen
    on his phone.

Left for later: an external server in place of iCloud (held unless Mo asks);
cutting the ads out of the file (Mo said no for now).

## Later

- Round Z (2026-11-28), from the final check: `teach_second_look.py` is 337
  lines, and `preparedSync.ts` (368), `PodcastAdFinder.swift` (353) and
  `AdScoreCommand.swift` (408) grew past 300; split them in the next cleanup.
  Two `teach_words.py --no-lock` runs at once could share a `.part` file. A held
  new episode that is still held after 2 days is forgotten, not downloaded.
- Prepared episodes (Y, 2026-11-27), found by the Opus check or by the builders
  and left: when the ads file of a copy cannot be saved the copy stays installed
  without the Mac's marks and is not taken again (the phone's own finders then
  work on it); the show's language is not noted for the transcriber when a copy
  is installed; an automatic download that is not the list's read-ahead leaves
  the `ahead` mark on an entry (the Up Next rules, older than this round); a
  swap drops the old file's transcript, `plainURL` and `playThrough`; an episode
  that is not in the phone's ahead table (its list and the newest 12 unplayed of
  a show) never gets a copy; a feed episode with no guid is not prepared; a
  picked episode that still waits for its second download after the keep days is
  dropped, and its marking was paid for; a run that is killed during a call does
  not record that call's cost; the linked folder's bookmark is not refreshed by
  `LofiLinkedCopy`, which has no tests because it lives outside LofiScoreKit;
  `brctl quota` and `cp -c` were tested with stand-ins only; other scorecard
  rows may still pass the feed's stated length; `preparedSync.ts` (341 lines),
  its test file and `AdScoreCommand.swift` are over 300 lines.
- One tap leaves the whole break (X7, 2026-11-27), found by the Opus check and
  left: a carry or a bridge passes over an open question or a maybe that lies in
  the hole, so it is never asked; the Undo of a carried skip is not remembered,
  so a later tap in the same ad carries over the same hole again; when the tap
  itself was the mistake (the ad was no ad), the Undo of a carried skip does not
  save that ad as undone; a carried hole leaves no note, so the Mac does not
  hear that the phone saw a hole inside a break; `PodcastPlayer+Ads.swift` is
  314 lines.
- Timing fixes and the skip tap (2026-11-27), found by the Opus check and not
  fixed: a pull that the phone then throws away (it lies over an undone stretch,
  a "no" or an ad of a kind that is not skipped) still uses up the stretch's one
  pull, so a later opening line of the same ad is lost; the questions are picked
  before the two finders' stretches are known, so the timeline's count of
  questions can include one that was dropped; the meaning model's middle band
  makes no maybes; a tap whose answer or confirmation cannot be saved falls back
  to the plain move without the landing rule.
- The same round, seen on the Mac (2026-11-27): the "Score" step of
  `teach-finish.sh` failed in the last two finishes and the log does not say why
  (`scorecard.json` is of 2026-11-23). The steps after it ran.
- The same round, in the scorecard: when a new stretch joins a skip with no ad
  to a skip of an ad, "skips with no ad" falls by one although the same show
  time is cut. Read that number together with the breaks that start early.
- The second-copy trial (2026-11-26), found and not fixed: `teach_snap.py` adds
  every unmarked differing stretch of 10 to 300 s as a sponsor label, so an
  episode whose second download is another version of it (The Daily
  `b97026c08408` on the shelf, 86% differing) gets show content labelled as ads
  in `labels-snapped`; it needs the same more-than-half guard.
- Ad skipping to 95%, round B (2026-11-24), found and not fixed: at the `off`
  level a show still gets a whole-episode run of Apple's model (battery); skip
  the model at `off` but save the final file with the model version. A per-show
  `skip` for the Apple finder can never happen, because `teach_settings.py`
  needs 3 scored episodes of a show and the shelf holds one per show (score the
  training set per show, or document it). Four files grew over 300 lines:
  `PodcastStreamHead` 480, `PodcastAdFinder+New` 322, `AdScoreCommand` 318,
  `teach_settings.py` 348. The old phone parser ignores `apple-model`, so a Mac
  setting for it only reaches phones that have this round's build. Half of the
  late starts are 18 to 97 s late, out of the edge snap's reach: a trained edge
  score is the one more try. The weekly run also marks and downloads ahead
  episodes that are left unmarked, and ahead audio is never deleted, so the
  nightly fills the 12 GB audio limit the big runs share within weeks: delete
  ahead audio after its marks are written. Up Next episodes the weekly run
  already marked are never sent to the phone.

- Ad skipping to 95%, round A (2026-11-23), found and not fixed: the new word
  model's skips land more than 5 seconds past the ad in about 27 of 226 breaks
  (15 before), mostly one line late, and a plain trim of the end by the line's
  score only trades that for hearing the ad's last line (a model of the end
  border is the next idea); the first 3 minutes of a stream depend on how fast
  the phone writes down speech, which is not measured (the timeline's "head
  audio on disk" to "local:" lines, or "Time the first minute of an episode");
  the stream replay runs the repeated words at every reach, drops a remembered
  ad whose end is a guess, knows no sponsor names or opening words, joins
  Apple's row after the per-show settings (so where Apple's model starts an ad
  before the words do, the scorecard pulls and the phone does not), and prints
  no failure causes; a library entry whose first member covers two ads can miss
  one, and `KnownAds.swift` is over 300 lines; a joint pull that lands on the
  end of the ad before glues two ads; a trim the listener made on a start the
  snap had moved may not be found again when the episode is looked at a second
  time; the scorecard works the word list out three times an episode;
  `teach_train.py` and `teach_settings.py` are over 300 lines; nothing on the
  Mac knows the phone's app version before it writes a version 2 model; there
  are no unit tests for the phone's own `NewAds.snap`, `isFixed` and `trimReach`
  (macOS CI only compiles them).
- Podcasts ads (round of 2026-11-23): a rule that promotes a repeat to skip
  after enough confirmed answers on a show (today a repeat never skips); new
  finders for episodes that finished before the update; a habit counted twice
  for an episode that was streamed and then downloaded; deny-by-words for
  transcripts over 64 MB; questions on the lock screen; counts of own sounds,
  the guard and the Mac's new files on the "Ad skipping results" page (today the
  question note and the skip log are the only proof on the phone); an Undo in a
  streamed episode only counts for the guard and does not yet forget the own
  sound print until the download is filed; own sounds and habits are learned
  only after Apple's model pass, so nothing is learned while it cannot be asked;
  a swipe-away or memory kill with a mark on disk counts as a crash for the
  guard; the scorecard's finder and joints lines describe the default decision,
  not a show's own; Skip ad inside an open question jumps to the question's end
  (up to 300 s, with Undo); a switch for each finder in the app.
- Podcasts ads: the sound scan of a stream's bytes as they arrive after the
  first three minutes (a mid-roll in a streamed episode is found only when
  transcription reaches it); questions from the head scan and on the lock
  screen; guesses of Apple's detector as questions; per-show thresholds once a
  show has ten marked episodes; the meaning model in the head scan once the
  diary shows its speed.

- Podcasts: with a dark Podcasts theme on a light iPhone (or the other way
  round) the status bar text follows iOS, not the theme. The three screens that
  draw a `StatusBar` could take its style from the theme.
- Podcasts: marking an episode unplayed does not reset its saved place for Up
  Next in Swift.
- Podcasts: deleting an imported file from the Downloads screen leaves its row
  in "Your files"; the empty "Your files" page says "This feed has no episodes
  yet."
- Podcasts: the trimmer reads the ads only when an episode loads, so ads found
  while it plays are not avoided until the next load.
- Podcasts: since the Books look, Appearance's Dark and Extra Dark are both
  black and differ only in their accent colour.

- Podcasts ads: an ad the Mac taught (from the library or by its sound) that the
  listener undoes is skipped again in the next episode, until the Mac's next
  teaching run has read the phone's note. The phone could keep its own list of
  stretches that are not ads. Lines that only the small model marked become
  "sure" when they join a sure rule line. A download made before this round that
  was never played or queued does not know its show, so the known ads do not
  reach it. `PodcastPower` does not look at the phone's heat while every
  download is checked again after a detector change. A feed that moves does not
  move its pending "finished in Apple Podcasts" list for that one refresh.
  `dbFeeds.ts`, `PodcastPlayer.swift` and `PodcastPlayer+Ads.swift` are over 300
  lines.
- Podcasts ads: the head scan stops at three minutes; decide from the diary
  whether it should go on. A missed-ad tap jumps 30 seconds; it could end where
  the small model thinks the stretch ends and teach the phone's memory at once.
  `AdCleanup`'s own merge is not kind-aware. The teaching run transcribes
  everything as US English, a feed without dates that lists its oldest episode
  first gives the oldest episodes, and a feed with no guids makes a new id when
  an audio address changes.

- Run lint (`oxlint` on fork paths) in Fork CI too.
- Podcasts: `savePlayback` notifies the library on every 15 s save, so open
  lists re-read the database while playing. Notify only when what a row shows
  (minutes left or played) changes.
- Split the big Swift files (`AmbienceSynth`, `AmbiencePlayer`,
  `LofiAtmosphereHost`).
- Stop building the mood code while the music is shelved.
- Give the fork its own app icon before sharing it with anyone.
- A publish edition and the App Store (see `FORK.md` and the publishing notes).
- Bring the music back (`shelved/lofi-music/README.md`).
- Podcasts: Apple's cloud model and Claude Haiku as other ad detectors, a Mac
  command comparing detectors, OPML import, sleep timer, chapters, CarPlay (see
  `docs/PODCASTS-PLAN.md`).
- Podcasts: search the words spoken inside downloaded episodes (needs P3a's
  transcripts), suggestions ranked by how alike the shows' descriptions are
  (on-device model), and charts for other countries.
- Podcasts, left out of the Pocket Casts match for now (reasons in
  `docs/PODCASTS-PLAN.md`): CarPlay, Apple Watch, widgets, Live Activities, Siri
  Shortcuts, Chromecast and Sonos, video podcasts, the iPad layout, app icons,
  and sync with other devices.
- Freeing the teaching audio (2026-11-25), found and not fixed: the scorecard's
  own-sounds and repeated-sounds rows and `joints.json` still read the audio of
  earlier episodes, so a Mac score after freeing has less history for them (a
  bank for the finders' sure ads, or a rule to keep each show's newest few,
  would close it); the freshness rule uses file times, which are exact on the
  Mac's own disk; the launcher's look and delete are two lock takes, so the
  delete run may free a few more episodes than the look showed (all of them meet
  the same rules).
