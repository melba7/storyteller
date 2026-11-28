#!/bin/bash
# Not double-clicked: the launchd job "com.storyteller-lofi.podcast-nightly-teaching" runs it every
# night at 3:30 (Install nightly teaching.command sets that up). It teaches the phone again from
# what was marked that day, by running teach-finish.sh: backup, snap, habits, model, cues, library,
# sounds, meaning, joints, score, settings and the copy to the phone's folders. It makes no call to
# Claude and costs nothing: the marking is done by the other jobs, this only learns from the marks.
# When the score fails, teach-finish.sh makes no new settings from the old scorecard and says so.
# One run at a time is enforced by the tools' lock on the teaching folder, the same one episode
# preparing holds. When another run holds it, this says so in one line and ends with exit 0, and
# the next night tries again. Otherwise it exits with the code of teach-finish.sh (0 when the
# results reached the phone's folders).
# What it prints goes to ~/Storyteller Lofi/logs/podcast-nightly-teaching.log (from launchd) and
# to ~/Storyteller Lofi/logs/podcast-teaching.log. For the tests, TEACH_TOOLS and TEACH_FOLDER can
# be set (see teach-finish.sh). The Mac's bash is 3.2: plain variables only.
HERE="$(cd "$(dirname "$0")" && pwd)"
TOOLS="${TEACH_TOOLS:-$HERE}"
FOLDER="${TEACH_FOLDER:-$HOME/Storyteller Lofi/PodcastTeaching}"
LOG_FOLDER="$HOME/Storyteller Lofi/logs"
LOG="$LOG_FOLDER/podcast-teaching.log"
export PATH="$PATH:/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/opt/homebrew/bin:$HOME/.local/bin"

mkdir -p "$LOG_FOLDER" || { echo "Could not make $LOG_FOLDER."; exit 1; }
command -v python3 > /dev/null || { echo "python3 is missing. Install Apple's command line tools: open Terminal and run xcode-select --install"; exit 1; }

say() { echo "$@" | tee -a "$LOG"; }

SKIPPED="Another teaching run is already working in the teaching folder, so tonight's teaching is skipped. It tries again tomorrow night."
say "=== $(date '+%Y-%m-%d %H:%M') nightly teaching ==="
# Another run in the folder: say so and end quietly. (teach-finish.sh takes the lock itself, so a
# run that starts between this question and its own lock is stopped there with exit 3.)
python3 -u "$TOOLS/teach_store.py" busy "$FOLDER" > /dev/null 2>&1
if [ "$?" -eq 3 ]; then
  say "$SKIPPED"
  exit 0
fi
/bin/bash "$HERE/teach-finish.sh"
CODE="$?"
if [ "$CODE" -eq 3 ]; then
  say "$SKIPPED"
  exit 0
fi
exit "$CODE"
