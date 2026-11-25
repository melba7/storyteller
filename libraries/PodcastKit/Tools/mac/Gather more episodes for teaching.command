#!/bin/bash
# Double-click in Finder. Gathers about 500 more episodes of the shows you follow (the newest 12 of
# each show, up to 40 GB of audio in all, keeping 15 GB of the disk free) and writes down what is
# said in them: it starts "Gather episodes for teaching" with those numbers. When you type yes at
# the start, Claude then marks the ads in them, only at night, over several nights, and the
# results are worked out ("Mark the new episodes at night"). It asks once, at the start. If you do
# not type yes it only gathers, and nothing is marked. TEACH_YES=1 in the environment answers yes.
# Everything it prints is also added to ~/Storyteller Lofi/logs/podcast-teaching.log.
# For the tests, these can be set: TEACH_GATHER and TEACH_NIGHT (the files that are started).
HERE="$(cd "$(dirname "$0")" && pwd)"
GATHER="${TEACH_GATHER:-$HERE/Gather episodes for teaching.command}"
NIGHT="${TEACH_NIGHT:-$HERE/Mark the new episodes at night.command}"
LOG_FOLDER="$HOME/Storyteller Lofi/logs"
LOG="$LOG_FOLDER/podcast-teaching.log"

finish() {
  echo
  echo "$1"
  read -r -p "Press Return to close this window. " _
  exit "${2:-0}"
}

[ -x "$GATHER" ] || finish "$GATHER is missing, so nothing can be started." 2
mkdir -p "$LOG_FOLDER" || finish "Could not make $LOG_FOLDER." 2

echo "Storyteller Lofi: gather more episodes for teaching"
echo
echo "This downloads more episodes of the shows you follow: the newest ${TEACH_PER_SHOW:-12} of each"
echo "show, up to ${TEACH_MAX_GB:-40} GB of audio in all. It keeps 15 GB of the disk free, and it writes down what"
echo "is said in them. That takes hours. Keep the Mac plugged in with the lid open."
echo
echo "Then Claude can mark the ads in them, but only between 11 at night and 7 in the morning,"
echo "over several nights, and it uses at most \$95 of the Claude plan's usage in all. When it is done,"
echo "the results are worked out and copied to the phone's folders."
echo "The marking uses the Claude plan this Mac is signed in to and shares its usage allowance."
echo "You can stop with Control-C and double-click this file again later to carry on."
echo

if [ "$TEACH_YES" = 1 ]; then
  TYPED=yes
else
  read -r -p "Type yes to include the marking, or press Return to only gather: " TYPED
fi
# Only the ends are trimmed: "ye s" is not yes.
TYPED="$(echo "$TYPED" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | tr '[:upper:]' '[:lower:]')"

# Both can be set before this file starts (a deeper run asks for more of each show); the default is
# the newest 12 of each show and 40 GB.
TEACH_PER_SHOW="${TEACH_PER_SHOW:-12}"
TEACH_MAX_GB="${TEACH_MAX_GB:-40}"
export TEACH_PER_SHOW TEACH_MAX_GB
unset TEACH_EXAM  # this is never the exam
if [ "$TYPED" = yes ]; then
  echo "=== $(date '+%Y-%m-%d %H:%M') gather more: with the marking at night ===" >> "$LOG"
  [ -x "$NIGHT" ] || finish "$NIGHT is missing, so nothing can be started." 2
  TEACH_AFTER="$NIGHT"
  TEACH_YES=1
  export TEACH_AFTER TEACH_YES
else
  echo "=== $(date '+%Y-%m-%d %H:%M') gather more: gathering only ===" >> "$LOG"
  echo "Nothing will be marked. Double-click \"Mark the new episodes at night\" later to do that."
  echo
  unset TEACH_AFTER TEACH_YES
fi
exec "$GATHER"
