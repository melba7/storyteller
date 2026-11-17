#!/bin/bash
# Double-click in Finder. Asks for a transcript ("<hash>.transcript.json" from the app's
# download folder, or one made by "Transcribe an episode") or an audio file, finds the ads with
# the same Swift code the app uses (PodcastKit's podcast-ads, Apple's on-device model), and
# saves them as "<file name>.ads.txt" next to the file. Needs macOS 26 with Apple Intelligence
# turned on, and Xcode 26. Building takes a minute; an audio file is transcribed first.
set -o pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
KIT="$(cd "$HERE/../.." && pwd)"

finish() {
  echo
  read -r -p "$1 Press Return to close this window. " _
  exit "${2:-0}"
}

echo "Storyteller Lofi: find the ads in an episode"
echo
command -v swift > /dev/null || finish "swift is missing (install Xcode 26 from the App Store)." 1
FILE="$(osascript -e 'POSIX path of (choose file with prompt "Choose a transcript (.transcript.json) or an episode")' 2> /dev/null)"
[ -n "$FILE" ] || finish "No file chosen." 1

OUT="$FILE.ads.txt"
echo "Finding ads in: $FILE"
echo "(each piece of about ten minutes takes the model a few seconds)"
echo
cd "$KIT" || finish "Could not open $KIT." 1
if swift run -c release podcast-ads "$FILE" | tee "$OUT.part"; then
  mv "$OUT.part" "$OUT"
  echo
  echo "Saved: $OUT"
  open -R "$OUT"
  finish "Done."
else
  rm -f "$OUT.part"
  finish "It did not work (see above)." 1
fi
