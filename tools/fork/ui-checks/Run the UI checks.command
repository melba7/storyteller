#!/bin/bash
# Double-click in Finder. Runs the simulator checks on this Mac: it builds the Storyteller+ app for
# the iOS Simulator (or uses the last build), starts a simulator, and drives the app with Maestro
# the way a listener would: opens Podcasts, plays an episode, taps the small player, swipes the
# big player down. It saves a screen recording and screenshots of every check and opens the
# results folder (~/Storyteller Lofi/logs/ui-checks-<time>). It needs the tools from "Install the
# UI check tools.command", which you only run once. See README.md in this folder.
HERE="$(cd "$(dirname "$0")" && pwd)"

finish() {
  echo
  read -r -p "$1 Press Return to close this window. " _
  exit "${2:-0}"
}

echo "Storyteller Lofi: check the app in the iPhone simulator"
echo
CHOICE="$(osascript -e 'button returned of (display dialog "Build the app first? A build takes about 4 minutes (the first one longer). Choose the last build to check what you built before." buttons {"Use the last build", "Build the app and check (recommended)"} default button "Build the app and check (recommended)")' 2> /dev/null)"
case "$CHOICE" in
  "Build the app"*) OPTION="--build" ;;
  "Use the last build") OPTION="--last-build" ;;
  *) finish "Nothing chosen." 1 ;;
esac

"$HERE/run.sh" "$OPTION"
STATUS=$?
echo
case $STATUS in
  0) finish "Every check passed. The recordings and screenshots are in the folder that just opened." 0 ;;
  1) finish "A check failed (see above). The folder that just opened has a recording and Maestro's screenshots of what went wrong. Send the whole folder along." 1 ;;
  *) finish "The checks could not run (see above)." 1 ;;
esac
