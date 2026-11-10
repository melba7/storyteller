#!/bin/bash
# Double-click in Finder. Sets the Mac up to score books by itself, so adding
# atmosphere sounds to a book is as easy as syncing it in Storyteller:
#
#   - a copy of the fork's tools in "~/Storyteller Lofi/scoring-tools", built once;
#   - your Storyteller server's address and login (optional: without it, books
#     are scored when you drop their read-aloud EPUBs into "~/Storyteller Lofi/Books");
#   - a launchd job that runs Tools/mac/lofi-sync.sh when a book lands in Books/
#     and every half hour: it fetches newly synced books, scores them through your
#     Claude plan (capped per book), copies the results into LofiMusic (the
#     folder the phone follows; the name is from when it held the music) and its
#     iCloud copy (the phone's linked sounds folder picks them up), and puts each
#     score inside its book on the server.
#
# Run it again to change the login or update the tools. stop-automatic-scoring.command
# turns the job off. Logs: "~/Storyteller Lofi/logs". Nothing here touches the
# Freesound or Anthropic key files.
ROOT="$HOME/Storyteller Lofi"
TOOLS="$ROOT/scoring-tools"
REPO="https://github.com/melba7/storyteller.git"
LABEL="com.storyteller-lofi.sync"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
KEYCHAIN_SERVICE="Storyteller Lofi server"
PATH="$PATH:/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$HOME/.claude/local"

finish() {
  echo
  read -r -p "$1 Press Return to close this window. " _
  exit "${2:-0}"
}

# The branch this copy of the installer came from, when it is inside a checkout.
HERE="$(cd "$(dirname "$0")" && pwd)"
BRANCH="feat/lofi-app"
if git -C "$HERE" rev-parse --is-inside-work-tree > /dev/null 2>&1; then
  found="$(git -C "$HERE" rev-parse --abbrev-ref HEAD 2>/dev/null)"
  [ -n "$found" ] && [ "$found" != HEAD ] && BRANCH="$found"
fi

echo "Storyteller Lofi: automatic scoring"
echo
command -v claude > /dev/null || finish "Claude Code isn't installed in Terminal. Install it, run 'claude' once and sign in, then double-click this again." 1
command -v swift > /dev/null || finish "Xcode's command line tools are missing (xcode-select --install)." 1
mkdir -p "$ROOT/Books" "$ROOT/logs" "$HOME/Library/LaunchAgents"

# 1. The tools.
if [ -d "$TOOLS/.git" ]; then
  echo "Updating the tools in $TOOLS ($BRANCH)..."
  git -C "$TOOLS" fetch --quiet origin "$BRANCH" && git -C "$TOOLS" checkout --quiet "$BRANCH" && git -C "$TOOLS" pull --ff-only --quiet || echo "(could not update; using the tools as they are)"
else
  echo "Fetching the tools into $TOOLS ($BRANCH)..."
  git clone --quiet --branch "$BRANCH" "$REPO" "$TOOLS" || finish "Could not fetch the tools." 1
fi
echo "Building the scoring tools (a few minutes the first time)..."
(cd "$TOOLS/libraries/LofiScoreKit" && swift build -c release --product lofi-eval > "$ROOT/logs/build.log" 2>&1 && swift build -c release --product lofi-atmosphere >> "$ROOT/logs/build.log" 2>&1) \
  || finish "The build failed; see $ROOT/logs/build.log." 1

# 2. The server login (optional).
echo
current_url=""
current_user=""
if [ -f "$ROOT/server.json" ]; then
  read -r current_url current_user < <(python3 -I -c 'import json,sys; c=json.load(open(sys.argv[1])); print(c.get("url",""), c.get("username",""))' "$ROOT/server.json")
  echo "Storyteller server: $current_url as $current_user (press Return to keep)"
else
  echo "Your Storyteller server fetches newly synced books by itself. Leave the address empty to skip this"
  echo "and score the read-aloud EPUBs you put into $ROOT/Books instead."
fi
read -r -p "Server address (like https://storyteller.example.net): " url
url="${url:-$current_url}"
if [ -n "$url" ]; then
  read -r -p "Username or email: " user
  user="${user:-$current_user}"
  if [ -n "$user" ]; then
    read -r -s -p "Password (kept in your login keychain, never in a file): " password
    echo
    if [ -n "$password" ]; then
      security add-generic-password -U -s "$KEYCHAIN_SERVICE" -a "$user" -w "$password" || finish "Could not save the password in the keychain." 1
    fi
    unset password
    python3 -I -c 'import json,sys; json.dump({"url": sys.argv[1].rstrip("/"), "username": sys.argv[2]}, open(sys.argv[3], "w"), indent=1)' "$url" "$user" "$ROOT/server.json"
    echo "Checking the login..."
    if "$TOOLS/libraries/LofiScoreKit/Tools/mac/fetch-books.sh" > /dev/null 2>&1; then
      echo "Signed in. Newly synced books will be fetched from $url."
    else
      echo "Could not sign in to $url as $user. Check the address and password; run this again to change them."
    fi
  fi
fi

# 3. The launchd job.
cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>$TOOLS/libraries/LofiScoreKit/Tools/mac/lofi-sync.sh</string>
  </array>
  <key>WatchPaths</key>
  <array><string>$ROOT/Books</string></array>
  <key>StartInterval</key><integer>1800</integer>
  <key>RunAtLoad</key><true/>
  <key>ThrottleInterval</key><integer>120</integer>
  <key>LowPriorityIO</key><true/>
  <key>Nice</key><integer>5</integer>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key><string>/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$HOME/.claude/local</string>
    <key>HOME</key><string>$HOME</string>
  </dict>
  <key>StandardOutPath</key><string>$ROOT/logs/lofi-sync.log</string>
  <key>StandardErrorPath</key><string>$ROOT/logs/lofi-sync.log</string>
</dict>
</plist>
PLIST
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null
launchctl bootstrap "gui/$(id -u)" "$PLIST" || finish "Could not start the job (launchctl)." 1
echo
echo "Automatic scoring is on. It runs now, when a book lands in $ROOT/Books, and every half hour."
echo "Progress: $ROOT/logs/lofi-sync.log. On the phone, pick the LofiMusic folder in iCloud Drive once"
echo "(Settings > Atmosphere Sounds > Import a sounds folder); from then on new scores and sounds arrive by themselves."
finish "Done."
