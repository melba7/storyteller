#!/bin/bash
# One command for Mo's Mac: build and test LofiScoreKit, retrain the Fast
# engine on the newest labels, score it on the 320 held-out windows, and, only
# if "~/Storyteller Lofi/.anthropic-key" exists, score Claude too under a hard
# spending cap (default $6 at list prices).
#
#   cd "~/Storyteller Lofi/<clone>/libraries/LofiScoreKit"
#   Tools/mac/run-mood-eval.sh [--cap DOLLARS] [--skip-claude] [--out DIR]
#
# Everything it writes stays inside "~/Storyteller Lofi": build products and
# Tools/data/work in this package, results in
# "~/Storyteller Lofi/lofi-mood-eval-results/<date>/" (or --out). It installs
# nothing, needs no sudo, never pushes, and never prints the API key: it only
# passes the key file's path to lofi-eval.
set -uo pipefail

ROOT="$HOME/Storyteller Lofi"
KEY_FILE="$ROOT/.anthropic-key"
PKG="$(cd "$(dirname "$0")/../.." && pwd)"
CAP=6
SKIP_CLAUDE=0
OUT="$ROOT/lofi-mood-eval-results/$(date +%Y-%m-%d-%H%M)"
while [ $# -gt 0 ]; do
  case "$1" in
    --cap) CAP="$2"; shift 2 ;;
    --skip-claude) SKIP_CLAUDE=1; shift ;;
    --out) OUT="$2"; shift 2 ;;
    *) echo "unknown option $1"; exit 2 ;;
  esac
done
case "$PKG" in
  "$ROOT"/*) ;;
  *) echo "Run this from a clone inside ~/Storyteller Lofi (found $PKG)."; exit 2 ;;
esac
case "$OUT" in
  "$ROOT"/*) ;;
  *) echo "--out must be inside ~/Storyteller Lofi"; exit 2 ;;
esac

mkdir -p "$OUT/readings"
exec > >(tee "$OUT/run.log") 2>&1
cd "$PKG"
B=.build/release
W=Tools/data/work
L=Tools/data/labels
STEP=0
step() { STEP=$((STEP + 1)); echo; echo "== $STEP. $* ($(date +%H:%M:%S))"; }
die() { echo "STOPPED: $*"; echo "Log: $OUT/run.log"; exit 1; }

step "Toolchain"
xcrun swift --version || die "Swift is missing; open Xcode once to finish installing it"
git log -1 --format='%h %s' 2>/dev/null || true

step "Build and test"
swift build -c release > "$OUT/build.log" 2>&1 || { grep -E "error" "$OUT/build.log"; die "release build failed (see build.log)"; }
grep -E "warning: " "$OUT/build.log" | grep -v "Package.resolved" | sort -u || true
swift test > "$OUT/test.log" 2>&1
grep -E "error:|✘|Test run with" "$OUT/test.log"
grep -q "✘\|error:" "$OUT/test.log" && die "a test failed or did not compile (see test.log)"
grep -q "Test run with" "$OUT/test.log" || die "tests did not run (see test.log)"

step "Windows"
mkdir -p "$W"
[ -s "$W/sample.jsonl" ] || gunzip -c Tools/data/eval/sample-v1.jsonl.gz > "$W/sample.jsonl"
[ -s "$W/sample2.jsonl" ] || gunzip -c Tools/data/eval/sample-v2.jsonl.gz > "$W/sample2.jsonl"
[ -s "$W/sample3.jsonl" ] || gunzip -c Tools/data/eval/sample-v3.jsonl.gz > "$W/sample3.jsonl"
wc -l "$W/sample.jsonl" "$W/sample2.jsonl" "$W/sample3.jsonl"

step "Fast engine: export and train maxent v4 on the newest labels"
# Later label files win: v1 and v2 are the eight-mood labels, the g2 files
# carry them over to the eleven moods (guidelines v2), and claude-g2-v3 labels
# the extra training windows picked for the rarer moods.
LABELS=(--labels "$L/claude-v1.jsonl" --labels "$L/claude-v2.jsonl")
for f in "$L/claude-g2-test.jsonl" "$L/claude-g2-train.jsonl" "$L/claude-g2-v3.jsonl"; do
  [ -s "$f" ] && LABELS+=(--labels "$f")
done
$B/lofi-train export --windows "$W/sample.jsonl" --windows "$W/sample2.jsonl" --windows "$W/sample3.jsonl" \
  --split "$L/split.json" --balance --validation-books 3 "${LABELS[@]}" || die "export failed"
$B/lofi-train train --algorithm maxent --version 4 || die "training failed"
cp Models/LofiMood-maxent-4.mlmodel* "$OUT/" 2>/dev/null || true
cp Models/LofiMood-maxent-4.report.json "$OUT/" 2>/dev/null || true

step "Fast engine: Apple's on-device embeddings with a trained softmax head"
# Settings (and how much the earlier words count) are chosen by 5-fold
# cross-validation over the 26 training books; the summary's "test" is the
# 320 held-out windows, and the learning curve shows whether more labelled
# windows would help. The contextual kind is skipped (not downloaded) if its
# assets are not already on this Mac.
$B/lofi-train embed --kinds word,contextual,word+contextual --version 2 --curve 2> "$OUT/embed.log"
grep -A30 "^summary" "$OUT/embed.log" || tail -30 "$OUT/embed.log"
cp Models/LofiMood-embed-*-2.report.json "$OUT/" 2>/dev/null || true

step "Fast engine and baselines on the 320 held-out windows"
T="$W/train/test-windows.jsonl"
$B/lofi-eval run --engine fast:Models/LofiMood-maxent-4.mlmodel --in "$T" --out "$OUT/readings/fast-maxent-4.jsonl"
[ -s Models/LofiMood-maxent-3.mlmodel ] && \
  $B/lofi-eval run --engine fast:Models/LofiMood-maxent-3.mlmodel --in "$T" --out "$OUT/readings/fast-maxent-3.jsonl"
$B/lofi-eval run --engine lexicon --in "$T" --out "$OUT/readings/lexicon.jsonl"
for m in Models/LofiMood-embed-*-2.json; do
  [ -s "$m" ] || continue
  k=$(basename "$m" .json)
  $B/lofi-eval run --engine "embed:$m" --in "$T" --out "$OUT/readings/fast-${k#LofiMood-}.jsonl"
done
[ -s "$W/train/test.masked.jsonl" ] || python3 -I Tools/eval/mask_names.py "$T" > "$W/train/test.masked.jsonl"

SPENT=0
spent_in() { grep -oE 'about \$[0-9.]+ at' "$1" | tail -1 | sed -E 's/about \$([0-9.]+) at/\1/' ; }
claude_run() {  # claude_run SLICE NAME lofi-eval-args...
  local slice="$1" name="$2"; shift 2
  local left; left=$(python3 -c "print(round(max(0.0, min($slice, $CAP - $SPENT)), 2))")
  if python3 -c "import sys; sys.exit(0 if $left >= 0.05 else 1)"; then
    echo "-- $name (up to \$$left; \$$SPENT of \$$CAP spent so far)"
    $B/lofi-eval "$@" --max-dollars "$left" 2> "$OUT/$name.log"
    local status=$?
    cat "$OUT/$name.log"
    local cost; cost=$(spent_in "$OUT/$name.log")
    [ -n "$cost" ] && SPENT=$(python3 -c "print(round($SPENT + $cost, 3))")
    # A run where every request failed (a bad key, no credit, no network)
    # stops everything: the error text comes from the API, never the key.
    if grep -qE ": 0 readings, [1-9][0-9]* failures|0 scored, [1-9][0-9]* failed" "$OUT/$name.log"; then
      local out=""
      local prev=""
      for a in "$@"; do [ "$prev" = "--out" ] && out="$a"; prev="$a"; done
      [ -n "$out" ] && grep -m1 -oE '"error":"[^"]{0,300}' "$out" 2>/dev/null
      grep -m1 "failed " "$OUT/$name.log"
      die "every Claude request failed in $name; fix the key or account, then run again"
    fi
    return $status
  else
    echo "-- $name skipped: the \$$CAP cap is reached (\$$SPENT spent)"
  fi
}

if [ "$SKIP_CLAUDE" = 1 ]; then
  step "Claude: skipped (--skip-claude)"
elif [ ! -s "$KEY_FILE" ]; then
  step "Claude: skipped, no key file at ~/Storyteller Lofi/.anthropic-key"
else
  step "Claude on the held-out windows, at most \$$CAP in total"
  export ANTHROPIC_API_KEY_FILE="$KEY_FILE"
  $B/lofi-eval engines 2>&1 | grep -i claude
  # Cheapest first, so a bad key or a billing problem costs cents.
  claude_run 0.30 claude-haiku run --engine claude:haiku-5-5 --in "$T" --out "$OUT/readings/claude-haiku.jsonl" --concurrency 4
  claude_run 3.60 claude-opus run --engine claude --in "$T" --out "$OUT/readings/claude-opus.jsonl" --concurrency 4
  claude_run 0.30 claude-haiku-masked run --engine claude:haiku-5-5 --in "$W/train/test.masked.jsonl" --out "$OUT/readings/claude-haiku.masked.jsonl" --concurrency 4
  BOOK=Tools/data/books/epub/a-christmas-carol
  if [ -d "$BOOK" ]; then
    # A whole mood track with change refinement, to see real flip rates and cost.
    claude_run 0.25 claude-haiku-track track "$BOOK" --engine claude:haiku-5-5 --out "$OUT/a-christmas-carol.haiku.track.json" --concurrency 4
    [ -s "$OUT/a-christmas-carol.haiku.track.json" ] && $B/lofi-eval simulate "$BOOK" --engine lexicon \
      --track "$OUT/a-christmas-carol.haiku.track.json" --out "$OUT/a-christmas-carol.simulate.jsonl" 2>&1 | tail -2
  fi
  claude_run 1.50 claude-sonnet run --engine claude:sonnet-5-5 --in "$T" --out "$OUT/readings/claude-sonnet.jsonl" --concurrency 4
  echo "Claude total: about \$$SPENT at list prices (cap \$$CAP)"
fi

step "Scores against the eleven-mood labels"
GOLD="$L/claude-g2-test.jsonl"
[ -s "$L/mo-gold.jsonl" ] && GOLD="$L/mo-gold.jsonl"
echo "labels: $GOLD"
PLAIN=()
for f in "$OUT"/readings/*.jsonl; do
  case "$f" in *.masked.jsonl) ;; *) PLAIN+=("$f") ;; esac
done
python3 -I Tools/eval/score.py --windows "$T" --labels "$GOLD" --confusion "${PLAIN[@]}" | tee "$OUT/scores.txt"
if [ -s "$OUT/readings/claude-haiku.masked.jsonl" ]; then
  python3 -I Tools/eval/score.py --windows "$T" --masked-pair "$OUT/readings/claude-haiku.jsonl" "$OUT/readings/claude-haiku.masked.jsonl" | tee -a "$OUT/scores.txt"
fi

step "Done"
echo "Results: $OUT"
