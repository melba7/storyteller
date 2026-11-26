#!/bin/bash
# Double-click in Finder. Takes the public SPoRC sample from 500 up to 1000 episodes and has Claude
# mark the ads in the new ones (and any of the first 500 that were left unmarked), spending at most
# $100 more of your Claude plan's usage: the first $100 went on the first pull under the budget
# sporc-1, this one counts under the budget sporc-2, so the two pulls come to $200 and a second
# double-click of this launcher carries on without passing its own $100.
#   1. "Fetch a sample of public transcripts" with TEACH_SPORC_COUNT=1000. It adds episodes and
#      leaves the transcripts that are already there untouched (the cached download is reused).
#   2. "Mark the public transcripts" with the budget sporc-2 and a cap of $100.
# It asks you to type yes once, which covers both. It runs next to the big run (a separate folder with
# its own lock) and next to a "Test the public marks" that is still training: it writes only new files
# in the public folder and does not run the test. Both runs share one Claude usage allowance, so each
# goes a little slower while both are marking. When it is done, ask Claude to run the test again (the
# new test replaces the old test's folder, so Claude first keeps the numbers of the old one).
# SPoRC is released for research and educational use only, so the files stay on this Mac, are never
# committed, and what is learned from them stays out of a published build.
HERE="$(cd "$(dirname "$0")" && pwd)"
FETCH="$HERE/Fetch a sample of public transcripts.command"
MARK="$HERE/Mark the public transcripts.command"

finish() {
  echo
  echo "$1"
  read -r -p "Press Return to close this window. " _
  exit "${2:-0}"
}

echo "Storyteller Lofi: fetch and mark 500 more public transcripts"
echo
echo "This runs two steps one after the other, with nothing more to click:"
echo "  1. Fetch 500 more public podcast transcripts (SPoRC, research and educational use only; they"
echo "     stay on this Mac and what is learned from them stays out of a published build)."
echo "  2. Have Claude mark their ads. This uses your Claude plan's usage, at about 20 cents an episode,"
echo "     and never more than \$100 more (\$200 with the first pull)."
echo
echo "It runs next to the big run and does not touch the test that is still training. Marking takes"
echo "hours. Keep this window open. If it stops, double-click again and it carries on."
echo
for STEP in "$FETCH" "$MARK"; do
  [ -f "$STEP" ] || finish "A step is missing: $STEP" 2
done
read -r -p "Type yes to start both: " TYPED
TYPED="$(echo "$TYPED" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | tr '[:upper:]' '[:lower:]')"
[ "$TYPED" = yes ] || finish "Nothing was started, because you did not type yes." 0

export TEACH_CHAIN=1 TEACH_SPORC_COUNT=1000 TEACH_SPORC_LIMIT=1000 TEACH_SPORC_CAP=100 TEACH_SPORC_BUDGET=sporc-2

echo
echo "=== Step 1 of 2: fetch 500 more public transcripts ==="
/bin/bash "$FETCH"
CODE=$?
[ "$CODE" = 0 ] || finish "Stopped at step 1: nothing more was fetched (see above). Nothing was marked." "$CODE"

echo
echo "=== Step 2 of 2: mark the new public transcripts ==="
/bin/bash "$MARK"
CODE=$?
case "$CODE" in
  0) finish "Done. The new marks are saved. Tell Claude it is finished." 0 ;;
  5) finish "The spending limit of \$100 more was reached, so marking ended. What was marked is saved. Tell Claude it is finished." 0 ;;
  6) finish "Some episodes failed to be marked (see failures.json in the public folder); the rest are saved. Tell Claude." 6 ;;
  3) finish "Marking stopped: your Claude usage allowance stayed used up for longer than it waits, or Claude is not signed in. What was marked is saved. Double-click again to carry on." 3 ;;
  *) finish "Marking did not finish (see above). What was marked is saved. Double-click again to carry on." "$CODE" ;;
esac
