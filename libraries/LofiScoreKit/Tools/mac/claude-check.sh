#!/bin/bash
# Claude against the local model on the 320 held-out test passages, scored
# on the plausible sets ("fits") with by-book 95% intervals, window by window.
# Compares prompt versions too (v2, and v3 which describes the moment first
# and lists the other moods that also fit).
#
#   cd "~/Storyteller Lofi/<clone>/libraries/LofiScoreKit"
#   Tools/mac/claude-check.sh [--via plan|api] [--model sonnet-5-5|opus-5-5|haiku-5-5]
#                             [--prompts "2 3"] [--cap DOLLARS] [--out DIR]
#
# --via plan (the default) runs on the Claude subscription Claude Code is
# signed in with (run `claude` once in Terminal and log in); --via api uses
# "~/Storyteller Lofi/.anthropic-key". --cap limits each prompt's run,
# counted at API list prices (default 3), so a plan run cannot eat the whole
# usage allowance. Needs Tools/data/work/train/test-windows.jsonl, which
# run-mood-eval.sh writes, and the word-2 readings from an earlier run for
# the local model's side. Writes "~/Storyteller Lofi/lofi-mood-eval-results/<date>-claude/".
set -uo pipefail

ROOT="$HOME/Storyteller Lofi"
KEY_FILE="$ROOT/.anthropic-key"
PKG="$(cd "$(dirname "$0")/../.." && pwd)"
VIA=plan
MODEL=sonnet-5-5
PROMPTS="2 3"
CAP=3
OUT="$ROOT/lofi-mood-eval-results/$(date +%Y-%m-%d-%H%M)-claude"
while [ $# -gt 0 ]; do
  case "$1" in
    --via) VIA="$2"; shift 2 ;;
    --model) MODEL="$2"; shift 2 ;;
    --prompts) PROMPTS="$2"; shift 2 ;;
    --cap) CAP="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    *) echo "unknown option $1"; exit 2 ;;
  esac
done
case "$PKG" in "$ROOT"/*) ;; *) echo "Run this from a clone inside ~/Storyteller Lofi."; exit 2 ;; esac
case "$OUT" in "$ROOT"/*) ;; *) echo "--out must be inside ~/Storyteller Lofi"; exit 2 ;; esac
case "$VIA" in
  plan) ;;
  api) [ -s "$KEY_FILE" ] || { echo "no key file at ~/Storyteller Lofi/.anthropic-key"; exit 2; }
       export ANTHROPIC_API_KEY_FILE="$KEY_FILE" ;;
  *) echo "--via must be plan or api"; exit 2 ;;
esac
export LOFI_CLAUDE_VIA="$VIA"

cd "$PKG"
B=.build/release
L=Tools/data/labels
T=Tools/data/work/train/test-windows.jsonl
[ -s "$T" ] || { echo "no $T: run Tools/mac/run-mood-eval.sh once first"; exit 2; }
mkdir -p "$OUT/readings"
exec > >(tee "$OUT/run.log") 2>&1
swift build -c release --product lofi-eval > "$OUT/build.log" 2>&1 || { grep error "$OUT/build.log"; echo "build failed"; exit 1; }
$B/lofi-eval engines 2>&1 | grep -i claude

# The local model's readings of the same windows, from the newest run that has them.
LOCAL=$(ls -t "$ROOT"/lofi-mood-eval-results/*/readings/fast-embed-word-2.jsonl 2>/dev/null | head -1)
[ -n "$LOCAL" ] && cp "$LOCAL" "$OUT/readings/" && echo "local model: $LOCAL"

# One passage first, so a missing sign-in or key stops here.
head -1 "$T" > "$OUT/one.jsonl"
if ! $B/lofi-eval run --engine "claude:$MODEL" --in "$OUT/one.jsonl" --out "$OUT/one.readings.jsonl" 2> "$OUT/one.log" \
   || grep -q '"error"' "$OUT/one.readings.jsonl"; then
  cat "$OUT/one.log"; grep -m1 -oE '"error":"[^"]{0,300}' "$OUT/one.readings.jsonl" 2>/dev/null
  echo "STOPPED: Claude did not answer. For --via plan, run \`claude\` in Terminal once and log in."
  exit 1
fi

FILES=()
[ -n "$LOCAL" ] && FILES+=("$OUT/readings/fast-embed-word-2.jsonl")
for p in $PROMPTS; do
  out="$OUT/readings/claude-$MODEL-p$p.jsonl"
  echo "-- Claude $MODEL, prompt v$p, 320 passages (cap \$$CAP at list prices)"
  LOFI_CLAUDE_PROMPT=$p $B/lofi-eval run --engine "claude:$MODEL" --in "$T" --out "$out" \
    --concurrency 3 --max-dollars "$CAP" 2> "$OUT/claude-p$p.log"
  tail -3 "$OUT/claude-p$p.log"
  FILES+=("$out")
done

echo
python3 -I Tools/eval/score.py --windows "$T" --labels "$L/claude-g2-test-sets.jsonl" --compare "${FILES[@]}" --confusion \
  | tee "$OUT/scores-sets.txt"
echo "Results: $OUT"
