#!/bin/bash
# Double-click in Finder (a copy lives at "~/Storyteller Lofi/Score atmosphere.command").
#
# Scores every read-aloud EPUB in "~/Storyteller Lofi/Books" through your Claude plan:
# no API key and no extra cost, only the plan's usage limits. It runs
# Tools/mac/lofi-sync.sh in this window, which also fetches newly synced books
# from your Storyteller server (once install-automatic-scoring.command has set
# it up), mirrors the results to the iCloud copy of LofiMusic and puts each
# score inside its book on the server. For each book it makes the atmosphere
# (which quiet sounds play under each scene, where the narration pauses briefly
# for a swell, the one-off sounds): Tools/mac/make-atmosphere.sh, which writes
# "<book>.score.json". Then it fetches recordings for any new sounds the books
# asked for and copies the tracks and sounds into "~/Storyteller Lofi/LofiMusic"
# (the folder the phone follows), ready for the phone.
#
# The shelved music's mood track (which music plays when; Tools/mac/make-tracks.sh)
# is not made unless LOFI_MOOD_TRACKS=1 is set, to spare the plan.
#
# Books already scored are skipped, and a stopped run carries on where it stopped.
# Each step is capped per book (in lofi-sync.sh, at API list prices) so a run that
# goes wrong can't use up the plan; double-click again to carry on past a cap. A long
# novel takes about an hour. With automatic scoring installed this is never needed:
# the same thing runs by itself when a book lands in Books/ and every half hour.
ROOT="$HOME/Storyteller Lofi"
BOOKS_DIR="$ROOT/Books"
PATH="$PATH:/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$HOME/.claude/local"

finish() {
  echo
  read -r -p "$1 Press Return to close this window. " _
  exit "${2:-0}"
}

# The tools: the checkout this command is in, else the one the installer made,
# else the atmosphere thread's clone.
TOOLS=""
HERE="$(cd "$(dirname "$0")" && pwd)"
for candidate in "$HERE/../../../.." "$ROOT/scoring-tools" "$ROOT/atmosphere-tools"; do
  if [ -d "$candidate/.git" ] && [ -d "$candidate/libraries/LofiScoreKit" ]; then
    TOOLS="$(cd "$candidate" && pwd)"
    break
  fi
done
[ -n "$TOOLS" ] || finish "The tools are missing: double-click install-automatic-scoring.command first (it fetches them into $ROOT/scoring-tools)." 1
command -v claude > /dev/null || finish "Claude Code isn't installed in Terminal. Install it, run 'claude' once and sign in, then double-click this again." 1
mkdir -p "$BOOKS_DIR"

echo "Updating the tools in $TOOLS..."
git -C "$TOOLS" pull --ff-only --quiet || echo "(could not update; using the tools as they are)"
SYNC="$TOOLS/libraries/LofiScoreKit/Tools/mac/lofi-sync.sh"
[ -x "$SYNC" ] || finish "The tools in $TOOLS are too old (no lofi-sync.sh); double-click install-automatic-scoring.command to update them." 1

shopt -s nullglob
books=("$BOOKS_DIR"/*.epub)
if [ ${#books[@]} -eq 0 ] && [ ! -f "$ROOT/server.json" ]; then
  open "$BOOKS_DIR"
  finish "No books yet: put read-aloud EPUBs (Storyteller's read-aloud download of a book) in the Books folder that just opened, then double-click this again. Or double-click install-automatic-scoring.command so synced books are fetched from your Storyteller server by themselves." 1
fi
"$SYNC" --interactive --no-pull --tools "$TOOLS"
finish "Done."
