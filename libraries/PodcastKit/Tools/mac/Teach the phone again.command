#!/bin/bash
# Double-click in Finder. Teaches the phone again from what has been marked so far, without marking
# anything new. It reads the notes the phone wrote while you listened (teach_feedback.py), which
# gives the next "Gather episodes for teaching" a list of episodes to fetch first, and then runs
# the steps after marking (teach-finish.sh): the snap to the second download (when there is one),
# the habits, the model, the library, the sounds, the meaning model, the score, the per-show
# settings and the copy to the phone's folders. It does not use your Claude plan's usage allowance.
# (python3 -u keeps what it prints from being held back while it is also copied to the log.)
# What it prints is also added to ~/Storyteller Lofi/logs/podcast-teaching.log.
HERE="$(cd "$(dirname "$0")" && pwd)"
FOLDER="$HOME/Storyteller Lofi/PodcastTeaching"
LOG_FOLDER="$HOME/Storyteller Lofi/logs"
LOG="$LOG_FOLDER/podcast-teaching.log"

finish() {
  echo
  echo "$1"
  read -r -p "Press Return to close this window. " _
  exit "${2:-0}"
}

echo "Storyteller Lofi: teach the phone again"
echo
command -v python3 > /dev/null || finish "python3 is missing. Install Apple's command line tools: open Terminal and run xcode-select --install" 2
mkdir -p "$LOG_FOLDER" || finish "Could not make $LOG_FOLDER." 2
# Everything below is shown here and added to the log; pipefail keeps the Python exit codes.
set -o pipefail

python3 -u "$HERE/teach_store.py" busy "$FOLDER" > /dev/null 2>&1
if [ "$?" = 3 ]; then
  finish "Another teaching run is already working in the teaching folder, so nothing was done. Wait for it to finish (or close its window), then double-click this again." 1
fi

echo "This does not use your Claude usage allowance: nothing new is marked."
echo "It reads what the phone noted, then works out the habits, trains the models, makes the"
echo "library and the sounds, scores the ad skipping, chooses the per-show settings and copies the"
echo "results to the phone's folders."
echo

echo "=== $(date '+%Y-%m-%d %H:%M') phone notes ===" >> "$LOG"
echo "Reading the phone's notes"
python3 -u "$HERE/teach_feedback.py" --folder "$FOLDER" 2>&1 | tee -a "$LOG"
NOTES="${PIPESTATUS[0]}"
[ "$NOTES" != 0 ] && echo "The phone's notes could not be used (see above). The other steps still run."

echo
"$HERE/teach-finish.sh"
AFTER="$?"

[ "$AFTER" = 3 ] && finish "Another teaching run started while this one worked, so the steps after marking did not run (see above). Wait for it to finish and double-click this again." 1
[ "$AFTER" != 0 ] && finish "Not every step worked (see the summary above)." 1
[ "$NOTES" != 0 ] && finish "The results are in the phone's folders, but the phone's notes could not be used (see above)." 1
finish "Done. The results are in the phone's folders."
