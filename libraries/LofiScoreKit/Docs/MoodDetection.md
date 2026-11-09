# Mood detection (the text side of LofiScoreKit)

This half of the package answers one question while a readaloud book plays:
*what music fits the story at the sentence being narrated now?* It never reads
past that sentence.

```
EPUB 3 media overlays ──► SpoilerGuard ──► CausalWindow ──► MoodEngine ──► MoodReading ──► director (audio side)
 (LofiText)               (no lookahead)    (text ≤ now)     (LofiMood)     (11 buckets + valence/arousal)
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
| `embed:<model.json>` | the Fast engine with Apple's on-device embeddings (`sentence`, `word`, `contextual`, or several side by side such as `word+contextual`) instead of a bag of words: the mean vector of the newest 160 words plus the mean of their last part, fed to a small softmax model (`LinearMoodModel`, plain JSON) trained by `lofi-train embed`, with the 160 words before them blended in at a weight chosen with the model | iOS/macOS NaturalLanguage; `contextual` needs iOS 17+ and Apple's embedding assets |
| `recommended[:<model>]` | what `MoodEngineCatalog` picks: the Fast classifier when given, else `nltagger` (the on-device model is opt-in only, via `onDeviceModelEngine`) | |
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
   the eleven moods; refusals and cut-off answers throw, and
   `FallbackMoodEngine` covers them. Requests to Opus and Sonnet carry
   `fallbacks: "default"` so a classifier refusal is retried server-side.
4. Rate limits, overload and 5xx are retried with `retry-after` or 2, 4, 8 s
   backoff; a rejected key or a bad request is not retried.
5. **Change points** (added 9 Nov 2026, for Mo's "start the music without too
   much delay... just enough time to get to that thing"). Entries every 250
   words alone could switch the music up to ~100 s after the text turned.
   After scoring, the builder looks at neighbouring entries whose moods
   differ and scores the sentence halfway between, then halfway again on the
   side where the change fell, until the change is pinned to within 3
   sentences (about 15 s). Probes go best first, by mood jump (anchor
   distance) times the sentences the change could still be late by, so a
   calm-to-tense turn is pinned before a calm-to-cozy drift. A per-book
   budget caps probes at 0.6 x the planned entries (`--refine-budget`,
   `--resolution`). Each probe is an ordinary entry judged only from its own
   causal window, so the music never changes before the narrated text reads
   as the new mood. What does depend on later text is where probes are
   spent: only between entries that disagree. A mood that comes and goes
   between two entries is not looked for, so a change heard in playback is
   slightly more likely than chance to last. That is the accepted price of
   not scoring every sentence. On the lexicon stand-in (which flips far more
   than Claude should), the budget ran out with about half the changes
   pinned, biggest first.
6. **Reading on every sentence.** `MoodEngineCatalog.cadence(for:)` gives
   `ReadingCadence.Configuration.everySentence` to track and Fast engines
   (both answer in milliseconds) and keeps the plan's 4 sentences / 20 s for
   Apple's on-device model. `MoodTracker` uses it unless told otherwise. The
   chapter-start rule is unchanged (first reading on a chapter's third
   sentence). Every `MoodObservation` now says where its reading came from:
   `source == .track` (one reading is enough to act on) or `.live`
   (neighbouring live readings share most of their window, so a run of them
   agreeing proves little). The director in the audio thread weighs them
   differently.

Cost, estimated by `lofi-eval track <book> --dry-run` before any call (prompt
v2, about 1,000 tokens of instructions per request): *A Christmas Carol*
(29,000 words) is 109 entries plus up to 66 probes, about $1.21 with Opus 5.5,
or $1.95 at most with probes; Sonnet 5.5 is half that and Haiku 5.5 about 3
cents. A 120,000-word novel is about four times that: up to ~$8 with Opus
and refinement, ~$4 with Sonnet, ~$0.20 with Haiku. These are estimates (the
thinking tokens at low effort are a guess) until the Mac run measures real
usage; `lofi-eval run` and `track` print the measured tokens and cost, and
`--max-dollars` stops either one before it spends more.

On the Mac, two scripts wrap all of this (both stay inside
`~/Storyteller Lofi`, never print the key, and resume when run again):

```sh
Tools/mac/run-mood-eval.sh            # build, test, retrain Fast v4, score it; Claude only if the key file exists, $6 cap
Tools/mac/make-tracks.sh --dry-run ~/Downloads/*.epub                # what tracks for these books would cost
Tools/mac/make-tracks.sh --cap 10 --engine claude:sonnet-5-5 BOOK.epub  # tracks into ~/Storyteller Lofi/tracks/
```

Make tracks from the read-aloud EPUB exactly as Storyteller serves it. The
app finds a book's track by the digests of its first sentences, not by file
name, so the sentence text must match what `SpoilerGuard` reads on the phone.
To install them, copy the tracks folder into the music folder and import it
in the app; the import collects every `*.track.json`.

By hand:

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

### An outside check: EmoBank (9 Nov 2026)

Every score above is against Claude's labels, so Claude both teaches the
local model and grades it. `Tools/eval/emobank.py` adds a check against
people instead: EmoBank's 2,753 fiction sentences (seven stories, CC-BY-SA
4.0, github.com/JULIELab/EmoBank), each rated by several readers for
valence and arousal. Each sentence becomes a window ending on it, with up to
120 words of the story before it, so engines read it as they read a book.
The data stays out of git (`Tools/data/work`). Scores are Spearman
correlations of each engine's valence and arousal with the people's, with
intervals from resampling stories, and on the sentences people clearly
found pleasant or unpleasant, how often the engine's mood is on that side.
It checks direction and intensity only: emotion ratings say nothing about
calm against cozy or mysterious. Lexicon, as a floor: valence 0.19 (0.11 to
0.25), arousal 0.16 (0.09 to 0.21), same side 71% of 386 clear sentences.

### Claude on the Max plan instead of an API key (9 Nov 2026)

Mo asked whether the Claude steps could run on their Max plan. They can, on
the Mac: `ClaudeCodeTransport` sends each request through Claude Code's
scripted mode (`claude -p`, never `--bare`, which ignores the subscription
login) from an empty folder, with the request's system prompt in place of
Claude Code's own, every tool off, the answer held to the request's JSON
schema, no saved session, and `ANTHROPIC_API_KEY` removed from the child's
environment. It turns Claude Code's JSON result back into a Messages API
response, so `ClaudeMoodEngine`, its retries and its usage counts are
unchanged; "Not logged in" maps to 401 (stop), usage limits to 429 (retry).
`lofi-eval` picks the route with `LOFI_CLAUDE_VIA=plan|api` (default: the API
when a key is set, otherwise the plan). `make-tracks.sh` and
`claude-check.sh` default to `--via plan`. It costs no money but uses the
plan's usage limits, which every Claude session on the account shares, so
runs keep a cap counted at API list prices. Claude Code must be signed in
once on the Mac (`claude`, then log in), or `CLAUDE_CODE_OAUTH_TOKEN` set from
`claude setup-token`.

`Tools/mac/claude-check.sh` scores Claude against the local model on the 320
test passages with the plausible sets, prompt v2 against v3 on the same
windows. Prompt v3 (`LOFI_CLAUDE_PROMPT=3`) asks first for `about`, one line
on what is happening and what is at stake (the schema's keys are sent
sorted, so it is written before the mood), and then for `also`, up to two
other moods whose music would also suit. Those go into the reading's
`scores` after the best mood, so playback can keep music that still fits
instead of switching.

## Labels

- `Tools/data/labels/GUIDELINES.md` is the one definition of the moods for
  people and models alike (it matches `MoodPrompt` and `ClaudeMoodPrompt`).
  Version 2 (9 Nov 2026) added romantic, dreamy and adventurous, the three
  moods Mo asked for, and moved "love declared" from hopeful to romantic.
- `claude-g2-test.jsonl`: the 320 held-out windows under guidelines v2. The
  v1 labels carry over unchanged except where a window belongs to a new
  mood; the 91 windows that might (new-mood cue words in the last 80 words,
  or a v1 label of hopeful) were re-read, and 5 changed
  (`v2-overrides-test.json`, applied by `Tools/data/relabel_v2.py`). The new
  moods are rare in these eight books, so their scores rest on few windows.
- `claude-g2-train.jsonl`: the 1,998 training windows (the other 26 books of
  sample v1, plus sample v2) carried over the same way. 608 were re-read and
  61 changed: 33 romantic, 15 adventurous, 13 dreamy
  (`v2-overrides-train.json`). That is too few for a bag-of-words model to
  learn the new moods well: on a Linux stand-in (TF-IDF and logistic
  regression) training on these labels left the other moods' accuracy
  unchanged and still almost never predicted a new mood. So for now the
  new moods come from Claude tracks; the Fast engine needs more labelled
  examples of them first.
- `Tools/data/eval/sample-v3.jsonl.gz` and `claude-g2-v3.jsonl`: 361 more
  windows from the 26 training books, picked where cue words for romantic,
  dreamy or adventurous appear in the newest words (at least 15 sentences
  from any v1 or v2 window), labelled under guidelines v2 by Claude. They add
  31 romantic, 24 adventurous and 19 dreamy examples. The other 287 got one
  of the older moods, which also shows a model that a cue word alone does not
  make a new mood.
- `Tools/data/eval/sample-v4.jsonl.gz` and `claude-g2-v4.jsonl`: 40 random
  causal windows from each of 19 more public-domain novels (the "famous"
  group at the end of `Tools/data/books.csv`, built the same way as v1),
  760 in all, labelled under guidelines v2 by Claude. They are training data
  only, added because the embedding model's learning curve was still
  climbing at 26 books. With them the export has 3,119 labelled training
  windows from 45 books (42 for training, 3 for validation).
- `claude-g2-test-sets.jsonl`: the 320 test windows re-read blind by
  Claude (9 Nov 2026), each with a best mood (`bucket`) and every mood that
  would also suit it (`accept`, best first). Scored as "fits" by
  `Tools/eval/score.py`; see "Plausible sets" in `GUIDELINES.md`.
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
# Apple's embeddings with a trained softmax head; settings are chosen by
# 5-fold cross-validation over the training books, then it trains on all of
# them; --curve adds a learning curve, --all also trains on the test books.
# (Add --windows $W/sample3.jsonl --windows $W/sample4.jsonl and the
# claude-g2 label files to the export above, as run-mood-eval.sh does.)
$B/lofi-train embed --kinds word,contextual,word+contextual --version 2 --curve
$B/lofi-train embed --kinds word --version 6 --curve     # 45 books (sample v4)
# the model that ships: the chosen kind, trained on every labelled book
$B/lofi-train embed --kinds word --version 7 --all
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
   (exact agreement, close agreement, macro-F1, kappa) with p50/p95 latency,
   and on the plausible sets with `score.py --compare` (fits, and paired
   differences with intervals from resampling whole books). For a new Fast
   recipe, the all-books comparison (`lofi-train oof`) decides: it ships
   when its exact agreement is clearly better, or no more than half a point
   lower with macro-F1 and kappa no worse and one of them clearly better,
   and when fits on the plausible sets is not clearly worse.
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
| **Mac round 3** | | | | | |
| fast:maxent v3 (23 books, 3 held out for validation) | 320 | 28.7% | 0.248 | 0.158 | 0.9 ms |
| Claude relabelling 80 test windows blind (`claude-rerun-80.jsonl`) | 80 | 67.5% | | 0.620 | |
| **Mac round 4, against the eleven-mood labels (`claude-g2-test`)** | | | | | |
| lexicon | 320 | 25.9% | 0.160 | 0.126 | 0.6 ms |
| fast:maxent v3 | 320 | 28.1% | 0.179 | 0.154 | 1.0 ms |
| fast:maxent v4 (23 books, 2,104 windows including sample v3) | 320 | 27.5% | 0.230 | 0.146 | 1.0 ms |
| embed:sentence v1 | 320 | 24.7% | 0.145 | 0.132 | 117 ms |
| embed:word v1 (26 books) | 320 | 35.6% | 0.289 | 0.237 | 10 ms |
| embed:contextual v1 (26 books) | 320 | **36.2%** | **0.318** | **0.251** | 52 ms |
| **Mac round 5, settings by 5-fold cross-validation over the 26 training books** | | | | | |
| embed:word v2 | 320 | 35.3% | 0.295 | 0.234 | 10 ms |
| embed:contextual v2 | 320 | 34.4% | 0.287 | 0.232 | 47 ms |
| embed:word+contextual v2 | 320 | 34.4% | 0.329 | 0.234 | 56 ms |
| **Mac round 6** | | | | | |
| embed:word v4 (settings chosen by kappa: class-weighted) | 320 | 30.6% | 0.268 | 0.209 | 10 ms |
| **Mac round 7** (sample v4: 45 training books) | | | | | |
| embed:word v6 (l2 0.03, earlier words 0.35; CV 37.6%) | 320 | 33.4% | 0.274 | 0.217 | 10 ms |
| embed:word v2 (same run, for comparison) | 320 | 35.3% | 0.295 | 0.234 | 10 ms |
| fast:maxent v5 (45 books) | 320 | 28.7% | 0.226 | 0.158 | 0.8 ms |

Mac rows are from Mo's Mac (macOS 26.6.2, Xcode SDK 27.2) on 9 Nov 2026,
scored against Claude's labels. Round 1 used the first 1,360 windows and
prompt v1; round 2 used both label sets, `--balance` and prompt v2. The raw
readings, models and logs are on the Mac in
`~/Storyteller Lofi/lofi-mood-eval-results/round2/` (round 4:
`2026-11-09-1043/`).

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

Round 3 retrained maxent with three training books held out for Create ML's
validation: validation accuracy now reads 34.4% next to 28.7% on the test
books, instead of round 2's misleading 90.9%. The 3-point drop from v2 is 9
windows of 320 and v3 trained on three fewer books, so it is noise rather than
a regression; the shipped model should be trained with `--all` anyway.
`lofi-train` reports about a point less than `lofi-eval` for the same model
(27.8% vs 28.7%) because training scores only the newest 160 words, while
`ClassifierMoodEngine` blends in the 160 words before them at weight 0.35.

Round 4 tried Apple's on-device embeddings in place of the bag of words
(`embed:`), with settings picked on the three validation books and the model
then trained on all 26 training books. Word and contextual embeddings both
beat every maxent model by 8 to 9 points of exact agreement and about 0.1
kappa on the 320 held-out windows; sentence embeddings did not help. The two
good models agree with each other on only 44% of windows, so they read the
text differently, which is why `word+contextual` (both side by side) is the
next thing to measure. Three validation books proved too few to pick
settings (neighbouring settings swung by 5 points), so `lofi-train embed`
now cross-validates over all 26 training books, and it scores the test books
exactly as the engine reads them. The new moods still have only 1 or 2 test
windows each, so their scores mean little yet.

Round 5 ran that. Cross-validated over the 26 training books, word scored
37.6% exact (kappa 0.255), contextual 37.5% (0.257) and the two side by side
35.4% (0.239); on the test books 35.3%, 34.4% and 34.4%, the same numbers
`lofi-eval` gives, so the trainer and the engine now agree. All three chose
l2 0.1 and the earlier 160 words at weight 0.2. Word ships: it is as good as
the others, five times quicker (10 ms) and built into every iPhone, while
contextual needs an asset download. Its learning curve is still climbing:
on the test books it scored 26.5% trained on 6 books, 31.2% on 13, 33.0% on
19 and 35.3% on 26, about 4 points per doubling, so labelled windows from
more books are the next lever. (Contextual levelled off near 34% from 13
books.) Choosing settings by exact agreement picked unweighted moods; the
class-weighted setting had 2.4 points less exact agreement in
cross-validation but macro-F1 0.291 instead of 0.229 and the same kappa.

Round 6 tested choosing by kappa, which picks that class-weighted setting.
On the test books it lost on every measure (30.6% exact, macro-F1 0.268,
kappa 0.209, against 35.3%, 0.295 and 0.234) and overcorrected: it named
hopeful 45 times where the labels have 20, cozy 40 against 18, and the
three new moods 27 times against 5. So exact agreement stays the default
(`--choose exact|kappa|macro-f1`), and the shipped model is
`LofiMood-embed-word-3.json`: word embeddings, unweighted, l2 0.1, earlier
words at 0.2, trained on all 34 books.

Round 7 added sample v4 (760 windows from 19 more books) to test that
lever, and it did not pay: word v6, trained on 45 books, scored 33.4% on
the test books against word v2's 35.3%, and cross-validation stayed at
37.6% although the pool grew from 26 to 45 books. One standard error on 320
windows is about 2.7 points, so the extra books neither clearly helped nor
clearly hurt. v6 over-predicts tense (79 against 44 in the labels; the new
books are tense-heavy) and still under-predicts somber and hopeful. A
linear head on averaged word embeddings looks saturated near 36%, about
half of Claude's 67.5% self-agreement, so word-3 stays the shipped model and
the bigger accuracy gain is the per-book Claude track, with Fast as its
fallback.

Round 8 changed how engines are tested instead of how they are trained,
at Mo's request: stop adding books until the test can tell a real gain
from luck. The old test had three weaknesses. Each window had one label,
though the labeller agrees with itself only 67.5% of the time, so exact
agreement punished defensible near-misses. The 320 windows come from 8
books, and windows from one book move together, so the real error bar was
wider than the 2.7 points quoted above. And engines were compared by their
separate scores, not window by window. The fixes:

- **Plausible sets** (`claude-g2-test-sets.jsonl`, protocol in
  `GUIDELINES.md`): every test window re-read blind for a best mood plus
  every other mood whose music would clearly suit it. **Fits** counts a
  reading anywhere in the set. Sets hold 1.94 moods on average and the old
  single label falls inside them 95.9% of the time, so the ceiling for fits
  is near 96%, where exact agreement topped out near 67.5%.
- **`score.py --compare`**: each engine's exact and fits with a 95% interval
  from resampling whole books (2,000 draws), then each engine minus the
  first on the same windows, which cancels the luck of the sample they
  share. An interval that includes 0 means the difference could be luck.

The round 7 readings, scored this way (Mac, 9 Nov 2026):

| Engine | Exact (95% interval) | Fits (95% interval) | Minus word-2, exact | Minus word-2, fits |
| --- | --- | --- | --- | --- |
| embed:word v2 (34 books, as shipped) | 36.2% (32.2 to 40.6) | **56.6%** (52.2 to 61.3) | | |
| embed:word v6 (45 books) | 33.4% (27.8 to 38.1) | 56.2% (50.6 to 61.6) | -2.8 (-5.6 to 0.0) | -0.3 (-5.0 to +4.4) |
| fast:maxent v5 | 28.4% (22.5 to 33.8) | 49.7% (42.5 to 55.0) | -7.8 (-16.3 to -0.3) | -6.9 (-15.9 to +0.9) |
| fast:maxent v4 | 25.9% (21.6 to 30.3) | 48.8% (40.9 to 54.7) | -10.3 (-18.1 to -2.8) | -7.8 (-17.5 to +0.6) |
| lexicon | 21.2% (15.0 to 26.6) | 38.8% (32.2 to 45.0) | -15.0 (-24.1 to -6.6) | -17.8 (-28.4 to -8.4) |

So the 19 extra books changed nothing (fits -0.3 points), the embedding
model is clearly better than the lexicon and probably better than maxent,
and the shipped model's mood suits the passage a little more than half the
time. Its main misses: mysterious windows read as calm (19 of 78), calm and
playful swapped both ways, and it never says romantic, dreamy or
adventurous.

Soft targets were checked and dropped. The idea was to give moods near the
label in valence/arousal part of the credit in training. But the moods the
plausible sets accept are not the near ones: on average they sit 0.87 apart
from the best mood against 0.94 for any two moods, and they are spread
almost evenly from the nearest to the tenth nearest (mysterious with tense
and with calm are the common pairs). Targets built from the sets
themselves would leak the test into training, and the training labels have
no independent second reading to draw soft labels from (the v2 labels were
derived from v1 and agree with them 96 to 98% of the time).

The 320 test windows still cannot separate recipes less than about 4
points apart, so `lofi-train oof` (Mac) scores recipes on every labelled
book instead: the 53 books are shuffled into 10 folds, each fold is
predicted by models trained on the other nine, and this is repeated with 3
shuffles, so each recipe makes 10,317 predictions over 3,439 windows, all
on the same folds. `Tools/eval/oof_compare.py` then compares recipes window
by window with intervals from resampling books. `run-mood-eval.sh` runs both.
First results (9 Nov 2026, exact agreement against the single labels):

| Recipe | Exact | Macro-F1 | Minus word-2 settings: exact | macro-F1 |
| --- | --- | --- | --- | --- |
| word-2 settings (unweighted, l2 0.1, earlier 0.2) | 37.9% (35.2 to 40.5) | 0.243 | | |
| word-6 settings (unweighted, l2 0.03, earlier 0.35) | 37.8% (35.0 to 40.4) | 0.272 | -0.1 (-1.0 to +0.8) | **+0.029 (+0.014 to +0.043)** |
| word-2 settings, trained only on the 34 older books | 37.1% | 0.243 | -0.8 (-1.7 to +0.1) | +0.001 |
| settings re-chosen inside each fold (nested) | 37.0% | 0.227 | -0.9 (-1.5 to -0.2) | -0.015 |
| balanced moods, l2 0.1 | 33.0% | 0.298 | -4.8 (-6.6 to -3.0) | +0.056 |

What it says: the 19 newer books add under a point (more books are not the
lever); round 7's "word-6 is 2 points worse" was noise from the 8 test
books, and word-6's settings are as accurate while naming the rarer moods
more often (hopeful 66 against 38 per pass, somber 104 against 67, with 200
and 196 in the labels); the cross-validated 37.6% quoted above flatters
by about a point, because choosing settings on the same windows adds
optimism; and every recipe still over-predicts tense (about 1,000 against
701) and calm (880 against 632). So the shipped model moves to word-6's
settings trained on all 53 books (`LofiMood-embed-word-7.json`), and the
next gains are expected from better labels and a better Claude reading,
not from more books.

By the rule above, **the Fast engine is the default**: it is the best
engine, deterministic, quick and plot-blind. Since round 4 the embedding
model is the better Fast model; `MoodEngineCatalog.fastEngine` takes either
kind (a `.json` embedding model or a Create ML `.mlmodel`), and
`fastEngine(modelURLs:)` falls back from one to the next, so a phone missing
the contextual embedding's assets still gets a Fast engine. fm stays off. Mo's gold
labels may still move the numbers, and the gap to the ceiling is why a
precomputed Claude mood track is now a decision for Mo.

The lexicon says "calm" for two thirds of windows; it is a floor, not a
candidate. A bag-of-words classifier does a little better and gains from the
extra labels, but stays far below the last row, which is the ceiling: the same
labeller agrees with itself about two times in three (most slips are
calm/mysterious, cozy/hopeful and calm/tense), so no engine should be expected
to beat about 65% against these labels, and Mo's gold labels will set the real
ceiling. The BERT-embedding Fast engine and the on-device model need the Mac.
