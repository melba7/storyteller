#!/bin/bash
# Double-click in Finder. For a big run: writes down the gathered episodes a few at a time and has
# Claude mark the ads in each batch before the next batch is written down, so the marking (and the
# Claude plan's usage it spends) starts within minutes instead of after every episode has been written
# down. It is "Gather episodes for teaching" step 2 and "Mark the new episodes at night" step 3 in a
# loop, at any hour, then the steps after marking (habits, models, library, sounds, score, settings and
# the copy to the phone). The Claude marking counts under the budget in current-budget.txt (else
# big-run-1), up to $95 over every run, and waits for up to 120 hours when the plan's usage allowance is
# used up. It asks for a typed yes once (anything else starts nothing). When another teaching run is
# still working in the folder it waits for it and says so once: close that run's window (or press
# Control-C in it) and this carries on by itself, from where that run was (what is written down and
# marked is kept). The batch size is TEACH_CHUNK (default 20 episodes). Nothing is downloaded or
# deleted. Needs Xcode 26 for the transcriber, like "Gather episodes for teaching".
# What it prints is also added to ~/Storyteller Lofi/logs/podcast-teaching.log.
HERE="$(cd "$(dirname "$0")" && pwd)"
FOLDER="$HOME/Storyteller Lofi/PodcastTeaching"
LOG_FOLDER="$HOME/Storyteller Lofi/logs"
LOG="$LOG_FOLDER/podcast-teaching.log"
BUDGET_FILE="$FOLDER/current-budget.txt"

finish() {
  echo
  echo "$1"
  read -r -p "Press Return to close this window. " _
  exit "${2:-0}"
}

CHUNK="${TEACH_CHUNK:-20}"
printf '%s' "$CHUNK" | LC_ALL=C grep -Eq '^[0-9]{1,3}$' && [ "$CHUNK" -ge 1 ] || CHUNK=20
TEACH_WAIT_HOURS="${TEACH_WAIT_HOURS:-120}"
TEACH_CAP="${TEACH_CAP:-95}"
BUDGET_FROM="the environment"
if [ -z "$TEACH_BUDGET" ]; then
  TEACH_BUDGET="big-run-1"
  BUDGET_FROM="the default"
  if [ -f "$BUDGET_FILE" ]; then
    NAME=""
    IFS= read -r NAME < "$BUDGET_FILE" 2> /dev/null
    NAME="$(printf '%s' "$NAME" | LC_ALL=C sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' 2> /dev/null)"
    if printf '%s' "$NAME" | LC_ALL=C grep -Eq '^[A-Za-z0-9][A-Za-z0-9_-]{0,39}$'; then
      TEACH_BUDGET="$NAME"
      BUDGET_FROM="$BUDGET_FILE"
    fi
  fi
fi

echo "Storyteller Lofi: write down and mark together"
echo
echo "This writes down the gathered episodes $CHUNK at a time and has Claude mark the ads in each"
echo "batch before the next batch is written down, at any hour, so the marking starts within minutes."
echo "It uses the Claude plan this Mac is signed in to and shares its usage allowance, up to \$$TEACH_CAP"
echo "in all under the budget \"$TEACH_BUDGET\" (from $BUDGET_FROM). When the allowance is used up it"
echo "waits and carries on, for up to $TEACH_WAIT_HOURS hours. Keep the Mac plugged in with the lid open."
echo "Then the results are worked out and copied to the phone's folders."
echo
command -v python3 > /dev/null || finish "python3 is missing. Install Apple's command line tools: open Terminal and run xcode-select --install" 2
command -v swift > /dev/null || finish "swift is missing (install Xcode 26 from the App Store)." 1
mkdir -p "$LOG_FOLDER" || finish "Could not make $LOG_FOLDER." 2
[ -d "$FOLDER" ] || finish "There is no teaching folder at $FOLDER, so there is nothing to write down." 2

read -r -p "Type yes to start: " TYPED
# Only the ends are trimmed: "ye s" is not yes.
TYPED="$(echo "$TYPED" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | tr '[:upper:]' '[:lower:]')"
[ "$TYPED" = yes ] || finish "Nothing was started, because you did not type yes." 0

echo "=== $(date '+%Y-%m-%d %H:%M') write down and mark together: $CHUNK at a time ===" >> "$LOG"
TOLD=no
while python3 "$HERE/teach_store.py" busy "$FOLDER" > /dev/null 2>&1; FREE="$?"; [ "$FREE" = 3 ]; do
  if [ "$TOLD" = no ]; then
    echo "Another teaching run is still working in the folder. Close its window (or press Control-C"
    echo "in it) and this goes on by itself. Waiting..." | tee -a "$LOG"
    TOLD=yes
  fi
  sleep 10
done
[ "$FREE" = 0 ] || finish "The teaching folder could not be checked (see the log)." 2

KIT=""
for CANDIDATE in "$HERE/../.." "$HOME/Storyteller Lofi/testflight-build/libraries/PodcastKit"; do
  if [ -f "$CANDIDATE/Package.swift" ]; then
    KIT="$(cd "$CANDIDATE" && pwd)"
    break
  fi
done
[ -n "$KIT" ] || finish "Could not find PodcastKit (no Package.swift next to these tools or in testflight-build)." 1
cd "$KIT" || finish "Could not open $KIT." 1
echo "Building the transcriber (this takes a minute the first time)..."
swift build -c release --product podcast-transcribe 2>&1 | tee -a "$LOG"
[ "${PIPESTATUS[0]}" = 0 ] || finish "The transcriber did not build (see above)." 1
TOOL="$(swift build -c release --show-bin-path)/podcast-transcribe"

echo "First: backing up what is marked so far"
python3 -u "$HERE/teach_backup.py" make --check --folder "$FOLDER" 2>&1 | tee -a "$LOG"
[ "${PIPESTATUS[0]}" = 0 ] || echo "The backup did not work (see above). It goes on without it." | tee -a "$LOG"

STOP=""
ROUND=0
while [ "$ROUND" -lt 400 ]; do
  ROUND=$((ROUND + 1))
  BEFORE="$(ls "$FOLDER/transcripts" 2> /dev/null | wc -l | tr -d ' ')"
  echo
  echo "=== batch $ROUND: writing down up to $CHUNK episodes ===" | tee -a "$LOG"
  caffeinate -i python3 -u "$HERE/teach_transcribe.py" --folder "$FOLDER" --tool "$TOOL" --limit "$CHUNK" 2>&1 | tee -a "$LOG"
  CODE="${PIPESTATUS[0]}"
  if [ "$CODE" = 3 ]; then
    STOP="Writing down stopped early because several episodes in a row failed (see above). What was marked is kept."
    break
  elif [ "$CODE" != 0 ]; then
    finish "Writing down did not work, or another run is working in the folder (see above). Nothing more was started." 2
  fi
  AFTER="$(ls "$FOLDER/transcripts" 2> /dev/null | wc -l | tr -d ' ')"
  echo "=== batch $ROUND: marking ===" | tee -a "$LOG"
  caffeinate -i python3 -u "$HERE/teach_label.py" --folder "$FOLDER" --between 0-24 --wait-hours "$TEACH_WAIT_HOURS" --cap "$TEACH_CAP" --budget "$TEACH_BUDGET" --yes 2>&1 | tee -a "$LOG"
  CODE="${PIPESTATUS[0]}"
  case "$CODE" in
    0) ;;
    3) STOP="Marking stopped early: Claude's usage allowance stayed used up for longer than it waits, or Claude is not signed in (see above). What was marked is saved. Double-click again to carry on, for example after your usage allowance has reset."; break ;;
    5) STOP="The spending limit of \$$TEACH_CAP is reached (counted over every run under \"$TEACH_BUDGET\") and nothing more will be marked under it."; break ;;
    6) STOP="Marking stopped because episodes failed (see failures.json in $FOLDER). What was marked is saved."; break ;;
    *) finish "Marking did not work, or another run is working in the folder (see above). Nothing more was started." 2 ;;
  esac
  [ "$AFTER" = "$BEFORE" ] && break
done

echo
echo "Now the steps after marking: habits, models, library, sounds, score, settings and the copy to the phone."
"$HERE/teach-finish.sh"
DONE="$?"
[ "$DONE" = 3 ] && finish "Another teaching run started meanwhile, so the steps after marking did not run (see above). Double-click \"Teach the phone again\" when it is done." 2
[ -n "$STOP" ] && finish "$STOP" 3
[ "$DONE" != 0 ] && finish "Everything was written down and marked, but not every step after it worked (see the summary above)." 2
finish "Done. Everything gathered is written down and marked, and the results are in the phone's folders."
