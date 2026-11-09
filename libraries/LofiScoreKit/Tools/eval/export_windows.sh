#!/bin/bash
# Export causal windows for every readaloud book under Tools/data/books/epub.
#
#   Tools/eval/export_windows.sh [lofi-eval binary]
#
# Writes to Tools/data/work/:
#   playback.jsonl   the windows the app would read during straight playback
#   sample.jsonl     40 random sentences per book (for labelling and agreement)
set -euo pipefail
cd "$(dirname "$0")/../.."
EVAL=${1:-.build/release/lofi-eval}
OUT=Tools/data/work
mkdir -p "$OUT"
: > "$OUT/playback.jsonl"
: > "$OUT/sample.jsonl"
seed=1
for dir in Tools/data/books/epub/*/; do
  book=$(basename "$dir")
  "$EVAL" windows "$dir" --book "$book" --out "$OUT/$book.playback.jsonl"
  "$EVAL" windows "$dir" --book "$book" --sample "${SAMPLE_PER_BOOK:-40}" --seed "$seed" --min-sentence 3 --out "$OUT/$book.sample.jsonl"
  cat "$OUT/$book.playback.jsonl" >> "$OUT/playback.jsonl"
  cat "$OUT/$book.sample.jsonl" >> "$OUT/sample.jsonl"
  rm "$OUT/$book.playback.jsonl" "$OUT/$book.sample.jsonl"
  seed=$((seed + 1))
done
wc -l "$OUT/playback.jsonl" "$OUT/sample.jsonl"
