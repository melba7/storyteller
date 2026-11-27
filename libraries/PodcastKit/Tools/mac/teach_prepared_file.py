"""prepared.json, the list of the audio the Mac has prepared for the phone (teach_prepared.py), and
what may be said about it: which entries have a name that is safe to remove, and which copies are
really in the iCloud folder.

Standard library only.

  {"version": 1, "episodes": [{"id": "<12 hex>", "file": "prepared/<id>.<ext>", "sha256": "<64 hex>",
                               "bytes": <int>, "published": <seconds>, "removed": <seconds or null>}]}

Run the tests: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import json
import os
import re

import teach_store
from teach_publish import SUBFOLDER
from teach_store import AUDIO_EXTENSIONS, ID_PATTERN

FILE = "prepared.json"
FOLDER_NAME = "prepared"
NAME = re.compile(r"^prepared/([0-9a-f]{12})\.(%s)$" % "|".join(AUDIO_EXTENSIONS))


def shaped(one):
    return (isinstance(one, dict) and isinstance(one.get("id"), str) and isinstance(one.get("file"), str)
            and isinstance(one.get("sha256"), str)
            and all(isinstance(one.get(key), int) and not isinstance(one[key], bool)
                    for key in ("bytes", "published"))
            and (one.get("removed") is None
                 or (isinstance(one["removed"], int) and not isinstance(one["removed"], bool))))


def read_prepared(folder):
    """The entries of prepared.json in the order they were made, [] when there is no file. Raises
    teach_store.Problem when the file is damaged."""
    path = os.path.join(folder, FILE)
    if not os.path.exists(path):
        return []
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, ValueError):
        data = None
    found = data.get("episodes") if isinstance(data, dict) and data.get("version") == 1 else None
    if not isinstance(found, list) or not all(shaped(one) for one in found):
        raise teach_store.Problem("%s is damaged. Fix or remove it, and run again." % path)
    return found


def write_prepared(folder, entries):
    teach_store.write_json(os.path.join(folder, FILE), {"version": 1, "episodes": entries})


def name_belongs(one):
    """True when the entry's file is prepared/<its own id>.<ext>, the only kind of name removed."""
    found = NAME.match(one["file"])
    return bool(found) and found.group(1) == one["id"] and bool(ID_PATTERN.match(one["id"]))


def copies(folder, to):
    """{id: {"file", "sha256", "bytes"}} of the prepared audio that is published and still there
    (same size as when it was copied) in the iCloud copy `to`. teach_ahead_ads.py tells the phone
    about exactly these."""
    found = {}
    for one in read_prepared(folder):
        if one["removed"] is not None or not name_belongs(one):
            continue
        try:
            size = os.path.getsize(os.path.join(to, SUBFOLDER, one["file"]))
        except OSError:
            continue
        if size == one["bytes"] and re.fullmatch(r"[0-9a-f]{64}", one["sha256"]):
            found[one["id"]] = {"file": one["file"], "sha256": one["sha256"], "bytes": one["bytes"]}
    return found
