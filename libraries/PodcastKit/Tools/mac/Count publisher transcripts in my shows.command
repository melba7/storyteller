#!/bin/bash
# Double-click in Finder. Reads the feed of every show you follow in Apple Podcasts (the list the
# Apple Podcasts sync writes) and says which of them carry a publisher's transcript (the
# podcast:transcript tag), in which file types, and whether the newest transcript still has the
# spoken ad reads in it. It downloads each feed once (a few seconds each, one second apart) and one
# transcript file (at most 300 KB) from each feed that has one. It downloads no audio, needs no keys
# and no Xcode, writes nothing but one report in ~/Storyteller Lofi/logs, and sends nothing but the
# requests to the feeds' own hosts. It takes about two minutes.
HERE="$(cd "$(dirname "$0")" && pwd)"
LOGS="$HOME/Storyteller Lofi/logs"

finish() {
  echo
  echo "$1"
  read -r -p "Press Return to close this window. " _
  exit "${2:-0}"
}

echo "Storyteller Lofi: count publisher transcripts in my shows"
echo
command -v python3 > /dev/null || finish "python3 is missing (install the Xcode command line tools: xcode-select --install)." 1
mkdir -p "$LOGS" || finish "Could not make $LOGS." 1
OUT="$LOGS/publisher-transcripts-$(date +%Y%m%d-%H%M%S).txt"
python3 "$HERE/probe_transcripts.py" "$OUT"
CODE="$?"
[ "$CODE" = 0 ] || finish "Nothing was counted (see above)." "$CODE"
echo
cat "$OUT"
echo
echo "Saved: $OUT"
command -v open > /dev/null && open -R "$OUT"
finish "Done. Tell Claude it is finished; the report is in the logs folder."
