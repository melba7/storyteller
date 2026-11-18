# Simulator checks (Maestro)

These checks start the Storyteller+ app in an iPhone simulator and use it the
way a listener does: open Podcasts, play an episode, tap the small player, swipe
the big player down. They are how the player bug (the page that shows twice and
then cannot be opened) and the "needs several taps" bug are checked without a
phone. The tool is [Maestro](https://docs.maestro.dev). It drives the finished
app from outside, so nothing is added to the app. Building the app for it does
touch `applications/mobile/package.json` for a while; see "Run it on Mo's Mac".

## The four flows

They are in `flows/`. Every flow starts the app on a clean install.

1. **`smoke.yaml`** opens the side menu, goes to Podcasts and checks that the
   four tabs show (Home, New, Library, Search). It proves that the build starts
   and that the first screens draw. It needs no network.
2. **`player-opens-once.yaml`** follows a public feed from the Search tab, plays
   its newest episode and waits for the mini player. It taps the mini player
   four times, 100 milliseconds apart, and checks that the player is open. One
   swipe down must close it, with nothing of the player left under it and the
   tabs showing. Then it opens and closes the player five more times, one tap
   and one swipe each. This is Mo's bug. On a build without the fix the extra
   taps stack extra copies of the page, so the page is still there after one
   swipe and the flow fails at "player-gone". On a build with the fix it passes.
3. **`player-tap-during-close.yaml`** opens the player, swipes it down fast and
   taps the mini player at once. The tap must not be lost and must not add a
   second copy: one player is open afterwards and one swipe closes it. Then the
   player must open once more, which a stuck native lock would stop. Maestro
   cannot choose the millisecond, so the tap may land just before or just after
   the slide ends. A pass shows the end state is right. It does not show that
   the race was hit.
4. **`scroll.yaml`** plays an episode on a show's page and scrolls the page down
   and up ten times, then checks that the mini player is still there and the
   player still opens. The recording shows a hang or a blank row. It does
   **not** measure smoothness.

The pieces the flows share are in `flows/lib/`. Maestro runs only the files at
the top of `flows/`.

## What the flows assume

- The Mac or runner has a network. The flows follow a public show from the
  Search tab by pasting its feed address (NPR's Planet Money,
  `https://feeds.npr.org/510289/podcast.xml`). Nothing private is used: no
  account, no key, nothing from Mo's library. To use another show, pass
  `--feed <address>`.
- The show has at least one episode with a working audio address. The flows play
  the **newest** one, whichever it is, so they do not need a title. On a feed
  with only a few episodes the scroll flow reaches the end of the list quickly.
- The phone language is English and the simulator has iOS 26 or newer (the mini
  player lives in iOS 26's tab bar).
- The app is the **Release** build for the simulator, which carries its own
  JavaScript. Its bundle id comes from `fork.config.ts`:
  `io.github.melba7.storytellerlofi`. A development build
  (`APP_VARIANT=development`) has `io.github.melba7.storytellerlofi.dev` and the
  name "Storyteller+ (dev)" and loads its JavaScript from a Metro server, so it
  is not used. `run.sh` reads the id from the app it is given.

## How the flows find the mini player and the player page

Milestone S1 gives the Podcasts screens three test ids: `podcasts-mini-player`,
`podcasts-player` and `podcasts-player-close`. Maestro reads a React Native
`testID` as the `id` of an element.

A build from before S1 has no ids, so each step also exists in a second form
that uses what the app already says out loud: the mini player's label "Open the
player, <title>, <time> left" (matched as `Open the player.*`) and the player's
close control "Close the player". The mode is the environment variable
`SELECTORS` (`ids` or `labels`). `run.sh --selectors auto`, the default, looks
for the id text inside the app's JavaScript and picks `ids` when it is there,
and `labels` when it is not. Labels work on both kinds of build. Each file in
`flows/lib/` holds both forms, behind `when: true: ${SELECTORS == 'ids'}` and
`${SELECTORS != 'ids'}`.

To prove the bug on the code before S1, build that code and run
`player-opens-once` with the default mode: it uses the labels by itself.

## Run it on Mo's Mac (the first choice)

The Mac builds a Release app in about 4 minutes once it has built it before. The
first build takes an estimated 20 to 40 minutes. A run of the four flows takes
an estimated 10 minutes more (not measured yet). It needs Xcode 26 or newer,
Node with corepack, CocoaPods and about 10 GB free.

1. Once: double-click `Install the UI check tools.command`. It installs Maestro
   (with Homebrew, which brings Java), downloads Apple's iOS simulator if the
   Mac has none, and lists anything else that is missing, with what to do about
   it. Run it again after you have done what it says.
2. Each time: double-click `Run the UI checks.command`. Choose "Build the app
   and check" (or "Use the last build" to check what you built last time). It
   prints what it is doing in plain words and opens the results folder at the
   end.

"Build the app" does what FORK.md's iOS Simulator section does: it installs the
app's dependencies (`yarn workspaces focus`), makes a fresh
`applications/mobile/ios` folder with `expo prebuild --clean` (the fork's store
identity, no `APP_VARIANT`), runs `pod install` and builds the Release app for
this Mac's chip into `~/Storyteller Lofi/ui-checks-build`, so the next build is
incremental. Its log is `build.log` in the results folder.

The first step of the build, `scripts/pre-install.mjs`, rewrites
`applications/mobile/package.json`: it drops the `@storyteller-platform/web`
devDependency and the final newline. So `run.sh` copies the file to
`package.json.before-build` in the results folder before the build and puts it
back when the script ends, whether the build worked or not (also after Ctrl-C).
`git status` shows nothing for it afterwards. If the Mac loses power or the
window is force-quit in the middle of a build, the file stays changed: put it
back with `git checkout applications/mobile/package.json`.

It saves everything in `~/Storyteller Lofi/logs/ui-checks-<time>/`, outside the
repository:

- `summary.txt`: which flows passed and which failed.
- `<flow>/<flow>.mov`: a recording of the simulator's screen during the flow. It
  is recorded also when the flow fails.
- `<flow>/maestro/`: Maestro's own files. The screenshots the flows take are in
  `takeScreenshot/`. For a failed step Maestro adds a `screenshots/` folder and
  the view hierarchy it saw (`screen-hierarchy/`).
- `<flow>/maestro-output.txt`: what Maestro printed. The step that failed is
  named there.
- `<flow>/debug/`: Maestro's log.

The auto mode on Mo's Mac refuses to run installs and fetch scripts, which is
why the install is a file to double-click. An agent can run `run.sh` but not the
installer.

`run.sh` can also be run in a terminal. Its options (`--app`, `--build`,
`--last-build`, `--simulator`, `--flows`, `--selectors`, `--feed`, `--results`,
`--keep-simulator`) are at the top of the file and in `run.sh --help`.

To run one flow by hand against a simulator that has the app installed:

```
maestro test -e APP_ID=io.github.melba7.storytellerlofi \
  -e SELECTORS=labels \
  -e FEED_URL=https://feeds.npr.org/510289/podcast.xml \
  tools/fork/ui-checks/flows/smoke.yaml
```

## Run it on GitHub (the second choice)

GitHub's Macs are often full for hours, so this is the fallback. Open the
repository's Actions tab, choose **UI checks**, click **Run workflow**, pick the
branch, and pick `macos-15-intel` under "macOS runner" when the default
`macos-26` does not get a runner. It runs only when started by hand, never on a
push, so it does not compete with Fork CI for Macs.

It follows Fork CI's iOS steps up to `pod install`, builds the Release app for
the simulator (unsigned, with Sentry's upload turned off), installs Maestro, and
calls `run.sh`. A run takes an estimated 40 to 60 minutes, nearly all of it the
build, and costs nothing because the repository is public. When it ends, the
recordings, screenshots and logs are in the run's artifact `ui-check-results`,
kept for 14 days, and the summary is on the run's page.

## What a simulator cannot show

- The on-device model and speech recognition. A Mac's model is not the phone's,
  and GitHub's Macs have none. Ad finding is checked on a Mac with the tools in
  `libraries/PodcastKit/Tools/mac`, and on the phone.
- Real scroll smoothness and heat. A simulator runs on a Mac's chip.
- The load of streaming and transcribing at once, which may be what delays the
  first tap on a phone.
- AirPods, the lock screen, calls and Siri.
- Anything that differs in a signed TestFlight build: signing, entitlements and
  the keychain (see below).

## If a check fails or does not run

- **"Element not found" at the mini player.** The mini player sits in the native
  tab bar and is mounted twice, so Maestro may not see it or may pick the hidden
  copy. Look at `screen-hierarchy/` of the failed step. If the id is missing,
  run once with `--selectors labels`. If the label is missing too, the accessory
  cannot be driven by Maestro: keep `smoke` and `scroll` and say so.
- **The search field does not take the address.** On iOS 26 the system search
  tab is expected to open with its field active. If it does not, the flow taps
  the field by its hint "Shows, episodes and words said". If neither works, the
  first fix is a longer wait or a tap on the field's own label in
  `flows/lib/follow-and-play.yaml`.
- **The app does not start on a simulator, or stops with a keychain error.** The
  simulator build is unsigned (`CODE_SIGNING_ALLOWED=NO`), like Fork CI's. If
  the keychain refuses an unsigned app, build with ad-hoc signing instead.
- **No sound on a runner.** A GitHub Mac has no sound device. The checks do not
  listen to anything. Whether an episode plays there is not what they test, but
  the mini player appears only once an episode is loaded.
- **A flow that waits for a long time and then fails** usually means the network
  or the feed was slow or the show page did not load. The recording shows it.

## Tests of this folder

`node --test 'tools/fork/ui-checks/*.test.mjs'` reads the flows as text and
checks that every command is one Maestro's documentation lists, that every
subflow that is called exists, that an id is one of the three above, that every
id step has its labels step, that the scripts are executable and have no syntax
error, and that the folder holds no audio, key or `.env` file. It also runs
`run.sh --build` in a made-up checkout with stand-ins for the build tools, and
checks that `package.json` is put back whether the build works or fails. It does
not run Maestro. Only a Mac can do that.

## What was checked against Maestro's documentation

Maestro CLI 2.11.0 (1 October 2026) and docs.maestro.dev on 18 November 2026:
installing (`curl -fsSL "https://get.maestro.mobile.dev" | bash`, or Homebrew's
`mobile-dev-inc/tap/maestro`, and Java 17 or newer), iOS simulators ("any iOS
Simulator managed by Xcode"; a physical iPhone is not supported), and the
commands `launchApp` (with `clearState`), `tapOn` (with `id`, `text`, `enabled`,
`repeat`, `delay`, `optional`), `inputText`, `swipe` (with `from`, `direction`,
`start`, `end`, `duration`, `waitToSettleTimeoutMs`), `assertVisible`,
`assertNotVisible`, `extendedWaitUntil`, `repeat`, `runFlow` (with `file`,
`commands`, `when`), `takeScreenshot`, and the `maestro test` options `-e`,
`--test-output-dir` and `--debug-output`. Maestro's `startRecording` is not
used: its page does not say it works on iOS, so `run.sh` records the screen with
`xcrun simctl io recordVideo`.
