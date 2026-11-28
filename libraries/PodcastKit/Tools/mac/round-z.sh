#!/bin/bash
# Not double-clicked: "Run the round when it is ready.command" runs it once, from the clone in
# ~/Storyteller Lofi/testflight-build, after it has built and uploaded the app. It does the Mac's
# part of round Z with nobody at the keyboard. It never waits for typed input: every step gets an
# empty standard input. The double-click on the launcher was the yes for all of it, the two paid
# tests included (at most 5 and 15 dollars of the Claude plan's usage, each a hard cap).
#   1. updates the Mac's copy of the teaching tools (~/Storyteller Lofi/podcast-teaching-tools)
#      from the clone, without the .build folders, so the copy keeps its own build
#   2. installs the 20-minute episode preparing and the nightly teaching again, from that copy
#   3. scores the ad skipping ("Score the ad skipping.command", which says its exit code)
#   4. runs the test of Claude's second look (paid, capped at 5 dollars)
#   5. builds the show playbook (paid, capped at 15 dollars), then replays it on the shelf (free)
#   6. the week-before sounds row, and the ends as they are now (the "before" numbers)
#   7. maps for the copies already prepared
#   8. word-exact ends: writes the words of the shelf episodes down again (2 to 4 hours, so it is
#      the last step; a stopped run goes on where it was), then measures the ends again and
#      switches the word-exact ends on only when the bar passes
# The preparing job runs from the tools copy and holds the teaching folder's run lock
# (teach_store.py hold), so step 1 and every step that works in the teaching folder takes the same
# lock first. When another run holds it, this waits: it looks every 30 seconds, for 30 minutes at
# most, and then gives the step up with exit code 3.
# A step that fails says its exit code and the next one still runs. The end lists every step and
# writes ~/Storyteller Lofi/logs/round-z-summary.json (each step, its exit code, its seconds).
# What the steps print is shown and added to ~/Storyteller Lofi/logs/round-z-steps.log. It exits 0
# when every step worked and 1 when one did not. The Mac's bash is 3.2: plain variables only.
# For the tests, ROUND_Z_WAIT_SECONDS and ROUND_Z_WAIT_TRIES change the waiting.
HERE="$(cd "$(dirname "$0")" && pwd)"
SOURCE="$(cd "$HERE/../.." && pwd)"
ROOT="$HOME/Storyteller Lofi"
COPY="$ROOT/podcast-teaching-tools/storyteller/libraries/PodcastKit"
TOOLS="$COPY/Tools/mac"
F="$ROOT/PodcastTeaching"
LOG_FOLDER="$ROOT/logs"
LOG="$LOG_FOLDER/round-z-steps.log"
SUMMARY_FILE="$LOG_FOLDER/round-z-summary.json"
WAIT_SECONDS="${ROUND_Z_WAIT_SECONDS:-30}"
WAIT_TRIES="${ROUND_Z_WAIT_TRIES:-60}"
export PATH="$PATH:/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/opt/homebrew/bin:$HOME/.local/bin:$HOME/.claude/local"
# Nothing below may wait for the keyboard.
exec < /dev/null
set -o pipefail

say() { echo "$@" | tee -a "$LOG"; }

heading() { say; say "=== $1 ==="; }

# copy_tools: puts the clone's PodcastKit over the tools copy. The .build folders are left out, so
# the copy's own build stays, and files that are only in the copy stay too.
copy_tools() {
  mkdir -p "$COPY" || return 1
  COPYFILE_DISABLE=1 tar -C "$SOURCE" --exclude .build -cf - . | tar -C "$COPY" -xf - || return 1
  echo "The tools in $COPY are the new ones."
}

# The script starts itself again as `--held MARKER COMMAND...` under the lock (see locked). The
# marker file says that the lock was got, so an exit code 3 of the command itself is not taken
# for "another run holds the lock".
if [ "$1" = "--held" ]; then
  : > "$2"
  shift 2
  "$@"
  exit "$?"
fi

# locked COMMAND...: runs the command while holding the teaching folder's run lock, waiting for a
# run that holds it. Returns the command's exit code, or 3 when the lock never came free.
locked() {
  local tries=0 code
  while :; do
    if python3 "$HERE/teach_store.py" busy "$F" > /dev/null 2>&1; then
      rm -f "$MARKER"
      python3 -u "$HERE/teach_store.py" hold "$F" /bin/bash "$0" --held "$MARKER" "$@"
      code="$?"
      # Got the lock (the marker is there), or failed in another way than "busy".
      if [ -e "$MARKER" ] || [ "$code" -ne 3 ]; then return "$code"; fi
    fi
    tries=$((tries + 1))
    if [ "$tries" -ge "$WAIT_TRIES" ]; then
      echo "Another teaching run was still working after $tries checks, so this step was given up."
      return 3
    fi
    [ "$tries" -eq 1 ] && echo "Another teaching run is working in the teaching folder. Waiting for it (a look every $WAIT_SECONDS seconds, $WAIT_TRIES at most)."
    sleep "$WAIT_SECONDS"
  done
}

# step LABEL COMMAND...: runs one command of the round, shows what it prints (also in the log),
# says its exit code when it failed, and keeps its result for the summary. It never stops the run.
step() {
  local label="$1" began code seconds
  shift
  say
  say "--- $label"
  began="$(date +%s)"
  "$@" 2>&1 | tee -a "$LOG"
  code="${PIPESTATUS[0]}"
  seconds=$(( $(date +%s) - began ))
  printf '%s\t%s\t%s\n' "$code" "$seconds" "$label" >> "$RESULTS"
  COUNT=$((COUNT + 1))
  if [ "$code" -ne 0 ]; then
    FAILED=$((FAILED + 1))
    say "$label ended with exit code $code. The steps after it still run."
  fi
}

# group NUMBER-AND-NAME FUNCTION: a heading, then the steps of the function.
group() {
  local before="$COUNT"
  heading "$1"
  "$2"
  [ "$COUNT" -eq "$before" ] && say "No commands were given for this step."
}

# build_tool PRODUCT: builds one Swift program in the tools copy. built PRODUCT: where it is then.
build_tool() { cd "$COPY" && swift build -c release --product "$1"; }
built() { echo "$(cd "$COPY" && swift build -c release --show-bin-path 2> /dev/null)/$1"; }

update_the_tools() {
  step "Update the Mac's tools" locked copy_tools
  # The steps below run from the tools copy, so a command may name a tool without its folder.
  cd "$TOOLS" || say "Could not open $TOOLS, so the steps below will fail."
}

install_the_jobs() {
  step "Install episode preparing" env TEACH_INSTALL_YES=1 /bin/bash "$TOOLS/Install episode preparing.command"
  step "Install nightly teaching" env TEACH_INSTALL_YES=1 /bin/bash "$TOOLS/Install nightly teaching.command"
}

score_the_ad_skipping() {
  step "Score the ad skipping" locked /bin/bash "$TOOLS/Score the ad skipping.command"
}

second_look_test() {
  step "Claude's second look test" locked python3 -u "$TOOLS/teach_second_look.py" test "$F" --cap 5 --yes
}

show_playbook() {
  step "Build the show playbook" locked python3 -u "$TOOLS/teach_playbook.py" build "$F" --cap 15 --yes
  step "Build the scoring tool" build_tool podcast-teach
  step "Score the shelf for the replay" locked "$(built podcast-teach)" score "$F" --dump "$F/shelf-dump.json"
  step "Replay the playbook on the shelf" locked python3 -u "$TOOLS/teach_playbook.py" replay "$F" --dump "$F/shelf-dump.json"
}

# Steps 6, 7 and 8 take one line for each command, in the order they must run:
#   step "What it does, in a few plain words" locked COMMAND ARGUMENTS...
# Leave `locked` out for a command that does not work in the teaching folder. The commands run
# from the tools copy's Tools/mac folder; "$TOOLS" is that folder, "$F" the teaching folder,
# `build_tool NAME` builds a Swift program in the tools copy and "$(built NAME)" is its path.

# Step 6: the week-before sounds row and the ends before the rewrite.
week_before_sounds_and_ends_before() {
  step "Build the transcriber" build_tool podcast-transcribe
  step "Build the scoring tool again" build_tool podcast-teach
  step "Score the week-before sounds row" locked "$(built podcast-teach)" score "$F" --labels labels-snapped --stream --week
  step "Measure the ends before the rewrite" locked python3 -u "$TOOLS/teach_end_score.py" --folder "$F"
}

# Step 7: maps for the copies already prepared.
maps_for_the_prepared_copies() {
  :
}

# Step 8, the long one, so it is the last: word-exact ends.
word_exact_ends() {
  step "Write down the words of the shelf episodes again" python3 -u "$TOOLS/teach_words.py" --folder "$F" --tool "$(built podcast-transcribe)"
  step "Measure the ends again and switch on if the bar passes" locked python3 -u "$TOOLS/teach_end_score.py" --folder "$F" --switch-on-pass
}

mkdir -p "$LOG_FOLDER" || { echo "Could not make $LOG_FOLDER."; exit 1; }
command -v python3 > /dev/null || { say "python3 is missing, so nothing was done. Install Apple's command line tools: open Terminal and run xcode-select --install"; exit 1; }
RESULTS="$(mktemp "${TMPDIR:-/tmp}/round-z.XXXXXX")" || { say "Could not make a temporary file."; exit 1; }
MARKER="$RESULTS.held"
trap 'rm -f "$RESULTS" "$MARKER"' EXIT
COUNT=0
FAILED=0
STARTED="$(date +%s)"
# Keep the Mac awake for as long as this runs.
command -v caffeinate > /dev/null && caffeinate -i -w "$$" > /dev/null 2>&1 &

say "=== $(date '+%Y-%m-%d %H:%M') round Z on the Mac ==="
group "1. Update the Mac's copy of the teaching tools" update_the_tools
group "2. Install episode preparing (every 20 minutes) and nightly teaching again" install_the_jobs
group "3. Score the ad skipping" score_the_ad_skipping
group "4. Claude's second look test (paid, at most 5 dollars)" second_look_test
group "5. The show playbook (paid, at most 15 dollars) and its replay on the shelf (free)" show_playbook
group "6. The week-before sounds row, and the ends as they are now" week_before_sounds_and_ends_before
group "7. Maps for the copies already prepared" maps_for_the_prepared_copies
group "8. Word-exact ends (2 to 4 hours)" word_exact_ends

heading "Summary"
while IFS="$(printf '\t')" read -r code seconds label; do
  if [ "$code" -eq 0 ]; then say "  worked: $label ($seconds s)"
  else say "  failed with exit code $code: $label ($seconds s)"; fi
done < "$RESULTS"
python3 - "$RESULTS" "$SUMMARY_FILE" "$STARTED" <<'SUMMARY' || say "The summary file could not be written."
import json, os, sys, time
steps = []
with open(sys.argv[1], encoding="utf-8") as f:
    for line in f:
        code, seconds, label = line.rstrip("\n").split("\t", 2)
        steps.append({"step": label, "code": int(code), "seconds": int(seconds)})
summary = {"version": 1, "startedAt": int(sys.argv[3]), "endedAt": int(time.time()),
           "failed": sum(1 for step in steps if step["code"] != 0), "steps": steps}
with open(sys.argv[2] + ".tmp", "w", encoding="utf-8") as f:
    json.dump(summary, f, indent=2)
    f.write("\n")
os.replace(sys.argv[2] + ".tmp", sys.argv[2])
SUMMARY
if [ "$FAILED" -eq 0 ]; then
  say "Every step worked. The summary is in $SUMMARY_FILE."
  exit 0
fi
say "$FAILED of $COUNT steps did not work (see above). The summary is in $SUMMARY_FILE."
exit 1
