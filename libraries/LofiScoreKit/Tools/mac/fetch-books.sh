#!/bin/bash
# Downloads newly synced read-aloud books from your Storyteller server into
# "~/Storyteller Lofi/Books", where lofi-sync.sh and "Score atmosphere.command"
# score them. Books already downloaded are skipped; a book whose read-aloud
# EPUB the server has re-made (its text may have changed) is downloaded again
# and its old tracks are set aside, so it is scored afresh.
#
# Needs "~/Storyteller Lofi/server.json":
#   {"url": "https://storyteller.example.net", "username": "mo"}
# and the password in the login keychain, which install-automatic-scoring.command
# puts there (or: security add-generic-password -U -s "Storyteller Lofi server" -a USERNAME -w).
# The password is never printed and never written to disk.
#
# Prints one line per book downloaded, "<uuid><tab><file>", and keeps
# "Books/.synced.json" (uuid, file, the server's readaloud date). Exit 3 when
# there is no server.json, so callers can tell "not set up" from a failure.
set -uo pipefail

ROOT="$HOME/Storyteller Lofi"
CONFIG="$ROOT/server.json"
BOOKS="$ROOT/Books"
TRACKS="$ROOT/tracks"
STATE="$BOOKS/.synced.json"
KEYCHAIN_SERVICE="Storyteller Lofi server"

[ -f "$CONFIG" ] || exit 3
command -v curl > /dev/null || { echo "curl is missing"; exit 1; }
mkdir -p "$BOOKS" "$TRACKS"

read -r URL USERNAME < <(python3 -I - "$CONFIG" <<'PY'
import json, sys
c = json.load(open(sys.argv[1]))
url = c.get("url", "").rstrip("/")
user = c.get("username", "")
if not url or not user:
    sys.exit(1)
print(url, user)
PY
) || { echo "server.json needs \"url\" and \"username\""; exit 1; }

PASSWORD="$(security find-generic-password -s "$KEYCHAIN_SERVICE" -a "$USERNAME" -w 2>/dev/null)" \
  || { echo "No password for $USERNAME in the keychain. Double-click install-automatic-scoring.command to set it."; exit 1; }

# The token request's form goes in through stdin (curl's config format, with
# quotes and backslashes escaped), so the password is never a command-line argument.
QUOTED="${PASSWORD//\\/\\\\}"
QUOTED="${QUOTED//\"/\\\"}"
TOKEN="$(curl -sS -f -K - "$URL/api/v2/token" <<EOF2 | python3 -I -c 'import json, sys; print(json.load(sys.stdin)["access_token"])'
request = "POST"
form-string = "usernameOrEmail=$USERNAME"
form-string = "password=$QUOTED"
EOF2
)" || { echo "Could not sign in to $URL as $USERNAME"; exit 1; }
unset PASSWORD QUOTED

LIST="$(curl -sS -f -H "Authorization: Bearer $TOKEN" "$URL/api/v2/books?mediaFilter=synced")" \
  || { echo "Could not list the books on $URL"; exit 1; }

# Which books are new or re-made, as "<uuid><tab><safe title><tab><readaloud date>".
TODO="$(LIST="$LIST" python3 -I - "$STATE" <<'PY'
import json, os, re, sys
books = json.loads(os.environ["LIST"])
state_path = sys.argv[1]
try:
    state = json.load(open(state_path))
except Exception:
    state = {}
for book in books:
    ra = book.get("readaloud")
    if not ra or ra.get("missing"):
        continue
    uuid = book["uuid"]
    date = ra.get("updatedAt") or ""
    known = state.get(uuid)
    if known and known.get("updatedAt") == date and os.path.exists(os.path.join(os.path.dirname(state_path), known.get("file", ""))):
        continue
    title = book.get("title") or uuid
    safe = re.sub(r"[/:\\\x00-\x1f]", "_", title).strip().strip(".") or uuid
    print(f"{uuid}\t{safe}\t{date}")
PY
)"
[ -n "$TODO" ] || exit 0

while IFS=$'\t' read -r uuid safe date; do
  [ -n "$uuid" ] || continue
  file="$safe.epub"
  tmp="$BOOKS/.$safe.epub.part"
  if ! curl -sS -f -L -H "Authorization: Bearer $TOKEN" -o "$tmp" "$URL/api/v2/books/$uuid/files?format=readaloud"; then
    echo "Could not download $safe" >&2
    rm -f "$tmp"
    continue
  fi
  # A book downloaded before but re-made since: its old tracks no longer match
  # its text. They go to tracks/stale, and the unpacked copy is removed.
  if [ -f "$BOOKS/$file" ]; then
    stamp="$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$TRACKS/stale/$stamp"
    for old in "$TRACKS/$safe".*.json; do
      [ -f "$old" ] && mv "$old" "$TRACKS/stale/$stamp/"
    done
    rm -rf "$TRACKS/books/$safe"
  fi
  mv -f "$tmp" "$BOOKS/$file"
  python3 -I - "$STATE" "$uuid" "$file" "$date" <<'PY'
import json, sys
path, uuid, file, date = sys.argv[1:5]
try:
    state = json.load(open(path))
except Exception:
    state = {}
state[uuid] = {"file": file, "updatedAt": date}
json.dump(state, open(path, "w"), indent=1, sort_keys=True)
PY
  printf '%s\t%s\n' "$uuid" "$file"
done <<< "$TODO"
