#!/bin/bash
# Not double-clicked: the launchd job "com.storyteller-lofi.podcast-teaching" runs it every Sunday
# at 3:00 at night (Install weekly teaching.command sets that up). It does one small teaching run
# without anyone there:
#   1. reads the phone's notes (teach_feedback.py), which lists the episodes to fetch first
#   2. gathers new episodes, one newest episode per show, plus the wanted ones (teach_collect.py)
#   3. writes down what is said in them (podcast-transcribe, after building it)
#   4. has Claude mark the ads in at most 15 episodes, at most $25 of Claude's own cost estimate
#      (teach_label.py --yes --limit 15 --cap 25). Every episode that is sent counts towards the 15,
#      also one that fails. This is the only step that uses the Claude plan's usage allowance
#   5. runs the steps after marking (teach-finish.sh): habits, model, library, sounds, score, and
#      the copy to the phone's folders
# One run at a time is enforced by the tools' lock on the teaching folder. When another run holds
# it, this says so and ends quietly (exit 0). A step that fails is said plainly and the next ones
# still run, because each works from what is already on disk. It exits 0 when every step worked.
# What it prints goes to ~/Storyteller Lofi/logs/podcast-teaching-weekly.log (from launchd) and to
# ~/Storyteller Lofi/logs/podcast-teaching.log.
#
# launchd starts jobs with no terminal and a short PATH, so the usual places are added to it. The
# Mac's bash is 3.2: plain variables only. TEACH_CAP (dollars, at the price Claude itself reports
# for each call; 15 episodes were estimated at about $1 each, so $25 leaves room) and TEACH_MAX_GB (the most
# audio the teaching folder keeps) can be set to change the two limits. For the tests, TEACH_TOOLS,
# TEACH_KIT and TEACH_FOLDER can be set too (see teach-finish.sh).
HERE="$(cd "$(dirname "$0")" && pwd)"
TOOLS="${TEACH_TOOLS:-$HERE}"
FOLDER="${TEACH_FOLDER:-$HOME/Storyteller Lofi/PodcastTeaching}"
CAP="${TEACH_CAP:-25}"
MAX_GB="${TEACH_MAX_GB:-12}"
LOG_FOLDER="$HOME/Storyteller Lofi/logs"
LOG="$LOG_FOLDER/podcast-teaching.log"
export PATH="$PATH:/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/opt/homebrew/bin:$HOME/.local/bin:$HOME/.claude/local"

mkdir -p "$LOG_FOLDER" || { echo "Could not make $LOG_FOLDER."; exit 1; }
command -v python3 > /dev/null || { echo "python3 is missing. Install Apple's command line tools: open Terminal and run xcode-select --install"; exit 1; }
set -o pipefail

CAFFEINATE=""
command -v caffeinate > /dev/null && CAFFEINATE="caffeinate -i"
STATUS=0

say() { echo "$@" | tee -a "$LOG"; }

# step WORDS COMMAND...: says what is about to happen, runs the command (its output is shown and
# added to the log) and returns its exit code.
step() {
  local words="$1"
  shift
  say
  say "$words"
  "$@" 2>&1 | tee -a "$LOG"
  return "${PIPESTATUS[0]}"
}

say "=== $(date '+%Y-%m-%d %H:%M') weekly teaching ==="

# Another run in the folder: say so and end quietly.
python3 -u "$TOOLS/teach_store.py" busy "$FOLDER" > /dev/null 2>&1
LOCKED="$?"
if [ "$LOCKED" -eq 3 ]; then
  say "Another teaching run is already working in the teaching folder, so this week's run is skipped."
  exit 0
elif [ "$LOCKED" -ne 0 ]; then
  say "The teaching folder $FOLDER cannot be used, so this week's run did not start."
  exit 1
fi

step "Step 1 of 5: reading the phone's notes" python3 -u "$TOOLS/teach_feedback.py" --folder "$FOLDER"
if [ "$?" -ne 0 ]; then
  say "The phone's notes could not be used (see above). The run goes on without them."
  STATUS=1
fi

step "Step 2 of 5: gathering new episodes" $CAFFEINATE python3 -u "$TOOLS/teach_collect.py" --folder "$FOLDER" --per-show 1 --max-gb "$MAX_GB"
GATHERED="$?"
if [ "$GATHERED" -eq 3 ]; then
  say "Nothing more can be gathered: the audio kept in the teaching folder has reached its limit of $MAX_GB GB. To go on, raise TEACH_MAX_GB (the number near the top of teach-weekly.sh). The run goes on with what is already there."
  STATUS=1
elif [ "$GATHERED" -ne 0 ]; then
  say "Gathering did not work (see above). The run goes on with what is already there."
  STATUS=1
fi

# Step 3 needs the transcriber built.
say
say "Step 3 of 5: writing down what is said"
KIT=""
for CANDIDATE in "${TEACH_KIT:-$HERE/../..}" "$HOME/Storyteller Lofi/testflight-build/libraries/PodcastKit"; do
  if [ -f "$CANDIDATE/Package.swift" ]; then
    KIT="$(cd "$CANDIDATE" && pwd)"
    break
  fi
done
TRANSCRIBER=""
if [ -z "$KIT" ]; then
  say "Could not find PodcastKit (no Package.swift next to these tools or in testflight-build)."
elif ! command -v swift > /dev/null; then
  say "swift is missing (install Xcode 26 from the App Store)."
elif ! (cd "$KIT" && swift build -c release --product podcast-transcribe 2>&1 | tee -a "$LOG"; exit "${PIPESTATUS[0]}"); then
  say "The transcriber did not build (see above)."
else
  TRANSCRIBER="$(cd "$KIT" && swift build -c release --show-bin-path)/podcast-transcribe"
fi
if [ -z "$TRANSCRIBER" ]; then
  say "Writing down what is said was left out. The run goes on."
  STATUS=1
else
  $CAFFEINATE python3 -u "$TOOLS/teach_transcribe.py" --folder "$FOLDER" --tool "$TRANSCRIBER" 2>&1 | tee -a "$LOG"
  if [ "${PIPESTATUS[0]}" -ne 0 ]; then
    say "Writing down what is said did not finish (see above). The run goes on with what is done."
    STATUS=1
  fi
fi

step "Step 4 of 5: having Claude mark the ads in at most 15 episodes, at most about \$$CAP (this uses your Claude usage allowance)" $CAFFEINATE python3 -u "$TOOLS/teach_label.py" --folder "$FOLDER" --yes --limit 15 --cap "$CAP"
if [ "$?" -ne 0 ]; then
  say "Marking did not finish (see above). What was marked is saved. The run goes on."
  STATUS=1
fi

say
say "Step 5 of 5: the steps after marking"
"$HERE/teach-finish.sh"
if [ "$?" -ne 0 ]; then
  STATUS=1
fi

if [ "$STATUS" -eq 0 ]; then
  say "This week's teaching run is done."
else
  say "This week's teaching run is done, but not every step worked (see above)."
fi
exit "$STATUS"
