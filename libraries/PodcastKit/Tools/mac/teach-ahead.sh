#!/bin/bash
# Not double-clicked: the launchd job "com.storyteller-lofi.podcast-read-ahead" runs it every night at
# 2:00 (Install nightly read-ahead.command sets that up). It reads ahead the episodes the phone
# expects to play next, so the phone knows where their ads are before Mo presses play:
#   1. reads the phone's list of next episodes (Podcasts/phone-queue.json, the iCloud copy first) and
#      picks at most 8 episodes that are not marked yet (teach_ahead.py pick)
#   2. downloads them, with the teaching run's size and disk limits (teach_collect.py --only-ahead)
#   3. writes down what is said in them (podcast-transcribe, after building it)
#   4. has Claude mark the ads in them (teach_label.py --only-ahead), under the budget
#      ahead-<ISO year>-W<ISO week> with a hard stop at $10 a week: it stops before a call that would
#      pass the cap, because each episode is expected to cost about $0.19. This is the only step that
#      uses the Claude plan's usage allowance
#   5. writes ahead-ads.json, the ads of the last 14 days' episodes told in words (teach_ahead.py
#      write), and copies it with the other files to the phone's folders (teach_publish.py)
# The episodes join the teaching set with their labels, so the weekly run learns from them, but they
# never become shelf or exam episodes (ahead.json).
# A night with no queue, nothing new in it, no budget left or no audio to work on says so in one line
# and ends quietly (exit 0). A step that fails is said plainly and the next ones still run when they
# can; it exits 0 when every step worked. One run at a time is enforced by the tools' lock on the
# teaching folder. What it prints goes to ~/Storyteller Lofi/logs/podcast-read-ahead.log (and what
# launchd saw to podcast-read-ahead-job.log).
#
# launchd starts jobs with no terminal and a short PATH, so the usual places are added to it. The
# Mac's bash is 3.2: plain variables only. TEACH_AHEAD_CAP (dollars a week, 10), TEACH_AHEAD_ESTIMATE
# (dollars one episode is expected to cost, 0.19), TEACH_AHEAD_MOST (episodes a night, 8) and
# TEACH_MAX_GB (the most audio the teaching folder keeps, 12) can be set to change the limits. For
# the tests, TEACH_TOOLS, TEACH_KIT and TEACH_FOLDER can be set too (see teach-finish.sh).
HERE="$(cd "$(dirname "$0")" && pwd)"
TOOLS="${TEACH_TOOLS:-$HERE}"
FOLDER="${TEACH_FOLDER:-$HOME/Storyteller Lofi/PodcastTeaching}"
CAP="${TEACH_AHEAD_CAP:-10}"
ESTIMATE="${TEACH_AHEAD_ESTIMATE:-0.19}"
MOST="${TEACH_AHEAD_MOST:-8}"
MAX_GB="${TEACH_MAX_GB:-12}"
LOG_FOLDER="$HOME/Storyteller Lofi/logs"
LOG="$LOG_FOLDER/podcast-read-ahead.log"
export PATH="$PATH:/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/opt/homebrew/bin:$HOME/.local/bin:$HOME/.claude/local"

mkdir -p "$LOG_FOLDER" || { echo "Could not make $LOG_FOLDER."; exit 1; }
command -v python3 > /dev/null || { echo "python3 is missing. Install Apple's command line tools: open Terminal and run xcode-select --install"; exit 1; }
set -o pipefail

CAFFEINATE=""
command -v caffeinate > /dev/null && CAFFEINATE="caffeinate -i"
STATUS=0
# The budget of this week, counted over every night of the week.
BUDGET="ahead-$(date +%G-W%V)"

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

say "=== $(date '+%Y-%m-%d %H:%M') nightly read-ahead ==="

# Another run in the folder: say so and end quietly.
python3 -u "$TOOLS/teach_store.py" busy "$FOLDER" > /dev/null 2>&1
LOCKED="$?"
if [ "$LOCKED" -eq 3 ]; then
  say "Another teaching run is already working in the teaching folder, so tonight's read-ahead is skipped."
  exit 0
elif [ "$LOCKED" -ne 0 ]; then
  say "The teaching folder $FOLDER cannot be used, so tonight's read-ahead did not start."
  exit 1
fi

# Exit 3 of teach_ahead.py is "nothing to do tonight", said in one line by the tool itself.
step "Step 1 of 5: choosing tonight's episodes from the phone's list" python3 -u "$TOOLS/teach_ahead.py" pick --folder "$FOLDER" --budget "$BUDGET" --cap "$CAP" --estimate "$ESTIMATE" --most "$MOST"
PICKED="$?"
if [ "$PICKED" -eq 3 ]; then
  exit 0
elif [ "$PICKED" -ne 0 ]; then
  say "Choosing tonight's episodes did not work (see above), so nothing was read ahead."
  exit 1
fi

step "Step 2 of 5: downloading them" $CAFFEINATE python3 -u "$TOOLS/teach_collect.py" --folder "$FOLDER" --only-ahead --max-gb "$MAX_GB"
GATHERED="$?"
if [ "$GATHERED" -eq 3 ]; then
  say "Not everything can be downloaded: the audio kept in the teaching folder has reached its limit of $MAX_GB GB. To go on, raise TEACH_MAX_GB (the number near the top of teach-ahead.sh and teach-weekly.sh). The night goes on with what was downloaded."
  STATUS=1
elif [ "$GATHERED" -ne 0 ]; then
  say "Downloading did not work (see above). The night goes on with what is already there."
  STATUS=1
fi

# No audio (for instance no network) means nothing to write down or mark: end quietly.
python3 -u "$TOOLS/teach_ahead.py" ready --folder "$FOLDER" 2>&1 | tee -a "$LOG"
if [ "${PIPESTATUS[0]}" -eq 3 ]; then
  exit "$STATUS"
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
  say "Writing down what is said was left out. The night goes on."
  STATUS=1
else
  $CAFFEINATE python3 -u "$TOOLS/teach_transcribe.py" --folder "$FOLDER" --tool "$TRANSCRIBER" --only-ahead 2>&1 | tee -a "$LOG"
  if [ "${PIPESTATUS[0]}" -ne 0 ]; then
    say "Writing down what is said did not finish (see above). The night goes on with what is done."
    STATUS=1
  fi
fi

# Exit 5 is the budget reached: the weekly cap doing its job, not a failure.
step "Step 4 of 5: having Claude mark the ads, under the weekly cap of about \$$CAP (this uses your Claude usage allowance)" $CAFFEINATE python3 -u "$TOOLS/teach_label.py" --folder "$FOLDER" --yes --only-ahead --limit "$MOST" --budget "$BUDGET" --cap "$CAP" --reserve "$ESTIMATE"
MARKED="$?"
if [ "$MARKED" -eq 5 ]; then
  say "This week's cap of \$$CAP is reached, so no more episodes are marked until next week. What was marked is saved."
elif [ "$MARKED" -ne 0 ]; then
  say "Marking did not finish (see above). What was marked is saved. The night goes on."
  STATUS=1
fi

step "Step 5 of 5: telling the phone where the ads are" python3 -u "$TOOLS/teach_ahead.py" write --folder "$FOLDER"
if [ "$?" -ne 0 ]; then
  say "The list of marked episodes could not be written (see above)."
  STATUS=1
fi
python3 -u "$TOOLS/teach_publish.py" --folder "$FOLDER" 2>&1 | tee -a "$LOG"
PUBLISHED="${PIPESTATUS[0]}"
if [ "$PUBLISHED" -eq 3 ]; then
  say "The list reached the Mac's own folder, but the copy into iCloud Drive did not work, so the phone does not have it yet. Give /bin/bash Full Disk Access (or fix iCloud Drive)."
  STATUS=1
elif [ "$PUBLISHED" -ne 0 ]; then
  say "The list did not reach the phone's folders (see above)."
  STATUS=1
fi

if [ "$STATUS" -eq 0 ]; then
  say "Tonight's read-ahead is done."
else
  say "Tonight's read-ahead is done, but not every step worked (see above)."
fi
exit "$STATUS"
