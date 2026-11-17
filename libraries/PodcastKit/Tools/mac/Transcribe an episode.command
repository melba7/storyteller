#!/bin/bash
# Double-click in Finder. Asks for an audio file, transcribes it with the same Swift code the
# app uses (PodcastKit's podcast-transcribe, Apple's SpeechAnalyzer), and saves the lines with
# their times as "<file name>.transcript.txt" next to the file. Needs macOS 26 and Xcode 26.
# The first run for a language downloads its speech model, and building takes a minute.
HERE="$(cd "$(dirname "$0")" && pwd)"
KIT="$(cd "$HERE/../.." && pwd)"

finish() {
  echo
  read -r -p "$1 Press Return to close this window. " _
  exit "${2:-0}"
}

echo "Storyteller Lofi: transcribe an episode"
echo
command -v swift > /dev/null || finish "swift is missing (install Xcode 26 from the App Store)." 1
FILE="$(osascript -e 'POSIX path of (choose file with prompt "Choose the episode to transcribe")' 2> /dev/null)"
[ -n "$FILE" ] || finish "No file chosen." 1

OUT="$FILE.transcript.txt"
echo "Transcribing: $FILE"
echo "(progress is shown as a percentage; a stopped run carries on where it was)"
echo
cd "$KIT" || finish "Could not open $KIT." 1
if swift run -c release podcast-transcribe "$FILE" > "$OUT.part"; then
  mv "$OUT.part" "$OUT"
  echo
  echo "Saved: $OUT"
  open -R "$OUT"
  finish "Done."
else
  rm -f "$OUT.part"
  finish "It did not work (see above)." 1
fi
