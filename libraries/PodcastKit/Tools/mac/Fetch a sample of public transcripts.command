#!/bin/bash
# Double-click in Finder. Takes a sample (500 episodes by default, TEACH_SPORC_COUNT changes it; a second double-click adds to what is there) of
# the SPoRC public podcast transcripts from Hugging Face and writes them as a teaching folder,
# ~/Storyteller Lofi/PodcastTeachingSporc, so Claude can mark their ads (a separate, asked-for step)
# and the ad model can learn from many more shows than the ones you follow. SPoRC is released for
# research and educational use only, so the files stay on this Mac, are never committed, and what is
# learned from them stays out of a published build. It asks for a typed yes once.
# First time only: it makes its own Python folder (~/Storyteller Lofi/venv-sporc) and installs
# huggingface_hub and pyarrow there from PyPI, then asks you to log in to Hugging Face (a free account
# that has clicked Agree on https://huggingface.co/datasets/blitt/SPoRC; the token is pasted into this
# window by you, kept by Hugging Face's own tool in ~/Storyteller Lofi/hf-cache, and never printed).
# It downloads two files: the episode catalog and one part of the transcripts (the dataset's page does
# not say their size; expect from a few hundred MB to a couple of GB). It uses no Claude usage, no
# audio and no Xcode. Delete ~/Storyteller Lofi/hf-cache when you are done to free the disk.
HERE="$(cd "$(dirname "$0")" && pwd)"
BASE="$HOME/Storyteller Lofi"
VENV="$BASE/venv-sporc"
OUT="$BASE/PodcastTeachingSporc"
LOGS="$BASE/logs"
export HF_HOME="$BASE/hf-cache"

finish() {
  echo
  echo "$1"
  read -r -p "Press Return to close this window. " _
  exit "${2:-0}"
}

COUNT="${TEACH_SPORC_COUNT:-500}"
printf '%s' "$COUNT" | LC_ALL=C grep -Eq '^[0-9]{1,4}$' && [ "$COUNT" -ge 1 ] || COUNT=500

echo "Storyteller Lofi: fetch a sample of public transcripts"
echo
echo "This takes about $COUNT episodes from SPoRC, a public set of podcast transcripts that is released for"
echo "research and educational use only. They stay on this Mac in $OUT, are never"
echo "committed or shared, and what is learned from them stays out of a published build."
echo "It needs a free Hugging Face account that has agreed to the terms at"
echo "https://huggingface.co/datasets/blitt/SPoRC and downloads a few hundred MB to a couple of GB."
echo
command -v python3 > /dev/null || finish "python3 is missing (install the Xcode command line tools: xcode-select --install)." 1
read -r -p "Type yes to go on: " TYPED
TYPED="$(echo "$TYPED" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | tr '[:upper:]' '[:lower:]')"
[ "$TYPED" = yes ] || finish "Nothing was started, because you did not type yes." 0

mkdir -p "$BASE" "$LOGS" || finish "Could not make $BASE." 1
if [ ! -x "$VENV/bin/python" ]; then
  echo "Making its own Python folder (first time only)..."
  python3 -m venv "$VENV" || finish "Could not make the Python folder $VENV." 1
fi
if ! "$VENV/bin/python" -c "import huggingface_hub, pyarrow" > /dev/null 2>&1; then
  echo "Installing huggingface_hub and pyarrow (first time only)..."
  "$VENV/bin/python" -m pip install --quiet --upgrade pip huggingface_hub pyarrow || finish "The install did not work (see above)." 1
fi

if ! "$VENV/bin/python" -c "import sys; from huggingface_hub import get_token; sys.exit(0 if get_token() else 1)" > /dev/null 2>&1; then
  echo
  echo "Not logged in to Hugging Face yet. Before the next step:"
  echo "  1. Make a free account at https://huggingface.co/join (skip if you have one)."
  echo "  2. Open https://huggingface.co/datasets/blitt/SPoRC while signed in and click Agree."
  echo "  3. Make a token with Read access at https://huggingface.co/settings/tokens and copy it."
  echo "Then paste it below (nothing shows while you paste). Say n to the git credential question."
  echo
  if [ -x "$VENV/bin/hf" ]; then
    "$VENV/bin/hf" auth login || finish "The login did not work (see above)." 1
  else
    "$VENV/bin/huggingface-cli" login || finish "The login did not work (see above)." 1
  fi
fi

REPORT="$LOGS/sporc-sample-$(date +%Y%m%d-%H%M%S).txt"
"$VENV/bin/python" "$HERE/sporc_sample.py" --out "$OUT" --count "$COUNT" 2>&1 | tee "$REPORT"
CODE="${PIPESTATUS[0]}"
[ "$CODE" = 0 ] || finish "Nothing was written (see above)." "$CODE"
echo
echo "Saved: $OUT"
command -v open > /dev/null && open "$OUT"
finish "Done. Tell Claude it is finished; the report is in the folder and in $LOGS."
