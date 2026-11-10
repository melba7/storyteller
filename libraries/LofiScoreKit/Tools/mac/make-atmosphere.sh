#!/bin/bash
# Score Storyteller read-aloud books with Claude into atmosphere tracks (which
# quiet sounds go under each scene), once each, under a total spending cap.
#
#   cd "~/Storyteller Lofi/<clone>/libraries/LofiScoreKit"
#   Tools/mac/make-atmosphere.sh [--via plan|api] [--cap DOLLARS] [--model claude-opus-5-5|claude-sonnet-5-5|claude-haiku-5-5]
#                                [--parallel N] [--dry-run] [--rescore] [--no-fetch] [--no-copy] BOOK.epub|EPUB-DIR ...
#
# --via works as in make-tracks.sh. plan (the default) runs every request
# through Claude Code (`claude -p`) on the Claude subscription it is signed in
# with: no API key and no money, but it uses the plan's usage limits; sign
# Claude Code in once first (run `claude` in Terminal and log in). api uses the
# Anthropic API with the key file "~/Storyteller Lofi/.anthropic-key" and
# needs --cap. With the plan, --cap is optional and limits usage measured at
# API list prices.
#
# --dry-run prints each book's entries and estimated cost per model and spends
# nothing. Otherwise each book's track goes to
# "~/Storyteller Lofi/tracks/<book>.atmosphere.json". When the mood track
# "<book>.track.json" is there too, the two are also combined into
# "<book>.score.json" (the file that can go inside the book). A run stopped by
# the cap, a network error or Ctrl-C resumes where it stopped when run again.
#
# Each book's first pass runs in order, because every request is told the
# places met so far (that is how a place keeps its sounds when the story comes
# back to it), so a long novel takes most of an hour. --parallel N scores N
# books at once; the cap is then split evenly between the books.
#
# Claude may use the more specific sounds in "~/Storyteller Lofi/Atmosphere/variants.json"
# (church bells, a waterfall, a cafe...) and may ask for new ones. After scoring,
# the script runs Tools/atmosphere/fetch_ambience.py to fetch recordings for any
# new ones (--no-fetch skips that; it needs ffmpeg), then copies the tracks and
# the Atmosphere folder into "~/Storyteller Lofi/LofiMusic" (--no-copy skips that),
# ready to import on the phone.
#
# The API key is never printed. Use the read-aloud EPUBs as Storyteller serves them: the app matches
# a track to its book by the digests of its first sentences. To get the tracks
# onto the phone, put the tracks folder inside the music folder before
# importing it in the app; the import picks up every *.atmosphere.json in it.
set -uo pipefail

ROOT="$HOME/Storyteller Lofi"
KEY_FILE="$ROOT/.anthropic-key"
PKG="$(cd "$(dirname "$0")/../.." && pwd)"
TRACKS="$ROOT/tracks"
CAP=""
MODEL=claude-opus-5-5
VIA=plan
PARALLEL=1
DRY=0
FETCH=1
COPY=1
RESCORE=0
BOOKS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --cap) CAP="$2"; shift 2 ;;
    --rescore) RESCORE=1; shift ;;
    --model) MODEL="$2"; shift 2 ;;
    --via) VIA="$2"; shift 2 ;;
    --parallel) PARALLEL="$2"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    --no-fetch) FETCH=0; shift ;;
    --no-copy) COPY=0; shift ;;
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
case "$PARALLEL" in ''|*[!0-9]*|0) echo "--parallel takes a whole number of books"; exit 2 ;; esac

cd "$PKG"
B=.build/release
# Always build: quick when nothing changed, and never an old binary after a git pull.
swift build -c release --product lofi-atmosphere > /dev/null || { echo "build failed"; exit 1; }
VARIANTS="$ROOT/Atmosphere/variants.json"
mkdir -p "$TRACKS/books" "$TRACKS/logs"
export LOFI_CLAUDE_VIA="$VIA"
[ "$VIA" = api ] && export ANTHROPIC_API_KEY_FILE="$KEY_FILE"

# Unpack the EPUB files; keep the folders.
DIRS=()
NAMES=()
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
  DIRS+=("$dir")
  NAMES+=("$name")
done
[ ${#DIRS[@]} -gt 0 ] || exit 1

if [ "$DRY" = 1 ]; then
  for i in "${!DIRS[@]}"; do
    $B/lofi-atmosphere track "${DIRS[$i]}" --book "${NAMES[$i]}" --dry-run --variants "$VARIANTS" 2>&1
  done
  exit 0
fi

EACH=""
if [ -n "$CAP" ]; then
  EACH=$(python3 -c "print(round($CAP / ${#DIRS[@]}, 2))")
  echo "Scoring ${#DIRS[@]} book(s) with $MODEL via the $VIA, up to \$$EACH each (\$$CAP in all at list prices), $PARALLEL at a time."
else
  echo "Scoring ${#DIRS[@]} book(s) with $MODEL via the $VIA, $PARALLEL at a time."
fi

score_one() {
  local dir="$1" name="$2" log="$3"
  local cap=()
  [ -n "$EACH" ] && cap=(--max-dollars "$EACH")
  if [ "$RESCORE" = 1 ]; then
    # A track from an older prompt or catalogue is kept aside, never overwritten.
    mkdir -p "$TRACKS/old"
    local stamp; stamp="$(date +%Y%m%d-%H%M%S)"
    for kind in atmosphere score; do
      [ -s "$TRACKS/$name.$kind.json" ] && mv "$TRACKS/$name.$kind.json" "$TRACKS/old/$name.$stamp.$kind.json"
    done
  fi
  "$B/lofi-atmosphere" track "$dir" --book "$name" --model "$MODEL" --variants "$VARIANTS" \
    --out "$TRACKS/$name.atmosphere.json" "${cap[@]+"${cap[@]}"}" 2> "$log"
  # One block per book, even when books finish together.
  local report
  report="== $name"$'\n'"$(grep -vE "^  [0-9]+ scored, now at" "$log")"
  if [ -s "$TRACKS/$name.track.json" ] && [ -s "$TRACKS/$name.atmosphere.json" ]; then
    report="$report"$'\n'"$("$B/lofi-atmosphere" score --mood "$TRACKS/$name.track.json" \
      --atmosphere "$TRACKS/$name.atmosphere.json" --out "$TRACKS/$name.score.json" 2>&1)"
  fi
  printf '%s\n' "$report"
}

# macOS's bash 3.2 has no "wait -n", so books go in batches of --parallel.
LOGS=()
stamp=$(date +%Y%m%d-%H%M%S)
running=0
for i in "${!DIRS[@]}"; do
  log="$TRACKS/logs/${NAMES[$i]}.atmosphere.$stamp.log"
  LOGS+=("$log")
  score_one "${DIRS[$i]}" "${NAMES[$i]}" "$log" &
  running=$((running + 1))
  if [ "$running" -ge "$PARALLEL" ]; then
    wait
    running=0
  fi
done
wait

total=$(python3 - "${LOGS[@]}" <<'PY'
import re, sys
spent = 0.0
for path in sys.argv[1:]:
    try:
        found = re.findall(r"about \$([0-9.]+) at", open(path).read())
    except OSError:
        continue
    if found:
        spent += float(found[-1])
print(f"{spent:.2f}")
PY
)
if [ "$VIA" = plan ]; then
  echo "This run used about \$$total of plan usage, counted at API list prices. Tracks: $TRACKS"
else
  echo "This run spent about \$$total at list prices. Tracks: $TRACKS"
fi

if [ "$FETCH" = 1 ]; then
  if command -v ffmpeg > /dev/null || [ -x /opt/homebrew/bin/ffmpeg ]; then
    PATH="$PATH:/opt/homebrew/bin"
    echo "Fetching recordings for any sounds still missing (new ones the books asked for too)..."
    python3 -I "$PKG/Tools/atmosphere/fetch_ambience.py" 2>&1 | grep -vE ": already has [0-9]+$"
  else
    echo "Skipped fetching sounds: ffmpeg is missing (brew install ffmpeg)."
  fi
fi

MUSIC="$ROOT/LofiMusic"
if [ "$COPY" = 1 ] && [ -d "$MUSIC" ]; then
  mkdir -p "$MUSIC/tracks"
  for file in "$TRACKS"/*.atmosphere.json "$TRACKS"/*.score.json "$TRACKS"/*.track.json; do
    [ -f "$file" ] && cp "$file" "$MUSIC/tracks/"
  done
  [ -d "$ROOT/Atmosphere" ] && rsync -a --exclude skipped.csv "$ROOT/Atmosphere/" "$MUSIC/Atmosphere/"
  echo "Copied the tracks and sounds into $MUSIC. Put that folder in iCloud Drive and import it in the app (Settings > Import a music folder)."
else
  echo "To hear them on the phone, copy the tracks and the Atmosphere folder into the music folder and import it in the app."
fi
echo "Check a track's scenes with: $B/lofi-atmosphere show \"$TRACKS/<book>.atmosphere.json\" --places"
