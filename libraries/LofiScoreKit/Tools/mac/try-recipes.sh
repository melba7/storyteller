#!/bin/bash
# Compare ways of training the Fast engine's word-embedding model on Mo's Mac,
# with no Claude calls: every recipe is scored out of fold on every labelled
# book (Claude's labels, and "fits" on the plausible sets), then each
# candidate is trained on all books and checked against people's ratings
# (EmoBank's fiction sentences). Nothing is shipped: the results say whether
# a candidate meets the ship rule in Docs/MoodDetection.md.
#
#   cd "~/Storyteller Lofi/<clone>/libraries/LofiScoreKit"
#   Tools/mac/try-recipes.sh [--out DIR] [--repeats 3] [--recipes a,b,...] [--version 9]
#                            [--shipped LofiMusic/LofiMood-embed-....json]
#
# The shipped model is the one LofiMood-embed-*.json in LofiMusic; its recipe
# (read from the name, e.g. word-8-people-v0.5 -> people-v0.5) is the second
# baseline, since a new candidate has to beat what ships, not just word-2.
#
# Recipes are in Sources/LofiTrainCLI/Recipes.swift. The people recipes lean
# the moods towards how pleasant and energetic people rate a text, learned
# from EmoBank's NON-fiction sentences (`lofi-train people`); its fiction
# sentences stay the test. EmoBank must be unpacked in
# "~/Storyteller Lofi/external-data/emobank" (emobank.csv and meta.tsv).
# Writes only inside "~/Storyteller Lofi"; installs nothing; never pushes.
set -uo pipefail
# (macOS bash 3.2: an empty array is expanded as ${a[@]+"${a[@]}"} under set -u.)

ROOT="$HOME/Storyteller Lofi"
PKG="$(cd "$(dirname "$0")/../.." && pwd)"
EMOBANK="$ROOT/external-data/emobank"
SHIPPED=""
OUT="$ROOT/lofi-mood-eval-results/$(date +%Y-%m-%d-%H%M)-recipes"
REPEATS=3
RECIPES=""
VERSION=9
while [ $# -gt 0 ]; do
  case "$1" in
    --out) OUT="$2"; shift 2 ;;
    --repeats) REPEATS="$2"; shift 2 ;;
    --recipes) RECIPES="$2"; shift 2 ;;
    --shipped) SHIPPED="$2"; shift 2 ;;
    --version) VERSION="$2"; shift 2 ;;
    *) echo "unknown option $1"; exit 2 ;;
  esac
done
case "$PKG" in "$ROOT"/*) ;; *) echo "Run this from a clone inside ~/Storyteller Lofi (found $PKG)."; exit 2 ;; esac
case "$OUT" in "$ROOT"/*) ;; *) echo "--out must be inside ~/Storyteller Lofi"; exit 2 ;; esac
if [ -z "$SHIPPED" ]; then
  # The one model in LofiMusic (the app loads whichever is there).
  for f in "$ROOT"/LofiMusic/LofiMood-embed-*.json; do [ -s "$f" ] && SHIPPED="$f"; done
fi
# Its recipe, from the name: LofiMood-embed-word-8-people-v0.5.json -> people-v0.5;
# a plain LofiMood-embed-word-8.json was the word-2 settings.
SHIPPED_RECIPE=$(basename "${SHIPPED:-none}" .json | sed -E 's/^LofiMood-embed-word-[0-9]+-?//')
[ -n "$SHIPPED_RECIPE" ] && [ "$SHIPPED_RECIPE" != none ] || SHIPPED_RECIPE=word2-settings

mkdir -p "$OUT/emobank"
exec > >(tee "$OUT/run.log") 2>&1
cd "$PKG"
B=.build/release
W=Tools/data/work
L=Tools/data/labels
STEP=0
step() { STEP=$((STEP + 1)); echo; echo "== $STEP. $* ($(date +%H:%M:%S))"; }
die() { echo "STOPPED: $*"; echo "Log: $OUT/run.log"; exit 1; }

step "Build"
git log -1 --format='%h %s' 2>/dev/null || true
swift build -c release > "$OUT/build.log" 2>&1 || { grep -E "error" "$OUT/build.log"; die "release build failed (see build.log)"; }

step "Windows and labels"
mkdir -p "$W"
WINDOWS=()
for v in 1 2 3 4 5; do
  gz=Tools/data/eval/sample-v$v.jsonl.gz
  [ -s "$gz" ] || continue
  f="$W/sample$v.jsonl"; [ "$v" = 1 ] && f="$W/sample.jsonl"
  [ -s "$f" ] && [ "$f" -nt "$gz" ] || gunzip -c "$gz" > "$f"
  WINDOWS+=(--windows "$f")
done
LABELS=(--labels "$L/claude-v1.jsonl" --labels "$L/claude-v2.jsonl")
for f in "$L/claude-g2-test.jsonl" "$L/claude-g2-train.jsonl" "$L/claude-g2-v3.jsonl" "$L/claude-g2-v4.jsonl" "$L/claude-g2-v5.jsonl"; do
  [ -s "$f" ] && LABELS+=(--labels "$f")
done
echo "${WINDOWS[*]}" | tr ' ' '\n' | grep -v -- --windows
$B/lofi-train export "${WINDOWS[@]}" --split "$L/split.json" --balance --validation-books 3 "${LABELS[@]}" || die "export failed"

# Books from before the newest batch, for the "-old" recipe: what did it add?
OLDEST_NEW=4; [ -s Tools/data/eval/sample-v5.jsonl.gz ] && OLDEST_NEW=5
OLD_FILES=()
for v in $(seq 1 $((OLDEST_NEW - 1))); do
  f="$W/sample$v.jsonl"; [ "$v" = 1 ] && f="$W/sample.jsonl"
  [ -s "$f" ] && OLD_FILES+=("$f")
done
python3 -I -c 'import json,sys; print("\n".join(sorted({json.loads(l)["book"] for p in sys.argv[1:] for l in open(p)})))' \
  "${OLD_FILES[@]}" > "$W/old-books.txt"
echo "old books (samples before v$OLDEST_NEW): $(wc -l < "$W/old-books.txt")"
SETS=(--alternatives "$L/claude-g2-test-sets.jsonl")
SETS_PY=(--sets "$L/claude-g2-test-sets.jsonl")
if [ -s "$L/claude-g2-v5.jsonl" ] && grep -q '"accept"' "$L/claude-g2-v5.jsonl"; then
  SETS+=(--alternatives "$L/claude-g2-v5.jsonl")
  SETS_PY+=(--sets "$L/claude-g2-v5.jsonl")
fi

echo "shipped model: ${SHIPPED:-none} (recipe $SHIPPED_RECIPE)"

step "word-$VERSION: the word-2 settings on every labelled book"
# Also computes the word features of any new windows (cached in $W/train).
$B/lofi-train embed --kinds word --recipe word2-settings --all --version "$VERSION" 2> "$OUT/embed-$VERSION.log" || { tail -5 "$OUT/embed-$VERSION.log"; die "embed failed"; }
grep -A4 "^summary" "$OUT/embed-$VERSION.log"

step "People's ratings: how pleasant and energetic (EmoBank non-fiction)"
PEOPLE=()
if [ -s "$EMOBANK/emobank.csv" ] && [ -s "$EMOBANK/meta.tsv" ]; then
  python3 -I Tools/eval/emobank.py people "$EMOBANK" > "$W/emobank-people.jsonl"
  if $B/lofi-train people --in "$W/emobank-people.jsonl" --out "$W/people-word.json" 2> "$OUT/people.log"; then
    grep -v "l2=" "$OUT/people.log"
    PEOPLE=(--people "$W/people-word.json")
  else
    tail -3 "$OUT/people.log"
  fi
  [ -s "$W/emobank-windows.jsonl" ] || python3 -I Tools/eval/emobank.py windows "$EMOBANK" > "$W/emobank-windows.jsonl"
else
  echo "no EmoBank in $EMOBANK: the people recipes and the people's-ratings check are skipped"
fi

step "All-books comparison ($REPEATS repeats of 10 folds)"
RECIPE_ARGS=()
[ -n "$RECIPES" ] && RECIPE_ARGS=(--recipes "$RECIPES")
$B/lofi-train oof --kind word --folds 10 --repeats "$REPEATS" --old-books "$W/old-books.txt" "${SETS[@]}" ${PEOPLE[@]+"${PEOPLE[@]}"} \
  ${RECIPE_ARGS[@]+"${RECIPE_ARGS[@]}"} --out "$OUT/oof-word.jsonl" 2> "$OUT/oof.log" || { tail -5 "$OUT/oof.log"; die "oof failed"; }
grep -E "^recipes:|^alternatives:" "$OUT/oof.log"
python3 -I Tools/eval/oof_compare.py "$OUT/oof-word.jsonl" "${SETS_PY[@]}" | tee "$OUT/oof-compare.txt"
if [ "$SHIPPED_RECIPE" != word2-settings ] && grep -q "\"recipe\": *\"$SHIPPED_RECIPE\"" "$OUT/oof-word.jsonl"; then
  echo; echo "-- against the shipped recipe ($SHIPPED_RECIPE) --"
  python3 -I Tools/eval/oof_compare.py "$OUT/oof-word.jsonl" --baseline "$SHIPPED_RECIPE" "${SETS_PY[@]}" | tee "$OUT/oof-compare-vs-shipped.txt"
fi

step "Candidates trained on every book"
CANDIDATES=("Models/LofiMood-embed-word-$VERSION.json")
for r in $(python3 -I -c 'import json,sys; print(" ".join(sorted({json.loads(l)["recipe"] for l in open(sys.argv[1])})))' "$OUT/oof-word.jsonl"); do
  case "$r" in word2-settings|*-old|nested-exact) continue ;; esac
  case "$r" in people-*) [ ${#PEOPLE[@]} -gt 0 ] || continue ;; esac
  if $B/lofi-train embed --kinds word --recipe "$r" --all --version "$VERSION-$r" "${SETS[@]}" ${PEOPLE[@]+"${PEOPLE[@]}"} 2> "$OUT/embed-$VERSION-$r.log"; then
    CANDIDATES+=("Models/LofiMood-embed-word-$VERSION-$r.json")
    echo "trained $r"
  else
    tail -2 "$OUT/embed-$VERSION-$r.log"
  fi
done
cp "${CANDIDATES[@]}" "$OUT/" 2>/dev/null || true

if [ -s "$W/emobank-windows.jsonl" ]; then
  step "People's ratings check (EmoBank fiction): shipped model first"
  READINGS=()
  if [ -s "$SHIPPED" ]; then
    $B/lofi-eval run --engine "embed:$SHIPPED" --in "$W/emobank-windows.jsonl" --out "$OUT/emobank/shipped.jsonl" 2>/dev/null \
      && READINGS+=("$OUT/emobank/shipped.jsonl")
  else
    echo "no shipped model at $SHIPPED"
  fi
  for m in "${CANDIDATES[@]}"; do
    k=$(basename "$m" .json); k=${k#LofiMood-embed-}
    $B/lofi-eval run --engine "embed:$m" --in "$W/emobank-windows.jsonl" --out "$OUT/emobank/$k.jsonl" 2>/dev/null \
      && READINGS+=("$OUT/emobank/$k.jsonl")
  done
  [ ${#READINGS[@]} -gt 0 ] && python3 -I Tools/eval/emobank.py score "$EMOBANK" "${READINGS[@]}" | tee "$OUT/emobank-score.txt"
fi

step "Done"
echo "Results: $OUT (oof-compare.txt, emobank-score.txt, candidate models). Nothing was shipped."
