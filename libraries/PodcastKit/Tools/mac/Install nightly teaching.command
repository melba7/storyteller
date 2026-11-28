#!/bin/bash
# Double-click in Finder. Sets up a launchd job, "com.storyteller-lofi.podcast-nightly-teaching",
# that runs teach-nightly.sh from this folder every night at 3:30: it teaches the phone again from
# what was marked that day (the steps habits, model, cues, library, sounds, meaning, score, settings
# and the copy to the phone's folders, which "Teach the phone again" runs by hand). It costs
# nothing: it makes no call to Claude. It says what it will do first and installs only after you
# type yes. Double-click it again any time: it replaces the job, it does not add a second one.
# "Stop nightly teaching.command" turns the job off. Logs: ~/Storyteller Lofi/logs
# (podcast-nightly-teaching.log for what launchd saw, podcast-teaching.log for the steps).
# launchd runs a start that was missed while the Mac slept as soon as it wakes; a Mac that is shut
# down does not run it. The job gets a short PATH, and this checks that swift can be found on it
# before it installs anything (claude is not needed). The job file is written to a temporary file,
# checked with plutil -lint and only then moved into place.
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HOME/Storyteller Lofi"
LOGS="$ROOT/logs"
LABEL="com.storyteller-lofi.podcast-nightly-teaching"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
SCRIPT="$HERE/teach-nightly.sh"
# The PATH the job will have (teach-nightly.sh adds the same places to whatever it is given).
JOB_PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin"

finish() {
  echo
  echo "$1"
  read -r -p "Press Return to close this window. " _
  exit "${2:-0}"
}

# xml TEXT: the text with & < > made safe inside the job file.
xml() { printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }

echo "Storyteller Lofi: nightly teaching"
echo
[ -f "$SCRIPT" ] || finish "Could not find teach-nightly.sh next to this file." 1
command -v python3 > /dev/null || finish "python3 is missing. Install Apple's command line tools: open Terminal and run xcode-select --install" 1

# The job has a short PATH, so look for the tools there and not in this window's own.
MISSING=""
PATH="$JOB_PATH" command -v swift > /dev/null || MISSING="$MISSING
  - swift was not found. Install Xcode 26 from the App Store."
if [ -n "$MISSING" ]; then
  echo "The nightly job could not work yet. On the PATH it will have ($JOB_PATH):"
  echo "$MISSING"
  finish "Nothing was changed. Fix that and double-click this file again." 1
fi

echo "This sets up a job that runs every night at 3:30. Each time it teaches the phone again from"
echo "the episodes marked so far, mostly those marked that day:"
echo "  - backs up the marks,"
echo "  - trains the models and the ad sounds,"
echo "  - scores the ad skipping,"
echo "  - chooses what each finder may do on each show (not when the score failed: the old settings stay),"
echo "  - copies the results to the phone's folders."
echo
echo "It costs nothing: it makes no call to Claude. Marking is done by episode preparing and the other jobs."
echo "If another teaching run is working at that time (episode preparing, for one), tonight is skipped"
echo "and it tries again the next night."
echo "The Mac has to be on or asleep at that time, not shut down. If it was asleep, the job runs"
echo "when the Mac wakes up. If it was shut down, that night is skipped."
echo "The job runs the files in this folder: $HERE"
echo "If you move or delete this folder, double-click this file again from its new place."
echo "So that the job can copy into iCloud Drive (macOS keeps background jobs out of it), once:"
echo "System Settings > Privacy & Security > Full Disk Access > +, press Cmd-Shift-G, type /bin/bash, add it and switch it on."
echo
# TEACH_INSTALL_YES=1 stands for the typed yes, for a script that runs with nobody at the keyboard.
if [ "$TEACH_INSTALL_YES" = 1 ]; then
  answer=yes
  echo "TEACH_INSTALL_YES=1 was given, so it is turned on without asking."
else
  read -r -p "Type yes to turn it on, or just press Return to leave it off: " answer
fi
case "$answer" in
  yes|YES|Yes) ;;
  *) finish "Nothing was changed. Nightly teaching was not turned on." 0 ;;
esac

mkdir -p "$LOGS" "$HOME/Library/LaunchAgents" || finish "Could not make the folders for the job." 1
NEW_PLIST="$(mktemp "${TMPDIR:-/tmp}/nightly-teaching-job.XXXXXX")" || finish "Could not make a temporary file." 1
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
    <key>Hour</key><integer>3</integer>
    <key>Minute</key><integer>30</integer>
  </dict>
  <key>LowPriorityIO</key><true/>
  <key>Nice</key><integer>5</integer>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key><string>$X_PATH</string>
    <key>HOME</key><string>$X_HOME</string>
  </dict>
  <key>StandardOutPath</key><string>$X_LOGS/podcast-nightly-teaching.log</string>
  <key>StandardErrorPath</key><string>$X_LOGS/podcast-nightly-teaching.log</string>
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
echo "Nightly teaching is on: every night at 3:30."
echo "What it did is written to $LOGS/podcast-nightly-teaching.log and $LOGS/podcast-teaching.log."
finish "Done. To turn it off, double-click \"Stop nightly teaching\"."
