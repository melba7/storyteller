#!/bin/bash
# Double-click in Finder. Runs one Apple Podcasts sync in this window (what the hourly job
# from "Install Apple Podcasts sync.command" does): writes the followed shows and finished
# episodes to Podcasts/apple-podcasts.json in LofiMusic and its iCloud copy. Reads Apple's
# library, never writes to it.
HERE="$(cd "$(dirname "$0")" && pwd)"
echo "Reading Apple Podcasts' library..."
if /bin/bash "$HERE/sync-apple-podcasts.sh"; then
  echo "Done."
else
  echo
  echo "It did not work (see above). If macOS says it blocked access: System Settings > Privacy & Security >"
  echo "Full Disk Access > +, press Cmd-Shift-G, type /bin/bash, add it and switch it on."
fi
echo
read -r -p "Press Return to close this window. " _
