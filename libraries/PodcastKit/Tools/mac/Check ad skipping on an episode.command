#!/bin/bash
# Double-click in Finder. Asks for an audio file and does what the phone does for an episode
# that is playing: transcribes it piece by piece, looks for ads after each piece, and times every
# step on this Mac (PodcastKit's podcast-ads --play, Apple's on-device model). It says for each ad
# whether a listener who pressed play at 0:00 would have had it skipped, and saves the result as
# "<file name>.ad-check.txt" next to the file. Needs macOS 26 with Apple Intelligence turned on,
# and Xcode 26. Building takes a minute; the whole episode is processed, so allow a few minutes.
set -o pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
KIT="$(cd "$HERE/../.." && pwd)"

finish() {
  echo
  read -r -p "$1 Press Return to close this window. " _
  exit "${2:-0}"
}

echo "Storyteller Lofi: check ad skipping on an episode"
echo
command -v swift > /dev/null || finish "swift is missing (install Xcode 26 from the App Store)." 1
FILE="$(osascript -e 'POSIX path of (choose file with prompt "Choose the episode (an audio file) to check")' 2> /dev/null)"
[ -n "$FILE" ] || finish "No file chosen." 1

OUT="$FILE.ad-check.txt"
echo "Checking: $FILE"
echo "(the whole episode is transcribed and checked; the progress is shown below)"
echo
cd "$KIT" || finish "Could not open $KIT." 1
if swift run -c release podcast-ads --play "$FILE" | tee "$OUT.part"; then
  mv "$OUT.part" "$OUT"
  echo
  echo "Saved: $OUT"
  open -R "$OUT"
  finish "Done."
else
  rm -f "$OUT.part"
  finish "It did not work (see above)." 1
fi
