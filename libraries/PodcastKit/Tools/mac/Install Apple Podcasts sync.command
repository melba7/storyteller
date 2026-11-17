#!/bin/bash
# Double-click in Finder. Makes the Mac tell the Storyteller Lofi phone app which podcasts you
# follow in Apple Podcasts and which episodes you finished. It installs a launchd job that
# runs every hour (and now) and writes Podcasts/apple-podcasts.json into
# "~/Storyteller Lofi/LofiMusic" and its iCloud Drive copy; the phone reads it through the
# sounds folder it already links. One way only: nothing is written to Apple Podcasts' files.
#
# Run it again to update. "Sync Apple Podcasts now.command" runs one sync in a window, and
# deleting ~/Library/LaunchAgents/com.storyteller-lofi.apple-podcasts.plist (after
# `launchctl bootout gui/$(id -u)/com.storyteller-lofi.apple-podcasts`) turns it off.
ROOT="$HOME/Storyteller Lofi"
TOOLS="$ROOT/podcasts-tools"
LABEL="com.storyteller-lofi.apple-podcasts"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
HERE="$(cd "$(dirname "$0")" && pwd)"

finish() {
  echo
  read -r -p "$1 Press Return to close this window. " _
  exit "${2:-0}"
}

echo "Storyteller Lofi: follow Apple Podcasts"
echo
command -v /usr/bin/python3 > /dev/null || finish "python3 is missing (xcode-select --install installs it)." 1
mkdir -p "$TOOLS" "$ROOT/logs" "$ROOT/LofiMusic" "$HOME/Library/LaunchAgents"
# A copy the job runs, so it keeps working if this folder moves.
cp "$HERE/apple_podcasts_export.py" "$HERE/sync-apple-podcasts.sh" "$TOOLS/" || finish "Could not copy the tools." 1
chmod +x "$TOOLS/sync-apple-podcasts.sh"

cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>$TOOLS/sync-apple-podcasts.sh</string>
  </array>
  <key>StartInterval</key><integer>3600</integer>
  <key>RunAtLoad</key><true/>
  <key>LowPriorityIO</key><true/>
  <key>Nice</key><integer>5</integer>
  <key>EnvironmentVariables</key>
  <dict>
    <key>HOME</key><string>$HOME</string>
  </dict>
  <key>StandardOutPath</key><string>$ROOT/logs/apple-podcasts.log</string>
  <key>StandardErrorPath</key><string>$ROOT/logs/apple-podcasts.log</string>
</dict>
</plist>
PLIST

echo "Trying one sync now. macOS may ask whether Terminal may access data from other apps:"
echo "click Allow. That lets this window read Apple Podcasts' library."
echo
if /bin/bash "$TOOLS/sync-apple-podcasts.sh"; then
  echo "That worked."
else
  echo
  echo "The sync did not work yet (see above). If macOS did not ask, or you said Don't Allow:"
  echo "System Settings > Privacy & Security > Full Disk Access > +, press Cmd-Shift-G, type /bin/bash,"
  echo "add it and switch it on (it also lets the hourly job copy into iCloud Drive). Then double-click this again."
fi
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null
launchctl bootstrap "gui/$(id -u)" "$PLIST" || finish "Could not start the job (launchctl)." 1
echo
echo "The job runs every hour. The hourly run is a different program from this window, so macOS may ask once more"
echo "(\"bash would like to access data from other apps\"): click Allow, or add /bin/bash to Full Disk Access as above."
echo "Progress: $ROOT/logs/apple-podcasts.log. On the phone nothing more is needed: the sounds folder link"
echo "(Settings > Atmosphere Sounds > Import a sounds folder, the LofiMusic folder in iCloud Drive) brings the file."
finish "Done."
