#!/bin/bash
# Fetches recordings for every sound in the catalogue (Tools/atmosphere/catalog.json):
# the personal edition (Freesound and Wikimedia Commons, into "~/Storyteller
# Lofi/Atmosphere") and then the publish edition (Commons only, into
# "~/Storyteller Lofi/AtmospherePublish"), then copies the personal set into
# "~/Storyteller Lofi/LofiMusic/Atmosphere" and the iCloud Drive copy the phone
# follows. Runs add what is missing, so it is safe to run again; a full first run
# over the whole catalogue takes a few hours, so run it in the background:
#
#   cd "~/Storyteller Lofi/<clone>/libraries/LofiScoreKit"
#   nohup Tools/mac/fetch-sounds.sh > "$HOME/Storyteller Lofi/logs/fetch-sounds.out" 2>&1 &
#
#   Tools/mac/fetch-sounds.sh [--personal-only|--publish-only] [--no-copy] [fetch_ambience.py options ...]
#
# Anything else on the command line goes to fetch_ambience.py (--per-variant 1,
# --sound Crowd.SchoolCorridor, --dry-run, ...). Needs python3 and ffmpeg
# (brew install ffmpeg); the Freesound key in ~/Storyteller Lofi/.freesound-key.
set -uo pipefail

ROOT="$HOME/Storyteller Lofi"
PKG="$(cd "$(dirname "$0")/../.." && pwd)"
LOGS="$ROOT/logs"
MUSIC="$ROOT/LofiMusic"
ICLOUD="$HOME/Library/Mobile Documents/com~apple~CloudDocs/Storyteller Lofi/LofiMusic"
PATH="$PATH:/opt/homebrew/bin"
EDITIONS="personal publish"
COPY=1
ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --personal-only) EDITIONS=personal; shift ;;
    --publish-only) EDITIONS=publish; shift ;;
    --no-copy) COPY=0; shift ;;
    *) ARGS+=("$1"); shift ;;
  esac
done
mkdir -p "$LOGS"
command -v ffmpeg > /dev/null || { echo "ffmpeg is needed (brew install ffmpeg)"; exit 1; }

say() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" | tee -a "$LOGS/fetch-sounds.log"; }

say "fetching sounds from the catalogue in $PKG ($EDITIONS)"
status=0
for edition in $EDITIONS; do
  say "== $edition edition"
  python3 -I "$PKG/Tools/atmosphere/fetch_ambience.py" --edition "$edition" "${ARGS[@]+"${ARGS[@]}"}" 2>&1 \
    | grep -vE ": already has [0-9]+$" | tee -a "$LOGS/fetch-sounds.log"
  [ "${PIPESTATUS[0]}" = 0 ] || { status=1; say "$edition edition: the fetch stopped early (see above); what it fetched is kept"; }
done

if [ "$COPY" = 1 ] && [ -d "$MUSIC" ] && [ -d "$ROOT/Atmosphere" ]; then
  rsync -a --exclude skipped.csv "$ROOT/Atmosphere/" "$MUSIC/Atmosphere/" && say "copied Atmosphere into $MUSIC"
  if [ -d "$ICLOUD" ]; then
    if rsync -a --exclude .DS_Store --exclude '.*.part' --exclude '.imported.json' "$MUSIC/" "$ICLOUD/"; then
      say "iCloud copy up to date; the phone picks the new sounds up from its linked folder"
    else
      say "could not update the iCloud copy"
    fi
  fi
fi
say "done"
exit $status
