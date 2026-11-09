# Mood detection (the text side of LofiScoreKit)

This half of the package answers one question while a readaloud book plays:
*what music fits the story at the sentence being narrated now?* It never reads
past that sentence.

```
EPUB 3 media overlays ──► SpoilerGuard ──► CausalWindow ──► MoodEngine ──► MoodReading ──► director (audio side)
 (LofiText)               (no lookahead)    (text ≤ now)     (LofiMood)     (8 buckets + valence/arousal)
```

## Targets

| Target | What it holds | Runs on |
| --- | --- | --- |
| `LofiScoreCore` | `MoodBucket`, `MoodPoint`, `MoodReading`, `MoodObservation`, shared with the audio side | everywhere |
| `LofiText` | EPUB/OPF/SMIL/XHTML reading with Storyteller's markup, `SpoilerGuard`, `CausalWindow`, `ReadingCadence` | everywhere (pure Foundation) |
| `LofiMood` | `MoodEngine` and the engines, `MoodTracker`, `MoodEngineCatalog` | lexicon everywhere; the rest on Apple platforms |
| `lofi-eval` | windows from books, engine runs with latency, playback simulation | everywhere (engines as available) |
| `lofi-train` | Create ML export and training for the Fast engine | export anywhere, training on macOS |

### Spoiler safety

`CausalWindow` can only be built by `SpoilerGuard`, and the guard only ever
reads sentences at or before the position it is given. The property test in
`Tests/LofiTextTests` checks this on 1,000 random positions: changing any text
after the position never changes the window. Engines receive nothing else.

### Engines

| Engine id | What it is | Needs |
| --- | --- | --- |
| `lexicon` | hand-written cue words, weighted toward the newest sentences | nothing; the baseline |
| `nltagger` | Apple's sentiment score plus the cue words | iOS/macOS NaturalLanguage |
| `fm`, `fm-tagging` | Apple's on-device model asked for one line (`bucket=…; valence=…; arousal=…; confidence=…`), `String` output under `permissiveContentTransformations`, falls back on refusal | iOS/macOS 26 with Apple Intelligence on |
| `fast:<model>` | Create ML text classifier trained by `lofi-train` on the newest 160 words of each window | the `.mlmodel`; BERT models need iOS 17+ and Apple's embedding assets |
| `recommended[:<model>]` | what `MoodEngineCatalog` would pick on this device | |

## Labels

- `Tools/data/labels/GUIDELINES.md` is the one definition of the eight buckets
  for people and models alike (it matches `MoodPrompt`).
- `Tools/data/eval/sample-v1.jsonl.gz` is the frozen sample: 40 causal windows
  from each of 34 public-domain novels (PG-19 texts turned into readaloud
  EPUBs by `Tools/data/make_readaloud.py`), 1,360 in all. Window ids are
  `book:chapter:sentence` and only hold for this exact build, so use the frozen
  file instead of rebuilding the books.
- `claude-v1.jsonl`: Claude's label for every sampled window, judged on the
  text alone.
- `Tools/data/eval/sample-v2.jsonl.gz` and `claude-v2.jsonl`: 958 more
  windows from the 26 training books only (new positions, near-duplicates of
  v1 windows dropped), each labelled by Claude the same way. With v1 that makes
  1,998 training windows; the 320 test windows are unchanged.
- `split.json`: 8 books (320 windows) held out of training. Mo labels these
  blind; they are the test set every engine is scored on.
- Mo's labels come from the labelling page (an artifact with its own small
  database). Claude copies them into `mo-gold.jsonl` (blind, test books) and
  `mo-check.jsonl` (200 spot-checks of Claude's training labels). Pass label
  files to `lofi-train export` in order of trust: a later file wins.

## Running the eval and training on a Mac

Needs macOS 26 with Xcode 26 or its Command Line Tools. Apple Intelligence must
be on for the `fm` engines.

```sh
cd libraries/LofiScoreKit
swift build -c release && swift test
B=.build/release
W=Tools/data/work && mkdir -p $W/readings
gunzip -c Tools/data/eval/sample-v1.jsonl.gz > $W/sample.jsonl
gunzip -c Tools/data/eval/sample-v2.jsonl.gz > $W/sample2.jsonl   # extra training windows
python3 Tools/eval/mask_names.py $W/sample.jsonl > $W/sample.masked.jsonl

$B/lofi-eval engines                      # what can run here

# 1. Off-the-shelf engines on all 1,360 windows (fm takes a while)
for e in lexicon nltagger fm fm-tagging; do
  $B/lofi-eval run --engine $e --in $W/sample.jsonl --out $W/readings/$e.jsonl
done
$B/lofi-eval run --engine fm --in $W/sample.masked.jsonl --out $W/readings/fm.masked.jsonl

# 2. Train the Fast engine on the 26 training books
$B/lofi-train export --windows $W/sample.jsonl --windows $W/sample2.jsonl \
  --split Tools/data/labels/split.json \
  --labels Tools/data/labels/claude-v1.jsonl --labels Tools/data/labels/claude-v2.jsonl
  # add --labels Tools/data/labels/mo-check.jsonl last once it exists
$B/lofi-train train --algorithm maxent
$B/lofi-train train --algorithm bert
for m in maxent bert; do
  $B/lofi-eval run --engine fast:Models/LofiMood-$m-1.mlmodel --in $W/sample.jsonl --out $W/readings/fast-$m.jsonl
done

# 3. Score on the 320 held-out windows (swap in mo-gold.jsonl when it exists)
python3 Tools/eval/score.py --windows $W/train/test-windows.jsonl \
  --labels Tools/data/labels/claude-v1.jsonl --confusion $W/readings/*.jsonl
# Plot-knowledge drift: does fm turn dark early in famous books more than a plot-blind engine?
python3 Tools/eval/score.py --windows $W/sample.jsonl --drift $W/readings/fm.jsonl --against $W/readings/fast-bert.jsonl
python3 Tools/eval/score.py --windows $W/sample.jsonl --masked-pair $W/readings/fm.jsonl $W/readings/fm.masked.jsonl
```

For changes per hour under the plan's director rules, build playback windows
with `Tools/eval/export_windows.sh` (needs the EPUBs from `fetch_books.py` and
`make_readaloud.py`, and `pip3 install pysbd`; it never overwrites the frozen
samples, and its `sample.rebuilt.jsonl` should match `sample-v1` byte for
byte, which it does on Linux) and run
`score.py --director` on readings of `playback.jsonl`, or play a book through
`MoodTracker` with `lofi-eval simulate <epub-dir> --engine NAME`.

## Choosing the default engine

From the plan: the default has no plot knowledge, works offline on every
supported iPhone, and agrees best with Mo's labels. So:

1. Score every engine on the 320 blind windows against `mo-gold.jsonl`
   (exact agreement, close agreement, macro-F1, kappa) with p50/p95 latency.
2. The Fast engine is the default if it is within a few points of the best
   engine: it is deterministic, takes milliseconds, and knows no plots.
3. An LLM engine (`fm`) becomes the default only if it is clearly better *and*
   the drift and name-masking reports show no early-book darkening on famous
   titles. Otherwise it stays an option in Settings, falling back to Fast.
4. Retrain the shipped model on all labelled books (`lofi-train train --all`)
   once the choice is made.

## Results so far

| Engine | Test windows | Exact | Macro-F1 | Kappa | p50 latency |
| --- | --- | --- | --- | --- | --- |
| lexicon (vs Claude labels) | 320 | 26.2% | 0.215 | 0.124 | 0.8 ms |

The lexicon says "calm" for two thirds of windows; it is a floor, not a
candidate. The other engines need the Mac.
