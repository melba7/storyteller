#!/bin/bash
# Double-click in Finder. Turns episode preparing off (the launchd job that
# "Install episode preparing.command" set up). The tools, the teaching folder, the marks already
# made and the logs are kept; double-click the installer to turn it on again.
# It then asks whether to also remove the prepared episodes from iCloud now. On yes it runs the
# cleaning of teach_prepared.py with zero keep days, so the same rules hold as for the job: only
# what prepared.json lists, only names of the form <12 hex>.<ext>, never an episode of the exam or
# the shelf, never a transcript, a label or any other file. It also removes every half-copied
# <12 hex>.<ext>.part file in the prepared folder (--all-parts), which nobody else would remove now.
HERE="$(cd "$(dirname "$0")" && pwd)"
TOOLS="${TEACH_TOOLS:-$HERE}"
FOLDER="${TEACH_FOLDER:-$HOME/Storyteller Lofi/PodcastTeaching}"
LABEL="com.storyteller-lofi.podcast-prepare"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null
rm -f "$PLIST"
echo
echo "Episode preparing is off. Nothing will run every 20 minutes."
echo
echo "The prepared episodes are still in iCloud Drive and take space there."
read -r -p "Type yes to remove the prepared episodes from iCloud now (and the Mac's own copy of their audio), or just press Return to keep them: " answer
case "$answer" in
  yes|YES|Yes)
    command -v python3 > /dev/null || { echo "python3 is missing, so nothing was removed."; read -r -p "Press Return to close this window. " _; exit 1; }
    python3 -u "$TOOLS/teach_prepared.py" clean --folder "$FOLDER" --keep-days 0 --all-parts
    CLEANED="$?"
    echo
    if [ "$CLEANED" -eq 0 ]; then
      echo "That removed the prepared episodes from iCloud (see above for how many), and any half-copied files."
    elif [ "$CLEANED" -eq 3 ]; then
      echo "Nothing was removed: another teaching run is working in the folder, or there is no iCloud copy of the phone's folder (see above). The prepared episodes stay until you run this again or remove them by hand."
    else
      echo "Not everything could be removed (see above). What is left stays in iCloud until you run this again or remove it by hand."
    fi
    ;;
  *)
    echo "The prepared episodes stay in iCloud and take space until the job runs again or you remove them by hand."
    ;;
esac
read -r -p "Press Return to close this window. " _
exit 0
