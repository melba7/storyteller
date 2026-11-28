# Lessons

One line per lesson.

- Cloud yarn: set `COREPACK_NPM_REGISTRY=https://registry.npmjs.org` or corepack
  cannot fetch yarn (check.sh does this).
- Fork CI does not lint, so lint errors in fork code went unseen; run
  `tools/fork/check.sh` (it lints) before pushing.
- A picker that promises "this plays here" needs a test that asks the thing that
  plays: the sound check's stops are checked sentence by sentence against
  `AtmosphereDirector.target(at:)` (a chapter start dips the sounds until the
  new chapter's first scene, which reading the picker alone did not show).
- The follower treats a jump back of up to 8 sentences as a rewind, not a seek.
  Code that moves the narration itself must say so first
  (`NarrationFollower.expectJump`), or one-offs and scene changes behave as if
  nothing happened.
- A scoring run that hits the Claude plan's usage limit skips those scenes,
  still exits 0 and writes the score, so the sync job counted the book as done
  with silent chapters; the job now keeps a `.retry` marker and later runs fill
  the gaps.
- Keeping a squash-merged branch's old tip with `git merge -X ours` re-applied
  that tip's non-conflicting changes (P1b's mini players came back into P1c's
  screens). Use `git merge -s ours FETCH_HEAD`, which keeps the tree as it is,
  and check that `git diff HEAD^1 HEAD` is empty before pushing.
- A PodcastKit test class had a property named `hash`. It passed on Linux, but
  on macOS `XCTestCase` is an `NSObject`, so Fork CI failed to compile it. Don't
  give test classes properties that `NSObject` already has (`hash`,
  `description`, `name`).
- Expo hands every JavaScript number to Swift as a `Double`, also whole ones, so
  `values["x"] as? Int` on a `[String: Any]` from JavaScript is always nil and
  the playback settings fell back to their defaults. Read numbers from
  JavaScript as `Double` (or through a helper that takes both).
- Expo Router opens a stack on its first screen, and with no
  `unstable_settings.anchor` it orders static names shortest first. The shared
  "preview" screen in every Podcasts tab group sorted before "discover", so the
  Discover tab opened on an empty preview (Mo saw it on build 23.1). A tab whose
  home is not `index` needs an anchor; `tabStacks.test.ts` checks every tab.
- Run `yarn oxfmt` from the repository root on the changed paths. Run from
  another folder it formats the wrong files, and the format check fails (a
  builder lost a check run to it on 2026-11-17).
- In expo-router 58, options set with `<Stack.Screen options>` inside a page
  stay after that element unmounts (they go through `navigation.setOptions`),
  while `Stack.Title` and `Stack.Toolbar` are removed with it. Anything that
  changes while a screen is open (a title that appears on scroll) must use the
  composition components only.
- Column names found by other people's tools are not proof of what a column
  holds: Apple's library has `ZHASBEENPLAYED` but leaves it empty. Check a value
  against the real data (or say it is unchecked) before relying on it.
- A native large title shrinks, and the transparent bar blurs, only when the
  screen's first child is its scroll view. ScreenBar's comment said so, but
  every screen wrapped the list in a View anyway, and Mo saw titles over the
  text in 27.1. Return the list first and put the bar and overlays after it.
- `pb-safe` and a later `pb-N` on the same element fight; use `pb-safe-offset-N`
  for the inset plus a gap.
- Keep a round of Mo's fixes in one pull request and one TestFlight build. I
  planned the streaming ad skip for "after this round is on TestFlight", and Mo
  asked why it was split: add the bigger fix to the same pull request instead.
- Apple's App Transport Security keys cancel each other:
  `NSAllowsArbitraryLoads` is ignored when `NSAllowsArbitraryLoadsForMedia`,
  `...InWebContent` or `NSAllowsLocalNetworking` is set. Check the final plist,
  not one key.
- Run `yarn oxfmt` on directories before `check.sh`: on single files it can sort
  imports differently from the check.
- In `global.css`, an `@import` after other rules is an error ("@import rules
  must precede all rules"), so a theme that must override upstream values goes
  in a marked block appended at the end of the file (2026-11-17).
- With `withUniwind` missing, a third-party native view such as `GlassView`
  silently ignores `className`. Wrap it once (`withUniwind(GlassView)`) before
  styling it with classes (2026-11-17).
- An `@expo/ui` SF Symbol with no `color` is drawn in iOS's own label colour,
  not the theme's text colour, so it is wrong under a fixed Appearance. Pass the
  theme's colour (`useCSSVariable`) every time (2026-11-17).
- A restyle of a shared component reaches every screen that uses it: the Books
  look's wider `Button` padding wrapped the Podcasts swipe actions' labels.
  After merging such a change, check the other section's uses (2026-11-17).
- A worklet (gesture callback, `useAnimatedStyle`) may call only worklets: a
  helper imported from another file needs the `"worklet"` directive, or the call
  moves to the JS side with `scheduleOnRN`. Otherwise a release build crashes on
  touch (`SeekBar` and `barFraction`, 2026-11-18).
  `modules/podcasts/worklets.test.ts` now checks this.
- Moving Swift code into an extension file (`PodcastAdFinder+Queue.swift`)
  breaks any call to a `private` member of the main file, and only Mac CI
  compiles the iOS module. Grep the moved code for the main file's `private`
  members before pushing (2026-11-18, found by Fable's review).
- `SpeechAnalyzer.finalize(through:)` waits until the analyzer has consumed
  audio up to that time. Finalize through the audio really fed (the decoder and
  rate converter keep a few milliseconds back), and put a time limit on each
  step (2026-11-18).
- A rule that lowers an ad's confidence (N6: a sure ad with no line that sells
  becomes unsure) quietly breaks every older test whose fixture had no such
  line, and the tests that expect two ads can then pass for the wrong reason
  (unsure ads never merge). Give the fixtures a selling line and re-read each
  failing test before changing it (2026-11-18).
- Merge cherry-picks of parallel builders in the order the files depend on each
  other, and run the whole check on the main checkout: a worktree's typecheck
  always fails through its symlinks, so it hides real errors (2026-11-18).
- A flag that means "the first look is done" must be separate from "an ads file
  exists": a look that finds nothing saves no file (2026-11-18).
- In React Native, `flex-1` sets a flex basis of 0 and that wins over `width`:
  give a fixed column both `width` and `flexBasis` (2026-11-18, found by Opus).
- Read the whole of a reviewer-found list again after the fixes: a fix that
  changes a function's signature (`StartHold.wanted`, `sponsors`) needs every
  caller and test checked, because only Mac CI compiles the iOS module
  (2026-11-18).
- Only a Mac compiles `modules/podcasts/ios`. Before pushing, grep each new or
  changed file there for PodcastKit type names whose module it does not import:
  `AdHeadRules` without `import PodcastAds` broke the first archive of build
  31.1 (2026-11-18, found on Mo's Mac after GitHub's Macs were full).
- Apple's model errors change between iOS versions: classify an unknown error by
  type, case and a short word list instead of catching only the types we know,
  or one new error stops a whole pass (2026-11-18).
- Read the native sheet code before wiring navigation events: a cancelled swipe
  sends `gestureCancel`, not `transitionEnd` (2026-11-18, found by Sonnet and
  confirmed by Opus).
- `yarn oxfmt` on one file does not sort imports, but `check.sh` formats
  directories and does: run it on the directories (2026-11-18).
- A value that the native player reports before the audio loads (the feed's
  length) is a guess: a rule that compares the place with it, like "played",
  must not read a place past it as the end (2026-11-18, found by Opus).
- An agent's worktree starts from `origin/main`, not from the branch being
  worked on: every builder brief starts with `git merge --ff-only <branch>`, and
  its commits come back by cherry-pick (2026-11-22).
- Two tools that share a file must be tested against the same text: the Mac
  wrote shows as `feed` while the phone's reader needed `show` and `id`, and
  each side's own tests passed (2026-11-22, found before it shipped).
- The Mac's auto mode also refuses a script that fetches when it is started
  through the device shell. Leave a `.command` for Mo (2026-11-22).
- Two sides of one contract need one written rule before either is fixed: a
  removal by count, a carried-over switch and a span rule each had to change in
  Swift, TypeScript or Python at once, and the briefs carried the exact rule to
  every fixer (2026-11-22).
- A fixer told to make old tests pass can loosen the rule instead: check the fix
  against the finding, not against the tests. The promo rule came back accepting
  the same phrase twice as proof (2026-11-22).
- Fork CI runs on pull requests into main, pushes to main and by hand, not on a
  plain branch push: open the draft pull request early to get the iOS build, and
  put `[skip ci]` on a push that must not cancel a build that is running
  (2026-11-22).
- Matching a stored row by one value alone (an audio address, a count of lines)
  breaks on the odd feed or the odd moment: ask what else must be the same
  (2026-11-22).
- A launcher is only tested when every exit code of the tool it starts has been
  run through it: the gathering treated "size limit reached" as a failure and
  stopped before writing anything down on Mo's first real run (2026-11-22).
- Anything that must survive the next write cannot live only in a field the join
  rewrites: `AdJoin` drops an ad's `source`, so a "yes" kept only as a "tap" ad
  was lost at the next checkpoint and the question came back. Keep it where no
  join touches it, here inside the question itself (2026-11-23).
- A limit that drops pieces before they are counted lets the pieces through: a
  long replay broken into short ones passed both the length cap and the "mostly
  repeated" guard. Count everything first, then drop (2026-11-23).
- A new rule needs a test that fails without it: the checkers found guards,
  limits and a "never matches itself" rule that stayed green when removed. Prove
  each by deleting the rule in a copy (2026-11-23).
- Settings that act on an ad by its `source` must run before the join, on each
  finder's own list, or a joined ad has no source and skips without asking
  (2026-11-23).
- iOS files cannot be built in the cloud, but a harness that compiles the real
  files against the real PodcastKit with stubs for the app's other types finds
  most compile errors and logic slips before Fork CI (2026-11-23).
- Mo's plan allowance is shared by the cloud builders and the Mac's marking: a
  full builder fleet used the window and the marking stopped at once with 0
  episodes marked. Builders must also commit early, because a limit cut-off
  loses what is not committed (2026-11-23).
- A model file the phone refuses is silent: the scorecard just left the model
  out and every row looked weak. After a run, read the publish step's lines and
  check the scorecard has a "Plus the trained model" row before judging any
  finder. The trainer must also fix the bias at plain talk, or the many
  plain-word weights carry it and the bias ends up saying "ad" (2026-11-23).
- The Mac's test cannot see what the phone's own learners gain (one unseen
  episode per show), and the first rule switched them off for every show on 0 s
  found and 15 s cut. A finder that found nothing and cut almost nothing is not
  judged (2026-11-23).
- Measure each part of a round alone on its own branch before joining them. The
  rule that cut skips back to a remembered ad's edges looked good in the
  prototype and netted nothing when measured (6 fixed, 6 broken), and was worse
  with the phone's shorter memory (2026-11-23).
- A rule that moves a skip's border on the phone must be limited to what the
  scorecard measures. The first joint pull moved every ad on the phone (Apple's
  model, chapters, memory) while the scorecard only had the word finders' ads.
  And a limit by the finder's name switched the pull off altogether, because the
  older finders' ads carry no name: check what the data really holds before
  writing a rule on it (2026-11-23).
- Four Opus checks at extra effort beside the builders used up Mo's 5-hour
  allowance and stopped everything for 40 minutes. Run one or two agents at a
  time (2026-11-23).
- The cloud cannot start a launcher on Mo's Mac: Remote Control's own permission
  check refuses to start or stop processes, and a locked screen cannot be
  driven. Leave one double-clickable launcher that does every step in a row, and
  give a detached launcher `< /dev/null` so it does not wait at a "Press Return"
  prompt (2026-11-23).
- Builders must run the format check on every doc they touch
  (`yarn oxfmt --check` on `libraries/PodcastKit`); a merge of two branches that
  both edited the Mac tools README needs it again (2026-11-23).
- The trainer's built-in loop could not match the reference fit on version 2
  features, so a weakened test crept in. Keep the old path writing the old file
  and never loosen a test to fit a new path (2026-11-23).
- A remote session said the Mac's permission check had refused to start the
  TestFlight build, but the build had started and uploaded. Read the logs on the
  Mac before offering another way to start a job: a second start would have run
  two builds at once (2026-11-23).
- Apple's on-device model made the phone worse when the scorecard finally scored
  it (2026-11-24): never leave a finder on skip without its own scorecard row,
  and say which finders a number leaves out. I told Mo 64% before the Apple row
  was scored.
- Python tests need 15 GB free disk (teach_collect's keep-free default): they
  failed at 14 GB after Docker volumes piled up. Prune unused volumes before a
  full check (2026-11-24).
- Two builders that add a file with the same name to two branches make an
  add/add conflict at the merge: tell each builder its own test file names, and
  read the merged tests by hand (2026-11-24).
- A tool a builder changed in one branch (teach_publish.py's list of files)
  changes tests in another: after a merge, run the whole Python suite, not just
  the new files (2026-11-24).
- Docker run logs in the scratchpad lag: read the exit line, not the tail. A
  `for ... in infiniteSequence where cond` loop never ends: run swift test with
  a timeout (2026-11-24).
- A lock held around a job whose tools take the same lock themselves refuses
  them all, because flock belongs to each opened copy of the file: the nightly
  read-ahead would have done nothing every night and logged "skipped". Its shell
  test used stubs and missed it. `hold` now tells the tools it started by the
  environment (`TEACH_LOCK_HELD`), and a test runs the real tool under it. Test
  the real tool, not a stub, wherever a lock or a file handle crosses a process
  (2026-11-24).
- Marks that cost $90 had no backup until Mo asked twice; a step that spends
  money needs a backup of what it buys (2026-11-25).
- A cleanup that deletes audio was designed first as "delete what has a
  transcript and marks"; the independent check found that the ad sounds and the
  second-download comparison still learn from the audio, so deleting would have
  shrunk the library. Before deleting an input, list every step that reads it
  (2026-11-25).
- The sound bank was first tested with the audio file gone but the list entry
  intact; the cleanup sets `file` to null, and the sounds step skipped such
  entries. Test the exact state the deleting tool leaves behind (2026-11-25).
- A launcher's `read -p "message"` prints nothing when its input is not a
  terminal, so a test never saw the closing message. Print messages with `echo`
  and keep `read` for the Return key only (2026-11-25).
- A Swift error that reaches the phone's screen must be a `LocalizedError`: the
  app shows `localizedDescription`, so the sounds import showed "The operation
  couldn't be completed. (LofiScoreHost.SoundsFolderImport.ImportError error
  0.)" instead of its own sentence, which hid that the Atmosphere folder had
  been picked instead of LofiMusic (2026-11-26).
- Two builders each added a teaching file in their own worktree, and two tests
  that pin how many teaching files there are failed after the merge. Run the
  whole check right after merging parallel work, before anything is built on it
  (2026-11-26).
- The quick trial joined stretches only when they touch; the player and the
  scorer chain ads that lie within half a second. The real scorer passed one
  break fewer than the trial. A trial replays the bar with the player's own
  chain rule (2026-11-26).
- The opening lines passed their trial with a reach of 120 s, and one of the
  seven pulls on the shelf cut 83 s of show. A total hides that. Before a finder
  that moves a border ships, list each break it makes worse and how far it went
  (2026-11-27).
- A finder that only extends another finder's ad was undone together with that
  ad, and the Undo counted against the finder that was right. When a new finder
  chains its stretches to other ads, decide what an Undo of the chain takes back
  (2026-11-27).
- Two pushes to a pull request got no Fork CI run at all: the branch conflicted
  with main, where another pull request had appended a lesson at the end of this
  file too, and GitHub starts no pull request run while there is a conflict.
  When a push gets no run, look at whether the pull request can be merged first,
  and merge main into the branch (2026-11-27).
- The same gap came back a day later: the plan for the tap that carries over
  short holes said nothing about its Undo (it blamed both ads) or about what the
  listener keeps in the hole (a kind whose switch is off, what a trim cut off).
  The Opus check found both. A rule that makes a skip longer needs two answers
  in the plan before it is built: what its Undo takes back, and what in its way
  stops it (2026-11-27).
- On macOS a test class is an NSObject. A property named `hash` or a helper
  named `copy` in an XCTestCase subclass does not compile there (two failed CI
  builds), though Linux and Docker accept it. Name test helpers so that they
  cannot be NSObject's (2026-11-27).
- The first run of the scorecard row "Prepared copy" passed 159 of 222 breaks
  although its marks were the truth. The row had cut the marks to the length the
  feed states, which is shorter than the audio for 50 of 63 shelf episodes. A
  number that should be 100% by construction and is not is a bug to trace before
  it is reported, and a length comes from the audio, never from the feed
  (2026-11-28).
- The formatter reads two dollar amounts in one paragraph of Markdown as maths
  and breaks the lines around them. Write one of them in words (2026-11-27).
- The hourly preparing job would have done nothing on Mo's Mac: its download
  limit of 25 GB counted all the audio in the teaching folder, which already
  held 75 GB. Every test passed, because no test folder was that full. Before a
  job for the Mac is called ready, look at the Mac's real folders (sizes,
  counts, free space) and run the job's limits against those numbers
  (2026-11-28).
- The same job paid Claude in step 4 and found out in step 6 that it could not
  put the audio into iCloud. A job that spends money checks first, in the same
  run and with a real write, that its result can be delivered, and spends
  nothing when it cannot (2026-11-28).
