#!/bin/bash
# Double-click in Finder. Asks for two different episodes of one show (two MP3 files) and finds
# out whether a spot that comes back in both, such as the ad every episode opens with, is the very
# same bytes in both files. If it is, the host copies an ad's audio as it is, and a spot heard once
# could be known again from its first half second, with its start and end exact to a frame. It
# runs PodcastKit's podcast-ads --shared, which cuts both files into MP3 frames and lists the
# stretches that are the same in both, with their times in each file and whether the file's
# encoding changes at each edge. The result is saved in ~/Storyteller Lofi/logs as
# "ad-shared-<name of the first file>-<time>.txt". It needs no Apple Intelligence and no network,
# only Xcode 26 to build. It reads the two files and keeps nothing else; nothing is sent anywhere.
set -o pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
KIT="$(cd "$HERE/../.." && pwd)"
LOGS="$HOME/Storyteller Lofi/logs"

finish() {
  echo
  read -r -p "$1 Press Return to close this window. " _
  exit "${2:-0}"
}

echo "Storyteller Lofi: compare two episodes of a show"
echo
echo "Choose two different episodes of the same show, ideally two that open with the same"
echo "kind of ad. This only reads the two files."
echo
command -v swift > /dev/null || finish "swift is missing (install Xcode 26 from the App Store)." 1
FIRST="$(osascript -e 'POSIX path of (choose file with prompt "Choose the first episode (an MP3 file)")' 2> /dev/null)"
[ -n "$FIRST" ] || finish "No file chosen." 1
SECOND="$(osascript -e 'POSIX path of (choose file with prompt "Now choose a second, different episode of the same show (an MP3 file)")' 2> /dev/null)"
[ -n "$SECOND" ] || finish "No second file chosen." 1
if [ "$FIRST" = "$SECOND" ] || cmp -s "$FIRST" "$SECOND"; then
  finish "Those are the same episode. Start again and choose two different ones." 1
fi

mkdir -p "$LOGS"
NAME="$(basename "$FIRST" | sed 's/\.[^.]*$//' | tr -c 'A-Za-z0-9\n' '-' | cut -c1-30)"
OUT="$LOGS/ad-shared-${NAME:-episode}-$(date +%Y%m%d-%H%M%S).txt"
echo "Comparing:"
echo "  $FIRST"
echo "  $SECOND"
echo
cd "$KIT" || finish "Could not open $KIT." 1
if swift run -c release podcast-ads --shared "$FIRST" "$SECOND" | tee "$OUT.part"; then
  mv "$OUT.part" "$OUT"
  echo
  echo "Saved: $OUT"
  open -R "$OUT"
  finish "Done. Send the file back."
else
  rm -f "$OUT.part"
  finish "It did not work (see above)." 1
fi
