#!/bin/bash
# Fine-tune a small language model on the mood labels (Mo's Mac), and test it
# the same two ways as the word-embedding recipes: out of fold on every
# labelled book against Claude's labels (and "fits"), paired with the shipped
# recipe, and on people's ratings (EmoBank fiction) against the shipped
# model. Nothing is shipped: the ship rule in Docs/MoodDetection.md decides.
#
#   cd "~/Storyteller Lofi/<clone>/libraries/LofiScoreKit"
#   Tools/mac/finetune.sh [--recipes-dir DIR] [--base NAME] [--variants hard,soft]
#                         [--leans V:A:P,...] [--folds 10] [--epochs 3] [--out DIR] [--smoke]
#   Tools/mac/finetune.sh --convert RESULTS/models/lm-soft-mt1 --lean 1:0:0.3 [--name LofiMood-lm-soft-mt1]
#
# Variants and leans are explained in Tools/eval/finetune_mood.py: "-mt1"
# also teaches the encoder people's ratings (EmoBank non-fiction), and a lean
# V:A:P adds the people's-ratings lean (V pleasant, A energetic) and the
# rare-mood prior shift (P) to the mood head. Every lean is scored both ways.
#
# Run Tools/mac/try-recipes.sh first: this reuses its export
# (Tools/data/work/train), its out-of-fold rows (oof-word.jsonl) and its
# EmoBank readings of the shipped model (emobank/shipped.jsonl). By default it
# takes the newest "*-recipes" results folder. --smoke runs 2 folds of a few
# steps, to check the setup quickly.
#
# Python packages (PyTorch, transformers) go into a virtual environment in
# "~/Storyteller Lofi/python-mood" (Mo agreed on 9 Nov 2026), with pip's and
# Hugging Face's caches in "~/Storyteller Lofi/.cache". Nothing is installed
# system-wide, no sudo; it writes only inside "~/Storyteller Lofi"; never pushes.
# The base model (default sentence-transformers/all-MiniLM-L6-v2, Apache-2.0,
# about 90 MB) is downloaded from Hugging Face once.
set -uo pipefail

ROOT="$HOME/Storyteller Lofi"
PKG="$(cd "$(dirname "$0")/../.." && pwd)"
VENV="$ROOT/python-mood"
EMOBANK="$ROOT/external-data/emobank"
RECIPES_DIR=""
BASE="sentence-transformers/all-MiniLM-L6-v2"
VARIANTS="soft,soft-mt1"
LEANS=""
LEAN=""
FOLDS=10
EPOCHS=3
SMOKE=0
OUT=""
CONVERT=""
NAME=""
while [ $# -gt 0 ]; do
  case "$1" in
    --recipes-dir) RECIPES_DIR="$2"; shift 2 ;;
    --base) BASE="$2"; shift 2 ;;
    --variants) VARIANTS="$2"; shift 2 ;;
    --leans) LEANS="$2"; shift 2 ;;
    --lean) LEAN="$2"; shift 2 ;;
    --folds) FOLDS="$2"; shift 2 ;;
    --epochs) EPOCHS="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --smoke) SMOKE=1; shift ;;
    --convert) CONVERT="$2"; shift 2 ;;
    --name) NAME="$2"; shift 2 ;;
    *) echo "unknown option $1"; exit 2 ;;
  esac
done
[ -n "$OUT" ] || OUT="$ROOT/lofi-mood-eval-results/$(date +%Y-%m-%d-%H%M)-finetune$([ $SMOKE = 1 ] && echo -smoke)$([ -n "$CONVERT" ] && echo -coreml)"
case "$PKG" in "$ROOT"/*) ;; *) echo "Run this from a clone inside ~/Storyteller Lofi (found $PKG)."; exit 2 ;; esac
case "$OUT" in "$ROOT"/*) ;; *) echo "--out must be inside ~/Storyteller Lofi"; exit 2 ;; esac
if [ -z "$RECIPES_DIR" ]; then
  for d in "$ROOT"/lofi-mood-eval-results/*-recipes; do [ -s "$d/oof-word.jsonl" ] && RECIPES_DIR="$d"; done
fi
[ -n "$RECIPES_DIR" ] && [ -s "$RECIPES_DIR/oof-word.jsonl" ] || { echo "No try-recipes.sh results found: run Tools/mac/try-recipes.sh first."; exit 2; }

mkdir -p "$OUT" "$ROOT/.cache" "$ROOT/.tmp-finetune"
exec > >(tee "$OUT/run.log") 2>&1
export PIP_CACHE_DIR="$ROOT/.cache/pip" HF_HOME="$ROOT/.cache/huggingface" TORCH_HOME="$ROOT/.cache/torch" \
  XDG_CACHE_HOME="$ROOT/.cache" TMPDIR="$ROOT/.tmp-finetune" PYTORCH_ENABLE_MPS_FALLBACK=1 \
  TOKENIZERS_PARALLELISM=false HF_HUB_DISABLE_TELEMETRY=1 PIP_DISABLE_PIP_VERSION_CHECK=1 PYTHONNOUSERSITE=1 \
  HF_HUB_DISABLE_PROGRESS_BARS=1 TRANSFORMERS_VERBOSITY=error PYTHONWARNINGS=ignore
# Keep the Mac awake while this runs (caffeinate ships with macOS).
command -v caffeinate >/dev/null && { caffeinate -i -w $$ & }
cd "$PKG"
W=Tools/data/work
L=Tools/data/labels
STEP=0
step() { STEP=$((STEP + 1)); echo; echo "== $STEP. $* ($(date +%H:%M:%S))"; }
die() { echo "STOPPED: $*"; echo "Log: $OUT/run.log"; exit 1; }

step "Python environment in $VENV"
git log -1 --format='%h %s' 2>/dev/null || true
PY="$VENV/bin/python"
make_env() {  # $1 = a Python; PyTorch publishes wheels for some versions only
  rm -rf "$VENV"
  "$1" -m venv "$VENV" && "$PY" -m pip install -q --upgrade pip && "$PY" -m pip install -q torch transformers numpy
}
if [ -x "$PY" ] && "$PY" -I -c 'import torch, transformers' 2>/dev/null; then
  echo "using the existing environment"
else
  OK=0
  for p in python3.13 python3.12 python3.11 python3.10 python3.14 python3 /usr/bin/python3; do
    command -v "$p" >/dev/null 2>&1 || continue
    echo "trying $("$p" --version 2>&1) ($(command -v "$p"))"
    if make_env "$p" >> "$OUT/pip.log" 2>&1; then OK=1; break; fi
    tail -2 "$OUT/pip.log"
  done
  [ $OK = 1 ] || die "could not install torch and transformers for any Python here (see pip.log)"
fi
"$PY" -I -c 'import sys, torch, transformers; print("python", sys.version.split()[0], "| torch", torch.__version__, "| transformers", transformers.__version__, "| device", "mps (Apple GPU)" if torch.backends.mps.is_available() else "cpu")' \
  || die "torch does not import"
du -sh "$VENV" 2>/dev/null | sed 's/^/environment size: /'

if [ -n "$CONVERT" ]; then
  # --convert: Core ML for the app (an .mlpackage, compiled to .mlmodelc,
  # plus a JSON file with the tokenizer's word pieces), checked against
  # PyTorch on the 320 test windows. Adds coremltools to the environment.
  step "Core ML conversion of $CONVERT"
  [ -s "$CONVERT/meta.json" ] || die "no model in $CONVERT (expected meta.json)"
  "$PY" -m pip install -q coremltools >> "$OUT/pip.log" 2>&1 || { tail -3 "$OUT/pip.log"; die "installing coremltools failed"; }
  [ -n "$NAME" ] || NAME="LofiMood-lm-$(basename "$CONVERT" | sed 's/^lm-//')"
  LEAN_ARGS=()
  [ -n "$LEAN" ] && LEAN_ARGS=(--lean "$LEAN")
  "$PY" -I Tools/eval/finetune_mood.py coreml --model "$CONVERT" ${LEAN_ARGS[@]+"${LEAN_ARGS[@]}"} --out "$OUT/coreml" --name "$NAME" \
    --check "$W/train/test-windows.jsonl" 2> >(tee "$OUT/coreml.log" >&2) || die "conversion failed (see coreml.log)"
  xcrun coremlcompiler compile "$OUT/coreml/$NAME.mlpackage" "$OUT/coreml" > "$OUT/compile.log" 2>&1 \
    || { tail -5 "$OUT/compile.log"; die "coremlcompiler failed"; }
  du -sh "$OUT/coreml/"* | sed 's/^/  /'

  step "The app's path: Swift tokenizer + Core ML (lofi-eval lm:) against PyTorch on the 320 test windows"
  swift build -c release --product lofi-eval > "$OUT/build.log" 2>&1 || { grep -E "error" "$OUT/build.log" | head -5; die "lofi-eval build failed"; }
  .build/release/lofi-eval run --engine "lm:$OUT/coreml/$NAME.json" --in "$W/train/test-windows.jsonl" \
    --out "$OUT/coreml/swift-test.jsonl" 2> "$OUT/swift-test.log" || { tail -5 "$OUT/swift-test.log"; die "lofi-eval lm: failed"; }
  PYTHON_TEST=$("$PY" -I Tools/eval/finetune_mood.py read --model "$CONVERT" --in "$W/train/test-windows.jsonl" \
    --leans "${LEAN:-0:0:0}" --out "$OUT/coreml/python-test" 2>> "$OUT/swift-test.log" | tail -1) || die "python read failed"
  python3 -I -c '
import json, statistics, sys
a = {r["id"]: r for r in map(json.loads, open(sys.argv[1])) if r.get("bucket")}
b = {r["id"]: r for r in map(json.loads, open(sys.argv[2])) if r.get("bucket")}
ids = sorted(set(a) & set(b))
same = sum(a[i]["bucket"] == b[i]["bucket"] for i in ids)
dv = max(abs(a[i]["valence"] - b[i]["valence"]) for i in ids)
ms = statistics.median(a[i]["latencyMs"] for i in ids)
print(f"Swift + Core ML vs PyTorch: same mood on {same} of {len(ids)} windows; largest valence difference {dv:.3f}; Swift median {ms:.1f} ms a window")
' "$OUT/coreml/swift-test.jsonl" "$PYTHON_TEST" | tee "$OUT/swift-check.txt"
  step "Done"
  echo "Core ML model: $OUT/coreml ($NAME.mlmodelc and $NAME.json). Nothing was shipped."
  exit 0
fi

step "Labelled windows (from try-recipes.sh's export)"
[ -s "$W/train/train.json" ] && [ -s "$W/train/test.json" ] || die "no export in $W/train: run Tools/mac/try-recipes.sh first"
SETS_PY=(--sets "$L/claude-g2-test-sets.jsonl")
[ -s "$L/claude-g2-v5.jsonl" ] && SETS_PY+=(--sets "$L/claude-g2-v5.jsonl")
echo "recipes results: $RECIPES_DIR"
SHIPPED=""
for f in "$ROOT"/LofiMusic/LofiMood-embed-*.json; do [ -s "$f" ] && SHIPPED="$f"; done
SHIPPED_RECIPE=$(basename "${SHIPPED:-none}" .json | sed -E 's/^LofiMood-embed-word-[0-9]+-?//')
[ -n "$SHIPPED_RECIPE" ] && [ "$SHIPPED_RECIPE" != none ] || SHIPPED_RECIPE=word2-settings
echo "shipped model: ${SHIPPED:-none} (recipe $SHIPPED_RECIPE)"
grep -q "\"recipe\": *\"$SHIPPED_RECIPE\"" "$RECIPES_DIR/oof-word.jsonl" || die "$RECIPES_DIR/oof-word.jsonl has no rows for $SHIPPED_RECIPE"

TRAIN_ARGS=(--data "$W/train" "${SETS_PY[@]}" --base "$BASE" --epochs "$EPOCHS")
# People's ratings (EmoBank non-fiction) for the leans and the -mt variants.
if [ ! -s "$W/emobank-people.jsonl" ] && [ -s "$EMOBANK/emobank.csv" ]; then
  python3 -I Tools/eval/emobank.py people "$EMOBANK" > "$W/emobank-people.jsonl"
fi
if [ -s "$W/emobank-people.jsonl" ]; then
  TRAIN_ARGS+=(--people "$W/emobank-people.jsonl")
else
  echo "no EmoBank people file: no people's-ratings leans or -mt variants"
fi
LEAN_LIST=()
[ -n "$LEANS" ] && LEAN_LIST=(--leans "$LEANS")
OOF_ARGS=(--folds "$FOLDS")
if [ $SMOKE = 1 ]; then
  TRAIN_ARGS+=(--max-steps 20)
  OOF_ARGS=(--folds 10 --only-folds 0,1)
fi

step "Out of fold on every labelled book ($FOLDS folds of whole books; variants $VARIANTS)"
"$PY" -I Tools/eval/finetune_mood.py oof "${TRAIN_ARGS[@]}" "${OOF_ARGS[@]}" --variants "$VARIANTS" ${LEAN_LIST[@]+"${LEAN_LIST[@]}"} --out "$OUT/oof-lm.jsonl" \
  2> >(tee "$OUT/oof.log" >&2) || die "fine-tuning failed (see oof.log)"

step "Compared with the shipped recipe ($SHIPPED_RECIPE), window by window"
# The shipped recipe's and word-2's rows from try-recipes.sh, plus the new ones.
python3 -I -c '
import json, sys
keep = set(sys.argv[2].split(","))
for line in open(sys.argv[1]):
    if json.loads(line)["recipe"] in keep:
        sys.stdout.write(line)
' "$RECIPES_DIR/oof-word.jsonl" "$SHIPPED_RECIPE,word2-settings" > "$OUT/oof-combined.jsonl"
if [ $SMOKE = 1 ]; then
  # Only two folds were run: compare on those books only.
  python3 -I -c '
import json, sys
books = {json.loads(l)["book"] for l in open(sys.argv[2])}
rows = [l for l in open(sys.argv[1]) if json.loads(l)["book"] in books]
open(sys.argv[1], "w").writelines(rows)
' "$OUT/oof-combined.jsonl" "$OUT/oof-lm.jsonl"
fi
cat "$OUT/oof-lm.jsonl" >> "$OUT/oof-combined.jsonl"
python3 -I Tools/eval/oof_compare.py "$OUT/oof-combined.jsonl" --baseline "$SHIPPED_RECIPE" "${SETS_PY[@]}" | tee "$OUT/oof-compare.txt"

step "Models trained on every labelled book"
MODELS=()
IFS=, read -r -a VLIST <<< "$VARIANTS"
for v in "${VLIST[@]}"; do
  "$PY" -I Tools/eval/finetune_mood.py final "${TRAIN_ARGS[@]}" --variant "$v" --out "$OUT/models/lm-$v" \
    2> >(tee "$OUT/final-$v.log" >&2) && MODELS+=("$OUT/models/lm-$v")
done

if [ -s "$W/emobank-windows.jsonl" ] && [ -s "$EMOBANK/emobank.csv" ]; then
  step "People's ratings check (EmoBank fiction): shipped model first"
  READINGS=()
  # The model in LofiMusic now: its readings from the recipes run (a candidate
  # there that has since shipped), else the run's "shipped" readings.
  K=$(basename "${SHIPPED:-none}" .json); K=${K#LofiMood-embed-}
  if [ -s "$RECIPES_DIR/emobank/$K.jsonl" ]; then
    READINGS+=("$RECIPES_DIR/emobank/$K.jsonl")
  elif [ -s "$RECIPES_DIR/emobank/shipped.jsonl" ]; then
    READINGS+=("$RECIPES_DIR/emobank/shipped.jsonl")
  fi
  echo "people's ratings baseline: ${READINGS[0]:-none}"
  for m in ${MODELS[@]+"${MODELS[@]}"}; do
    # Every lean the out-of-fold step scored, one readings file each. (EmoBank
    # windows are under 200 words, so the earlier words never count here.)
    k=$(basename "$m")
    ALL_LEANS="$LEANS"
    [ -n "$ALL_LEANS" ] || ALL_LEANS=$("$PY" -I -c 'import sys; sys.path.insert(0, "Tools/eval"); import finetune_mood as f; print(f.DEFAULT_LEANS)')
    while IFS= read -r path; do
      [ -s "$path" ] && READINGS+=("$path")
    done < <("$PY" -I Tools/eval/finetune_mood.py read --model "$m" --in "$W/emobank-windows.jsonl" \
      --leans "$ALL_LEANS" --engine "$k" --out "$OUT/emobank-$k" 2>> "$OUT/emobank-read.log")
  done
  [ ${#READINGS[@]} -gt 1 ] && python3 -I Tools/eval/emobank.py score "$EMOBANK" "${READINGS[@]}" | tee "$OUT/emobank-score.txt"
else
  echo "no EmoBank windows ($W/emobank-windows.jsonl) or data ($EMOBANK): skipped"
fi

step "Done"
echo "Results: $OUT (oof-compare.txt, emobank-score.txt, models/). Nothing was shipped."
