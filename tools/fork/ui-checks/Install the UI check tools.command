#!/bin/bash
# Double-click in Finder, once. Gets this Mac ready for "Run the UI checks.command": it installs
# Maestro (the tool that taps and swipes in the iPhone simulator) and checks the other things the
# checks need: Xcode 26, an iPhone simulator with iOS 26, Java 17 for Maestro, and the tools that
# build the app. It says in plain words what is missing and what to do. It downloads Maestro, and
# Apple's iOS simulator if this Mac has none (several GB, once). See README.md in this folder.
MAESTRO_VERSION="2.11.0"
export PATH="$HOME/.maestro/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
PROBLEMS=0

finish() {
  echo
  read -r -p "$1 Press Return to close this window. " _
  exit "${2:-0}"
}

problem() {
  echo "  MISSING: $1"
  PROBLEMS=$((PROBLEMS + 1))
}

echo "Storyteller Lofi: install the UI check tools"
echo

echo "Xcode"
if command -v xcrun > /dev/null && xcodebuild -version > /dev/null 2>&1; then
  echo "  $(xcodebuild -version | head -n 1)"
else
  problem "Xcode. Install Xcode 26 from the App Store, open it once to accept the licence, then double-click this again."
  finish "Stopping here, because the rest needs Xcode." 1
fi

echo "iPhone simulator with iOS 26"
if xcrun simctl list runtimes available 2> /dev/null | grep -Eq '^iOS (2[6-9]|[3-9][0-9])'; then
  echo "  found"
else
  echo "  Not found. Downloading Apple's iOS simulator now (several GB, once). This can take a while."
  if xcodebuild -downloadPlatform iOS && xcrun simctl list runtimes available 2> /dev/null | grep -Eq '^iOS (2[6-9]|[3-9][0-9])'; then
    echo "  done"
  else
    problem "an iOS 26 simulator. Open Xcode, then Settings, Platforms (or Components), and download iOS 26. Then double-click this again."
  fi
fi

echo "Maestro"
if command -v maestro > /dev/null && maestro --help > /dev/null 2>&1; then
  echo "  already installed: $(maestro --version 2> /dev/null | tail -n 1)"
else
  if command -v brew > /dev/null; then
    # Homebrew's Maestro brings its own Java. The three lines are the ones on docs.maestro.dev; a
    # Homebrew that is too old for "brew trust" skips that one.
    echo "  Installing Maestro with Homebrew..."
    brew tap mobile-dev-inc/tap
    brew trust --formula mobile-dev-inc/tap/maestro 2> /dev/null
    brew install mobile-dev-inc/tap/maestro
  elif /usr/libexec/java_home -v 17+ > /dev/null 2>&1; then
    echo "  Installing Maestro $MAESTRO_VERSION..."
    curl -fsSL "https://get.maestro.mobile.dev" | MAESTRO_VERSION="$MAESTRO_VERSION" bash
  else
    problem "Java 17 or newer, which Maestro runs on. Install \"Temurin 17\" (a .pkg) from https://adoptium.net, then double-click this again. (Or install Homebrew from https://brew.sh first: this then installs Java by itself.)"
  fi
  if command -v maestro > /dev/null && maestro --help > /dev/null 2>&1; then
    echo "  installed: $(maestro --version 2> /dev/null | tail -n 1)"
  else
    problem "Maestro did not install (see above)."
  fi
fi

echo "Tools that build the app (only needed when the checks build it)"
for tool in node yarn pod cmake pkg-config; do
  if command -v "$tool" > /dev/null; then
    echo "  $tool: found"
  else
    case "$tool" in
      node) fix="install Node 24 from https://nodejs.org" ;;
      yarn) fix="run: corepack enable" ;;
      pod) fix="run: brew install cocoapods" ;;
      *) fix="run: brew install $tool" ;;
    esac
    problem "$tool. To fix it, $fix."
  fi
done

echo
if [ "$PROBLEMS" -eq 0 ]; then
  finish "Everything is ready. Now double-click \"Run the UI checks.command\"." 0
else
  finish "$PROBLEMS thing(s) are missing (listed above). Do what each line says, then double-click this again." 1
fi
