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
| `LofiMood` | `MoodEngine` and the engines, `MoodTracker`, `MoodEngineCatalog`, `MoodTrack` and its builder | lexicon, Claude and tracks everywhere; the rest on Apple platforms |
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
| `fm`, `fm-tagging` | Apple's on-device model asked for one line (`fm-tagging` does not follow the format; see results) (`bucket=…; valence=…; arousal=…; confidence=…`), `String` output under `permissiveContentTransformations`, falls back on refusal | iOS/macOS 26 with Apple Intelligence on |
| `fast:<model>` | Create ML text classifier trained by `lofi-train` on the newest 160 words of each window | the `.mlmodel`; BERT models need iOS 17+ and Apple's embedding assets |
| `recommended[:<model>]` | what `MoodEngineCatalog` would pick on this device | |
| `claude[:<model>]` | Claude through the Anthropic Messages API, one window per request, answer fixed by a JSON schema (default `claude-opus-5-5`, effort low) | network and an API key; costs money, so it scores books ahead of time rather than during playback |
| `track[…]>…` | a saved mood track played back, with a live engine wherever the track does not reach | a track file from `lofi-eval track` or the in-app builder |

## Claude mood tracks (Mo's choice, 9 Nov 2026)

On-device engines top out at about a third agreement with the reference
labels, so Mo chose **Claude scoring with the Fast engine as fallback**:

1. When a book is added, `MoodTrackBuilder` walks it once in reading order
   and asks `ClaudeMoodEngine` about the causal window at one sentence every
   ~250 narrated words, plus the third sentence of every chapter (where the
   live cadence takes its chapter-start reading). Each request holds only
   `SpoilerGuard.window(at:)` for that sentence: no title, no author, no other
   answers. Entries arrive into a `MoodTrackStore` and are saved as they come,
   so an interrupted build resumes.
2. During playback, `TrackedMoodEngine` answers each reading with the newest
   track entry **at or before** the sentence being narrated, never a later
   one, so the music depends only on narrated text, as with a live engine.
   It uses the Fast engine instead before the first entry, past the part
   scored so far (more than 60 sentences behind), or when the entry's
   sentence in the current window no longer matches the digest stored with it
   (the book was re-aligned since the track was made).
3. The system prompt is `GUIDELINES.md` in prompt form, so Claude answers the
   question the reference labels answer. Structured outputs pin the answer to
   the eight moods; refusals and cut-off answers throw, and
   `FallbackMoodEngine` covers them. Requests to Opus and Sonnet carry
   `fallbacks: "default"` so a classifier refusal is retried server-side.
4. Rate limits, overload and 5xx are retried with `retry-after` or 2, 4, 8 s
   backoff; a rejected key or a bad request is not retried.

Cost, estimated by `lofi-eval track <book> --dry-run` before any call:
a 41,000-word book (*The Thirty-Nine Steps*) is 157 entries, about $1.55 with
Opus 5.5, $0.77 with Sonnet 5.5 and $0.04 with Haiku 5.5 at list prices; a
90,000-word novel is roughly twice that. These are estimates (the thinking
tokens at low effort are a guess) until the Mac run measures real usage;
`lofi-eval run` and `track` print the measured tokens and cost.

```sh
export ANTHROPIC_API_KEY_FILE=~/"Storyteller Lofi"/.anthropic-key   # never commit the key
$B/lofi-eval run --engine claude --in $W/train/test-windows.jsonl --out $W/readings/claude-opus.jsonl --concurrency 4
$B/lofi-eval run --engine claude:haiku-5-5 --in $W/train/test-windows.jsonl --out $W/readings/claude-haiku.jsonl --concurrency 4
$B/lofi-eval track <epub-dir> --dry-run                                       # entries and cost, no calls
$B/lofi-eval track <epub-dir> --engine claude --out book.track.json           # resumable
$B/lofi-eval simulate <epub-dir> --engine fast:Models/LofiMood-maxent-3.mlmodel --track book.track.json
```

Still to decide with Mo once the numbers are in: which model (Opus, Sonnet
or Haiku), and whether to use the Batch API (half price, answers within
hours) for whole-book scoring. Claude knows famous novels, so the
name-masking test matters more for it than for the on-device engines.

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
- `claude-rerun-80.jsonl`: 80 of the test windows (10 per book) labelled a
  second time by Claude, blind to the first pass, to measure label noise.
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

# 2. Train the Fast engine on the 26 training books (3 of them held out for
#    Create ML's validation, so balancing cannot leak copies into it)
$B/lofi-train export --windows $W/sample.jsonl --windows $W/sample2.jsonl \
  --split Tools/data/labels/split.json --balance --validation-books 3 \
  --labels Tools/data/labels/claude-v1.jsonl --labels Tools/data/labels/claude-v2.jsonl
  # add --labels Tools/data/labels/mo-check.jsonl last once it exists
$B/lofi-train train --algorithm maxent --version 3
$B/lofi-train train --algorithm bert --version 3      # optional; see the results below
for m in maxent bert; do
  $B/lofi-eval run --engine fast:Models/LofiMood-$m-3.mlmodel --in $W/train/test-windows.jsonl --out $W/readings/fast-$m.jsonl
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
| lexicon (vs Claude labels) | 320 | 26.2% | 0.215 | 0.124 | 0.5 ms |
| nltagger | 320 | 25.0% | 0.180 | 0.132 | 4.0 ms |
| fm, prompt v1 | 315 | 19.7% | 0.125 | 0.096 | 734 ms |
| fm-tagging, prompt v1 | 0 | no usable answers | | | |
| fast:maxent v1 (1,040 windows) | 320 | 25.3% | 0.176 | 0.118 | 0.9 ms |
| fast:bert v1 (1,040 windows) | 320 | 23.1% | 0.114 | 0.073 | 16 ms |
| TF-IDF + logistic regression, 1,040 train windows (Linux stand-in for `fast:maxent`) | 320 | 30.6% | 0.260 | 0.188 | n/a |
| same, 1,998 train windows | 320 | 31.9% | 0.298 | 0.199 | n/a |
| **Mac round 2** | | | | | |
| fast:maxent v2 (1,998 windows, balanced) | 320 | **31.6%** | **0.278** | **0.191** | 0.9 ms |
| fast:bert v2 (1,998 windows, balanced) | 320 | 22.2% | 0.172 | 0.071 | 17 ms |
| fast:bert v3 (same, `--max-iterations 100`) | 320 | identical to v2 | | | 16 ms |
| fm, prompt v2 | 319 | 19.7% | 0.180 | 0.118 | 812 ms |
| fm, prompt v2, names masked | 319 | 22.3% | 0.215 | 0.143 | 819 ms |
| Claude relabelling 80 test windows blind (`claude-rerun-80.jsonl`) | 80 | 67.5% | | 0.620 | |

Mac rows are from Mo's Mac (macOS 26.6.2, Xcode SDK 27.2) on 9 Nov 2026,
scored against Claude's labels. Round 1 used the first 1,360 windows and
prompt v1; round 2 used both label sets, `--balance` and prompt v2. The raw
readings, models and logs are on the Mac in
`~/Storyteller Lofi/lofi-mood-eval-results/round2/`.

What the first Mac run showed:

- **fm, prompt v1** answered tense, somber or hopeful almost every time and
  never calm. The prompt's format example was `bucket=tense; …`, and a small
  model copies examples. Prompt v2 shows a placeholder instead, says that most
  of a novel is calm, and adds the tie-breaks from the guidelines. 17 of 1,360
  answers said `bucket=tension`; nouns like that now parse.
- **fm-tagging** (the content-tagging adapter) ignores the answer format and
  replies with topic tags ("emotion analysis"), and refused 48 of 320 windows.
  It is not usable for this and should not be offered.
- **fast:maxent** reached 100% training accuracy in 4 iterations, so it
  memorised the 1,040 windows; it is no better than the lexicon. `--balance`
  and the 1,998-window set help the Linux stand-in a little.
- **fast:bert** only ever predicted calm, playful or tense and stopped at 40%
  training accuracy: it had not finished learning.
- Drift: on the first 15% of famous books fm was 14 points darker than on
  obscure ones (relative to fast:bert), but it was about 81% dark everywhere,
  so the test says little until fm stops answering dark by default. Masking
  names changed 8.7% of its answers on famous books.

What the second Mac run showed:

- **fast:maxent v2 is the best engine so far** (31.6% exact, kappa 0.19), and
  the only one that predicts all eight moods in useful amounts. It rarely says
  somber (4 of 24 somber windows found) and often calls mysterious windows
  calm. The Linux stand-in predicted it closely (31.9%).
- **Create ML's validation accuracy was meaningless** (90.9% for maxent while
  test was 30.6%): with `--balance`, its automatic validation split held copies
  of training rows. `lofi-train export --validation-books N` now holds whole
  books out for validation instead.
- **fast:bert got worse with more data** and `--max-iterations 100` changed
  none of its 320 answers: Create ML appears to keep the best-validation
  checkpoint (iteration 36), and with leaked validation that is the most
  memorised one. Not worth pursuing at this data size.
- **fm, prompt v2** almost stopped failing to parse (1 in 320, a made-up mood
  "reverent thankfulness") but swapped one bias for another: somber 46%,
  hopeful 32%, and calm only 4 times in 320 (31 of the 56 calm windows came
  back somber). The words the prompt explains are the words it answers with.
  Masking names barely moved it (8.3% of answers changed on famous books, 8.9%
  on obscure ones), so it shows no sign of using plot knowledge; it is simply
  not reading mood well.
- **More labels help less and less.** On the Linux stand-in
  (`Tools/eval/learning_curve.py`, unigrams, C=4), 500 training
  windows give 27.5% exact, 1,000 give 29.6%, 1,500 give 30.2% and 1,998 give
  30.6% (mean of 8 random subsets each), so doubling the set again would add
  perhaps a point or two. A bag-of-words model tops out far below the ceiling.

By the rule above, **the Fast engine (maxent) is the default**: it is the best
engine, deterministic, sub-millisecond and plot-blind. fm stays off. Mo's gold
labels may still move the numbers, and the gap to the ceiling is why a
precomputed Claude mood track is now a decision for Mo.

The lexicon says "calm" for two thirds of windows; it is a floor, not a
candidate. A bag-of-words classifier does a little better and gains from the
extra labels, but stays far below the last row, which is the ceiling: the same
labeller agrees with itself about two times in three (most slips are
calm/mysterious, cozy/hopeful and calm/tense), so no engine should be expected
to beat about 65% against these labels, and Mo's gold labels will set the real
ceiling. The BERT-embedding Fast engine and the on-device model need the Mac.
