# Podcast tools (Mac)

Tells the Storyteller Lofi app which podcasts you follow in Apple Podcasts and
which episodes you finished there. One way: Apple Podcasts' files are only read,
never changed.

## Set it up once

1. In Finder, double-click `Install Apple Podcasts sync.command`.
2. macOS may ask whether Terminal may access data from other apps. Click
   **Allow**. That is Apple's own guard on the Podcasts library.
3. The window says "That worked." and the job now runs every hour.

If the prompt never appeared or you clicked Don't Allow, open System Settings,
Privacy & Security, Full Disk Access, click **+**, press Cmd-Shift-G, type
`/bin/bash`, add it and switch it on. Then double-click the installer again. The
hourly job is a different program from the Terminal window, so macOS may ask
once more the first time it runs by itself. Allow it too.

The phone needs nothing new. It reads the file through the sounds folder you
already linked (the `LofiMusic` folder in iCloud Drive) the next time the app
opens or refreshes.

## What it writes

`Podcasts/apple-podcasts.json` in `~/Storyteller Lofi/LofiMusic` and in its
iCloud Drive copy: the feed link and title of every followed show, and the feed
link and guid of every finished episode. An episode is finished when you played
it or marked it as played; the old episodes Apple Podcasts marks as played when
you follow a show do not count. It is only rewritten when something changed.

On the phone, a followed show that is new to the app is subscribed to, but none
of its episodes is downloaded. Finished episodes are marked played. A show you
unfollow in Apple Podcasts stays in the app, and a show you unsubscribe from in
the app is not added again.

## Other things to double-click

- `Sync Apple Podcasts now.command` runs one sync in a window.
- `Transcribe an episode.command`: see the next section.
- `Find ads in an episode.command`: see the section after it.
- `Check ad skipping on an episode.command`: see "Check ad skipping".
- `Time the first minute of an episode.command` and
  `Compare two downloads of an episode.command`: see "How fast can the first ads
  be found".

To turn the hourly job off, run in Terminal:
`launchctl bootout gui/$(id -u)/com.storyteller-lofi.apple-podcasts`, then
delete `~/Library/LaunchAgents/com.storyteller-lofi.apple-podcasts.plist`.

## If it says it failed

The log is `~/Storyteller Lofi/logs/apple-podcasts.log`. The last run's result
is at the end.

- "Apple Podcasts' library has changed: missing table or column ..." means a
  macOS update renamed something in Apple's file. The names are in one place at
  the top of `apple_podcasts_export.py`; send the message along to get it fixed.
  Nothing was written, so the phone keeps what it had.
- "macOS did not let this read Apple Podcasts' library" means the macOS prompt
  was refused; see the Full Disk Access steps above.
- "Apple Podcasts' library is not at ..." means Apple Podcasts has not been set
  up on this Mac.

Exit codes: 0 worked, 2 could not read or write, 3 Apple's format changed.

## Transcribe an episode

`Transcribe an episode.command` asks for an audio file in a dialog, transcribes
it with the same Swift code the app uses (Apple's SpeechAnalyzer through
PodcastKit's `podcast-transcribe`), and saves the lines with their times next to
the file as `<file name>.transcript.txt`. Use it to check transcripts without a
new build of the app.

It needs macOS 26 and Xcode 26. The first run builds the tool (about a minute),
and the first run for a language downloads Apple's speech model. The language is
the Mac's; to use another one, run
`swift run -c release podcast-transcribe --locale de-DE <file>` in
`libraries/PodcastKit`. A run that is stopped carries on where it was (progress
is kept in the temporary folder). On a Mac without macOS 26 the tool only says
so.

## Find ads in an episode

`Find ads in an episode.command` asks for a transcript (a
`<hash>.transcript.json`) or an audio file, finds the ads with the same Swift
code the app uses (Apple's on-device model through PodcastKit's `podcast-ads`),
and saves the list next to the file as `<file name>.ads.txt`. An audio file is
transcribed first, as above. Each line is one ad: its start and end, its length,
its kind (an ad, or the hosts' own plug), how sure the model is, the advertiser
and its first words. The app skips the sure and the unsure ones (Undo takes a
skip back). Use it to check what the detector finds in an episode without a new
build of the app.

It needs macOS 26 with Apple Intelligence turned on (System Settings, Apple
Intelligence & Siri) and Xcode 26. The first run builds the tool (about a
minute). Each piece of about ten minutes takes the model a few seconds, so an
hour-long episode takes a minute or so. If Apple Intelligence is off, or its
model is still downloading, the tool says so and stops. On a Mac without macOS
26 it only says so.

## Check ad skipping on an episode

`Check ad skipping on an episode.command` asks for an audio file and finds out
whether ad skipping would keep ahead of you. It does what the phone does for an
episode that is playing: it transcribes the file piece by piece (the first
pieces are short, so the first lines come within seconds), looks for ads after
each piece, and times every step on this Mac. It runs PodcastKit's
`podcast-ads --play`, and saves the result next to the file as
`<file name>.ad-check.txt`.

For each ad it prints where the ad is, how sure the model is, how long the work
had been going when the ad was first known, when a listener who pressed play at
0:00 at normal speed would reach it, and SKIPPED or NOT SKIPPED. An ad counts as
skipped when it was known before the playhead got there. The skips before it are
counted, because each one moves you ahead. The end says how long transcribing
and the model took, and how many times faster than real time the whole thing
ran. Above 1 means the work keeps ahead of someone listening.

How to run it:

1. In Finder, double-click `Check ad skipping on an episode.command`. (Auto mode
   on the Mac refuses `swift run`, so this is the way to run it.)
2. Choose an episode in the dialog. Pick one with ads in the first minutes, like
   a pre-roll.
3. Wait. The first run builds the tool (about a minute) and may download Apple's
   speech model. An hour-long episode takes a few minutes.
4. Read the list. If ads are NOT SKIPPED, send the saved `.ad-check.txt` along.

It needs macOS 26 with Apple Intelligence turned on and Xcode 26, like the two
tools above. It counts only the work on this Mac, not the download. The phone is
slower than a Mac, so a Mac that only just keeps ahead means a phone that falls
behind.

## How fast can the first ads be found

Two tools that measure what "skip the first ad at once" can rely on. They cost
nothing and use no keys.

### Time the first minute of an episode

`Time the first minute of an episode.command` asks for an MP3 file and runs
`podcast-ads --head 90 --timings`. It follows the path a stream takes on the
phone: one speech analyzer made ready ahead, the start of the file cut at a
whole MP3 frame in 30 second steps (30, 60, 90), each step transcribed, the text
rules run after each step, and the ad model asked at 60 seconds (with a session
warmed ahead) and at 180 seconds (with a fresh one) when the head reaches them.
A stall or an error here is one the phone would meet too. It does all of this
twice in one go, so you see a cold run (the app just opened) and a warm one.
Each run prints, in seconds since that run began:

- **speech ready**: Apple's speech model loaded. The warm run should be close to
  zero.
- **transcript to N s**: each step's transcript, with its words and how long the
  step took.
- **rules at N s**: the text rules after that step, with the ads they found.
- **model at N s**: the ad model's answer, with how long it took. The last time
  on a run is how long the first 90 seconds of a stream take to check.

Then it lists the ads left at the end. It saves the text next to the file as
`<file name>.head-timings.txt`. Under 10 seconds on the Mac is good. A phone is
slower, so a Mac result is the best case. Pick an MP3 episode with an ad at the
start (a file that is not an MP3 is refused, as the phone's scan refuses it).
Needs macOS 26 with Apple Intelligence on and Xcode 26, like the other ad tools.

### Compare two downloads of an episode

`Compare two downloads of an episode.command` offers two choices.

**Test my shows (recommended).** Double-click it, choose Test my shows, wait a
few minutes, and send back the file it shows. It reads the shows you follow
(from the Apple Podcasts sync; if that file is missing, it says to double-click
`Sync Apple Podcasts now.command` first), takes the newest episode of up to 8 of
them, one per hosting service, and probes each one (see below). The report is
`~/Storyteller Lofi/logs/ad-probe-shows-<time>.txt`, with a table at the end:
one line per show with its host, whether the two copies were the same bytes or
differed, and whether they share frames. It downloads 3 MB twice per show, one
show at a time with a pause between them. `probe_shows.py` picks the shows.

**One episode address.** The rest of this section is about this choice, which
asks for an episode's audio address (the `.mp3` link in the show's feed; if the
clipboard holds a web address it uses that without asking). It runs
`podcast-ads --probe`: it downloads the first 3 MB twice, once as
"StorytellerLofi/1.0 podcast client" and once under a different name, because a
host that inserts ads chooses them per request and may hand the same ads to the
same client twice. Then it cuts both copies into MP3 frames (skipping the ID3
tag), lines them up by a hash of each frame, and prints:

- the host after redirects, the answer code (206 means the range request
  worked), the size, the frame count and the length of each copy;
- the **ranges that differ and then join again**, with their times in each copy.
  These are candidate inserted ads. A range that is empty in one copy is an ad
  only that copy had;
- how many frames are **byte-identical** in both copies. A high share means the
  show's own audio comes through the host untouched, so frames can be compared.
  Zero means the host re-encodes every download and this method cannot work
  there;
- a line saying what it all means.

If it says the copies are byte for byte the same, that host gave both listeners
one file (the same ads, or none), and there is nothing to compare. Listen to a
range at its time before believing it is an ad. It needs no key and no Apple
Intelligence, only Xcode 26. The output goes to `~/Storyteller Lofi/logs`. The
second download looks like a second listener to the publisher, so run it once
per episode, not in a loop.

### Which six episodes to try

One episode from each of these six hosts, ideally from a show that plays ads at
the start (so a second download can differ):

| Host             | How to tell from the feed's audio address                        |
| ---------------- | ---------------------------------------------------------------- |
| Megaphone        | `traffic.megaphone.fm` (feeds are on `feeds.megaphone.fm`)       |
| Art19            | `art19.com`, such as `rss.art19.com` for the feed                |
| Acast            | `acast.com`; feeds look like `feeds.acast.com/public/shows/<id>` |
| Simplecast       | `simplecast.com` or `simplecastaudio.com`                        |
| Omny             | `omny.fm` or `omnycontent.com`                                   |
| Spotify / Anchor | `anchor.fm` or `spotifycdn.com`                                  |

Many shows send audio through a counting service first (`dts.podtrac.com`,
`chrt.fm`, `pscrb.fm`, `mgln.ai` and the like). The probe prints the host after
redirects, so run it once and read that line: that is the real host. To find an
address, open the show's feed in a browser and copy an `<enclosure url="...">`.

I could not confirm from the web which famous show sits on which host today (the
pages found only listed old Panoply and Slate shows for Megaphone, and the Acast
feed pattern above is from Acast's help page). Choose shows you listen to, look
at their feeds, and use the table. Shows that come from a network with a sales
team (public radio, big talk shows) are the most likely to have inserted ads.

## Tests

`python3 -m unittest discover -s libraries/PodcastKit/Tools/mac` builds a small
library in the test; `tools/fork/check.sh` runs it. They never touch your real
library.
