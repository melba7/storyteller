#!/bin/bash
# Double-click in Finder (a copy lives at "~/Storyteller Lofi/Score atmosphere.command").
#
# Scores the atmosphere (which quiet sounds play under each scene, and where the
# narration pauses briefly for a swell) of every read-aloud EPUB in
# "~/Storyteller Lofi/Books", through your Claude plan: no API key and no extra
# cost, only the plan's usage limits. Then it fetches recordings for any new
# sounds the books asked for and copies the tracks and sounds into
# "~/Storyteller Lofi/LofiMusic", ready to import on the phone.
#
# Books already scored are skipped, and a stopped run carries on where it
# stopped. A long novel takes most of an hour; two books are scored at a time.
ROOT="$HOME/Storyteller Lofi"
CLONE="$ROOT/atmosphere-tools"
BOOKS_DIR="$ROOT/Books"
PATH="$PATH:/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin"

finish() {
  echo
  read -r -p "$1 Press Return to close this window. " _
  exit "${2:-0}"
}

[ -d "$CLONE/.git" ] || finish "The tools folder $CLONE is missing; ask Claude in the atmosphere thread to set it up." 1
command -v claude > /dev/null || finish "Claude Code isn't installed in Terminal. Install it, run 'claude' once and sign in, then double-click this again." 1
mkdir -p "$BOOKS_DIR"
shopt -s nullglob
books=("$BOOKS_DIR"/*.epub)
[ ${#books[@]} -gt 0 ] || { open "$BOOKS_DIR"; finish "No books yet: put read-aloud EPUBs (Storyteller's read-aloud download of a book) in the Books folder that just opened, then double-click this again." 1; }

echo "Updating the tools..."
git -C "$CLONE" pull --ff-only --quiet || echo "(could not update; using the tools as they are)"
cd "$CLONE/libraries/LofiScoreKit" || finish "The tools folder looks broken." 1
echo "Scoring ${#books[@]} book(s): ${books[*]##*/}"
Tools/mac/make-atmosphere.sh --via plan --parallel 2 "${books[@]}"
finish "Done."
