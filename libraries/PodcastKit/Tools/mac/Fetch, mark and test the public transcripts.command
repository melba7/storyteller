#!/bin/bash
# Double-click in Finder. One click for the whole public-transcripts test, in this order:
#   1. "Fetch a sample of public transcripts" (500 episodes from SPoRC, adds to what is there),
#   2. "Mark the public transcripts" (Claude marks the ads, at most 500 episodes and at most $100 of
#      your Claude plan's usage in all, counted under the budget sporc-1),
#   3. "Test the public marks" (trains the ad model with and without the public marks and prints how
#      precision and recall change on the held-out shelf; no Claude usage).
# It asks you to type yes once, which covers all three, and then runs them one after the other in this
# window with nothing more to click. Marking takes many hours, so keep this window open and the Mac
# awake (it keeps itself awake). If you close the window or something stops it, double-click again:
# fetching adds to what is there, marking carries on under the same budget and cannot pass the cap,
# and the test runs once marking has finished. The three single launchers still work on their own.
# SPoRC is released for research and educational use only, so the files stay on this Mac, are never
# committed, and what is learned from them stays out of a published build.
# Settings (all optional): TEACH_SPORC_COUNT, TEACH_SPORC_LIMIT, TEACH_SPORC_CAP, TEACH_SPORC_BUDGET,
# TEACH_SPORC_WAIT_HOURS, as in the single launchers.
HERE="$(cd "$(dirname "$0")" && pwd)"
BASE="$HOME/Storyteller Lofi"
FETCH="$HERE/Fetch a sample of public transcripts.command"
MARK="$HERE/Mark the public transcripts.command"
TEST="$HERE/Test the public marks.command"
WORK="$BASE/PodcastTeachingPublicTest"

finish() {
  echo
  echo "$1"
  read -r -p "Press Return to close this window. " _
  exit "${2:-0}"
}

number() { printf '%s' "$1" | LC_ALL=C grep -Eq '^[0-9]{1,4}$' && [ "$1" -ge 1 ]; }
COUNT="${TEACH_SPORC_COUNT:-500}"
number "$COUNT" || COUNT=500
LIMIT="${TEACH_SPORC_LIMIT:-500}"
number "$LIMIT" || LIMIT=500
CAP="${TEACH_SPORC_CAP:-100}"
number "$CAP" || CAP=100

echo "Storyteller Lofi: fetch, mark and test the public transcripts"
echo
echo "This runs three steps one after the other, with nothing more to click:"
echo "  1. Fetch about $COUNT public podcast transcripts (SPoRC, research and educational use only;"
echo "     they stay on this Mac and what is learned from them stays out of a published build)."
echo "  2. Have Claude mark the ads in up to $LIMIT of them. This uses your Claude plan's usage,"
echo "     at about 15 to 20 cents an episode, and never more than \$$CAP in all."
echo "  3. Train the ad model with and without those marks and show what changed (no Claude usage)."
echo
echo "Marking takes many hours. Keep this window open. If it stops, double-click again and it carries on."
echo
for STEP in "$FETCH" "$MARK" "$TEST"; do
  [ -f "$STEP" ] || finish "A step is missing: $STEP" 2
done
read -r -p "Type yes to start all three: " TYPED
TYPED="$(echo "$TYPED" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | tr '[:upper:]' '[:lower:]')"
[ "$TYPED" = yes ] || finish "Nothing was started, because you did not type yes." 0

export TEACH_CHAIN=1

echo
echo "=== Step 1 of 3: fetch the public transcripts ==="
/bin/bash "$FETCH"
CODE=$?
[ "$CODE" = 0 ] || finish "Stopped at step 1: nothing was fetched (see above). Nothing was marked or tested." "$CODE"

echo
echo "=== Step 2 of 3: mark the public transcripts ==="
/bin/bash "$MARK"
CODE=$?
NOTE=""
case "$CODE" in
  0) ;;
  5) NOTE="The spending limit of \$$CAP was reached, so the test below uses what was marked." ;;
  6) NOTE="Some episodes failed to be marked (see failures.json in the public folder), so the test below uses the rest." ;;
  *) finish "Stopped at step 2: marking did not finish (see above). What was marked is saved. Double-click again to carry on; the test comes after marking." "$CODE" ;;
esac
[ -z "$NOTE" ] || echo "$NOTE"

echo
echo "=== Step 3 of 3: test the public marks ==="
/bin/bash "$TEST"
CODE=$?
[ "$CODE" = 0 ] || finish "Stopped at step 3: the test did not finish (see above). The marks are saved. Double-click again to run the test." "$CODE"

echo
[ -f "$WORK/COMPARE.txt" ] && cat "$WORK/COMPARE.txt"
finish "All three steps are done. Tell Claude it is finished; the table is in $WORK/COMPARE.txt." 0
