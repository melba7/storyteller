#!/bin/bash
# Double-click in Finder. Gathers about 60 brand-new episodes and keeps them apart as an exam: the
# phone's learning never sees them (see teach_exam.py). It writes down what is said in them, says how
# many of them have audio and a transcript, then, when you type yes at the start, Claude marks the
# ads in them only at night (up to $14 in all) and marks 15 of them a second time (up to $4 in all)
# so we can see how much two markings differ. The two limits are budgets kept over every run (the
# names exam and exam-second, in marking-spend.json), so double-clicking again never gives a fresh
# $14 or $4. It does not run the steps that teach the phone: the exam teaches nothing, it is only
# to be scored.
# It asks once, at the start. If you do not type yes it only gathers. TEACH_YES=1 answers yes (only
# the exact value 1 counts).
# It starts "Gather episodes for teaching" (with TEACH_EXAM=1 TEACH_PER_SHOW=2 TEACH_MAX_GB=46),
# which starts this file again, with TEACH_EXAM_STAGE=night, when the gathering worked. A stopped
# run carries on where it was when you double-click again. It says "Done" only when every exam
# episode that has a transcript has a first marking and the second marking holds 15 of them (or
# all of them when there are fewer); otherwise it says what is left (counted by teach_exam.py).
# Everything it prints is also added to ~/Storyteller Lofi/logs/podcast-teaching.log. The Mac is
# kept awake for the whole wait (caffeinate -i).
# For the tests, TEACH_GATHER is the file that is started for the gathering.
HERE="$(cd "$(dirname "$0")" && pwd)"
GATHER="${TEACH_GATHER:-$HERE/Gather episodes for teaching.command}"
FOLDER="$HOME/Storyteller Lofi/PodcastTeaching"
LOG_FOLDER="$HOME/Storyteller Lofi/logs"
LOG="$LOG_FOLDER/podcast-teaching.log"

finish() {
  echo
  echo "$1"
  read -r -p "Press Return to close this window. " _
  exit "${2:-0}"
}

# Says how the exam stands (how many are marked once and twice), whatever the marking did.
report() {
  python3 -u "$HERE/teach_exam.py" finish --folder "$FOLDER" 2>&1 | tee -a "$LOG"
}

# The closing words for a marking that stopped: $1 is the exit code of teach_label.py, $2 the limit
# in dollars that marking had, $3 what it was (the first marking, the second marking).
stopped() {
  case "$1" in
    3) finish "$3 stopped early: Claude's usage allowance stayed used up for longer than it waits, or Claude is not signed in (see the last lines above). What was marked is saved. Double-click again to carry on, for example after your usage allowance has reset." 3 ;;
    5) finish "The spending limit of \$$2 for the $3 is reached (counted over every run) and nothing more will be marked under it. What was marked is saved." 5 ;;
    6)
      FAILED="$(python3 "$HERE/teach_failures.py" count --folder "$FOLDER" 2> /dev/null)"
      finish "$3 stopped because episodes failed: ${FAILED:-some} episodes are on the list of failures, in $FOLDER/failures.json. What was marked is saved. Double-click again to try the next ones." 6 ;;
    *) finish "Something is not set up, or another run is working in the folder (see above). Nothing more was marked." 2 ;;
  esac
}

command -v python3 > /dev/null || finish "python3 is missing. Install Apple's command line tools: open Terminal and run xcode-select --install" 2
mkdir -p "$LOG_FOLDER" || finish "Could not make $LOG_FOLDER." 2

if [ "$TEACH_EXAM_STAGE" != night ]; then
  [ -x "$GATHER" ] || finish "$GATHER is missing, so nothing can be started." 2
  echo "Storyteller Lofi: gather the exam episodes"
  echo
  echo "This downloads about 60 brand-new episodes of the shows you follow and keeps them apart as"
  echo "an exam: the phone's learning never sees them. It writes down what is said in them."
  echo "That takes hours. Keep the Mac plugged in with the lid open."
  echo
  echo "Then Claude can mark the ads in them, only between 11 at night and 7 in the morning, over"
  echo "several nights, using at most \$18 of the Claude plan's usage in all (\$14 for the first"
  echo "marking and \$4 for the second, counted over every run). It also marks 15 of them a"
  echo "second time, so we can see how much two markings differ."
  echo "The marking uses the Claude plan this Mac is signed in to and shares its usage allowance."
  echo "You can stop with Control-C and double-click this file again later to carry on."
  echo
  if [ "$TEACH_YES" = 1 ]; then
    TYPED=yes
  else
    read -r -p "Type yes to include the marking, or press Return to only gather: " TYPED
  fi
  # Only the ends are trimmed: "ye s" is not yes.
  TYPED="$(echo "$TYPED" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | tr '[:upper:]' '[:lower:]')"
  TEACH_EXAM=1
  TEACH_PER_SHOW=2
  TEACH_MAX_GB=46
  TEACH_AFTER="$HERE/Gather the exam episodes.command"
  TEACH_EXAM_STAGE=night
  export TEACH_EXAM TEACH_PER_SHOW TEACH_MAX_GB TEACH_AFTER TEACH_EXAM_STAGE
  if [ "$TYPED" = yes ]; then
    echo "=== $(date '+%Y-%m-%d %H:%M') exam: gathering, then the marking at night ===" >> "$LOG"
    TEACH_YES=1
    export TEACH_YES
  else
    echo "=== $(date '+%Y-%m-%d %H:%M') exam: gathering only ===" >> "$LOG"
    echo "Nothing will be marked. Double-click this file again and type yes to mark the exam."
    echo
    unset TEACH_YES
  fi
  exec "$GATHER"
fi

# From here on this is the second part, started by the gathering after it worked. It first says how
# many exam episodes have audio and a transcript; with none there is nothing to mark.
unset TEACH_AFTER TEACH_EXAM_STAGE TEACH_EXAM TEACH_PER_SHOW TEACH_MAX_GB
echo
python3 -u "$HERE/teach_exam.py" ready --folder "$FOLDER" 2>&1 | tee -a "$LOG"
READY="${PIPESTATUS[0]}"
[ "$READY" = 1 ] && finish "Nothing was marked, because no exam episode has audio and a transcript yet. Double-click this file again to gather more." 1
# Without that yes nothing is marked.
[ "$TEACH_YES" = 1 ] || finish "Nothing was marked, because no yes was given. Double-click this file again and type yes to mark the exam." 0
[ "$READY" = 0 ] || finish "Something is not set up (see above). Nothing was marked." 2

echo
echo "Marking the exam episodes, only between 11 at night and 7 in the morning. It waits for the"
echo "night, and for the usage allowance when it is used up (up to 120 hours). Keep the Mac"
echo "plugged in with the lid open."
echo
CAFFEINATE=()
command -v caffeinate > /dev/null && CAFFEINATE=(caffeinate -i)
set -o pipefail

echo "=== $(date '+%Y-%m-%d %H:%M') exam: marking ===" >> "$LOG"
echo "Step 1 of 2: marking the exam episodes (at most \$14 in all, over every run)" | tee -a "$LOG"
"${CAFFEINATE[@]}" python3 -u "$HERE/teach_label.py" --folder "$FOLDER" --only-exam --between 23-7 --wait-hours 120 --cap 14 --budget exam --yes 2>&1 | tee -a "$LOG"
CODE="${PIPESTATUS[0]}"
if [ "$CODE" != 0 ]; then
  report
  stopped "$CODE" 14 "The first marking"
fi

echo
echo "Step 2 of 2: marking 15 of the exam episodes a second time (at most \$4 in all, over every run)" | tee -a "$LOG"
"${CAFFEINATE[@]}" python3 -u "$HERE/teach_label.py" --folder "$FOLDER" --only-exam --labels labels-second --limit 15 --between 23-7 --wait-hours 120 --cap 4 --budget exam-second --yes 2>&1 | tee -a "$LOG"
CODE="${PIPESTATUS[0]}"
if [ "$CODE" != 0 ]; then
  report
  stopped "$CODE" 4 "The second marking"
fi

echo
report
if [ "${PIPESTATUS[0]}" = 0 ]; then
  finish "The exam is marked and kept apart from the learning."
fi
finish "Not everything is marked yet (see what is left above)." 3
