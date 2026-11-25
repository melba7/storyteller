#!/bin/bash
# Double-click in Finder. Starts another big run of the teaching work with a NEW spending budget of up
# to $95 of the Claude plan's usage (about $0.19 an episode, so about 480 episodes). It asks for a
# typed yes; anything else changes nothing and starts nothing. After the yes it sets TEACH_BUDGET to
# big-run-YYYYMMDD-HHMM (a name that is new each minute, so the $95 are counted from zero and the
# earlier budgets keep what they spent) and TEACH_YES=1 (the yes was just typed, so the marking does
# not ask again), and starts "Second downloads then gather more", which does the second downloads,
# gathers about 500 more episodes and has Claude mark them at night.
# "Second downloads then gather more.command" is only on the Mac (in "Podcast teaching" next to the
# launchers' wrappers, not in the repo). TEACH_SECOND names another file to start; it is also looked
# for next to this file. TEACH_CAP changes the 95. TEACH_YES in the environment does NOT answer the
# question here: spending money is always asked.
# The new name is also written, as one line, to current-budget.txt in the teaching folder (through a
# temporary file that is moved into place, so it is never half written), and only after the yes.
# "Mark the new episodes at night" takes its default budget from that file, so a stopped run is
# carried on by a double-click on it under the same budget. The name is also in the window and in
# ~/Storyteller Lofi/logs/podcast-teaching.log. When the file cannot be written nothing is started.
# Typing yes here again starts yet another new budget.
HERE="$(cd "$(dirname "$0")" && pwd)"
SECOND_NAME="Second downloads then gather more.command"
FOLDER="$HOME/Storyteller Lofi/PodcastTeaching"
LOG_FOLDER="$HOME/Storyteller Lofi/logs"
LOG="$LOG_FOLDER/podcast-teaching.log"

finish() {
  echo
  echo "$1"
  read -r -p "Press Return to close this window. " _
  exit "${2:-0}"
}

SECOND="$TEACH_SECOND"
if [ -z "$SECOND" ]; then
  for CANDIDATE in "$HERE/$SECOND_NAME" "$HOME/Storyteller Lofi/Podcast teaching/$SECOND_NAME"; do
    if [ -x "$CANDIDATE" ]; then
      SECOND="$CANDIDATE"
      break
    fi
  done
fi
[ -x "$SECOND" ] || finish "$SECOND_NAME is missing, so nothing can be started. It was looked for next to this file and in $HOME/Storyteller Lofi/Podcast teaching." 2
mkdir -p "$LOG_FOLDER" || finish "Could not make $LOG_FOLDER." 2

CAP="${TEACH_CAP:-95}"
echo "Storyteller Lofi: start another big run"
echo
echo "This starts a NEW budget of up to \$$CAP of the Claude plan's usage. Marking costs about \$0.19 an"
echo "episode, so \$95 is about 480 episodes. It is on top of what the earlier runs used: the new"
echo "budget is counted from zero, and the earlier budgets keep what they spent."
echo
echo "It does the second downloads, gathers about 500 more episodes of the shows you follow, and"
echo "has Claude mark the ads in them, only between 11 at night and 7 in the morning, over several"
echo "nights. The marking uses the Claude plan this Mac is signed in to and shares its usage"
echo "allowance. Keep the Mac plugged in with the lid open. A backup of the marks is made before it"
echo "marks anything."
echo "Double-click this file again and type yes again, and that starts yet another new budget."
echo
read -r -p "Type yes to start a new budget of up to \$$CAP, or press Return to change nothing: " TYPED
# Only the ends are trimmed: "ye s" is not yes.
TYPED="$(echo "$TYPED" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | tr '[:upper:]' '[:lower:]')"
if [ "$TYPED" != yes ]; then
  echo "=== $(date '+%Y-%m-%d %H:%M') big run: not started ===" >> "$LOG"
  finish "Nothing was started and nothing was changed." 0
fi

# The name is made after the yes, so it is the minute of the start.
TEACH_BUDGET="big-run-$(date +%Y%m%d-%H%M)"
BUDGET_FILE="$FOLDER/current-budget.txt"
BUDGET_TMP="$FOLDER/.current-budget.$$"
if ! { mkdir -p "$FOLDER" && echo "$TEACH_BUDGET" > "$BUDGET_TMP" && mv "$BUDGET_TMP" "$BUDGET_FILE"; }; then
  rm -f "$BUDGET_TMP" 2> /dev/null
  finish "Could not write $BUDGET_FILE, so nothing was started: a stopped run could not be carried on under its budget." 2
fi
TEACH_CAP="$CAP"
TEACH_YES=1
export TEACH_BUDGET TEACH_CAP TEACH_YES
echo "=== $(date '+%Y-%m-%d %H:%M') big run: new budget $TEACH_BUDGET ===" >> "$LOG"
echo
echo "Starting under the new budget \"$TEACH_BUDGET\" (up to \$$CAP)."
echo "To carry on this run after a stop, double-click \"Mark the new episodes at night\": it takes this"
echo "budget from $BUDGET_FILE."
echo
exec "$SECOND"
