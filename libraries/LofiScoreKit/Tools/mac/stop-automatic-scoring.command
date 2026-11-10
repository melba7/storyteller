#!/bin/bash
# Double-click in Finder. Turns automatic scoring off (the launchd job that
# install-automatic-scoring.command set up). The tools, the books, the tracks
# and the server login are kept; double-click the installer to turn it on again.
LABEL="com.storyteller-lofi.sync"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null
rm -f "$PLIST"
echo
read -r -p "Automatic scoring is off. Press Return to close this window. " _
