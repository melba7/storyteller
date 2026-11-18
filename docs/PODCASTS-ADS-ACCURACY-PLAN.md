# Ad skipping: start and end accuracy (plan, 2026-11-18)

Mo, after TestFlight 30.1: "It doesn't skip ads in the first few seconds and
when it does catch ads, it skips too far." This plan fixes both. Fable planned
it, Sonnet builds it, Opus reviews it. Nothing here costs money: everything runs
on the phone or on Mo's Mac.

Words used: a **line** is one transcript sentence (at most 25 words, about 3 to
10 seconds). An **edge** is an ad's start or end. **Landing** is where the
player is after a skip. **Overshoot** means landing after the ad's real end, so
show content is lost. **Head** is the first 3 minutes of an episode.

Rule for every choice below: a wrong skip costs more than a missed ad. So end
fixes may only make a skip shorter or safer, never longer.

## 1. What is really wrong

### B. "Skips too far" (ranked by how much I expect each to matter)

| #   | Cause                                                                                                                                                                                                                                                                                                                                                                      | Where                                                                                                     | Size                                                                                           |
| --- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| B1  | The model picks the last line, and its instructions push it long: "keep going to the last web address" and "The ad ends when the show comes back, not when the pitch ends". One line too many is one lost sentence. Nothing checks the end afterwards.                                                                                                                     | `PodcastAdsOnDevice/AppleAdDetector.swift:136-137`                                                        | 3 to 10 s per ad, often. Likely the biggest.                                                   |
| B2  | The end is carried on for up to 8 more lines while each "reads like the ad". A line counts if it only names the advertiser, or holds any web address. Hosts who then talk about the sponsor's company, or say "find us at show.com", are swallowed.                                                                                                                        | `PodcastAds/AdCleanup.swift:19, 43, 79-87`; `AdSignals.swift:29-39`                                       | Usually one line (3 to 10 s); worst case 8 lines (about a minute).                             |
| B3  | The player's seek is only exact on files with one steady bitrate. `AVPlayerItem(url:)` is made without Apple's "precise timing" option, and AVFoundation then guesses the byte for a time from the average bitrate. The `.zero` tolerances do not help. After a wrong seek the player's clock is off for the rest of the episode, so later skips start and land wrong too. | `ios/PodcastPlayer+Stream.swift:17, 50`; `PodcastPlayer.swift:199-206`; `PodcastStreamDownload.swift:106` | 0 s on steady-bitrate files; seconds to a minute on others. **Unknown share: M1 measures it.** |
| B4  | Two ads of one kind with under 12 s of "speech" between them become one ad, so the talk between them is skipped. Apple's word times seem to run on to the next word (see B8), so this is 12 s of clock time. A teaser between a pre-roll and the sponsor read is lost this way.                                                                                            | `AdCleanup.swift:11, 110-116`                                                                             | Up to 12 s, sometimes.                                                                         |
| B5  | The quick rules for a stream's head carry an ad on while a signal comes within 3 lines, so up to 2 plain lines and then a line with any web address are taken. The clean-up then carries on again (B2). One line with "percent off" or "free trial" marks an ad with no sponsor lead-in.                                                                                   | `AdHeadRules.swift:21, 91-93, 141-149`; `ios/PodcastStreamHead.swift:266-267`                             | Up to about 25 s at the start of a stream.                                                     |
| B6  | Each edge moves to the nearest pause within 4 s in either direction, so an end can move 4 s into the show.                                                                                                                                                                                                                                                                 | `AdCleanup.swift:21, 54-57, 152-163`                                                                      | Up to 4 s. Probably rare on the phone (B8), but free to fix.                                   |
| B7  | Answers are only ever joined by taking the later end: overlapping pieces, rules plus model, a kept partial file. A long answer always beats a short one.                                                                                                                                                                                                                   | `AdCleanup.swift:107-108`; `AdHeadRules.swift:180`; `AdsRunner.swift:102-104`                             | Makes B1, B2, B5 stick.                                                                        |
| B8  | The end is the last word's end time. A developer reports that SpeechTranscriber's word ends equal the next word's start, pauses included. Then the landing is exactly the first content word with no margin, and its first sound is clipped. That feels "too far" by a fraction of a second on every skip.                                                                 | `PodcastSpeech/AppleSpeech.swift:84-93, 233-239`                                                          | 0.1 to 0.3 s, every skip. **M1 confirms the word times.**                                      |

Checked and not a cause: the piece cuts in `AdChunker` (120 s overlap, ads seen
whole), the partial passes (they cut ads short at the edge, never long), the 0.5
s chain in `AdSkipper`, and the stream's time base while playing straight
through (`Mp3Prefix` counts frames, the decoder counts the same samples; only a
seek can go wrong, which is B3).

I cannot rank B1, B2 and B3 against each other from the cloud: there is no real
transcript or audio here. M1 prints, for Mo's own episodes, what each step added
to each end and whether his files are steady-bitrate. The safe fixes E1 to E4 do
not wait for it.

### A. Nothing skipped in the first seconds

| #   | Cause                                                                                                                                                                                                                                          | Where                                                            |
| --- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------- |
| A1  | On a stream the first look happens only after 30 s of audio is on disk and transcribed, and the model is first asked after 60 s of audio. Playback starts at once, so the listener is in the ad before anything is known.                      | `AdHeadRules.swift:26-28`; `ios/PodcastStreamHead.swift:204-290` |
| A2  | The quick rules need a sponsor lead-in plus a link or code. A produced pre-roll (an inserted spot) has no lead-in, so only the model catches it, 8 to 15 s after the tap by my estimate. The phone timing was never measured (`PLAN.md:1078`). | `AdHeadRules.swift:104-116`                                      |
| A3  | An ad's start is its first word. Music or a sting before that word plays. Nothing says "an ad that begins in the first seconds begins at 0:00".                                                                                                | `AdCleanup.swift:46, 54`                                         |
| A4  | Nothing is remembered. The same inserted spot or the same sponsor read is found from scratch in every episode.                                                                                                                                 | no code yet                                                      |
| A5  | Episodes in Up Next are not downloaded ahead, so they start as never-checked streams.                                                                                                                                                          | `ios/PodcastPrepQueue.swift:27`                                  |
| A6  | The sponsors named in the episode's notes are never passed to the rules on the phone, so that rule is dead there.                                                                                                                              | `ios/PodcastStreamHead.swift:266`                                |

Honest limit, unchanged from the earlier research: an ad nobody has seen, in an
episode nobody has checked, cannot be skipped at 0:00. Its words must be
downloaded, transcribed and judged. The plan gets that case to about 5 to 8 s
(jumping out of the ad), and gets repeats and prepared episodes to 0:00.

## 2. What was looked up

Ideas and numbers only. No code was copied.

| Source                                                                                                                                                                                  | What I took                                                                                                                                                                                             |
| --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [MinusPod audio cues](https://github.com/ttlequals0/MinusPod/blob/main/docs/audio-cues.md) (MIT)                                                                                        | Its silence snap moves an edge at most 2 s, to a silence of 0.3 s or more, is off by default, and is undone when it harms the ad. So our 4 s two-way snap is too loose (E1).                            |
| [MinusPod how it works](https://github.com/ttlequals0/MinusPod/blob/main/docs/how-it-works.md), [configuration](https://github.com/ttlequals0/MinusPod/blob/main/docs/configuration.md) | "Tail completion" (our carry-on) runs only with its reviewer on. A reviewer pass "confirms, adjusts, or rejects each cut" (E6). Ads are learned as text patterns only when sure, 15 to 120 s long (S2). |
| [Detecting Extraneous Content in Podcasts](https://ar5iv.labs.arxiv.org/html/2103.02585) (Spotify, 2021)                                                                                | Found ends are off by 35 words on average, starts by 16. Ends are the hard edge for everyone. Sentence-level text models work; whole-segment matches are only 43 to 67% right.                          |
| [Earsay: how ad detection works](https://scour.ing/@matmat/p/https://earsay.app/blog/how-ad-detection-works.php)                                                                        | Refine each edge with a second, narrow look (binary search), need several "not ad" answers in a row to leave an ad, snap only "within a small window" (E6, E1).                                         |
| [SponsorBlock guidelines](https://wiki.sponsor.ajay.app/w/Guidelines)                                                                                                                   | A segment at the start begins at 00:00.0 (E1). Exclude content that is not needed for a clean skip. Start early "to account for any lag".                                                               |
| [Marco Arment on VBR MP3](https://marco.org/2016/08/)                                                                                                                                   | AVFoundation seeks MP3 by `time / duration × bytes`. On variable bitrate the error "can result in an error of over a minute" (B3, E5).                                                                  |
| [Apple: AVURLAsset options](https://developer.apple.com/documentation/avfoundation/avurlasset-initialization-options.md)                                                                | `AVURLAssetPreferPreciseDurationAndTimingKey`: "accurate duration and precise random access by time" (E5).                                                                                              |
| [Apple forum: SpeechTranscriber time indexes](https://developer.apple.com/forums/thread/788827)                                                                                         | "Each run is always exactly one word" and "the end of one run is always identical to the start of the next run, even if there's a pause" (B8). One developer's report, so M1 checks it.                 |
| [Unsplice](https://github.com/karangattu/unsplice)                                                                                                                                      | Uses "changes in sound or MP3 encoding" as a hint, and fingerprints of sponsor messages that repeat across episodes. A change alone is only a suggestion (M1 seam scan, S2).                            |
| [Efficient Advertisement Discovery for Audio Podcast Content](https://link.springer.com/article/10.1155/2010/572571)                                                                    | Ads repeat across episodes; a store of repeats built on the fly found 97.5%. Edges come from tracing the match outwards (S2 does this with words).                                                      |
| [Skipper on the App Store](https://apps.apple.com/us/app/skipper-auto-skip-podcast-ads/id6757127240), [PinePods](https://pinepods.online/docs/next/AI/AdDetection)                      | Skipper shipped "Greatly improved accuracy of ad start and stop times" and star buttons to report bad skips (F1). PinePods admits "within a few seconds (the boundary of a spoken segment)".            |

Rejected, and why:

- **Acoustic fingerprints (Chromaprint and the like).** They would recognise a
  repeat about a second sooner than text. But they need a decode and a spectrum
  pipeline, and [Chromaprint](https://oxygene.sk/) "still depends on LGPL code".
  Text memory (S2) reuses the transcript we already make. Later.
- **An audio classifier (Earsay).** Needs labelled audio and a trained model.
- **Jingle templates (MinusPod).** The listener must mark each show's jingle.
- **Loudness steps as splice proof (MinusPod, 12 dB).** Needs a decode of the
  stream and several episodes to calibrate. Later.
- **Per-show time templates** ("this show has 60 s of ads at 0:00"). Inserted
  ads change in number and length per download. See decision 3.
- **Crowd lists, servers, cloud models.** No open list exists; the others cost
  money or send Mo's listening away from the phone.

## 3. The milestones, in order

Each is one Sonnet session. All of E1 to E4, M1 and F1 go in one pull request
and one TestFlight build (LESSONS: keep a round together). Every milestone:
write the named test first and see it fail; run `tools/fork/check.sh`; the iOS
module compiles only in Fork CI. Tests use `makeTranscript` from
`AdTestSupport.swift` (line n covers (n-1)×10 s to +9 s, a 1 s gap after it)
unless they say "own words".

### E1. Safe landing (pure Swift)

- Files: `PodcastAds/AdCleanup.swift`, `AdCleanupTests.swift`.
- Replace the two-way pause snap (`Pauses`, `snapReach`) with these rules, in
  `AdCleanup.run` after the merge:
  1. **End**: let L be the last transcript word that starts before the span's
     end, and N the next word. `end = max(L.start, N.start - 0.25)`. With no N,
     `end = L.end`. New constant `AdRules.landBefore = 0.25`.
  2. **Start**: let F be the first word at or after the span's start, and P the
     word before it. `start = max(P.end, F.start - 0.25)`. With no P,
     `start = 0`.
  3. **Top of the episode**: when `F.start <= 6.0` the start is 0. New constant
     `AdRules.topOfEpisode = 6.0`.
  4. Then the length checks as today (10 to 300 s).
- Remove `Pauses` and `snapReach` (unused after this) and their two tests.
- Tests first:
  - "The landing is a quarter second before the first word after the ad":
    `talk(30)`, `range(3, 5)` gives start 19.75, end 49.75.
  - "A pause three seconds into the show does not pull the end" (own words: the
    ad's last word is 48.0 to 49.0, show words run without a gap from 49.2 to
    52.0, then a pause to 54.0): end is 48.95. Today it is 53.0.
  - "Words that run on to the next word still leave a margin" (own words: last
    ad word 48.0 to 50.0, next word starts 50.0): end is 49.75.
  - "An ad that begins in the first six seconds begins at zero": first word at
    4.0 gives start 0; first word at 7.0 gives start 6.75.
- Existing tests that expect an edge in the middle of a pause (x9.5) change to
  x9.75. That is the rule changing, not a test being weakened.
- Risk: the last quarter second of an ad is heard. Intended.

### E2. A short, strict carry-on, and "the show is back" cues (pure Swift)

- Files: `PodcastAds/AdSignals.swift`, `AdCleanup.swift`, tests.
- `AdSignals` gets three checks. `hardSignal(text)`: today's patterns (a web
  address, "dot com", a code, "percent off", "free trial", "brought to you by").
  `softCue(text)`: `thanks( again)? to`, `thank you to`, `go to`, `head to`,
  `visit`, `check out`, `sign up`, `learn more`, `again,? that's`.
  `returnCue(text)`: `welcome back`, `(we're|we are) back`,
  `back to the (show|episode|conversation|interview)`, `let's get back`,
  `now,? back to`, `where were we`, `welcome to`, `i'm your host`,
  `on today's (show|episode)`, `in this episode`, `my guest today`,
  `joining me (today|now)`. All case-insensitive, whole words.
- A line after the ad is **carried** only when it has no return cue and either
  has a hard signal, or names the advertiser and also has a soft cue or is at
  most 8 words long.
- `AdRules.carryLines` is 2 (was 8). New `AdRules.carrySeconds = 15`: a carried
  line must end within 15 s of the model's last line.
- **Trim**: in the model's own last 3 lines (never its first line), find the
  first line R with a return cue such that no line from R to the end has a hard
  signal or names the advertiser. The ad then ends at line R-1 and nothing is
  carried.
- **Unsure** ads are never carried.
- Tests first (advertiser "Quokka", `range(3, 5)`, edges per E1):
  - Line 6 "Quokka shares fell four percent after the company reported earnings
    on Tuesday": end 49.75 (today 59.5).
  - Line 6 "Thanks again to Quokka": end 59.75.
  - Line 6 "Welcome back to the show, find us at example.com slash podcast": end
    49.75.
  - `range(3, 6)` with line 6 "And we're back. So where were we": end 49.75.
  - `range(3, 6)` with line 6 "Welcome back, and remember code SHOW at
    acme.com": end 59.75 (a hard signal keeps it).
  - Forty lines of "go to acme dot com", `carriedEnd(of: 5)`: 7 (today 13).
  - An unsure `range(3, 5)` followed by "that is acme dot com slash show": end
    49.75.
- Risk: an ad's plain last sentence ("They're great. I love them.") is heard.
  That is the cheap side of the trade.

### E3. A stricter merge (pure Swift)

- Files: `AdCleanup.swift`, tests.
- `AdRules.mergeSpeech` is 4.0 (was 12). New `AdRules.mergeFiller = 12.0`: two
  sure ads of one kind with under 12 s between them still merge when every line
  that lies wholly between them is filler. A line is filler when
  `AdSignals.hardSignal` is true, or it names either advertiser, or it matches a
  new `AdSignals.breakCue`: `right back`, `after (the|this) break`,
  `quick break`, `one more`, `a word from`, `support for`, `sponsors?`,
  `also brought`.
- An unsure ad never merges with a neighbour that it does not overlap.
- Tests first: ads at lines 3 to 5 and 7 to 9 with line 6 plain talk are two ads
  (today one). With line 6 "We'll be right back after one more word from our
  sponsor" they are one ad, 19.75 to 89.75. A sure ad and an unsure ad with
  filler between stay two.
- `testAdsWithLittleSpeechBetweenThemAreOneBreak` keeps its meaning with a
  filler line between its ads.
- Risk: a few seconds of "we'll be right back" talk plays between two skips.

### E4. Tighter quick rules for a stream's head (pure Swift)

- Files: `PodcastAds/AdHeadRules.swift`, tests.
- `gap` is 1 (was 3), and the next signal line must start within 12 s of the
  last one's end (`gapSeconds = 12`). A line with a return cue (E2) ends the ad
  before it.
- A span with no lead-in and no sponsor from the notes needs two signals: one
  line with both a web address and an offer or code, or two signal lines at most
  2 lines apart.
- Tests first: lead-in on line 1, link on line 2, plain talk on 3 and 4, "follow
  us at example.com" on line 5: the ad is lines 1 to 2 (today 1 to 5). "That is
  twenty percent off the usual price" alone in plain talk: no ad. The same line
  followed by "at acme.com slash show": an ad.
- Risk: a long host read found by the rules ends early until the model's answer
  joins it. The model's 30 s step (S1) closes most of that gap.

### M1. Measure the edges and the seeks on Mo's Mac

- Files: `PodcastAds/AdCleanup.swift` (a trace), new
  `PodcastAudioMatch/SeekDrift.swift`, `podcast-ads/main.swift`, new
  `Tools/mac/Check ad edges on an episode.command`, the Mac README.
- `AdCleanup.explain(ranges:transcript:)` returns, per ad: the model's first and
  last line, lines trimmed, lines carried, how many answers were merged, the
  final times, and the text and times of the 2 lines before and 3 lines after
  each edge. `run` is built on it, so both always agree.
- `SeekDrift.report(_ parse: MP3Parse)` returns: the frame count per bitrate,
  `steady` (one bitrate for 99% of frames), `worstSeconds` (for each frame, the
  time AVFoundation's ratio guess would land on, minus the true time; the
  largest gap), and `seams`: places where the frame header (bitrate, sample rate
  or channels) changes for at least 50 frames, or an `Xing` or `Info` marker
  sits in a frame after the first.
- `podcast-ads --edges <audio or transcript>` prints the trace, then: the share
  of neighbouring words with a gap of 0.3 s or more (answers B8), the mean words
  and seconds per line, and for audio the SeekDrift lines plus the player's
  duration without the precise option against the decoded duration. With
  `--truth <file>` (lines of `mm:ss mm:ss`, hand-marked ads) it also prints, per
  ad, start error and end error in seconds, the mean and the worst overshoot,
  missed ads and false ads.
- The `.command` asks for an audio file, runs `--edges`, and saves
  `<name>.ad-edges.txt` next to it.
- Tests first: `SeekDriftTests`, "a file of 1,000 frames of 417 bytes and then
  3,000 frames of 209 bytes is not steady and its worst error is about 9.8 s
  (within 0.2)"; "4,000 equal frames are steady with 0 s". `AdCleanupTests`,
  "explain says one line was carried and names it".
- Mo: double-click it on 3 episodes where a skip went too far and send the 3
  files. It needs macOS 26 with Apple Intelligence on, like the other ad tools.
- What the result decides: `steady` false on any show makes E5's second half
  needed. Ends that are still late in the trace with nothing carried mean B1,
  and E6 goes ahead. Seams at the times of known ads feed I3.

### F1. "Too far" is one tap, and is remembered

- Files: `PodcastAds/AdsStore.swift`, `AdSkipping.swift`, tests;
  `ios/PodcastPlayer+Ads.swift`, `PodcastPlayer.swift`, `PodcastPlayer+Stats`;
  the "Skipped ad" note in `podcasts/`.
- `AdsFile` gets `trims: [AdTrim]?` (`adStart`, `end`); an old file reads as no
  trims. `AdSkipper.backSeek(to:now:)` returns a trim when a skip was made at
  most 20 s ago and the seek lands before the landing and at most 60 s before
  it, inside the skipped stretch. From then on that ad ends at the trim.
- The player calls it from `seek(to:)` and saves the trim. The note gets a
  second button, "Back 10 s", beside Undo. Undo stays as it is: it plays the ad
  from its start and that ad is never skipped again.
- Three counters in the listening stats: ad skips, undone, too far. They are the
  phone's own proof numbers (section 5).
- Test first: an ad 60 to 120 skipped at `now` 100;
  `backSeek(to: 110, now: 105)` gives a trim (60, 110) and the ad is then 60 to
  110; `backSeek(to: 110, now: 130)` gives nil; `backSeek(to: 30, now: 105)`
  gives nil.
- Risk: low. A trim only shortens.

### E5. Exact seeks

- Files: `ios/PodcastPlayer+Stream.swift`, `ios/PodcastStreamHead.swift`.
- A downloaded file plays as
  `AVPlayerItem(asset: AVURLAsset(url: file, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true]))`.
  Cost: iOS reads the file's frame table when it opens, a fraction of a second
  for a local file. No pure-Swift test is possible; the proof is on the phone.
- Only if M1 shows a file that is not steady: the head scan runs
  `SeekDrift.report` on the bytes it already reads. When a stream is not steady
  and its download has been filed, the next ad skip swaps the player item to the
  filed file with the precise option and seeks there (the same bytes, so the ads
  fit). Before the file is whole, such a stream's skips can still land wrong;
  the status line says "This file's timing is rough".
- Proof: on a show M1 flagged, the first words after a skip are whole.
- Risk: a slower start on very long files. Log "item ready" in the timeline.

### S1. A faster first look on a stream

- Files: `PodcastAds/AdHeadRules.swift`, `ios/PodcastStreamHead.swift`,
  `PodcastSpeech/AppleSpeech.swift`, `ios/PodcastsModule.swift`,
  `podcast-ads/HeadTimings.swift`.
- Steps are 15, 30, 60, 90, 120, 150, 180 s (was 30 first). The model is asked
  at 30, 60, 120 and 180 s (was 60 and 180). At the 30 s step only its sure
  answers count; an unsure one waits for the 60 s step. After each answer the
  next warm session is made and asked to prewarm.
- The speech model is loaded once when the app comes to the front with Skip ads
  on (`AppleSpeech.warm(locale:)`: make an analyzer, `prepareToAnalyze`, let it
  go; the model stays for the process).
- Test first: `AdHeadRules.steps(upTo: 90)` is `[15, 30, 60, 90]`; `modelSteps`
  is `[30, 60, 120, 180]`.
- Proof: `Time the first minute of an episode.command` (rules at 15 s under 2 s
  warm, model at 30 s under 6 s on the Mac). On the phone the `AdTimeline` log
  gives tap to first skip.
- Limit: a never-seen produced pre-roll is known about 5 to 8 s after the tap on
  Wi-Fi, and the player jumps out of it. A pre-roll shorter than that plus 3 s
  is heard whole.
- Cost: two more model calls per stream (a few seconds of the chip), about 100
  MB of speech model held by the system while the app runs.

### S2. Remember ads by their words (pure Swift)

- Files: new `PodcastAds/KnownAds.swift`, `KnownAdsTests.swift`.
- `KnownAd`: show id, advertiser, kind, the ad's words (lower case, no
  punctuation, at most 150), its length in seconds, times seen, last seen.
- **Learn** from a final ads file and its transcript: only sure ads, not undone,
  not trimmed (F1), 15 to 120 s, at least 25 words. An ad that matches a stored
  one updates it (seen + 1). At most 40 per show and 400 in all; ones not seen
  for 60 days go. One file, `Application Support/Podcasts/known-ads.json` (under
  0.5 MB).
- **Match** against transcript words, using runs of 3 words: the ad opens where
  at least 6 of its first 10 runs appear in order within 16 words. From there go
  on while its runs keep appearing with at most 12 unmatched words between. With
  at least 60% of its runs found the answer is `whole(start, end)`: the first
  and last matched word's times. When the transcript ends first the answer is
  `opening(start, expectedEnd: start + length)`.
- Tests first: a learned 60-word ad placed at word 30 of other talk, with 2
  words changed, is `whole` with exactly those word times; a transcript that
  ends 20 words into it is `opening`; 5 shared words in a row match nothing; an
  unsure, undone, 12 s or 130 s ad is not learned; the same ad twice is one
  entry with seen 2.

### S3. Use the memory on the phone

- Files: `ios/PodcastAdFinder.swift` (learn when a final file is saved),
  `ios/PodcastStreamHead.swift` and `PodcastAdFinder+Queue.swift` (match before
  the rules, save matches as sure ads), `ios/PodcastPlayer+Ads.swift` (Undo on a
  remembered ad forgets it).
- On `opening`, the head scan's next step goes straight to `expectedEnd + 10` s
  of audio. Only when the ad was seen at least twice is a provisional ad saved
  at once, ending 1 s before `expectedEnd`.
- Proof: play two episodes of a show that share a pre-roll; in the second the
  timeline shows "memory: 1 ad" at the 15 s step and the first skip under 3 s.
- Limit: only ads whose words repeat. A host who reads the same sponsor
  differently is not matched.

### S4. A short wait before a never-checked stream starts (needs Mo's OK)

- Files: new `PodcastAds/StartHold.swift` and tests, `ios/PodcastPlayer.swift`,
  `ios/PodcastStreamHead.swift`.
- `StartHold.wanted` is true when Skip ads is on, the episode plays through its
  own download, it starts under 1 s, nothing is saved for it, and the show is
  not known to start clean (the last 5 checked episodes had no ad before 30 s;
  kept beside the known ads). Then `play()` waits for the first of: the 15 s
  step's rules and memory are done, the scan ended, 3.0 s since the tap, or a
  second tap on Play. If an ad holds 0:00 the player starts after it.
- The status line says "Checking the start for ads".
- Test first: a table of the five inputs; "released by the first verdict at 1.4
  s"; "released at 3.0 s with no verdict".
- Limit: it only helps ads the rules or the memory catch in 15 s of audio.
- Cost: up to 3 s of silence on such episodes.

### E6. The model checks each end, and new instructions

- Only after M1 shows late ends that E2 does not explain.
- Files: `PodcastAds/AdModels.swift`, `AdsRunner.swift`, tests;
  `PodcastAdsOnDevice/AppleAdDetector.swift`.
- New protocol `AdEdgeChecker` with
  `lastAdLine(of range: AdRange, in lines: [NumberedLine]) async throws -> Int?`.
  After a piece is answered, `AdsRunner` asks it for each ad of 3 lines or more,
  with the lines from 3 before the end to 4 after it. An answer is used only
  when it lies inside the ad (it can only shorten). The refined answer is what
  the progress file keeps.
- The instructions lose "The ad ends when the show comes back, not when the
  pitch ends" and gain: "The last line of a run is the last line that still
  sells something. The line where the hosts greet listeners or return to their
  topic is not part of it." The version becomes "2", so every episode is checked
  again on the phone (free, but it uses battery for a day or two).
- Tests first, with a fake checker: an answer one line earlier ends the ad one
  line earlier; an answer 3 lines later is ignored; a thrown error keeps the
  model's end.
- Proof: `--edges --truth` on Mo's 3 episodes before and after.
- Cost: one more model call per ad, about 20 s more per episode.

### S5. Download what is next in Up Next (needs Mo's OK)

- With Skip ads on and on Wi-Fi, the next 2 episodes in Up Next download ahead
  and are deleted like other played downloads. Their heads are then checked
  before they play, so they skip at 0:00.
- It touches downloads and storage (50 to 100 MB per episode), so it follows the
  review step in CLAUDE.md. Files: `ios/PodcastDownloader.swift`,
  `PodcastPlayer+UpNext.swift`, `PodcastDownloads` rules and tests.

### What happens when a skip is still a little off

- A little early: the last quarter second or sentence of the ad plays. Nothing
  to do.
- A little late: "Back 10 s" on the note (F1). The ad is shortened for good.
- Not an ad at all: Undo, as today. A remembered ad is forgotten (S3).
- No fade for now: the landing is in a pause in most cases after E1. See Later.

## 4. Decisions

1. **Should a never-checked episode wait before it plays?** Yes, for at most 3
   s, and only for a stream that starts at 0:00 on a show not known to start
   clean (S4). A longer wait would be needed for the model (5 to 8 s), and that
   is too long to sit in silence; the model's answer arrives while the ad plays
   and the player jumps out. Mo confirms before S4 is built.
2. **Should found ads be remembered?** Yes, as words, not as sound (S2, S3). The
   transcript already exists 1 to 3 s after the tap, a text match gives edges
   exact to the word, and it needs no new decoder or licence. Sound fingerprints
   stay in Later.
3. **Should per-show start templates be learned?** No. A template that says
   "skip the first 60 s" is wrong whenever the host inserts a different number
   of ads, and a wrong skip costs content. One bit per show is kept instead:
   whether its episodes start with an ad, which decides the wait in S4.
4. **Is I3 (a second quick download) worth building?** Only if Mo's "Test my
   shows" report shows, for at least 3 of his shows, that the two copies differ
   at the start and then share identical frames. Then it is the one way to skip
   a never-heard inserted pre-roll within 1 to 3 s with an end exact to 26 ms,
   and it is worth it. If the copies are the same or share no frames, drop it:
   S2 covers repeats. M1's seam scan is added to that report first.
5. **Should confidence change how far a skip goes?** Yes. An unsure ad is
   skipped to its safest end: the model's own last line, never carried (E2),
   never merged with a neighbour (E3), never learned (S2), and at the 30 s step
   it waits for a second opinion (S1).

## 5. Proof

Numbers, and where each comes from:

| Number                                        | Target                                    | Printed by                           |
| --------------------------------------------- | ----------------------------------------- | ------------------------------------ |
| End overshoot against hand-marked ads         | at most 1 s for 9 ads in 10; never over 3 | `--edges --truth` (M1)               |
| End undershoot (ad still heard)               | at most 5 s for 8 ads in 10               | the same                             |
| Start error                                   | within 2 s                                | the same                             |
| False ads                                     | at most 1 in 10 episodes                  | the same, and the "undone" counter   |
| Worst seek error                              | 0 s on steady files                       | `--edges` SeekDrift lines            |
| First skip, never-seen stream                 | 8 s or less after the tap                 | `AdTimeline` log; `--head --timings` |
| First skip, remembered ad or prepared episode | at 0:00 (after a wait of at most 3 s)     | `AdTimeline` log                     |
| "Too far" taps per 20 skips                   | at most 1                                 | the three counters (F1)              |

Hand marks: Mo sends 3 episodes' `.ad-edges.txt`. Claude marks each ad's real
first and last line from the printed text, and Mo checks 3 of them by ear. That
truth file is reused for every later change.

The one thing Mo does on the phone: on Wi-Fi, play a brand-new episode of a show
that opens with an ad, from the start. Count the seconds until the first skip,
listen whether the first word after each skip is whole, and tap "Back 10 s"
whenever a skip went too far. Then open the listening stats and read the three
numbers.

## 6. Later

- A 150 ms fade-in after a skip, if landings still click (it must work with the
  volume slider and voice boost).
- Sound fingerprints for ads, if text memory misses repeats.
- When two pieces saw the same ad whole and disagree, take the earlier end (B7).
- Land on a measured silence (`<sha256>.silence.json`) instead of a word time.
- Loudness steps and frame seams as proof of an inserted ad's edges.
- Pass the sponsors named in the episode's notes to the rules on the phone (A6).
- `docs/PODCASTS-PLAN.md` still says streams play without ad skipping and that
  edges move to the nearest pause; update it when E1 lands.

## 7. Second round: more ideas (2026-11-18)

Mo: "think of more ideas to make ad skipping as good as possible". Nothing in
sections 1 to 6 is repeated here. The rule stays: a wrong skip costs more than a
missed ad, so a new signal may shorten an end or raise or lower how sure an ad
is, but it never makes a skip longer on its own. Nothing here costs money.

### 7.1 What was looked up

| Source                                                                                                                                                                   | What I took                                                                                                                                                                                                                                                       |
| ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [RSS.com: why timestamps are off with paid ads](https://help.rss.com/en/support/solutions/articles/44002648096-why-timestamps-might-be-slightly-off-when-using-paid-ads) | The host does not move chapters, transcripts or soundbites when it inserts ads; each is late by the full length of the ads before it. So the publisher's transcript holds the show without the inserted ads (N3), and chapter times need a check (N9).            |
| [US patent 12190871, dynamic ads in long-form audio](https://image-ppubs.uspto.gov/dirsearch-public/print/downloadPdf/12190871)                                          | Two versions of one episode are compared by sound and by transcript words; "matched runs are content, mismatched runs are ads", and short stray windows are folded into their neighbours. N3 does the word half against the feed's transcript, with one download. |
| [US patent 11922967, repetitive content in podcasts](https://image-ppubs.uspto.gov/dirsearch-public/print/downloadPdf/11922967)                                          | Only the title was read: repeats across episodes are a known route to ads and intros (N1, N4).                                                                                                                                                                    |
| [Sounds Profitable: the many flavors of DAI](https://soundsprofitable.com/article/the-many-flavors-of-dynamic-ad-insertion/)                                             | Ads are chosen per request (IP, user agent, time) and stitched in at markers the producer set. It does not say whether the ad's bytes are copied as they are; that is the open question behind N1.                                                                |
| [Apple: prompting an on-device model](https://developer.apple.com/tutorials/data/documentation/foundationmodels/prompting-an-on-device-foundation-model.md)              | Keep instructions to "one to three paragraphs", give "between 2-15 examples" that are very simple, put a reasoning field first, turn if-else wording into code that builds the prompt, and split a hard task into simple requests (N10).                          |
| [Wolf, Univ. Hamburg 2025, MA thesis on podcast ads](https://www.inf.uni-hamburg.de/en/inst/ab/lt/teaching/theses/completed-theses/2025-ma-wolf.pdf)                     | Sound plus text beat either alone; neighbouring sentences did not help a per-sentence judge; inserted and host-read ads differ; most ads come in blocks of two or more spots. The result tables were not readable, so no numbers are quoted.                      |
| [Apple forum: native diarization](https://developer.apple.com/forums/thread/829621)                                                                                      | A developer says the iOS 26 speech API has no "who is speaking". No Apple reply. So a voice-change signal has no free source (hold H3).                                                                                                                           |
| [SoundAnalysis built-in classifier](https://www.swiftjectivec.com/sound-analysis-framework-built-in-model)                                                               | Over 300 sound classes ship on the device and can run over a file in windows. A music-or-speech track is possible without training (hold H2).                                                                                                                     |

Not found: any public write-up of how hosts splice MP3 frames (bit reservoir,
re-encoding). N1 and N2 are therefore guesses with a cheap Mac experiment.

### 7.2 The ideas, ranked

Gain letters: (a) first seconds, (b) exact end, (c) no lost content, (d) no
false skips. "Apple" means code that compiles only in Fork CI.

| Id  | What                                                                                                                          | Gain                             | Effort           | Mo's OK?                    | When                     |
| --- | ----------------------------------------------------------------------------------------------------------------------------- | -------------------------------- | ---------------- | --------------------------- | ------------------------ |
| N1  | Find audio that is byte-for-byte the same in two different episodes (frame hashes): inserted spots, with edges exact to 26 ms | a, b: large if it holds          | small, pure      | no (Mac tool)               | now: the probe only      |
| N2  | Sponsor names from the notes (links with a path, "code X") and from the show's past ads, used by the phone's rules            | a: medium, d: small              | small, pure + 1  | no                          | now                      |
| N3  | Compare our words with the feed's `podcast:transcript`: words the publisher does not have are inserted audio                  | a, b: large where a feed has one | medium, pure     | yes for the fetch (small)   | now: pure part and count |
| N4  | Learn each show's opening words; where they start, the pre-roll has ended                                                     | b, c: medium at the start        | small, pure      | no                          | now, after S2            |
| N5  | Cut inside the edge line: end before a "we're back" in the ad's last line                                                     | b, c: 3 to 8 s on some ads       | small, pure      | no                          | now, after E1 and E2     |
| N6  | An evidence gate: a "sure" ad with no ad words in it becomes unsure; a cap on the share of an episode that can be ads         | d: medium                        | small, pure      | no                          | now                      |
| N7  | Cues of produced spots ("terms apply", "download the app") as signals and as the ad's last line                               | a: small to medium, b: small     | small, pure      | no                          | now, after E2 and E4     |
| N8  | A skip log with the outcome of every skip, sent from Settings; later it tunes each show                                       | measures a to d                  | small, pure + UI | yes (a new file is kept)    | now: log; tuning held    |
| N9  | Chapters named "Sponsor" or "Ad" as ads, when the transcript agrees                                                           | b: exact on such shows           | small, pure      | no                          | now                      |
| N10 | Prompt: two or three tiny examples, a reason field first, the notes' sponsors written into the prompt                         | a, b, d: unknown                 | small, Apple     | no (re-check uses battery)  | hold: joins E6           |
| N11 | Unsure ads are offered ("Ad? Skip") instead of skipped                                                                        | d: large, a: costs a tap         | medium, UI       | yes (behaviour)             | hold for the counters    |
| N12 | Fetch only the first 3 minutes of the next episodes (3 to 4 MB each) and check them ahead                                     | a: 0:00 on a first play          | medium, Apple    | yes (network, battery)      | hold: replaces S5 first  |
| N13 | A per-show "stitched or baked-in" flag from the enclosure hosts, the notes and the response headers                           | enables N9, N12, S4              | small, pure      | no                          | hold until N1's result   |
| N14 | Remember inserted spots by their frames on the phone (N1's finding in the player)                                             | a: 0:00 in under 1 s, b          | medium           | yes (keeps hashes per show) | hold until N1's result   |
| N15 | Per-show caution from the log: fewer unsure skips and shorter ends on shows where Mo undoes                                   | c, d                             | small, pure      | no                          | hold for 2 weeks of log  |
| N16 | Music or speech per second (SoundAnalysis), to put a start on the sting and an end after the outro bed                        | a (A3), b: unknown               | medium, Apple    | yes (battery)               | hold                     |

### 7.3 The milestones to build now

Same rules as section 3: one Sonnet session each, the named test first and
failing, `tools/fork/check.sh`, pure Swift unless marked.

#### N1. Shared frames between episodes, and truth without hand marks (Mac tool)

- Cause: A4 and B1. A guess to be settled: a host that stitches an ad copies the
  ad's MP3 frames as they are, so the same spot in two episodes is the same
  bytes. If true, a spot heard once is recognised from its first half second of
  bytes, before any transcript exists, and its end is exact to one frame.
- Files: new `PodcastAudioMatch/SharedRuns.swift`, `MP3SideInfo.swift`, tests;
  `podcast-ads/main.swift`; new
  `Tools/mac/Compare two episodes of a show.command`; the Mac README.
- `SharedRuns.find(_ a: MP3Parse, _ b: MP3Parse, minFrames: 115)` returns the
  runs of equal frame hashes in the same order (115 frames is 3 s), by an index
  of hashes, not by aligning the files. A run needs at least 20 different
  hashes, so digital silence is not a run.
- `MP3SideInfo.mainDataBegin(_ frame: Data) -> Int?` reads the 9-bit (MPEG-1) or
  8-bit (MPEG-2) reservoir pointer after the header and CRC. `SeekDrift.report`
  (M1) gains `reservoirResets`: frames with pointer 0 that follow 50 frames with
  a pointer above 0. Second guess: a spot encoded on its own starts with an
  empty reservoir, so a reset marks a stitch.
- `podcast-ads --shared a.mp3 b.mp3` prints each run's times in both files and
  whether a reset or an M1 seam lies within 2 frames of each end.
  `podcast-ads --truth-from-copies a.mp3 b.mp3` (two downloads of one episode,
  the existing `FrameAlign`) writes the differing stretches of copy A as a
  `--truth` file, so stitched shows get exact truth with no listening.
- Tests first: "a 1,150-frame spot at frame 200 of one file and at frame 0 of
  another is one run, 200..<1350 and 0..<1150"; "a run of 100 frames is not
  reported"; "300 equal frames of one hash are not a run"; "the pointer of a
  frame whose side info starts 0x0A 0x80 is 21"; "a reset after 60 frames with a
  pointer is listed, one after 10 is not".
- Mo: double-click it on two different episodes of each of 3 shows that open
  with the same kind of ad, and send the 3 text files.
- Proof target P1: on at least 2 of 3 shows, a run of 10 s or more lies inside a
  known ad, with a reset or seam at both ends. Then N14 is built. If no show has
  a run, N14 and the reservoir idea are dropped and S2's words stay the only
  memory.

#### N2. Sponsor names reach the phone (pure Swift, one line of iOS)

- Cause: A6 (it was in Later; it is cheap and feeds A2, so it moves up).
- Files: `PodcastAds/AdHeadRules.swift`, `AdSignals.swift`, tests;
  `ios/PodcastStreamHead.swift` (pass the names).
- `sponsors(inNotes:showLink:)` also takes a name from each link with a path
  (`quince.com/pod` gives "quince") and from "code POD at acme.com", leaves out
  the show's own host, social and podcast-app hosts, and the hosts' own-plug
  words. Names of 4 letters or more only.
- `AdSignals.mentions(_ text:, name:)` ignores spaces and "dot", so "better help
  dot com" matches "betterhelp". The rules and the carry-on both use it.
- The head scan passes the notes' names plus the advertisers of that show's
  sure, not undone ads (from S2's known ads once S3 is in; the notes alone
  before that).
- Tests first: notes "Go to betterhelp.com/show for 10% off. Follow us at
  instagram.com/show and example.fm/live" with show link `example.fm` give
  `["betterhelp"]`; the head lines "Better Help makes therapy simple" and "visit
  better help dot com slash show" with that sponsor are one sure ad, lines 1 to
  2 (today nothing); a line that names the sponsor with no call within 2 lines
  is no ad.
- Proof target P2: on Mo's 3 episodes, `--head --timings` shows the rules
  catching at least one pre-roll at the 15 s step that only the model caught
  before.
- Risk: a note that links a guest's book ("penguin.com/book") makes that
  publisher a sponsor name. The rule still needs a call to action beside the
  name, so the cost is small.

#### N3. Words the publisher's transcript does not have (pure part and a count)

- Cause: A1, A2, B1 for inserted ads. The feed's transcript is made from the
  show before ads are stitched in. Our words that are missing from it, between
  stretches that match, are inserted audio, and the match gives both edges to
  the word. With the transcript fetched when the feed refreshes, the 15 s step
  can say "these first words are not the show's opening" in milliseconds.
- Files: new `PodcastAds/TranscriptDiff.swift`, tests; `probe_shows.py` (count
  the feeds that carry `podcast:transcript`, and its types).
- `TranscriptDiff.plainWords(_ file: String, type: String)` strips VTT, SRT and
  JSON timing and speaker labels. `TranscriptDiff.inserted(ours:theirs:)`
  anchors on runs of 5 equal words in order and returns our unmatched stretches
  of at least 20 words and 8 s that have a match after them (and a match before
  them, unless they start the episode). It answers nil when under half of our
  words match at all (another language, a summary, or a transcript that was made
  from the stitched file and so has the ads).
- How an answer is used (wired in a later milestone, after Mo's OK): a stretch
  that overlaps a rules or model ad gives that ad its start, and its end when
  that is earlier. A stretch no one else found is saved as unsure, or sure when
  it holds a hard signal (E2).
- Tests first: 40 ad words, then 200 words of theirs with 3 changed: one
  stretch, words 0..<40, ending at word 39's time; a 12-word stretch is not
  reported; ours and theirs sharing 30% of words give nil; a stretch that runs
  to the end of our words (a head still downloading) is not reported.
- Proof target P3: the probe says how many of Mo's shows carry a transcript.
  Under 3 shows: stop here. Otherwise ask Mo for the fetch (tens of KB per
  episode, at feed refresh) and wire it.
- Risk: a publisher that cuts its own cold open from the transcript. That is why
  a stretch alone is only unsure.

#### N4. The show's opening words (pure Swift, after S2)

- Cause: B1 and B5 at the start: nothing says where the show begins.
- Files: `PodcastAds/KnownAds.swift` (reuse the run matcher), new
  `ShowOpening.swift`, tests. The phone wiring rides with S3.
- Learn: when two checked episodes of a show share a run of 8 to 40 words in
  their first 5 minutes, outside every ad, keep it as the show's opening (one
  per show, replaced when 3 newer episodes do not have it).
- Use: when the opening is found at time t in a head, any ad that holds 0:00 and
  ends after t ends at `t - 0.25`; an unsure ad that contains the opening is
  dropped; S4's wait is released ("the show has begun").
- Tests first: two episodes with "from the example network this is the daily
  example i'm sam" after different pre-rolls learn those words; a head where
  they start at 31.0 and an ad runs 0 to 42 gives an ad 0 to 30.75; a show whose
  episodes share no run learns nothing; a shared run inside a sure ad is not
  learned.
- Proof target P4: on a show with a fixed intro, `--edges --truth` shows the
  pre-roll's end within 0.5 s.
- Limit: shows with a cold open before the intro gain nothing (and lose nothing:
  the opening is then found later than any pre-roll's end).

#### N5. Cut inside the edge line (pure Swift, after E1 and E2)

- Cause: B1. A line holds up to 25 words, so the ad's last line can hold the end
  of the pitch and the hosts' return. E2 trims whole lines only.
- Files: `PodcastAds/AdCleanup.swift`, `AdSignals.swift`, tests.
- In the ad's last line, find a return cue (E2's list). When every hard signal
  and advertiser mention in the line comes before the cue, and at least 3 words
  come before it, the ad ends at the last word before the cue (then E1's landing
  rule). The same for the first line of a sure ad with a lead-in: when 8 or more
  words come before the lead-in and none of them is a signal, the ad starts at
  the lead-in's first word.
- `AdSignals.returnCueRange(in:)` and `leadInRange(in:)` return word indexes.
- Tests first (own words): last line "that's acme dot com slash show and we're
  back with Dana", "and" starting at 57.0: end 56.75 (after E2 it is 59.75);
  "we're back at acme dot com" does not cut; a first line "so that was wild
  anyway this episode is brought to you by Quokka" starts at "this".
- Risk: none for content; a cut can only shorten.

#### N6. The evidence gate (pure Swift)

- Cause: false skips. The model's "sure" is its own word; nothing checks it.
- Files: new `PodcastAds/AdEvidence.swift`, `AdCleanup.swift`, tests.
- `AdEvidence.count(lines:advertiser:)` counts lines with a hard signal, a soft
  cue, a spot cue (N7) or a usable advertiser name. In `AdCleanup.run`, before
  the merge: a sure ad with a count of 0 becomes unsure (and so, by decision 5,
  is never carried, merged or learned). After the merge: when the ads cover over
  35% of the transcript's time, or one ad is longer than 180 s, each such ad
  with a count under 2 becomes unsure.
- Rules ads, memory ads and trims are not touched.
- Tests first: `range(3, 5)` sure over plain talk with advertiser "" comes out
  unsure; with "acme.com" on line 4 it stays sure; 12 of 30 lines marked sure in
  three ads, one of them with no signal: that one is unsure.
- Proof target P6: on Mo's truth files, no true ad loses "sure".
- Note for N11: this makes "unsure" mean more, which is what makes offering
  unsure ads instead of skipping them worth a decision.

#### N7. Cues of produced spots (pure Swift, after E2 and E4)

- Cause: A2. A produced spot has no lead-in, but it has a legal or store close.
- Files: `PodcastAds/AdSignals.swift`, `AdHeadRules.swift`, tests.
- `AdSignals.spotCue(text)`: `terms( and conditions)? apply`,
  `restrictions apply`, `see (site|store|website) for details`, `member fdic`,
  `(must be|for ages) (18|21)`, `gamble responsibly`, `(for a )?limited time`,
  `download the .{1,30} app`, `available (now|today) (at|on|in|wherever)`,
  `wherever you (get|listen to) (your )?podcasts`, `streaming now`,
  `in theaters`, a spoken phone number (`1[- ]8(00|88|77|66)`).
- A spot cue counts as a signal in E4's two-signal rule and in N6's count. A
  line that ends with a terms cue is a **closer**: the line after it is carried
  (E2) only when it has a hard signal.
- Tests first: head lines "Download the Quokka app today" and "Terms and
  conditions apply" are an ad; either alone is not; `range(3, 5)` with line 5
  "...restrictions apply" and line 6 "Thanks again to Quokka": end 49.75.
- Risk: "wherever you get your podcasts" is also said by hosts about their own
  show. It is one signal of the two needed, never enough alone.

#### N8. The skip log (pure Swift and a Settings row)

- Cause: nobody can see why a skip was wrong. F1 gives three totals; this gives
  the cases.
- Files: new `PodcastAds/SkipLog.swift`, tests; `ios/PodcastPlayer+Ads.swift`; a
  "Send skip log" row beside the listening stats.
- One line of JSON per skip in `Application Support/Podcasts/skip-log.jsonl`:
  time, show and episode ids, ad start and end, kind, confidence, source (rules,
  model, memory, chapter, diff), seconds from tap to skip, the 12 words before
  and after each edge, and the outcome. `SkipLog.outcome` is `kept`, `undone`,
  `trimmed(seconds)` (F1), or `seekBack(seconds)` for a manual seek back within
  20 s that is not a trim. Three forward jumps by the listener within 60 s where
  no ad is known are logged as `maybeMissed`.
- At most 500 lines; the oldest go. Nothing leaves the phone unless Mo shares
  it. Words from the transcript are in it, so it is never committed.
- Tests first: a skip then `backSeek` 5 s later is `trimmed(10)`; no event in 20
  s is `kept`; line 501 drops line 1; three forward jumps in 40 s give one
  `maybeMissed`.
- Proof target P8: after a week Mo sends the file and section 5's numbers are
  read from it, per source.

#### N9. Chapters that name a sponsor (pure Swift)

- Cause: B1 on shows whose producer marks ad breaks as chapters.
- Files: new `PodcastAds/ChapterAds.swift` (uses `PodcastChapters`), tests. The
  phone wiring is one call where the finder already has the chapters.
- A chapter whose title starts with `sponsor`, `ad`, `ads`, `ad break`,
  `advert`, `commercial`, `break`, or contains `sponsored by` or
  `brought to you by`, is a candidate from its start to the next chapter's
  start, 10 to 300 s. It becomes a sure ad only when the transcript lines inside
  it hold a hard signal or the name in the title; this is the guard against
  chapters that inserted ads have pushed out of place (7.1, first row). When it
  overlaps a model ad, the chapter's edges win if they shorten the end.
- Tests first: chapters at 0 "Intro", 600 "Sponsor: Squarespace", 690
  "Follow-up" with "squarespace dot com" at 640 give one ad 600 to 690; the same
  with plain talk inside gives none; "Adventures in Peru" is no candidate.

### 7.4 What changes in the plan's milestones and order

- **M1** gains N1's `reservoirResets` line and `--truth-from-copies`. If M1 is
  merged first, N1 adds them; nothing in M1 is redone.
- **E2 and E4** keep their lists; N7 adds `spotCue` and the closer rule after
  them. **E1 and E2** are followed by N5 in the same file, so N5 waits for their
  merge.
- **F1**'s counters stay. N8 writes one log line where F1 counts.
- **S2** is unchanged; N4 reuses its run matcher, and N2 reads its advertiser
  names. **S3** also carries N4's use and N2's names.
- **S4** (the 3 s wait) gets two earlier releases: N4's "the show has begun"
  and, once wired, N3's "the first words match the publisher's". Mo's OK for S4
  is still needed.
- **S5** changes shape if Mo agrees: do N12 (heads only, 3 to 4 MB) first and
  whole downloads only if N12's bytes turn out not to be reusable.
- **E6** takes N10 with it (examples, reason field, sponsors in the prompt) so
  the model's version goes up once and every episode is re-checked once. N5 and
  N6 should shrink what E6 has to fix; measure before building E6.
- Later items "frame seams as proof of edges" and "sound fingerprints" are now
  N1 and N14; "pass the notes' sponsors" is N2.
- Order after the round in flight: N2, N6, N5, N7 (one pull request, all
  `PodcastAds`), then N1 and N8 (Mo's part starts), then N9, N3, N4.

### 7.5 What to hold, and why

- **N10 (prompt).** A prompt change can only be judged against truth. Wait for
  M1's files and N1's `--truth-from-copies`, then compare old and new
  instructions on the Mac with `--edges --truth` (free, Mo's Mac).
- **N11 (offer unsure ads).** It trades missed ads for a tap. Decide from F1's
  "undone" count and N8's log: if unsure ads are over a third of the undone
  skips, ask Mo.
- **N12 (heads ahead).** Only works when a later request gives the same bytes.
  "Compare two downloads of an episode" already answers that per show: where the
  copies are equal, build it; where they differ, it is wasted.
- **N13 and N14.** They depend on P1. N14 keeps 55 KB of head hashes per episode
  for 5 episodes a show, so it needs Mo's OK for storage.
- **N15.** Needs two weeks of N8's log; with less, one bad day would silence a
  show.
- **H1: land on a measured silence or reset.** Still in Later; now also needs P1
  to say whether resets sit at real edges.
- **H2: N16, music or speech from SoundAnalysis.** Apple-only, costs a decode of
  the head, and there is no evidence yet that stings are what Mo hears. Cheapest
  test: in N8's log, look for skips whose 12 words before the start are empty
  for 3 s or more.
- **H3: voice change.** No speaker labels in the iOS 26 speech API by a
  developer's report; a home-made pitch tracker is a research task. Dropped
  unless Apple adds it.
- **H4: a second quick download for every stream (I3).** Unchanged from decision
  4; N1's tool makes its truth, so I3's test is cheaper now.
- **Honest gaps.** N1, the reservoir reset, N3's share of shows and N10's gain
  are guesses until P1, P3 and the truth files exist. N2, N5, N6, N7 and N9 are
  rule changes whose direction is safe (they add evidence or shorten), so they
  do not wait.
