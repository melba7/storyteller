"""The sealed exam of the teaching run: a list of episodes that no learning step may see.

Standard library only. The exam is the list of episode ids in <folder>/exam.json, written as
{"episodes": ["<12 hex id>", ...]}. The rule is simple: an exam episode is invisible to every step
that learns (training, the shelf, the library of ads, the habits). Only gathering, writing down what
is said, marking, second downloads and the scorer, when it is asked, may use it. teach_collect.py adds
the ids, before it saves episodes.json and before any download, so a run that stops half way can
never leak an exam episode into training.

Run the tests: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import json
import os

import teach_store
from teach_feed import feed_key

EXAM_FILE = "exam.json"
MOST = 60  # the usual size of the exam


def read_exam(folder):
    """The ids in exam.json in their order, [] when there is no file. Raises teach_store.Problem
    when the file is damaged."""
    path = os.path.join(folder, EXAM_FILE)
    if not os.path.exists(path):
        return []
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, ValueError):
        data = None
    if not isinstance(data, dict) or not isinstance(data.get("episodes"), list) \
            or not all(isinstance(x, str) and teach_store.ID_PATTERN.match(x) for x in data["episodes"]):
        raise teach_store.Problem("%s is damaged. Fix or remove it, and run again." % path)
    return data["episodes"]


def add_to_exam(folder, ids):
    """Adds the ids that are not in the exam yet, after the ones that are, and saves the file
    atomically. Returns the whole list."""
    found = read_exam(folder)
    joined = list(dict.fromkeys(found + list(ids)))
    if joined != found:
        teach_store.write_json(os.path.join(folder, EXAM_FILE), {"episodes": joined})
    return joined


def number(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def pick_new(known, planned, already, most):
    """The planned entries that may join the exam, in the planner's order. An entry must have a
    published time that is later than the newest published time of every `known` entry of the same
    feed (so it is newer than everything gathered before); one with no published time is not taken.
    At most `most` episodes are in the exam in all, those in `already` (the ids now in exam.json)
    counting towards that."""
    newest = {}
    for entry in known:
        if number(entry["published"]):
            key = feed_key(entry["feed"])
            newest[key] = max(newest.get(key, entry["published"]), entry["published"])
    room = max(most - len(already), 0)
    picked = []
    for entry in planned:
        if len(picked) >= room:
            break
        if number(entry["published"]) and entry["published"] > newest.get(feed_key(entry["feed"]),
                                                                           float("-inf")):
            picked.append(entry)
    return picked
