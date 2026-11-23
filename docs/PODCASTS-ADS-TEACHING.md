# Podcasts: the Mac teaches, the phone skips alone

This is how ad skipping works after the rounds of 2026-11-22 and 2026-11-23, and
the contracts between its parts. The reasons are in the plan document "Podcast
ad skipping rethink" (linked from `docs/PLAN.md`). The second round ("the phone
learns by itself") is described under "What the phone learns by itself" below.

## The rule

The phone must skip ads by itself. The Mac may teach it and prepare files, but
nothing may depend on the Mac being on, or on iCloud having synced, when Play is
pressed. Every layer below is a backup for the others: an episode is skipped
from whatever the layers found, and a layer that cannot run leaves the others
working.

## The layers on the phone

| Layer         | Needs                        | Where                                     |
| ------------- | ---------------------------- | ----------------------------------------- |
| Word rules    | nothing                      | `AdHeadRules`, `AdPromoRules`             |
| Small model   | `ad-model.json` from the Mac | `AdWordModel`                             |
| Known ads     | the phone's own memory, plus | `KnownAds`, `AdLibrary`                   |
|               | `ad-library.json`            |                                           |
| Sounds        | `ad-sounds.json`             | `AdSoundScanner` in `PodcastAudioMatch`   |
| Apple's model | Apple Intelligence           | `AppleAdDetector` in `PodcastAdsOnDevice` |
| Chapters      | chapters in the file         | `ChapterAds`                              |
| The listener  | a tap                        | Skip ad, Undo, going back after a skip    |

`LocalAds` runs the word rules and the small model together. `AdJoin.join` joins
what the layers found: ads of one kind that touch become one, and where two
kinds overlap the higher one keeps its stretch (ad, then promo, then own plug,
then credits), so an ad is never taken over by credits that are not skipped.

There are four sorts, each with its own switch (`AdSkipSettings`): sponsor ads
(`ad`), the hosts' own plugs (`ownPlug`), promos for the show's or network's
other things (`promo`) and intros and credits (`credits`, off until turned on).
The Mac's names for them are `sponsor`, `host_ask`, `network_promo` and
`intro_credits`; `AdKind(sort:)` converts.

A show can have its own choice for sponsor ads and for the hosts' plugs
(`AdSkipSettings.overridden`). A show whose own Skip ads is off keeps its promos
too, because promos were ads before this round. On a phone updated from the
two-switch build only the Skip ads switch is stored, and promos take its value.
The app's `effectiveAdSettings` and `skippingAnyFor` follow the same two rules.

What keeps the layers from cutting the show itself:

- `AdPromoRules` keeps a promo only on proof: a web address, a code or an offer
  near the cue, cues from two groups (a live show and a subscription, say), or
  two different cue phrases of which one asks the listener to do something. One
  phrase said twice, or two phrases people also use in plain talk, prove
  nothing.
- The small model's span is cut where the sort changes from one line to the
  next, so credits beside an ad stay credits and are not skipped with it.
- The phone refuses a model file whose line with no known word is not plain
  talk, or whose start threshold is below 0.5.
- A sound match ends where the matching stopped, not at the sound's full length.
- An ad the listener undid stays undone when the episode is checked again, and a
  trim stays when a new ad cuts the trimmed one.

### When each layer runs

- **A stream's first three minutes** (`PodcastStreamHead`): at each step the
  known ads, `LocalAds` and the sounds look at what has arrived, then Apple's
  model at its steps. A show that usually opens with an ad (`ShowHabits`) gets a
  first look that covers its usual opening, a wait of up to 5 seconds before the
  audio starts, and unsure answers count from the first step. A show that never
  opens with an ad gets no wait.
- **A downloaded file with no transcript yet**: the sounds are looked for at
  once.
- **A transcript that is growing or whole** (`PodcastAdFinder`): the local
  layers run first and their ads go into the episode's ads file
  (`LocalAdsFile`), then Apple's model is asked. When Apple's model cannot be
  asked at all, the local result is saved as the episode's result
  (`detectorVersion` empty); when the model can be asked again, the episode is
  checked again and the local ads are added to its answer.

## What the phone learns by itself

Since the round of 2026-11-23 the phone also finds ads from its own listening,
with no help from the Mac. Every new finder returns ads that are `unsure` at
most, and a finder alone never makes a skip that Undo cannot take back. The
Mac's files only make each finder better or stricter.

| Finder (the `source` of its ads)    | What it does                                                                                                                              |
| ----------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| `own-sound` (`OwnAdSounds`)         | Keeps the sound print of every sure ad the phone skipped (`own-ad-sounds.json`) and finds it again                                        |
| `repeat-sound`                      | A stretch that sounds the same in the last three episodes of a show (`RepeatScanner`, prints in Caches)                                   |
| `repeat-words`                      | A run of words said in the last three episodes of a show (`RepeatedWords`)                                                                |
| `meaning` (`MeaningAds`)            | Apple's sentence embedding plus the Mac's weights (`ad-meaning.json`), for host-read plugs with no ad words                               |
| joints (`JointFinder`, `JointSnap`) | Moves the start or end of an ad to the nearest quiet joint: a start up to 3 s earlier or 1 s later, an end up to 2 s earlier or 4 s later |

For each new finder the phone does, in this order: find, keep only the parts
outside the ads already known (0.6 s away from them), apply the Mac's per-show
choice (`ShowTuning.apply`, and the finder guard's mode), join the ads that skip
(`AdJoin.join`), snap to joints, write through `AdsStore`, and then learn from
what was found. `ShowTuning.apply` must run on each finder's own list before the
join, because a joined ad loses its `source`.

- **A repeat only asks.** A repeated stretch is not always an ad, so repeats
  skip only where `show-settings.json` has been edited by hand to say `skip`.
  The Mac's own rules only make the phone stricter.
- **Questions.** A guess that is not sure enough to skip becomes a question,
  from whole-transcript passes only, at most three in an episode (answered ones
  count). The phone shows "Ad? Skip" with two answers while the stretch plays
  (`answerAdQuestion`, event `onAdAsk`). A yes skips the stretch like any skip,
  with Undo, and is kept inside the question (`AdsFile.asks`) so that a join
  cannot lose it; a no goes to `AdsFile.denied`, never to `undone`. Ads that are
  `unsure` are still skipped with Undo, as before.
- **The finder guard** (`FinderGuard`). A mark on disk before a new finder runs
  tells the next launch that the finder crashed. A crash, or two undone skips
  among the last five answers on a show (answers older than 30 days do not
  count), make the finder ask instead of skip. Two "not an ad" answers out of
  five turn it off for that show. The guard can only make a finder stricter than
  the Mac's file does.
- **Learning from answers.** Each saved answer goes to the ad finder
  (`learnAnswered`). A yes is remembered by its words, its sound is learned and
  the guard hears the finder was right. A no tells the guard it was wrong and a
  repeat of words or sound is forgotten. Undo takes what was learned for the
  stretch back out (`forgetUndone`). Own sound prints are learned only from sure
  ads, after the joint snap, that were not undone or trimmed.
- **Limits.** About 20 MB of new data on the phone: prints of the last three
  episodes of 60 shows (12 MB in Caches) and hashes of repeated words (about 7
  MB). A show whose own Skip ads switch is off gets no new finder, joints,
  prints or questions.
- **Show starts.** `show-starts.json` is version 2 and keeps where openings end;
  the Mac's habit wins when it has one, so a show the Mac never sampled gets the
  same first look.

## The files the Mac makes

The teaching folder is `~/Storyteller Lofi/PodcastTeaching` on the Mac. It is
never committed. `teach_publish.py` copies six files and a list of them into
`Podcasts/` of the `LofiMusic` folder and its iCloud copy, which is the folder
the phone has linked.

| File                 | Made by                 | Holds                                                |
| -------------------- | ----------------------- | ---------------------------------------------------- |
| `ad-model.json`      | `teach_train.py`        | weights of the small word model                      |
| `ad-library.json`    | `teach_library.py`      | the words of ads met in marked episodes              |
| `show-habits.json`   | `teach_habits.py`       | per show: how many episodes open with an ad          |
| `ad-sounds.json`     | `podcast-teach sounds`  | the sound prints of marked ads                       |
| `ad-meaning.json`    | `podcast-teach meaning` | weights of the meaning model, with two probe vectors |
| `show-settings.json` | `teach_settings.py`     | per show: skip, ask or off for each finder and sort  |
| `teaching.json`      | `teach_publish.py`      | the six files' sizes and SHA-256, read first         |

All are JSON objects with `"version": 1` and stay under 4.5 MB (the phone
refuses a file over 5 MB).

- `ad-model.json`:
  `{"version", "buckets": 262144, "classes": ["none", "sponsor", "network_promo", "host_ask", "intro_credits"], "thresholds": {...}, "weights": {"<bucket>": [5 numbers]}, "trained": {"writtenAt", "episodes", "lines", "shelf", "heldOut": {"episodes", "lines", "anyAd": {"precision", "recall"}, "classes": {...}}}}`.
  A file with no weights is refused. `heldOut` also holds `shows`,
  `predictedAdSeconds`, `adSeconds` and `lineAnyAd`. `teach_publish.py`
  publishes a model only when its check rests on at least 5 held-out episodes
  from 3 shows and 600 predicted ad seconds, the spans the phone would cut are
  right for at least 0.85 of their seconds, and the phone would accept the file.
  `teach_spans.py` decodes spans exactly as `AdWordModel+Spans.swift` does;
  change neither without the other.
- `ad-library.json`:
  `{"version", "writtenAt", "ads": [{"feed", "scope": "show" | "all", "sort", "who", "text", "length", "seen"}]}`.
  `teach_library.py` also writes `ad-library-score.json`, the same library built
  without the shelf episodes. It is not published. The scorecard reads it when
  it scores only the shelf, so an episode is never scored against its own ads.
- `show-habits.json`:
  `{"version", "writtenAt", "shows": [{"feed", "title", "episodes", "opensWithAd", "openingStarts", "openingEnds", "breaks", "adSeconds"}]}`.
- `ad-sounds.json`:
  `{"version", "step": 8, "sounds": [{"sort", "who", "frames", "seconds", "seen", "anchors": "<base64>"}]}`.
  An anchor is the low 32 bits of the hash of every 8th MP3 frame.
- `teaching.json`:
  `{"version", "writtenAt", "files": {"<name>": {"sha256", "bytes"}}}`.

An episode's length is the same number everywhere (the trainer, the scorecard
and the phone's end-of-episode feature): `seconds` from `episodes.json` when it
is above zero, otherwise the start of the last line.

**Shows are named by their feed address in the Mac's files.** The phone names a
show by its own id. The app tells the native side which feed is which show
(`setTeachingShows`), and the phone converts when it reads the files. Feed
addresses are compared as "feed keys": no scheme, no `www.`, lower-case host, no
fragment, no closing slash (`feedKey` in `applePodcasts.ts`, `FeedKey` in
PodcastKit).

**The second download.** `Check ads with a second download.command` fetches
again, at most 40 marked episodes and 3 GB a run, the copy of an episode the
phone would play. `teach-finish.sh` then runs `teach_snap.py`, which moves the
borders of Claude's marked ads onto what the two downloads differ in (where an
inserted ad starts and ends exactly). The result goes to `labels-snapped/`
beside Claude's `labels/`, which are never overwritten, and the later steps use
the snapped labels when they exist. The snap step is left out when there is no
second download.

**The finish steps.** `teach-finish.sh` prints "Step N of 8": the snap (only
when `copies/` or `labels-snapped/` exists), then habits, the word model, the
library, the sounds, the meaning model, the score, the per-show settings and the
copy to the phone's folders. `podcast-teach meaning` exits 2 for a set-up
problem (for example, no sentence embedding on this Mac), and that does not stop
the later steps.

## From the phone back to the Mac

The phone writes two files into `Podcasts/` of its linked folder:

- `phone-notes.jsonl`: one line per event, the newest 2,000 lines.
  `{"v": 1, "at": <ms>, "what": "skipped" | "undone" | "trimmed" | "missed" | "confirmed" | "denied", "feed", "guid", "title", "address", "start", "end", "kind", "by"}`.
  "missed" is a tap on Skip ad where the phone knew no ad. "confirmed" is a yes
  and "denied" a no to a question the phone asked. `by` names the finder that
  made the ad, only when the phone knew it (older notes have none).
  `teach_feedback.py` turns episodes with misses, undone skips or answers into
  `wanted.json` ("confirmed" counts like "missed" and "denied" like "undone"),
  and the next gathering takes those episodes first.
- `phone-diary.jsonl`: the skip log and the ad finder's diary, as "Send skip
  log" shares them, written again when they changed.

## The bridge between Swift and TypeScript

Native module `Podcasts` (`modules/podcasts/ios/PodcastsModule.swift`):

| Function                                                            | Returns                                            |
| ------------------------------------------------------------------- | -------------------------------------------------- |
| `getAdSkipSettings()`                                               | `{skipAds, skipOwnPlugs, skipPromos, skipCredits}` |
| `setAdSkipSettings(skipAds, skipOwnPlugs, skipPromos, skipCredits)` | nothing                                            |
| `skipAdNow()`                                                       | `{to, known}` or null when nothing is loaded       |
| `readPendingAdNotes()`                                              | the pending notes as JSON lines, "" when none      |
| `removePendingAdNotes(count, upToAt)`                               | nothing; see below                                 |
| `getAdTally()`                                                      | JSON text, see below                               |
| `readSkipLogText()`                                                 | the skip log and diary text, or null               |
| `installTeachingFile(name, text, sha256)`                           | true when the file was checked and installed       |
| `setTeachingShows(json)`                                            | nothing; `json` is `{"<feed key>": "<show id>"}`   |
| `getTeachingState()`                                                | JSON text, see below                               |
| `answerAdQuestion(episodeId, start, isAd)`                          | true when an open question starts at `start`       |

- A pending note is
  `{"v": 1, "at": <ms>, "what", "episode": "<episode id>", "show": "<show id or empty>", "start", "end": <seconds or null>, "kind"}`.
  The app adds the feed, guid, title and audio address from its database before
  it writes the line to the linked folder. A "missed" note has an empty `kind`,
  and the file keeps it empty.
- `removePendingAdNotes(count, upToAt)` drops at most `count` lines from the
  start, and only lines whose `at` is not later than `upToAt` (the `at` of the
  newest note the app wrote). A note made since the read stays. The app does not
  write a line the file already holds, so a removal that never ran costs
  nothing.
- `skipAdNow()` inside a known ad skips that ad whatever the switches say, as an
  ordinary skip with its note and Undo (`known` true). Anywhere else it jumps 30
  seconds, or to the end of a skipped ad the landing falls in. Within 3 seconds
  of a skip it does nothing. `AdSkipNow.decide` holds the rule.
- `getAdTally()`:
  `{"since": <ms or null>, "shows": {"<show id>": {"skipped", "undone", "trimmed", "missed", "seconds"}}}`.
  The results page calls an id that starts with `preview:` "A show you
  previewed" and an empty id "Your files".
- `getTeachingState()`:
  `{"files": {"<name>": {"sha256", "installedAt"}}, "model": {"writtenAt", "episodes", "precision", "recall"} | null, "library": <entries>, "habits": <shows>, "sounds": <sounds>}`.
- The `onAdSkipped` event also carries `"kind"`. `onAdsChange` is also sent
  after a trim.
- The `onAdAsk` event (`{episodeId, start, end, kind}`) is sent once for each
  question when the playhead enters the stretch. The app shows "Ad? Skip" until
  the stretch ends. `answerAdQuestion` with `isAd` true skips the stretch like
  any skip (note, Undo); with false it says the stretch is not an ad. Neither
  needs the Skip ads switch, because the listener asked for it.
- The load options take `startChosen`: true when the listener chose the place to
  start from, so an ad there is not skipped at once.
- An Up Next item carries `notes` (the first 4,000 characters) and `showLink`,
  so an episode the player moves to on its own is checked with its sponsors'
  names.
- `fetchFeed`'s answer carries `newFeedUrl` when the feed names a new address
  (http or https only). The app moves the show to it (`feedMove.ts`).
- `download` takes the episode's show id as its last argument, so an episode
  that is downloaded and checked before it is ever played still gets the ads the
  phone knows for its show.

Native module `LofiScore` (`modules/lofi-score`):

| Function                            | Returns                                                                                             |
| ----------------------------------- | --------------------------------------------------------------------------------------------------- |
| `writeLinkedFolderFile(path, text)` | `{status: "written"}`, `{status: "notLinked" \| "folderGone"}` or `{status: "unwritable", message}` |

## Measuring

`podcast-teach score <teaching folder>` runs the phone's local layers over the
episodes Claude marked and prints the scorecard: ads caught, ad seconds still
heard, show seconds cut by mistake, per sort, per show, how many opening ads the
first look knows, and what each layer adds. By default it scores only the shelf
episodes, which the model never saw in training. Each run is added to
`scorecard.json`, so the next run says what changed. Double-click
`Score the ad skipping.command` on the Mac.

The scorecard lists the layers in the order the phone adds them, and each row is
the row before plus one more layer: the existing layers, then "Plus the meaning
model", "Plus the phone's own sounds", "Plus repeated sounds", "Plus repeated
words", "Plus joints", "Plus joints (steady files too)" and, always last, "Plus
per-show settings" (with the built-in settings when there is no file yet). The
row names must equal `ROWS` in `teach_settings.py`, which reads them to decide
what is turned on or off. The learning rows (own sounds, repeats) first learn
from the marked episodes that are not scored, then scan the scored ones, so each
episode is judged only on what the earlier episodes of its show taught. The
scorecard also prints how many questions the word model would ask (not the
repeat finders' or the meaning model's), a note on habits and what was left out.
The meaning model is published only when its row adds right seconds for host_ask
and network_promo and at least 85% of the added seconds are right, and the
scorecard is not older than the model.

The app's "Ad skipping results" page shows the tally per show (skipped, undone,
trimmed, missed, time saved) and what the Mac taught and when.

## Later

- Words inside a teaching transcript line have no times of their own, so the
  scorecard spreads them evenly over the line.
- The head scan stops at three minutes. Whether it should go on is to be decided
  from the diary.
- A missed-ad tap jumps 30 seconds. It could end where the small model thinks
  the stretch ends, and teach the phone's own memory at once.
- `AdCleanup`'s own merge is not kind-aware.
- A repeat never skips unless `show-settings.json` is edited by hand. A rule
  that promotes a repeat to skip after enough confirmed answers on a show is
  parked until the answers show it is safe.
- Episodes that finished before the update never run the new finders again.
- A habit may be counted twice for an episode that was streamed and then
  downloaded; the check of play-through limits it.
- Transcripts over 64 MB skip the deny-by-words step.
