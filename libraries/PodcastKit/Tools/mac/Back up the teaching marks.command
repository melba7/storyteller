#!/bin/bash
# Double-click in Finder. Makes one backup of what the teaching runs have paid for (teach_backup.py):
# the marks Claude made (labels, labels-snapped, labels-second), the transcripts, the second-download
# results (copies) and the small .json files of the teaching folder. It is one file,
# teaching-YYYY-MM-DD-HHMM.tar.gz, in ~/Storyteller Lofi/PodcastTeachingBackups, and the newest 14 of
# them are kept (the one-off before-*.tar.gz files are never removed). The audio and the caches are
# not in it: they are large and can be made again. Then it checks the new file by reading it to the
# end and parsing every JSON file in it. It only reads the teaching folder, takes no lock, so marking
# and teaching may run meanwhile, and uses no Claude usage allowance.
# To check an older backup, or to unpack one into an empty folder, see "Backups" in README.md.
# What it prints is also added to ~/Storyteller Lofi/logs/podcast-teaching.log.
HERE="$(cd "$(dirname "$0")" && pwd)"
FOLDER="$HOME/Storyteller Lofi/PodcastTeaching"
LOG_FOLDER="$HOME/Storyteller Lofi/logs"
LOG="$LOG_FOLDER/podcast-teaching.log"

finish() {
  echo
  echo "$1"
  read -r -p "Press Return to close this window. " _
  exit "${2:-0}"
}

echo "Storyteller Lofi: back up the teaching marks"
echo
echo "This copies the marks, the transcripts and the small files of the teaching folder into"
echo "$HOME/Storyteller Lofi/PodcastTeachingBackups and then checks the copy. It costs nothing and"
echo "uses no Claude allowance. The audio is not copied."
echo
command -v python3 > /dev/null || finish "python3 is missing. Install Apple's command line tools: open Terminal and run xcode-select --install" 2
mkdir -p "$LOG_FOLDER" || finish "Could not make $LOG_FOLDER." 2
[ -d "$FOLDER" ] || finish "There is no teaching folder at $FOLDER, so there is nothing to back up." 2

echo "=== $(date '+%Y-%m-%d %H:%M') backup ===" >> "$LOG"
python3 -u "$HERE/teach_backup.py" make --check --folder "$FOLDER" 2>&1 | tee -a "$LOG"
CODE="${PIPESTATUS[0]}"
case "$CODE" in
  0) finish "Done. What it saved and the check of it are in the lines above. The backups are in $HOME/Storyteller Lofi/PodcastTeachingBackups." ;;
  2) finish "The backup was not made (see above)." 2 ;;
  *) finish "The backup did not work, or the new file did not check out (see above). Nothing older was removed. Double-click this again; if it keeps failing, tell Claude what the lines above say." 1 ;;
esac
