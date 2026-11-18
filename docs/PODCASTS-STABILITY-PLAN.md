# Podcasts stability plan (after TestFlight build 31.1)

Written on 2026-11-18 by the planner for the bug-fix and smoothness round.
Builders (Sonnet) work from the milestones below in parallel git worktrees. The
checker (Opus) uses "How Opus should check this round". Nothing here is built
yet.

Mo's report, word for word: "Fix. Not skipping ads here. Glitch when I swipe
down this page another same page comes up and I have to swipe three times down
then I can't open it again until I quit app. Talking about player page. Finding
ads really takes a while and finds nothing, see attached. Have to click multiple
times on small player to open big player page. Also scroll has a bit of a
stutter." Later he added: "Merge when done. Let me know if any questions. Find
way to test changes."

The round is one pull request and one TestFlight build (see `docs/LESSONS.md`).
Mo has already said to merge when the checks pass.

All paths below are relative to `applications/mobile/` unless they start with
`libraries/`, `tools/`, `docs/` or `.github/`. Every file a milestone may change
is in a fork-owned path (`tools/fork/touchpoints.json`, `forkPaths`). No new
touch point is needed and no upstream file changes.

## Symptoms and evidence

| Id  | What Mo saw                                                                                                             | Evidence                                                                                                                                          |
| --- | ----------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| A1  | "Ads can't be found: Finding ads stopped: The model re…" on The Daily, "Finally, a Vaccine for Cancer" (position 6:04). | Second screenshot. The text after the second colon comes from an error's own description (`modules/podcasts/ios/PodcastAdFinder+Retry.swift:30`). |
| A2  | A Burlington pre-roll plays unskipped at 0:25 while the line says "Finding ads, 11% transcribed".                       | First screenshot. The transcript panel shows the ad's words.                                                                                      |
| A3  | "Finding ads really takes a while and finds nothing."                                                                   | Both screenshots, three minutes apart.                                                                                                            |
| B1  | Swiping the player down shows the same page again. Three swipes are needed.                                             | Second screenshot shows a second rounded sheet edge behind the player's top.                                                                      |
| B2  | After that the player cannot be opened until the app is quit.                                                           | Mo's words.                                                                                                                                       |
| C1  | The small player needs several taps to open the big player.                                                             | Mo's words.                                                                                                                                       |
| D1  | "Scroll has a bit of a stutter."                                                                                        | Mo's words. He did not say which list. He was streaming an episode that was being transcribed at the time.                                        |

## Root causes

Each cause is marked **confirmed by code**, **likely** (the code allows it and
it fits what Mo saw, but nothing proves it happened) or **needs device**.

### A. Ads are not found on this episode

1. **The model's new error type is not caught, so one refused piece stops the
   whole pass (confirmed by code; that the error is iOS 27's refusal is
   likely).**
   `libraries/PodcastKit/Sources/PodcastAdsOnDevice/AppleAdDetector.swift` (the
   `do`/`catch` around `session.respond`, about lines 100 to 118) catches only
   `LanguageModelSession.GenerationError`. Apple's documentation gives that type
   the availability "iOS 26.0 to 27.0, deprecated" and names the new types
   (`LanguageModelError` and others). Any other error leaves `findAds` as it is.
   `libraries/PodcastKit/Sources/PodcastAds/AdsRunner.swift:183-187` catches
   only our own `AdDetectorError.refused` and `.tooLong`, so the raw error ends
   the loop over the pieces. It reaches the generic `catch` in
   `PodcastAdFinder.find` and `findPartial`
   (`modules/podcasts/ios/PodcastAdFinder+Queue.swift:117-120`), which turns it
   into "Finding ads stopped: " plus the error's description. Developers report
   that the iOS 27 model answers health and medical text with "The model refused
   to answer", and the episode is about a cancer vaccine. Our own refusal cannot
   be the text Mo saw: `AdsRunner` catches it and
   `AdsPartialTests.testARefusedPieceCountsAsNoAdsAndIsReported` proves it.
2. **The same piece fails again on every retry (confirmed by code).** The
   detector samples greedily, so the model gives the same answer to the same
   piece. `PrepRetry` asks again after 60, 300 and 900 seconds and then at each
   return to the app (`PodcastAdFinder+Retry.swift:12-27`). Each run keeps the
   earlier pieces' answers in the progress file and stops at the same piece. The
   pieces after it are never asked and no final file is ever saved. That is
   "takes a while and finds nothing".
3. **A failure hides the ads already found (confirmed by code).**
   `AdsRules.status` in
   `libraries/PodcastKit/Sources/PodcastAds/AdsStatus.swift` returns
   `.notPossible(reason:)` for a failure before it looks at the partial results,
   and `modules/podcasts/adLine.ts` shows `ads.state === "unavailable"` before
   anything found. The line has room for one row of text, so the nested sentence
   is cut off.
4. **The pre-roll at 0:00 to 0:30 (needs device and a Mac measurement).** On a
   stream only the head scan can know about an ad this early
   (`modules/podcasts/ios/PodcastStreamHead.swift`). Its quick rules need a
   lead-in with a link or code, or two signals, and a produced spot such as
   Burlington's has none. The model is first asked at the 30 second step, and
   the start of play is held for at most 3 seconds. A model error in the head
   scan is caught at `PodcastStreamHead.swift:348` and written only to the
   system log, so nothing on the phone says what happened. Milestone S5 records
   it and measurement M1 times this exact episode on the Mac.

### B. The player page stacks copies and then cannot open

1. **Every tap adds another copy of the page (confirmed by code).** Both openers
   call `router.push("/podcasts/player")`: `podcasts/MiniPlayer.tsx:74` and
   `podcasts/EpisodeMenu.tsx:191-192`. In expo-router 58 a `PUSH` always adds a
   new route unless the screen has an id
   (`node_modules/expo-router/build/react-navigation/routers/StackRouter.js:253-300`).
   The `player` screen has none (`app/(root)/podcasts/_layout.tsx`).
2. **Each copy is a separate sheet, and a swipe removes only the top one
   (confirmed by code).** react-native-screens 4.30.0 presents every modal route
   on top of the one before (`ios/RNSScreenStack.mm`,
   `setModalViewControllers:`, lines 462 to 660). After a swipe it tells
   JavaScript to pop only the route that went away (`NativeStackView.native.js`,
   `onDismissed`), so the next copy is still there. Three taps make three sheets
   and three swipes.
3. **The native modal lock can stay held for the rest of the app's life
   (likely).** `setModalViewControllers:` returns at once while
   `_updatingModals` is set. Its `finish` block returns at
   `previous.beingDismissed` (about line 571) without releasing the lock, and a
   present that UIKit refuses never calls its completion. react-native-screens'
   own pull request 4949 describes this lock and was closed unmerged, so 4.30.0
   has it. A tap that pushes while a sheet is being swiped away reaches that
   path. Once the lock is held no modal can be presented, which is "can't open
   it again until I quit app".

### C. The small player needs several taps

1. **The tap gives no sign that it worked (confirmed by code).** The main
   `Pressable` in `podcasts/MiniPlayer.tsx:65-74` has no pressed style and no
   haptic, unlike the buttons beside it.
2. **The first tap's work is slow, so Mo taps again (likely; the size of the
   delay needs a device).** A push changes expo-router's route information.
   `useSegments` reads it from a React context
   (`node_modules/expo-router/build/hooks/useSegments.js:13-15`,
   `global-state/useRouteInfo.js:21-22`), so every mounted `EpisodeRow`
   (`podcasts/EpisodeRow.tsx:93`) and its `EpisodeMenu`
   (`podcasts/EpisodeMenu.tsx:150`) renders again in the same commit that has to
   mount the player. All visited tabs stay mounted. The mini player itself is
   mounted twice by react-native-screens
   (`src/components/tabs/host/TabsHost.ios.tsx:60-69`) and both copies render
   twice a second because they read the whole player view
   (`podcasts/MiniPlayer.tsx:53`).
3. **Every extra tap makes B worse (confirmed by code).** See B1.
4. Whether the glass accessory's own gestures swallow some taps is not known
   (needs device).

### D. Scroll stutter (ranked by how sure the code makes us)

1. **Every 15 seconds of playing, every open list reads the database again
   (confirmed by code).** `savePlayback` ends with `notifyLibraryChanged()`
   (`modules/podcasts/db.ts:154-169`) and the player saves every
   `SAVE_EVERY_MS = 15_000` (`modules/podcasts/playbackRules.ts:9`,
   `modules/podcasts/playback.ts:171`). Every `useLibraryQuery` in every mounted
   screen then loads again and sets new arrays (`podcasts/hooks.ts:27-62`), so
   every mounted row renders again.
2. **Rows render far more often than what they show changes (confirmed by
   code).** `EpisodeRow` is not memoized (`podcasts/EpisodeRow.tsx:70`). Each
   row reads the whole Up Next queue (`EpisodeRow.tsx:96`,
   `EpisodeMenu.tsx:151`) and the route (`EpisodeRow.tsx:93`,
   `EpisodeMenu.tsx:150`). The show page reads the whole download map
   (`podcasts/PodcastShow.tsx:50`), which changes at every progress step of any
   download, including the stream-through download of the playing episode
   (`modules/podcasts/ios/PodcastStreamDownload.swift:177`, `:240`, `:259`). Its
   `renderItem` is a new function each render (`PodcastShow.tsx:178`), so the
   list draws every mounted row again.
3. **Each row hosts a SwiftUI menu (likely a cost when rows mount; needs
   device).** `podcasts/EpisodeMenuSurface.ios.tsx` puts a `Host`, a `Menu` and
   an `RNHostView` in every row. No list sets `windowSize`, so React Native
   keeps about 21 screens of rows mounted.
4. **Some pages render twice a second while anything plays (confirmed by
   code).** `podcasts/PodcastEpisode.tsx:39`, `podcasts/TranscriptView.tsx:86`
   and `podcasts/ChapterList.tsx:27` read the whole player view.
5. **The phone is transcribing and running the model while Mo scrolls (needs
   device).** The head scan runs at `.userInitiated` priority
   (`modules/podcasts/ios/PodcastStreamHead.swift:87`). This round does not
   change it, because finding ads fast matters more.

## How we test

There is no phone in the cloud, so each fix has up to four kinds of proof. Every
milestone has a "Test" field that names which ones apply.

### 1. Pure tests (cloud, every push)

The mobile tests are vitest over plain `.ts` files (`yarn test:mobile`). There
is no React renderer in the tests, and this round does not add one. Logic is
pulled out of components into `modules/podcasts/*.ts` so it can be tested: the
player gate (S1), the status line (S4), the save notice rule (S6) and the row
rules (S7, S8). Where a rule is about component source ("a row must not read the
whole player view"), the test reads the source file and checks it, the way
`modules/podcasts/worklets.test.ts` already does. PodcastKit's Swift tests run
in Docker `swift:6.2` through `tools/fork/check.sh` (S2, S3, S4, S5). Code in
`modules/podcasts/ios` compiles only in Fork CI on a Mac.

### 2. Simulator checks with Maestro (milestone S9)

Three routes were compared.

- **Maestro (chosen).** It drives a simulator build from outside through the
  accessibility layer. Flows are short YAML files. Its documentation says it
  needs no package in the app and tests the built `.app`, and that a React
  Native `testID` is matched as `id`. Nothing in an upstream file or in
  `package.json` changes. It needs Xcode's command line tools and a Java
  runtime.
- **XCUITest (rejected).** It needs a test target in the Xcode project. The
  project is generated by `expo prebuild`, so the target would need a config
  plugin and a change to how the app is built.
- **`xcrun simctl` alone (rejected for taps).** It can boot, install, open a
  link, take a screenshot and record, but it cannot tap or swipe. It is used for
  those other jobs.

**Where it runs.** The first choice is GitHub: a new workflow builds the app for
the simulator on the `macos-26` runner (Fork CI already builds it there,
`.github/workflows/fork-ci.yml:105-171`), boots a simulator, runs the flows and
uploads the screenshots and a screen recording. The repository is public, so the
runner costs nothing, and long runs go to GitHub by Mo's choice. The second
choice is Mo's Mac through Remote Control, with two double-clickable `.command`
files, because auto mode on his Mac refuses install and fetch scripts. The Mac
needs Xcode 26 or newer, Node with corepack, CocoaPods and about 10 GB free. A
first build takes an estimated 20 to 40 minutes and a later run 3 to 10 minutes.
On GitHub a run takes an estimated 40 to 60 minutes, nearly all of it the build.

**The flows** (in `tools/fork/ui-checks/flows/`):

1. `smoke.yaml`: start the app, open the side menu, go to Podcasts, take a
   screenshot.
2. `player-opens-once.yaml`: follow a public feed from the Search tab, play its
   first episode, wait for the mini player, tap the mini player four times 100
   ms apart, check the player is showing, swipe down once, check the player is
   gone and the tabs are showing, tap the mini player once, check the player is
   showing again. Repeat the open and close five times.
3. `player-tap-during-close.yaml`: swipe the player down and tap the mini player
   at once, then check that exactly one tap later the player is open and that
   one swipe closes it.
4. `scroll.yaml`: open a show with many episodes, scroll down and up ten times
   while an episode plays, and record the screen. This shows hangs and blank
   rows. It does not measure smoothness.

Flow 2 must be run once on `main` before S1 is merged. If it fails there (a
second swipe is needed), the simulator reproduces Mo's bug and the flow is real
proof. If it passes on `main`, say so in the pull request: the flow then guards
against a regression but does not prove the fix.

**What a simulator cannot show.** The on-device model and speech recognition
(GitHub's runners have no Apple Intelligence, and a Mac's model is not the
phone's), real scroll smoothness and heat, the load of streaming and
transcribing at once (which may be what delays the first tap), AirPods, the lock
screen, calls, and anything that differs in a signed TestFlight build.

### 3. The real model on the exact episode (measurement M1, Mo's Mac)

The existing tools in `libraries/PodcastKit/Tools/mac/` run the same Swift code
and Apple's model on a Mac: `Check ad skipping on an episode.command`
(`podcast-ads --play`), `Time the first minute of an episode.command`
(`podcast-ads --head 90 --timings`) and `Check ad edges on an episode.command`.
They ask for an audio file in a dialog.

The audio is The Daily, "Finally, a Vaccine for Cancer" (16 November). Mo or the
coordinator saves the episode's MP3 from the show's feed with the browser into a
folder outside the repository, for example `~/Downloads/ad-checks/`. It is never
copied into the repository, and `node tools/fork/check-fork.mjs` fails on any
audio file. The tools write their results next to the audio file. Paste only the
text results into the pull request.

Run it twice: once on `main` (expected: the run stops with the model's raw
error, which names the error type and confirms cause A1) and once on the round's
branch (expected: it finishes, lists the ads and says how many parts could not
be checked). Two limits: the Mac must be on the same major system version as the
phone for the model to behave the same, and the feed inserts ads per download,
so the Mac's copy may carry different ads than the phone's stream. The refusal
is caused by the episode's own words, so it should still appear.

### 4. On Mo's phone (TestFlight)

1. Play any episode. Tap the small player once. The big player opens within
   about half a second and the small player dims while your finger is on it.
2. Tap the small player four times fast. One player opens. One swipe down closes
   it and the tabs are back.
3. Open and close the player ten times, sometimes tapping the small player while
   the sheet is still sliding away. It always opens again. No quit is needed.
4. Stream The Daily, "Finally, a Vaccine for Cancer", from the start and leave
   the player open for ten minutes. The line under the title never says "Ads
   can't be found". It ends as "N ads found" with or without "Couldn't check
   some parts". Ads after the first minutes are skipped.
5. Note whether the ad before the show's opening was skipped. Then use "Send
   skip log" in the Podcasts settings and send the file. It now holds the ad
   finder's diary for the episode.
6. While an episode plays, scroll a show with many episodes for 30 seconds.
   There is no hitch every 15 seconds.

## Milestones

Order of importance for Mo: S1 (B and C), then S2 to S5 (A), then S6 to S8 (D).
S9 is the test harness.

**Wave 1, in parallel (no shared files):** S1, S2, S3, S4, S6, S9. **Wave 2, in
parallel, after S1 is merged into the round's branch:** S5, S7, S8. Merge in the
order S2, S3, S4, S6, S1, S7, S8, S5, S9 and run `tools/fork/check.sh` on the
main checkout after each merge (see `docs/LESSONS.md` on worktrees).

Rules for every milestone: write the named test first and see it fail. Run
`yarn oxfmt` from the repository root on the changed directories, then
`tools/fork/check.sh`. Keep files under about 300 lines. Add no dependency.
Comments in plain English sentences. Never weaken or delete a test.

### S1. The player opens once, on the first tap (B, C)

- **Symptom:** B1, B2, C1.
- **Root cause:** B1 to B3 and C1 to C3 above.
- **Files owned:** `app/(root)/podcasts/_layout.tsx`,
  `modules/podcasts/playerGate.ts` (new), `modules/podcasts/playerGate.test.ts`
  (new), `podcasts/MiniPlayer.tsx`, `podcasts/PlayerScreen.tsx`,
  `podcasts/EpisodeMenu.tsx` (only the two lines at 191-192),
  `modules/podcasts/playerPageRequest.ts` and its test (only if the gate needs
  it).
- **Failing test first** (`playerGate.test.ts`): "four open requests in a row
  push once" asserts that `step` returns the effect `"push"` for the first
  `open` event and `null` for the next three. Further cases: an `open` while
  closing pushes nothing and pushes once after `gone`; two `close` events go
  back once; `timeout` while opening returns to closed; an `open` request more
  than 700 ms after `shown` (the sheet cannot be covering the mini player, so
  the state is stale) goes back once and pushes once after `gone`; a dropped
  request leaves no page request behind.
- **The change:**
  1. In the layout, make the screen singular:
     `<Stack.Screen name="player" dangerouslySingular options={{ presentation: "modal" }} />`.
     expo-router turns this into an id
     (`node_modules/expo-router/build/useScreens.js:124-152`) and a `PUSH` then
     reuses the route that exists (`StackRouter.js:259-267`). This is the
     guarantee that copies cannot stack, whatever calls `push`.
  2. `playerGate.ts` holds a pure function `step(gate, event)` that returns the
     next gate and an effect (`"push"`, `"back"` or `null`). States: closed,
     opening, open, closing. Events: `open` (with an optional page), `close`,
     `shown`, `gone`, `leaving`, `stayed`, `timeout`. Every event carries the
     time, so the tests need no clock. The same file has a thin wrapper with the
     module's one gate: `openPlayer(router, page?)`, `closePlayer(router)`,
     `playerShown()`, `playerGone()`. The wrapper calls
     `requestPlayerPage(page)` only just before a push, and starts a 1.5 second
     timer when it pushes.
  3. `MiniPlayer.tsx` and `EpisodeMenu.tsx` call `openPlayer`. Nothing else may
     call `router.push("/podcasts/player")`.
  4. `PlayerScreen.tsx` calls `playerShown()` in an effect and `playerGone()` in
     its cleanup. Its `close()` goes through `closePlayer`, so a double tap on
     the close control cannot go back twice (today the second `router.back()` at
     `PlayerScreen.tsx:100-103` leaves the page under the player, or the
     Podcasts section).
  5. If the vendored native stack sends `transitionStart` and `transitionEnd`
     with `data.closing` (grep `NativeStackView.native.js`), feed them in as
     `leaving` and `stayed`, so a tap during the slide down is remembered and
     opens the player once the sheet is gone. If it does not, leave these two
     events out and say so in the commit.
  6. In `MiniPlayer.tsx`: give the main `Pressable` a pressed style
     (`active:opacity-60`) and the existing `tap()` haptic. Read the player with
     `usePlayerValue` selectors (episode, show, playing, error, and the position
     rounded down to the minute for the spoken label) instead of `usePlayer()`.
     Add `testID="podcasts-mini-player"`. In `PlayerScreen.tsx` add
     `testID="podcasts-player"` on the root view and
     `testID="podcasts-player-close"` on the close control.
- **Test:** pure test above. Flows 2 and 3 of S9. Phone steps 1 to 3.
- **Done when:** the pure test passes, `grep -rn 'push("/podcasts/player")'`
  finds only `playerGate.ts`, and `tools/fork/check.sh` passes.
- **Check on device:** phone steps 1 to 3.
- **Risk:** the stale-state rule could close and reopen a player that is really
  showing. The 700 ms floor and the fact that the mini player is covered by the
  sheet make that unlikely. On iPad the sheet does not cover the whole screen,
  so check there that the dimmed area blocks taps.

### S2. A refusal by the model no longer stops the ad search (A)

- **Symptom:** A1, A3.
- **Root cause:** A1 and A2 above.
- **Files owned:**
  `libraries/PodcastKit/Sources/PodcastAds/AdModelFailure.swift` (new),
  `libraries/PodcastKit/Tests/PodcastAdsTests/AdModelFailureTests.swift` (new),
  `libraries/PodcastKit/Sources/PodcastAdsOnDevice/AppleAdDetector.swift`.
- **Failing test first** (`AdModelFailureTests`):
  `testARefusalByAnyNameIsRefused` asserts that
  `AdModelFailure.classify(typeName: "FoundationModels.LanguageModelError", caseName: "refusal", text: "The model refused to answer")`
  equals `.refused`. Further cases: `guardrailViolation` gives `.refused`;
  `contextSizeExceeded` gives `.tooLong`; `rateLimited` and `timeout` give
  `.failed` (so they are retried); an unknown case with unknown text gives
  `.failed` with the text; an error that is already an `AdDetectorError` comes
  back unchanged.
- **The change:** `AdModelFailure` is a pure enum with
  `classify(typeName:caseName:text:) -> AdDetectorError` and
  `classify(_ error: Error) -> AdDetectorError`. The second reads the type name
  with `String(reflecting: type(of: error))`, the case name with
  `Mirror(reflecting: error).children.first?.label ?? String(describing: error)`,
  and the text from `localizedDescription`. It must not name any iOS 27 symbol,
  because the package must still compile with Swift 6.2. In
  `AppleAdDetector.findAds`, after the existing `catch` for `GenerationError`,
  add `catch let error as CancellationError { throw error }` and then
  `catch { throw AdModelFailure.classify(error) }`.
- **Why a wrong skip cannot come from this:** a refused piece gives no ads. The
  change turns "the pass stops" into "this piece has no answer", and can only
  lead to fewer skips than a full answer.
- **Swift that the cloud cannot compile:** `AppleAdDetector.swift` is inside
  `#if canImport(FoundationModels) && compiler(>=6.2)` and builds only on a Mac.
  It already imports `PodcastAds`, where `AdModelFailure` lives. Keep the
  existing `catch` clauses in the same order and add only the two new ones.
- **Test:** pure Swift test in Docker. M1 on the Mac. Phone step 4.
- **Done when:** the tests pass in Docker, Fork CI's Mac build passes, and M1 on
  the branch finishes instead of stopping.
- **Risk:** matching words in an error's text is loose. A word list that is too
  wide turns a real fault into "refused" and hides it. Keep the list short
  (refus, guardrail, sensitive) and log the type name and case name through S5.

### S3. A refused piece is asked again in halves (A)

- **Symptom:** A3 (few ads found in an episode with sensitive talk).
- **Root cause:** a piece holds several minutes of transcript. One refused
  passage makes the whole piece unread, including any ad in it
  (`AdsRunner.swift:183-186`).
- **Files owned:** `libraries/PodcastKit/Sources/PodcastAds/AdsRunner.swift`,
  `libraries/PodcastKit/Tests/PodcastAdsTests/AdsRefusalTests.swift` (new). Read
  `AdTestSupport.swift` (`FakeDetector`) and `AdChunker.swift` but do not change
  them.
- **Failing test first:**
  `testARefusedPieceIsAskedInHalvesAndKeepsTheAdInTheOtherHalf`. A
  `FakeDetector` refuses any piece that contains a marked line and returns one
  ad for a piece that contains the ad's lines. Assert that the final file holds
  the ad and that `refusedPieces` is 1. Further cases: a piece shorter than
  `AdChunker.growingMinimum` seconds is not split; the split goes at most two
  levels deep; a piece whose halves both answer counts as not refused.
- **The change:** in `ask`, on `AdDetectorError.refused`, split with
  `AdChunker.split(_:)` (signature
  `public static func split(_ piece: TranscriptPiece) -> (TranscriptPiece, TranscriptPiece)?`)
  when the piece is long enough and the depth allows, ask both halves and join
  the answers the way the `.tooLong` branch already does. Mark the piece refused
  only when a leaf was refused.
- **Why a wrong skip cannot come from this:** the halves are asked with the same
  prompt and cleaned by the same `AdCleanup`. An ad cut by the split can only
  come out shorter.
- **Test:** pure Swift tests in Docker (all of `PodcastAdsTests` must still pass
  unchanged). M1.
- **Done when:** the tests pass and M1 reports fewer unchecked parts than with
  S2 alone, or the same.
- **Risk:** up to six more model calls for each refused piece, which makes a
  refused episode slower. That is why the depth is two.

### S4. The status line tells the truth (A)

- **Symptom:** A1 (a cut-off sentence that says ads can't be found while the
  search is only waiting to try again).
- **Root cause:** A3 above.
- **Files owned:** `libraries/PodcastKit/Sources/PodcastAds/AdsStatus.swift` and
  its test file in `PodcastAdsTests`, `modules/podcasts/adLine.ts`,
  `modules/podcasts/adLine.test.ts`.
- **Failing test first:** in `adLine.test.ts`, "a failure of this episode's
  search is one short line": for an ads state that is unavailable with a reason
  starting "Finding ads stopped:", `playerAdLine` returns a text of at most 40
  characters that does not contain "can't be found" and does not repeat the
  reason. In Swift, `testAFailureDoesNotHideAdsFoundSoFar`: with a partial file
  that holds two ads and a failure, `AdsRules.status` reports the two ads.
- **The change:** in `AdsRules.status`, look at the partial results before the
  failure. In `adLine.ts`, show "Ad check paused. Trying again soon" for a
  failure of this episode's search, and keep "Ads can't be found: …" for reasons
  that belong to the phone (Apple Intelligence off, language not supported). The
  words "Finding ads stopped:" stay in the data, because
  `modules/podcasts/ads.ts` uses them to tell the two kinds apart.
- **Test:** vitest and Swift tests. Phone step 4.
- **Done when:** both tests pass and no other test in `adLine.test.ts` or
  `ads.test.ts` had to change its expectation without a reason written in the
  commit.
- **Risk:** the wording is something Mo will see (Ask-Mo item 3).

### S5. The ad finder keeps a diary that Mo can send (A)

- **Symptom:** A2. Nobody can tell from the phone what the head scan and the
  model did.
- **Root cause:** `PodcastTimeline.mark` writes only to the system log
  (`modules/podcasts/ios/PodcastTimeline.swift:33`), and the head scan's model
  error goes only there (`PodcastStreamHead.swift:348`).
- **Files owned:** `libraries/PodcastKit/Sources/PodcastAds/AdDiary.swift`
  (new), `libraries/PodcastKit/Tests/PodcastAdsTests/AdDiaryTests.swift` (new),
  `modules/podcasts/ios/PodcastTimeline.swift`,
  `modules/podcasts/ios/PodcastSkipLog.swift`, and one-line
  `PodcastTimeline.mark` calls in
  `modules/podcasts/ios/PodcastAdFinder+Queue.swift` and
  `PodcastAdFinder.swift`.
- **Failing test first** (`AdDiaryTests`): `testTheDiaryKeepsOnlyTheNewestLines`
  asserts that `AdDiary.trimmed(text, maxLines: 500)` keeps the last 500 lines.
  `testALineHasNoTranscriptWords` asserts the shape of
  `AdDiary.line(at:episodeId:what:)`: a time, a short episode id and the mark,
  as one JSON object with `"kind": "diary"`.
- **The change:** `PodcastTimeline.mark` also appends a line to `ad-diary.jsonl`
  beside the skip log, trimmed to 500 lines. `copyForSharing()` adds the diary's
  lines to the shared copy. New marks: a partial pass and a full pass starting
  and ending, the number of pieces asked and refused, and for every failure the
  error's type name and case name. The diary holds no transcript words, no
  addresses and no keys.
- **Swift that the cloud cannot compile (all of `modules/podcasts/ios`):** read
  these before writing. `enum PodcastTimeline` with
  `static func mark(_ episodeId: String, _ what: String)`,
  `static func tap(_ episodeId: String)`,
  `static func secondsSinceTap(_ episodeId: String) -> Double?`. In
  `PodcastSkipLog.swift`: `static func append(_ entries: [SkipLogEntry])` (line
  102), `static func copyForSharing() -> URL?` (line 124) and `SkipLogFile.url`.
  In the finder: `private func findPartial(_ id: String) async`
  (`PodcastAdFinder+Queue.swift:81`),
  `private func fail(_ id: String, _ reason: String, retry: Bool = true)`
  (`PodcastAdFinder.swift:256`),
  `static func reason(for error: Error) -> String`. `PodcastTimeline.swift` and
  `PodcastSkipLog.swift` each need `import PodcastAds` if they use `AdDiary`
  (last round a file failed on the Mac only because that import was missing). Do
  not move code between files, because `private` members do not cross files.
  Grep for anything that reads `skip-log.jsonl` (in `tools/` and
  `libraries/PodcastKit/Tools/mac/`) and make it ignore lines with
  `"kind": "diary"`.
- **Test:** pure Swift tests in Docker, Fork CI's Mac build, phone step 5.
- **Done when:** the tests pass, the Mac build passes, and a shared log from the
  phone holds diary lines.
- **Risk:** a new file on the phone (Ask-Mo item 1). Writing on every mark must
  not happen on the main thread: use the queue the skip log already writes on.

### S6. A playing episode does not make every list load again every 15 seconds (D)

- **Symptom:** D1.
- **Root cause:** D1 above. `docs/PLAN.md` already lists it under "Later".
- **Files owned:** `modules/podcasts/playbackRules.ts`,
  `modules/podcasts/playback.ts`, `modules/podcasts/playback.test.ts`,
  `modules/podcasts/db.ts` (only `savePlayback`).
- **Failing test first** (`playback.test.ts`): "a timed save inside the same
  minute does not notify the library" plays for 45 seconds with fake timers and
  asserts that `savePlayback` was called three times and asked to notify at most
  once. Further cases: a save after pause, seek, a change of episode or a change
  of `played` always notifies; a timed save that crosses a whole minute
  notifies.
- **The change:** a pure rule in `playbackRules.ts`,
  `shouldNotifyListen(before, after)`, that says yes when the whole minute or
  `played` changed or the save was not a timed one. `persist` in `playback.ts`
  passes the answer to `savePlayback(episodeId, position, played, notify)`,
  which calls `notifyLibraryChanged()` only when asked. The position is still
  saved every 15 seconds.
- **Test:** vitest. Phone step 6.
- **Done when:** the test passes and `tools/fork/check.sh` passes.
- **Risk:** a screen that counted on the 15 second notice shows a value up to a
  minute old (time left on a row, the Home shelf, History, the statistics). Opus
  greps for such readers.

### S7. Episode rows draw again only when what they show changes (D, C)

- **Symptom:** D1, C1.
- **Root cause:** D2 and C2 above.
- **Files owned:** `podcasts/EpisodeRow.tsx`, `podcasts/EpisodeMenu.tsx` (after
  S1), `podcasts/PlayButton.tsx`, `podcasts/useUpNext.ts`,
  `podcasts/useSelection.ts`, `modules/podcasts/sameProps.ts` (new),
  `modules/podcasts/sameProps.test.ts` (new),
  `modules/podcasts/rowRules.test.ts` (new).
- **Failing test first** (`rowRules.test.ts`, in the style of
  `worklets.test.ts`): "a row reads no whole store" reads the source of
  `EpisodeRow.tsx`, `EpisodeMenu.tsx` and `PlayButton.tsx` and asserts that none
  calls `useSegments(`, `usePlayer(`, `useDownloadMap(` or `useUpNext(`, and
  that `EpisodeRow` is exported through `memo(`. `sameProps.test.ts` asserts
  that two episodes with equal fields are the same and that any changed field
  makes them differ.
- **The change:** wrap `EpisodeRow` in `memo` with a comparison that treats two
  `episode` objects with equal own fields as equal (`sameProps.ts`, compared
  with `Object.is` field by field, so a forgotten field can only cause an extra
  draw, never a stale row). Add `useQueued(episodeId)` to `useUpNext.ts`, a
  selector that returns a plain value for one episode. Read the tab for a link
  at press time from `lastTabSegments()` (`modules/podcasts/lastTab.ts`) instead
  of subscribing with `useSegments`. Make `useSelection` return the same object
  until its state changes.
- **Test:** vitest. Flow 4. Phone step 6.
- **Done when:** the tests pass, and every existing behaviour of a row and its
  menu is unchanged (same links, same menu entries, same labels).
- **Risk:** a link built from the last tab could open in the wrong tab if
  `rememberTabFrom` runs late. Check `app/(root)/podcasts/(tabs)/_layout.tsx`
  and the tests in `routes.test.ts`.

### S8. List pages and the episode page stop drawing on every tick (D)

- **Symptom:** D1.
- **Root cause:** D2 and D4 above.
- **Files owned:** `podcasts/PodcastShow.tsx`, `podcasts/EpisodeListScreen.tsx`,
  `podcasts/PlaylistScreen.tsx`, `podcasts/PodcastEpisode.tsx`,
  `podcasts/useDownloads.ts`, `modules/podcasts/downloads.ts` and its test (for
  one new pure function), `modules/podcasts/listRules.test.ts` (new).
- **Failing test first:** in the downloads test, "progress alone does not change
  the downloaded ids": `downloadedIdsKey(map)` returns the same string for two
  maps that differ only in a download's progress, and a different string when a
  download finishes. `listRules.test.ts` asserts that the four screens do not
  call `useDownloadMap(` or `usePlayer(`.
- **The change:** add `useDownloadedIds()` to `useDownloads.ts`, a selector that
  changes only when the set of finished downloads changes (the `finished` string
  in `useStorageUsed` is the pattern). `PodcastShow.tsx` uses it in place of
  `useDownloadMap()`. Give the lists a `renderItem` and `keyExtractor` that keep
  their identity (`useCallback`), and pass rows constant props (`here` as a
  module constant). In `PodcastEpisode.tsx`, replace `usePlayer()` with
  `usePlayerValue` selectors for the few values it shows.
- **Test:** vitest. Flow 4. Phone step 6.
- **Done when:** the tests pass and the screens look and behave the same.
- **Risk:** a stale closure in a memoized `renderItem` (for example the
  selection). List every value it reads in its dependencies.

### S9. Simulator checks with Maestro (test harness)

- **Symptom:** none. It is how B and C are proven without a phone.
- **Files owned (all new):** `tools/fork/ui-checks/flows/*.yaml`,
  `tools/fork/ui-checks/run.sh`,
  `tools/fork/ui-checks/Run the UI checks.command`,
  `tools/fork/ui-checks/Install the UI check tools.command`,
  `tools/fork/ui-checks/README.md`, `.github/workflows/ui-checks.yml`.
- **First step:** read Maestro's current documentation (docs.maestro.dev) for
  the exact command names before writing a flow. Then get `smoke.yaml` green in
  GitHub before writing the others.
- **The change:** the workflow runs on `workflow_dispatch` and on pushes to
  `claude/**` that change the Podcasts screens or the flows. It reuses Fork CI's
  steps up to `pod install`, builds a simulator build that carries its own
  JavaScript (Release, unsigned, with Sentry's upload turned off), boots a
  simulator, installs the app with `xcrun simctl install`, runs `maestro test`,
  and uploads screenshots and the recording. `run.sh` does the same on a Mac
  from a built `.app`. The `.command` files only call it, and say plainly what
  is missing when a tool is not installed. Flows find things by the `testID`s
  from S1 (`podcasts-mini-player`, `podcasts-player`, `podcasts-player-close`).
  For the run on `main`, which has no ids yet, find the mini player by the
  episode's title.
- **Test:** the workflow's own run. Flow 2 run once on `main` (see "How we
  test").
- **Done when:** `smoke.yaml` and `player-opens-once.yaml` pass on the round's
  branch in GitHub, and the pull request says what flow 2 did on `main`.
- **Risk:** the mini player lives in the native tab bar and is mounted twice, so
  Maestro may not see it or may pick the hidden copy. The flows need the network
  for a public feed. Nothing private goes in a flow: use a well-known public
  show, not Mo's library. If the accessory cannot be driven, say so and keep
  flows 1 and 4.

### M1. Measure the exact episode on the Mac (coordinator, no code)

Follow "How we test", part 3, before and after S2 and S3. Record: the raw
error's type on `main`, the number of parts that could not be checked on the
branch, the ads found, and from `--head 90 --timings` when the Burlington spot
was first known. That last number decides held item H1.

## Ask-Mo items

1. **A small diary file on the phone (S5).** It holds the ad finder's steps and
   error names, no transcript words, at most 500 lines, and leaves the phone
   only when Mo taps "Send skip log". Recommended: yes. Without it nobody can
   say why a pre-roll was missed.
2. **Skipping the ad before the show starts on a first listen (A2).** The only
   ways are to ask the model earlier or to hold the start longer than 3 seconds,
   and both change how fast an episode starts. Recommended: not in this round.
   Measure first (M1), then decide.
3. **New words on the status line (S4).** "Ad check paused. Trying again soon"
   in place of "Ads can't be found: Finding ads stopped: …". Recommended: yes.
4. **Running the simulator checks on GitHub (S9).** No money (public
   repository), about an hour per run. Recommended: yes, started by hand and on
   pushes that touch the Podcasts screens.

Nothing in this round costs money, deletes user data or changes the database.

## How Opus should check this round

For every milestone: was the named test written first, does it fail without the
change, and does it pass for the right reason?

- **S1.** Trace every event order through `step`: open, open, shown; open, gone
  before shown; close, close; leaving, stayed; leaving, open, gone; timeout in
  every state. Can the gate ever rest in opening or closing with no timer
  running? Is the timer cleared on `shown` and `gone`? Is there any
  `router.push("/podcasts/player")` left outside the gate? Does `goToShow`
  (`PlayerScreen.tsx:105-113`), which closes and then pushes a show page, still
  work? Does the page request survive only when a push really happens? Do both
  mounted copies of the mini player share the one gate?
- **S2.** Does `classify` name no iOS 27 symbol? Is `CancellationError` passed
  through? Could the word list turn "model not downloaded" or "busy" into
  refused? Is the order of the `catch` clauses still right?
- **S3.** Is the recursion bounded? Are answers from halves in the same line
  numbering as before? Are refused pieces still remembered in the progress file
  so that they are not asked again each run? Does any older test now pass for
  the wrong reason?
- **S4.** Does every older status still appear when it should (phone reasons,
  transcript failed, not downloaded)? Is the 40 character limit a real property
  of the text and not of one test case?
- **S5.** Thread safety of the append. Is the file capped? Does anything read
  `skip-log.jsonl` strictly? Is every new file's import list complete? Was any
  `private` member called from another file? Does a diary line ever hold
  transcript text?
- **S6.** Grep every reader that relied on the 15 second notice. Is the position
  still saved every 15 seconds and on pause, seek, episode change and app
  background?
- **S7 and S8.** Can a memoized row go stale: a field the comparison skips, a
  callback that closes over old state, a selection that no longer updates? Do
  rows still update for a download finishing, a queue change, played, saved and
  archived? Are the source-reading tests strict enough to catch the hook being
  renamed or re-exported?
- **S9.** Do the flows prove anything on `main`? Is anything private, any audio
  or any key in the folder or the workflow?
- **Whole round.** Re-entrancy (two taps in one frame, a tap during a
  dismissal), state left behind after an error, memory (timers and listeners
  removed), every changed Swift signature's callers, and
  `node tools/fork/check-fork.mjs`.

## Other problems found in the sweep

| Problem                                                                                                  | Where                                                             | Mark              | Handled by |
| -------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------- | ----------------- | ---------- |
| A double tap on the player's close control goes back twice and leaves the page under it, or the section. | `podcasts/PlayerScreen.tsx:100-103`                               | likely            | S1         |
| A page request stays set when the player does not mount, so a later plain open shows the transcript.     | `modules/podcasts/playerPageRequest.ts`, `PlayerScreen.tsx:59-61` | confirmed by code | S1         |
| The head scan's model errors leave no trace on the phone.                                                | `modules/podcasts/ios/PodcastStreamHead.swift:348`                | confirmed by code | S5         |
| A failure that is not a refusal is retried at every return to the app, for ever.                         | `modules/podcasts/ios/PodcastAdFinder+Retry.swift:12-27`          | confirmed by code | Later      |
| The transcript panel loads the whole transcript again at every saved piece while transcribing.           | `podcasts/useTranscriptLines.ts:30-66`                            | confirmed by code | Later      |
| The transcript and chapter panels draw twice a second.                                                   | `podcasts/TranscriptView.tsx:86`, `podcasts/ChapterList.tsx:27`   | confirmed by code | Later      |
| Opening the account sheet just as the player slides away can reach the native modal lock.                | `RNSScreenStack.mm`, about line 571                               | needs device      | Later      |
| Deleting the playing episode's download: the player falls back to the plain address. No bug found.       | `modules/podcasts/ios/PodcastDownloader.swift:161-173`            | confirmed by code | none       |
| Fast taps on different play buttons: the newest wins. No bug found.                                      | `modules/podcasts/playback.ts:336-356`                            | confirmed by code | none       |

Not walked in this pass, for lack of time: first launch, no network, calls and
Siri, AirPods and the lock screen, rotation, the sleep timer, queue edits and an
app killed during a download. They need their own sweep.

## Later (held, not built in this round)

- **H1.** Ask the model at the head scan's 15 second step, or hold the start
  longer, to catch pre-rolls. Needs M1's numbers and Mo's answer (Ask-Mo item
  2).
- **H2.** Tune the lists (`windowSize`, `initialNumToRender`,
  `maxToRenderPerBatch`) and look again at one SwiftUI menu per row. Only if
  phone step 6 still stutters after S6 to S8, because these trade blank rows for
  speed.
- **H3.** Patch react-native-screens' modal lock. Only if the player still
  cannot open after S1. It needs a patch file outside the fork's paths, so it
  needs a new touch point.
- **H4.** Read the quick rules over refused stretches and keep what they find as
  unsure ads.
- **H5.** Stop retrying a failure that returns the same error three times.
- **H6.** Lower the priority of transcribing while the listener scrolls. Only
  with a measurement.
- **H7.** Narrow the player's own reads of the player view
  (`PlayerScreen.tsx:54`, the transcript and chapter panels).
