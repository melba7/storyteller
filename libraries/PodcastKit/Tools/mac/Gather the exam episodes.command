#!/bin/bash
# Double-click in Finder. Gathers about 60 brand-new episodes and keeps them apart as an exam: the
# phone's learning never sees them (see teach_exam.py). It writes down what is said in them, then,
# when you type yes at the start, Claude marks the ads in them only at night (up to $14), and marks
# 15 of them a second time (up to $4) so we can see how much two markings differ. It does not run
# the steps that teach the phone: the exam teaches nothing, it is only to be scored.
# It asks once, at the start. If you do not type yes it only gathers. TEACH_YES=1 answers yes.
# It starts "Gather episodes for teaching" (with TEACH_EXAM=1 TEACH_PER_SHOW=2 TEACH_MAX_GB=46),
# which starts this file again, with TEACH_EXAM_STAGE=night, when the gathering worked. A stopped
# run carries on where it was when you double-click again.
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
  echo "several nights, using at most \$18 of the Claude plan's usage in all. It also marks 15 of"
  echo "them a second time, so we can see how much two markings differ."
  echo "The marking uses the Claude plan this Mac is signed in to and shares its usage allowance."
  echo "You can stop with Control-C and double-click this file again later to carry on."
  echo
  if [ "$TEACH_YES" = 1 ]; then
    TYPED=yes
  else
    read -r -p "Type yes to include the marking, or press Return to only gather: " TYPED
  fi
  TYPED="$(echo "$TYPED" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')"
  TEACH_EXAM=1
  TEACH_PER_SHOW=2
  TEACH_MAX_GB=46
  export TEACH_EXAM TEACH_PER_SHOW TEACH_MAX_GB
  if [ "$TYPED" = yes ]; then
    echo "=== $(date '+%Y-%m-%d %H:%M') exam: gathering, then the marking at night ===" >> "$LOG"
    TEACH_AFTER="$HERE/Gather the exam episodes.command"
    TEACH_EXAM_STAGE=night
    TEACH_YES=1
    export TEACH_AFTER TEACH_EXAM_STAGE TEACH_YES
  else
    echo "=== $(date '+%Y-%m-%d %H:%M') exam: gathering only ===" >> "$LOG"
    echo "Nothing will be marked. Double-click this file again and type yes to mark the exam."
    echo
    unset TEACH_AFTER TEACH_EXAM_STAGE TEACH_YES
  fi
  exec "$GATHER"
fi

# From here on this is the second part, started by the gathering after it worked (it always came
# with a typed yes). Without that yes nothing is marked.
[ "$TEACH_YES" = 1 ] || finish "Nothing was marked, because no yes was given." 0
unset TEACH_AFTER TEACH_EXAM_STAGE TEACH_EXAM TEACH_PER_SHOW TEACH_MAX_GB

echo
echo "Marking the exam episodes, only between 11 at night and 7 in the morning. It waits for the"
echo "night, and for the usage allowance when it is used up (up to 120 hours). Keep the Mac"
echo "plugged in with the lid open."
echo
CAFFEINATE=()
command -v caffeinate > /dev/null && CAFFEINATE=(caffeinate -i)
set -o pipefail

echo "=== $(date '+%Y-%m-%d %H:%M') exam: marking ===" >> "$LOG"
echo "Step 1 of 2: marking the exam episodes (at most \$14)" | tee -a "$LOG"
"${CAFFEINATE[@]}" python3 -u "$HERE/teach_label.py" --folder "$FOLDER" --only-exam --between 23-7 --wait-hours 120 --cap 14 --yes 2>&1 | tee -a "$LOG"
CODE="${PIPESTATUS[0]}"
if [ "$CODE" = 3 ]; then
  finish "It stopped early (see the last lines above). What was marked is saved. Double-click again to carry on, for example after your usage allowance has reset." 3
elif [ "$CODE" != 0 ]; then
  finish "Something is not set up, or another run is working in the folder (see above). Nothing more was marked." 2
fi

echo
echo "Step 2 of 2: marking 15 of the exam episodes a second time (at most \$4)" | tee -a "$LOG"
"${CAFFEINATE[@]}" python3 -u "$HERE/teach_label.py" --folder "$FOLDER" --only-exam --labels labels-second --limit 15 --between 23-7 --wait-hours 120 --cap 4 --yes 2>&1 | tee -a "$LOG"
CODE="${PIPESTATUS[0]}"
if [ "$CODE" = 3 ]; then
  finish "The second marking stopped early (see the last lines above). Double-click again to carry on, for example after your usage allowance has reset." 3
elif [ "$CODE" != 0 ]; then
  finish "The second marking did not work (see above)." 2
fi
finish "Done. The exam episodes are marked, 15 of them twice, and kept apart from the learning. The exam is ready to be scored."
