#!/bin/bash
# Not double-clicked: the other teaching files call it. It does the steps after the ads are marked,
# in this order:
#   1. habits   (teach_habits.py)    what each show usually does at its start
#   2. train    (teach_train.py)     the small model that spots ads
#   3. library  (teach_library.py)   the library of known ads
#   4. sounds   (podcast-teach sounds) builds podcast-teach first (swift build)
#   5. score    (podcast-teach score)  the scorecard of the ad skipping
#   6. publish  (teach_publish.py)   copies the results to the folders the phone reads
# A step that fails is said plainly and the later steps still run, except that the two Swift steps
# (4 and 5) are left out together when podcast-teach does not build. It ends with one line per
# step (worked, nothing to do, failed) and exits 0 when publish worked, 1 otherwise. It holds the
# teaching folder's run lock for its whole length (it starts itself again under
# `teach_store.py hold`), so a second window cannot gather, mark or train while it works. When
# another run holds the lock it says so and exits 3 without doing anything.
# Everything it prints is also added to ~/Storyteller Lofi/logs/podcast-teaching.log. It uses no
# Claude allowance.
#
# For the tests, these can be set: TEACH_TOOLS (where the Python tools are, default: next to this
# file), TEACH_KIT (the PodcastKit package folder) and TEACH_FOLDER (the teaching folder).
# Lessons from the other launchers: bash on the Mac is 3.2 (no associative arrays, no ${x,,}, no
# mapfile), so this keeps to plain variables; and a job started by launchd has a short PATH, so
# the usual places are added to it.
HERE="$(cd "$(dirname "$0")" && pwd)"
TOOLS="${TEACH_TOOLS:-$HERE}"
FOLDER="${TEACH_FOLDER:-$HOME/Storyteller Lofi/PodcastTeaching}"
LOG_FOLDER="$HOME/Storyteller Lofi/logs"
LOG="$LOG_FOLDER/podcast-teaching.log"
export PATH="$PATH:/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin:$HOME/.local/bin"

command -v python3 > /dev/null || { echo "python3 is missing. Install Apple's command line tools: open Terminal and run xcode-select --install"; exit 1; }
if [ -z "$TEACH_HOLDING" ]; then
  TEACH_HOLDING=1
  export TEACH_HOLDING
  exec python3 -u "$TOOLS/teach_store.py" hold "$FOLDER" /bin/bash "$0" "$@"
fi
mkdir -p "$LOG_FOLDER" || { echo "Could not make $LOG_FOLDER."; exit 1; }
# Everything below is shown and added to the log; pipefail keeps the exit codes of the tools.
set -o pipefail

CAPTURE="$(mktemp "${TMPDIR:-/tmp}/teach-finish.XXXXXX")" || { echo "Could not make a temporary file."; exit 1; }
trap 'rm -f "$CAPTURE"' EXIT
CAFFEINATE=""
command -v caffeinate > /dev/null && CAFFEINATE="caffeinate -i"
SUMMARY=""

say() { echo "$@" | tee -a "$LOG"; }

# A short fingerprint of a file, or "none" when there is no such file.
fingerprint() { if [ -f "$1" ]; then cksum < "$1"; else echo none; fi; }

# note LABEL RESULT: adds a line to the summary at the end.
note() { SUMMARY="$SUMMARY  $1: $2
"; }

# run_step LABEL OUTPUT COMMAND...: runs a tool, shows what it prints (also in the log) and notes
# whether it worked. OUTPUT is the file the tool writes: "worked" when it is new or changed and
# "nothing to do" when it is not there or the same as before. With OUTPUT "-" the tool worked when
# it said a file was written. Returns 1 when the tool failed, and leaves its own exit code in
# LAST_CODE.
run_step() {
  local label="$1" output="$2" before after code
  shift 2
  before="$(fingerprint "$output")"
  : > "$CAPTURE"
  "$@" 2>&1 | tee -a "$LOG" "$CAPTURE"
  code="${PIPESTATUS[0]}"
  LAST_CODE="$code"
  after="$(fingerprint "$output")"
  if [ "$code" -ne 0 ]; then
    note "$label" "failed"
    say "$label did not work (see above). The steps after it still run."
    return 1
  fi
  if [ "$output" = "-" ]; then
    if grep -q ': written\.' "$CAPTURE"; then note "$label" "worked"; else note "$label" "nothing to do"; fi
  elif [ "$after" = none ] || [ "$after" = "$before" ]; then
    note "$label" "nothing to do"
  else
    note "$label" "worked"
  fi
  return 0
}

echo "=== $(date '+%Y-%m-%d %H:%M') finish: habits, model, library, sounds, score, publish ===" >> "$LOG"

say "Step 1 of 6: working out what each show usually does at its start"
run_step "Habits" "$FOLDER/habits.json" $CAFFEINATE python3 -u "$TOOLS/teach_habits.py" --folder "$FOLDER"

say
say "Step 2 of 6: training the model that spots ads"
run_step "Model" "$FOLDER/ad-model.json" $CAFFEINATE python3 -u "$TOOLS/teach_train.py" --folder "$FOLDER"

say
say "Step 3 of 6: making the library of known ads"
run_step "Library" "$FOLDER/ad-library.json" $CAFFEINATE python3 -u "$TOOLS/teach_library.py" --folder "$FOLDER"

# The two Swift steps: build podcast-teach once, then run it twice.
say
say "Step 4 of 6: building the ad sounds"
KIT=""
for CANDIDATE in "${TEACH_KIT:-$HERE/../..}" "$HOME/Storyteller Lofi/testflight-build/libraries/PodcastKit"; do
  if [ -f "$CANDIDATE/Package.swift" ]; then
    KIT="$(cd "$CANDIDATE" && pwd)"
    break
  fi
done
TEACH_TOOL=""
if [ -z "$KIT" ]; then
  say "Could not find PodcastKit (no Package.swift next to these tools or in testflight-build)."
elif ! command -v swift > /dev/null; then
  say "swift is missing (install Xcode 26 from the App Store)."
elif ! (cd "$KIT" && swift build -c release --product podcast-teach 2>&1 | tee -a "$LOG"; exit "${PIPESTATUS[0]}"); then
  say "podcast-teach did not build (see above)."
else
  TEACH_TOOL="$(cd "$KIT" && swift build -c release --show-bin-path)/podcast-teach"
fi
if [ -z "$TEACH_TOOL" ]; then
  note "Sounds" "failed (podcast-teach is not built)"
  note "Score" "failed (left out because podcast-teach is not built)"
  say "The sounds and the score are left out."
else
  run_step "Sounds" "$FOLDER/ad-sounds.json" "$TEACH_TOOL" sounds "$FOLDER"
  say
  say "Step 5 of 6: scoring the ad skipping"
  run_step "Score" "$FOLDER/scorecard.json" "$TEACH_TOOL" score "$FOLDER"
fi

say
say "Step 6 of 6: copying the results to the phone's folders"
run_step "Publish" "-" python3 -u "$TOOLS/teach_publish.py" --folder "$FOLDER"
PUBLISH="$LAST_CODE"

say
say "Summary:"
printf '%s' "$SUMMARY" | tee -a "$LOG"
if [ "$PUBLISH" -eq 0 ]; then
  say "The results are where the phone reads them."
  exit 0
elif [ "$PUBLISH" -eq 3 ]; then
  say "The results reached the Mac's own folder, but the copy into iCloud Drive did not work (see above), so the phone does not have them yet. Give /bin/bash Full Disk Access (or fix iCloud Drive) and run this again."
  exit 1
fi
say "The results did not reach the phone's folders (see above)."
exit 1
