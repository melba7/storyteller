"""Reads the rows of the newest run in scorecard.json for teach_settings.py.

Standard library only. A run has `rows`, one per finder (each stands on the row before it), and a row
has `total` and `shows[]` (`feed`, `show`, `total`). Of a total only the numbers this needs are read:
how many episodes, the right seconds (adSeconds - heardSeconds), the wrong seconds (cutSeconds) and
the seconds of show (showSeconds, 0 when the file has none). A row may also carry the owner's `bar`
(AdBar.swift): of it only `breaks`, `passed` and `noAdSkips` are read, and a bar that lacks one of them
or holds a number that is not a number counts as none.
Anything of the wrong shape is skipped, never raised.

Run the tests: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import collections
import json
import math
import os

from teach_feed import feed_key
from teach_store import Problem

SCORECARD = "scorecard.json"
SCORECARD_LIMIT = 16 * 1024 * 1024

Figures = collections.namedtuple("Figures", "episodes right wrong show")
Show = collections.namedtuple("Show", "feed name figures")
Bar = collections.namedtuple("Bar", "breaks passed skips")
Row = collections.namedtuple("Row", "name total shows bar", defaults=(None,))


def number(value):
    """True for a finite number (not a bool, NaN, an infinity or a whole number too big for a float)."""
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return False
    try:
        return math.isfinite(value)
    except OverflowError:
        return False


def figures(total):
    """The figures of a total, or None when a number it needs is missing or not a finite number."""
    if not isinstance(total, dict):
        return None
    kept = [total.get(key) for key in ("episodes", "adSeconds", "heardSeconds", "cutSeconds")]
    if not all(number(value) for value in kept) or kept[0] < 0:
        return None
    shown = total.get("showSeconds")
    return Figures(int(kept[0]), kept[1] - kept[2], kept[3], shown if number(shown) and shown > 0 else 0.0)


def added(first, second):
    return Figures(*(a + b for a, b in zip(first, second)))


def read_bar(value):
    """The Bar of a row's `bar`, or None when there is none or it is not made of numbers."""
    if not isinstance(value, dict):
        return None
    kept = [value.get(key) for key in ("breaks", "passed", "noAdSkips")]
    if not all(number(each) and each >= 0 for each in kept):
        return None
    return Bar(*(int(each) for each in kept))


def read_row(item):
    """The Row an item of `rows` holds, or None when it is not one. A show that cannot be used is left
    out; a feed that comes twice (or spelt two ways) is added up."""
    if not isinstance(item, dict) or not isinstance(item.get("name"), str):
        return None
    whole = figures(item.get("total"))
    if whole is None:
        return None
    shows = {}
    for one in item["shows"] if isinstance(item.get("shows"), list) else []:
        if not isinstance(one, dict) or not isinstance(one.get("feed"), str):
            continue
        key, counted = feed_key(one["feed"]), figures(one.get("total"))
        if not key or counted is None:
            continue
        if key in shows:
            counted = added(shows[key].figures, counted)
            one = dict(one, feed=shows[key].feed, show=shows[key].name)
        name = one["show"] if isinstance(one.get("show"), str) else ""
        shows[key] = Show(one["feed"], name, counted)
    return Row(item["name"], whole, shows, read_bar(item.get("bar")))


def rows_in(root):
    """The rows of the newest run of a decoded scorecard (runs come oldest first). A run saved before
    rows existed has none."""
    runs = root.get("runs") if isinstance(root, dict) else None
    newest = runs[-1] if isinstance(runs, list) and runs else None
    items = newest.get("rows") if isinstance(newest, dict) else None
    rows = [read_row(item) for item in items] if isinstance(items, list) else []
    return [row for row in rows if row]


def read_scorecard(path):
    """The decoded scorecard, None when there is none. Raises Problem for one that cannot be used."""
    unreadable = "The scorecard at %s could not be read: %s. Nothing was written."
    try:
        size = os.path.getsize(path)
    except FileNotFoundError:
        return None
    except OSError as error:
        raise Problem(unreadable % (path, error))
    if size > SCORECARD_LIMIT:
        raise Problem("%s is too big to read (more than %d MB). Nothing was written."
                      % (SCORECARD, SCORECARD_LIMIT // 1024 // 1024))
    try:
        with open(path, "rb") as handle:
            root = json.loads(handle.read().decode("utf-8"))
    except OSError as error:
        raise Problem(unreadable % (path, error))
    except (ValueError, RecursionError):
        raise Problem("%s is damaged: it is not valid JSON. Nothing was written." % SCORECARD)
    if not isinstance(root, dict) or type(root.get("version")) is not int or root["version"] != 1 \
            or not isinstance(root.get("runs"), list):
        raise Problem("%s is not a scorecard this can read. Nothing was written." % SCORECARD)
    return root
