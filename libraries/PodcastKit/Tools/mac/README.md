# Apple Podcasts sync (Mac)

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
link and guid of every finished episode. It is only rewritten when something
changed.

On the phone, a followed show that is new to the app is subscribed to, but none
of its episodes is downloaded. Finished episodes are marked played. A show you
unfollow in Apple Podcasts stays in the app, and a show you unsubscribe from in
the app is not added again.

## Other things to double-click

- `Sync Apple Podcasts now.command` runs one sync in a window.

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

## Tests

`python3 -m unittest discover -s libraries/PodcastKit/Tools/mac` builds a small
library in the test; `tools/fork/check.sh` runs it. They never touch your real
library.
