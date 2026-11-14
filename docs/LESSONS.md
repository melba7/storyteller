# Lessons

One line per lesson.

- Cloud yarn: set `COREPACK_NPM_REGISTRY=https://registry.npmjs.org` or corepack
  cannot fetch yarn (check.sh does this).
- Fork CI does not lint, so lint errors in fork code went unseen; run
  `tools/fork/check.sh` (it lints) before pushing.
- A scoring run that hits the Claude plan's usage limit skips those scenes,
  still exits 0 and writes the score, so the sync job counted the book as done
  with silent chapters; the job now keeps a `.retry` marker and later runs fill
  the gaps.
