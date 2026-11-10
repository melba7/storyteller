#!/bin/bash
# The unattended path from a book synced in Storyteller to music and atmosphere
# on the phone. install-automatic-scoring.command runs it from launchd when a
# book lands in "~/Storyteller Lofi/Books" and every half hour; "Score
# atmosphere.command" runs it when double-clicked. It does, in order:
#
#   1. Fetches newly synced read-aloud books from your Storyteller server into
#      Books/ (fetch-books.sh), when "~/Storyteller Lofi/server.json" is set up.
#   2. Scores every book in Books/ that has no score yet, through your Claude
#      plan: the mood track (make-tracks.sh, Claude Opus, prompt 3) and the
#      atmosphere (make-atmosphere.sh), which combines the two into
#      "<book>.score.json", fetches recordings for new sounds, and copies the
#      tracks and sounds into "~/Storyteller Lofi/LofiMusic".
#   3. Mirrors LofiMusic into its iCloud Drive copy (iCloud Drive/Storyteller
#      Lofi/LofiMusic) when there is one, adding and updating, never deleting.
#      The phone's linked music folder picks the new files up by itself.
#   4. Puts each score inside the book on the server (PUT
#      /api/v2/books/<id>/lofi-score), when the server is the fork's, so the
#      phone also gets the score with the book itself.
#
# One run at a time; a run stopped part way carries on next time. Each step is
# capped per book at API list prices, so a run that goes wrong can't use up
# the plan. A long novel takes about an hour.
#
#   lofi-sync.sh [--tools DIR] [--no-pull] [--interactive]
#
# --tools is the fork checkout to use (default: the one this script is in).
# --no-pull skips updating it. --interactive prints progress for a Terminal
# window instead of the log.
set -uo pipefail

ROOT="$HOME/Storyteller Lofi"
BOOKS_DIR="$ROOT/Books"
TRACKS="$ROOT/tracks"
MUSIC="$ROOT/LofiMusic"
ICLOUD="$HOME/Library/Mobile Documents/com~apple~CloudDocs/Storyteller Lofi/LofiMusic"
LOGS="$ROOT/logs"
LOCK="$ROOT/.lofi-sync.lock"
MOOD_CAP_PER_BOOK=20
ATMOSPHERE_CAP_PER_BOOK=25
TOOLS="$(cd "$(dirname "$0")/../../../.." && pwd)"
PULL=1
INTERACTIVE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --tools) TOOLS="$2"; shift 2 ;;
    --no-pull) PULL=0; shift ;;
    --interactive) INTERACTIVE=1; shift ;;
    *) echo "unknown option $1"; exit 2 ;;
  esac
done
PKG="$TOOLS/libraries/LofiScoreKit"
MAC="$PKG/Tools/mac"
export PATH="$PATH:/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$HOME/.claude/local"
mkdir -p "$BOOKS_DIR" "$TRACKS" "$LOGS"

say() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*"; }

# One run at a time. A lock older than twelve hours is a crashed run's.
if ! mkdir "$LOCK" 2>/dev/null; then
  if [ -n "$(find "$LOCK" -maxdepth 0 -mmin +720 2>/dev/null)" ]; then
    rmdir "$LOCK" 2>/dev/null && mkdir "$LOCK" 2>/dev/null || { say "another run is going"; exit 0; }
  else
    say "another run is going"
    exit 0
  fi
fi
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

[ -d "$PKG" ] || { say "no tools at $TOOLS"; exit 1; }
if ! command -v claude > /dev/null; then
  say "Claude Code isn't installed (or not on the PATH). Install it, run 'claude' once in Terminal and sign in."
  exit 1
fi
if [ "$PULL" = 1 ] && [ -d "$TOOLS/.git" ]; then
  git -C "$TOOLS" pull --ff-only --quiet 2>/dev/null || say "(could not update the tools; using them as they are)"
fi

# 1. New books from the server.
FETCHED=()
if [ -f "$ROOT/server.json" ]; then
  say "looking for newly synced books on the server"
  while IFS=$'\t' read -r uuid file; do
    [ -n "$file" ] && { FETCHED+=("$file"); say "downloaded $file"; }
  done < <("$MAC/fetch-books.sh" 2>&1 | tee -a "$LOGS/fetch-books.log" | grep -E $'^[0-9a-f-]{36}\t')
fi

# 2. Score what has no score yet. A file changed in the last minute is still
# being copied in; it waits for the next run.
shopt -s nullglob
TODO=()
for book in "$BOOKS_DIR"/*.epub; do
  name="$(basename "$book" .epub)"
  [ -s "$TRACKS/$name.score.json" ] && continue
  [ -n "$(find "$book" -mmin -1 2>/dev/null)" ] && { say "$name is still being copied; next time"; continue; }
  TODO+=("$book")
done
if [ ${#TODO[@]} -eq 0 ]; then
  say "nothing new to score"
else
  cd "$PKG" || exit 1
  for book in "${TODO[@]}"; do
    name="$(basename "$book" .epub)"
    say "scoring $name: the mood track"
    if [ "$INTERACTIVE" = 1 ]; then
      "$MAC/make-tracks.sh" --via plan --engine claude --prompt 3 --cap "$MOOD_CAP_PER_BOOK" "$book"
    else
      "$MAC/make-tracks.sh" --via plan --engine claude --prompt 3 --cap "$MOOD_CAP_PER_BOOK" "$book" >> "$LOGS/scoring.log" 2>&1
    fi
    [ -s "$TRACKS/$name.track.json" ] || { say "$name: no mood track was made (see $LOGS/scoring.log); the atmosphere waits"; continue; }
    say "scoring $name: the atmosphere"
    if [ "$INTERACTIVE" = 1 ]; then
      "$MAC/make-atmosphere.sh" --via plan --cap "$ATMOSPHERE_CAP_PER_BOOK" "$book"
    else
      "$MAC/make-atmosphere.sh" --via plan --cap "$ATMOSPHERE_CAP_PER_BOOK" "$book" >> "$LOGS/scoring.log" 2>&1
    fi
    if [ -s "$TRACKS/$name.score.json" ]; then
      say "$name: scored"
    else
      say "$name: not finished (the cap, or an error; see $LOGS/scoring.log). Next run carries on."
    fi
  done
fi

# 3. The iCloud copy, which the phone's linked music folder follows.
if [ -d "$ICLOUD" ] && [ -d "$MUSIC" ]; then
  if rsync -a --exclude .DS_Store --exclude '.*.part' --exclude '.imported.json' "$MUSIC/" "$ICLOUD/" 2>> "$LOGS/sync.log"; then
    say "iCloud copy up to date"
  else
    say "could not update the iCloud copy (see $LOGS/sync.log)"
  fi
fi

# 4. The score into the book on the server. Books/.synced.json maps the server's
# books to their files; .pushed.json remembers what was sent.
if [ -f "$ROOT/server.json" ] && [ -f "$BOOKS_DIR/.synced.json" ]; then
  "$MAC/push-scores.sh" 2>&1 | while read -r line; do say "$line"; done
fi
say "done"
