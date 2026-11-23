#!/bin/bash
# Double-click in Finder. Has Claude mark every advertisement and promotion in the transcribed
# teaching episodes (teach_label.py), then runs the steps after marking (teach-finish.sh): the
# snap (when there is a second download), habits, models, library, sounds, score, per-show
# settings and the copy to the phone's folders. Only
# the marking uses the Claude plan this Mac is signed in to (it shares its usage allowance), and it
# asks you to type yes before it starts. A stopped run carries on where it was when you double-click
# again. If you do not type yes, nothing else runs.
# (python3 -u keeps what it prints from being held back while it is also copied to the log.)
# Optional first argument: the name of another Claude model to use instead of the default one.
# Only one run can work in the folder at a time: marking and the steps after it each hold the
# folder's lock, and when marking finds another run busy the steps after it do not run.
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

echo "Storyteller Lofi: mark the ads in the teaching episodes"
echo
command -v python3 > /dev/null || finish "python3 is missing. Install Apple's command line tools: open Terminal and run xcode-select --install" 2
mkdir -p "$LOG_FOLDER" || finish "Could not make $LOG_FOLDER." 2

MODEL=()
[ -n "$1" ] && MODEL=(--model "$1")
# "Mark ads when the gathering is done" asks for the yes before it waits and sets TEACH_YES, so the
# marking does not ask a second time in the night.
YES=()
[ -n "$TEACH_YES" ] && YES=(--yes)

echo "=== $(date '+%Y-%m-%d %H:%M') mark ads ===" >> "$LOG"
caffeinate -i python3 -u "$HERE/teach_label.py" --folder "$FOLDER" "${MODEL[@]}" "${YES[@]}" 2>&1 | tee -a "$LOG"
CODE="${PIPESTATUS[0]}"

# You did not type yes: nothing was marked, so there is nothing to work out.
[ "$CODE" = 4 ] && finish "Nothing was marked, because you did not type yes. Double-click again and type yes to start." 0

# Marking did not start: something is not set up, or another run is working in the folder. The
# steps after marking must not run then.
if [ "$CODE" != 0 ] && [ "$CODE" != 3 ]; then
  finish "Something is not set up, or another run is working in the folder (see above). Nothing was marked and the steps after marking did not run." 2
fi

echo
echo "Now the steps after marking: habits, models, library, sounds, score, settings and the copy to the phone."
"$HERE/teach-finish.sh"
AFTER="$?"

[ "$AFTER" = 3 ] && finish "Another teaching run started while this one was marking, so the steps after marking did not run (see above). Double-click \"Teach the phone again\" when it is done." 2
[ "$CODE" = 0 ] && [ "$AFTER" != 0 ] && finish "The ads are marked, but not every step after it worked (see the summary above)." 2
case "$CODE" in
  0) finish "Done. The marks are in $FOLDER/labels and the results are in the phone's folders." ;;
  3) finish "It stopped early (see the last lines above). What was marked is saved and was used for the steps after it. Double-click again to carry on, for example after your usage allowance has reset." 3 ;;
esac
