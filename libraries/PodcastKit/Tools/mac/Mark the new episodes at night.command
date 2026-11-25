#!/bin/bash
# Double-click in Finder, or started by "Gather more episodes for teaching". Has Claude mark the ads
# in the transcribed teaching episodes that have no mark yet, only between 11 at night and 7 in the
# morning (the Mac stays awake and waits for the night), and then runs the steps after marking. It
# is "Mark ads in the teaching episodes" with night hours, up to $95 of the Claude plan's usage, and
# waiting up to 120 hours (five days) when the usage allowance is used up. A stopped run carries on
# where it was when you double-click again. TEACH_YES set in the environment answers the typed
# yes (only when it is exactly 1); without it the marking asks for it. These can be changed:
# TEACH_BETWEEN (default 23-7), TEACH_WAIT_HOURS (default 120) and TEACH_CAP (default 95).
# The 95 dollars are counted over every run, under the budget TEACH_BUDGET: double-clicking again
# carries on with what is left of them and never starts a fresh 95. When TEACH_BUDGET is not set the
# budget is the name in current-budget.txt in the teaching folder, which "Start another big run"
# writes, so a stopped run is carried on under its own budget; with no such file, or one that does
# not hold a usable name (1 to 40 letters, digits, - or _, starting with a letter or digit), it is
# big-run-1 (the first big run of 2026-11-24; the run before it used more-episodes and has $89.57
# spent). The window says which budget it uses. To start a new budget on purpose, set TEACH_BUDGET
# to a new name or double-click "Start another big run".
# The Mac is kept awake for the whole wait (caffeinate -i, in the file this starts).
# What it prints is also added to ~/Storyteller Lofi/logs/podcast-teaching.log.
HERE="$(cd "$(dirname "$0")" && pwd)"
FOLDER="$HOME/Storyteller Lofi/PodcastTeaching"
BUDGET_FILE="$FOLDER/current-budget.txt"
MARK="$HERE/Mark ads in the teaching episodes.command"

finish() {
  echo
  echo "$1"
  read -r -p "Press Return to close this window. " _
  exit "${2:-0}"
}

[ -x "$MARK" ] || finish "$MARK is missing, so nothing can be started." 2

TEACH_BETWEEN="${TEACH_BETWEEN:-23-7}"
TEACH_WAIT_HOURS="${TEACH_WAIT_HOURS:-120}"
TEACH_CAP="${TEACH_CAP:-95}"
# Where the budget comes from: the environment, then the name in current-budget.txt (its first line,
# trimmed, which must be a name the budget file accepts), then big-run-1.
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
    else
      BUDGET_FROM="the default, because $BUDGET_FILE is not a usable budget name"
    fi
  fi
fi
export TEACH_BETWEEN TEACH_WAIT_HOURS TEACH_CAP TEACH_BUDGET

echo "Storyteller Lofi: mark the new episodes at night"
echo
echo "Claude marks the ads in the episodes that are written down and not marked yet, only between"
echo "11 at night and 7 in the morning. It waits for the night, and when the Claude plan's usage"
echo "allowance is used up it waits and carries on, for up to $TEACH_WAIT_HOURS hours. It uses at"
echo "most \$$TEACH_CAP of the plan's usage in all, counted over every night: double-clicking this"
echo "file again carries on with what is left and never starts a new \$$TEACH_CAP. Keep the Mac"
echo "plugged in with the lid open."
echo "It counts the spending under the budget \"$TEACH_BUDGET\" (from $BUDGET_FROM)."
echo "Then the results are worked out and copied to the phone's folders."
echo
exec "$MARK"
