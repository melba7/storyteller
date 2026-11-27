#!/bin/bash
# Double-click in Finder. Turns episode preparing off (the launchd job that
# "Install episode preparing.command" set up). The tools, the teaching folder, the marks already
# made, the copies already in iCloud (nothing cleans them while the job is off, so they stay until
# you delete them) and the logs are kept; double-click the installer to turn it on again.
LABEL="com.storyteller-lofi.podcast-prepare"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null
rm -f "$PLIST"
echo
echo "Episode preparing is off. Nothing will run every hour."
read -r -p "Press Return to close this window. " _
