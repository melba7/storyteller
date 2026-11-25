"""The episodes of the nightly read-ahead: ahead.json in the teaching folder.

Standard library only. teach_ahead.py puts the episodes it picks for the night in
<folder>/ahead.json, before they are added to episodes.json and before any download:

  {"version": 1, "episodes": [{"id": "<12 hex id>", "feed": "<the phone's feed address>",
                               "guid": "<the phone's guid>", "title": "...", "picked": <seconds>}]}

The list does two jobs. It is the flag that keeps these episodes apart: teach_train.py never puts
one on the shelf, and the exam only takes episodes that are new, which these never are again. And it
remembers the phone's own spelling of the feed and the guid, which are what the phone matches the
night's marks by (the Mac's id uses the Mac's own spelling of the feed). The tools that gather,
write down and mark take `--only-ahead`, which limits them to these episodes.

Run the tests: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import json
import os

import teach_store

AHEAD_FILE = "ahead.json"


def read_ahead(folder):
    """The episodes in ahead.json in the order they were picked, [] when there is no file. Raises
    teach_store.Problem when the file is damaged."""
    path = os.path.join(folder, AHEAD_FILE)
    if not os.path.exists(path):
        return []
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, ValueError):
        data = None
    episodes = data.get("episodes") if isinstance(data, dict) and data.get("version") == 1 else None
    if not isinstance(episodes, list) or not all(
            isinstance(e, dict) and isinstance(e.get("id"), str) and teach_store.ID_PATTERN.match(e["id"])
            and all(isinstance(e.get(field), str) for field in ("feed", "guid", "title"))
            and isinstance(e.get("picked"), int) and not isinstance(e["picked"], bool)
            for e in episodes):
        raise teach_store.Problem("%s is damaged. Fix or remove it, and run again." % path)
    return episodes


def ahead_ids(folder):
    """The ids of the episodes in ahead.json."""
    return {e["id"] for e in read_ahead(folder)}


def add_ahead(folder, items):
    """Adds the items (dicts like the entries above) whose id is not in the file yet, after the
    ones that are, and saves the file atomically. Returns the whole list."""
    found = read_ahead(folder)
    known = {e["id"] for e in found}
    joined = found + [item for item in items if item["id"] not in known]
    if len(joined) != len(found):
        teach_store.write_json(os.path.join(folder, AHEAD_FILE), {"version": 1, "episodes": joined})
    return joined
