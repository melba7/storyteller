#!/bin/bash
# Double-click in Finder. Has Claude mark every advertisement and promotion in the transcribed
# teaching episodes (teach_label.py), then works out each show's habits (teach_habits.py). It uses
# the Claude plan this Mac is signed in to, shares its usage allowance, and asks you to type yes
# before it starts. A stopped run carries on where it was when you double-click again.
# (python3 -u keeps what it prints from being held back while it is also copied to the log.)
# Optional first argument: the name of another Claude model to use instead of the default one.
# Only one run can work in the folder at a time.
# What it prints is also added to ~/Storyteller Lofi/logs/podcast-teaching.log.
HERE="$(cd "$(dirname "$0")" && pwd)"
FOLDER="$HOME/Storyteller Lofi/PodcastTeaching"
LOG_FOLDER="$HOME/Storyteller Lofi/logs"
LOG="$LOG_FOLDER/podcast-teaching.log"

finish() {
  echo
  read -r -p "$1 Press Return to close this window. " _
  exit "${2:-0}"
}

echo "Storyteller Lofi: mark the ads in the teaching episodes"
echo
command -v python3 > /dev/null || finish "python3 is missing. Install Apple's command line tools: open Terminal and run xcode-select --install" 2
mkdir -p "$LOG_FOLDER" || finish "Could not make $LOG_FOLDER." 2

MODEL=()
[ -n "$1" ] && MODEL=(--model "$1")

echo "=== $(date '+%Y-%m-%d %H:%M') mark ads ===" >> "$LOG"
caffeinate -i python3 -u "$HERE/teach_label.py" --folder "$FOLDER" "${MODEL[@]}" 2>&1 | tee -a "$LOG"
CODE="${PIPESTATUS[0]}"

# You did not type yes: nothing was marked, so there is nothing to work out.
[ "$CODE" = 4 ] && finish "Nothing was marked, because you did not type yes. Double-click again and type yes to start." 0

echo
echo "=== $(date '+%Y-%m-%d %H:%M') habits ===" >> "$LOG"
python3 -u "$HERE/teach_habits.py" --folder "$FOLDER" 2>&1 | tee -a "$LOG"
HABITS="${PIPESTATUS[0]}"

[ "$CODE" = 0 ] && [ "$HABITS" != 0 ] && finish "The ads are marked, but the habits could not be worked out (see above)." 2
case "$CODE" in
  0) finish "Done. The marks are in $FOLDER/labels and the habits in $FOLDER/habits.json." ;;
  3) finish "It stopped early (see the last lines above). What was marked is saved. Double-click again to carry on, for example after your usage allowance has reset." 3 ;;
  *) finish "Something is not set up, or another run is working in the folder (see above). Nothing was marked." 2 ;;
esac
