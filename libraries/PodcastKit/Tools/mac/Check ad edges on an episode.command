#!/bin/bash
# Double-click in Finder. Asks for an audio file and finds out where an ad skip starts and ends and
# why: it transcribes the episode, finds the ads with the same Swift code the app uses (PodcastKit's
# podcast-ads --edges, Apple's on-device model), and for each ad prints what the model said, what
# each clean-up step did to the start and end, and the lines of speech around each edge. It then
# says whether the transcript's word times show pauses and, for an MP3 file, whether the file's
# bitrate is steady (Apple's player can seek to the wrong place when it is not) and where the
# encoding changes. The result is saved as "<file name>.ad-edges.txt" next to the file. If a file
# named "<file name>.truth.txt" sits next to the episode (one ad to a line, as two times such as
# 12:30 13:45), the skips are also compared with those marks. Needs macOS 26 with Apple
# Intelligence turned on, and Xcode 26. Building takes a minute; the whole episode is processed,
# so allow a few minutes. Nothing is sent anywhere and no audio is kept.
set -o pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
KIT="$(cd "$HERE/../.." && pwd)"

finish() {
  echo
  read -r -p "$1 Press Return to close this window. " _
  exit "${2:-0}"
}

echo "Storyteller Lofi: check ad edges on an episode"
echo
command -v swift > /dev/null || finish "swift is missing (install Xcode 26 from the App Store)." 1
FILE="$(osascript -e 'POSIX path of (choose file with prompt "Choose the episode (an audio file) to check")' 2> /dev/null)"
[ -n "$FILE" ] || finish "No file chosen." 1

OUT="$FILE.ad-edges.txt"
TRUTH="$FILE.truth.txt"
ARGS=(--edges)
if [ -f "$TRUTH" ]; then
  echo "Comparing with the ads marked in: $TRUTH"
  ARGS+=(--truth "$TRUTH")
fi
echo "Checking: $FILE"
echo "(the whole episode is transcribed and checked; the progress is shown below)"
echo
cd "$KIT" || finish "Could not open $KIT." 1
if swift run -c release podcast-ads "${ARGS[@]}" "$FILE" | tee "$OUT.part"; then
  mv "$OUT.part" "$OUT"
  echo
  echo "Saved: $OUT"
  open -R "$OUT"
  finish "Done. Send the file back."
else
  rm -f "$OUT.part"
  finish "It did not work (see above)." 1
fi
