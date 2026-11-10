#!/bin/bash
# Puts each finished score inside its book on the Storyteller server, when the
# server is the fork's (it answers PUT /api/v2/books/<id>/lofi-score). The
# phone then gets the score with the book, as the atmosphere's own "sync". A server without the route answers 404 and is left alone.
#
# Uses "~/Storyteller Lofi/server.json" and the keychain like fetch-books.sh,
# and "Books/.synced.json" to know which file is which book. Scores already
# sent are remembered in "tracks/.pushed.json" by their size and date.
set -uo pipefail

ROOT="$HOME/Storyteller Lofi"
CONFIG="$ROOT/server.json"
BOOKS="$ROOT/Books"
TRACKS="$ROOT/tracks"
STATE="$BOOKS/.synced.json"
PUSHED="$TRACKS/.pushed.json"
KEYCHAIN_SERVICE="Storyteller Lofi server"

[ -f "$CONFIG" ] && [ -f "$STATE" ] || exit 0
read -r URL USERNAME < <(python3 -I - "$CONFIG" <<'PY'
import json, sys
c = json.load(open(sys.argv[1]))
print(c.get("url", "").rstrip("/"), c.get("username", ""))
PY
)
[ -n "$URL" ] && [ -n "$USERNAME" ] || exit 0

# "<uuid><tab><score file>" for every score not sent in this form yet.
TODO="$(python3 -I - "$STATE" "$PUSHED" "$TRACKS" <<'PY'
import json, os, sys
state_path, pushed_path, tracks = sys.argv[1:4]
state = json.load(open(state_path))
try:
    pushed = json.load(open(pushed_path))
except Exception:
    pushed = {}
for uuid, entry in state.items():
    name = entry.get("file", "")
    if name.endswith(".epub"):
        name = name[:-5]
    score = os.path.join(tracks, name + ".score.json")
    if not os.path.isfile(score):
        continue
    st = os.stat(score)
    stamp = f"{st.st_size}:{int(st.st_mtime)}"
    if pushed.get(uuid) == stamp:
        continue
    print(f"{uuid}\t{score}")
PY
)"
[ -n "$TODO" ] || exit 0

PASSWORD="$(security find-generic-password -s "$KEYCHAIN_SERVICE" -a "$USERNAME" -w 2>/dev/null)" || { echo "no password in the keychain for $USERNAME"; exit 1; }
QUOTED="${PASSWORD//\\/\\\\}"
QUOTED="${QUOTED//\"/\\\"}"
TOKEN="$(curl -sS -f -K - "$URL/api/v2/token" <<EOF2 | python3 -I -c 'import json, sys; print(json.load(sys.stdin)["access_token"])'
request = "POST"
form-string = "usernameOrEmail=$USERNAME"
form-string = "password=$QUOTED"
EOF2
)" || { echo "could not sign in to $URL"; exit 1; }
unset PASSWORD QUOTED

sent=0
while IFS=$'\t' read -r uuid score; do
  [ -n "$uuid" ] || continue
  code="$(curl -sS -o /dev/null -w '%{http_code}' -X PUT -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" --data-binary "@$score" "$URL/api/v2/books/$uuid/lofi-score")"
  case "$code" in
    200|201|204)
      python3 -I - "$PUSHED" "$uuid" "$score" <<'PY'
import json, os, sys
path, uuid, score = sys.argv[1:4]
try:
    pushed = json.load(open(path))
except Exception:
    pushed = {}
st = os.stat(score)
pushed[uuid] = f"{st.st_size}:{int(st.st_mtime)}"
json.dump(pushed, open(path, "w"), indent=1, sort_keys=True)
PY
      sent=$((sent + 1))
      echo "score sent to the server for $(basename "$score" .score.json)" ;;
    404|405)
      echo "the server has no lofi-score route (not the fork's server); scores stay in the sounds folder only"
      break ;;
    *)
      echo "could not send the score for $(basename "$score" .score.json): HTTP $code" ;;
  esac
done <<< "$TODO"
[ "$sent" -gt 0 ] && echo "$sent score(s) now inside their books on the server"
exit 0
