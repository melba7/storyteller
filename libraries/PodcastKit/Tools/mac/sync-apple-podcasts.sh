#!/bin/bash
# Reads the shows you follow and the episodes you finished in Apple Podcasts on this Mac and
# writes Podcasts/apple-podcasts.json into ~/Storyteller Lofi/LofiMusic and its iCloud Drive
# copy, where the phone's linked sounds folder picks it up. One way: Apple's files are only
# read. The hourly launchd job from "Install Apple Podcasts sync.command" runs this; it can
# also be run by hand. Logs: ~/Storyteller Lofi/logs/apple-podcasts.log.
HERE="$(cd "$(dirname "$0")" && pwd)"
LOGS="$HOME/Storyteller Lofi/logs"
mkdir -p "$LOGS"
{
  echo "--- $(date '+%Y-%m-%d %H:%M:%S')"
  /usr/bin/python3 "$HERE/apple_podcasts_export.py" "$@"
} >> "$LOGS/apple-podcasts.log" 2>&1
status=$?
tail -n 3 "$LOGS/apple-podcasts.log"
exit $status
