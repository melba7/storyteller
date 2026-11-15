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
