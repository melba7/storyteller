#!/bin/bash
# Double-click in Finder. Tests whether the model that spots ads does better on the held-out shelf (the
# episodes of your own shows that it is never trained on) when it also learns from the marked public
# transcripts ("Mark the public transcripts"). It trains the model twice in scratch folders of links,
# once on your teaching folder alone and once with the public marks added, with the same settings the
# steps after marking use, and prints both models' precision and recall side by side. It uses no Claude
# usage, downloads nothing, writes nothing in your teaching folder or the public folder (the results
# are in ~/Storyteller Lofi/PodcastTeachingPublicTest) and does not change the model on the phone.
# Needs Xcode 26 to build the tool that fits the model, and takes a few minutes of Mac time for each of
# the two trainings. Run it after "Mark the public transcripts" has marked some episodes; the more
# are marked, the better the test. What it prints is also added to ~/Storyteller Lofi/logs/podcast-teaching.log.
HERE="$(cd "$(dirname "$0")" && pwd)"
BASE="$HOME/Storyteller Lofi"
FOLDER="$BASE/PodcastTeaching"
PUBLIC="$BASE/PodcastTeachingSporc"
WORK="$BASE/PodcastTeachingPublicTest"
LOG_FOLDER="$BASE/logs"
LOG="$LOG_FOLDER/podcast-teaching.log"

finish() {
  echo
  echo "$1"
  # TEACH_CHAIN=1 means "Fetch, mark and test the public transcripts" is running this step: it shows the message and carries on.
  [ "${TEACH_CHAIN:-}" = 1 ] || read -r -p "Press Return to close this window. " _
  exit "${2:-0}"
}

echo "Storyteller Lofi: test the public marks"
echo
command -v python3 > /dev/null || finish "python3 is missing. Install Apple's command line tools: open Terminal and run xcode-select --install" 2
command -v swift > /dev/null || finish "swift is missing (install Xcode 26 from the App Store)." 1
[ -f "$PUBLIC/episodes.json" ] || finish "There is no public sample yet. Double-click \"Fetch a sample of public transcripts\" and \"Mark the public transcripts\" first." 2
[ -d "$PUBLIC/labels" ] || finish "No public transcript is marked yet. Double-click \"Mark the public transcripts\" first." 2
mkdir -p "$LOG_FOLDER" || finish "Could not make $LOG_FOLDER." 2

KIT=""
for CANDIDATE in "$HERE/../.." "$BASE/testflight-build/libraries/PodcastKit"; do
  if [ -f "$CANDIDATE/Package.swift" ]; then
    KIT="$(cd "$CANDIDATE" && pwd)"
    break
  fi
done
[ -n "$KIT" ] || finish "Could not find PodcastKit (no Package.swift next to these tools or in testflight-build)." 1
echo "Building the tool that fits the model (this takes a minute the first time)..."
(cd "$KIT" && swift build -c release --product podcast-teach 2>&1 | tee -a "$LOG"; exit "${PIPESTATUS[0]}") || finish "The tool did not build (see above)." 1
TOOL="$(cd "$KIT" && swift build -c release --show-bin-path)/podcast-teach"

LABELS=labels
[ -d "$FOLDER/labels-snapped" ] && LABELS=labels-snapped
echo "=== $(date '+%Y-%m-%d %H:%M') test the public marks (labels: $LABELS) ===" >> "$LOG"
caffeinate -i python3 -u "$HERE/teach_public_compare.py" --folder "$FOLDER" --public "$PUBLIC" --work "$WORK" --labels "$LABELS" --fit-tool "$TOOL" 2>&1 | tee -a "$LOG"
CODE="${PIPESTATUS[0]}"
[ "$CODE" = 0 ] || finish "The test did not finish (see above)." "$CODE"
finish "Done. The table is in $WORK/COMPARE.txt. Tell Claude it is finished." 0
