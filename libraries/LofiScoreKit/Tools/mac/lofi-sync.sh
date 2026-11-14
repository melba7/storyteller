#!/bin/bash
# The unattended path from a book synced in Storyteller to atmosphere sounds on
# the phone. install-automatic-scoring.command runs it from launchd when a
# book lands in "~/Storyteller Lofi/Books" and every half hour; "Score
# atmosphere.command" runs it when double-clicked. It does, in order:
#
#   1. Fetches newly synced read-aloud books from your Storyteller server into
#      Books/ (fetch-books.sh), when "~/Storyteller Lofi/server.json" is set up.
#   2. Scores every book in Books/ that has no score yet, through your Claude
#      plan: the atmosphere (make-atmosphere.sh), which writes
#      "<book>.score.json", fetches recordings for new sounds, and copies the
#      tracks and sounds into "~/Storyteller Lofi/LofiMusic" (the folder the
#      phone follows; the name is from when it held the music). The music's
#      mood track (make-tracks.sh, Claude Opus, prompt 3) is made first only
#      with --with-mood-tracks or LOFI_MOOD_TRACKS=1, for when the music comes
#      back (see shelved/lofi-music/README.md at the repository root).
#   3. Mirrors LofiMusic into its iCloud Drive copy (iCloud Drive/Storyteller
#      Lofi/LofiMusic) when there is one, adding and updating, never deleting.
#      The phone's linked sounds folder picks the new files up by itself.
#   4. Puts each score inside the book on the server (PUT
#      /api/v2/books/<id>/lofi-score), when the server is the fork's, so the
#      phone also gets the score with the book itself.
#
# One run at a time; a run stopped part way carries on next time, and scenes
# that failed (on the plan's usage limit, say) are retried by the next runs.
# Each step is capped per book at API list prices, so a run that goes wrong
# can't use up the plan. A long novel takes about an hour.
#
#   lofi-sync.sh [--tools DIR] [--no-pull] [--interactive] [--with-mood-tracks]
#
# While a sound fetch (fetch-sounds.sh) is running nothing is scored: from
# launchd the run ends and the next one tries again; in a window it waits.
# With "since" in server.json (the installer writes it) only books whose
# read-aloud version was made from then on are fetched, plus the titles listed
# in Books/wanted.txt; books put into Books/ by hand are always scored.
#
# --tools is the fork checkout to use (default: the one this script is in).
# --no-pull skips updating it. --interactive prints progress for a Terminal
# window instead of the log. --with-mood-tracks also makes each book's mood
# track for the shelved music (the score then carries both).
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
MOOD_TRACKS="${LOFI_MOOD_TRACKS:-0}"
while [ $# -gt 0 ]; do
  case "$1" in
    --tools) TOOLS="$2"; shift 2 ;;
    --no-pull) PULL=0; shift ;;
    --interactive) INTERACTIVE=1; shift ;;
    --with-mood-tracks) MOOD_TRACKS=1; shift ;;
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

# A sound fetch (fetch-sounds.sh, hours long) fills the same folders and uses the
# same Freesound quota, and a book scored before it ends would miss the new
# sounds. From launchd, scoring waits for the next run; in a window, it waits here.
sound_fetch_running() { pgrep -f 'fetch_ambience\.py|fetch-sounds\.sh' > /dev/null 2>&1; }
if sound_fetch_running; then
  if [ "$INTERACTIVE" = 1 ]; then
    say "a sound fetch is still running; scoring waits for it to finish (Ctrl-C stops waiting)"
    while sound_fetch_running; do sleep 60; done
    say "the sound fetch has finished"
  else
    say "a sound fetch is still running; scoring waits for the next run"
    exit 0
  fi
fi

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

# 2. Score what has no score yet, then retry the books whose last run left scenes
# unscored (they keep a "<book>.retry" marker; see below). A file changed in the
# last minute is still being copied in and waits for the next run, unless this
# run downloaded it.
shopt -s nullglob
just_fetched() {
  local file
  for file in ${FETCHED[@]+"${FETCHED[@]}"}; do [ "$file" = "$1" ] && return 0; done
  return 1
}
TODO=()
RETRY=()
for book in "$BOOKS_DIR"/*.epub; do
  name="$(basename "$book" .epub)"
  if [ -s "$TRACKS/$name.score.json" ]; then
    [ -f "$TRACKS/$name.retry" ] && RETRY+=("$book")
    continue
  fi
  if [ -n "$(find "$book" -mmin -1 2>/dev/null)" ] && ! just_fetched "$(basename "$book")"; then
    say "$name is still being copied; next time"
    continue
  fi
  TODO+=("$book")
done
TODO+=(${RETRY[@]+"${RETRY[@]}"})

# A run that ends with scenes failed (its log's summary says "N failed") still
# writes the score, with those scenes silent. The book then keeps a
# "<book>.retry" marker, and the next runs score the missing scenes only, until
# a run ends with none failed. Failures on the plan's usage limit go away by
# themselves, so they are retried every run; other failures three times.
MAX_RETRIES=3
note_failed_scenes() {
  local name="$1" logs log failed tries
  logs=("$TRACKS/logs/$name.atmosphere."*.log)
  [ ${#logs[@]} -gt 0 ] && log="$(ls -t "${logs[@]}" | head -n 1)" || log=""
  failed="$(grep -o -E '[0-9]+ failed, [0-9]+ places' "$log" 2>/dev/null | tail -n 1 | cut -d' ' -f1)"
  if [ -z "$failed" ] || [ "$failed" = 0 ]; then
    rm -f "$TRACKS/$name.retry"
    say "$name: scored"
    return
  fi
  tries="$(cat "$TRACKS/$name.retry" 2>/dev/null)"
  case "$tries" in ''|*[!0-9]*) tries=0 ;; esac
  if grep -q "rate_limit_error" "$log"; then
    say "$name: scored, but $failed scenes failed on the plan's usage limit; the next runs retry them"
  elif [ "$tries" -ge "$MAX_RETRIES" ]; then
    rm -f "$TRACKS/$name.retry"
    say "$name: scored, but $failed scenes failed again; giving up on them after $MAX_RETRIES retries (see $log)"
    return
  else
    tries=$((tries + 1))
    say "$name: scored, but $failed scenes failed; the next run retries them ($tries of $MAX_RETRIES)"
  fi
  echo "$tries" > "$TRACKS/$name.retry"
}
if [ ${#TODO[@]} -eq 0 ]; then
  say "nothing new to score"
else
  cd "$PKG" || exit 1
  for book in "${TODO[@]}"; do
    name="$(basename "$book" .epub)"
    if [ "$MOOD_TRACKS" = 1 ]; then
      say "scoring $name: the mood track"
      if [ "$INTERACTIVE" = 1 ]; then
        "$MAC/make-tracks.sh" --via plan --engine claude --prompt 3 --cap "$MOOD_CAP_PER_BOOK" "$book"
      else
        "$MAC/make-tracks.sh" --via plan --engine claude --prompt 3 --cap "$MOOD_CAP_PER_BOOK" "$book" >> "$LOGS/scoring.log" 2>&1
      fi
      [ -s "$TRACKS/$name.track.json" ] || { say "$name: no mood track was made (see $LOGS/scoring.log); the atmosphere waits"; continue; }
    fi
    say "scoring $name: the atmosphere"
    if [ "$INTERACTIVE" = 1 ]; then
      "$MAC/make-atmosphere.sh" --via plan --cap "$ATMOSPHERE_CAP_PER_BOOK" "$book"
    else
      "$MAC/make-atmosphere.sh" --via plan --cap "$ATMOSPHERE_CAP_PER_BOOK" "$book" >> "$LOGS/scoring.log" 2>&1
    fi
    if [ -s "$TRACKS/$name.score.json" ]; then
      note_failed_scenes "$name"
    else
      say "$name: not finished (the cap, or an error; see $LOGS/scoring.log). Next run carries on."
    fi
  done
fi

# 3. The iCloud copy, which the phone's linked sounds folder follows.
if [ -d "$ICLOUD" ] && [ -d "$MUSIC" ]; then
  if rsync -a --exclude .DS_Store --exclude '.*.part' --exclude '.imported.json' "$MUSIC/" "$ICLOUD/" 2>> "$LOGS/sync.log"; then
    say "iCloud copy up to date"
  elif tail -n 3 "$LOGS/sync.log" 2>/dev/null | grep -q "Operation not permitted"; then
    # macOS keeps background jobs out of iCloud Drive until the interpreter
    # has Full Disk Access; a double-clicked .command runs inside Terminal,
    # which has it, so the installer's own copy step is unaffected.
    say "could not update the iCloud copy: macOS blocks this background job from iCloud Drive. Once: System Settings > Privacy & Security > Full Disk Access > +, press Cmd-Shift-G, type /bin/bash, add it and switch it on."
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
