#!/usr/bin/env python3
"""Works out each show's habits from the labels of the teaching run (for example whether it
usually opens with an ad), writes them to habits.json and prints a small table, with the shows
that most often open with an ad first.

Standard library only. It reads <folder>/episodes.json and every <folder>/<labels>/*.json that
teach_label.py wrote, and writes <folder>/habits.json. A label file that is not valid is skipped
with one line.

  teach_habits.py [--folder F] [--labels labels]

How the numbers are worked out:
- Only segments of sort "sponsor" or "network_promo" with confidence "high" or "medium" count as
  ads here. Everything else is ignored.
- An ad block is a run of such segments where each next one starts within 20 seconds of the
  previous one's end.
- An episode opens with an ad when its first ad block starts within the first 90 seconds. That
  block is its opening.
- Each show (keyed by its feed) gets: feed, title, episodes (how many labelled episodes),
  opensWithAd (how many of them open with an ad), openingStarts and openingEnds (the median start
  and end of the openings in seconds, null when there are none), breaks (the median number of ad
  blocks in an episode) and adSeconds (the median total length of the ads in an episode).

Exit code: 0 it worked (also when there are no labels yet), 2 a set-up problem (no episodes.json,
or a damaged one).

Run the tests: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import argparse
import json
import os
import sys
import time

from teach_store import FOLDER, Problem, require_manifest, write_json

AD_SORTS = ("sponsor", "network_promo")
AD_CONFIDENCE = ("high", "medium")
JOIN_SECONDS = 20
OPENING_SECONDS = 90


def number(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def median(values):
    """The middle value (the mean of the two middle ones for an even count), or None."""
    ordered = sorted(values)
    if not ordered:
        return None
    middle = len(ordered) // 2
    if len(ordered) % 2:
        return ordered[middle]
    return (ordered[middle - 1] + ordered[middle]) / 2


def rounded(value):
    return None if value is None else round(value, 1)


def facts_of(one):
    """What one label says: its ad blocks as (start, end), whether it opens with an ad, the
    opening block or None, and the total seconds of ads."""
    spans = sorted((s["start"], s["end"]) for s in one["segments"]
                   if s.get("sort") in AD_SORTS and s.get("confidence") in AD_CONFIDENCE)
    blocks = []
    for start, end in spans:
        if blocks and start - blocks[-1][1] <= JOIN_SECONDS:
            blocks[-1] = (blocks[-1][0], max(blocks[-1][1], end))
        else:
            blocks.append((start, end))
    opens = bool(blocks) and blocks[0][0] <= OPENING_SECONDS
    return {"blocks": blocks, "opens": opens, "opening": blocks[0] if opens else None,
            "ad_seconds": sum(end - start for start, end in spans)}


def summarize(labels, titles):
    """One entry per feed, shows that most often open with an ad first. `titles` maps a feed to
    the show's name from episodes.json."""
    by_feed = {}
    for one in labels:
        by_feed.setdefault(one["feed"], []).append(one)
    shows = []
    for feed, group in by_feed.items():
        facts = [facts_of(one) for one in group]
        openings = [f["opening"] for f in facts if f["opening"]]
        shows.append({"feed": feed, "title": titles.get(feed) or group[0].get("show") or feed,
                      "episodes": len(group), "opensWithAd": len(openings),
                      "openingStarts": rounded(median([o[0] for o in openings])),
                      "openingEnds": rounded(median([o[1] for o in openings])),
                      "breaks": rounded(median([len(f["blocks"]) for f in facts])),
                      "adSeconds": rounded(median([f["ad_seconds"] for f in facts]))})
    shows.sort(key=lambda s: (-s["opensWithAd"] / s["episodes"], -s["episodes"], s["title"]))
    return shows


def valid(one):
    """True when a decoded label has the shape this tool needs."""
    if not isinstance(one, dict) or not isinstance(one.get("feed"), str) \
            or not isinstance(one.get("segments"), list):
        return False
    return all(isinstance(s, dict) and number(s.get("start")) and number(s.get("end"))
               for s in one["segments"])


def read_labels(folder, say):
    """The valid labels in a folder; each damaged file is skipped with one line."""
    labels = []
    if not os.path.isdir(folder):
        return labels
    for name in sorted(os.listdir(folder)):
        if not name.endswith(".json"):
            continue
        try:
            with open(os.path.join(folder, name), encoding="utf-8") as f:
                one = json.load(f)
        except (OSError, ValueError):
            one = None
        if valid(one):
            labels.append(one)
        else:
            say("Skipping %s: it is not a valid label." % name)
    return labels


def table(shows):
    """The lines of the printed table."""
    rows = [("Show", "Episodes", "Opens with an ad", "Ad blocks", "Ad seconds")]
    for s in shows:
        rows.append((s["title"][:40], str(s["episodes"]),
                     "%d of %d" % (s["opensWithAd"], s["episodes"]),
                     "%g" % s["breaks"], "%g" % s["adSeconds"]))
    widths = [max(len(row[i]) for row in rows) for i in range(5)]
    return ["  ".join(cell.ljust(widths[i]) for i, cell in enumerate(row)).rstrip()
            for row in rows]


def main(argv, say=print):
    parser = argparse.ArgumentParser(prog="teach_habits.py")
    parser.add_argument("--folder", default=FOLDER)
    parser.add_argument("--labels", default="labels")
    options = parser.parse_args(argv)
    folder = os.path.expanduser(options.folder)
    try:
        episodes = require_manifest(folder)
    except Problem as error:
        say(str(error))
        return 2
    titles = {}
    for item in episodes:
        if item["feed"] and item["show"]:
            titles.setdefault(item["feed"], item["show"])
    labels = read_labels(os.path.join(folder, options.labels), say)
    if not labels:
        say("No labels yet. Run \"Mark ads in the teaching episodes\" first.")
        return 0
    shows = summarize(labels, titles)
    write_json(os.path.join(folder, "habits.json"),
               {"version": 1, "writtenAt": int(time.time() * 1000), "shows": shows})
    for row in table(shows):
        say(row)
    say("Saved habits.json for %d shows from %d episodes." % (len(shows), len(labels)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
