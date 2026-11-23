#!/bin/bash
# Double-click in Finder. Builds the podcast-teach tool (Swift, needs Xcode 26) and has it ask Apple's
# on-device model about each test episode of the teaching folder (podcast-teach apple). The answers
# are kept in apple-model.json in ~/Storyteller Lofi/PodcastTeaching, and the next "Score the ad
# skipping" shows them as one more row. It costs nothing and does not use your Claude plan's usage
# allowance, but it may take a few hours. Each answer is saved at once, so you can close this window
# and double-click this file again to carry on where it was.
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

echo "Storyteller Lofi: ask Apple's model about the test episodes"
echo
echo "This costs nothing and uses no Claude allowance. It may take a few hours."
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

echo "=== $(date '+%Y-%m-%d %H:%M') apple ===" >> "$LOG"
cd "$KIT" || finish "Could not open $KIT." 1
echo "Building the tool (this takes a minute the first time)..."
swift build -c release --product podcast-teach 2>&1 | tee -a "$LOG"
[ "$?" -ne 0 ] && finish "The tool did not build (see above)." 1
TOOL="$(swift build -c release --show-bin-path)/podcast-teach"

echo
CAFFEINATE=""
command -v caffeinate > /dev/null && CAFFEINATE="caffeinate -i"
$CAFFEINATE "$TOOL" apple "$FOLDER" 2>&1 | tee -a "$LOG"
CODE="${PIPESTATUS[0]}"
case "$CODE" in
  0) finish "Done. The answers are in $FOLDER/apple-model.json. Double-click \"Score the ad skipping\" to see them." ;;
  2) finish "Apple's model could not be asked (see above). It needs macOS 26 with Apple Intelligence on." 2 ;;
  *) finish "Some episodes could not be asked (see above). Double-click this again to try those once more." 1 ;;
esac
