# Lessons

One line per lesson.

- Cloud yarn: set `COREPACK_NPM_REGISTRY=https://registry.npmjs.org` or corepack
  cannot fetch yarn (check.sh does this).
- Fork CI does not lint, so lint errors in fork code went unseen; run `tools/fork/check.sh` (it lints) before pushing.
