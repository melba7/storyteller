#!/bin/bash
# Double-click in Finder. Gathers recent episodes of the shows you follow into
# ~/Storyteller Lofi/PodcastTeaching (step 1), then writes down what is said in them with the same
# Swift code the app uses (PodcastKit's podcast-transcribe, Apple's SpeechAnalyzer) (step 2). Needs
# macOS 26 and Xcode 26. Double-click it again to carry on where it stopped: finished downloads and
# finished transcripts are kept. Everything it prints is also added to
# ~/Storyteller Lofi/logs/podcast-teaching.log. Only one run can work in the folder at a time.
# (python3 -u keeps what it prints from being held back while it is also copied to the log.)
HERE="$(cd "$(dirname "$0")" && pwd)"
FOLDER="$HOME/Storyteller Lofi/PodcastTeaching"
LOG="$HOME/Storyteller Lofi/logs/podcast-teaching.log"

finish() {
  echo
  read -r -p "$1 Press Return to close this window. " _
  exit "${2:-0}"
}

command -v python3 > /dev/null || finish "python3 is missing. Install Apple's command line tools: open Terminal and run xcode-select --install" 1
mkdir -p "$(dirname "$LOG")" || finish "Could not make the folder for the log." 1
# Everything below is shown here and added to the log; pipefail keeps the Python exit codes.
set -o pipefail

echo "Storyteller Lofi: gather episodes for teaching"
echo
echo "Step 1 downloads recent episodes of your shows, up to 12 GB, into:"
echo "  $FOLDER"
echo "Step 2 writes down what is said in them. It can take hours."
echo "Keep the Mac plugged in with the lid open. You can stop with Control-C and double-click"
echo "this file again later to carry on."
echo

echo "Step 1 of 2: downloading episodes" | tee -a "$LOG"
caffeinate -i python3 -u "$HERE/teach_collect.py" --folder "$FOLDER" 2>&1 | tee -a "$LOG"
CODE="$?"
# 3 means the size limit on all kept audio stopped the downloads. That is not a failure: what is
# on disk still gets written down.
if [ "$CODE" -eq 3 ]; then
  echo "The size limit is reached, so nothing more is downloaded. Step 2 goes on with what is on disk." | tee -a "$LOG"
elif [ "$CODE" -ne 0 ]; then
  finish "Step 1 did not work (see above)." 1
fi

echo
echo "Step 2 of 2: writing down what is said" | tee -a "$LOG"
KIT=""
for CANDIDATE in "$HERE/../.." "$HOME/Storyteller Lofi/testflight-build/libraries/PodcastKit"; do
  if [ -f "$CANDIDATE/Package.swift" ]; then
    KIT="$(cd "$CANDIDATE" && pwd)"
    break
  fi
done
[ -n "$KIT" ] || finish "Could not find PodcastKit (no Package.swift next to these tools or in testflight-build)." 1
command -v swift > /dev/null || finish "swift is missing (install Xcode 26 from the App Store)." 1

cd "$KIT" || finish "Could not open $KIT." 1
echo "Building the transcriber (this takes a minute the first time)..."
swift build -c release --product podcast-transcribe 2>&1 | tee -a "$LOG"
if [ "$?" -ne 0 ]; then
  finish "The transcriber did not build (see above)." 1
fi
TOOL="$(swift build -c release --show-bin-path)/podcast-transcribe"

caffeinate -i python3 -u "$HERE/teach_transcribe.py" --folder "$FOLDER" --tool "$TOOL" 2>&1 | tee -a "$LOG"
CODE="$?"
if [ "$CODE" -eq 3 ]; then
  finish "Step 2 stopped early because several episodes in a row failed (see above). Fix that, then double-click again to carry on." 1
elif [ "$CODE" -ne 0 ]; then
  finish "Step 2 did not work (see above)." 1
fi
finish "Done: the episodes are in $FOLDER and written down. Double-click again to carry on with new ones."
