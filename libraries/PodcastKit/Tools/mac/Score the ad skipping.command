#!/bin/bash
# Double-click in Finder. Builds the podcast-teach tool (Swift, needs Xcode 26) and has it score the
# ad skipping on the teaching folder (podcast-teach score): the report it prints is what this
# window shows, and it is added to scorecard.json in ~/Storyteller Lofi/PodcastTeaching. It does
# not use your Claude plan's usage allowance.
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

echo "Storyteller Lofi: score the ad skipping"
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

echo "=== $(date '+%Y-%m-%d %H:%M') score ===" >> "$LOG"
cd "$KIT" || finish "Could not open $KIT." 1
echo "Building the scoring tool (this takes a minute the first time)..."
swift build -c release --product podcast-teach 2>&1 | tee -a "$LOG"
[ "$?" -ne 0 ] && finish "The scoring tool did not build (see above)." 1
TOOL="$(swift build -c release --show-bin-path)/podcast-teach"

echo
"$TOOL" score "$FOLDER" 2>&1 | tee -a "$LOG"
CODE="${PIPESTATUS[0]}"
case "$CODE" in
  0) finish "Done. The scorecard is above, and added to $FOLDER/scorecard.json." ;;
  2) finish "The scoring is not set up (see above). Gather, transcribe and mark some episodes first." 2 ;;
  *) finish "The scoring did not work (see above)." 1 ;;
esac
