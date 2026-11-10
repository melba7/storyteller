#!/bin/bash
# Claude against the local mood model, to choose how books get their Claude
# mood tracks (which model, which prompt). Two tests, window by window:
#
#  1. the 320 held-out test passages, scored on Claude's plausible sets
#     ("fits"), with by-book 95% intervals. These labels were made by Claude,
#     so they favour prompt v2, which is closest to how they were made.
#  2. EmoBank's 386 fiction sentences that people clearly rated pleasant or
#     unpleasant: how often the mood lands on the side people rated, with
#     by-story 95% intervals. This one does not rest on Claude at all.
#
#   cd "~/Storyteller Lofi/<clone>/libraries/LofiScoreKit"
#   Tools/mac/claude-check.sh [--via plan|api] [--runs "opus-5-5:2 opus-5-5:3 sonnet-5-5:2"]
#                             [--cap DOLLARS] [--no-emobank] [--out DIR]
#
# Each run is MODEL:PROMPT (prompt v2, or v3, which describes the moment
# first and lists the other moods that also fit); --model M --prompts "2 3"
# still work and mean the runs M:2 M:3. Make-tracks.sh uses opus-5-5 with
# prompt v2 unless told otherwise. The local side is every mood model in
# "~/Storyteller Lofi/LofiMusic" (the one the app uses now).
#
# --via plan (the default) runs on the Claude subscription Claude Code is
# signed in with (run `claude` once in Terminal and log in); --via api uses
# "~/Storyteller Lofi/.anthropic-key". --cap limits each run, counted at API
# list prices (default 6; a run reads 706 passages, about $4.50 with Opus and
# $2.30 with Sonnet), so a plan run cannot eat the whole usage allowance. A run
# where most requests fail (for example the plan's usage limit) stops the
# rest. Needs Tools/data/work/train/test-windows.jsonl, which run-mood-eval.sh
# writes, and EmoBank in "~/Storyteller Lofi/external-data/emobank" for test 2.
# Writes "~/Storyteller Lofi/lofi-mood-eval-results/<date>-claude/".
set -uo pipefail

ROOT="$HOME/Storyteller Lofi"
KEY_FILE="$ROOT/.anthropic-key"
EMOBANK="$ROOT/external-data/emobank"
PKG="$(cd "$(dirname "$0")/../.." && pwd)"
VIA=plan
RUNS="opus-5-5:2 opus-5-5:3 sonnet-5-5:2"
MODEL=""
PROMPTS="2 3"
CAP=6
DO_EMOBANK=1
OUT="$ROOT/lofi-mood-eval-results/$(date +%Y-%m-%d-%H%M)-claude"
while [ $# -gt 0 ]; do
  case "$1" in
    --via) VIA="$2"; shift 2 ;;
    --runs) RUNS="$2"; shift 2 ;;
    --model) MODEL="$2"; shift 2 ;;
    --prompts) PROMPTS="$2"; shift 2 ;;
    --cap) CAP="$2"; shift 2 ;;
    --no-emobank) DO_EMOBANK=0; shift ;;
    --out) OUT="$2"; shift 2 ;;
    *) echo "unknown option $1"; exit 2 ;;
  esac
done
if [ -n "$MODEL" ]; then
  RUNS=""
  for p in $PROMPTS; do RUNS="$RUNS $MODEL:$p"; done
fi
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
mkdir -p "$OUT/readings" "$OUT/emobank"
exec > >(tee "$OUT/run.log") 2>&1
swift build -c release --product lofi-eval > "$OUT/build.log" 2>&1 || { grep error "$OUT/build.log"; echo "build failed"; exit 1; }
$B/lofi-eval engines 2>&1 | grep -i claude

E=""
if [ "$DO_EMOBANK" = 1 ]; then
  if [ -s "$EMOBANK/emobank.csv" ] && [ -s "$EMOBANK/meta.tsv" ]; then
    E="$OUT/emobank/clear-windows.jsonl"
    python3 -I Tools/eval/emobank.py windows "$EMOBANK" --clear-only > "$E"
    echo "EmoBank: $(wc -l < "$E" | tr -d ' ') clearly rated sentences"
  else
    echo "EmoBank is not in $EMOBANK; skipping test 2."
  fi
fi

# The local side: every mood model in the music folder, on the same passages.
LOCAL=()
LOCAL_E=()
shopt -s nullglob
for m in "$ROOT"/LofiMusic/LofiMood-*.json; do
  name="$(basename "$m" .json)"
  case "$name" in LofiMood-lm-*) engine="lm:$m" ;; *) engine="embed:$m" ;; esac
  if $B/lofi-eval run --engine "$engine" --in "$T" --out "$OUT/readings/local-$name.jsonl" 2> "$OUT/local-$name.log"; then
    LOCAL+=("$OUT/readings/local-$name.jsonl")
    echo "local model: $name"
    if [ -n "$E" ] && $B/lofi-eval run --engine "$engine" --in "$E" --out "$OUT/emobank/local-$name.jsonl" 2>> "$OUT/local-$name.log"; then
      LOCAL_E+=("$OUT/emobank/local-$name.jsonl")
    fi
  else
    echo "could not read with $name (see $OUT/local-$name.log)"
  fi
done
shopt -u nullglob

# One passage first, so a missing sign-in or key stops here.
first="${RUNS# }"; first="${first%% *}"
head -1 "$T" > "$OUT/one.jsonl"
if ! $B/lofi-eval run --engine "claude:${first%%:*}" --in "$OUT/one.jsonl" --out "$OUT/one.readings.jsonl" 2> "$OUT/one.log" \
   || grep -q '"error"' "$OUT/one.readings.jsonl"; then
  cat "$OUT/one.log"; grep -m1 -oE '"error":"[^"]{0,300}' "$OUT/one.readings.jsonl" 2>/dev/null
  echo "STOPPED: Claude did not answer. For --via plan, run \`claude\` in Terminal once and log in."
  exit 1
fi

# Errors in a readings file, as a whole percentage of its lines.
failed_percent() {
  python3 -c '
import json, sys
rows = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
bad = sum(1 for r in rows if r.get("error") or r.get("bucket") is None)
print(round(100 * bad / max(1, len(rows))))' "$1" 2>/dev/null || echo 100
}

FILES=("${LOCAL[@]+"${LOCAL[@]}"}")
FILES_E=("${LOCAL_E[@]+"${LOCAL_E[@]}"}")
CAP_T=$(python3 -c "print(round($CAP * 320 / 706, 2))")
CAP_E=$(python3 -c "print(round($CAP * 386 / 706, 2))")
for run in $RUNS; do
  model="${run%%:*}"; p="${run##*:}"
  [ "$model" != "$run" ] || p=2
  out="$OUT/readings/claude-$model-p$p.jsonl"
  echo "-- Claude $model, prompt v$p: 320 test passages (cap \$$CAP_T at list prices)"
  LOFI_CLAUDE_PROMPT=$p $B/lofi-eval run --engine "claude:$model" --in "$T" --out "$out" \
    --concurrency 4 --max-dollars "$CAP_T" 2> "$OUT/claude-$model-p$p.log"
  tail -2 "$OUT/claude-$model-p$p.log"
  FILES+=("$out")
  bad=$(failed_percent "$out")
  if [ "$bad" -gt 30 ]; then
    echo "STOPPED: $bad% of this run's requests failed (usage limit?). See $OUT/claude-$model-p$p.log"
    break
  fi
  if [ -n "$E" ]; then
    oute="$OUT/emobank/claude-$model-p$p.jsonl"
    echo "-- Claude $model, prompt v$p: EmoBank (cap \$$CAP_E at list prices)"
    LOFI_CLAUDE_PROMPT=$p $B/lofi-eval run --engine "claude:$model" --in "$E" --out "$oute" \
      --concurrency 4 --max-dollars "$CAP_E" 2> "$OUT/claude-$model-p$p.emobank.log"
    tail -2 "$OUT/claude-$model-p$p.emobank.log"
    FILES_E+=("$oute")
    bad=$(failed_percent "$oute")
    if [ "$bad" -gt 30 ]; then
      echo "STOPPED: $bad% of this run's requests failed (usage limit?). See $OUT/claude-$model-p$p.emobank.log"
      break
    fi
  fi
done

echo
python3 -I Tools/eval/score.py --windows "$T" --labels "$L/claude-g2-test-sets.jsonl" --compare "${FILES[@]}" --confusion \
  > "$OUT/scores-sets.txt"
if [ -n "$E" ] && [ ${#FILES_E[@]} -gt 1 ]; then
  python3 -I Tools/eval/emobank.py score "$EMOBANK" "${FILES_E[@]}" > "$OUT/emobank-score.txt"
  cat "$OUT/emobank-score.txt"
fi
echo
sed -n '/^## Compared/,/^## Pairwise/p' "$OUT/scores-sets.txt" | grep -v '^## Pairwise'
echo "Results: $OUT (scores-sets.txt, emobank-score.txt)"
