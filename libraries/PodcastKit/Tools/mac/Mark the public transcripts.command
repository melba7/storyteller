#!/bin/bash
# Double-click in Finder. Has Claude mark every advertisement and promotion in the public SPoRC
# transcripts that "Fetch a sample of public transcripts" wrote (teach_label.py, in the folder
# ~/Storyteller Lofi/PodcastTeachingSporc). It uses the Claude plan this Mac is signed in to and
# shares its usage allowance, at about 15 to 20 cents an episode, and asks you to type yes before
# it starts. It marks at most TEACH_SPORC_LIMIT episodes (default 500) and spends at most
# TEACH_SPORC_CAP dollars (default 100) in all, counted over every double-click under the budget
# sporc-1 (TEACH_SPORC_BUDGET for another name), so a second double-click carries on and cannot
# pass the cap. When the usage allowance is used up it waits up to TEACH_SPORC_WAIT_HOURS (default
# 12) and carries on. It marks at any hour, runs next to a big run in the other folder, writes
# only into the SPoRC folder and does nothing else with the marks: they are not taught to the
# phone, and the files stay on this Mac (SPoRC is released for research and educational use only).
# What it prints is also added to ~/Storyteller Lofi/logs/podcast-teaching.log.
HERE="$(cd "$(dirname "$0")" && pwd)"
FOLDER="$HOME/Storyteller Lofi/PodcastTeachingSporc"
LOG_FOLDER="$HOME/Storyteller Lofi/logs"
LOG="$LOG_FOLDER/podcast-teaching.log"

finish() {
  echo
  echo "$1"
  read -r -p "Press Return to close this window. " _
  exit "${2:-0}"
}

number() { printf '%s' "$1" | LC_ALL=C grep -Eq '^[0-9]{1,4}$' && [ "$1" -ge 1 ]; }
LIMIT="${TEACH_SPORC_LIMIT:-500}"
number "$LIMIT" || LIMIT=500
CAP="${TEACH_SPORC_CAP:-100}"
number "$CAP" || CAP=100
WAIT="${TEACH_SPORC_WAIT_HOURS:-12}"
number "$WAIT" || WAIT=12
BUDGET="${TEACH_SPORC_BUDGET:-sporc-1}"
printf '%s' "$BUDGET" | LC_ALL=C grep -Eq '^[A-Za-z0-9][A-Za-z0-9_-]{0,39}$' || BUDGET=sporc-1

echo "Storyteller Lofi: mark the public transcripts"
echo
echo "This has Claude mark the ads in up to $LIMIT of the public transcripts in $FOLDER,"
echo "spending at most \$$CAP of your Claude plan's usage in all (budget \"$BUDGET\")."
echo
command -v python3 > /dev/null || finish "python3 is missing. Install Apple's command line tools: open Terminal and run xcode-select --install" 2
[ -f "$FOLDER/episodes.json" ] || finish "There is no sample yet. Double-click \"Fetch a sample of public transcripts\" first." 2
mkdir -p "$LOG_FOLDER" || finish "Could not make $LOG_FOLDER." 2

echo "=== $(date '+%Y-%m-%d %H:%M') mark the public transcripts: up to $LIMIT episodes, \$$CAP ===" >> "$LOG"
caffeinate -i python3 -u "$HERE/teach_label.py" --folder "$FOLDER" --limit "$LIMIT" --cap "$CAP" --budget "$BUDGET" --wait-hours "$WAIT" 2>&1 | tee -a "$LOG"
CODE="${PIPESTATUS[0]}"
case "$CODE" in
  0) finish "Done. The marks are in $FOLDER/labels. Tell Claude it is finished." 0 ;;
  3) finish "Marking stopped: Claude's usage allowance stayed used up for longer than it waits, or Claude is not signed in (see above). What was marked is saved. Double-click again to carry on." 3 ;;
  4) finish "Nothing was marked, because you did not type yes. Double-click again and type yes to start." 0 ;;
  5) finish "The spending limit of \$$CAP is reached (counted over every run under \"$BUDGET\"). What was marked is saved." 5 ;;
  6) finish "Marking stopped because episodes failed (see failures.json in $FOLDER). What was marked is saved." 6 ;;
  *) finish "Something is not set up, or another run is working in the folder (see above). Nothing more was marked." 2 ;;
esac
