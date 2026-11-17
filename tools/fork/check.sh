#!/usr/bin/env bash
# The fork's one check command: fork rules, tool tests, typecheck, lint, format,
# mobile tests, the Apple Podcasts export tests (python3) and the Swift tests of LofiScoreKit and
# PodcastKit. Prints only failures and a summary.
# The iOS simulator build runs only in Fork CI (it needs a Mac): push a branch for it.
# Usage: tools/fork/check.sh [--no-swift]
set -u
cd "$(dirname "$0")/../.."
export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
export COREPACK_NPM_REGISTRY="${COREPACK_NPM_REGISTRY:-https://registry.npmjs.org}"
LOG="$(mktemp -d)"
failed=()
passed=0

step() { # name, command...
  local name="$1"; shift
  if "$@" >"$LOG/$name.log" 2>&1; then
    passed=$((passed + 1))
  else
    failed+=("$name")
    echo "✗ $name"
    tail -n 25 "$LOG/$name.log" | sed 's/^/    /'
  fi
}

FORK_JS=(applications/mobile/lofi applications/mobile/modules/lofi-score
  applications/mobile/modules/podcasts applications/mobile/podcasts
  "applications/mobile/app/(root)/podcasts" tools/fork)
FORMAT=(FORK.md CLAUDE.md docs .github/workflows tools/fork
  applications/mobile/fork.config.ts applications/mobile/app.config.ts
  applications/mobile/lofi applications/mobile/modules/lofi-score
  applications/mobile/modules/podcasts applications/mobile/podcasts
  "applications/mobile/app/(root)/podcasts" libraries/PodcastKit)

[ -d node_modules ] || step install yarn install --immutable --mode=skip-build
step fork-rules node tools/fork/check-fork.mjs
step tool-tests node --test 'tools/fork/*.test.mjs'
step typecheck yarn tsc --build applications/mobile
step lint yarn oxlint "${FORK_JS[@]}"
step format yarn oxfmt --check "${FORMAT[@]}"
step mobile-tests yarn test:mobile
step apple-podcasts-tests python3 -m unittest discover -s libraries/PodcastKit/Tools/mac

if [ "${1:-}" != "--no-swift" ]; then
  if command -v swift >/dev/null 2>&1; then
    step swift-tests bash -c 'cd libraries/LofiScoreKit && swift test'
    step podcastkit-tests bash -c 'cd libraries/PodcastKit && swift test'
  elif command -v docker >/dev/null 2>&1; then
    step swift-tests docker run --rm -v "$PWD/libraries/LofiScoreKit":/src \
      -v "${CHECK_VOLUME_PREFIX:-}lofi-build":/src/.build -w /src swift:6.2 swift test
    step podcastkit-tests docker run --rm -v "$PWD/libraries/PodcastKit":/src \
      -v "${CHECK_VOLUME_PREFIX:-}podcastkit-build":/src/.build -w /src swift:6.2 swift test
  else
    echo "– swift-tests skipped (no swift or docker)"
  fi
fi

if [ ${#failed[@]} -eq 0 ]; then
  echo "check: all $passed steps passed"
else
  echo "check: ${#failed[@]} failed (${failed[*]}), $passed passed. Logs: $LOG"
  exit 1
fi
