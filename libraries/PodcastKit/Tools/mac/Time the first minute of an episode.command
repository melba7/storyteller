#!/bin/bash
# Double-click in Finder. Asks for an audio file and times what the phone must do to check the
# first minute and a half of a stream: the speech model getting ready, the first words, the
# head transcript and the ad model's first answer. It runs everything twice in one go (cold,
# then warm) with PodcastKit's podcast-ads --head 90 --timings, and saves the result as
# "<file name>.head-timings.txt" next to the file. Needs macOS 26 with Apple Intelligence turned
# on, and Xcode 26. Building takes a minute; the check itself takes under a minute.
set -o pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
KIT="$(cd "$HERE/../.." && pwd)"

finish() {
  echo
  read -r -p "$1 Press Return to close this window. " _
  exit "${2:-0}"
}

echo "Storyteller Lofi: time the first minute of an episode"
echo
command -v swift > /dev/null || finish "swift is missing (install Xcode 26 from the App Store)." 1
FILE="$(osascript -e 'POSIX path of (choose file with prompt "Choose an episode (an audio file) to time")' 2> /dev/null)"
[ -n "$FILE" ] || finish "No file chosen." 1

OUT="$FILE.head-timings.txt"
echo "Timing the first 90 seconds of: $FILE"
echo
cd "$KIT" || finish "Could not open $KIT." 1
if swift run -c release podcast-ads --head 90 --timings "$FILE" | tee "$OUT.part"; then
  mv "$OUT.part" "$OUT"
  echo
  echo "Saved: $OUT"
  echo
  echo "How to read it: each time is seconds since that run started. 'Run 1' is the first time the"
  echo "app would do this after opening (cold); 'Run 2' is the next time (warm). The last line of a"
  echo "run, the model's first answer, is how long the first 90 s of a stream take to check. Under"
  echo "10 s on this Mac is good. A phone is slower than a Mac, so treat this as the best case."
  open -R "$OUT"
  finish "Done."
else
  rm -f "$OUT.part"
  finish "It did not work (see above)." 1
fi
