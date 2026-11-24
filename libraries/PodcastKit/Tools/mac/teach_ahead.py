#!/usr/bin/env python3
"""The nightly read-ahead's own steps: choosing the night's episodes, saying whether any of them has
audio, and writing the file that tells the phone where their ads are. teach-ahead.sh runs them with
the gathering, the writing down and the marking of the other tools in between.

Standard library only. The phone writes Podcasts/phone-queue.json into its linked folder (the iCloud
copy of LofiMusic), the episodes it expects to play next, 12 at most:

  {"version": 1, "writtenAt": <seconds>, "episodes": [{"feed": "<feed address>", "guid": "<guid>",
   "title": "...", "show": "<show title>", "audio": "<audio address>", "reason": "upNext" | "newest",
   "rank": <0 for the first>}]}

  teach_ahead.py pick  --budget NAME [--folder F] [--queue FILE] [--shows FILE] [--cap 10]
                       [--most 8] [--estimate 0.19]
  teach_ahead.py ready [--folder F]
  teach_ahead.py write [--folder F]

pick reads the queue (the iCloud copy first, then the Mac's own, or --queue) and takes the first
--most episodes, in the phone's order, that are not marked yet: not in the teaching set (by id, or
by the feed's key and the guid or the audio address, so another spelling of a feed does not make
a second copy), not in the exam or on the shelf and not picked on an earlier night. At most as many
as the weekly budget NAME (see teach_budget.py) has room for: one more fits while what is spent plus
its --estimate dollars stays under the cap, which is when the marking (teach_label.py --reserve)
would still make the call. They are
put in ahead.json (teach_ahead_set.py) and then in episodes.json, waiting for a download. The Mac's
own spelling of a feed is used for the id when the show is one the Mac follows (--shows).
ready says whether any of those episodes has audio and no label yet. write makes ahead-ads.json
(teach_ahead_ads.py), which teach_publish.py then copies to the phone's folders.

Exit codes: 0 it worked, 2 a set-up problem (a damaged file, a folder that cannot be used, macOS
refusing to let this read the phone's folder), 3 nothing to do tonight, said in one plain line: no
queue, nothing new in it, no room in the budget, another run in the folder, or (ready) no audio.

Run the tests: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import argparse
import json
import math
import os
import sys
import time

import probe_shows as probe
import teach_ahead_ads
import teach_budget
import teach_exam
import teach_feedback
import teach_shelf
import teach_store
from apple_podcasts_export import default_folders
from teach_ahead_set import add_ahead, read_ahead
from teach_collect import new_entry
from teach_feed import episode_id, feed_key, is_web_address

QUEUE = os.path.join("Podcasts", "phone-queue.json")
FILE_LIMIT = 1024 * 1024
MOST = 8
CAP = 10.0
ESTIMATE = 0.19  # dollars of the Claude plan for one episode, as Claude counts it
NOTHING = 3


# MARK: The phone's list

def number(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def usable(one):
    """True for a list entry the Mac can fetch: texts, a guid, and web addresses for the feed and
    the audio."""
    return (isinstance(one, dict) and number(one.get("rank"))
            and all(isinstance(one.get(field), str) for field in ("feed", "guid", "title", "show", "audio"))
            and bool(one["guid"]) and is_web_address(one["feed"]) and is_web_address(one["audio"]))


def read_queue(path):
    """([entries in the phone's order], the number of entries that could not be used). Raises
    OSError, and ValueError (with the reason in plain words) for a file that is over a megabyte, not
    JSON or not a version 1 list."""
    if os.path.getsize(path) > FILE_LIMIT:
        raise ValueError("it is bigger than %d MB" % (FILE_LIMIT // 1024 // 1024))
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    if not isinstance(data, dict) or data.get("version") != 1 or not isinstance(data.get("episodes"), list):
        raise ValueError("it is not a version 1 list of episodes")
    items = [one for one in data["episodes"] if usable(one)]
    return sorted(items, key=lambda one: one["rank"]), len(data["episodes"]) - len(items)


def locate(explicit, defaults, say):
    """(path, ok): the queue file, from the iCloud copy, then the Mac's own, or the one asked for.
    `ok` is False when macOS refused to let this read the phone's folder (said here)."""
    if explicit:
        return os.path.expanduser(explicit), True
    denied = []
    path = teach_feedback.find_notes(defaults, denied, QUEUE)
    if denied and path is None:
        say("macOS did not let this read the phone's list of next episodes at %s (a permission "
            "problem), so nothing is read ahead. Give /bin/bash Full Disk Access once: System "
            "Settings > Privacy & Security > Full Disk Access > +, press Cmd-Shift-G, type /bin/bash, "
            "add it and switch it on." % denied[0])
        return None, False
    return path, True


# MARK: Choosing

def known_by(entries, kept):
    """(ids, keys) of what is marked or kept apart: the ids of the teaching set and of `kept`, and
    for every entry its feed's key together with its guid and with its audio address."""
    ids, keys = {e["id"] for e in entries} | set(kept), set()
    for e in entries:
        keys.add((feed_key(e["feed"]), e["address"]))
        if e["guid"]:
            keys.add((feed_key(e["feed"]), e["guid"]))
    return ids, keys


def choose(items, entries, kept, own, limit, now):
    """(entries for episodes.json, items for ahead.json, how many were left out because they are
    known): the first `limit` of the phone's episodes that are not known. `own` maps a feed key to
    the Mac's own spelling of that feed."""
    ids, keys = known_by(entries, kept)
    new, picked, left_out = [], [], 0
    for item in items:
        key = feed_key(item["feed"])
        feed = own.get(key, item["feed"])
        identifier = episode_id(feed, item["guid"], item["audio"])
        marks = {(key, item["guid"]), (key, item["audio"])}
        if identifier in ids or keys & marks:
            left_out += 1
        elif len(new) < limit:
            ids.add(identifier)
            keys |= marks
            new.append(new_entry(item["show"], feed, {
                "guid": item["guid"], "title": item["title"], "published": None, "seconds": None,
                "address": item["audio"], "size": None}))
            picked.append({"id": identifier, "feed": item["feed"], "guid": item["guid"],
                           "title": item["title"], "picked": now})
    return new, picked, left_out


def plural(count, one, many):
    return "%d %s" % (count, one if count == 1 else many)


def choosing(folder, items, options, shows, say, now):
    """pick, once the queue is read and the folder is locked."""
    entries = teach_store.load_manifest(folder)
    budget = teach_budget.Budget(folder, options.budget, options.cap)
    say(budget.line())
    # One more episode fits while what is spent plus its estimate stays under the cap: the same rule
    # teach_label.py --reserve uses before each call, so what is picked can be marked.
    room = min(options.most, max(math.ceil(budget.left() / options.estimate - 1e-9) - 1, 0))
    if room < 1:
        say("The weekly cap of $%.2f leaves no room for another episode (about $%.2f each), so "
            "nothing is read ahead tonight." % (options.cap, options.estimate))
        return NOTHING
    kept = set(teach_exam.read_exam(folder)) | set(teach_shelf.read_shelf(folder)) \
        | {e["id"] for e in read_ahead(folder)}
    own = {feed_key(show["feed"]): show["feed"] for show in shows}
    new, picked, left_out = choose(items, entries, kept, own, room, now)
    if not new:
        say("All %s in the phone's list are already marked or in the teaching set, so nothing is "
            "read ahead tonight." % plural(len(items), "episode", "episodes"))
        return NOTHING
    add_ahead(folder, picked)  # the flag first, so a stop half way cannot lose it
    teach_store.save_manifest(folder, entries + new)
    say("Tonight %s will be read ahead (%d of the phone's list were already marked):"
        % (plural(len(new), "episode", "episodes"), left_out))
    for item in new:
        say("  %s: %s" % (item["show"], item["title"]))
    return 0


def pick(options, say, defaults, now, load_shows):
    folder = os.path.expanduser(options.folder)
    path, allowed = locate(options.queue, defaults, say)
    if not allowed:
        return 2
    if path is None or not os.path.exists(path):
        say("The phone has not written its list of next episodes yet (%s in the linked folder), so "
            "nothing is read ahead tonight." % QUEUE)
        return NOTHING
    try:
        items, bad = read_queue(path)
    except (OSError, ValueError) as error:
        say("The phone's list of next episodes in %s cannot be used: %s. Nothing is read ahead."
            % (path, error))
        return 2
    if bad:
        say("%s in the phone's list could not be used and %s left out."
            % (plural(bad, "episode", "episodes"), "was" if bad == 1 else "were"))
    if not items:
        say("The phone's list of next episodes is empty, so nothing is read ahead tonight.")
        return NOTHING
    try:
        shows = load_shows(os.path.expanduser(options.shows))
    except (OSError, ValueError, AttributeError, TypeError):
        shows = []  # a Mac that does not follow shows uses the phone's spelling of every feed
    try:
        with teach_store.run_lock(folder):
            return choosing(folder, items, options, shows, say, int(now()))
    except teach_store.Busy:
        say("Another teaching run is already working in the teaching folder, so tonight's "
            "read-ahead is skipped.")
        return NOTHING
    except (teach_store.Problem, teach_store.ManifestError) as error:
        say(str(error))
        return 2
    except OSError as error:
        say("The teaching folder %s cannot be used: %s" % (folder, error))
        return 2


# MARK: Waiting, writing

def ready(folder, say):
    """Exit 0 when an episode of ahead.json has audio and no label yet, else 3 with one line."""
    entries = {e["id"]: e for e in teach_store.load_manifest(folder)}
    count = 0
    for item in read_ahead(folder):
        found = entries.get(item["id"])
        if found and found["file"] and os.path.exists(os.path.join(folder, found["file"])) \
                and not teach_exam.has(folder, "labels", item["id"]):
            count += 1
    if not count:
        say("None of tonight's episodes has audio to write down or mark (is this Mac online?), so "
            "the rest of the night is skipped.")
        return NOTHING
    say("%s to write down and mark." % plural(count, "episode has audio", "episodes have audio"))
    return 0


def write(folder, say, now):
    outcome = teach_ahead_ads.write(folder, int(now()), say)
    say("%s: %s." % (teach_ahead_ads.FILE, {"nothing": "nothing to tell the phone yet, no file",
                                            "unchanged": "unchanged"}.get(outcome, outcome)))
    return 0


# MARK: Command line

def positive(text):
    value = float(text)
    if not math.isfinite(value) or value <= 0:
        raise argparse.ArgumentTypeError("%r is not a number above zero" % text)
    return value


def main(argv, say=print, defaults=default_folders, now=time.time, load_shows=probe.load_shows):
    parser = argparse.ArgumentParser(prog="teach_ahead.py")
    parser.add_argument("command", choices=("pick", "ready", "write"))
    parser.add_argument("--folder", default=teach_store.FOLDER)
    parser.add_argument("--queue")
    parser.add_argument("--shows", default=probe.SHOWS_FILE)
    parser.add_argument("--budget")
    parser.add_argument("--cap", type=positive, default=CAP)
    parser.add_argument("--estimate", type=positive, default=ESTIMATE)
    parser.add_argument("--most", type=int, default=MOST)
    try:
        options = parser.parse_args(argv)
    except SystemExit as stop:
        return stop.code if isinstance(stop.code, int) else 2
    folder = os.path.expanduser(options.folder)
    try:
        if options.command == "pick":
            if not options.budget or options.most < 1:
                say("pick needs a --budget name and a --most of 1 or more.")
                return 2
            return pick(options, say, defaults, now, load_shows)
        if options.command == "ready":
            return ready(folder, say)
        return write(folder, say, now)
    except (teach_store.Problem, teach_store.ManifestError) as error:
        say(str(error))
        return 2
    except OSError as error:
        say("The teaching folder %s cannot be used: %s" % (folder, error))
        return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
