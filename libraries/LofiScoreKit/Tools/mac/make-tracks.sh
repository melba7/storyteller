#!/bin/bash
# Score Storyteller read-aloud books with Claude into mood tracks, once each.
# Run on Mo's Mac after Tools/mac/run-mood-eval.sh has shown which model is
# worth it.
#
#   cd "~/Storyteller Lofi/<clone>/libraries/LofiScoreKit"
#   Tools/mac/make-tracks.sh [--via plan|api] [--cap DOLLARS] [--engine claude|claude:sonnet-5-5|claude:haiku-5-5] [--dry-run] BOOK.epub|EPUB-DIR ...
#
# --via plan (the default) runs every request through Claude Code (`claude -p`)
# on the Claude subscription it is signed in with: no API key and no money,
# but it uses the plan's usage limits. Sign Claude Code in once first: run
# `claude` in Terminal and log in. --via api uses the Anthropic API with the
# key file "~/Storyteller Lofi/.anthropic-key" and needs --cap. With the plan,
# --cap is optional and limits usage measured at API list prices.
#
# --dry-run prints each book's entries, probes and estimated cost per model
# and spends nothing. Otherwise each book's track goes to
# "~/Storyteller Lofi/tracks/<book>.track.json"; a run stopped by the cap, a
# network error or Ctrl-C resumes where it stopped when run again. EPUB files
# are unpacked under "~/Storyteller Lofi/tracks/books/". The API key is never
# printed.
#
# Use the read-aloud EPUBs as Storyteller serves them (the synced book the
# phone downloads): the app matches a track to its book by the digests of its
# first sentences, so the text must be the same. To get tracks onto the
# phone, put the tracks folder inside the music folder before importing it
# in the app; the import picks up every *.track.json in it.
set -uo pipefail

ROOT="$HOME/Storyteller Lofi"
KEY_FILE="$ROOT/.anthropic-key"
PKG="$(cd "$(dirname "$0")/../.." && pwd)"
TRACKS="$ROOT/tracks"
CAP=""
ENGINE=claude
VIA=plan
DRY=0
BOOKS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --cap) CAP="$2"; shift 2 ;;
    --engine) ENGINE="$2"; shift 2 ;;
    --via) VIA="$2"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    -*) echo "unknown option $1"; exit 2 ;;
    *) BOOKS+=("$1"); shift ;;
  esac
done
[ ${#BOOKS[@]} -gt 0 ] || { echo "give one or more read-aloud EPUB files or unpacked EPUB folders"; exit 2; }
case "$VIA" in plan|api) ;; *) echo "--via must be plan or api"; exit 2 ;; esac
if [ "$DRY" = 0 ] && [ "$VIA" = api ]; then
  [ -n "$CAP" ] || { echo "give --cap DOLLARS (the most this run may spend, at list prices)"; exit 2; }
  [ -s "$KEY_FILE" ] || { echo "no key file at ~/Storyteller Lofi/.anthropic-key"; exit 2; }
fi
case "$PKG" in "$ROOT"/*) ;; *) echo "Run this from a clone inside ~/Storyteller Lofi."; exit 2 ;; esac

cd "$PKG"
B=.build/release
[ -x "$B/lofi-eval" ] || swift build -c release --product lofi-eval > /dev/null || { echo "build failed"; exit 1; }
mkdir -p "$TRACKS/books" "$TRACKS/logs"
export LOFI_CLAUDE_VIA="$VIA"
[ "$VIA" = api ] && export ANTHROPIC_API_KEY_FILE="$KEY_FILE"
SPENT=0
NOCAP=0
[ -n "$CAP" ] || { CAP=100000; NOCAP=1; }

for book in "${BOOKS[@]}"; do
  name="$(basename "$book")"
  name="${name%.epub}"
  dir="$book"
  if [ -f "$book" ]; then
    dir="$TRACKS/books/$name"
    if [ ! -d "$dir" ]; then
      mkdir -p "$dir" && (cd "$dir" && unzip -q "$book" 2>/dev/null || ditto -x -k "$book" .) || { echo "$name: could not unpack"; continue; }
    fi
  fi
  [ -d "$dir/META-INF" ] || { echo "$name: not an EPUB folder ($dir)"; continue; }

  if [ "$DRY" = 1 ]; then
    $B/lofi-eval track "$dir" --book "$name" --dry-run 2>&1
    continue
  fi
  left=$(python3 -c "print(round(max(0.0, $CAP - $SPENT), 2))")
  if python3 -c "import sys; sys.exit(0 if $left >= 0.05 else 1)"; then
    if [ "$NOCAP" = 1 ]; then echo "== $name (on the Claude plan, no cap)"; else echo "== $name (up to \$$left of the \$$CAP cap)"; fi
    log="$TRACKS/logs/$name.$(date +%Y%m%d-%H%M%S).log"
    $B/lofi-eval track "$dir" --book "$name" --engine "$ENGINE" --out "$TRACKS/$name.track.json" \
      --concurrency 4 --max-dollars "$left" 2> "$log"
    grep -v "^  [0-9]* scored$" "$log"
    cost=$(grep -oE 'about \$[0-9.]+ at' "$log" | tail -1 | sed -E 's/about \$([0-9.]+) at/\1/')
    [ -n "$cost" ] && SPENT=$(python3 -c "print(round($SPENT + $cost, 3))")
    if grep -qE ", 0 scored, [1-9][0-9]* failed" "$log"; then
      echo "Every request failed for $name; stopping (see $log)."
      break
    fi
  else
    echo "== $name skipped: the \$$CAP cap is reached"
  fi
done
[ "$DRY" = 1 ] || {
  if [ "$VIA" = plan ]; then echo "Used about \$$SPENT of plan usage, counted at API list prices. Tracks: $TRACKS"
  else echo "Spent about \$$SPENT at list prices. Tracks: $TRACKS"; fi
  echo "To use them on the phone, copy that folder into the music folder and import it in the app."
}
