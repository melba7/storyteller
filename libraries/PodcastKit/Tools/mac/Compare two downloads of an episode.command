#!/bin/bash
# Double-click in Finder. Two choices. "Test my shows" (recommended) picks the newest episode of
# several shows you follow in Apple Podcasts, one per hosting service (it reads the list the
# Apple Podcasts sync writes), and probes each. "One episode address" asks for a single episode's
# audio address (or takes it from the clipboard). A probe downloads an episode's first 3 MB
# twice with two different User-Agents and prints where the two copies differ: those stretches
# are candidate inserted ads. It runs PodcastKit's podcast-ads --probe. Test my shows therefore
# downloads 3 MB twice for each of up to 8 shows (about 50 MB in all), one show at a time with a
# pause of a second between them, and no retries. The result goes to ~/Storyteller Lofi/logs. It
# needs no keys and no Apple Intelligence, only Xcode 26 to build. It saves no audio. To a
# publisher the second download looks like a second listener, so do not run it over and over.
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

test_my_shows() {
  command -v python3 > /dev/null || finish "python3 is missing (install the Xcode command line tools)." 1
  WORK="$(mktemp -d)"
  python3 "$HERE/probe_shows.py" pick "$WORK/picks.tsv"
  if [ ! -s "$WORK/picks.tsv" ]; then
    finish "Nothing to test. (If your shows are not saved yet, double-click \"Sync Apple Podcasts now.command\", or choose One episode address.)" 1
  fi
  cd "$KIT" || finish "Could not open $KIT." 1
  echo
  echo "Building the tool once..."
  swift build -c release --product podcast-ads || finish "The build did not work (see above)." 1
  N=0
  while IFS="$(printf '\t')" read -r TITLE URL; do
    N=$((N + 1))
    [ "$N" -gt 1 ] && sleep 1
    echo
    echo "[$N] $TITLE"
    swift run -c release podcast-ads --probe "$URL" < /dev/null > "$WORK/$N.txt" 2>&1 \
      || echo "    (it did not work for this show; the report says why)"
  done < "$WORK/picks.tsv"
  mkdir -p "$LOGS"
  OUT="$LOGS/ad-probe-shows-$(date +%Y%m%d-%H%M%S).txt"
  python3 "$HERE/probe_shows.py" report "$WORK" "$OUT" || finish "Could not write the report." 1
  echo
  sed -n '/^Summary/,$p' "$OUT"
  echo
  echo "Saved: $OUT"
  open -R "$OUT"
  finish "Done. Send the file back."
}

CHOICE="$(osascript -e 'button returned of (display dialog "What do you want to test?" buttons {"One episode address", "Test my shows (recommended)"} default button "Test my shows (recommended)")' 2> /dev/null)"
case "$CHOICE" in
  "Test my shows"*) test_my_shows ;;
  "One episode address") ;;
  *) finish "Nothing chosen." 1 ;;
esac

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
