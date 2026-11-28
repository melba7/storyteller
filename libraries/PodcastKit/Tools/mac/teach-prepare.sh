#!/bin/bash
# Not double-clicked: the launchd job "com.storyteller-lofi.podcast-prepare" runs it every 20 minutes
# (at 5, 25 and 45 minutes past the hour; Install episode preparing.command sets that up). It prepares the new episodes of every show you
# follow, so the phone can play the very file the Mac marked, and the Mac's times for the ads hold to
# the frame:
#   0. reads what you tapped on the phone (Undo, Skip ad) and turns it into short lines per show for
#      the marking (teach_taps.py learn). It never stops the run and never spends anything
#   1. picks up to 6 new episodes: the phone's list of next episodes first, then every followed show's
#      episodes of the last 72 hours, newest first (teach_prepare.py pick). The moment they are picked, before anything is downloaded or marked,
#      they are told to the phone as "coming" in ahead-ads.json (teach_coming_publish.py)
#   2. downloads them, with the teaching run's size and disk limits (teach_collect.py --only-ahead)
#   3. writes down what is said in them (podcast-transcribe, after building it)
#   4. has Claude mark the ads in them (teach_label.py --only-ahead), under the budget
#      prepare-<ISO year>-W<ISO week> with a hard stop at $35 a week: it stops before a call that
#      could pass the cap. The pick counts an episode at about $0.19, but one call can cost more,
#      so the marking keeps a reserve of $1.00 (TEACH_PREPARE_RESERVE) and therefore stops at about
#      $34. This is the only step that uses the Claude plan's usage allowance
#   5. downloads each marked episode a second time and compares the two files (teach_copies.py
#      --only-ahead, podcast-ads after building it), then moves the marks onto the exact borders
#      (teach_snap.py)
#   6. puts a copy of each marked episode's audio into the phone's iCloud folder and removes the
#      copies that are 7 days old or over 10 GB (teach_prepared.py publish)
#      (before step 7 the "coming" list is closed: an episode with its copy is in the file with
#      it, one that got none is dropped, so the phone never waits for a copy that is not on its way)
#   7. writes ahead-ads.json, with the copy of each prepared episode and the times in that very file
#      (teach_ahead.py write), and copies it with the other files to the phone's folders
#      (teach_publish.py)
# Before step 1 it checks that the audio can reach iCloud (teach_prepared.py ready): when it cannot
# (no Full Disk Access for /bin/bash, iCloud or this Mac full) it says why and exits 1 without
# picking, downloading or marking anything, so no Claude usage is spent in a run that cannot
# publish.
# It takes the place of the nightly read-ahead (teach-ahead.sh). The episodes join the teaching set
# with their labels, but never become shelf or exam episodes (ahead.json).
# A run with nothing new to pick still runs the steps that finish earlier work (the second
# download, the copy into iCloud, the file for the phone): they do nothing when there is nothing to
# do. A run with no audio to work on skips the writing down and the marking and says so. A step
# that fails is said plainly and the next ones still run, and a failing episode never keeps the
# others from the phone (each tool leaves it out and goes on); it exits 0 when every step worked.
# It holds the teaching folder's run lock for the whole run (it starts itself again under
# `teach_store.py hold`, as teach-ahead.sh does); when another run holds the lock it says so and
# ends quietly (exit 0). It does not skip Sundays. What it prints goes to
# ~/Storyteller Lofi/logs/podcast-prepare.log (and what launchd saw to podcast-prepare-job.log).
#
# launchd starts jobs with no terminal and a short PATH, so the usual places are added to it. The
# Mac's bash is 3.2: plain variables only. These can be set to change the limits (the installer
# passes the first two): TEACH_PREPARE_KEEP_DAYS (days a copy stays in iCloud, 7), TEACH_PREPARE_GB
# (the most GB of copies kept in iCloud, 10), TEACH_PREPARE_CAP (dollars a week, 35),
# TEACH_PREPARE_ESTIMATE (dollars one episode is expected to cost, 0.19, used by the pick),
# TEACH_PREPARE_RESERVE (dollars the pick and the marking keep below the cap, 1.00), TEACH_PREPARE_MOST
# (episodes a run, 6; the weekly cap and not the number of runs limits the spending: the budget is one
# for the whole week and is checked before every call) and TEACH_PREPARE_OWN_GB (the most GB of audio this job's own episodes keep on
# this Mac, 25: the copies waiting for their second download count; other audio in the teaching
# folder from earlier runs does not). For the tests, TEACH_TOOLS, TEACH_KIT and TEACH_FOLDER can be set too.
HERE="$(cd "$(dirname "$0")" && pwd)"
TOOLS="${TEACH_TOOLS:-$HERE}"
FOLDER="${TEACH_FOLDER:-$HOME/Storyteller Lofi/PodcastTeaching}"
KEEP_DAYS="${TEACH_PREPARE_KEEP_DAYS:-7}"
ICLOUD_GB="${TEACH_PREPARE_GB:-10}"
CAP="${TEACH_PREPARE_CAP:-35}"
ESTIMATE="${TEACH_PREPARE_ESTIMATE:-0.19}"
RESERVE="${TEACH_PREPARE_RESERVE:-1.00}"
MOST="${TEACH_PREPARE_MOST:-6}"
OWN_GB="${TEACH_PREPARE_OWN_GB:-25}"
LOG_FOLDER="$HOME/Storyteller Lofi/logs"
LOG="$LOG_FOLDER/podcast-prepare.log"
export PATH="$PATH:/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/opt/homebrew/bin:$HOME/.local/bin:$HOME/.claude/local"

mkdir -p "$LOG_FOLDER" || { echo "Could not make $LOG_FOLDER."; exit 1; }
command -v python3 > /dev/null || { echo "python3 is missing. Install Apple's command line tools: open Terminal and run xcode-select --install"; exit 1; }
set -o pipefail

CAFFEINATE=""
command -v caffeinate > /dev/null && CAFFEINATE="caffeinate -i"
STATUS=0
# The budget of this week, counted over every hour of the week.
BUDGET="prepare-$(date +%G-W%V)"

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

# The first start only: say so in the log and run it all again under the lock.
if [ -z "$TEACH_HOLDING" ]; then
  say "=== $(date '+%Y-%m-%d %H:%M') episode preparing ==="
  TEACH_HOLDING=1
  export TEACH_HOLDING
  # Not exec: the exit code 3 (another run holds the lock) is turned into a quiet end below.
  python3 -u "$TOOLS/teach_store.py" hold "$FOLDER" /bin/bash "$0" "$@"
  HELD="$?"
  if [ "$HELD" -eq 3 ]; then
    say "Another teaching run is already working in the teaching folder, so this run's episode preparing is skipped."
    exit 0
  fi
  exit "$HELD"
fi

# KIT is PodcastKit, where the transcriber and the comparing program are built from.
KIT=""
for CANDIDATE in "${TEACH_KIT:-$HERE/../..}" "$HOME/Storyteller Lofi/testflight-build/libraries/PodcastKit"; do
  if [ -f "$CANDIDATE/Package.swift" ]; then
    KIT="$(cd "$CANDIDATE" && pwd)"
    break
  fi
done

# build PRODUCT: builds a PodcastKit program and sets BUILT to its path, or to nothing (said).
BUILT=""
build() {
  BUILT=""
  if [ -z "$KIT" ]; then
    say "Could not find PodcastKit (no Package.swift next to these tools or in testflight-build)."
  elif ! command -v swift > /dev/null; then
    say "swift is missing (install Xcode 26 from the App Store)."
  elif ! (cd "$KIT" && swift build -c release --product "$1" 2>&1 | tee -a "$LOG"; exit "${PIPESTATUS[0]}"); then
    say "$1 did not build (see above)."
  else
    BUILT="$(cd "$KIT" && swift build -c release --show-bin-path)/$1"
  fi
}

# Before anything is picked or paid for: can this run's audio reach iCloud at all? (The iCloud copy
# is there, a file can really be written into it, this Mac and iCloud have room; the cleaning of old
# copies runs here too.) When not, the reason is said in one line and nothing is spent this run.
python3 -u "$TOOLS/teach_prepared.py" ready --folder "$FOLDER" --keep-days "$KEEP_DAYS" --max-gb "$ICLOUD_GB" 2>&1 | tee -a "$LOG"
if [ "${PIPESTATUS[0]}" -ne 0 ]; then
  say "Nothing was picked or marked this run, so nothing was spent."
  exit 1
fi

# Exit 3 of teach_prepare.py is "nothing to do this run", said in one line by the tool itself.
# What you tapped on the phone, read before the marking so that its lines can go into the prompt. A
# notes file that cannot be read is said and skipped inside the tool; a failing tool never stops the run.
step "Reading what you tapped on the phone" python3 -u "$TOOLS/teach_taps.py" learn --folder "$FOLDER"
if [ "$?" -ne 0 ]; then
  say "What you tapped could not be read into notes (see above). The run goes on."
  STATUS=1
fi

step "Step 1 of 7: choosing this run's episodes" python3 -u "$TOOLS/teach_prepare.py" pick --folder "$FOLDER" --budget "$BUDGET" --cap "$CAP" --estimate "$ESTIMATE" --reserve "$RESERVE" --most "$MOST"
PICKED="$?"
if [ "$PICKED" -ne 0 ] && [ "$PICKED" -ne 3 ]; then
  say "Choosing this run's episodes did not work (see above), so nothing was prepared."
  exit 1
fi

step "Step 2 of 7: downloading them" $CAFFEINATE python3 -u "$TOOLS/teach_collect.py" --folder "$FOLDER" --only-ahead --own-gb "$OWN_GB"
GATHERED="$?"
if [ "$GATHERED" -eq 3 ]; then
  say "Not everything can be downloaded: the audio of this job's own episodes has reached its limit of $OWN_GB GB on this Mac. To go on, raise TEACH_PREPARE_OWN_GB (the number near the top of teach-prepare.sh). The run goes on with what was downloaded."
  STATUS=1
elif [ "$GATHERED" -ne 0 ]; then
  say "Downloading did not work (see above). The run goes on with what is already there."
  STATUS=1
fi

# No audio waiting (for instance no network) means nothing to write down or mark.
python3 -u "$TOOLS/teach_ahead.py" ready --folder "$FOLDER" 2>&1 | tee -a "$LOG"
if [ "${PIPESTATUS[0]}" -ne 3 ]; then
  say
  say "Step 3 of 7: writing down what is said"
  build podcast-transcribe
  if [ -z "$BUILT" ]; then
    say "Writing down what is said was left out. The run goes on."
    STATUS=1
  else
    $CAFFEINATE python3 -u "$TOOLS/teach_transcribe.py" --folder "$FOLDER" --tool "$BUILT" --only-ahead 2>&1 | tee -a "$LOG"
    if [ "${PIPESTATUS[0]}" -ne 0 ]; then
      say "Writing down what is said did not finish (see above). The run goes on with what is done."
      STATUS=1
    fi
  fi

  # Exit 5 is the budget reached: the weekly cap doing its job, not a failure.
  step "Step 4 of 7: having Claude mark the ads, under the weekly cap of about \$$CAP (this uses your Claude usage allowance)" $CAFFEINATE python3 -u "$TOOLS/teach_label.py" --folder "$FOLDER" --yes --only-ahead --limit "$MOST" --budget "$BUDGET" --cap "$CAP" --reserve "$RESERVE" --unknown-cost "$ESTIMATE"
  MARKED="$?"
  if [ "$MARKED" -eq 5 ]; then
    say "This week's cap of \$$CAP is reached, so no more episodes are marked until next week. What was marked is saved."
  elif [ "$MARKED" -ne 0 ]; then
    say "Marking did not finish (see above). What was marked is saved. The run goes on."
    STATUS=1
  fi
fi

say
say "Step 5 of 7: downloading the marked episodes a second time to find the exact borders of the ads"
build podcast-ads
if [ -z "$BUILT" ]; then
  say "The second download was left out, so the marks are not moved onto exact borders this run. The run goes on."
  STATUS=1
else
  $CAFFEINATE python3 -u "$TOOLS/teach_copies.py" --folder "$FOLDER" --tool "$BUILT" --only-ahead 2>&1 | tee -a "$LOG"
  COMPARED="${PIPESTATUS[0]}"
  # Exit 3 is a limit stopping it with episodes waiting, which is not a failure.
  if [ "$COMPARED" -ne 0 ] && [ "$COMPARED" -ne 3 ]; then
    say "The second download did not finish (see above). The run goes on with what is done."
    STATUS=1
  fi
fi
# The snapping copies a label that has no second download as it is, so it always runs.
step "Moving the marks onto the exact borders" python3 -u "$TOOLS/teach_snap.py" --folder "$FOLDER"
if [ "$?" -ne 0 ]; then
  say "Moving the marks did not work (see above). The marks of Claude are used as they are."
  STATUS=1
fi

# Exit 3 is a stop for space or no iCloud folder, said in one line by the tool: not a failure.
step "Step 6 of 7: putting the audio the Mac marked into the phone's iCloud folder" python3 -u "$TOOLS/teach_prepared.py" publish --folder "$FOLDER" --keep-days "$KEEP_DAYS" --max-gb "$ICLOUD_GB"
PREPARED="$?"
if [ "$PREPARED" -ne 0 ] && [ "$PREPARED" -ne 3 ]; then
  say "Not all the audio reached iCloud (see above). The run goes on."
  STATUS=1
fi

# The "coming" list is closed here: what has its copy is in the file with it, the rest is dropped.
python3 -u "$TOOLS/teach_coming_publish.py" settle --folder "$FOLDER" 2>&1 | tee -a "$LOG"

step "Step 7 of 7: telling the phone where the ads are" python3 -u "$TOOLS/teach_ahead.py" write --folder "$FOLDER"
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
  say "This run's episode preparing is done."
else
  say "This run's episode preparing is done, but not every step worked (see above)."
fi
exit "$STATUS"
