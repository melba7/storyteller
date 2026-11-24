#!/bin/bash
# Double-click in Finder. Turns the nightly read-ahead off (the launchd job that
# "Install nightly read-ahead.command" set up). The tools, the teaching folder, the marks already
# made and the logs are kept; double-click the installer to turn it on again.
LABEL="com.storyteller-lofi.podcast-read-ahead"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null
rm -f "$PLIST"
echo
echo "The nightly read-ahead is off. Nothing will run at 2:00 at night."
read -r -p "Press Return to close this window. " _
