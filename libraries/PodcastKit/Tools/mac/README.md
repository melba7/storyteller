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
- `Check ad edges on an episode.command`: see "Check ad edges".
- `Compare two episodes of a show.command`: see "Compare two episodes of a
  show".
- `Time the first minute of an episode.command` and
  `Compare two downloads of an episode.command`: see "How fast can the first ads
  be found".
- `Gather episodes for teaching.command` and
  `Mark ads in the teaching episodes.command`: see "Teaching run".

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

## Check ad edges

`Check ad edges on an episode.command` finds out where each ad skip starts and
ends, and why it is where it is. Use it on an episode where a skip went too far
or started late. It asks for an audio file, transcribes it, finds the ads with
the same Swift code the app uses, and runs PodcastKit's `podcast-ads --edges`.
The result is saved next to the file as `<file name>.ad-edges.txt`.

For each ad it prints:

- the times, the kind, how sure the model is and the advertiser;
- the lines the model named, as line numbers with their times;
- the lines taken off the end because the hosts said the show was back, and the
  lines carried onto the end because they still sold something;
- how many seconds each step moved the start and the end: trimming or carrying,
  then the landing (a quarter second before the next word);
- the two lines before and the three lines after each edge, with their times and
  words, so you can read where the skip really lands.

After the ads it prints what the transcript's word times look like: the share of
neighbouring words with a gap of 0.3 s or more, and the share where one word
ends exactly where the next starts. If nearly every word ends where the next
starts, the transcript hides the pauses, and a skip cannot find a pause to land
in. It also prints the average words and seconds in a line.

For an MP3 file it adds what Apple's player does with the file. Apple's player
finds a time by jumping to the same share of the file's bytes, which is right
only when every frame is the same size (one steady bitrate). It prints how many
frames there are at each bitrate, whether the bitrate is steady, the worst seek
error that jump would make (0 s on a steady file), the places where the encoding
changes for good (often where an ad was spliced in), the places where the bit
reservoir restarts (see the next section), and the length the player is given
next to the decoded length.

How to run it:

1. In Finder, double-click `Check ad edges on an episode.command`.
2. Choose the episode. The first run builds the tool (about a minute) and may
   download Apple's speech model. An hour-long episode takes a few minutes.
3. Send back the saved `.ad-edges.txt`. Do this for 3 episodes where a skip went
   too far.

To compare the skips with ads you marked by hand, put a text file named
`<file name>.truth.txt` next to the episode, with one ad on each line as two
times (`12:30 13:45`; `1:02:03` and `12:30.5` work too; lines that start with
`#` are left out). The result then also says, for each marked ad, how many
seconds early or late the start and the end are, the mean and the worst
overshoot (a skip that lands after the ad's real end), the ads that were missed
and the ads that were not ads.

It needs macOS 26 with Apple Intelligence turned on and Xcode 26, like the other
ad tools. With a transcript file (`<hash>.transcript.json`) and Terminal,
`swift run -c release podcast-ads --edges <file>` still prints the transcript's
numbers on a system without Apple Intelligence, and says that the rest is left
out.

## Compare two episodes of a show

`Compare two episodes of a show.command` finds out whether an ad that comes back
in two episodes of a show is the very same bytes in both. Some hosts may copy an
ad's audio into every episode as it is. If so, an ad heard once could be known
again from its first half second, before any transcript exists, and its start
and end would be exact to one MP3 frame (about 26 milliseconds). No public
write-up of whether hosts do this was found, so this is a measurement, not a
fix. It changes nothing in the app.

How to run it:

1. In Finder, double-click `Compare two episodes of a show.command`.
2. Click **Compare my shows (recommended)**. You need no files: it reads the
   shows you follow in Apple Podcasts (from the Apple Podcasts sync; if that
   file is missing it says to double-click `Sync Apple Podcasts now.command`
   first), takes up to 3 of them from different hosting services, finds the two
   newest episodes of each in the show's feed, and downloads only the first 20
   MB of each, one at a time with a pause between them: 6 downloads, about 120
   MB in all. The start of an episode is where pre-roll ads sit, so that is
   enough; ads later in an episode are not looked at. The downloads go to a
   temporary folder that is deleted when it is done.
3. Wait a few minutes. The first run builds the tool. The report is saved as
   `ad-shared-shows-<time>.txt` in `~/Storyteller Lofi/logs`, and Finder shows
   it. Send that one file back.

To use two MP3 files you already have, click **Two files I choose** instead,
then pick the first episode and a second, different episode of the same show
(two that open with the same kind of ad). The result is saved as
`ad-shared-<name of the first file>-<time>.txt` in the same folder.

A publisher sees each of the 6 downloads as a listener who stopped after the
first minutes, so run it once, not in a loop.

It needs no Apple Intelligence, only Xcode 26. It keeps no audio.

The report for the shows has one section for each show, with the two addresses
it downloaded, how much of each it kept, and then the result below. It ends with
a table, one line per show: the host, how many runs there are, the longest one,
and how many runs have a reset or a change of encoding at both ends, in the
first and in the second episode. Each section holds the result for its two
files. That result first says how long each file is and how often its bit
reservoir restarts. An MP3 frame can borrow room from the frames before it; the
pointer that says how far back is the "main data begin" number. A piece of audio
that was encoded on its own starts with nothing to borrow, so a frame with the
number 0 that follows 50 or more frames with a number above 0 is called a
reservoir reset, and may be where a spot was joined in. It then lists each
stretch of 3 s or more that is the same bytes in both files, as a "run". The two
files need not hold it at the same time; a spot may open one episode and sit in
the middle of the other. A stretch has to hold 20 different frames, so digital
silence is not a run. For each run it gives the times in both files and says
whether a reset or a change of encoding sits within 2 frames of the start and of
the end. The summary counts the runs of 10 s or more that have one at both ends,
and says in plain words what the result means.

How to read it: a run of 10 s or more that you recognise as an ad when you
listen at its time, with a reset or a change at both ends, means the host copies
ads as they are and the edges can be seen in the bytes. No run, or runs that are
only a jingle, means a spot cannot be told by its bytes on that show. If the
file says most of the two files is the same audio, you chose two downloads of
one episode, not two episodes.

### Marking the ads of an episode without listening

`podcast-ads --truth-from-copies <first.mp3> <second.mp3>` takes two downloads
of one episode (the same episode fetched twice, so a host that picks ads for
each listener gave each copy different ads), finds where they differ and then
agree again, and writes those stretches of the first file as
`<first.mp3>.truth.txt`, the file of marked ads that
`Check ad edges on an episode.command` compares the skips with. The times are
exact to a frame. Run it in Terminal in `libraries/PodcastKit` with
`swift run -c release podcast-ads --truth-from-copies <first.mp3> <second.mp3>`.
It refuses to overwrite a `.truth.txt` that is already there, so marks you made
by hand are kept. It marks only what the two copies do not share: an ad that
both copies got is not marked, and the end of a file that stops differing is
only mentioned in a note, because a download that was cut off looks the same.
Stretches under 1 s are left out and noted too.

## How fast can the first ads be found

Two tools that measure what "skip the first ad at once" can rely on. They cost
nothing and use no keys.

### Time the first minute of an episode

`Time the first minute of an episode.command` asks for an MP3 file and runs
`podcast-ads --head 90 --timings`. It follows the path a stream takes on the
phone: one speech analyzer made ready ahead, the start of the file cut at a
whole MP3 frame in steps (15, 30, 60, 90 seconds), each step transcribed, the
text rules run after each step, and the ad model asked at 30 seconds (only its
sure answers count then) and at 60 seconds, and at 120 and 180 seconds when the
head reaches them. Each time the model gets a session that was warmed after the
last answer. A stall or an error here is one the phone would meet too. It does
all of this twice in one go, so you see a cold run (the app just opened) and a
warm one. Each run prints, in seconds since that run began:

- **speech ready**: Apple's speech model loaded. The warm run should be close to
  zero.
- **transcript to N s**: each step's transcript, with its words and how long the
  step took.
- **rules at N s**: the text rules after that step, with the ads they found.
- **model at N s**: the ad model's answer, with how long it took. The last time
  on a run is how long the first 90 seconds of a stream take to check.

In the warm run, the "rules at 15 s" line should come under 2 seconds and the
"model at 30 s" line under 6 seconds.

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

## Teaching run

Two files to double-click collect the examples the ad detector is taught from.
Each window shows what it does, and everything is also added to
`~/Storyteller Lofi/logs/podcast-teaching.log`. Both can be stopped with
Control-C and started again: they carry on where they were. Only one of them can
work at a time; a second window says so and stops.

- `Gather episodes for teaching.command` has two steps. Step 1 reads the feed of
  every show you follow and downloads the newest four episodes of each, up to
  12 GB, keeping 15 GB of the disk free. Step 2 writes down what is said in
  them with the Swift code the app uses (needs macOS 26 and Xcode 26; it can
  take hours, so keep the Mac plugged in).
- `Mark ads in the teaching episodes.command` has Claude mark every ad and
  promotion in the written-down episodes, then works out each show's habits (for
  example whether it often starts with an ad). It uses your Claude plan and
  shares its usage allowance, so it says what it is about to do and waits for
  you to type `yes`. Anything else marks nothing. It stops by itself when the
  allowance is used up, and you can double-click it again later.

Everything is in `~/Storyteller Lofi/PodcastTeaching`:

- `episodes.json`: the list of episodes and what happened to each one (step 1
  writes it).
- `audio/`: the downloaded files. A file that is over 600 MB is marked
  "skipped" in the list and not tried again.
- `transcripts/`: one text file per episode (step 2).
- `labels/`: one file per episode with the stretches Claude marked.
- `habits.json`: what is usual for each show.
- `failures.json`: which episodes failed in step 2 or in the marking. Episodes
  that never failed go first. One that failed three times is left out, and the
  last lines of the window say how many. To try those once more, run the step
  in Terminal with `--retry-failed`, for example
  `python3 teach_label.py --retry-failed` in the folder with these tools.
- `.lock`: how a second run notices the first. Leave it alone.

The tests are `python3 -m unittest discover -s libraries/PodcastKit/Tools/mac`;
they use fake feeds and a fake `claude`, so they cost nothing and send nothing.

## Tests

`python3 -m unittest discover -s libraries/PodcastKit/Tools/mac` builds a small
library in the test; `tools/fork/check.sh` runs it. They never touch your real
library.
