#!/bin/bash
# Double-click in Finder while "Gather episodes for teaching" is still working, or after it. It
# asks once for a typed yes, waits until the gathering is done, and then does everything "Mark ads
# in the teaching episodes" does without asking again: Claude marks the ads, then the steps after
# marking run. So the marking can start in the night with nobody there. Only the marking uses the
# Claude plan this Mac is signed in to (it shares its usage allowance). If you do not type yes,
# nothing runs.
# The gathering counts as done when, three looks in a row, no gathering window has anything running
# under it and no gathering tool runs on its own. A gathering window that only waits for Return
# has nothing under it, so it does not have to be closed. A gathering that failed counts as done
# too: the marking then works on what is already written down.
# The Mac is kept awake while this waits and works. What it does is also noted in
# ~/Storyteller Lofi/logs/podcast-teaching.log.
# For the tests, these can be set: TEACH_LOOK_SECONDS (the time between two looks, default 20) and
# TEACH_MARK (the file that is started when the gathering is done).
HERE="$(cd "$(dirname "$0")" && pwd)"
MARK="${TEACH_MARK:-$HERE/Mark ads in the teaching episodes.command}"
LOOK="${TEACH_LOOK_SECONDS:-20}"
LOG_FOLDER="$HOME/Storyteller Lofi/logs"
LOG="$LOG_FOLDER/podcast-teaching.log"

finish() {
  echo
  echo "$1"
  read -r -p "Press Return to close this window. " _
  exit "${2:-0}"
}

# True while a gathering works: its window has something running under it (a download, the build
# of the transcriber, the writing down), or one of its tools runs on its own.
gathering() {
  local pid
  for pid in $(pgrep -f "Gather episodes for teaching.command"); do
    pgrep -P "$pid" > /dev/null && return 0
  done
  pgrep -f "teach_collect.py|teach_transcribe.py" > /dev/null
}

echo "Storyteller Lofi: mark the ads when the gathering is done"
echo
[ -x "$MARK" ] || finish "$MARK is missing, so nothing can be started." 2
command -v pgrep > /dev/null || finish "pgrep is missing, so this cannot tell when the gathering is done." 2
mkdir -p "$LOG_FOLDER" || finish "Could not make $LOG_FOLDER." 2

echo "This waits until \"Gather episodes for teaching\" has finished. Then Claude marks every"
echo "advertisement and promotion in the episodes it wrote down, and the results are worked out"
echo "and copied to the phone's folders. Nobody needs to be here for that."
echo "The marking uses the Claude plan this Mac is signed in to and shares its usage allowance."
echo "It stops by itself when the allowance is used up and keeps what it marked."
echo "Keep the Mac plugged in with the lid open, and leave this window and the gathering's open."
echo
read -r -p "Type yes to agree: " TYPED
TYPED="$(echo "$TYPED" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')"
[ "$TYPED" = yes ] || finish "Nothing will run, because you did not type yes." 0

# Keeps the Mac from going to sleep for as long as this window works, the marking included.
command -v caffeinate > /dev/null && caffeinate -i -w $$ &

echo "=== $(date '+%Y-%m-%d %H:%M') yes typed: waiting for the gathering to finish ===" >> "$LOG"
echo
echo "$(date '+%H:%M') Thank you. Waiting for the gathering to finish."
QUIET=0
LOOKS=0
while [ "$QUIET" -lt 3 ]; do
  if gathering; then
    QUIET=0
    # One line about every half hour, so the window shows it is still there.
    [ $((LOOKS % 90)) -eq 0 ] && echo "$(date '+%H:%M') The gathering is still working."
    LOOKS=$((LOOKS + 1))
  else
    QUIET=$((QUIET + 1))
  fi
  [ "$QUIET" -lt 3 ] && sleep "$LOOK"
done

echo "=== $(date '+%Y-%m-%d %H:%M') the gathering is done: the marking starts by itself ===" >> "$LOG"
echo "$(date '+%H:%M') The gathering is done. The marking starts now."
echo
TEACH_YES=1
export TEACH_YES
exec "$MARK"
