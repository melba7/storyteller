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
  A file with no weights is refused. `teach_publish.py` does not publish a model
  whose held-out precision for any ad is below 0.85.
- `ad-library.json`:
  `{"version", "writtenAt", "ads": [{"feed", "scope": "show" | "all", "sort", "who", "text", "length", "seen"}]}`.
- `show-habits.json`:
  `{"version", "writtenAt", "shows": [{"feed", "title", "episodes", "opensWithAd", "openingStarts", "openingEnds", "breaks", "adSeconds"}]}`.
- `ad-sounds.json`:
  `{"version", "step": 8, "sounds": [{"sort", "who", "frames", "seconds", "seen", "anchors": "<base64>"}]}`.
  An anchor is the low 32 bits of the hash of every 8th MP3 frame.
- `teaching.json`:
  `{"version", "writtenAt", "files": {"<name>": {"sha256", "bytes"}}}`.

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
| `removePendingAdNotes(count)`                                       | nothing; drops the first `count` lines             |
| `getAdTally()`                                                      | JSON text, see below                               |
| `readSkipLogText()`                                                 | the skip log and diary text, or null               |
| `installTeachingFile(name, text, sha256)`                           | true when the file was checked and installed       |
| `setTeachingShows(json)`                                            | nothing; `json` is `{"<feed key>": "<show id>"}`   |
| `getTeachingState()`                                                | JSON text, see below                               |

- A pending note is
  `{"v": 1, "at": <ms>, "what", "episode": "<episode id>", "show": "<show id or empty>", "start", "end": <seconds or null>, "kind"}`.
  The app adds the feed, guid, title and audio address from its database before
  it writes the line to the linked folder.
- `getAdTally()`:
  `{"since": <ms or null>, "shows": {"<show id>": {"skipped", "undone", "trimmed", "missed", "seconds"}}}`.
- `getTeachingState()`:
  `{"files": {"<name>": {"sha256", "installedAt"}}, "model": {"writtenAt", "episodes", "precision", "recall"} | null, "library": <entries>, "habits": <shows>, "sounds": <sounds>}`.
- The `onAdSkipped` event also carries `"kind"`.

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
