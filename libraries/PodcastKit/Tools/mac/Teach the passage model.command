#!/bin/bash
# Double-click in Finder. Tries a small language model on the ad finding (a trial, milestone W5 of the
# plan, nothing of it reaches the phone): teach_passage.py reads every transcript line of the marked
# episodes that are not on the shelf with the MiniLM sentence model, learns from windows of five lines
# how likely each line is inside an ad, and writes its answers for the shelf episodes into
# passage-model.json in ~/Storyteller Lofi/PodcastTeaching (probabilities only, no words). The next
# "Score the ad skipping" shows them as the row "Plus the passage model". It uses the python of the
# python-mood environment in ~/Storyteller Lofi (it has torch, transformers and numpy; finetune.sh in
# libraries/LofiScoreKit/Tools/mac makes it) and Hugging Face's files in ~/Storyteller Lofi/.cache.
# It costs nothing and does not use your Claude plan's usage allowance. The first run may download the
# sentence model (about 90 MB) if the mood work did not already, and it embeds about 700 episodes of
# lines, which may take a few hours; the vectors are kept in passage-cache in the teaching folder, so
# you can close this window and double-click this file again to carry on, and a second run takes
# minutes. TEACH_EPOCHS (default 8) can be set to change the most passes of one fit.
# What it prints is also added to ~/Storyteller Lofi/logs/podcast-teaching.log.
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HOME/Storyteller Lofi"
FOLDER="$ROOT/PodcastTeaching"
VENV="$ROOT/python-mood"
LOG_FOLDER="$ROOT/logs"
LOG="$LOG_FOLDER/podcast-teaching.log"

finish() {
  echo
  echo "$1"
  read -r -p "Press Return to close this window. " _
  exit "${2:-0}"
}

echo "Storyteller Lofi: teach the passage model (a trial)"
echo
echo "This costs nothing and uses no Claude allowance. It may take a few hours the first time."
echo "You can close this window and double-click it again to carry on."
echo
mkdir -p "$LOG_FOLDER" || finish "Could not make $LOG_FOLDER." 1
# Everything below is shown here and added to the log; pipefail keeps the exit codes.
set -o pipefail

PY="$VENV/bin/python"
[ -x "$PY" ] || finish "The python-mood environment is not set up at $VENV. It holds torch, transformers and numpy, and libraries/LofiScoreKit/Tools/mac/finetune.sh makes it." 2
"$PY" -I -c 'import numpy, torch, transformers' > /dev/null 2>&1 \
  || finish "The python-mood environment at $VENV has no numpy, torch or transformers (or they do not import). libraries/LofiScoreKit/Tools/mac/finetune.sh sets it up again." 2
command -v python3 > /dev/null || finish "python3 is missing. Install Apple's command line tools: open Terminal and run xcode-select --install" 2
[ -d "$FOLDER" ] || finish "There is no teaching folder at $FOLDER. Gather, transcribe and mark some episodes, and double-click \"Teach the phone again\", first." 2

# The caches of the mood work: Hugging Face's files, and nothing installed outside ~/Storyteller Lofi.
export HF_HOME="$ROOT/.cache/huggingface" TORCH_HOME="$ROOT/.cache/torch" XDG_CACHE_HOME="$ROOT/.cache" \
  PYTORCH_ENABLE_MPS_FALLBACK=1 TOKENIZERS_PARALLELISM=false HF_HUB_DISABLE_TELEMETRY=1 \
  HF_HUB_DISABLE_PROGRESS_BARS=1 TRANSFORMERS_VERBOSITY=error PYTHONWARNINGS=ignore PYTHONNOUSERSITE=1

# The same labels the teaching steps use: the snapped ones (exact borders) when there are any.
LABELS=()
if [ -d "$FOLDER/labels-snapped" ]; then
  LABELS=(--labels labels-snapped)
  echo "Learning from the labels in labels-snapped."
  echo
fi
CAFFEINATE=""
command -v caffeinate > /dev/null && CAFFEINATE="caffeinate -i"

echo "=== $(date '+%Y-%m-%d %H:%M') passage ===" >> "$LOG"
SAID="$(mktemp "${TMPDIR:-/tmp}/passage-said.XXXXXX")" || SAID="/dev/null"
# Only one run may work in the teaching folder: teach_store.py hold ends with 3 when another does.
python3 -u "$HERE/teach_store.py" hold "$FOLDER" $CAFFEINATE "$PY" -u "$HERE/teach_passage.py" \
  --folder "$FOLDER" --epochs "${TEACH_EPOCHS:-8}" "${LABELS[@]}" 2>&1 | tee -a "$LOG" "$SAID"
CODE="${PIPESTATUS[0]}"
NOTHING=""
grep -q "no answers were written" "$SAID" 2> /dev/null && NOTHING="yes"
[ "$SAID" != "/dev/null" ] && rm -f "$SAID"
case "$CODE" in
  0)
    if [ -n "$NOTHING" ]; then
      finish "Nothing was learned: there are too few marked episodes that are not on the shelf (see above). Mark more episodes, then double-click this again."
    else
      finish "Done. The answers are in $FOLDER/passage-model.json. Now double-click \"Score the ad skipping\" and read the row \"Plus the passage model\" against the last finder row. It is a trial: the plan goes on only when the row passes at least 10 more breaks on both label sets (labels and labels-snapped) with at most 2 more skips where there is no ad."
    fi ;;
  2) finish "The passage model was not made. The reason is in what the tool printed above (no shelf yet, a damaged file in the teaching folder, or the sentence model could not be loaded: it needs the internet once to download, unless the mood work already did)." 2 ;;
  3) finish "Another teaching run is already working in the teaching folder, so nothing was done. Wait for it to finish (or close its window), then double-click this again." 1 ;;
  *) finish "The passage model did not finish (see above). Double-click this again to carry on: what was embedded is kept." 1 ;;
esac
