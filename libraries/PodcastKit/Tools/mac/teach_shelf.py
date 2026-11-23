"""The held-out shelf of the teaching run and the check on it.

Standard library only. The shelf is a set of episodes the model is never trained on: for each show
(by feed) with at least 3 usable episodes, its newest one. It is kept in shelf.json, stays on the
shelf in later runs, and a show with one on the shelf gets no second. After training, the shelf is
scored and the precision and recall, in seconds of the spans the phone would cut, are saved in the
model (see teach_train.py).

Run the tests: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import json
import math
import os

import teach_spans as spans
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


def evaluate(weights, episodes, version=1):
    """Scores the shelf. weights maps a bucket to five numbers; episodes are as load_episode returns
    them (with the start and end second of every line). The numbers in "anyAd" are what the phone
    would cut, in seconds (see teach_spans.py); "lineAnyAd" and "classes" are per line, on the raw
    probabilities. Lines with a class of None are left out of the per-line numbers."""
    lines = 0
    hit = predicted = actual = 0
    per = [[0, 0, 0] for _ in CLASSES]
    cut = right = real = 0.0
    for episode in episodes:
        rows = []
        for cls, active in zip(episode["classes"], episode["buckets"]):
            p = softmax_of(active, weights)
            rows.append(p)
            if cls is None:
                continue
            lines += 1
            guess = p.index(max(p))
            predicted += p[0] < 0.5
            actual += cls != 0
            hit += p[0] < 0.5 and cls != 0
            per[guess][1] += 1
            per[cls][2] += 1
            per[cls][0] += guess == cls
        one = spans.span_scores(rows, episode["classes"], episode["starts"], episode["ends"],
                               version=version)
        cut, right, real = cut + one[0], right + one[1], real + one[2]
    shows = {episode.get("feed", episode["id"]) for episode in episodes}
    return {"episodes": len(episodes), "shows": len(shows), "lines": lines,
            "predictedAdSeconds": round(cut, 1), "adSeconds": round(real, 1),
            "anyAd": scores(right, cut, real), "lineAnyAd": scores(hit, predicted, actual),
            "classes": {CLASSES[c]: scores(*per[c]) for c in range(1, CLASS_COUNT)}}


def percent(value):
    return "n/a" if value is None else "%.0f%%" % (value * 100)


def check_lines(held):
    lines = ["Check on %d held-out episodes from %d shows (%d lines): the phone "
             "would cut %d seconds of them, precision %s, recall %s."
             % (held["episodes"], held["shows"], held["lines"], round(held["predictedAdSeconds"]),
                percent(held["anyAd"]["precision"]), percent(held["anyAd"]["recall"]))]
    for name, one in held["classes"].items():
        lines.append("  %s: precision %s, recall %s."
                     % (name, percent(one["precision"]), percent(one["recall"])))
    return lines
