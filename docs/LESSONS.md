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
