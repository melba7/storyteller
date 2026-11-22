# Podcasts: the Mac teaches, the phone skips alone

This is how ad skipping works after the round of 2026-11-22, and the contracts
between its parts. The reasons are in the plan document "Podcast ad skipping
rethink" (linked from `docs/PLAN.md`).

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

## The files the Mac makes

The teaching folder is `~/Storyteller Lofi/PodcastTeaching` on the Mac. It is
never committed. `teach_publish.py` copies four files and a list of them into
`Podcasts/` of the `LofiMusic` folder and its iCloud copy, which is the folder
the phone has linked.

| File               | Made by                | Holds                                         |
| ------------------ | ---------------------- | --------------------------------------------- |
| `ad-model.json`    | `teach_train.py`       | weights of the small word model               |
| `ad-library.json`  | `teach_library.py`     | the words of ads met in marked episodes       |
| `show-habits.json` | `teach_habits.py`      | per show: how many episodes open with an ad   |
| `ad-sounds.json`   | `podcast-teach sounds` | the sound prints of marked ads                |
| `teaching.json`    | `teach_publish.py`     | the four files' sizes and SHA-256, read first |

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

## From the phone back to the Mac

The phone writes two files into `Podcasts/` of its linked folder:

- `phone-notes.jsonl`: one line per event, the newest 2,000 lines.
  `{"v": 1, "at": <ms>, "what": "skipped" | "undone" | "trimmed" | "missed", "feed", "guid", "title", "address", "start", "end", "kind"}`.
  "missed" is a tap on Skip ad where the phone knew no ad. `teach_feedback.py`
  turns episodes with misses or undone skips into `wanted.json`, and the next
  gathering takes those episodes first.
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
