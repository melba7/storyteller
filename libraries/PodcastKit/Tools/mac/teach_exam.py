"""The sealed exam of the teaching run: a list of episodes that no learning step may see.

Standard library only. The exam is the list of episode ids in <folder>/exam.json, written as
{"episodes": ["<12 hex id>", ...]}. The rule is simple: an exam episode is invisible to every step
that learns (training, the shelf, the library of ads, the habits). Only gathering, writing down what
is said, marking, second downloads and the scorer, when it is asked, may use it. teach_collect.py adds
the ids, before it saves episodes.json and before any download, so a run that stops half way can
never leak an exam episode into training.

Run the tests: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import argparse
import json
import os
import sys

import teach_segments
import teach_store
from teach_feed import feed_key

EXAM_FILE = "exam.json"
MOST = 60  # the usual size of the exam
FIRST = "labels"  # the folders of the first and the second marking
SECOND = "labels-second"
SECOND_MOST = 15  # how many exam episodes are marked a second time, in all


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


# MARK: Counting

def has(folder, labels, identifier):
    return os.path.exists(os.path.join(folder, labels, identifier + ".json"))


def has_transcript(folder, identifier):
    """True when the episode has a transcript with at least one usable line."""
    try:
        with open(os.path.join(folder, "transcripts", identifier + ".txt"), encoding="utf-8",
                  errors="replace") as f:
            return bool(teach_segments.read_transcript(f.read()))
    except OSError:
        return False


def status(folder):
    """What the exam looks like: {"ready", "first", "second", "wanted_second", "complete"}. `ready`
    is the exam episodes that are in episodes.json and have a usable transcript, `first` and
    `second` those of them with a label of the first and of the second marking. The exam is
    complete when every ready episode has a first label and the second marking holds
    min(15, ready) of them. Raises teach_store.Problem when exam.json or episodes.json is
    damaged."""
    known = {item["id"] for item in teach_store.require_manifest(folder)}
    ready = [i for i in read_exam(folder) if i in known and has_transcript(folder, i)]
    first = sum(1 for i in ready if has(folder, FIRST, i))
    second = sum(1 for i in ready if has(folder, SECOND, i))
    wanted = min(SECOND_MOST, len(ready))
    return {"ready": len(ready), "first": first, "second": second, "wanted_second": wanted,
            "complete": bool(ready) and first == len(ready) and second >= wanted}


def plural(count, one, many):
    return "%d %s" % (count, one if count == 1 else many)


def main(argv, say=print):
    """`ready --folder F` says how many exam episodes have audio and a transcript (exit 1 when
    none). `finish --folder F` says how many are marked once and twice, and whether the exam is
    done (exit 1 when it is not). Exit 2 for a damaged file or a bad command."""
    parser = argparse.ArgumentParser(prog="teach_exam.py")
    parser.add_argument("command", choices=("ready", "finish"))
    parser.add_argument("--folder", default=teach_store.FOLDER)
    try:
        options = parser.parse_args(argv)
        found = status(os.path.expanduser(options.folder))
    except SystemExit:
        return 2
    except teach_store.Problem as error:
        say(str(error))
        return 2
    ready = found["ready"]
    if options.command == "ready":
        if not ready:
            say("No exam episode has audio and a transcript yet.")
            return 1
        say("%s audio and a transcript." % plural(ready, "exam episode has", "exam episodes have"))
        return 0
    twice = found["second"]
    say("Of the %s that have audio and a transcript: marked once: %d, marked twice: %d."
        % (plural(ready, "exam episode", "exam episodes"), found["first"] - twice, twice))
    if found["complete"]:
        say("Done. The exam episodes are marked (%d of them twice) and kept apart from the learning. "
            "The exam is ready to be scored." % twice)
        return 0
    if not ready:
        say("There is nothing to mark yet, because no exam episode has audio and a transcript.")
        return 1
    missing = ready - found["first"]
    if missing:
        say("%s no first marking yet." % (plural(missing, "exam episode has", "exam episodes have")))
    if found["second"] < found["wanted_second"]:
        say("The second marking has %d of the %d wanted." % (found["second"], found["wanted_second"]))
    say("Not done yet. Double-click again to carry on.")
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
