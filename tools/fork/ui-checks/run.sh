#!/bin/bash
# Runs the simulator checks (the Maestro flows in flows/) against a built Storyteller+ app for the
# iOS Simulator. It boots a simulator, installs the app, runs each flow, and saves the results
# (Maestro's screenshots, a screen recording of each flow, Maestro's logs and a summary) in
# ~/Storyteller Lofi/logs/ui-checks-<time>/, outside the repository. See README.md.
#
# Usage: tools/fork/ui-checks/run.sh [options]
#   --app PATH          a built simulator app (a folder ending in .app)
#   --build             build the Release app for the simulator first (about 4 minutes on a Mac
#                       that has built it before), then check it
#   --last-build        check the app that the last --build made
#   --simulator NAME    the simulator's name, for example "iPhone 17 Pro" (default: the best
#                       iPhone with iOS 26 or newer)
#   --flows "a b"       which flows to run (default: all four, in this order)
#   --selectors MODE    auto (default), ids or labels: how the flows find the mini player and the
#                       player page. auto uses the test ids when the app has them.
#   --feed URL          the public podcast feed the flows follow
#   --results DIR       where to save the results
#   --keep-simulator    leave the simulator running when done
# Exit code: 0 every flow passed, 1 a flow failed, 2 the checks could not run.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
LOGS="$HOME/Storyteller Lofi/logs"
BUILD_DIR="$HOME/Storyteller Lofi/ui-checks-build"
# The tools the installer puts in these places are not always on the PATH of a new window.
export PATH="$HOME/.maestro/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

ALL_FLOWS="smoke player-opens-once player-tap-during-close scroll"
# A public show (NPR's Planet Money). Its newest episode is played, whatever it is.
DEFAULT_FEED="https://feeds.npr.org/510289/podcast.xml"

APP=""
BUILD=0
LAST=0
SIM_NAME=""
FLOWS="$ALL_FLOWS"
SELECTORS="auto"
FEED="$DEFAULT_FEED"
RESULTS=""
KEEP=0

say() { printf '%s\n' "$*"; }
stop() { # message, exit code
  say ""
  say "$1"
  exit "${2:-2}"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --app) APP="${2:-}"; shift 2 ;;
    --build) BUILD=1; shift ;;
    --last-build) LAST=1; shift ;;
    --simulator) SIM_NAME="${2:-}"; shift 2 ;;
    --flows) FLOWS="${2:-}"; shift 2 ;;
    --selectors) SELECTORS="${2:-}"; shift 2 ;;
    --feed) FEED="${2:-}"; shift 2 ;;
    --results) RESULTS="${2:-}"; shift 2 ;;
    --keep-simulator) KEEP=1; shift ;;
    -h | --help) sed -n '2,/^set -u/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) stop "I do not know the option $1. Run it with --help to see the options." 2 ;;
  esac
done

case "$SELECTORS" in
  auto | ids | labels) ;;
  *) stop "--selectors must be auto, ids or labels." 2 ;;
esac
[ -n "$FLOWS" ] || FLOWS="$ALL_FLOWS"
for name in $FLOWS; do
  case " $ALL_FLOWS " in
    *" $name "*) ;;
    *) stop "There is no flow called $name. The flows are: $ALL_FLOWS." 2 ;;
  esac
done
case "$FEED" in
  http://* | https://*) ;;
  *) stop "--feed must be a web address that starts with http:// or https://." 2 ;;
esac

# --- Tools --------------------------------------------------------------------------------
INSTALL="double-click \"Install the UI check tools.command\" in tools/fork/ui-checks"
command -v xcrun > /dev/null || stop "Xcode's command line tools are missing. Install Xcode 26 from the App Store, then $INSTALL." 2
command -v maestro > /dev/null || stop "Maestro is not installed yet. Please $INSTALL. It installs it once." 2
# --help starts Maestro's Java program, so this also finds a missing or too old Java.
maestro --help > /dev/null 2>&1 || stop "Maestro is installed but does not start. It needs Java 17 or newer. Please $INSTALL." 2

# --- Where the results go -----------------------------------------------------------------
[ -n "$RESULTS" ] || RESULTS="$LOGS/ui-checks-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$RESULTS" || stop "Could not make the folder $RESULTS." 2
SUMMARY="$RESULTS/summary.txt"
: > "$SUMMARY"
note() { # a line for the screen and the summary file
  say "$*"
  say "$*" >> "$SUMMARY"
}

# --- Simulator ----------------------------------------------------------------------------
# Prints the id of the simulator called $1 (or, with no name, the newest iPhone) among those with
# iOS 26 or newer, because the mini player lives in iOS 26's tab bar.
find_simulator() {
  xcrun simctl list devices available | awk -v want="$1" '
    /^-- iOS / { split($3, v, "."); ok = (v[1] + 0 >= 26); next }
    /^-- / { ok = 0; next }
    ok {
      line = $0
      sub(/^ +/, "", line)
      sub(/ \([A-Za-z ]+\)$/, "", line)
      n = match(line, / \([0-9A-Fa-f-]+\)$/)
      if (n == 0) next
      name = substr(line, 1, n - 1)
      id = substr(line, n + 2, RLENGTH - 3)
      if (want != "") {
        if (name == want) best = id
        next
      }
      # The newest runtime is listed last, so a later one of the same rank wins.
      rank = 0
      if (name == "iPhone 17 Pro") rank = 4
      else if (name == "iPhone 16 Pro") rank = 3
      else if (name ~ /^iPhone [0-9]+( Pro)?$/) rank = 2
      else if (name ~ /^iPhone/) rank = 1
      if (rank > 0 && rank >= bestrank) { bestrank = rank; best = id }
    }
    END { if (best != "") print best }'
}

UDID="$(find_simulator "$SIM_NAME")"
if [ -z "$UDID" ]; then
  if [ -n "$SIM_NAME" ]; then
    stop "There is no simulator called \"$SIM_NAME\" with iOS 26 or newer. See the list with: xcrun simctl list devices available" 2
  fi
  stop "This Mac has no iPhone simulator with iOS 26 or newer. Please $INSTALL. It downloads Apple's iOS simulator once." 2
fi
SIM_LABEL="$(xcrun simctl list devices available | grep "$UDID" | head -n 1 | sed 's/^ *//; s/ ([0-9A-Fa-f-]*).*$//')"

# --- The app ------------------------------------------------------------------------------
# The build's first step (pre-install.mjs) rewrites applications/mobile/package.json in place: it
# drops the web devDependency and the final newline. The file is copied to the results folder
# before the build and put back when the script ends, whether the build worked or not (an EXIT
# trap also runs after Ctrl-C), so a checkout is not left changed.
MANIFEST=""
MANIFEST_COPY=""
# shellcheck disable=SC2329  # It is called by the EXIT trap that build_app sets.
restore_manifest() {
  [ -n "$MANIFEST_COPY" ] && [ -f "$MANIFEST_COPY" ] && cp -p "$MANIFEST_COPY" "$MANIFEST"
  return 0
}

build_app() {
  say "Building the Release app for the simulator. The log is $RESULTS/build.log."
  say "The first build takes longer (20 to 40 minutes); a later one takes about 4 minutes."
  local mobile="$REPO/applications/mobile"
  MANIFEST="$mobile/package.json"
  MANIFEST_COPY="$RESULTS/package.json.before-build"
  cp -p "$MANIFEST" "$MANIFEST_COPY" || stop "Could not save a copy of $MANIFEST before the build." 2
  trap restore_manifest EXIT
  (
    set -e
    cd "$REPO"
    command -v node > /dev/null || { say "Node is missing. Install Node 24 from nodejs.org."; exit 1; }
    corepack enable > /dev/null 2>&1 || true
    command -v yarn > /dev/null || { say "Yarn is missing. Run: corepack enable"; exit 1; }
    command -v pod > /dev/null || { say "CocoaPods is missing. Run: brew install cocoapods"; exit 1; }
    export HOMEBREW_NO_AUTO_UPDATE=1 EXPO_IMAGE_UTILS_NO_SHARP=1 SENTRY_DISABLE_AUTO_UPLOAD=true
    (cd "$mobile" && ./scripts/pre-install.mjs)
    yarn workspaces focus @storyteller-platform/mobile
    # Without APP_VARIANT the app gets the fork's store identity (see fork.config.ts). A
    # development build would not carry its own JavaScript.
    (cd "$mobile" && unset APP_VARIANT && CI=1 yarn expo prebuild --clean --no-install -p ios)
    ruby tools/fork/prefetch-sentry-xcframework.rb applications/mobile
    (cd "$mobile/ios" && pod install)
    cd "$mobile/ios"
    workspace="$(ls -d ./*.xcworkspace | head -n 1)"
    scheme="$(basename "$workspace" .xcworkspace)"
    # The same build as the TestFlight workflow's archive and Fork CI's simulator build, but
    # Release for the simulator, for this Mac's own chip only. Release carries its JavaScript.
    xcodebuild -workspace "$workspace" -scheme "$scheme" \
      -configuration Release -sdk iphonesimulator \
      -destination 'generic/platform=iOS Simulator' \
      -derivedDataPath "$BUILD_DIR" ARCHS="$(uname -m)" ONLY_ACTIVE_ARCH=NO \
      CODE_SIGNING_ALLOWED=NO COMPILER_INDEX_STORE_ENABLE=NO build
  ) > "$RESULTS/build.log" 2>&1
  local status=$?
  if [ $status -ne 0 ]; then
    say ""
    tail -n 40 "$RESULTS/build.log"
    stop "The build did not work. The end of its log is above; the whole log is $RESULTS/build.log." 2
  fi
}

last_build() {
  ls -d "$BUILD_DIR"/Build/Products/Release-iphonesimulator/*.app 2> /dev/null | head -n 1
}

if [ "$BUILD" -eq 1 ]; then
  build_app
  APP="$(last_build)"
elif [ "$LAST" -eq 1 ]; then
  APP="$(last_build)"
  [ -n "$APP" ] || stop "There is no earlier build to check. Build one first (--build)." 2
fi
[ -n "$APP" ] || stop "Say which app to check: --app PATH, --build or --last-build." 2
[ -f "$APP/Info.plist" ] || stop "$APP is not a built app (it has no Info.plist)." 2
APP_ID="$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP/Info.plist" 2> /dev/null)"
[ -n "$APP_ID" ] || stop "Could not read the app's bundle id from $APP/Info.plist." 2

# auto: use the test ids when the app has them. A build from before milestone S1 has none, and the
# flows then find the mini player and the player page by their spoken labels, which every build
# has. A miss here is safe: the labels work on both.
if [ "$SELECTORS" = "auto" ]; then
  if grep -aq "podcasts-mini-player" "$APP/main.jsbundle" 2> /dev/null; then
    SELECTORS="ids"
  else
    SELECTORS="labels"
  fi
  note "Selectors: $SELECTORS (chosen by looking for the test ids in the app)"
else
  note "Selectors: $SELECTORS"
fi

# --- Boot and install ---------------------------------------------------------------------
note "App: $APP ($APP_ID)"
note "Simulator: $SIM_LABEL ($UDID)"
note "Feed: $FEED"
say "Starting the simulator..."
# A simulator that was already running is left running at the end.
if xcrun simctl list devices | grep "$UDID" | grep -q "(Booted)"; then KEEP=1; fi
xcrun simctl bootstatus "$UDID" -b > /dev/null 2>&1 || stop "The simulator would not start. Open the Simulator app once and try again." 2
if [ -z "${CI:-}" ]; then
  open -a Simulator --args -CurrentDeviceUDID "$UDID" > /dev/null 2>&1 || true
fi
say "Installing the app..."
xcrun simctl install "$UDID" "$APP" || stop "The simulator would not take the app." 2

# --- Run the flows ------------------------------------------------------------------------
export MAESTRO_CLI_NO_ANALYTICS=true MAESTRO_CLI_ANALYSIS_NOTIFICATION_DISABLED=true
export MAESTRO_DISABLE_UPDATE_CHECK=true MAESTRO_DRIVER_STARTUP_TIMEOUT=120000

# Ends a screen recording the way its tool wants (Ctrl-C), so the file is finished. If the
# recorder has not ended after 10 seconds it is killed, so a stuck recorder cannot stop the run.
stop_recorder() {
  local waited=0
  kill -INT "$1" 2> /dev/null
  while kill -0 "$1" 2> /dev/null && [ "$waited" -lt 50 ]; do
    sleep 0.2
    waited=$((waited + 1))
  done
  kill -0 "$1" 2> /dev/null && kill -KILL "$1" 2> /dev/null
  wait "$1" 2> /dev/null
  return 0
}

PASSED=""
FAILED=""
for name in $FLOWS; do
  DIR="$RESULTS/$name"
  mkdir -p "$DIR"
  say ""
  say "=== $name ==="
  # Maestro's own recording command is not documented for iOS, so the simulator records the
  # screen of every flow, also when the flow fails.
  xcrun simctl io "$UDID" recordVideo --codec=h264 --force "$DIR/$name.mov" > /dev/null 2>&1 &
  RECORDER=$!
  # The recorder needs a moment before it takes Ctrl-C.
  sleep 2
  maestro --device "$UDID" test \
    -e APP_ID="$APP_ID" -e SELECTORS="$SELECTORS" -e FEED_URL="$FEED" \
    --test-output-dir "$DIR/maestro" --debug-output "$DIR/debug" \
    "$HERE/flows/$name.yaml" 2>&1 | tee "$DIR/maestro-output.txt"
  STATUS=${PIPESTATUS[0]}
  stop_recorder "$RECORDER"
  if [ "$STATUS" -eq 0 ]; then
    PASSED="$PASSED $name"
    note "PASSED  $name"
  else
    FAILED="$FAILED $name"
    note "FAILED  $name (see $DIR)"
  fi
done

[ "$KEEP" -eq 1 ] || xcrun simctl shutdown "$UDID" > /dev/null 2>&1

# --- Summary ------------------------------------------------------------------------------
say ""
note "Results are in: $RESULTS"
if [ -n "$FAILED" ]; then
  note "Not every flow passed:$FAILED"
  [ -z "${CI:-}" ] && open "$RESULTS" > /dev/null 2>&1
  exit 1
fi
note "Every flow passed:$PASSED"
[ -z "${CI:-}" ] && open "$RESULTS" > /dev/null 2>&1
exit 0
