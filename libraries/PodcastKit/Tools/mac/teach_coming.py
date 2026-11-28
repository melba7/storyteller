"""The episodes the Mac has picked and not finished yet: coming.json in the teaching folder.

Standard library only. The preparing job (teach_prepare.py pick) writes each episode it picks here
before any download or marking. teach_ahead_ads.py tells the phone about them as the top-level
array "coming" of ahead-ads.json, so the phone can wait for the Mac's copy instead of downloading
the publisher's:

  coming.json    {"version": 1, "episodes": [{"id": "<12 hex>", "feed": "...", "guid": "...", "since": <seconds>}]}
  ahead-ads.json "coming": [{"feed": "...", "guid": "...", "since": <seconds>}]

`since` is when the episode was picked, in unix seconds. An entry leaves "coming" when its copy is
published (it is in "episodes" with its "copy") and is dropped when the run ends without one, so
the phone never waits for a copy that is not on its way (teach_coming_publish.py settle). A file
that cannot be read counts as an empty list: this is only a hint for the phone and never stops a run.

Run the tests: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import json
import os

import teach_store

FILE = "coming.json"


def whole(value):
    return isinstance(value, int) and not isinstance(value, bool)


def read_coming(folder):
    """The entries of coming.json, [] when there is no file or it cannot be used."""
    try:
        with open(os.path.join(folder, FILE), encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, ValueError):
        return []
    found = data.get("episodes") if isinstance(data, dict) and data.get("version") == 1 else None
    if not isinstance(found, list):
        return []
    return [one for one in found if isinstance(one, dict) and isinstance(one.get("id"), str)
            and isinstance(one.get("feed"), str) and isinstance(one.get("guid"), str)
            and whole(one.get("since"))]


def write_coming(folder, entries):
    teach_store.write_json(os.path.join(folder, FILE), {"version": 1, "episodes": entries})


def add_coming(folder, picked, now):
    """Adds the picked episodes (dicts with id, feed and guid) that are not listed yet, each with
    `now` as its since. Raises OSError."""
    entries = read_coming(folder)
    known = {one["id"] for one in entries}
    entries += [{"id": one["id"], "feed": one["feed"], "guid": one["guid"], "since": int(now)}
                for one in picked if one["id"] not in known]
    write_coming(folder, entries)


def for_phone(folder, ready=()):
    """The array "coming" of ahead-ads.json: the entries whose id is not in `ready` (the episodes
    that have their copy), without the id."""
    return [{"feed": one["feed"], "guid": one["guid"], "since": one["since"]}
            for one in read_coming(folder) if one["id"] not in ready]
