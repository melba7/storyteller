# Podcasts stability sweep: the flows the first plan did not walk

Written 2026-11-18 by the second planner of the stability round. It goes with
`docs/PODCASTS-STABILITY-PLAN.md` (S1 to S9: the player that stacks, the mini
player's taps, ads that are not found, list stutter). Nothing from that plan is
planned again here, and nothing in this file has been built.

Paths are relative to `applications/mobile/` unless they start with `libraries/`
or `docs/`. Line numbers are those of 2026-11-18. The files the running builders
own (`playback.ts`, `PlayButton.tsx`, `MiniPlayer.tsx`) were changing while this
was written, so their line numbers may have moved.

Every finding carries one of three marks:

- **confirmed by code**: the code path was read end to end and does this.
- **likely**: the code allows it and nothing stops it, but one step was not
  proven.
- **needs device**: only a phone can say.

## What was walked and what not

| Flow                             | What was read                                                                                                                                                                                        | Result                                                                                                                               |
| -------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| First launch                     | `podcasts/Home.tsx` (empty state), `modules/podcasts/background.ts`, the player with nothing loaded (`playback.ts`, `PodcastPlayer.play()`)                                                          | No bug found.                                                                                                                        |
| No network                       | Start of a stream offline (`PodcastStreamDownload.swift:206-211`, `:331-362`), the failed item (`PodcastPlayer.swift:364-380`), the play button                                                      | F2, F3.                                                                                                                              |
| Flaky network                    | The stream's resume rules (`libraries/PodcastKit/Sources/PodcastDownloads/StreamRules.swift:168-178`), seeks that wait for bytes (`PodcastPlayer.swift:53-60`, `:220-238`)                           | F1, F2, F3.                                                                                                                          |
| Calls and Siri                   | `PodcastPlayer.swift:397-417` and the book's handler (`modules/readium/ios/AudiobookPlayerActor.swift:707`) against Apple's "Handling audio interruptions"                                           | No bug found. One note under Later (L4).                                                                                             |
| AirPods, Bluetooth, lock screen  | The route change (`PodcastPlayer.swift:419-430`), the commands (`PodcastPlayer+Book.swift:46-57`, `modules/readium/ios/LofiRemoteHandoff.swift`), the card (`PodcastLockScreen.swift`)               | F1 (quick presses add up wrongly), F7.                                                                                               |
| Sleep timer                      | `PodcastPlayer+Sleep.swift`, `libraries/PodcastKit/Sources/PodcastPlayback/SleepTimer.swift`                                                                                                         | Countdown, fade and end of episode: no bug found. End of chapter: F6.                                                                |
| Queue edits during playback      | `PodcastPlayer+UpNext.swift`, `libraries/PodcastKit/Sources/PodcastPlayback/UpNext.swift`, `podcasts/UpNext.tsx`, `podcasts/PlayerQueue.tsx`, `podcasts/DragList.tsx`                                | No bug that needs a milestone. F8 and two small notes under Later (L8, L12).                                                         |
| App killed during a download     | `PodcastsAppDelegate.swift`, `PodcastDownloader.swift`, `libraries/PodcastKit/Sources/PodcastDownloads/DownloadRules.swift`, `DownloadRecovery.swift`, `DownloadStore.swift` against Apple's article | No bug found. The session is made again at launch with the same name, as Apple asks.                                                 |
| Books and Podcasts while playing | `PodcastPlayer+Book.swift`, `PodcastLockScreen.swift`, `modules/readium/ios/LofiNarratorBridge.swift`, `AudiobookPlayerActor.swift:229-274`, `:596-620`                                              | Starting one pauses the other, and after a call only one resumes: no bug found. One mismatch: F7.                                    |
| Very large libraries             | Every Home and Library query, timed on made-up libraries (below)                                                                                                                                     | No index or database change is needed. The cost is how often the lists load again: F4.                                               |
| An episode with odd or no length | `libraries/PodcastKit/Sources/PodcastPlayback/Rules.swift:26-39`, `modules/podcasts/playbackRules.ts:61-71`, `modules/podcasts/dbFeeds.ts:82-91`, `modules/podcasts/db.ts:157-173`                   | No length: no bug found. A length that is wrong: F5.                                                                                 |
| Deleting the playing episode     | `podcasts/useDownloads.ts:142-161`, `PodcastDownloader.swift:161-173`, `modules/podcasts/db.ts:198-212`                                                                                              | A stream's own download: falls back to the plain address (first plan). A finished file that is playing: needs device. F2 is the net. |
| Rotation, iPad, CarPlay, AirPlay | Not walked. They need a device.                                                                                                                                                                      | Not determined.                                                                                                                      |

**The timing for large libraries.** The app's own SQL was run in Node's SQLite
on made-up libraries (the phone is slower, the shape is the same). With 30 shows
of 150 episodes (4,500 rows) every Home and Library query took 3 ms or less, and
History 15 ms. With 150 shows of 400 episodes (60,000 rows) the slowest list
query took 44 ms and History 310 ms (it has no limit). So the queries are not
what makes a normal library stutter.

**What Apple's documentation says** (developer.apple.com, read 2026-11-18):

- _Handling audio interruptions_: "AVPlayer monitors your app's audio session
  and automatically pauses playback in response to interruption events", and the
  end of an interruption carries `shouldResume`. The code follows this. The same
  page says that from iOS 27 there are new notices and that the old
  `interruptionNotification` "can get out of sync when the system can't deliver
  an end event". The new names cannot be used while the app must compile with
  Xcode 26 (L4).
- _Responding to audio route changes_: pause when the old device went away. The
  code does (`PodcastPlayer.swift:419-430`).
- `AVPlayerItem.Status.failed`: "The item no longer plays due to an error." This
  is the base of F2.
- `AVPlayer.seek(to:toleranceBefore:toleranceAfter:completionHandler:)`: "The
  completion handler for any prior seek request that is still in process will be
  invoked immediately with the finished parameter set to false." The player's
  own count of seeks (`PodcastPlayer.swift:220-238`) handles this correctly.
- _Downloading files in the background_: "recreate the background session …
  using the same session identifier as before". The code does.
- `beginBackgroundTask(withName:expirationHandler:)`: "Failure to end the task
  explicitly will result in the termination of the app." See L9.
- `MPNowPlayingInfoCenter` and `MPRemoteCommandCenter`: nothing on these pages
  contradicts how the card and the commands are shared with the book.
- `silenceSecondaryAudioHintNotification` is for an app's optional secondary
  audio. A podcast is primary audio, so it does not apply.

## Findings

Ranked by how often a normal listener meets it and how bad it is.

| Id  | What the listener meets                                                                                                                                                                                                                                                                                           | Where                                                                                                                                                                                                                             | Mark                                                                             | Handled by     |
| --- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------- | -------------- |
| F1  | While a seek is on its way the player reports the old place. (a) A resumed stream shows 0:00 until its bytes arrive. (b) Picking another episode in that time saves 0:00 as the first one's place: the place is lost. (c) Several quick skip presses count as one. (d) A scrub is undone by "rewind after pause". | `PodcastPlayer.swift:53-58`, `:153`, `:165`, `:183`, `:246-248`, `:292-299`, `:353-362`; `PodcastPlayer+UpNext.swift:24-30`; `PodcastPlayer+Settings.swift:53`; `modules/podcasts/playback.ts:195-215` (`onState`), `:374`        | confirmed by code. How long the wait lasts on a real network needs device.       | S10            |
| F2  | An episode that failed (played offline, a connection that dropped, a deleted file) cannot be started again. Play does nothing. The listener must pick another episode and come back, or restart the app.                                                                                                          | `PodcastPlayer.swift:171-176`, `:364-380`; `modules/podcasts/playback.ts:359-363`, `:435-441`; `podcasts/PlayerNowPlaying.tsx:104-112` (the error line has no retry)                                                              | confirmed by code. Whether iOS ever revives such an item by itself needs device. | S11            |
| F3  | A stream that is still loading cannot be paused in the app. The button shows a spinner and a tap sends Play again. The audio then starts by itself when the network is back, perhaps in a pocket.                                                                                                                 | `modules/podcasts/playback.ts:435-441` (`togglePlayPause`); `podcasts/PlayButton.tsx:27-34`; `podcasts/PlayerTransport.tsx:76-79`. Swift's own rule is right (`PodcastPlayer.swift:201-205`), so the lock screen is not affected. | confirmed by code                                                                | S12            |
| F4  | Three seconds after the app comes to the front (when 30 minutes have passed) every feed is read, and after each show every open list loads again, whether or not anything changed. With 30 shows that is 30 reloads of every mounted screen while the refresh runs.                                               | `modules/podcasts/dbFeeds.ts:225`, `:241-266`; `modules/podcasts/background.ts:63-67`; `modules/podcasts/automatic.ts:240`; `modules/podcasts/automaticRun.ts:250-260`; `podcasts/hooks.ts:27-31`                                 | confirmed by code. How much of the stutter it causes needs device.               | S13            |
| F5  | An episode stopped in its last minutes starts again at 0:00, when the feed's length is shorter than the real audio (inserted ads, or a feed with a wrong length). With a badly wrong length every resume restarts.                                                                                                | `libraries/PodcastKit/Sources/PodcastPlayback/Rules.swift:32-38`; `PodcastPlayer.swift:149-151`; `modules/podcasts/playbackRules.ts:61-71`. The real length is never kept (`dbFeeds.ts:82-91`, `db.ts:157-173`)                   | confirmed by code. How many of Mo's shows have such lengths is not known.        | S14 (Ask-Mo 1) |
| F6  | "Sleep at the end of the chapter" is cancelled without a word when an ad skip jumps over the chapter's end. Ad breaks sit at chapter changes, so playback goes on all night.                                                                                                                                      | `PodcastPlayer+Sleep.swift:95-105`; `libraries/PodcastKit/Sources/PodcastPlayback/SleepTimer.swift:61-72`; `PodcastPlayer+Ads.swift:199`                                                                                          | confirmed by code. Only for shows with chapters and ad skipping on.              | S15            |
| F7  | A podcast is paused, a book is opened but not played. The lock screen shows the book, and its play button starts the podcast.                                                                                                                                                                                     | `modules/readium/ios/AudiobookPlayerActor.swift:270-273`, `:602-620`; `PodcastPlayer+Book.swift:30-36`; `PodcastLockScreen.swift:46-56`, `:68-84`                                                                                 | confirmed by code. Rare.                                                         | Later (L1)     |
| F8  | An episode marked played stays in Up Next and plays later.                                                                                                                                                                                                                                                        | `modules/podcasts/dbEpisodes.ts:33-44`; only unfollowing and deleting a file take episodes out (`db.ts:204`, `dbLocalFiles.ts:117`)                                                                                               | confirmed by code. Whether it is wanted is Mo's choice.                          | Later (L2)     |

Read and found sound, so nothing is planned: what happens after a call
(`shouldResume`), headphones pulled out, the countdown sleep timer and its fade,
"stop at the end of the episode", a download that is running when the app is
killed or force-quit, the empty first launch, and the automatic archive and
delete (they skip the loaded episode and Up Next).

## Milestones

**Files the running builders own. No milestone below may touch them before their
work is merged into the round's branch.**

- S1: `app/(root)/podcasts/_layout.tsx`, `modules/podcasts/playerGate*.ts`,
  `podcasts/MiniPlayer.tsx`, `podcasts/PlayerScreen.tsx`,
  `podcasts/EpisodeMenu.tsx` lines 191-192,
  `modules/podcasts/playerPageRequest.ts`.
- The ads builder: `libraries/PodcastKit/Sources/PodcastAds*`, AdsRunner,
  AdsStatus, AppleAdDetector, `adLine.ts`, `PodcastTimeline.swift`,
  `PodcastSkipLog.swift`, `PodcastAdFinder*.swift`, and the one catch in
  `PodcastStreamHead.swift` near line 348.
- The performance builder: `modules/podcasts/playback.ts`, `playbackRules.ts`,
  `db.ts` (`savePlayback`), `podcasts/EpisodeRow.tsx`, `EpisodeMenu.tsx`,
  `PlayButton.tsx`, `useUpNext.ts`, `useSelection.ts`, `PodcastShow.tsx`,
  `EpisodeListScreen.tsx`, `PlaylistScreen.tsx`, `PodcastEpisode.tsx`,
  `useDownloads.ts`, `modules/podcasts/downloads.ts`.

**Order of importance:** S10, S11, S13, S12, S14, S15.

**Wave 1, in parallel now (no shared files, none of the files above):**

- Builder A: S10, then S11. Both edit `PodcastPlayer.swift`, so they are one
  builder, one after the other.
- Builder B: S13.
- Builder C: the Swift half of S14 (only after Mo's answer to Ask-Mo 1).
- Builder D: S15.

**Wave 2, after the performance builder's work is merged:** one builder takes
S12 and the JavaScript half of S14. Both edit files that builder owns today.

Merge in the order S13, S15, S14 (Swift), S10, S11, S12, S14 (JavaScript). Run
`tools/fork/check.sh` on the main checkout after each merge (see
`docs/LESSONS.md` on worktrees).

Rules for every milestone: write the named test first and see it fail. Run
`yarn oxfmt` from the repository root on the changed directories, then
`tools/fork/check.sh`. Add no dependency. Comments in plain English sentences.
Never weaken or delete a test. No upstream file changes and no new touch point
is needed by any milestone here. Nothing here may make the player skip more
audio than it does today.

For the Swift milestones: the code under `modules/podcasts/ios` compiles only on
a Mac (Fork CI), never in the cloud. Read the callee signatures named in the
milestone before calling them. A new file needs every import it uses. A
`private` member of `PodcastPlayer.swift` cannot be called from an extension
file. `PodcastPlayer.swift` already has 432 lines, so new code goes into
extension files and the main file gets only the lines named below. A new
PodcastKit file needs nothing in `Package.swift`, and a new file under
`modules/podcasts/ios` is picked up by the podspec
(`source_files = "**/*.swift"`). Test classes must not have a property called
`hash`, `description` or `name`.

### S10. The player knows its place while a seek is on its way (F1)

- **Symptom:** F1 (a) to (d).
- **Root cause:** `PodcastPlayer.swift:53-58` says it itself:
  `player.currentTime()` is the old place until a seek lands, and for a resumed
  stream that is until the bytes up to the place have arrived. But `begin`
  publishes that clock right after asking for the resume seek (`:153`, `:165`),
  so JavaScript shows 0:00 (`onState`, `playback.ts:195-215`) and saves it when
  another episode is picked (`playEpisode`, `playback.ts:374`). `skip(by:)` adds
  to the old place (`:246-248`), so presses that arrive before the first seek
  lands all aim at the same target. `playingItem()` puts the old place into Up
  Next (`PodcastPlayer+UpNext.swift:24-30`). `rewindAfterLongPause` rewinds from
  the old place and so undoes a scrub made while paused
  (`PodcastPlayer+Settings.swift:53`). The start hold and the stream fallback
  already use the right value (`PodcastPlayer+StartHold.swift:77`,
  `PodcastPlayer+Stream.swift:70-71`).
- **Files owned:** `libraries/PodcastKit/Sources/PodcastPlayback/Playhead.swift`
  (new), `libraries/PodcastKit/Tests/PodcastPlaybackTests/PlayheadTests.swift`
  (new), `modules/podcasts/ios/PodcastPlayer.swift`,
  `modules/podcasts/ios/PodcastPlayer+UpNext.swift`,
  `modules/podcasts/ios/PodcastPlayer+Settings.swift`,
  `modules/podcasts/ios/PodcastPlayer+Bookmarks.swift`.
- **Read first:**
  `Skip.target(from position: Double, by amount: Double, duration: Double?) -> Double`
  and `Skip.clamp(_ position: Double, duration: Double?) -> Double`
  (`Rules.swift:12-22`); in `PodcastPlayer.swift`: `var position: Double`
  (`:265`),
  `func publish(positionOverride: Double? = nil, refreshCard: Bool = true)`
  (`:292`), `func state() -> [String: Any]` (`:261`),
  `func movePlayhead(to seconds: Double)` (`:220`), `func forgetPendingSeek()`
  (`:241`).
- **Imports:** `Playhead.swift` needs `import Foundation` only. The test file
  needs `import XCTest` and `@testable import PodcastPlayback`. No iOS file gets
  a new import.
- **Failing test first** (`PlayheadTests.swift`):
  `testAPendingSeeksTargetIsThePlace` asserts that
  `Playhead.place(reported: 0, seekPending: true, seekTarget: 2700)` is 2700 and
  that `Playhead.place(reported: 812, seekPending: false, seekTarget: 2700)`
  is 812. `testTwoQuickSkipsAddUp` asserts that a skip of 30 from a reported 600
  lands on 630, and that a second skip of 30 while that seek is pending
  (reported still 600, target 630) lands on 660.
  `testATargetThatIsNotANumberIsIgnored` asserts that a pending target of `.nan`
  gives the reported place, and that a reported `.nan` gives 0.
- **The change:**
  1. `Playhead.swift`: `public enum Playhead` with
     `public static func place(reported: Double, seekPending: Bool, seekTarget: Double) -> Double`.
  2. `PodcastPlayer.swift`: add `var place: Double` under `position`. It returns
     `Playhead.place(reported: position, seekPending: seekPending, seekTarget: seekTarget)`.
     Use it in `publish` (`positionOverride ?? place`), in `state()`, in
     `skip(by:)` and in the "a finished episode starts over" check in
     `startPlaying()` (`:183`).
  3. `PodcastPlayer+UpNext.swift:28`: `item.position = place`.
     `PodcastPlayer+Settings.swift:53`: `seek(to: place - back)`.
     `PodcastPlayer+Bookmarks.swift:27`: `positionSeconds: place`.
  4. Leave `position` itself alone, and every other reader of it: the ad
     skipper, silence trimming, chapters, the sleep timer, the outro, the
     statistics. They decide about audio that is really being heard and must
     keep reading the real clock.
- **Done when:** the tests pass in Docker (`swift:6.2`), `tools/fork/check.sh`
  passes, Fork CI compiles the branch, and the diff touches none of
  `PodcastPlayer+Ads.swift`, `PodcastPlayer+Sound.swift`,
  `PodcastPlayer+Chapters.swift`, `PodcastPlayer+Sleep.swift` and
  `PodcastPlayer+ShowSettings.swift`.
- **Check on device:** (1) Listen to a not-downloaded episode for 20 minutes or
  scrub that far, play another episode, then tap the first one again: the mini
  player shows the saved time at once, not 0:00. (2) While it still loads, tap a
  third episode, then look at the first one's row: its place is still there. (3)
  On the lock screen press skip-forward three times fast: the time moves by
  three skips.
- **Risk:** while a seek waits, the shown place is where the listener asked to
  go, not where audio is. That is what the seek bar already shows after a scrub.
  If a seek could stay pending for ever the place would freeze, so Opus checks
  every way `seekPending` ends.

### S11. Play starts a failed episode again (F2)

- **Symptom:** F2.
- **Root cause:** when the item fails, the player only reports it
  (`PodcastPlayer.swift:364-380`). `play()` checks that there is an item and
  calls `player.play()` on it (`:171-192`), and Apple says a failed item "no
  longer plays". JavaScript sends only `play()` for an episode that is already
  loaded (`playback.ts:359-363`, `:435-441`). An item fails when a stream is
  started offline (`PodcastStreamDownload.swift:206-211` hands over to the plain
  address, which then fails), when a stream's own download drops and cannot be
  carried on (no ETag or Last-Modified, or ten minutes without a network:
  `StreamRules.swift:168-178`, `PodcastStreamDownload.swift:331-362`), and
  perhaps when the playing file is deleted.
- **Files owned:**
  `libraries/PodcastKit/Sources/PodcastPlayback/PlayRecovery.swift` (new),
  `libraries/PodcastKit/Tests/PodcastPlaybackTests/PlayRecoveryTests.swift`
  (new), `modules/podcasts/ios/PodcastPlayer+Reload.swift` (new),
  `modules/podcasts/ios/PodcastPlayer.swift` (after S10, same builder).
- **Read first:** `struct Episode` (`PodcastPlayer.swift:73-99`),
  `func begin(_ episode: Episode)` (`:110-167`), `var current: QueueItem?`
  (`:39`); `startNextInQueue()` (`PodcastPlayer+UpNext.swift:34-58`), which
  builds an `Episode` from a `QueueItem` and is the pattern to copy;
  `func skipAds(forShow showId: String?) -> Bool` (`:61-64`);
  `QueueSource.url(for item: QueueItem, localFile: URL?) -> URL?`
  (`libraries/PodcastKit/Sources/PodcastPlayback/UpNext.swift:141`);
  `PodcastDownloader.shared.localFile(for episodeId: String) -> URL?`
  (`PodcastDownloader.swift:175`).
- **Imports:** `PodcastPlayer+Reload.swift` needs `import Foundation` and
  `import PodcastPlayback` (as `PodcastPlayer+UpNext.swift` has for the same
  calls), and starts with `@MainActor extension PodcastPlayer`. It may use
  `current`, `begin`, `recovery` and `skipAds(forShow:)`. It must not use the
  `private` members `episodeId`, `knownDuration`, `emitError` or `stateObject`.
  `PlayRecovery.swift` needs `import Foundation` only.
- **Failing test first** (`PlayRecoveryTests.swift`):
  `testPlayAfterAFailureStartsAgainAtTheLastGoodPlace` loads at 0, notes 1200,
  fails, notes 0, and asserts that `reloadPlace` is 1200 and that
  `place(reported: 0)` is 1200. `testNothingIsReloadedWhileTheItemIsFine`
  asserts that `reloadPlace` is nil and `place(reported: 30)` is 30.
  `testAFailureBeforeAnythingPlayedStartsAtTheStartPlace` loads at 900, fails,
  and asserts 900. `testANewItemForgetsTheFailure` asserts nil after `loaded`.
- **The change:**
  1. `PlayRecovery.swift`: a `public struct PlayRecovery` with
     `mutating func loaded(startingAt:)`, `mutating func noted(_ place:)`
     (ignored after a failure and for values that are not a number),
     `mutating func itemFailed()`, `var reloadPlace: Double?` (the last good
     place after a failure, else nil) and `func place(reported:) -> Double` (the
     last good place after a failure, else the reported one).
  2. `PodcastPlayer.swift`: one property `var recovery = PlayRecovery()`. In
     `begin`, call `recovery.loaded(startingAt: start)` before the autoplay
     line. In `tick()` call `recovery.noted(place)`, and in `seek(to:)`
     `recovery.noted(target)`. In `itemStatusChanged` (when there is a failure)
     and in `failed(_:)` call `recovery.itemFailed()` before publishing. In
     `publish` and `state()` report `recovery.place(reported: …)`, so a failed
     item's clock never reaches JavaScript and is never saved. In `play()`,
     after the guard: `if reloadIfFailed() { return }`.
  3. `PodcastPlayer+Reload.swift`: `func reloadIfFailed() -> Bool`. When
     `recovery.reloadPlace` and `current` are set and `QueueSource.url` gives a
     source, it calls `begin` with an `Episode` built like the one in
     `startNextInQueue()`, with `savedPosition` the reload place,
     `played: false`, `autoplay: true` and `queueURL: item.url`, and returns
     true. It does not call `load`, so Up Next is not touched.
  4. No retry by itself. Only a press of Play (in the app, on the lock screen,
     on headphones) reloads.
- **Done when:** the tests pass in Docker, `tools/fork/check.sh` passes and Fork
  CI compiles the branch.
- **Check on device:** (1) Airplane mode on, tap an episode that is not
  downloaded, wait for the "couldn't be played" line. Airplane mode off, tap
  Play: it plays. (2) Stream an episode for a few minutes, airplane mode on,
  wait until the error line shows (with skipping on this can take ten minutes),
  airplane mode off, tap Play: it carries on within seconds of where it stopped.
  (3) Play a downloaded episode, delete its download in the menu, and scrub: if
  it stops with the error line, Play starts it again as a stream at the same
  place.
- **Risk:** a reloaded stream that plays through its own download starts that
  download from the first byte, so a place far into the episode takes as long to
  come back as it does today when the episode is picked again. A source that
  keeps failing shows its error once for every press. The reload goes through
  `begin`, so an end-of-chapter sleep timer is cancelled
  (`PodcastPlayer+Chapters.swift:52`) and the intro counts as skipped a second
  time in the statistics. Until S14 is in, a reload within the feed's last ten
  seconds starts at 0:00 (F5).

### S12. A stream that is still loading can be paused (F3)

- **Symptom:** F3.
- **Root cause:** `togglePlayPause` in `modules/podcasts/playback.ts:435-441`
  pauses only when `isPlaying` is true. While a stream loads, `isPlaying` is
  false and `isBuffering` is true, so the tap sends `play()` again, which
  changes nothing. `pressEpisode` in `podcasts/PlayButton.tsx:27-34` does the
  same for the button on a row.
- **Files owned:** `modules/podcasts/playback.ts`,
  `modules/podcasts/playback.test.ts`, `podcasts/PlayButton.tsx`. **All three
  belong to the performance builder today. This milestone must wait and be
  merged after that work.** `podcasts/MiniPlayer.tsx` (S1) and
  `podcasts/PlayerTransport.tsx` need no change: they call
  `player.togglePlayPause()`.
- **Failing test first** (`playback.test.ts`): "a tap while the stream is
  loading pauses it" plays an episode, sends the native state
  `{ isPlaying: false, isBuffering: true }`, calls `togglePlayPause()` and
  asserts that the native `pause` was called once and `play` was not called
  again. "a tap during the start check lets the episode start" sends the same
  state with `checkingStart: true` and asserts that `play` was called and
  `pause` was not (Swift ends its short wait on a second Play:
  `PodcastPlayer.swift:171-176`).
- **The change:** in `togglePlayPause`, pause when
  `isPlaying || (isBuffering && !checkingStart)`. In `pressEpisode`, call
  `playEpisode` only for the status `"idle"` and `togglePlayPause` for
  `"playing"` and `"buffering"`.
- **Done when:** the tests pass and `tools/fork/check.sh` passes.
- **Check on device:** play an episode that is not downloaded and scrub far
  ahead so the spinner shows. Tap the spinner: it becomes the play sign, and no
  audio starts by itself. Tap again: it loads and plays.
- **Risk:** the first moments of a new episode (`loaded` is false) still go
  through `playEpisode`, as today. The start check's "tap again to start now"
  must keep working, which the second test holds.

### S13. A feed refresh tells the screens only when something changed (F4)

- **Symptom:** F4.
- **Root cause:** `readFeedAgain` ends with `notifyLibraryChanged()` for every
  show (`modules/podcasts/dbFeeds.ts:225`), also when no episode was added or
  changed. `refreshAllShows` reads the shows one after the other (`:256-264`),
  and every `useLibraryQuery` runs its query again on each notice
  (`podcasts/hooks.ts:27-31`). The refresh starts three seconds after the app
  comes to the front (`modules/podcasts/background.ts:63-67`) when 30 minutes
  have passed (`modules/podcasts/automatic.ts:240`). `refreshedAt` is written
  each time but no screen shows it (`modules/podcasts/library.ts:267` is its
  only reader).
- **Files owned:** `modules/podcasts/feedChanges.ts` (new),
  `modules/podcasts/feedChanges.test.ts` (new), `modules/podcasts/dbFeeds.ts`.
  `dbFeeds.ts` cannot be imported by a test (it opens op-sqlite), so the rule
  lives in the new file.
- **Failing test first** (`feedChanges.test.ts`): "a feed with nothing new tells
  no screen" asserts that `feedChanged(show, feed, { inserted: 0, updated: 0 })`
  is false when the feed's title, author, description, picture, link, language,
  categories, funding and people equal the stored show's. Further cases assert
  true for one inserted episode, for one updated episode, and for a change in
  each of the nine fields. One case stores `author: null` and reads a feed with
  no author, and asserts false.
- **The change:** `feedChanges.ts` exports
  `feedChanged(stored: Show, feed: PodcastFeedData, counts: { inserted: number; updated: number }): boolean`.
  It compares the same values that the `UPDATE shows` statement writes
  (`dbFeeds.ts:187-203`), made the same way (`?? null`, `JSON.stringify`, the
  `toJson` helpers of `people.ts`), leaving out `refreshed_at`. Import the types
  with `import type`, so the test loads no native module. In `readFeedAgain`
  call `notifyLibraryChanged()` only when `feedChanged` says yes. In
  `refreshAllShows` call `notifyLibraryChanged()` once after the loop, so
  anything the comparison missed still reaches the screens once per run. The
  database writes stay as they are.
- **Done when:** the test passes, `tools/fork/check.sh` passes, and
  `grep -n "notifyLibraryChanged()" modules/podcasts/dbFeeds.ts` shows the call
  in `readFeedAgain` behind the condition.
- **Check on device:** with 20 or more shows, leave the app closed for an hour,
  open it and scroll Home and a show's page during the first half minute. Pull
  to refresh on Library still shows new episodes when it ends.
- **Risk:** a stored value and a feed value that are spelled differently (null
  and an empty string) would make every refresh look changed: no gain, no harm.
  A change the comparison misses shows up at the end of the run, or for the
  pull-to-refresh on one show's page (`podcasts/PodcastShow.tsx:82`) at the next
  notice.

### S14. An episode stopped near its end resumes there (F5, Ask-Mo 1)

- **Symptom:** F5.
- **Root cause:** `ResumeRule.start` returns 0 when the saved place is at or
  past the length, or within 10 seconds of it
  (`libraries/PodcastKit/Sources/PodcastPlayback/Rules.swift:32-38`). The length
  it is given is the feed's (`PodcastPlayer.swift:149-151`, from
  `episode.durationSeconds`), which every refresh writes again
  (`modules/podcasts/dbFeeds.ts:82-91`). The real length is known only while the
  episode plays and is never kept (`modules/podcasts/db.ts:157-173`). The
  `played` mark is worked out from the real length while playing (`persist`,
  `modules/podcasts/playback.ts:167-181`), so it already covers "stopped at the
  real end". `modules/podcasts/playbackRules.ts:61-71` mirrors the rule for the
  first number the app shows.
- **Files owned:** Swift half, free now:
  `libraries/PodcastKit/Sources/PodcastPlayback/Rules.swift`,
  `libraries/PodcastKit/Tests/PodcastPlaybackTests/PlaybackRulesTests.swift`.
  JavaScript half: `modules/podcasts/playbackRules.ts` and
  `modules/podcasts/playbackRules.test.ts`. **These two belong to the
  performance builder today, so this half waits and is merged after.** The Swift
  half alone fixes what is heard.
- **Read first:** the callers of `ResumeRule.start`:
  `libraries/PodcastKit/Sources/PodcastPlayback/ShowSettings.swift:114` and
  `ListeningStats.swift:185`. Keep the signature, so no caller and no file in
  the iOS module changes.
- **Failing test first** (`PlaybackRulesTests.swift`):
  `testAPlacePastTheFeedsLengthIsKept` asserts that
  `ResumeRule.start(savedPosition: 3660, duration: 3600, played: false)` is 3660
  and that `savedPosition: 3595` gives 3595. The tests at lines 72 to 79 assert
  the old rule (595 of 600 gives 0, 700 of 600 gives 0). They are changed in
  this milestone to the new rule, and the commit message says that the rule
  changed with Mo's OK. This is not a weakened test.
- **The change:** `ResumeRule.start` returns 0 for a played episode and for a
  saved place that is not a usable number, and otherwise the saved place. The
  feed's length no longer decides. The doc comment says why. Then the same in
  `resumeStart` and its test.
- **Done when:** the tests pass in Docker and in vitest, and
  `tools/fork/check.sh` passes.
- **Check on device:** find an episode whose length in the player is longer than
  the length on its row. Stop it past the row's length, play another episode,
  come back: it resumes where it was.
- **Risk:** an episode stopped between 5 and 10 seconds before its real end now
  plays those last seconds and ends, instead of starting over. If the file has
  become shorter than the saved place (new inserted ads), the episode ends at
  once and is marked played. That can already happen today for places below the
  feed's length. L3 would close it.

### S15. The end-of-chapter sleep timer survives an ad skip (F6)

- **Symptom:** F6.
- **Root cause:** `chapterSleepTick` cancels the timer when the place is more
  than 3 seconds past the chapter's end (`PodcastPlayer+Sleep.swift:95-105`,
  `SleepTimer.swift:64-72`). The rule means "the listener moved on". But an ad
  skip moves the playhead without the listener (`PodcastPlayer+Ads.swift:199`
  calls `movePlayhead`), and an ad break that holds the chapter's end jumps
  straight past the 3.5 second window. A listener's own seek always goes through
  `seek(to:)`, which calls `chapterSeeked(to:)` (`PodcastPlayer.swift:207-215`,
  `PodcastPlayer+Chapters.swift:149-152`). The player's own jumps do not (also
  `PodcastPlayer+Chapters.swift:163` and `PodcastPlayer+Sound.swift:213`).
- **Files owned:**
  `libraries/PodcastKit/Sources/PodcastPlayback/SleepTimer.swift`,
  `libraries/PodcastKit/Tests/PodcastPlaybackTests/SleepTimerTests.swift`,
  `modules/podcasts/ios/PodcastPlayer+Sleep.swift`,
  `modules/podcasts/ios/PodcastPlayer+Chapters.swift` (one line in
  `chapterSeeked`).
- **Read first:** `func chapterStatus(at position: Double) -> ChapterStatus`
  (`SleepTimer.swift:68`), `func cancelSleep()`
  (`PodcastPlayer+Sleep.swift:63`),
  `private func chapterSleepTick(_ timer: SleepTimer)` (`:95`),
  `func chapterSeeked(to position: Double)`
  (`PodcastPlayer+Chapters.swift:149`).
- **Imports:** no new file and no new import. The new `sleepSeeked(to:)` must be
  in `PodcastPlayer+Sleep.swift` and must not be `private`, because
  `PodcastPlayer+Chapters.swift` calls it.
- **Failing test first** (`SleepTimerTests.swift`):
  `testAJumpByThePlayerOverTheChaptersEndStillStops` makes a timer for a chapter
  that ends at 600 and asserts that
  `chapterAction(at: 640, listenerSeeked: false)` is `.pause`.
  `testAListenersSeekPastTheEndLetsTheTimerGo` asserts that
  `chapterAction(at: 640, listenerSeeked: true)` is `.cancel`. Both give `.none`
  at 300 and `.pause` at 599.6. The existing `chapterStatus` tests stay as they
  are.
- **The change:** `SleepTimer.swift` gets
  `public enum ChapterAction { case none, pause, cancel }` and
  `public func chapterAction(at position: Double, listenerSeeked: Bool) -> ChapterAction`,
  built on `chapterStatus`: waiting is none, reached is pause, passed is cancel
  for a listener's seek and pause otherwise. `chapterSleepTick` switches on
  `chapterAction(at: position, listenerSeeked: false)`. A new
  `func sleepSeeked(to target: Double)` cancels an end-of-chapter timer when
  `chapterAction(at: target, listenerSeeked: true)` is `.cancel`, and
  `chapterSeeked(to:)` calls it.
- **Done when:** the tests pass in Docker, `tools/fork/check.sh` passes and Fork
  CI compiles the branch.
- **Check on device:** in an episode with chapters and a known ad at a chapter
  change, with ad skipping on, set the sleep timer to "end of chapter" a minute
  before. Playback pauses right after the ad is skipped and the timer shows as
  off. Then set it again and scrub two chapters ahead: the timer goes off and
  playback carries on.
- **Risk:** every jump the player makes over the chapter's end (a skipped
  chapter, trimmed silence) now pauses too. That is what the timer is for. A new
  episode still cancels the timer (`PodcastPlayer+Chapters.swift:52`).

## Ask-Mo

1. **Resume where it was, also near the end (S14).** Today an episode whose
   saved place is within 10 seconds of the feed's length, or past it, starts
   again at 0:00. The feed's length is often shorter than the real audio.
   Recommended: yes, trust the "played" mark and the saved place, not the feed's
   length. It changes a rule that has tests, so it needs your OK.
2. **Should "mark as played" take the episode out of Up Next (F8, L2)?** Today
   it stays and plays later. It removes an entry from your queue, so it is your
   choice. Recommended: yes, as a small milestone after this round.
3. **A book opened while a podcast is paused (F7, L1).** The lock screen shows
   the book but its buttons still control the podcast. Either the buttons go to
   the book as soon as it shows its card, or the card goes back to the podcast
   until the book really plays. Recommended: the card goes back to the podcast,
   which keeps today's rule that whoever played last owns the lock screen. Not
   in this round.

Nothing in this sweep costs money, deletes user data or changes the database
structure.

## How Opus should check these

For every milestone: was the named test written first, does it fail without the
change, and does it pass for the right reason? Then:

- **S10.** Grep every reader of `position` under `modules/podcasts/ios`. Did
  only the six named places change? Do the ad skipper, silence trimming,
  chapters, the sleep timer, the outro and the statistics still read the real
  clock? Trace every way `seekPending` ends: the latest seek lands, a seek is
  interrupted by a direct `player.seek` (`PodcastPlayer+Chapters.swift:163`,
  `PodcastPlayer+Sound.swift:213`; Apple calls the older handler at once with
  false), the item is replaced (`forgetPendingSeek`), the item fails. Can it
  stay true for ever? Does `ended()` still publish the length? Does the lock
  screen's time jump back after a scrub?
- **S11.** List every caller of `play()`: `begin` with autoplay, the lock screen
  (`PodcastPlayer+Book.swift:48`), the end of an interruption
  (`PodcastPlayer.swift:408-410`, guarded by `wantsToPlay`, which a failure sets
  to false), `togglePlayPause`, the module function. Can any of them reload
  without a press? Is `recovery.loaded` called in `begin` before the autoplay
  line, so `begin` cannot call itself? Does the new file use a `private` member
  or miss an import? Is Up Next unchanged by a reload? After a failure, can
  JavaScript still save 0 (trace `publish` after `failed`, then
  `playback.ts:374`)? Does the error line clear when it plays again
  (`playback.ts:208`)?
- **S12.** Does a second tap during the start check still start the episode?
  Does a tap on another episode's button while one loads still start that other
  episode? Is the lock screen's behaviour unchanged?
- **S13.** Are all nine fields compared, each made the same way as in the
  `UPDATE`? Grep the callers of `refreshShow` and `refreshAllShows`
  (`podcasts/useRefreshShows.ts:20`, `podcasts/PodcastShow.tsx:82`,
  `modules/podcasts/automaticRun.ts:221`): does any spinner or list wait for the
  notice from an unchanged refresh? Is the notice at the end of the run sent
  also when a show failed?
- **S14.** Every caller of `ResumeRule.start`, `ShowRules.start` and
  `resumeStart`. Does a played episode still start at 0, and the intro rule
  still hold? Do Swift and JavaScript say the same? Were the old tests changed
  on purpose, with the reason in the commit?
- **S15.** `seek(to:)` now also asks the sleep timer. Its callers that are not
  the listener go backwards (the rewind after a long pause at
  `PodcastPlayer+Settings.swift:53`, a finished episode starting over at
  `PodcastPlayer.swift:183`, "play this ad" at `PodcastPlayer+Ads.swift:153`):
  can any of them cancel a timer wrongly? Does the pause send
  `onSleepTimerChange`, so the app shows the timer as off?
- **Whole sweep.** Every changed Swift signature's callers, imports of new
  files, `private` members reached from extension files, no test weakened,
  `node tools/fork/check-fork.mjs` (no upstream file is touched), and
  `PodcastPlayer.swift` grows only by the lines named.

## Later (held, not built in this round)

- **L1. A book opened while a podcast is paused (F7).** Needs Mo's choice
  (Ask-Mo 3). The hook exists and is empty: `PodcastPlayer+Book.swift:30-31`
  gets the book's track changes through
  `modules/readium/ios/LofiNarratorBridge.swift:61-63`. Only fork files are
  needed, no touch point. The book writes its card just after it calls the hook
  (`AudiobookPlayerActor.swift:602-620`), so writing the podcast's card back
  needs care with the order.
- **L2. "Mark as played" takes the episode out of Up Next (F8).** Needs Mo's
  answer (Ask-Mo 2). `setPlayed` in `modules/podcasts/dbEpisodes.ts:33-44` would
  call `removeManyFromUpNext` (`modules/podcasts/upNextNative.ts:46-50`) when
  `played` is true.
- **L3. Apply "under 10 seconds left starts over" with the real length.** Once
  the item is ready and the resume seek's target is within 10 seconds of the
  real end, seek to 0. It closes the last risk of S14. It edits
  `PodcastPlayer.swift`, so it follows S11.
- **L4. iOS 27's new interruption notices.** Apple says the old notification can
  miss its end event. Then `wantsToPlay` stays true while the player is paused.
  The app still shows "paused" and Play works, so the effect is small. The new
  names cannot be used while the build must compile with Xcode 26.
- **L5. History has no limit.** `modules/podcasts/episodeSql.ts:36-37` reads
  every listened episode: 15 ms at 3,000 rows and 310 ms at 40,000 in Node. Add
  a limit or pages only if History feels slow.
- **L6. Skip feeds that did not change.** Ask the server with `If-None-Match`
  and `If-Modified-Since` and do not parse an unchanged feed. A larger
  smoothness and battery gain than S13, but it changes the Swift fetch.
- **L7. A scrub on the lock screen while paused is saved late.** JavaScript
  saves on a change from playing to paused and on its own seeks
  (`modules/podcasts/playback.ts:195-215`, `:454-460`), not on a seek that Swift
  reports while paused. A force-quit right after loses that scrub.
- **L8. Up Next moves are by index.** `moveInUpNext(from:to:)`
  (`PodcastPlayer+UpNext.swift:75-78`) trusts the positions the app saw. A drag
  that lands in the same moment an episode ends and the queue shifts moves the
  wrong row. The window is tiny.
- **L9. End the background task inside its expiration handler.**
  `PodcastStreamDownload+Resume.swift:124-131` ends it one main-queue turn after
  the handler returns. Apple's page says the task must be ended and that the
  handler runs on the main thread. No failure was seen. Needs device (a crash
  log would show it).
- **L10. A second tap in the first moments of a new episode loads it twice**
  (`modules/podcasts/playback.ts:364`, `:438`). Harmless.
- **L11. Try again by itself when the network comes back after a failure.**
  After S11 one press of Play is enough. An automatic retry would need a rule
  for when to stop.
- **L12. "This episode is no longer in your library"**
  (`podcasts/PlayerQueue.tsx:121-131`). It was not determined whether an episode
  of a show that is not followed can be put in Up Next. If it can, "Play now" in
  the queue shows this alert for it.

**Not determined, because only a phone can say:** how long a resume seek on a
stream really waits on Mo's network (the size of F1), whether iOS ever revives a
failed item when Play is pressed (F2), whether a downloaded file keeps playing
after it is deleted, rotation and iPad layouts, CarPlay and AirPlay.
