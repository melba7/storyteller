#!/bin/bash
# Double-click in Finder. Writes down the time of each word for the 63 shelf episodes again (only
# the side files transcripts/<id>.words.json; the transcripts and the marks are never changed), and
# then scores Claude's label edges against the exact edges from the second downloads, before and
# after, within 1, 2 and 5 seconds (teach_words.py, teach_end_score.py). The result is saved as
# end-edges.json in the teaching folder. Needs Xcode 26 for the transcriber. It uses the Mac's own
# speech recognition: no Claude allowance, no key and no money, and nothing is sent anywhere. An
# episode that has its side file is skipped, so a stopped run carries on where it was. Set
# TEACH_WORDS_ALL=1 to take every episode that has audio, not only the shelf.
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

echo "Storyteller Lofi: write down the word times again"
echo
command -v python3 > /dev/null || finish "python3 is missing. Install Apple's command line tools: open Terminal and run xcode-select --install" 2
command -v swift > /dev/null || finish "swift is missing (install Xcode 26 from the App Store)." 1
mkdir -p "$LOG_FOLDER" || finish "Could not make $LOG_FOLDER." 2
[ -d "$FOLDER" ] || finish "There is no teaching folder at $FOLDER." 2
set -o pipefail

KIT=""
for CANDIDATE in "$HERE/../.." "$HOME/Storyteller Lofi/testflight-build/libraries/PodcastKit"; do
  if [ -f "$CANDIDATE/Package.swift" ]; then
    KIT="$(cd "$CANDIDATE" && pwd)"
    break
  fi
done
[ -n "$KIT" ] || finish "Could not find PodcastKit (no Package.swift next to these tools or in testflight-build)." 1
cd "$KIT" || finish "Could not open $KIT." 1

echo "=== $(date '+%Y-%m-%d %H:%M') word times ===" >> "$LOG"
echo "Building the transcriber (this takes a minute the first time)..."
swift build -c release --product podcast-transcribe 2>&1 | tee -a "$LOG"
[ "${PIPESTATUS[0]}" = 0 ] || finish "The transcriber did not build (see above)." 1
TOOL="$(swift build -c release --show-bin-path)/podcast-transcribe"

ALL=""
[ "$TEACH_WORDS_ALL" = 1 ] && ALL="--all"
echo "Writing down the word times (a stopped run carries on where it was)..."
caffeinate -i python3 -u "$HERE/teach_words.py" --folder "$FOLDER" --tool "$TOOL" $ALL 2>&1 | tee -a "$LOG"
CODE="${PIPESTATUS[0]}"
[ "$CODE" = 0 ] || finish "Writing down the word times did not finish (see above). Double-click again to carry on." 2

echo
echo "Scoring Claude's label edges against the exact edges..."
python3 -u "$HERE/teach_end_score.py" --folder "$FOLDER" 2>&1 | tee -a "$LOG"
[ "${PIPESTATUS[0]}" = 0 ] || finish "The edges could not be scored (see above)." 2
finish "Done. The numbers are in $FOLDER/end-edges.json."
