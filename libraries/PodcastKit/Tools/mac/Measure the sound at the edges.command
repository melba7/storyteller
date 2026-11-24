#!/bin/bash
# Double-click in Finder. Builds the podcast-teach tool (Swift, needs Xcode 26) and has it measure the
# sound at the edges of the ad spots the second download placed exactly (podcast-teach edges): for every
# shelf episode of the teaching folder it reads the sound once, finds where the sound changes most, and
# says how often that lies within a second of an exact ad edge, against random points, and whether
# that meets the plan's go rule. The change peaks are kept in edges.json and the numbers in
# edges-report.json, both in ~/Storyteller Lofi/PodcastTeaching. It costs nothing and does not use your
# Claude plan's usage allowance, but it reads about 50 hours of sound, so it may take an hour. Each
# episode is kept as soon as it is read, so you can close this window and double-click this file again
# to carry on where it was.
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

echo "Storyteller Lofi: measure the sound at the edges"
echo
echo "This costs nothing and uses no Claude allowance. It may take an hour."
echo "You can close this window and double-click it again to carry on."
echo
mkdir -p "$LOG_FOLDER" || finish "Could not make $LOG_FOLDER." 1
# Everything below is shown here and added to the log; pipefail keeps the exit codes.
set -o pipefail

KIT=""
for CANDIDATE in "$HERE/../.." "$HOME/Storyteller Lofi/testflight-build/libraries/PodcastKit"; do
  if [ -f "$CANDIDATE/Package.swift" ]; then
    KIT="$(cd "$CANDIDATE" && pwd)"
    break
  fi
done
[ -n "$KIT" ] || finish "Could not find PodcastKit (no Package.swift next to these tools or in testflight-build)." 1
command -v swift > /dev/null || finish "swift is missing (install Xcode 26 from the App Store)." 1
[ -d "$FOLDER" ] || finish "There is no teaching folder at $FOLDER. Gather, transcribe and mark some episodes first." 2

echo "=== $(date '+%Y-%m-%d %H:%M') edges ===" >> "$LOG"
cd "$KIT" || finish "Could not open $KIT." 1
echo "Building the tool (this takes a minute the first time)..."
swift build -c release --product podcast-teach 2>&1 | tee -a "$LOG"
[ "$?" -ne 0 ] && finish "The tool did not build (see above)." 1
TOOL="$(swift build -c release --show-bin-path)/podcast-teach"

echo
CAFFEINATE=""
command -v caffeinate > /dev/null && CAFFEINATE="caffeinate -i"
$CAFFEINATE "$TOOL" edges "$FOLDER" 2>&1 | tee -a "$LOG"
CODE="${PIPESTATUS[0]}"
case "$CODE" in
  0) finish "Done. The numbers are above and in $FOLDER/edges-report.json; the change peaks are in $FOLDER/edges.json. Tell Claude what the verdict line says." ;;
  2) finish "The sound was not measured. The reason is in what the tool printed above: the teaching folder may have no shelf (double-click \"Teach the phone again\"), no labels-snapped folder (double-click \"Check ads with a second download\"), or a file in it may be damaged." 2 ;;
  *) finish "Some episodes could not be read (see above). Double-click this again to try those once more. The numbers above leave them out." 1 ;;
esac
