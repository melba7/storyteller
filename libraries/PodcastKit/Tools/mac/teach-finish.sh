#!/bin/bash
# Not double-clicked: the other teaching files call it. It does the steps after the ads are marked,
# in this order:
#   0. snap     (teach_snap.py)      only when the folder copies/ (second downloads) or
#                                    labels-snapped/ exists: moves the borders of Claude's labels
#                                    onto what the two downloads differ in, into labels-snapped/.
#                                    When labels-snapped/ exists (and snapping did not fail) steps 1
#                                    to 6 are given --labels labels-snapped; Claude's own labels are
#                                    never changed.
#   1. habits   (teach_habits.py)    what each show usually does at its start
#   2. train    (teach_train.py)     the small model that spots ads
#   3. library  (teach_library.py)   the library of known ads
#   4. sounds   (podcast-teach sounds) builds podcast-teach first (swift build)
#   5. meaning  (podcast-teach meaning)  the small model that reads what a line means (needs a Mac;
#                                    when it cannot run it says so and the run goes on)
#   6. score    (podcast-teach score)  the scorecard of the ad skipping (it scores the meaning model).
#                                    Before it, "joints" (podcast-teach joints) finds the joints of each
#                                    episode's MP3 file once and keeps them in joints.json, so the
#                                    scorer's joint rows do not read the audio again
#   7. settings (teach_settings.py)  what each new finder may do on each show, from the scorecard
#   8. publish  (teach_publish.py)   copies the results to the folders the phone reads
# A step that fails is said plainly and the later steps still run, except that the Swift steps
# (4, 5 and 6, and the joints before 6) are left out together when podcast-teach does not build. It ends with one line per
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

# A short fingerprint of a file (or of the .json files of a folder), or "none" when there is none.
fingerprint() {
  if [ -f "$1" ]; then cksum < "$1"
  elif [ -d "$1" ]; then cat "$1"/*.json 2> /dev/null | cksum
  else echo none; fi
}

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

echo "=== $(date '+%Y-%m-%d %H:%M') finish: habits, model, library, sounds, meaning, score, settings, publish ===" >> "$LOG"

# Step 0: when second downloads were compared (copies/), or labels-snapped/ is there from an earlier
# run, bring labels-snapped up to date: Claude's label borders are moved onto the second downloads and
# the labels marked since the last time are copied in (teach_snap.py copies a label with no second
# download as it is). The folder's run lock is already held, so teach_snap.py takes none of its own.
# When it fails, the labels-snapped folder may be old, so Claude's own labels are used this time.
# LABELS is what the steps below that read labels are given (unquoted on purpose: nothing, or two
# words).
LABELS=""
SNAPPED=1
if [ -d "$FOLDER/copies" ] || [ -d "$FOLDER/labels-snapped" ]; then
  say "First: bringing the labels in labels-snapped up to date with the second downloads"
  if ! run_step "Snap" "$FOLDER/labels-snapped" python3 -u "$TOOLS/teach_snap.py" --folder "$FOLDER"; then
    SNAPPED=""
    say "Claude's own labels are used this time, not the snapped ones."
  fi
  say
fi
if [ -n "$SNAPPED" ] && [ -d "$FOLDER/labels-snapped" ]; then
  LABELS="--labels labels-snapped"
  say "The steps below read the labels in labels-snapped (Claude's labels with exact borders)."
  say
fi

say "Step 1 of 8: working out what each show usually does at its start"
run_step "Habits" "$FOLDER/habits.json" $CAFFEINATE python3 -u "$TOOLS/teach_habits.py" --folder "$FOLDER" $LABELS

say
say "Step 2 of 8: training the model that spots ads"
run_step "Model" "$FOLDER/ad-model.json" $CAFFEINATE python3 -u "$TOOLS/teach_train.py" --folder "$FOLDER" $LABELS

say
say "Step 3 of 8: making the library of known ads"
run_step "Library" "$FOLDER/ad-library.json" $CAFFEINATE python3 -u "$TOOLS/teach_library.py" --folder "$FOLDER" $LABELS

# The Swift steps: build podcast-teach once, then run it for the sounds, the meaning model, the joints and the score.
say
say "Step 4 of 8: building the ad sounds"
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
  note "Meaning" "failed (left out because podcast-teach is not built)"
  note "Joints" "failed (left out because podcast-teach is not built)"
  note "Score" "failed (left out because podcast-teach is not built)"
  say "The sounds, the meaning model, the joints and the score are left out."
else
  run_step "Sounds" "$FOLDER/ad-sounds.json" "$TEACH_TOOL" sounds "$FOLDER" $LABELS
  say
  # Exit 2 is a set-up problem (no embedder, no shelf, no vector for any line, no usable model); 0
  # also covers "no shelf yet" and "too few episodes". Neither stops the run.
  say "Step 5 of 8: training the model that reads what a line means"
  run_step "Meaning" "$FOLDER/ad-meaning.json" $CAFFEINATE "$TEACH_TOOL" meaning "$FOLDER" $LABELS \
    || say "No new meaning model this time (see above). One already at the phone's folders stays as it is."
  say
  say "Step 6 of 8: finding the joints of the audio, then scoring the ad skipping"
  # The joints are kept in joints.json; a failure here only means the scorer reads the audio itself.
  run_step "Joints" "$FOLDER/joints.json" $CAFFEINATE "$TEACH_TOOL" joints "$FOLDER" \
    || say "No joints were saved this time (see above). The score reads the audio itself."
  run_step "Score" "$FOLDER/scorecard.json" "$TEACH_TOOL" score "$FOLDER" $LABELS
fi

# It reads scorecard.json (exit 0 also when there is none yet: nothing is written). Exit 2 is a
# problem, said above; the settings file is optional, so the run goes on.
say
say "Step 7 of 8: choosing what each new finder may do on each show"
run_step "Settings" "$FOLDER/show-settings.json" python3 -u "$TOOLS/teach_settings.py" --folder "$FOLDER" \
  || say "No new settings this time (see above). The phone keeps the ones it has, or its built-in defaults."

say
say "Step 8 of 8: copying the results to the phone's folders"
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
