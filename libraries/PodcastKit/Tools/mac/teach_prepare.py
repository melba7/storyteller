#!/usr/bin/env python3
"""Episode preparing, the pick: which new episodes the Mac prepares for the phone this hour.

Standard library only. teach-prepare.sh runs it first. It is the nightly read-ahead's pick
(teach_ahead.py) for every show and not only for the phone's list:

  teach_prepare.py pick --budget NAME [--folder F] [--queue FILE] [--shows FILE] [--cap 35]
                        [--most 6] [--hours 72] [--estimate 0.19]

The candidates, in this order: the episodes of the phone's list of next episodes (as teach_ahead.py
reads it, whatever their age; a missing, empty or unusable list is said and is not a stop), then
the episodes of every show the Mac follows that came out in the last --hours, newest first. An
episode from a feed is told to the phone with the Mac's own feed address and the feed's guid (the
phone matches by the feed's key and the guid), so one with no guid is left out. The rule of
teach_ahead.choose leaves out what is known (in the teaching set, in ahead.json, in the exam or on
the shelf). At most --most are picked, and no more than the weekly budget NAME (see
teach_budget.py, the rule of teach_ahead.room_for) has room for. A feed that cannot be read is said
in one line and passed over.

What is picked goes into ahead.json and episodes.json exactly as the nightly pick does it, so the
download, the writing down and the marking run unchanged with --only-ahead.

Exit codes: 0 it picked, 2 a set-up problem, 3 nothing to do, said in one plain line.

Run the tests: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import argparse
import os
import sys
import time

import probe_shows as probe
import teach_ahead as night
import teach_budget
import teach_exam
import teach_feed
import teach_fetch
import teach_shelf
import teach_store
from apple_podcasts_export import default_folders
from teach_ahead import NOTHING, plural
from teach_ahead_set import add_ahead, read_ahead

HOURS = 72
MOST = 6
CAP = 35.0
ALL = 1_000_000


def phone_items(options, say, defaults):
    """The phone's list in its order, [] when there is none or it cannot be used (said)."""
    path, allowed = night.locate(options.queue, defaults, say)
    if not allowed or path is None or not os.path.exists(path):
        return []
    try:
        items, bad = night.read_queue(path)
    except (OSError, ValueError) as error:
        say("The phone's list of next episodes in %s cannot be used (%s), so only the shows' own "
            "newest episodes are looked at." % (path, error))
        return []
    if bad:
        say("%s in the phone's list could not be used and %s left out."
            % (plural(bad, "episode", "episodes"), "was" if bad == 1 else "were"))
    return items


def feed_items(shows, since, say, fetch, sleep):
    """The episodes of every show that came out at or after `since`, newest first, in the shape of
    the phone's list. A feed that cannot be read is said and passed over."""
    found = []
    for index, show in enumerate(shows):
        if index:
            sleep(probe.PAUSE)
        try:
            episodes = teach_feed.feed_episodes(fetch(show["feed"]), ALL)
        except Exception as error:  # a dead feed must not stop the others
            say("Skipped %s: its feed could not be read (%s)"
                % (show["title"], str(error) or error.__class__.__name__))
            continue
        for episode in episodes:
            if episode["published"] is not None and episode["published"] >= since and episode["guid"]:
                found.append({"feed": show["feed"], "guid": episode["guid"], "title": episode["title"],
                              "show": show["title"], "audio": episode["address"],
                              "published": episode["published"], "rank": 0})
    return sorted(found, key=lambda one: -one["published"])


def choosing(folder, items, options, shows, say, now):
    """pick, once the candidates are read and the folder is locked."""
    entries = teach_store.load_manifest(folder)
    budget = teach_budget.Budget(folder, options.budget, options.cap)
    room = night.room_for(budget, options.most, options.estimate)
    if room < 1:
        say("The weekly cap of $%.2f leaves no room for another episode (about $%.2f each), so "
            "nothing is prepared this hour." % (options.cap, options.estimate))
        return NOTHING
    kept = set(teach_exam.read_exam(folder)) | set(teach_shelf.read_shelf(folder)) \
        | {e["id"] for e in read_ahead(folder)}
    own = {teach_feed.feed_key(show["feed"]): show["feed"] for show in shows}
    new, picked, left_out = night.choose(items, entries, kept, own, room, now)
    if not new:
        say("There is nothing to prepare: the %s looked at %s already marked or in the teaching "
            "set." % (plural(len(items), "episode", "episodes"), "is" if len(items) == 1 else "are"))
        return NOTHING
    add_ahead(folder, picked)  # the flag first, so a stop half way cannot lose it
    teach_store.save_manifest(folder, entries + new)
    say(budget.line())
    say("This hour %s will be prepared (%d more were already known):"
        % (plural(len(new), "episode", "episodes"), left_out))
    for item in new:
        say("  %s: %s" % (item["show"], item["title"]))
    return 0


def pick(options, say, defaults, now, load_shows, fetch, sleep):
    folder = os.path.expanduser(options.folder)
    items = phone_items(options, say, defaults)
    try:
        shows = load_shows(os.path.expanduser(options.shows))
    except (OSError, ValueError, AttributeError, TypeError) as error:
        say("The list of followed shows could not be read (%s), so only the phone's list is used."
            % (str(error) or error.__class__.__name__))
        shows = []
    moment = int(now())
    items = items + feed_items(shows, moment - options.hours * 3600, say, fetch, sleep)
    if not items:
        say("There is nothing to prepare: no episode on the phone's list and none of your shows has "
            "a new one in the last %d hours." % options.hours)
        return NOTHING
    try:
        with teach_store.run_lock(folder):
            return choosing(folder, items, options, shows, say, moment)
    except teach_store.Busy:
        say("Another teaching run is already working in the teaching folder, so this hour is skipped.")
        return NOTHING
    except (teach_store.Problem, teach_store.ManifestError) as error:
        say(str(error))
        return 2
    except OSError as error:
        say("The teaching folder %s cannot be used: %s" % (folder, error))
        return 2


def main(argv, say=print, defaults=default_folders, now=time.time, load_shows=probe.load_shows,
         fetch=teach_fetch.fetch_feed, sleep=time.sleep):
    parser = argparse.ArgumentParser(prog="teach_prepare.py")
    parser.add_argument("command", choices=("pick",))
    parser.add_argument("--folder", default=teach_store.FOLDER)
    parser.add_argument("--queue")
    parser.add_argument("--shows", default=probe.SHOWS_FILE)
    parser.add_argument("--budget")
    parser.add_argument("--cap", type=night.positive, default=CAP)
    parser.add_argument("--estimate", type=night.positive, default=night.ESTIMATE)
    parser.add_argument("--most", type=int, default=MOST)
    parser.add_argument("--hours", type=night.positive, default=HOURS)
    try:
        options = parser.parse_args(argv)
    except SystemExit as stop:
        return stop.code if isinstance(stop.code, int) else 2
    if not options.budget or options.most < 1:
        say("pick needs a --budget name and a --most of 1 or more.")
        return 2
    try:
        return pick(options, say, defaults, now, load_shows, fetch, sleep)
    except (teach_store.Problem, teach_store.ManifestError) as error:
        say(str(error))
        return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
