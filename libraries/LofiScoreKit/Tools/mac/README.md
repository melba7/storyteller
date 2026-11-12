# Mac tools

Scripts for the Mac in `~/Storyteller Lofi`. The two to double-click:

- `install-automatic-scoring.command` sets the Mac up to score books by itself:
  it fetches and builds the tools (`~/Storyteller Lofi/scoring-tools`), asks for
  the Storyteller server's address and login (optional; the password goes into
  the login keychain, never a file), and installs a launchd job that runs
  `lofi-sync.sh` when a book lands in `~/Storyteller Lofi/Books` and every half
  hour. Run it again to change the login or update the tools.
- `stop-automatic-scoring.command` turns that job off.
- `score-atmosphere.command` runs the same sync once, in a Terminal window.

`lofi-sync.sh` is the pipeline: `fetch-books.sh` downloads newly synced
read-aloud books from the server into `Books/` (with `since` in `server.json`,
which the installer writes unless told otherwise, only books whose read-aloud
version is made from then on, plus the titles listed in `Books/wanted.txt`;
books put into `Books/` by hand are always scored); each unscored book gets an
atmosphere track (`make-atmosphere.sh`, Claude Opus through the Claude plan),
written as `tracks/<book>.score.json` and copied with any new sounds into
`LofiMusic` (the folder the phone follows; the name is from when it held the
music); `LofiMusic` is mirrored into its iCloud Drive copy (added and updated,
never deleted), where the phone's linked sounds folder picks it up; and
`push-scores.sh` puts each score inside its book on the server
(`PUT /api/v2/books/<id>/lofi-score`, the fork's route) so the book carries its
own score. While a sound fetch (`fetch-sounds.sh`) is running, nothing is
scored: from launchd the run ends and the next one tries again, in a window it
waits. Logs are in `~/Storyteller Lofi/logs`. The shelved music's mood
track (`make-tracks.sh`, Claude Opus, prompt 3) is only made with
`--with-mood-tracks` or `LOFI_MOOD_TRACKS=1`; see `shelved/lofi-music/README.md`
at the repository root.

The rest: `make-atmosphere.sh` and `make-tracks.sh` (one book at a time, with
`--dry-run` cost estimates), `claude-check.sh`, and `run-mood-eval.sh`,
`try-recipes.sh` and `finetune.sh` for the mood-model work (see
`Docs/MoodDetection.md`). To measure the scorer itself rather than a book, run
`lofi-atmosphere eval` from the clone (see "Scoring accuracy" in
`Docs/Atmosphere.md`).
