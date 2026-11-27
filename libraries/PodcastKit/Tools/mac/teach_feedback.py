#!/usr/bin/env python3
"""Reads what the phone noted while you listened and writes the list of episodes the next gather
should fetch first.

Standard library only. The phone writes Podcasts/phone-notes.jsonl into its linked folder (the
iCloud copy of LofiMusic). One JSON object per line:

  {"v": 1, "at": <ms>, "what": "skipped"|"undone"|"trimmed"|"missed"|"confirmed"|"denied",
   "feed": "<feed address>", "guid": "<may be empty>", "title": "...", "address": "<audio address>",
   "start": <seconds>, "end": <seconds or null>, "kind": "ad"|"promo"|"ownPlug"|"credits"|"",
   "by": "<the finder that made the ad, only when the phone knew it>"}

"missed" means you pressed Skip ad where the phone knew no ad, "undone" means you took a skip back.
"confirmed" means you said yes to a question the phone asked ("Ad? Skip"), "denied" that it is not
an ad. `by` is kept when it is there (older notes have none).

  teach_feedback.py [--folder F] [--notes FILE]

The notes are looked for in the iCloud copy first, then in the Mac's own copy (or read from
--notes). The tool prints a small table per show (skipped, undone, missed) and writes
<folder>/wanted.json: the episodes with at least one "missed" or "undone" note ("confirmed" counts
like "missed" and "denied" like "undone"), the most recent first, at most 40, one per (feed, guid)
or, without a guid, (feed, audio address). teach_collect.py gathers those first. Lines that are not
valid notes are counted and skipped. Having no notes is not an error: nothing is written.

After the table it prints up to three lines about prepared episodes (teach_feedback_prepared.py):
ads the phone skipped by the Mac's marks (notes with by "prepared"), skips taken back, and taps on
Skip ad in episodes prepared.json lists as published. It says nothing when there are none.

Exit code: 0 it worked (also with no notes), 2 a set-up problem.

Run the tests: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import argparse
import json
import math
import os
import sys
import time

import teach_feedback_prepared
import teach_store
from apple_podcasts_export import default_folders
from teach_feed import is_web_address

NOTES = os.path.join("Podcasts", "phone-notes.jsonl")
WANTED = "wanted.json"
MOST = 40
WHAT = ("skipped", "undone", "trimmed", "missed", "confirmed", "denied")
# The notes that make an episode wanted, and the count each one adds to.
WANTED_AS = {"missed": "missed", "confirmed": "missed", "undone": "undone", "denied": "undone"}
LINE_LIMIT = 64 * 1024
FILE_LIMIT = 8 * 1024 * 1024


# MARK: Reading

def number(value):
    """True for a finite number (not a bool, NaN, an infinity or a whole number too big for one)."""
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return False
    try:
        return math.isfinite(value)
    except OverflowError:
        return False


def read_note(line):
    """The note a line holds, or None when the line is not a valid note: not JSON (a line nested so
    deeply that Python gives up counts too), longer than 64 KB, or with a time that is not a
    finite number, or with a feed or audio address that is not http or https, or with a `by` that
    is there (not null) and is not text. A `by` is kept when there is one."""
    if len(line) > LINE_LIMIT:
        return None
    try:
        one = json.loads(line)
    except (ValueError, RecursionError):
        return None
    if not isinstance(one, dict) or one.get("v") != 1 or one.get("what") not in WHAT:
        return None
    if not number(one.get("at")) or not number(one.get("start")):
        return None
    if one.get("end") is not None and not number(one["end"]):
        return None
    for field in ("feed", "guid", "title", "address", "kind"):
        if not isinstance(one.get(field), str):
            return None
    if one.get("by") is not None and not isinstance(one["by"], str):
        return None
    if not one["feed"] or not (one["guid"] or one["address"]):
        return None
    if not is_web_address(one["feed"]) or (one["address"] and not is_web_address(one["address"])):
        return None
    return one


def read_notes(path):
    """([valid notes], the number of lines that were not valid). Blank lines are not counted.
    Raises OSError, and ValueError (with the sentence to show) for a file over 8 MB."""
    if os.path.getsize(path) > FILE_LIMIT:
        raise ValueError("the notes file is bigger than %d MB, which is too big to read. Move it "
                         "away or make it smaller, and run this again." % (FILE_LIMIT // 1024 // 1024))
    with open(path, "rb") as handle:
        lines = handle.read().splitlines()
    notes, bad = [], 0
    for raw in lines:
        if not raw.strip():
            continue
        try:
            one = read_note(raw.decode("utf-8")) if len(raw) <= LINE_LIMIT else None
        except UnicodeDecodeError:
            one = None
        if one is None:
            bad += 1
        else:
            notes.append(one)
    return notes, bad


def find_notes(defaults, denied=None, name=NOTES):
    """The path of the notes (or of another file the phone writes into Podcasts/, named by `name`):
    the iCloud copy first (the last folder), then the Mac's own. A copy that macOS does not let
    this read (permissions) is added to the list `denied`, when given, and the next one is tried."""
    for folder in reversed(defaults()):
        path = os.path.join(folder, name)
        try:
            os.stat(path)
        except PermissionError:
            if denied is not None:
                denied.append(path)
            continue
        except OSError:
            continue
        return path
    return None


# MARK: Counting

def wanted_episodes(notes):
    """The episodes with a "missed" or "undone" note, most recent first, at most MOST. A "confirmed"
    note counts like "missed" and a "denied" one like "undone"."""
    found = {}
    for one in sorted(notes, key=lambda n: n["at"]):
        if one["what"] not in WANTED_AS:
            continue
        key = (one["feed"], one["guid"] or None, "" if one["guid"] else one["address"])
        episode = found.setdefault(key, {"feed": one["feed"], "guid": one["guid"], "title": "",
                                         "address": "", "missed": 0, "undone": 0, "last": 0})
        episode[WANTED_AS[one["what"]]] += 1
        episode["last"] = max(episode["last"], one["at"])
        for field in ("title", "address"):
            if one[field]:  # notes come oldest first, so the newest one that has it wins
                episode[field] = one[field]
    ranked = sorted(found.values(), key=lambda e: -e["last"])
    return ranked[:MOST]


def show_names(folder):
    """{feed address: show name} from episodes.json, {} when it is missing or cannot be used."""
    try:
        return {e["feed"]: e["show"] for e in teach_store.load_manifest(folder)}
    except (teach_store.ManifestError, OSError):
        return {}


def table(notes, names):
    """The lines of a small table: one row per show with how many skips, undos and misses."""
    counts = {}
    for one in notes:
        row = counts.setdefault(one["feed"], {"skipped": 0, "undone": 0, "missed": 0})
        if one["what"] in row:
            row[one["what"]] += 1
    lines = ["%-46s %7s %6s %6s" % ("Show", "skipped", "undone", "missed")]
    for feed in sorted(counts, key=lambda f: names.get(f, f).lower()):
        row = counts[feed]
        name = names.get(feed, feed)
        if len(name) > 46:
            name = name[:45] + "~"
        lines.append("%-46s %7d %6d %6d" % (name, row["skipped"], row["undone"], row["missed"]))
    return lines


# MARK: Run

def main(argv, say=print, defaults=default_folders, now=lambda: int(time.time() * 1000)):
    parser = argparse.ArgumentParser(prog="teach_feedback.py")
    parser.add_argument("--folder", default=teach_store.FOLDER)
    parser.add_argument("--notes")
    try:
        options = parser.parse_args(argv)
    except SystemExit as stop:
        return stop.code if isinstance(stop.code, int) else 2
    folder = os.path.expanduser(options.folder)
    denied = []
    path = os.path.expanduser(options.notes) if options.notes else find_notes(defaults, denied)
    if path is not None and options.notes:
        try:
            os.stat(path)
        except PermissionError:
            denied.append(path)
        except OSError:
            pass
    if denied and (path is None or path in denied):
        say("macOS did not let this read the phone's notes at %s (a permission problem), so "
            "nothing was learned. Give /bin/bash Full Disk Access once: System Settings > Privacy "
            "& Security > Full Disk Access > +, press Cmd-Shift-G, type /bin/bash, add it and "
            "switch it on. Nothing was written." % denied[0])
        return 2
    if denied and path is not None:
        say("macOS did not let this read the notes at %s (a permission problem), so the copy at %s "
            "was used instead. It may be older." % (denied[0], path))
    if path is None or not os.path.exists(path):
        if options.notes:
            say("There is no notes file at %s, so there is nothing to learn from. Nothing was "
                "written." % path)
        else:
            say("The phone has sent no notes yet, so there is nothing to learn from. Nothing was "
                "written.")
        return 0
    try:
        notes, bad = read_notes(path)
    except ValueError as error:
        say(str(error))
        return 2
    except OSError as error:
        say("The notes in %s could not be read: %s" % (path, error))
        return 2
    wanted = wanted_episodes(notes)
    try:
        teach_store.write_json(os.path.join(folder, WANTED),
                               {"version": 1, "writtenAt": now(), "episodes": wanted})
    except OSError as error:
        say("The teaching folder cannot be used: %s" % error)
        return 2
    for line in table(notes, show_names(folder)):
        say(line)
    for line in teach_feedback_prepared.summary(notes, folder):
        say(line)
    if bad:
        say("%d line%s in the notes %s not valid and %s skipped."
            % (bad, "" if bad == 1 else "s", "was" if bad == 1 else "were",
               "was" if bad == 1 else "were"))
    if wanted:
        say("%d episode%s on the list for the next gather."
            % (len(wanted), " is" if len(wanted) == 1 else "s are"))
    else:
        say("No episodes are on the list for the next gather.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
