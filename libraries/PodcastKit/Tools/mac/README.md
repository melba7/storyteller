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
- `Gather more episodes for teaching.command`,
  `Mark the new episodes at night.command` and
  `Gather the exam episodes.command`: see "More episodes and the exam".
- `Measure the sound at the edges.command`: see "The sound at the edges".

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

The teaching run collects the examples the ad detector is taught from, and sends
what it learned to the phone. You do not need to write any code: you
double-click the files below, in this order, and read what the window says. Each
window shows what it does. Everything is also added to
`~/Storyteller Lofi/logs/podcast-teaching.log`. A window can be stopped with
Control-C and started again: it carries on where it was. Only one run can work
in the teaching folder at a time; a second window says so and stops. The steps
after marking hold that lock too, for their whole length, so a second window
cannot gather, mark or train while they work. When marking finds another run
busy, `Mark ads in the teaching episodes.command` stops without running them,
and `Teach the phone again.command` says so and stops.

### What to double-click

1. `Gather episodes for teaching.command`. Step 1 reads the feed of every show
   you follow and downloads the newest four episodes of each, up to 12 GB of
   audio kept in all (the limit is for everything kept, not for one run; when it
   is reached the window says so and goes on to step 2 with what is on disk),
   keeping 15 GB of the disk free. Episodes the phone asked for (see "The
   phone's notes and the wanted list" below) go first. Step 2 writes down what
   is said in them with the Swift code the app uses (needs macOS 26 and Xcode
   26; it can take hours, so keep the Mac plugged in). This does not use Claude.
2. `Mark ads in the teaching episodes.command`. Claude marks every ad and
   promotion in the written-down episodes. This is the step that uses your
   Claude plan: it shares your usage allowance, so it says what it is about to
   do and waits for you to type `yes`. Anything else marks nothing, and nothing
   else runs. It stops by itself when the allowance is used up, and you can
   double-click it again later. When the marking is over (also when it stopped
   early) it runs the steps after marking, described below. To leave the Mac
   alone for the night, double-click
   `Mark ads when the gathering is done.command` instead, while the gathering is
   still working: it asks for the `yes` at once, waits until the gathering has
   finished (also when it failed or only waits for Return), and then does the
   same without asking again.
3. `Teach the phone again.command`. Reads the phone's notes, then runs the steps
   after marking on what is marked so far. It marks nothing new and uses no
   Claude allowance. Use it after you have listened for a while, or to send the
   phone the newest results without waiting for new marks.
4. `Score the ad skipping.command`. Builds the Swift tool `podcast-teach` and
   has it score the ad skipping on the teaching folder. The report is what the
   window shows, and it is added to `scorecard.json`. It uses no Claude
   allowance.
5. `Check ads with a second download.command`. Downloads each marked episode a
   second time (at most 40 episodes and 3 GB a run, `--max` and `--max-gb`
   change that), compares the two copies and keeps the stretches where they
   differ, which are the ads the host put in. Then it snaps Claude's labels to
   those stretches into `labels-snapped/` (Claude's own labels are never
   changed) and removes the second copy. Run it before "Teach the phone again":
   the steps after marking use `labels-snapped/` whenever that folder exists.
6. `Install weekly teaching.command`, and later `Stop weekly teaching.command`.
   See "The weekly job" below.

The steps after marking are done by `teach-finish.sh`, which is not
double-clicked: the files above call it. When the folder `copies/` or
`labels-snapped/` exists it first snaps the labels to the second download (see
item 5). Then, in this order, it works out each show's habits, trains the model,
makes the library of known ads, builds `podcast-teach` and has it write the ad
sounds, trains the small meaning model (`podcast-teach meaning`, only on a Mac),
finds the joints of each episode's audio once (`podcast-teach joints`, see
`joints.json` below), scores the ad skipping, chooses the per-show settings
(`teach_settings.py`), and copies the results to the folders the phone reads.
Every step prints a heading ("Step N of 8"; the joints belong to step 6, with
the score). A step that fails is said plainly and the later steps still run,
except that the Swift steps are left out together when `podcast-teach` does not
build. The meaning step ending with a set-up problem (no shelf, no vector for
any line, no usable model) or the settings step ending without a scorecard does
not stop the run. When `labels-snapped/` exists the habits, model, library,
sounds, meaning and score steps read it instead of `labels/`. At the end it
prints one line per step (worked, nothing to do or failed). It counts as done
when the copy to the phone worked.

### More episodes and the exam

Three more files do the same work in bigger steps, with the marking only at
night. Use them in this order.

1. `Gather more episodes for teaching.command`. Downloads about 500 more
   episodes (the newest 12 of each show you follow, up to 40 GB of audio in all,
   keeping 15 GB of the disk free) and writes them down. It asks once, at the
   start: type `yes` to include the marking, or press Return to only gather.
   With `yes`, Claude then marks the new episodes (see the next file) and the
   results are worked out. It does the same as `Gather episodes for teaching`
   with the numbers set in the environment: `TEACH_PER_SHOW` (`--per-show`),
   `TEACH_MAX_GB` (`--max-gb`), `TEACH_EXAM=1` (`--exam`) and `TEACH_AFTER` (a
   file that is started in place of waiting for Return when both steps worked).
2. `Mark the new episodes at night.command`. Started by the file above when you
   typed `yes`, or double-clicked later. It is
   `Mark ads in the teaching episodes` with `--between 23-7` (it marks only
   between 11 at night and 7 in the morning, and waits for the night with the
   Mac kept awake), `--wait-hours 120` (when Claude's usage allowance is used up
   it waits 30 minutes and tries the same episode again, up to five days in all)
   and `--cap 95 --budget more-episodes` (at most $95 of the plan's usage in
   all, over every run: see "The budget" below). The environment can change
   them: `TEACH_BETWEEN`, `TEACH_WAIT_HOURS`, `TEACH_CAP` and `TEACH_BUDGET`.
   Waiting for the allowance is not a failure of the episode. Not being signed
   in still stops at once. When it ends (also stopped early) it runs the steps
   after marking, and it says why it stopped: the spending limit is reached, the
   usage allowance stayed used up for longer than it waits, or episodes failed
   (how many, and that the list is `failures.json`). Only `TEACH_YES=1` counts
   as a yes in the launchers, and a typed answer is trimmed at its ends only, so
   "ye s" is not yes.
3. `Gather the exam episodes.command`. See the next section. Run it after the
   two files above are done, so that the exam is newer than everything the phone
   learned from.

The sealed exam is a set of about 60 episodes that no learning step ever sees.
The ids are in `exam.json` in the teaching folder
(`{"episodes": ["<12 hex id>", ...]}`, `teach_exam.py`). Gathering, writing
down, marking and second downloads work on them, and the scorer when it is asked
to. The Python steps that learn leave them out:

- `teach_train.py` never trains on an exam episode, never puts one on the shelf
  and also leaves out a training episode that repeats an exam episode. It says
  how many exam episodes it left out.
- `teach_library.py` leaves their ads out of `ad-library.json` and of
  `ad-library-score.json`.
- `teach_habits.py` leaves their labels out.
- `teach_copies.py` downloads exam episodes second, first of all, then shelf
  episodes, then the rest, so a limit cuts the rest first.

Every learning step leaves exam episodes out, the Swift steps
`podcast-teach sounds` and `meaning` included. The scorer reads them only when
it is asked to.

`Gather the exam episodes.command` downloads about 60 brand-new episodes (it
runs `teach_collect.py --exam --per-show 2 --max-gb 46`; `--exam-most` changes
the 60). Only episodes that are newer than every episode of the same feed that
was gathered before are taken, and one with no date is not. Their ids go into
`exam.json` before `episodes.json` is saved and before any download, so a run
that stops half way can never leak them into training. `--list --exam` says how
many a run would take. The wanted list is ignored for an exam run. It then asks
once for a typed `yes` (or `TEACH_YES=1`). The exam's own episodes are
downloaded first, so episodes still waiting from an earlier gather cannot use up
the size allowance before them. After the gathering it says how many exam
episodes have audio and a transcript. With none it says so, marks nothing, and
stops with an error instead of saying "Done". With `yes`, Claude marks the exam
only at night (`teach_label.py --only-exam`, up to
$14 in all under the budget `exam`), and
marks 15 of them a second time into `labels-second/` (up to $4
in all under the budget `exam-second`), so we can see how much two markings
differ. The second marking is only made for an episode that already has a first
label, and its `--limit 15` counts the second labels already held. It does not
run the steps after marking: the exam teaches nothing. At the end it says how
many exam episodes are marked once and how many twice (counted by
`teach_exam.py finish`). It says "Done" and that the exam is ready to be scored
only when every exam episode that has a transcript has a first label and the
second marking holds 15 of them (or all of them when there are fewer). Otherwise
it says what is left and that double-clicking again carries on.

`teach_label.py` has these options. `--only-exam` marks only the episodes in
`exam.json`, in its order. `--between 23-7` gives the local clock hours it may
work in (a window over midnight works). The window rule: no call to Claude
starts outside the hours. The clock is checked before every call (each part of
an episode and each retry), so a usage-limit wait that ends at 7:15 does not
mark anything until 23:00. Outside the hours it waits in steps of at most ten
minutes. `--wait-hours H` waits for the usage allowance as described above. A
retry after that wait asks only for the parts of the episode that are still
missing. The opening message says the hours and the cap when they are set.

The budget. `--budget NAME` makes `--cap` the total for all runs under that
name. What was spent is kept in `marking-spend.json` in the teaching folder,
`{"version": 1, "budgets": {"<name>": {"dollars": 12.34, "episodes": 65}}}`,
written after every marked episode (and after a failed one that still cost
something). A run starts by saying what the budget has spent and what is left,
never starts a call when the budget is spent, and ends with a line saying where
it stands. A damaged file is a set-up problem, never a fresh start. Without
`--budget` the cap is for one run only, and it is checked before every call. The
launchers use the budgets `more-episodes` ($95), `exam` ($14) and `exam-second`
($4).

Exit codes of `teach_label.py`: 0 done, nothing to do, or `--limit` reached; 2 a
set-up problem or another run is working in the folder; 3 stopped early because
the usage allowance wait ran out or Claude is not signed in; 4 you did not type
yes; 5 the cap or the budget is reached; 6 stopped early because three episodes
in a row failed.

### The stream replay and Apple's model

`Score the ad skipping.command` passes `--stream`, so its report ends with a
block that replays every episode as a stream played from the start: the phone's
head scan and whole-file pass at an assumed standard pace and a slow one (the
report prints the speeds, which are guesses), the player's own skip rules, and
the same bar as above. "Ready" there means the same player with the finished
file known before play, so it shows what streaming costs. The head scan waits
for Apple's model in every row (a phone with Apple Intelligence on is assumed),
and the first 3 minutes are also shown at speech speeds of 6 and 25 times real
time, since the phone's real speed is not measured yet.

`Ask Apple's model about the test episodes.command` builds `podcast-teach` and
runs `podcast-teach apple` on the teaching folder under `caffeinate -i`. It asks
Apple's on-device model about each scored episode that has no answer yet and
saves each answer at once in `apple-model.json`, so it may be closed and
double-clicked again to carry on. It costs nothing and uses no Claude allowance,
but may take a few hours. Needs macOS 26 with Apple Intelligence on. When it
stops with exit 2 the window says to read what the tool printed above (no model,
a model still downloading, a damaged or foreign `apple-model.json`, or a folder
problem), and when every episode already had an answer it says so. A damaged
`apple-model.json` only leaves the row out of the scorecard, with a note. The
next scorecard then ends with the row "Plus Apple's model (asked on the Mac)"
and streams it too. The settings and publish steps read rows by name, so the
extra row changes nothing they decide.

### The sound at the edges

`Measure the sound at the edges.command` builds `podcast-teach` and runs
`podcast-teach edges` on the teaching folder under `caffeinate -i`. It answers
one question before anything is built into the phone: does the sound itself say
where an ad spot starts and ends? For every shelf episode that has an MP3 file
it reads the sound once (Apple's decoder, so only on a Mac, at 16 kHz, mono) and
works out, for every half second, the loudness, a 24-band spectrum and whether
it is a pause. A change score compares the 3 seconds before a point with the 3
seconds after it, and its peaks are the places where the sound changes most.
Then it counts how often the strongest change within 10 seconds of an edge lies
within 1, 2 and 5 seconds of it, for the exactly placed edges and for as many
random points (a fixed seed).

- The exact edges are the borders in `labels-snapped/` that the second download
  moved (they differ from Claude's own `labels/`), and both borders of a stretch
  that only the second download found (`"origin": "copy"`). Claude's own borders
  are not exact, so an episode with no second download has none. The folder
  needs `shelf.json` and `labels-snapped/`; the exam is never read.
- The go rule is the plan's: the strongest change within 10 seconds lies within
  1 second of at least 70% of exact edges, and of at most 10% of random points.
  The report says "Go." or "No go." and the numbers behind it. An edge within 3
  seconds of the start or end of an episode is left out, because its windows do
  not fit.
- `edges.json` keeps each shelf episode's strongest peaks (time in seconds and
  strength, about the decibels the sound moves, at most 300 for an hour) so that
  a later scorecard row can snap found edges onto them without the audio.
  `edges-report.json` keeps the numbers. Each episode is saved as soon as it is
  read, so the window may be closed and the file double-clicked again to carry
  on; an episode that is in `edges.json` is not read again. A damaged file, or
  one made by another version of the score (it is written into the file), is
  ignored with one line and made again.
- It costs nothing and uses no Claude allowance. The shelf is about 50 hours of
  sound, so it may take an hour. It needs a Mac, and stops with exit 2 and a
  plain sentence when there is no shelf, no `labels-snapped/`, or no decoder.

### What the steps write

Everything is in `~/Storyteller Lofi/PodcastTeaching`:

- `episodes.json`: the list of episodes and what happened to each one (the
  gather step writes it).
- `audio/`: the downloaded files. A file that is over 600 MB is marked "skipped"
  in the list and not tried again.
- `transcripts/`: one text file per episode (the writing-down step).
- `labels/`: one file per episode with the stretches Claude marked.
- `habits.json`: what is usual for each show.
- `shelf.json` and `ad-model.json`: the training keeps back the newest episode
  of each show as a test shelf, then writes the small model that spots ads and
  how well it did on the shelf. With `--fit-tool` (teach-finish.sh builds
  `podcast-teach` first and passes it) the model is version 2: word pairs of the
  two lines before and after as features, fitted by `podcast-teach fit`, and
  decoded with a second decoder in which the ad score leaves credits out,
  credits get a second pass, and an ad's start widens back. A widened line whose
  smoothed score is under `stay` takes the kind of the line before it, as
  bridged lines do. Without the fit tool the trainer writes a version 1 file.
  Warning: an app older than the build that reads version 2 refuses a version 2
  file and keeps the model it has, so update the phone's app before using the
  Mac's version 2 trainer.
- `ad-library.json`: every ad Claude marked with high confidence (at least 25
  words, 8 to 300 seconds), each different ad once, the ones met in most
  episodes first. An ad met in one episode only is in it too. An entry keeps the
  first 600 words of the ad. The phone gets it.
- `ad-library-score.json`: the same, built without the shelf episodes. It stays
  here, and is for scoring only, so the scorecard's "plus the library" row does
  not know the shelf ads' own words.
- `ad-sounds.json`: the sounds of the ads, made by `podcast-teach sounds`.
- `joints.json`: the joints of each episode's MP3 file (where an inserted ad was
  spliced in), made by `podcast-teach joints` once for each episode that has an
  audio file and no entry yet; existing entries are kept. `podcast-teach score`
  uses it for the joint rows when it has the episode, and reads the audio only
  when it does not, so a folder with `joints.json` and no audio still gets those
  rows. A damaged file, or one made by another version of the joint finder (it
  is written into the file), is ignored with one line and made again.
- `edges.json` and `edges-report.json`: the sound at the edges of ad spots, made
  by `podcast-teach edges` (see "The sound at the edges").
- `ad-meaning.json`: the small meaning model, made by `podcast-teach meaning`.
  It reads each transcript line as an Apple sentence vector (the Mac's own
  language model, so only on a Mac) and keeps its vectors in `meaning-cache/`.
- `show-settings.json`: per show and per finder, whether the phone may skip, may
  only ask, or must leave it off, and whether joints are used, chosen by
  `teach_settings.py` from `scorecard.json` and the phone's notes. It is written
  whole at every run, so a hand edit is lost at the next "Teach the phone
  again". It only ever makes the phone stricter than its built-in default.
  Steady joints (`steadyJoints`: steady files are used too, and a late start is
  pulled back to a joint up to 60 s before it, in steady files and in the
  others) are turned on when the scorecard's "Plus joints (steady files too)"
  row passes at least 3 more of the owner's breaks than the row before it and
  adds at most 1 skip with no ad; a scorecard with no bar is judged by seconds
  as before. The pull is only for a start that a word finder gave: an ad named
  by the repeated words, the meaning model or the word model, or an ad with no
  name that starts where an ad of the word rules or the word model starts.
- `copies/` and `labels-snapped/`: the second download's findings and the labels
  snapped to them (see item 5 above).
- `scorecard.json`: every scorecard `podcast-teach score` has made.
- `wanted.json`: the episodes to fetch first next time (see below).
- `failures.json`: which episodes failed in the writing-down step or in the
  marking. Episodes that never failed go first. One that failed three times is
  left out, and the last lines of the window say how many. To try those once
  more, run the step in Terminal with `--retry-failed`, for example
  `python3 teach_label.py --retry-failed` in the folder with these tools.
- `.lock`: how a second run notices the first. Leave it alone.

### What the phone gets

`teach_publish.py` copies the results into the `Podcasts` folder of
`~/Storyteller Lofi/LofiMusic` and of its iCloud Drive copy, the folder the
phone follows: `ad-model.json`, `ad-library.json`, `show-habits.json` (from
`habits.json`), `ad-sounds.json`, `ad-meaning.json` and `show-settings.json`.
Each file is checked first (it must be JSON with `"version": 1` and under 4.5
MB) and is only rewritten when it changed.

A weak model is not sent. The model is copied only when its precision on the
test shelf is at least 85% (`--min-precision` changes that). When it is lower,
or missing, the window says so in one sentence, a model the phone already has is
left alone and the other files are still sent. This is not counted as a failure.

The meaning model has a stricter gate. It is copied only when it passes the same
check on the test shelf and the newest scorecard shows its row "Plus the meaning
model" adding right seconds for host_ask or network_promo over the row before
it, with at least 85% of the added seconds right, and the scorecard is not older
than the model. With about four marked episodes a show this will often not hold;
then the phone never runs the meaning model, which is the safe default.
`show-settings.json` is copied when it is a valid version 1 file.

`Podcasts/teaching.json` is a short list of the files that are in that folder,
each with its hash and size. The phone reads this small file first and downloads
a big file only when its hash changed. It is rewritten only when the list
changes.

### The phone's notes and the wanted list

While you listen, the phone writes what happened to `Podcasts/phone-notes.jsonl`
in the folder it is linked to (the iCloud copy of `LofiMusic`): ads it skipped,
skips you took back ("undone"), skips you trimmed, times you pressed Skip ad
where the phone knew no ad ("missed"), and your answers to the phone's one-tap
questions ("confirmed" for Skip, "denied" for Not an ad; the note's `by` names
the finder that asked). `teach_feedback.py` reads that file (the iCloud copy
first, then the Mac's own copy), prints a small table per show and writes
`wanted.json`: the episodes with at least one "missed", "confirmed", "undone" or
"denied" note, the most recent first, at most 40. Lines that are not valid notes
are counted and skipped: not JSON, over 64 KB, a time that is not a finite
number, or a feed or audio address that is not http or https. A notes file over
8 MB is not read (it says so). A wanted episode is used only when its feed
matches a show you follow (the same feed key as the phone's: no scheme, no
`www.`, lower-case host, no fragment, no closing slash); it is gathered under
the followed show's own feed address. When the phone has sent no notes yet it
says so and writes nothing, and when macOS does not let the tool read the notes
it says that instead.

The next gather plans the wanted episodes before the newest episodes of each
show, at most 20 in one run (`--wanted 20`), even when that is more than the
usual four per show. A wanted episode is looked up in its show's feed, by its
guid or by its audio address. One that is no longer in the feed, or is already
gathered, is left out, and the window says so for a missing one. A damaged
`wanted.json` is ignored with one line. `Teach the phone again.command` and the
weekly job both run `teach_feedback.py` for you.

### The weekly job

`Install weekly teaching.command` sets up a job that runs `teach-weekly.sh`
every Sunday at 3:00 at night. It first says what it will do and asks you to
type `yes`, and installs nothing otherwise. Each week the job reads the phone's
notes, gathers the newest episode of each show (plus the wanted ones), writes
them down, has Claude mark up to 15 episodes and runs the steps after marking.
Marking is the only part that uses your Claude plan, about 15 episodes a week of
its allowance. An episode that fails still counts towards the 15, and marking
stops when the cost Claude itself counts for the calls reaches
$25 (change it
with `TEACH_CAP` near the top of `teach-weekly.sh`; the checker has no real
price, 15 episodes were estimated at about $1
each). The gather step keeps at most 12 GB of audio in all, for every week
together (`TEACH_MAX_GB`). Audio is never deleted, so once the folder is full
the job gathers nothing new: it ends with a non-zero status and one sentence in
the log that says so. The Mac has to be on or asleep at that time, not shut
down: a start missed while the Mac slept runs when it wakes up, and a week the
Mac was off is skipped. If another teaching run is working in the folder, the
job says so and ends. Double-click the installer again to replace the job (it
never makes two), and `Stop weekly teaching.command` to turn it off. For the job
to copy into iCloud Drive, give `/bin/bash` Full Disk Access once, as in "Set it
up once" above. The job runs the files in the folder you installed it from, so
install it again if you move that folder.

### The logs

- `~/Storyteller Lofi/logs/podcast-teaching.log`: what every window and the
  weekly job printed, with a dated heading for each run.
- `~/Storyteller Lofi/logs/podcast-teaching-weekly.log`: what launchd saw from
  the weekly job.

### Tests

The tests are `python3 -m unittest discover -s libraries/PodcastKit/Tools/mac`.
They use fake feeds, a fake `claude`, and stand-in `python3`, `swift` and
`podcast-teach` programs for the shell files, so they cost nothing, send nothing
and need no Mac. They also run `bash -n` on every `.command` and `.sh` file.

## Tests

`python3 -m unittest discover -s libraries/PodcastKit/Tools/mac` builds a small
library in the test; `tools/fork/check.sh` runs it. They never touch your real
library.
