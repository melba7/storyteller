#!/bin/bash
# Double-click in Finder. Sets up a launchd job, "com.storyteller-lofi.podcast-teaching", that runs
# teach-weekly.sh from this folder every Sunday at 3:00 at night: one small teaching run (the
# phone's notes, new episodes, writing them down, marking up to 15 of them with Claude, and the
# steps after marking). It says what it will do first and installs only after you type yes.
# Double-click it again any time: it replaces the job, it does not add a second one.
# "Stop weekly teaching.command" turns the job off. Logs: ~/Storyteller Lofi/logs
# (podcast-teaching-weekly.log for what launchd saw, podcast-teaching.log for the steps).
# launchd runs a start that was missed while the Mac slept as soon as it wakes; a Mac that is shut
# down does not run it. Like install-automatic-scoring.command, the job gets a short PATH, and this
# checks that claude and swift can be found on it before it installs anything. The job file is
# written to a temporary file, checked with plutil -lint and only then moved into place.
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HOME/Storyteller Lofi"
LOGS="$ROOT/logs"
LABEL="com.storyteller-lofi.podcast-teaching"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
SCRIPT="$HERE/teach-weekly.sh"
# The PATH the job will have (teach-weekly.sh adds the same places to whatever it is given).
JOB_PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$HOME/.claude/local"

finish() {
  echo
  echo "$1"
  read -r -p "Press Return to close this window. " _
  exit "${2:-0}"
}

# xml TEXT: the text with & < > made safe inside the job file.
xml() { printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }

echo "Storyteller Lofi: weekly teaching"
echo
[ -f "$SCRIPT" ] || finish "Could not find teach-weekly.sh next to this file." 1
command -v python3 > /dev/null || finish "python3 is missing. Install Apple's command line tools: open Terminal and run xcode-select --install" 1

# The job has a short PATH, so look for the tools there and not in this window's own.
MISSING=""
PATH="$JOB_PATH" command -v claude > /dev/null || MISSING="$MISSING
  - claude was not found. Install Claude Code and sign in once by running claude in Terminal."
PATH="$JOB_PATH" command -v swift > /dev/null || MISSING="$MISSING
  - swift was not found. Install Xcode 26 from the App Store."
if [ -n "$MISSING" ]; then
  echo "The weekly job could not work yet. On the PATH it will have ($JOB_PATH):"
  echo "$MISSING"
  finish "Nothing was changed. Fix that and double-click this file again." 1
fi

echo "This sets up a job that runs every Sunday at 3:00 at night. Each time it:"
echo "  - reads the notes the phone wrote while you listened,"
echo "  - downloads the newest episode of each of your shows, and the ones the phone's notes asked for,"
echo "  - writes down what is said in them,"
echo "  - has Claude mark the ads in up to 15 episodes,"
echo "  - trains the model and copies the results to the phone's folders."
echo
echo "Marking uses your Claude plan's usage allowance, for about 15 episodes a week. It sends at most 15"
echo "episodes (one that fails counts too) and stops when Claude's own cost count reaches \$25."
echo "The Mac has to be on or asleep at that time, not shut down. If it was asleep, the job runs"
echo "when the Mac wakes up. If it was shut down, that week is skipped."
echo "The job runs the files in this folder: $HERE"
echo "If you move or delete this folder, double-click this file again from its new place."
echo "So that the job can copy into iCloud Drive (macOS keeps background jobs out of it), once:"
echo "System Settings > Privacy & Security > Full Disk Access > +, press Cmd-Shift-G, type /bin/bash, add it and switch it on."
echo
read -r -p "Type yes to turn it on, or just press Return to leave it off: " answer
case "$answer" in
  yes|YES|Yes) ;;
  *) finish "Nothing was changed. The weekly job was not turned on." 0 ;;
esac

mkdir -p "$LOGS" "$HOME/Library/LaunchAgents" || finish "Could not make the folders for the job." 1
NEW_PLIST="$(mktemp "${TMPDIR:-/tmp}/teaching-job.XXXXXX")" || finish "Could not make a temporary file." 1
X_SCRIPT="$(xml "$SCRIPT")"
X_LOGS="$(xml "$LOGS")"
X_HOME="$(xml "$HOME")"
X_PATH="$(xml "$JOB_PATH")"
cat > "$NEW_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>$X_SCRIPT</string>
  </array>
  <key>StartCalendarInterval</key>
  <dict>
    <key>Weekday</key><integer>0</integer>
    <key>Hour</key><integer>3</integer>
    <key>Minute</key><integer>0</integer>
  </dict>
  <key>LowPriorityIO</key><true/>
  <key>Nice</key><integer>5</integer>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key><string>$X_PATH</string>
    <key>HOME</key><string>$X_HOME</string>
  </dict>
  <key>StandardOutPath</key><string>$X_LOGS/podcast-teaching-weekly.log</string>
  <key>StandardErrorPath</key><string>$X_LOGS/podcast-teaching-weekly.log</string>
</dict>
</plist>
PLIST
if ! plutil -lint "$NEW_PLIST" > /dev/null; then
  rm -f "$NEW_PLIST"
  finish "The job file could not be written correctly, so nothing was changed." 1
fi
mv "$NEW_PLIST" "$PLIST" || { rm -f "$NEW_PLIST"; finish "Could not put the job file in $PLIST." 1; }
# Replace a job that is already there, so doing this twice leaves one job. Right after bootout
# launchd can still be busy, so a start that fails is tried once more after a second.
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null
if ! launchctl bootstrap "gui/$(id -u)" "$PLIST"; then
  sleep 1
  launchctl bootstrap "gui/$(id -u)" "$PLIST" || finish "Could not start the job (launchctl)." 1
fi

echo
echo "The weekly teaching is on: every Sunday at 3:00 at night."
echo "What it did is written to $LOGS/podcast-teaching-weekly.log and $LOGS/podcast-teaching.log."
finish "Done. To turn it off, double-click \"Stop weekly teaching\"."
