#!/usr/bin/env bash
# The fork's one check command: fork rules, tool tests, typecheck, lint, format,
# mobile tests and LofiScoreKit's Swift tests. Prints only failures and a summary.
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

FORK_JS=(applications/mobile/lofi applications/mobile/modules/lofi-score tools/fork)
FORMAT=(FORK.md CLAUDE.md docs .github/workflows tools/fork
  applications/mobile/fork.config.ts applications/mobile/app.config.ts
  applications/mobile/lofi applications/mobile/modules/lofi-score)

[ -d node_modules ] || step install yarn install --immutable --mode=skip-build
step fork-rules node tools/fork/check-fork.mjs
step tool-tests node --test 'tools/fork/*.test.mjs'
step typecheck yarn tsc --build applications/mobile
step lint yarn oxlint "${FORK_JS[@]}"
step format yarn oxfmt --check "${FORMAT[@]}"
step mobile-tests yarn test:mobile

if [ "${1:-}" != "--no-swift" ]; then
  if command -v swift >/dev/null 2>&1; then
    step swift-tests bash -c 'cd libraries/LofiScoreKit && swift test'
  elif command -v docker >/dev/null 2>&1; then
    step swift-tests docker run --rm -v "$PWD/libraries/LofiScoreKit":/src \
      -v lofi-build:/src/.build -w /src swift:6.2 swift test
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
