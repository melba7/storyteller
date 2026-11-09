#!/bin/bash
# Export causal windows for every readaloud book under Tools/data/books/epub.
#
#   Tools/eval/export_windows.sh [lofi-eval binary]
#
# Writes to Tools/data/work/:
#   playback.jsonl         the windows the app would read during straight playback
#   sample.rebuilt.jsonl   40 random sentences per book, rebuilt from the EPUBs
#
# The labelled sample is Tools/data/eval/sample-v*.jsonl.gz and is never
# touched here: window ids only match the exact build they were labelled on,
# so compare sample.rebuilt.jsonl with the frozen file before trusting it.
set -euo pipefail
cd "$(dirname "$0")/../.."
EVAL=${1:-.build/release/lofi-eval}
case "$EVAL" in
  -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
esac
if [ ! -x "$EVAL" ]; then
  echo "export_windows.sh: $EVAL is not an executable lofi-eval (build it first)" >&2
  exit 1
fi
OUT=Tools/data/work
mkdir -p "$OUT"
: > "$OUT/playback.jsonl"
: > "$OUT/sample.rebuilt.jsonl"
seed=1
for dir in Tools/data/books/epub/*/; do
  book=$(basename "$dir")
  "$EVAL" windows "$dir" --book "$book" --out "$OUT/$book.playback.jsonl"
  "$EVAL" windows "$dir" --book "$book" --sample "${SAMPLE_PER_BOOK:-40}" --seed "$seed" --min-sentence 3 --out "$OUT/$book.sample.jsonl"
  cat "$OUT/$book.playback.jsonl" >> "$OUT/playback.jsonl"
  cat "$OUT/$book.sample.jsonl" >> "$OUT/sample.rebuilt.jsonl"
  rm "$OUT/$book.playback.jsonl" "$OUT/$book.sample.jsonl"
  seed=$((seed + 1))
done
wc -l "$OUT/playback.jsonl" "$OUT/sample.rebuilt.jsonl"
