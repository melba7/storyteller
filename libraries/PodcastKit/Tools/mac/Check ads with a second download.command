#!/bin/bash
# Double-click in Finder. Checks Claude's ad marks against a second download of each episode.
# Hosts that put ads into a download give two listeners different ads, so the stretches where two
# downloads of one episode differ are the ads the host put in, exact to a frame. For up to 40
# episodes Claude has marked (and 3 GB of traffic) in one run, this downloads the audio a second
# time from the episode's own address (teach_copies.py, with PodcastKit's podcast-ads
# --truth-from-copies, built here with Xcode 26), keeps what differs in the teaching folder's
# copies folder and deletes the second copy at once. Then it writes labels-snapped (teach_snap.py):
# Claude's labels with their borders moved onto those stretches. Claude's own labels are never
# changed. It needs no key, uses no Claude allowance and sends nothing but the audio requests. To
# a publisher a second download looks like a second listener, so it is bounded and only for marked
# episodes: do not run it over and over. An episode that was compared is not downloaded again, so
# double-clicking again carries on with the next ones. Afterwards double-click "Teach the phone
# again" so the model, the sounds and the score use the snapped labels.
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

echo "Storyteller Lofi: check ads with a second download"
echo
command -v python3 > /dev/null || finish "python3 is missing. Install Apple's command line tools: open Terminal and run xcode-select --install" 1
mkdir -p "$LOG_FOLDER" || finish "Could not make $LOG_FOLDER." 1
# Everything below is shown here and added to the log; pipefail keeps the Python exit codes.
set -o pipefail

echo "This downloads each marked episode a second time (up to 40 episodes and 3 GB in one run) from"
echo "its own address, compares the two files and deletes the second one. It uses no Claude allowance."
echo "You can stop with Control-C; the second copy is deleted and what was done is kept."
echo

KIT=""
for CANDIDATE in "$HERE/../.." "$HOME/Storyteller Lofi/testflight-build/libraries/PodcastKit"; do
  if [ -f "$CANDIDATE/Package.swift" ]; then
    KIT="$(cd "$CANDIDATE" && pwd)"
    break
  fi
done
[ -n "$KIT" ] || finish "Could not find PodcastKit (no Package.swift next to these tools or in testflight-build)." 1
command -v swift > /dev/null || finish "swift is missing (install Xcode 26 from the App Store)." 1

echo "=== $(date '+%Y-%m-%d %H:%M') second downloads ===" >> "$LOG"
cd "$KIT" || finish "Could not open $KIT." 1
echo "Building the comparing tool (this takes a minute the first time)..."
swift build -c release --product podcast-ads 2>&1 | tee -a "$LOG"
[ "${PIPESTATUS[0]}" -ne 0 ] && finish "The comparing tool did not build (see above)." 1
TOOL="$(swift build -c release --show-bin-path)/podcast-ads"

CAFFEINATE=""
command -v caffeinate > /dev/null && CAFFEINATE="caffeinate -i"

echo
echo "Step 1 of 2: downloading and comparing" | tee -a "$LOG"
$CAFFEINATE python3 -u "$HERE/teach_copies.py" --folder "$FOLDER" --tool "$TOOL" 2>&1 | tee -a "$LOG"
COPIES="${PIPESTATUS[0]}"
# 3 means a limit of this run (episodes or traffic) was reached with episodes waiting. That is not a
# failure: what was compared still gets snapped, and double-clicking again does the next ones.
case "$COPIES" in
  0 | 3) ;;
  1) finish "It stopped because several downloads in a row failed (see above). What was compared is kept. Fix that, then double-click this again." 1 ;;
  2) finish "Something is not set up, or another run is working in the folder (see above). Nothing was downloaded." 2 ;;
  *) finish "The second downloads did not work (see above)." 1 ;;
esac

echo
echo "Step 2 of 2: moving the borders of Claude's labels onto what differs" | tee -a "$LOG"
# teach_snap.py takes no lock of its own (teach-finish.sh holds it), so it runs under the folder's lock.
python3 -u "$HERE/teach_store.py" hold "$FOLDER" python3 -u "$HERE/teach_snap.py" --folder "$FOLDER" 2>&1 | tee -a "$LOG"
SNAP="${PIPESTATUS[0]}"
case "$SNAP" in
  0) ;;
  2) finish "The labels could not be snapped (see above). If there are none yet, double-click \"Mark ads in the teaching episodes\" first." 2 ;;
  3) finish "Another teaching run started while this one worked, so the snapped labels were not written (see above). What was compared is kept. Double-click this again when it is done." 2 ;;
  *) finish "Snapping the labels did not work (see above)." 1 ;;
esac

if [ "$COPIES" = 3 ]; then
  finish "A limit of this run was reached, so more episodes are waiting. The snapped labels are in $FOLDER/labels-snapped (Claude's own labels are unchanged). Double-click this again to compare the next ones, then double-click \"Teach the phone again\"." 3
fi
finish "Done. The snapped labels are in $FOLDER/labels-snapped (Claude's own labels are unchanged). Double-click \"Teach the phone again\" next, so the model, the sounds and the score use them."
