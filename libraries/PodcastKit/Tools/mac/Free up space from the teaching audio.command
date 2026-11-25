#!/bin/bash
# Double-click in Finder. Frees disk space by deleting the audio of the teaching episodes whose
# lessons are already kept (teach_free.py): an episode's audio goes only when it has been written
# down and marked, its sound bank is saved (written by "Teach the phone again") and it has been
# compared with its second download, and it is not on the shelf, in the exam or waiting in the nightly
# read-ahead. The transcripts, the marks, the sound banks, the models and every other small file stay,
# and the episode is written down in the list so it is never downloaded again. It first shows how much
# would be freed and asks for a typed yes (anything else deletes nothing; typing all also frees the
# episodes still waiting for a second download and gives up that comparison for them). Before it
# deletes anything it makes a backup of the marks and checks it; if that is not good, nothing is
# deleted. It takes the teaching folder's lock, so it says to wait when a gather, a writing down or a
# marking run is still working. It costs nothing and uses no Claude allowance. Run it between big
# runs, when the gathering has stopped because the disk is nearly full.
# What it prints is also added to ~/Storyteller Lofi/logs/podcast-teaching.log.
HERE="$(cd "$(dirname "$0")" && pwd)"
FOLDER="$HOME/Storyteller Lofi/PodcastTeaching"
LOG_FOLDER="$HOME/Storyteller Lofi/logs"
LOG="$LOG_FOLDER/podcast-teaching.log"
TOOL="$HERE/teach_free.py"

finish() {
  echo
  echo "$1"
  read -r -p "Press Return to close this window. " _
  exit "${2:-0}"
}

echo "Storyteller Lofi: free up space from the teaching audio"
echo
echo "This deletes the audio of episodes that are already written down, marked and saved in the"
echo "sound bank. What they taught (the transcripts, the marks, the sound banks, the models) stays, and"
echo "they are never downloaded again. The shelf, the exam and the read-ahead keep their audio. A backup"
echo "of the marks is made first. It costs nothing and uses no Claude allowance. If it says the sound"
echo "bank is missing, double-click 'Teach the phone again' first."
echo
command -v python3 > /dev/null || finish "python3 is missing. Install Apple's command line tools: open Terminal and run xcode-select --install" 2
[ -f "$TOOL" ] || finish "$TOOL is missing, so nothing can be done." 2
mkdir -p "$LOG_FOLDER" || finish "Could not make $LOG_FOLDER." 2
[ -d "$FOLDER" ] || finish "There is no teaching folder at $FOLDER, so there is nothing to free." 2

echo "=== $(date '+%Y-%m-%d %H:%M') free up space: looking ===" >> "$LOG"
SAID="$(python3 -u "$TOOL" --folder "$FOLDER" 2>&1)"
CODE="$?"
echo "$SAID" | tee -a "$LOG"
case "$CODE" in
  0) ;;
  3) finish "A teaching run is still working in the folder. Double-click this again when it has finished." 3 ;;
  *) finish "It could not look at the teaching folder (see above)." 2 ;;
esac
NOTHING=no
echo "$SAID" | grep -q "nothing to free" && NOTHING=yes
MORE=no
echo "$SAID" | grep -q "gives up that comparison" && MORE=yes
[ "$NOTHING" = yes ] && [ "$MORE" = no ] && finish "Nothing to do." 0

echo
if [ "$NOTHING" = yes ]; then
  read -r -p "Type all to delete that audio: " TYPED
elif [ "$MORE" = yes ]; then
  read -r -p "Type yes to delete the first group, or all to delete the waiting ones too: " TYPED
else
  read -r -p "Type yes to delete that audio: " TYPED
fi
# Only the ends are trimmed: "ye s" is not yes.
TYPED="$(echo "$TYPED" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | tr '[:upper:]' '[:lower:]')"
OPTION=""
if [ "$TYPED" = all ] && [ "$MORE" = yes ]; then
  OPTION="--without-copies"
elif [ "$TYPED" = yes ] && [ "$NOTHING" = no ]; then
  OPTION=""
else
  finish "Nothing was deleted, because you did not type what was asked." 0
fi

echo "=== $(date '+%Y-%m-%d %H:%M') free up space: deleting ===" >> "$LOG"
python3 -u "$TOOL" --folder "$FOLDER" --delete $OPTION 2>&1 | tee -a "$LOG"
CODE="${PIPESTATUS[0]}"
case "$CODE" in
  0) finish "Done. The lines above say how much was freed." ;;
  1) finish "Nothing was deleted, because the backup of the marks was not good (see above). Double-click this again; if it keeps failing, tell Claude what the lines above say." 1 ;;
  3) finish "A teaching run started working in the folder meanwhile, so nothing was deleted. Double-click this again when it has finished." 3 ;;
  *) finish "It did not work (see above)." 2 ;;
esac
