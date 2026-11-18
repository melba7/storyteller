#!/bin/bash
# Double-click in Finder. Asks for an episode's audio address (or takes it from the clipboard),
# downloads its first 3 MB twice with two different User-Agents, and prints where the two copies
# differ: those stretches are candidate inserted ads. It runs PodcastKit's podcast-ads --probe
# and saves the result in ~/Storyteller Lofi/logs. It needs no keys and no Apple Intelligence,
# only Xcode 26 to build. It saves no audio. To the show's publisher the second download looks
# like a second listener, so do not run it over and over on the same episode.
set -o pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
KIT="$(cd "$HERE/../.." && pwd)"
LOGS="$HOME/Storyteller Lofi/logs"

finish() {
  echo
  read -r -p "$1 Press Return to close this window. " _
  exit "${2:-0}"
}

echo "Storyteller Lofi: compare two downloads of an episode"
echo
command -v swift > /dev/null || finish "swift is missing (install Xcode 26 from the App Store)." 1
ADDRESS="$(pbpaste 2> /dev/null | head -n 1 | tr -d '[:space:]')"
case "$ADDRESS" in
  http://* | https://*) echo "Using the address on the clipboard." ;;
  *)
    ADDRESS="$(osascript -e 'text returned of (display dialog "Paste the episode audio address (the .mp3 link from the show feed)" default answer "")' 2> /dev/null | tr -d '[:space:]')"
    ;;
esac
case "$ADDRESS" in
  http://* | https://*) ;;
  *) finish "No web address given." 1 ;;
esac

mkdir -p "$LOGS"
OUT="$LOGS/ad-probe-$(date +%Y%m%d-%H%M%S).txt"
cd "$KIT" || finish "Could not open $KIT." 1
if swift run -c release podcast-ads --probe "$ADDRESS" | tee "$OUT"; then
  echo
  echo "Saved: $OUT"
  echo
  echo "How to read it: 'host after redirects' says who serves the audio. 'Byte for byte the same'"
  echo "means that host gave both listeners one file, so there is nothing to compare. Ranges listed"
  echo "as differing are where the copies had different audio and then joined again: candidate"
  echo "inserted ads. 'Share no frame' means the host re-encodes each download, and this trick"
  echo "cannot work there."
  open -R "$OUT"
  finish "Done."
else
  finish "It did not work (see above)." 1
fi
