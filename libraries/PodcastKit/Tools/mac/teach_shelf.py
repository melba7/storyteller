"""The held-out shelf of the teaching run and the check on it.

Standard library only. The shelf is a set of episodes the model is never trained on: for each show
(by feed) with at least 3 usable episodes, its newest one. It is kept in shelf.json, stays on the
shelf in later runs, and a show with one on the shelf gets no second. After training, the shelf is
scored and the precision and recall are saved in the model (see teach_train.py).

Run the tests: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import json
import math
import os

import teach_store
from teach_features import CLASSES, softmax_of

SHELF_MINIMUM = 3
SHELF_FILE = "shelf.json"
CLASS_COUNT = len(CLASSES)


# MARK: Shelf

def choose_shelf(entries, usable, shelf):
    """The shelf ids after this run: the old ones, then the newest usable episode of each show
    with at least 3 usable episodes that has none on the shelf yet."""
    chosen = list(dict.fromkeys(shelf))
    shelved_feeds = {e["feed"] for e in entries if e["id"] in chosen}
    by_feed = {}
    for e in entries:
        if e["id"] in usable:
            by_feed.setdefault(e["feed"], []).append(e)
    for feed, group in by_feed.items():
        if feed in shelved_feeds or len(group) < SHELF_MINIMUM:
            continue
        newest = group[0]
        for e in group[1:]:
            if (e["published"] if e["published"] is not None else -math.inf) > \
                    (newest["published"] if newest["published"] is not None else -math.inf):
                newest = e
        chosen.append(newest["id"])
    return chosen


def read_shelf(folder):
    """The ids in shelf.json, [] when there is none. Raises Problem when it is damaged."""
    path = os.path.join(folder, SHELF_FILE)
    if not os.path.exists(path):
        return []
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, ValueError):
        data = None
    if not isinstance(data, dict) or data.get("version") != 1 \
            or not isinstance(data.get("episodes"), list) \
            or not all(isinstance(x, str) for x in data["episodes"]):
        raise teach_store.Problem("%s is damaged. Fix or remove it, and run again." % path)
    return data["episodes"]


# MARK: Check

def ratio(part, whole_count):
    return round(part / whole_count, 4) if whole_count else None


def scores(true_positive, predicted, actual):
    return {"precision": ratio(true_positive, predicted), "recall": ratio(true_positive, actual)}


def evaluate(weights, episodes):
    """Scores every shelf line. weights maps a bucket to five numbers; episodes are as load_episode
    returns them. Lines with a class of None are left out."""
    lines = 0
    hit = predicted = actual = 0
    per = [[0, 0, 0] for _ in CLASSES]
    for episode in episodes:
        for cls, active in zip(episode["classes"], episode["buckets"]):
            if cls is None:
                continue
            lines += 1
            p = softmax_of(active, weights)
            guess = p.index(max(p))
            predicted += p[0] < 0.5
            actual += cls != 0
            hit += p[0] < 0.5 and cls != 0
            per[guess][1] += 1
            per[cls][2] += 1
            per[cls][0] += guess == cls
    return {"episodes": len(episodes), "lines": lines, "anyAd": scores(hit, predicted, actual),
            "classes": {CLASSES[c]: scores(*per[c]) for c in range(1, CLASS_COUNT)}}


def percent(value):
    return "n/a" if value is None else "%.0f%%" % (value * 100)


def check_lines(held):
    lines = ["Check on %d held-out episodes (%d lines): any ad precision %s, recall %s."
             % (held["episodes"], held["lines"], percent(held["anyAd"]["precision"]),
                percent(held["anyAd"]["recall"]))]
    for name, one in held["classes"].items():
        lines.append("  %s: precision %s, recall %s."
                     % (name, percent(one["precision"]), percent(one["recall"])))
    return lines
