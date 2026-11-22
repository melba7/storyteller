#!/bin/bash
# Double-click in Finder. Turns the weekly teaching off (the launchd job that
# "Install weekly teaching.command" set up). The tools, the teaching folder and the logs are kept;
# double-click the installer to turn it on again.
LABEL="com.storyteller-lofi.podcast-teaching"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null
rm -f "$PLIST"
echo
read -r -p "The weekly teaching is off. Nothing will run on Sunday night. Press Return to close this window. " _
