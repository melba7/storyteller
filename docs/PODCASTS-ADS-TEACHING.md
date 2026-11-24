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
- **The Mac's marks** (`ahead`): in the head scan, with the words heard so far,
  and in the whole-transcript pass of `PodcastAdFinder`, both after the other
  new finders, under the finder guard. The scan of a stream only skips; the
  whole pass skips the ads found by both edges and asks about the others. The
  Mac marks an episode at night, and the phone has usually checked it the
  evening before, so there is a third place: **an episode whose final ads file
  is made already** gets the finder run once over its stored transcript
  (`PodcastAdFinder+Ahead.swift`, `AheadPass.merge`), with no model and no sound
  read. It runs when `ahead-ads.json` is installed, when the app sends a new
  table of episodes, and at each scan of the downloads, in the finder's own
  background task and in a background turn. What it finds goes into the file as
  every new finder's ads do: the parts outside the ads that are there, never
  over a stretch the listener undid or said no to (those stay as they are),
  sorted by the show's settings before any join, at most unsure. The episode's
  `ahead-passes.json` records the `marked` time of the marks used, so the pass
  is not repeated at the next start and is made again when newer marks come. An
  episode that waits for its own pass, or is in one, is left to it: that pass
  runs the finder and records the same time.
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

| Finder (the `source` of its ads)    | What it does                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| ----------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `own-sound` (`OwnAdSounds`)         | Keeps the sound print of every sure ad the phone skipped (`own-ad-sounds.json`) and finds it again                                                                                                                                                                                                                                                                                                                                                                                                 |
| `repeat-sound`                      | A stretch that sounds the same in the last three episodes of a show (`RepeatScanner`, prints in Caches)                                                                                                                                                                                                                                                                                                                                                                                            |
| `repeat-words`                      | A run of words said in the last three episodes of a show (`RepeatedWords`)                                                                                                                                                                                                                                                                                                                                                                                                                         |
| `ahead` (`AheadAds`)                | The ads the Mac marked the night before in the next episodes (`ahead-ads.json`), found again by their first and last words, not by their times                                                                                                                                                                                                                                                                                                                                                     |
| `meaning` (`MeaningAds`)            | Apple's sentence embedding plus the Mac's weights (`ad-meaning.json`), for host-read plugs with no ad words                                                                                                                                                                                                                                                                                                                                                                                        |
| joints (`JointFinder`, `JointSnap`) | Moves the start or end of an ad to the nearest quiet joint: a start up to 3 s earlier or 1 s later, an end up to 2 s earlier or 4 s later. Whenever `steadyJoints` is on (in steady files and in the others), the late start of an ad whose start a word finder gave (`JointPull`: the repeated words, the meaning model, the word model, the word rules) with no joint near it is pulled back to the latest joint up to 60 s before it, never into an earlier ad or a stretch the listener judged |

For each new finder the phone does, in this order: find, keep only the parts
outside the ads already known (0.6 s away from them), apply the Mac's per-show
choice (`ShowTuning.apply`, and the finder guard's mode), join the ads that skip
(`AdJoin.join`), snap to joints, write through `AdsStore`, and then learn from
what was found. `ShowTuning.apply` must run on each finder's own list before the
join, because a joined ad loses its `source`.

- **A repeat only asks.** A repeated stretch is not always an ad, so a repeat
  never skips on its own: the phone's built-in level for repeats is `ask`, and
  the Mac's rules only make the phone stricter, never looser. (A hand edit of
  `show-settings.json` would say `skip`, but the next "Teach the phone again"
  writes the file whole and loses it.)
- **Apple's model asks too.** On the owner's labels the on-device model made the
  phone worse, so it is a fifth name in the settings (`apple-model`) with a
  built-in level of `ask`: its answers become questions (at most three in an
  episode, with the other finders'), and the stream's head scan neither asks nor
  waits for it. Only a show where the Mac's bar passes gets `skip` (see
  `teach_settings.py`); there its answers skip as before. The listener's undo
  and "no" count for the finder guard as for any other finder.
- **The Mac's marks of the night before** (`AheadAds`,
  `PodcastAdFinder+Ahead.swift`). The Mac marks the next episodes ahead of time
  (`ahead-ads.json`, below), and the phone's copy of an episode can carry other
  inserted ads than the Mac's copy, so a mark is used by its words and never by
  its times. The finder looks for the first words and the last words of each
  marked ad in the phone's transcript, with the matching that finds a remembered
  ad again (three fifths of the three-word runs). The ad starts where its first
  words start and ends where its last words end, landed like every ad
  (`AdLanding`). It is accepted only when both edges are found and the length
  between them is half to one and a half times the length the Mac marked. With
  one edge only, or two that do not fit, the finder offers a stretch of the
  marked length from the edge it found as a question, never as a skip. "high" is
  sure, "medium" is sure when both edges are found, and "low" is unsure. Its
  level in the settings is `skip` unless the file says otherwise, and the finder
  guard knows it by the same name (`ahead`). An entry is ignored 14 days after
  `marked`; a damaged file is no file. On a stream's head it finds an ad once
  its last words have arrived.
- **Questions.** A guess that is not sure enough to skip becomes a question,
  from whole-transcript passes only, at most three in an episode (answered ones
  count). The phone shows "Ad? Skip" with two answers while the stretch plays
  (`answerAdQuestion`, event `onAdAsk`). A yes skips the stretch like any skip,
  with Undo, and is kept inside the question (`AdsFile.asks`) so that a join
  cannot lose it; a no goes to `AdsFile.denied`, never to `undone`. Ads that are
  `unsure` are still skipped with Undo, as before.
- **The finder guard** (`FinderGuard`). A mark on disk before a new finder runs
  tells the next launch that the finder crashed. A crash turns that finder off
  for that episode, and a second crash in the same app build turns it off
  everywhere until the next build. Two undone skips among the last five answers
  on a show (answers older than 30 days do not count) make the finder ask
  instead of skip, and two "not an ad" answers out of five turn it off for that
  show. The guard can only make a finder stricter than the Mac's file does.
- **Learning from answers.** Each saved answer goes to the ad finder
  (`learnAnswered`). A yes is remembered by its words, its sound is learned and
  the guard hears the finder was right. A no tells the guard it was wrong and a
  repeat of words or sound is forgotten. Undo takes what was learned for the
  stretch back out (`forgetUndone`). Own sound prints are learned only from sure
  ads, after the joint snap, that were not undone or trimmed.
- **Limits.** About 20 MB of new data on the phone: prints of the last three
  episodes of 60 shows (12 MB in Caches) and hashes of repeated words (about 7
  MB). A show that skips nothing (every sort switched off) gets no new finder,
  joints, prints or questions.
- **What the phone keeps.** In `Podcasts/` of Application Support:
  `own-ad-sounds.json` (the phone's own sound prints), `repeat-words.json`
  (hashes of repeated words), `finder-guard.json` (the guard's marks and
  answers) and `finder-learned.json` (which episodes already taught the phone,
  in three lists: `own`, `print` and `habits`, so an episode teaches once). In
  `Library/Caches/Podcasts/prints/`: the prints of a show's last episodes, which
  iOS may clear. Losing any of them costs only what the phone had learned. In
  `Podcasts/teaching/`, beside the Mac's files: `ahead-episodes.json` (the table
  the app sent) and `ahead-passes.json` (which marks each episode was looked at
  with).
- **Show starts.** `show-starts.json` is version 2 and keeps where openings end;
  the Mac's habit wins when it has one, so a show the Mac never sampled gets the
  same first look.

## The files the Mac makes

The teaching folder is `~/Storyteller Lofi/PodcastTeaching` on the Mac. It is
never committed. `teach_publish.py` copies seven files and a list of them into
`Podcasts/` of the `LofiMusic` folder and its iCloud copy, which is the folder
the phone has linked. It also copies `ahead-ads.json` (see "The nightly
read-ahead" below) when the nightly job has made one.

| File                 | Made by                 | Holds                                                |
| -------------------- | ----------------------- | ---------------------------------------------------- |
| `ad-model.json`      | `teach_train.py`        | weights of the small word model                      |
| `ad-library.json`    | `teach_library.py`      | the words of ads met in marked episodes              |
| `show-habits.json`   | `teach_habits.py`       | per show: how many episodes open with an ad          |
| `ad-sounds.json`     | `podcast-teach sounds`  | the sound prints of marked ads                       |
| `ad-meaning.json`    | `podcast-teach meaning` | weights of the meaning model, with two probe vectors |
| `show-settings.json` | `teach_settings.py`     | per show: skip, ask or off for each finder and sort  |
| `ahead-ads.json`     | the Mac's read-ahead    | the ads marked in the next episodes, by their words  |
| `teaching.json`      | `teach_publish.py`      | the seven files' sizes and SHA-256, read first       |

All are JSON objects with `"version": 1` (the word model may be 2) and stay
under 4.5 MB (the phone refuses a file over 5 MB).

- `ad-model.json`:
  `{"version", "buckets": 262144, "classes": ["none", "sponsor", "network_promo", "host_ask", "intro_credits"], "thresholds": {...}, "weights": {"<bucket>": [5 numbers]}, "trained": {"writtenAt", "episodes", "lines", "shelf", "heldOut": {"episodes", "lines", "anyAd": {"precision", "recall"}, "classes": {...}}}}`.
  A file with no weights is refused. `heldOut` also holds `shows`,
  `predictedAdSeconds`, `adSeconds` and `lineAnyAd`. `teach_publish.py`
  publishes a model only when its check rests on at least 5 held-out episodes
  from 3 shows and 600 predicted ad seconds, the spans the phone would cut are
  right for at least 0.85 of their seconds, and the phone would accept the file.
  `teach_spans.py` decodes spans exactly as `AdWordModel+Spans.swift` does;
  change neither without the other. A model is version 1 (262144 buckets) or
  version 2 (4194304 buckets). Version 2 adds the word pairs of the two lines
  before and after as features, and decodes with `AdWordModel+SpansTwo.swift`
  (and `decode_two` in `teach_spans.py`): the ad score leaves credits out,
  credits get a second pass that never includes a line inside an ad, and an ad's
  start widens back over lines whose own score is at least `stay`. A widened
  line whose smoothed score is under `stay` takes the kind of the line before
  it, as bridged lines do. `teach_train.py` writes version 2 only with
  `--fit-tool` (the built `podcast-teach`, which fits the weights); without it
  the trainer writes a version 1 file as before. **Warning:** an app older than
  the build that reads version 2 refuses a version 2 file and keeps the model it
  has, so update the phone's app before using the Mac's version 2 trainer.
  Without the fit tool the trainer still writes a version 1 file.
- `ad-library.json`:
  `{"version", "writtenAt", "ads": [{"feed", "scope": "show" | "all", "sort", "who", "text", "length", "seen"}]}`.
  `teach_library.py` also writes `ad-library-score.json`, the same library built
  without the shelf episodes. It is not published. The scorecard reads it when
  it scores only the shelf, so an episode is never scored against its own ads.
  An entry's `text` holds up to 600 words of the ad, from segments marked "high"
  (not the stretches the snap added as copies). The phone finds an entry again
  when three fifths of its three-word runs, and at least eight different ones,
  lie at one distance in the transcript, so a different opening does not hide
  it. The match runs to its first and last matched word, moved out by at most
  five words.
- `show-habits.json`:
  `{"version", "writtenAt", "shows": [{"feed", "title", "episodes", "opensWithAd", "openingStarts", "openingEnds", "breaks", "adSeconds"}]}`.
- `ad-sounds.json`:
  `{"version", "step": 8, "sounds": [{"sort", "who", "frames", "seconds", "seen", "anchors": "<base64>"}]}`.
  An anchor is the low 32 bits of the hash of every 8th MP3 frame.
- `ahead-ads.json`:
  `{"version": 1, "writtenAt", "episodes": [{"feed", "guid", "title", "marked", "ads": [{"kind": "ad" | "promo" | "ownPlug", "confidence": "high" | "medium" | "low", "start", "end", "startWords", "endWords"}]}]}`.
  `marked` is when Claude marked the episode (seconds since 1970); an entry more
  than 14 days old is ignored. `start` and `end` are the times on the Mac's copy
  and only give the length the ad had. `startWords` and `endWords` are the first
  and the last (up to 40) words of the ad. An episode is the entry with its
  `guid`, or, when either has no guid, the entry with the same feed key and the
  same title (lower case, letters and digits). The phone refuses a file that is
  not version 1 with a list of `episodes`, and an entry or an ad of the wrong
  shape is left out when the file is read. `teach_publish.py` copies it from
  `ahead-ads.json` in the teaching folder to `Podcasts/ahead-ads.json` and lists
  it in `teaching.json`, as the nightly read-ahead (`teach_ahead.py`) writes it.
- `teaching.json`:
  `{"version", "writtenAt", "files": {"<name>": {"sha256", "bytes"}}}`.

An episode's length is the same number everywhere (the trainer, the scorecard
and the phone's end-of-episode feature): `seconds` from `episodes.json` when it
is above zero, otherwise the start of the last line.

**The nightly read-ahead.** The phone and the Mac talk through two more files in
`Podcasts/`. Both are JSON objects with `"version": 1`.

- `phone-queue.json`, written by the phone (`phoneQueue.ts`, at app start and
  when the app returns to the foreground, only when the list changed):
  `{"version", "writtenAt", "episodes": [{"feed", "guid", "title", "show", "audio", "reason": "upNext" | "newest", "rank"}]}`.
  It lists the Up Next episodes in order, then the newest unplayed episode of
  each show played in the last 14 days, 12 at most, with no show that has ad
  skipping off, no local file and no duplicate. `rank` is 0 for the first.
- `ahead-ads.json`, written by the Mac (`teach_ahead_ads.py`) and published with
  the other files:
  `{"version", "writtenAt", "episodes": [{"feed", "guid", "title", "marked", "ads": [{"kind": "ad" | "promo" | "ownPlug", "confidence", "start", "end", "startWords", "endWords"}]}]}`.
  `feed` and `guid` are the phone's own spelling from its list, `start` and
  `end` are seconds, and `startWords` and `endWords` are the first and last 40
  words of the ad so the phone can find the spot in its own transcript. It holds
  the episodes marked in the last 14 days (`marked` is when) and stays under the
  4.5 MB limit. Credits are left out. The phone does not read this file yet.

`teach-ahead.sh` (the 2:00 job) picks up to 8 unmarked episodes from the list,
downloads and writes them down with the weekly tools, has Claude mark them under
the budget `ahead-<ISO year>-W<ISO week>` with a hard stop at
$10 a week (each
episode is expected to cost about $0.19), and publishes
`ahead-ads.json`. `ahead.json` in the teaching folder lists those episodes: they
join `episodes.json` with their labels, so the weekly run learns from them, but
`teach_train.py` never puts them on the shelf and the exam never takes them.

**Shows are named by their feed address in the Mac's files.** The phone names a
show by its own id. The app tells the native side which feed is which show
(`setTeachingShows`), and the phone converts when it reads the files. Feed
addresses are compared as "feed keys": no scheme, no `www.`, lower-case host, no
fragment, no closing slash (`feedKey` in `applePodcasts.ts`, `FeedKey` in
PodcastKit).

**Episodes are named by their guid in the marks.** The phone's native side knows
an episode only by its own id. The app sends it a table of the newest unplayed
episodes of each show (`setAheadEpisodes`, `aheadEpisodesText` in
`teaching.ts`): `{"<episode id>": {"feed", "guid", "title"}}`, at most 12 for
each show and 400 in all, and only when the Mac has published marks. The phone
keeps it as `ahead-episodes.json` beside the teaching files and looks an
episode's marks up with it (`AheadEpisodes`, `TeachingFiles.aheadEntry`).

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
library, the sounds, the meaning model, the joints of the audio
(`podcast-teach joints`, kept in `joints.json` so the score needs no audio for
its joint rows), the score, the per-show settings and the copy to the phone's
folders. `podcast-teach meaning` exits 2 for a set-up problem (for example, no
sentence embedding on this Mac), and that does not stop the later steps.

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
  log" shares them, written again when they changed. It ends with the play diary
  (`play-diary.jsonl` on the phone, `PlayDiary.swift`), which has its own 2,000
  lines so the ad diary's 500 never push it out: one line (`"kind": "diary"`)
  for every play that starts, with `what` set to `play: ready` (the ads were
  found for the whole episode), `play: partly, transcript to N s` (downloaded,
  ads not finished) or `play: stream`, and one for every finished transcription
  (the whole episode or its head), `N s of audio in M s, front` or
  `, background`. `teach_pace.py` reads them.

## The bridge between Swift and TypeScript

Native module `Podcasts` (`modules/podcasts/ios/PodcastsModule.swift`):

| Function                                                            | Returns                                                    |
| ------------------------------------------------------------------- | ---------------------------------------------------------- |
| `getAdSkipSettings()`                                               | `{skipAds, skipOwnPlugs, skipPromos, skipCredits}`         |
| `setAdSkipSettings(skipAds, skipOwnPlugs, skipPromos, skipCredits)` | nothing                                                    |
| `skipAdNow()`                                                       | `{to, known}` or null when nothing is loaded               |
| `readPendingAdNotes()`                                              | the pending notes as JSON lines, "" when none              |
| `removePendingAdNotes(count, upToAt)`                               | nothing; see below                                         |
| `getAdTally()`                                                      | JSON text, see below                                       |
| `readSkipLogText()`                                                 | the skip log and diary text, or null                       |
| `installTeachingFile(name, text, sha256)`                           | true when the file was checked and installed               |
| `setTeachingShows(json)`                                            | nothing; `json` is `{"<feed key>": "<show id>"}`           |
| `setAheadEpisodes(json)`                                            | nothing; `json` is `{"<episode id>": {feed, guid, title}}` |
| `getTeachingState()`                                                | JSON text, see below                                       |
| `answerAdQuestion(episodeId, start, isAd)`                          | true when an open question starts at `start`               |

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

## Switching things off, and going back

- To make one finder stricter for every show or for one show, the Mac decides
  from the scorecard when you double-click "Teach the phone again": a finder
  that finds more wrong than right seconds is turned off, and one under 85%
  precision only asks. A finder that found no ad at all and cut under 0.05
  percent of the show is left as it is: the sound and repeat finders learn from
  a show's earlier episodes, which one unseen episode of each show cannot show.
  The phone's guard does the same by itself after a crash or two undone skips.
- There is no switch for a finder in the app. To go back to how ads were skipped
  before this round, install build 33.1 again from the build list in TestFlight;
  the files the new finders wrote have only new fields, which the old build
  skips over (it may lose the habits of shows it learned about in the new
  build).

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
words", "Plus joints", "Plus joints (steady files too)" and, last of the
finders, "Plus per-show settings" (with the built-in settings when there is no
file yet). The row names must equal `ROWS` in `teach_settings.py`, which reads
them to decide what is turned on or off. Steady joints (which switch on the
pull-back of a late start, in steady files and in the others) are on when the
steady row passes at least 3 more breaks than the row before it and adds at most
1 skip with no ad. The pull is for a start that a word finder gave: an ad with
the name of the repeated words, the meaning model or the word model, or an ad
with no name whose kind and start equal those of an ad the word rules and the
word model gave for the whole transcript (`LocalAds`, before any join). The
scorecard hands that list to the joint rows, and the phone finds it again before
it snaps. The learning rows (own sounds, repeats) first learn from the marked
episodes that are not scored, then scan the scored ones, so each episode is
judged only on what the earlier episodes of its show taught. The scorecard also
prints how many questions the word model would ask (not the repeat finders' or
the meaning model's), a note on habits and what was left out. The meaning model
is published only when its row adds right seconds for host_ask and network_promo
and at least 85% of the added seconds are right, and the scorecard is not older
than the model.

### The sealed exam

A set of about 60 newer episodes is kept apart as an exam. Their ids are in
`exam.json` in the teaching folder. The rule: an exam episode is invisible to
every step that learns. Only gathering, writing down, marking, second downloads
and the scorer, when it is asked, may use it. Every learning step leaves it out:
the word model, the shelf, the library of ads (both files), the habits and the
Swift steps `sounds` and `meaning`. A training episode that repeats an exam
episode is left out of training too. The exam is gathered only from episodes
newer than everything gathered before, so it tests the phone on episodes it
could not have learned from. Fifteen of its episodes are marked a second time
(`labels-second/`) to show how much two markings of the same episode differ,
which is the ceiling for any score against Claude's marks.
`Gather the exam episodes.command` makes it,
`Gather more episodes for teaching.command` and
`Mark the new episodes at night.command` gather and mark the other 500 or so
episodes only at night, over several nights, within a cost cap (see
`Tools/mac/README.md`).

Marking happens only in the night window: no call to Claude starts outside it,
also not a retry after a wait for the usage allowance, and a retry asks only for
the parts of an episode that are still missing. The cost cap is a budget kept
across runs in `marking-spend.json`, so double-clicking again carries on with
what is left and never starts a fresh cap. The exam launcher says how many exam
episodes have audio and a transcript, and says "Done" only when all of them are
marked once and 15 of them twice; otherwise it says what is left.

### The stream replay and Apple's model in the scorecard

`podcast-teach score <folder> --stream` adds one block after the bar. It replays
every episode as a stream played from the start by a listener who taps play and
never touches the phone, because on a stream the phone learns the ads while the
episode already plays, and a whole transcript is its best case. It follows the
phone's own scans: the head steps of the show, then the whole-file pass's pieces
from 0, with the finders run on the first seconds of the transcript at each
step. A real `AdSkipper` decides every jump, and the jumps are scored by the
same bar as found ads. The speeds are assumptions, not measurements, and the
block prints them: a standard pace (1 s to the first byte, 40 s of audio
downloaded and 12 s transcribed per second, 0.5 s per step, a jump costs 1 s,
the model 2 s per minute of the head read so far and at least 2 s) and a slow
one (4 s of audio downloaded and 5 s transcribed per second). The head scan
waits for Apple's model at the steps that ask it in every row, as on a phone
with Apple Intelligence on (an assumption, printed with the paces), although the
model's answers count only in the Apple row. "Ready" in the block means the same
player with the finished file known before the listener taps play (an episode
that was read to its end first), so it chains ads the way the player does and is
not the row's own bar, which stays in the bar block. After the paces the block
prints the first 3 minutes at two more speech speeds, 6 and 25 times real time,
because the first 3 minutes depend on the phone's real speed. That speed is
measured now: `teach_pace.py` reads the phone's diary and prints the speech pace
in seconds of audio per second of work, and `--stream --speech N` replays the
standard pace with that speech speed instead of 12. The pace is then called
"measured", the block says so, and the numbers saved in `scorecard.json` carry
the `speech` they were replayed at. `--speech` without `--stream` is refused.
Without `--stream` nothing changes.

Apple's on-device model only runs on a Mac or a phone.
`podcast-teach apple <folder> [--exam] [--limit N]` asks it about the episodes a
plain `score` run scores and keeps the answers (times, kinds and how sure, never
any text) in `apple-model.json`, one episode at a time, so a run that is stopped
carries on where it was. A damaged or newer `apple-model.json` stops
`podcast-teach apple` (it never overwrites the file), but the scorecard leaves
the Apple row out, prints one note that the file could not be read and carries
on; `podcast-teach apple` can make it again once the file is moved away. The
scorecard then gets one more row after all the others, "Plus Apple's model
(asked on the Mac)": the last row's ads joined with the answers, the row before
it for an episode with no answer. `teach_settings.py` and
`teach_publish_gates.py` find rows by name and never take the last one, so the
new row changes nothing they decide, and the run's saved total stays the
finders' last row. In the stream replay the model's answers count in a snapshot
only where the ad ends within the snapshot's reach, at the head's model steps,
and cost the model's time (the wait itself is in the head scan of every row).
Double-click `Ask Apple's model about the test episodes.command` to ask; it
costs nothing, uses no Claude allowance and may take a few hours.

### The passage model, a trial

`Tools/mac/teach_passage.py` (the launcher `Teach the passage model.command`)
tries a small language model, milestone W5 of the plan, and nothing of it is in
the app. In the Mac's `python-mood` environment it embeds every transcript line
with `sentence-transformers/all-MiniLM-L6-v2`, takes windows of five lines (two
before, the line, two after, zeros beyond an episode's edge) and trains a
softmax regression (numpy, L2, the word model trainer's class weights) on the
marked episodes that are not on the shelf, not in the exam and not a repeat of
either. It writes `passage-model.json` for the shelf episodes only:
`{"version": 1, "model", "decoder": 2, "classes", "thresholds", "trained", "episodes": {"<id>": {"lines": N, "rows": [[5 probabilities], ...]}}}`,
with no words. `podcast-teach score` reads it (`PassageAnswers`) and adds the
row "Plus the passage model" (`PassageScoreRow`) after the finders and Apple's
row. The rows go through the word model's version 2 decoder
(`AdWordModel.decodeTwo`, repeated by `decode_two` in `teach_spans.py`; change
neither without the other) with the file's cut-offs, and become `unsure` ads of
the source `passage-model`. The row stands on the last finder row, not on
Apple's row (`AnswerScoreRow.layer(standingOn:)`, which both rows share with
`AppleScoreRow`), so it can be compared with the finders. An episode with no
answer, or with another number of lines than its answer, stays as the last
finder row. A file that is damaged, of another version or made for another
decoder leaves the row out with a note. The go rule: the row must pass at least
10 more breaks than the last finder row on both label sets and add at most 2
more skips with no ad. Only then is it shrunk to Core ML for the app.

The app's "Ad skipping results" page shows the tally per show (skipped, undone,
trimmed, missed, time saved) and what the Mac taught and when.

### The Mac's marks, a row

`podcast-teach score <folder> --ahead` adds one row after all the others,
Apple's and the passage row included: "Plus the Mac's marks from the night
before" (`AheadScoreRow`). It stands on the last finder row like the passage
row, and the verdict compares it with that row. The marks are made from Claude's
own labels in `labels/` (credits are not marked, low confidence stays) and the
words of each transcript (the first and last 40 words of each ad), written and
read back as the phone reads the Mac's file, and the row runs the phone's finder
(`AheadAds`) on each transcript. An episode that has a second download
(`copies/<id>.truth.txt`) keeps only the marks that are in both downloads: a
marked ad that overlaps a stretch where the downloads differ by half of its
length or more is left out, because the phone's copy may not carry it. An
episode with no second download keeps all its marks, and the report says which
of the two it did. The report prints the bar, why breaks fail in the row and the
verdict. The go rule: at least 20 more breaks pass than the last finder row,
with at most 1 more skip with no ad.

On the shelf the marks are made from the same labels the row is scored against,
so the row proves only that the matching works: the words of a marked ad are
found again and give its edges. The real number comes from the exam, where an
episode is marked once the night before and scored against another marking.

### The sound at the edges

`podcast-teach edges <folder>` measures, before anything is built into the
phone, whether the sound itself says where an ad spot starts and ends. It needs
a Mac (Apple's decoder, `MacEdgeReader`, reads each shelf episode's MP3 file
once as mono 16 kHz) and costs nothing. For every half second it works out the
loudness in decibels, the level of 24 bands (log-spaced from 100 Hz to 7.5 kHz)
and whether it is a pause (22 dB or more under the episode's 90th percentile of
loudness). The change score at a point compares the 3 seconds before with the 3
seconds after: how much louder or quieter the half seconds with sound in them
are, how differently they are coloured (the bands with their loudness taken
out), and the difference of their share of pauses (6 dB for a whole window),
added as squares. A peak is a point that is the strongest within 1.5 seconds and
scores at least 3; an episode keeps its strongest 300 peaks for each hour.

- `edges.json`:
  `{"version": 1, "finder": 1, "episodes": {"<id>": {"seconds", "peaks": [[time, strength], ...]}}}`.
  The peaks of every shelf episode (the exam is never read), so a scorecard row
  can snap found edges onto them without the audio. An episode in it is not read
  again; a file that is damaged or made by another `finder` is ignored and made
  again.
- `edges-report.json`:
  `{"version", "finder", "writtenAt", "rule", "reaches": [1, 2, 5], "episodes", "leftOut", "edges": {"points", "within": [...], "share": [...]}, "random": {...}, "verdict": "go" | "no go" | "no verdict"}`.
  `within` counts the points whose strongest peak within 10 seconds is no
  further than each reach.

The exact edges are the borders in `labels-snapped/` that the second download
moved (a border that Claude's own `labels/` does not have) and both borders of a
stretch only the second download found (`"origin": "copy"`), for marked ads of
high or medium confidence. The random points are as many as the exact edges, in
the same episodes, drawn with a fixed seed. An edge or point within 3 seconds of
the start or end of an episode is left out. The go rule is: the strongest change
within 10 seconds lies within 1 second of at least 70% of exact edges, and of at
most 10% of random points. The weights of the score are first guesses and have
not been tuned on the shelf.

## Later

- Words inside a teaching transcript line have no times of their own, so the
  scorecard spreads them evenly over the line.
- The head scan stops at three minutes. Whether it should go on is to be decided
  from the diary.
- A missed-ad tap jumps 30 seconds. It could end where the small model thinks
  the stretch ends, and teach the phone's own memory at once.
- `AdCleanup`'s own merge is not kind-aware.
- A repeat never skips. A rule that promotes a repeat to skip after enough
  confirmed answers on a show is parked until the answers show it is safe.
- Episodes that finished before the update never run the new finders again.
- The pass over an episode whose ads are final does not learn from what it found
  (the memory of ads, the sound prints): only a full pass does.
- A habit may be counted twice for an episode that was streamed and then
  downloaded; the check of play-through limits it.
- Transcripts over 64 MB skip the deny-by-words step.
