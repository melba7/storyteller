#!/bin/bash
# Double-click in Finder. One click for "free the disk, then start the next run on your own shows", in
# this order:
#   1. "Free up space from the teaching audio": it shows how much it would free and asks you to type
#      yes (the audio whose lessons are kept) or all (also the episodes still waiting for a second
#      download, which gives that comparison up). Anything else deletes nothing. It makes and checks a
#      backup of the marks first and costs no Claude usage.
#   2. A NEW budget of up to $95 of your Claude plan's usage, then "Gather more episodes for teaching"
#      with the newest 30 of each show (the shows hold 24 each now, so about 400 more episodes, about
#      20 GB of audio; it stops by itself when the disk has less than 15 GB free). It writes down what
#      is said in them and has Claude mark the ads at any hour, as soon as the writing down is done,
#      then works out the results and copies them to the phone's folders. This step needs one typed
#      yes, because it spends your Claude usage.
# Both answers are typed in this window with nothing more to click. The marking takes many hours, so
# keep this window open, the Mac plugged in and the lid open. If it stops, double-click "Gather deeper
# and mark now": it carries on under the same budget (the name is saved in current-budget.txt in the
# teaching folder), marks what is already written down and never starts a fresh $95.
# TEACH_CAP changes the 95 and TEACH_PER_SHOW the 30. TEACH_YES in the environment does NOT answer the
# question here: spending money is always asked.
# Everything it prints is also added to ~/Storyteller Lofi/logs/podcast-teaching.log by the steps; this
# file adds the line that names the new budget.
HERE="$(cd "$(dirname "$0")" && pwd)"
FREE="$HERE/Free up space from the teaching audio.command"
MORE="$HERE/Gather more episodes for teaching.command"
FOLDER="$HOME/Storyteller Lofi/PodcastTeaching"
LOG_FOLDER="$HOME/Storyteller Lofi/logs"
LOG="$LOG_FOLDER/podcast-teaching.log"

finish() {
  echo
  echo "$1"
  read -r -p "Press Return to close this window. " _
  exit "${2:-0}"
}

number() { printf '%s' "$1" | LC_ALL=C grep -Eq '^[0-9]{1,4}$' && [ "$1" -ge 1 ]; }
CAP="${TEACH_CAP:-95}"
number "$CAP" || CAP=95
PER_SHOW="${TEACH_PER_SHOW:-30}"
number "$PER_SHOW" || PER_SHOW=30

echo "Storyteller Lofi: free space and start the next run"
echo
echo "This runs two steps one after the other, with nothing more to click:"
echo "  1. Delete the audio the Mac no longer needs. It shows how much would be freed. You type yes to"
echo "     delete the audio whose lessons are kept, or type all to also delete the episodes still waiting"
echo "     for a second download (that comparison is given up for them). The transcripts, the marks, the"
echo "     sound banks and the models stay, and a backup of the marks is made first."
echo "  2. Start the next run on your own shows: download the newest $PER_SHOW of each show, write down"
echo "     what is said, and have Claude mark the ads at any hour, as soon as that is done. This uses"
echo "     your Claude plan's usage, at about 19 cents an episode, and never more than \$$CAP. It asks"
echo "     for one more yes before it starts."
echo
for STEP in "$FREE" "$MORE"; do
  [ -x "$STEP" ] || finish "A step is missing: $STEP. Nothing was started." 2
done
mkdir -p "$LOG_FOLDER" || finish "Could not make $LOG_FOLDER." 2

export TEACH_CHAIN=1

echo "=== Step 1 of 2: free up space from the teaching audio ==="
"$FREE"
CODE=$?
case "$CODE" in
  0) ;;
  4) echo "Most of it was deleted, but some files could not be deleted (see above). The run goes on." ;;
  1) finish "Stopped at step 1: nothing was deleted, because the backup of the marks was not good (see above). Nothing was started." "$CODE" ;;
  3) finish "Stopped at step 1: a teaching run is still working in the folder. Double-click this again when it has finished. Nothing was started." "$CODE" ;;
  *) finish "Stopped at step 1: it could not look at the teaching folder (see above). Nothing was started." "$CODE" ;;
esac

echo
echo "=== Step 2 of 2: start the next run ==="
echo
echo "This starts a NEW budget of up to \$$CAP of the Claude plan's usage, counted from zero: the earlier"
echo "budgets keep what they spent. It downloads the newest $PER_SHOW episodes of each show you follow"
echo "(about 400 more than are on the disk now; it stops by itself when the disk has less than 15 GB"
echo "free) and writes down what is said in them. Then Claude marks the ads at any hour, as soon as the"
echo "writing down is done. The marking shares the usage allowance of the Claude plan this Mac is signed"
echo "in to. Keep the Mac plugged in with the lid open."
df -h "$HOME" 2> /dev/null | tail -n 1 | awk '{ print "Disk now: " $4 " free of " $2 "." }'
echo
read -r -p "Type yes to start a new budget of up to \$$CAP, or press Return to start nothing: " TYPED
# Only the ends are trimmed: "ye s" is not yes.
TYPED="$(echo "$TYPED" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | tr '[:upper:]' '[:lower:]')"
if [ "$TYPED" != yes ]; then
  echo "=== $(date '+%Y-%m-%d %H:%M') free space and next run: not started ===" >> "$LOG"
  finish "Nothing was started, because you did not type yes. The audio is freed as far as step 1 said." 0
fi

# The name is made after the yes, so it is the minute of the start, and it is written the way
# "Start another big run" writes it, so "Gather deeper and mark now" carries on under the same budget.
TEACH_BUDGET="big-run-$(date +%Y%m%d-%H%M)"
BUDGET_FILE="$FOLDER/current-budget.txt"
BUDGET_TMP="$FOLDER/.current-budget.$$"
if ! { mkdir -p "$FOLDER" && echo "$TEACH_BUDGET" > "$BUDGET_TMP" && mv "$BUDGET_TMP" "$BUDGET_FILE"; }; then
  rm -f "$BUDGET_TMP" 2> /dev/null
  finish "Could not write $BUDGET_FILE, so nothing was started: a stopped run could not be carried on under its budget." 2
fi
echo "=== $(date '+%Y-%m-%d %H:%M') free space and next run: new budget $TEACH_BUDGET ===" >> "$LOG"
echo
echo "Starting under the new budget \"$TEACH_BUDGET\" (up to \$$CAP)."
echo "To carry on this run after a stop, double-click \"Gather deeper and mark now\": it takes this"
echo "budget from $BUDGET_FILE."
echo

# The same settings "Gather deeper and mark now" gives, with the newest 30 of each show: the yes was just
# typed, the marking may happen at any hour, and the audio folder may hold up to 80 GB.
TEACH_PER_SHOW="$PER_SHOW"
TEACH_MAX_GB=80
TEACH_CAP="$CAP"
TEACH_YES=1
TEACH_BETWEEN=0-24
export TEACH_PER_SHOW TEACH_MAX_GB TEACH_CAP TEACH_BUDGET TEACH_YES TEACH_BETWEEN
unset TEACH_CHAIN  # the chain ends here; the steps after it are not part of it
exec "$MORE"
