#!/bin/bash
# Double-click in Finder. Sets up a launchd job, "com.storyteller-lofi.podcast-prepare", that runs
# teach-prepare.sh from this folder every 20 minutes (at 5, 25 and 45 minutes past the hour): the Mac picks the new episodes of every show you
# follow, has Claude mark their ads, finds the exact borders with a second download, puts its copy
# of the audio into the phone's iCloud folder, and tells the phone where the ads are in that very
# file. It says what it will do first and installs only after you type yes. Double-click it again
# any time: it replaces the job, it does not add a second one. It takes the place of the nightly
# read-ahead, so it unloads that job (and removes its job file) when it is loaded.
# "Stop episode preparing.command" turns the job off. Logs: ~/Storyteller Lofi/logs
# (podcast-prepare-job.log for what launchd saw, podcast-prepare.log for the steps).
# launchd runs a start that was missed while the Mac slept as soon as it wakes; a Mac that is shut
# down does not run it. Like "Install nightly read-ahead.command", the job gets a short PATH, and
# this checks that claude and swift can be found on it before it installs anything. The job file is
# written to a temporary file, checked with plutil -lint and only then moved into place. This file
# writes nothing into iCloud Drive; the job does, when it copies the audio and its results.
# The days a copy stays in iCloud and the most GB of copies are set here (or, for one run of this
# file, with TEACH_PREPARE_KEEP_DAYS and TEACH_PREPARE_GB); the job is given them. 5 GB and 3 days,
# or 20 GB and 14 days, are fine too.
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HOME/Storyteller Lofi"
LOGS="$ROOT/logs"
LABEL="com.storyteller-lofi.podcast-prepare"
OLD_LABEL="com.storyteller-lofi.podcast-read-ahead"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
OLD_PLIST="$HOME/Library/LaunchAgents/$OLD_LABEL.plist"
SCRIPT="$HERE/teach-prepare.sh"
KEEP_DAYS="${TEACH_PREPARE_KEEP_DAYS:-7}"
ICLOUD_GB="${TEACH_PREPARE_GB:-10}"
# The weekly cap, in dollars of the Claude plan's usage as Claude counts it. It is the default of
# TEACH_PREPARE_CAP in teach-prepare.sh, and the job runs with that default.
CAP=35
# The minutes of every hour the job starts at: every 20 minutes. The weekly cap, not the number of
# runs, limits the spending: the budget is one for the whole week and is checked before every call.
MINUTES="5 25 45"
# The PATH the job will have (teach-prepare.sh adds the same places to whatever it is given).
JOB_PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$HOME/.claude/local"

finish() {
  echo
  echo "$1"
  read -r -p "Press Return to close this window. " _
  exit "${2:-0}"
}

# xml TEXT: the text with & < > made safe inside the job file.
xml() { printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }

echo "Storyteller Lofi: episode preparing"
echo
[ -f "$SCRIPT" ] || finish "Could not find teach-prepare.sh next to this file." 1
command -v python3 > /dev/null || finish "python3 is missing. Install Apple's command line tools: open Terminal and run xcode-select --install" 1
case "$KEEP_DAYS$ICLOUD_GB" in
  *[!0-9]*|"") finish "The days and the GB must be whole numbers (now $KEEP_DAYS days and $ICLOUD_GB GB). Nothing was changed." 1 ;;
esac
[ "$KEEP_DAYS" -ge 1 ] && [ "$ICLOUD_GB" -ge 1 ] || finish "The days and the GB must be 1 or more. Nothing was changed." 1

# The job has a short PATH, so look for the tools there and not in this window's own.
MISSING=""
PATH="$JOB_PATH" command -v claude > /dev/null || MISSING="$MISSING
  - claude was not found. Install Claude Code and sign in once by running claude in Terminal."
PATH="$JOB_PATH" command -v swift > /dev/null || MISSING="$MISSING
  - swift was not found. Install Xcode 26 from the App Store."
if [ -n "$MISSING" ]; then
  echo "The job could not work yet. On the PATH it will have ($JOB_PATH):"
  echo "$MISSING"
  finish "Nothing was changed. Fix that and double-click this file again." 1
fi

# How much iCloud space is free, when macOS says it (brctl quota). Said only when it is understood.
FREE_TEXT=""
BYTES="$(brctl quota 2>/dev/null | grep -Eo '[0-9][0-9,]* bytes of quota remaining' | head -1 | sed 's/[^0-9]//g')"
if [ -n "$BYTES" ]; then
  FREE_TEXT="$(awk -v b="$BYTES" 'BEGIN { printf "%.1f", b / 1000000000 }')"
fi

echo "This sets up a job that runs every 20 minutes (at 5, 25 and 45 minutes past the hour). Each time it:"
echo "  - tells the phone which episodes are coming, so it waits for the Mac's copy,"
echo "  - picks up to 6 new episodes: first the ones the phone expects to play next, then the newest of every show you follow (the last 3 days),"
echo "  - downloads them and writes down what is said in them,"
echo "  - has Claude mark the ads in them,"
echo "  - downloads each a second time to find where the ads begin and end to the frame,"
echo "  - puts the Mac's copy of the audio into the phone's iCloud folder, so the phone plays the very file the Mac marked,"
echo "  - tells the phone where the ads are,"
echo "  - reads what you tapped on the phone (Undo, Skip ad) and gives Claude short notes about it for that show's next episodes. A tap changes no skip by itself."
echo "The phone still skips ads by itself for every episode the Mac has not prepared."
echo
echo "It runs every 20 minutes and uses at most \$$CAP a week of Claude usage (about \$0.19 an episode, so about 180 episodes a week)."
echo "It stops for the week before a call that could pass that cap. One call can cost more than an episode's usual share, so it keeps one dollar in reserve and marking stops at about $((CAP - 1)) dollars. Nothing else costs anything."
echo "It keeps at most $ICLOUD_GB GB of audio in iCloud for $KEEP_DAYS days. When a copy is $KEEP_DAYS days old, or the copies pass $ICLOUD_GB GB, the oldest go."
echo "After $KEEP_DAYS days it deletes the audio it downloaded itself, here on the Mac and in iCloud. Your other files are never touched."
if [ -n "$FREE_TEXT" ]; then
  echo "iCloud has $FREE_TEXT GB free now. It never fills iCloud: it stops with under 2 GB left, and with under 15 GB free on this Mac."
else
  echo "It never fills iCloud: it stops with under 2 GB left, and with under 15 GB free on this Mac."
fi
echo "If the job cannot put files into iCloud, it spends nothing and says so in the log."
echo "The Mac has to be awake and online at that time. If it was asleep, the job runs when the Mac wakes up. If it was shut down, that run is skipped. A run that takes longer than 20 minutes makes the next one wait: only one runs at a time."
echo "It replaces the nightly read-ahead: if that job is on, this turns it off. If an older hourly episode preparing job is on, this replaces it with this one."
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
  *) finish "Nothing was changed. Episode preparing was not turned on." 0 ;;
esac

mkdir -p "$LOGS" "$HOME/Library/LaunchAgents" || finish "Could not make the folders for the job." 1
NEW_PLIST="$(mktemp "${TMPDIR:-/tmp}/prepare-job.XXXXXX")" || finish "Could not make a temporary file." 1
X_SCRIPT="$(xml "$SCRIPT")"
X_LOGS="$(xml "$LOGS")"
X_HOME="$(xml "$HOME")"
X_PATH="$(xml "$JOB_PATH")"
INTERVALS=""
for MINUTE in $MINUTES; do
  INTERVALS="$INTERVALS    <dict><key>Minute</key><integer>$MINUTE</integer></dict>
"
done
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
  <array>
$INTERVALS
  </array>
  <key>LowPriorityIO</key><true/>
  <key>Nice</key><integer>5</integer>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key><string>$X_PATH</string>
    <key>HOME</key><string>$X_HOME</string>
    <key>TEACH_PREPARE_KEEP_DAYS</key><string>$KEEP_DAYS</string>
    <key>TEACH_PREPARE_GB</key><string>$ICLOUD_GB</string>
  </dict>
  <key>StandardOutPath</key><string>$X_LOGS/podcast-prepare-job.log</string>
  <key>StandardErrorPath</key><string>$X_LOGS/podcast-prepare-job.log</string>
</dict>
</plist>
PLIST
if ! plutil -lint "$NEW_PLIST" > /dev/null; then
  rm -f "$NEW_PLIST"
  finish "The job file could not be written correctly, so nothing was changed." 1
fi

# The nightly read-ahead is replaced: turn it off when it is loaded, and take its job file away so
# that it does not come back at the next login.
if launchctl print "gui/$(id -u)/$OLD_LABEL" > /dev/null 2>&1; then
  launchctl bootout "gui/$(id -u)/$OLD_LABEL" 2>/dev/null
  echo "The nightly read-ahead was on, and is turned off now."
fi
# A job file that is on disk but not loaded would start at the next login, so it goes too.
if [ -e "$OLD_PLIST" ]; then
  rm -f "$OLD_PLIST"
  echo "The nightly read-ahead's job file was removed, so it does not come back at the next login."
fi

mv "$NEW_PLIST" "$PLIST" || { rm -f "$NEW_PLIST"; finish "Could not put the job file in $PLIST." 1; }
# Replace a job that is already there, so doing this twice leaves one job. Right after bootout
# launchd can still be busy, so a start that fails is tried once more after a second.
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null
if ! launchctl bootstrap "gui/$(id -u)" "$PLIST"; then
  sleep 1
  if ! launchctl bootstrap "gui/$(id -u)" "$PLIST"; then
    rm -f "$PLIST"
    finish "Could not start the job (launchctl), so its job file was removed again and nothing will start at the next login." 1
  fi
fi

echo
echo "Episode preparing is on: every 20 minutes, at 5, 25 and 45 minutes past the hour."
echo "What it did is written to $LOGS/podcast-prepare-job.log and $LOGS/podcast-prepare.log."
finish "Done. To turn it off, double-click \"Stop episode preparing\"."
