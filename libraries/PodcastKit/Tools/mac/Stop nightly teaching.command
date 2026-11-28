#!/bin/bash
# Double-click in Finder. Turns nightly teaching off (the launchd job that
# "Install nightly teaching.command" set up). The tools, the teaching folder and the logs are kept;
# double-click the installer to turn it on again.
LABEL="com.storyteller-lofi.podcast-nightly-teaching"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null
rm -f "$PLIST"
echo
read -r -p "Nightly teaching is off. Nothing will run at 3:30 any more. Press Return to close this window. " _
