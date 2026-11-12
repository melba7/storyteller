#!/bin/bash
# Downloads newly synced read-aloud books from your Storyteller server into
# "~/Storyteller Lofi/Books", where lofi-sync.sh and "Score atmosphere.command"
# score them. Books already downloaded are skipped; a book whose read-aloud
# EPUB the server has re-made (its text may have changed) is downloaded again
# and its old tracks are set aside, so it is scored afresh.
#
# Needs "~/Storyteller Lofi/server.json":
#   {"url": "https://storyteller.example.net", "username": "mo", "since": "2026-11-12T01:00:00Z"}
# and the password in the login keychain, which install-automatic-scoring.command
# puts there (or: security add-generic-password -U -s "Storyteller Lofi server" -a USERNAME -w).
# The password is never printed and never written to disk.
#
# "since" (optional, UTC) limits the fetch to books whose read-aloud version was
# made from that moment on, so the books already on the server are left alone.
# Older books to score anyway go in "Books/wanted.txt", one per line: part of
# the title is enough, case doesn't matter, lines starting with # are ignored.
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

read -r URL USERNAME SINCE < <(python3 -I - "$CONFIG" <<'PY'
import json, sys
c = json.load(open(sys.argv[1]))
url = c.get("url", "").rstrip("/")
user = c.get("username", "")
if not url or not user:
    sys.exit(1)
print(url, user, str(c.get("since", "") or "").strip())
PY
) || { echo "server.json needs \"url\" and \"username\""; exit 1; }
SINCE="${SINCE:-}"

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
# With "since", a book not downloaded before is taken only when its read-aloud
# version was made from then on, or its title is listed in Books/wanted.txt.
TODO="$(LIST="$LIST" SINCE="$SINCE" python3 -I - "$STATE" <<'PY'
import json, os, re, sys
books = json.loads(os.environ["LIST"])
state_path = sys.argv[1]
books_dir = os.path.dirname(state_path)
try:
    state = json.load(open(state_path))
except Exception:
    state = {}
wanted = []
try:
    with open(os.path.join(books_dir, "wanted.txt"), encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#"):
                wanted.append(line.casefold())
except OSError:
    pass

def stamp(value):
    # "2026-11-10 21:16:00" and "2026-11-10T21:16:00.000Z" both become
    # "2026-11-10T21:16:00" (the server's dates are UTC), so they compare as text.
    return str(value or "").strip().replace(" ", "T")[:19]

since = stamp(os.environ.get("SINCE", ""))
for book in books:
    ra = book.get("readaloud")
    if not ra or ra.get("missing"):
        continue
    uuid = book["uuid"]
    date = ra.get("updatedAt") or ""
    title = book.get("title") or uuid
    known = state.get(uuid)
    if known and known.get("updatedAt") == date and os.path.exists(os.path.join(books_dir, known.get("file", ""))):
        continue
    if not known and since:
        listed = any(w in title.casefold() for w in wanted)
        if not listed and stamp(ra.get("createdAt") or date) < since:
            continue
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
