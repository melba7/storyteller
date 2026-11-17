# Plan

Done: 2 | Last cleanup: none | Podcasts: P1a, P1b merged; TestFlight 20.1 next

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
- [ ] **P5d. Smart playlists** (M): the Playlists tab, with playlists built from
      rules (shows, played state, release date, length, downloaded, starred),
      sorted and with auto-download. It starts with New Releases, In Progress
      and Starred.
- [ ] **P5e. Your own playlists** (S): playlists you fill by hand, with any
      episode (also from shows you don't follow), drag to reorder, and "Play
      all" into Up Next.
- [ ] **P5f. Sleep timer** (S): 5 to 60 minutes or your own time, end of
      episode, end of chapter once P5g is in, add 5 minutes, and a fade-out at
      the end.
  - Status: built and passing `check.sh` (Swift timer, 10 s fade-out, moon
    button in the player). "End of chapter" waits for P5g.
- [ ] **P5g. Chapters** (M to L): chapters from the feed (`podcast:chapters`),
      from M4A files (Apple's own reader) and from MP3 files (ID3 chapter tags,
      read with OutcastID3, MIT, copied in), a chapter list in the player,
      previous and next chapter, chapter artwork, and skipping a chapter.
- [ ] **P5h. Bookmarks** (S to M): a bookmark at the place playing now, with a
      title you can edit, from the player and as a headphone action; listed per
      episode and in Profile; tap to play from there.
- [ ] **P5i. Playback settings** (S): skip back and ahead amounts, what the
      headphones' next and previous buttons do (skip, next chapter or bookmark),
      mark an episode played when N seconds are left, and going back a few
      seconds after a long pause.
  - Status: built and passing `check.sh`: a Playback section in Profile, kept in
    Swift. "Next chapter or bookmark" waits for P5g and P5h.
- [ ] **P5j. Volume boost and trim silence** (L): a second Swift player
      (AVAudioEngine) for downloaded episodes that makes voices louder and cuts
      silent gaps, in three strengths, per show or for everything. Streamed
      episodes keep speed only.
- [ ] **P5k. Stats** (S to M): total time listened, time saved by speed,
      skipping, intro and outro skipping, trimmed silence and skipped ads, and
      listening by day, in Profile.
- [ ] **P5l. Themes** (M): Light, Dark, Extra Dark (true black) and a few colour
      themes with names and colours of our own, following iOS light and dark
      mode if you like, for the Podcasts section.
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

## Later

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
