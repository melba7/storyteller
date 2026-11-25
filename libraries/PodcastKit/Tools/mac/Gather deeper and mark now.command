#!/bin/bash
# Double-click in Finder. Same as "Gather deeper and mark tonight", except that the marking may happen
# at any hour (Mo asked for it on 2026-11-25), not only between 11 at night and 7 in the morning: the
# marking starts as soon as the episodes are gathered and written down. It uses the Claude plan's
# usage allowance in the daytime too. The second step of a big run: the first pass can gather only a few new
# episodes when the newest 12 of every show are already on disk, so this goes deeper: the newest 24
# of each show (about 500 more episodes, about 25 GB of audio; the gathering stops by itself when the
# disk has less than 15 GB free), writes them down, has Claude mark the ads at night (only between 11
# at night and 7 in the morning) under the same budget as the run before it, and works out and copies
# the results. It asks for a typed yes once (anything else starts nothing), then waits until the
# teaching folder is free (the steps after the last marking may still be working; it asks every 60
# seconds and says so once), and starts "Gather more episodes for teaching" with TEACH_PER_SHOW=24,
# TEACH_MAX_GB=80 and the yes given, so nothing asks again. A stopped run carries on if you
# double-click it again.
# The budget is TEACH_BUDGET when that is set, else the name in current-budget.txt in the teaching
# folder (written by "Start another big run"; 1 to 40 letters, digits, - or _, starting with a letter or
# digit), else big-run-1: the same rule as "Mark the new episodes at night". TEACH_YES in the
# environment does NOT answer the question here: spending is always asked.
# Everything it prints is also added to ~/Storyteller Lofi/logs/podcast-teaching.log.
HERE="$(cd "$(dirname "$0")" && pwd)"
FOLDER="$HOME/Storyteller Lofi/PodcastTeaching"
BUDGET_FILE="$FOLDER/current-budget.txt"
LOG_FOLDER="$HOME/Storyteller Lofi/logs"
LOG="$LOG_FOLDER/podcast-teaching.log"
MORE="$HERE/Gather more episodes for teaching.command"
STORE="$HERE/teach_store.py"

finish() {
  echo
  echo "$1"
  read -r -p "Press Return to close this window. " _
  exit "${2:-0}"
}

[ -x "$MORE" ] || finish "$MORE is missing, so nothing can be started." 2
[ -f "$STORE" ] || finish "$STORE is missing, so nothing can be started." 2
command -v python3 > /dev/null || finish "python3 is missing. Install Apple's command line tools: open Terminal and run xcode-select --install" 2
mkdir -p "$LOG_FOLDER" || finish "Could not make $LOG_FOLDER." 2

# The budget: the environment, then the name in current-budget.txt (its first line, trimmed), then big-run-1.
BUDGET="$TEACH_BUDGET"
if [ -z "$BUDGET" ]; then
  BUDGET="big-run-1"
  if [ -f "$BUDGET_FILE" ]; then
    NAME=""
    IFS= read -r NAME < "$BUDGET_FILE" 2> /dev/null
    NAME="$(printf '%s' "$NAME" | LC_ALL=C sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' 2> /dev/null)"
    if printf '%s' "$NAME" | LC_ALL=C grep -Eq '^[A-Za-z0-9][A-Za-z0-9_-]{0,39}$'; then
      BUDGET="$NAME"
    fi
  fi
fi

echo "Storyteller Lofi: gather deeper and mark now"
echo
echo "This downloads the newest 24 episodes of each show you follow (about 500 more than are on the"
echo "disk now, about 25 GB of audio; it stops by itself when the disk has less than 15 GB free) and"
echo "writes down what is said. Then Claude marks the ads in them at any hour, as soon as the"
echo "writing down is done, which also uses the Claude plan's usage in the daytime. It marks under the budget \"$BUDGET\", which stops at"
echo "\$95 of the Claude plan's usage in all, counted over every run (the window says what is left when"
echo "the marking starts). The marking shares the usage allowance of the Claude plan this Mac is"
echo "signed in to. Then the results are worked out and copied to the phone's folders."
echo "Keep the Mac plugged in with the lid open. You can stop with Control-C and double-click this"
echo "file again later to carry on."
echo
read -r -p "Type yes to start: " TYPED
# Only the ends are trimmed: "ye s" is not yes.
TYPED="$(echo "$TYPED" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | tr '[:upper:]' '[:lower:]')"
[ "$TYPED" = yes ] || finish "Nothing was started, because you did not type yes." 0

echo "=== $(date '+%Y-%m-%d %H:%M') gather deeper: newest 24 of each show, marking at any hour ===" >> "$LOG"

# The steps after the last marking may still be working and hold the folder: wait for them. Only exit
# code 3 means busy; any other failure of the check stops it instead of waiting for ever.
WAITED=""
while true; do
  python3 "$STORE" busy "$FOLDER" > /dev/null 2>&1
  CODE="$?"
  [ "$CODE" = 3 ] || break
  if [ -z "$WAITED" ]; then
    echo "Another teaching step is still working in the folder. Waiting for it to finish, then starting." | tee -a "$LOG"
    WAITED=1
  fi
  sleep 60
done
[ "$CODE" = 0 ] || finish "Whether the teaching folder is free could not be checked (exit code $CODE), so nothing was started." 2

TEACH_PER_SHOW=24
TEACH_MAX_GB=80
TEACH_BUDGET="$BUDGET"
TEACH_YES=1
TEACH_BETWEEN=0-24
export TEACH_PER_SHOW TEACH_MAX_GB TEACH_BUDGET TEACH_YES TEACH_BETWEEN
exec "$MORE"
