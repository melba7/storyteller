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
