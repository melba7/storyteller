#!/bin/bash
# Double-click in Finder. Finds out whether an ad that comes back in two episodes of a show is the
# very same bytes in both files. If it is, the host copies an ad's audio as it is, and a spot
# heard once could be known again from its first half second, with its start and end exact to a
# frame. Two choices. "Compare my shows" (recommended) needs no files: it reads the list of shows
# you follow in Apple Podcasts (from the Apple Podcasts sync), takes up to 3 of them from
# different hosting services, finds the two newest episodes of each in the show's feed and
# downloads only the first 20 MB of each (the start of an episode is where pre-roll ads sit): 6
# downloads, about 120 MB, one at a time with a pause between them. The downloads go to a temporary
# folder that is deleted at the end. "Two files I choose" asks for two different episodes of one
# show (two MP3 files). Either way it runs PodcastKit's podcast-ads --shared, which cuts the
# files into MP3 frames and lists the stretches that are the same in both, with their times and
# whether the encoding changes at each edge. The result is saved in ~/Storyteller Lofi/logs
# ("ad-shared-shows-<time>.txt" for the shows, "ad-shared-<file name>-<time>.txt" for two
# files). It needs no Apple Intelligence, only Xcode 26 to build, and keeps no audio.
set -o pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
KIT="$(cd "$HERE/../.." && pwd)"
LOGS="$HOME/Storyteller Lofi/logs"
WORK=""

cleanup() { [ -n "$WORK" ] && rm -rf "$WORK"; }
trap cleanup EXIT

finish() {
  echo
  read -r -p "$1 Press Return to close this window. " _
  exit "${2:-0}"
}

compare_my_shows() {
  command -v python3 > /dev/null || finish "python3 is missing (install the Xcode command line tools)." 1
  if [ ! -f "$HOME/Storyteller Lofi/LofiMusic/Podcasts/apple-podcasts.json" ]; then
    finish "Your followed shows are not saved on this Mac yet. Double-click \"Sync Apple Podcasts now.command\" first, then try again." 1
  fi
  cd "$KIT" || finish "Could not open $KIT." 1
  echo "Building the tool once..."
  swift build -c release --product podcast-ads || finish "The build did not work (see above)." 1
  WORK="$(mktemp -d)"
  echo
  echo "Downloading the first 20 MB of two episodes of up to 3 of your shows, one at a time"
  echo "(about 120 MB in all, deleted again when this is done)."
  echo
  python3 "$HERE/shared_shows.py" prepare "$WORK"
  case $? in
    0) ;;
    2) finish "Nothing to compare. (If your shows are not saved yet, double-click \"Sync Apple Podcasts now.command\" first.)" 1 ;;
    *) finish "Nothing could be compared (see above)." 1 ;;
  esac
  echo
  while IFS="$(printf '\t')" read -r NUMBER FIRST SECOND; do
    echo "[$NUMBER] comparing the two episodes..."
    swift run -c release podcast-ads --shared "$FIRST" "$SECOND" < /dev/null > "$WORK/$NUMBER.txt" 2>&1 \
      || echo "    (it did not work for this show; the report says why)"
  done < "$WORK/pairs.tsv"
  mkdir -p "$LOGS"
  OUT="$LOGS/ad-shared-shows-$(date +%Y%m%d-%H%M%S).txt"
  python3 "$HERE/shared_shows.py" report "$WORK" "$OUT" || finish "Could not write the report." 1
  echo
  sed -n '/^All shows at a glance/,$p' "$OUT"
  echo
  echo "Saved: $OUT"
  open -R "$OUT"
  finish "Done. Send the file back."
}

compare_two_files() {
  echo "Choose two different episodes of the same show, ideally two that open with the same"
  echo "kind of ad. This only reads the two files."
  echo
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
}

echo "Storyteller Lofi: compare two episodes of a show"
echo
command -v swift > /dev/null || finish "swift is missing (install Xcode 26 from the App Store)." 1
CHOICE="$(osascript -e 'button returned of (display dialog "What do you want to compare?" buttons {"Two files I choose", "Compare my shows (recommended)"} default button "Compare my shows (recommended)")' 2> /dev/null)"
case "$CHOICE" in
  "Compare my shows"*) compare_my_shows ;;
  "Two files I choose") compare_two_files ;;
  *) finish "Nothing chosen." 1 ;;
esac
