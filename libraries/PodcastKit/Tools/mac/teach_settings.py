#!/usr/bin/env python3
"""Chooses, from the scorecard and from what the phone noted, what each new ad finder may do on each
show, and writes show-settings.json into the teaching folder. The phone reads it (see ShowTuning.swift).

Standard library only. It reads <folder>/scorecard.json (the newest run's rows, one per finder, each
with the totals of every show) and the phone's notes (the same file teach_feedback.py reads, only read
here), and writes <folder>/show-settings.json:

  {"version": 1, "writtenAt": <seconds>, "default": {"finders": {"own-sound": "skip", ...},
   "joints": true, "steadyJoints": false, "ask": 0.35}, "shows": [{"feed": "<feed address>",
   "finders": {"meaning": "ask"}, "joints": false}]}

A finder's level is "skip" (it may skip, the listener can undo), "ask" (it only asks) or "off". The
rows of the scorecard are cumulative, so a finder is judged on what its row added to the row before
it. Right seconds are adSeconds - heardSeconds, wrong seconds are cutSeconds. The rules:
- A show with fewer than 3 marked episodes gets nothing of its own, whatever the numbers say.
- A finder with more wrong than right seconds on a show asks on that show.
- Two undone skips of a finder on a show among its last five answers in the notes (the last 30 days)
  make it ask there; two "not an ad" answers among the last five turn it off there. Same rule as the
  phone's own finder guard.
- A finder (or the joints) with more wrong than right seconds over all shows is off everywhere.
- Joints that do worse on a show than the row before are off for that show.
- Steady files get joints too only when that row hears less of the ads before the skip than "Plus
  joints" and has at most one in a hundred more wrong seconds.
Only the settings are written, to the teaching folder; the phone's notes are only read. A scorecard
without rows (an older file) gives the plain default. Nothing is raised to "skip": a finder asks until
the listener says yes.

  teach_settings.py [--folder F] [--notes FILE]

Exit code: 0 it worked (also when there is no scorecard yet: nothing is written), 2 a set-up problem
(no teaching folder, a damaged or too big scorecard, or the file cannot be written).

Run the tests: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import argparse
import copy
import json
import os
import sys
import time

import teach_feedback
import teach_store
from apple_podcasts_export import default_folders
from teach_feed import feed_key
from teach_settings_rows import SCORECARD, number, read_scorecard, rows_in
from teach_store import FOLDER, Problem

NAME = "show-settings.json"
# The rows the scorecard writes (the wiring registers exactly these names) and what each one holds.
ROWS = {
    "Plus the phone's own sounds": "own-sound",
    "Plus repeated sounds": "repeat-sound",
    "Plus repeated words": "repeat-words",
    "Plus the meaning model": "meaning",
    "Plus joints": "joints",
    "Plus joints (steady files too)": "steady-joints",
}
FINDERS = tuple(what for what in ROWS.values() if not what.endswith("joints"))
DEFAULT = {"finders": {"own-sound": "skip", "repeat-sound": "ask", "repeat-words": "ask",
                       "meaning": "skip"}, "joints": True, "steadyJoints": False, "ask": 0.35}
STRICTNESS = {"skip": 0, "ask": 1, "off": 2}
MIN_EPISODES = 3
ANSWERS = ("undone", "denied", "confirmed")
ANSWER_WINDOW = 5
BAD_ANSWERS = 2
ANSWER_LIFE_MS = 30 * 24 * 3600 * 1000


# MARK: What the scorecard says

def gained(after, before):
    """(right seconds, wrong seconds) that `after` has over `before`: what its finder added."""
    return after.right - before.right, after.wrong - before.wrong


def worse(right, wrong):
    """More wrong than right seconds (a hair more, so sums that differ by rounding do not count)."""
    return wrong - right > 1e-6


def secs(value):
    return "%d s" % round(max(0, value))


def cost(right, wrong):
    return "it cut %s of show by mistake and found only %s of ad" % (secs(wrong), secs(right))


def added_on(pairs, key, what):
    """(right, wrong) seconds the row of `what` added on the show `key`; None when the scorecard cannot
    say: there is no such row, or the show is missing from it or from the row before."""
    if what not in pairs:
        return None
    row, before = pairs[what]
    if key not in row.shows or key not in before.shows:
        return None
    return gained(row.shows[key].figures, before.shows[key].figures)


# MARK: What the notes say

def answers(notes, now):
    """{(feed key, finder): (level, why)} from the notes: of a finder's last five answers on a show
    (undone, denied or confirmed, none older than 30 days), two denied turn it off and two undone make
    it ask. This is the phone's finder guard's rule. `now` and the notes' "at" are in milliseconds."""
    given = {}
    for one in sorted((n for n in notes if number(n.get("at"))), key=lambda n: n["at"]):
        if one.get("what") in ANSWERS and one.get("by") in FINDERS \
                and abs(now - one["at"]) <= ANSWER_LIFE_MS:
            given.setdefault((feed_key(one["feed"]), one["by"]), []).append(one["what"])
    chosen = {}
    for key, last in given.items():
        last = last[-ANSWER_WINDOW:]
        for answer, level, words in (("denied", "off", "\"not an ad\""), ("undone", "ask", "undone skips")):
            if last.count(answer) >= BAD_ANSWERS:
                chosen[key] = (level, "%d of its last %d answers on this show were %s"
                               % (last.count(answer), len(last), words))
                break
    return chosen


# MARK: Choosing

def choose(rows, notes, now):
    """(the default block, the shows' entries, plain lines saying what was decided and why)."""
    default, lines = copy.deepcopy(DEFAULT), []
    named, pairs = {}, {}  # each row by what it holds; and with the row before it
    for index, row in enumerate(rows):
        what = ROWS.get(row.name)
        if what and what not in named:
            named[what] = row
            if index > 0:
                pairs[what] = (row, rows[index - 1])
    for what, (row, before) in pairs.items():
        right, wrong = gained(row.total, before.total)
        if what != "steady-joints" and row.total.episodes >= MIN_EPISODES and worse(right, wrong):
            if what == "joints":
                default["joints"] = False
            else:
                default["finders"][what] = "off"
            lines.append("%s is off for every show: over %d marked episodes %s."
                         % (what, row.total.episodes, cost(right, wrong)))
    joints, steady = named.get("joints"), named.get("steady-joints")
    if default["joints"] and joints and steady and joints.total.episodes >= MIN_EPISODES \
            and steady.total.before < joints.total.before \
            and steady.total.wrong * 100 <= joints.total.wrong * 101:
        default["steadyJoints"] = True
        lines.append("Joints are used in steady files too: %s of ad heard before the skip, against %s."
                     % (secs(steady.total.before), secs(joints.total.before)))
    return default, entries(rows, pairs, answers(notes, now), default, lines), lines


def level_of(pairs, heard, key, finder):
    """What the scorecard and the notes together let `finder` do on the show `key`: (level, why)."""
    level, why = "skip", ""
    seconds = added_on(pairs, key, finder)
    if seconds and worse(*seconds):
        level, why = "ask", cost(*seconds)
    if (key, finder) in heard and STRICTNESS[heard[key, finder][0]] > STRICTNESS[level]:
        level, why = heard[key, finder]
    return level, why


def entries(rows, pairs, heard, default, lines):
    """The shows' entries. A show gets one only for what is stricter than the default block, and
    `lines` gets one line for each."""
    episodes, first = {}, {}  # by feed key
    for row in rows:
        for key, show in row.shows.items():
            episodes[key] = max(episodes.get(key, 0), show.figures.episodes)
            first.setdefault(key, show)
    shows = []
    for key in sorted(episodes, key=lambda each: first[each].feed):
        if episodes[key] < MIN_EPISODES:
            continue
        finders, parts = {}, []
        for finder in FINDERS:
            level, why = level_of(pairs, heard, key, finder)
            if STRICTNESS[level] > STRICTNESS[default["finders"][finder]]:
                finders[finder] = level
                parts.append("%s %s (%s)" % (finder, "now only asks" if level == "ask" else "is off", why))
        entry = {"feed": first[key].feed}
        if finders:
            entry["finders"] = finders
        seconds = added_on(pairs, key, "joints")
        if default["joints"] and seconds and worse(*seconds):
            entry["joints"] = False
            parts.append("joints are off (%s)" % cost(*seconds).replace("it cut", "they cut"))
        if len(entry) > 1:
            shows.append(entry)
            lines.append("%s: %s." % (first[key].name or first[key].feed, "; ".join(parts)))
    return shows


# MARK: Run

def read_notes(given, defaults, say):
    """The phone's notes (from `given`, or where teach_feedback.py looks), or [] with a line saying
    why there are none to use. Never raises."""
    denied = []
    path = os.path.expanduser(given) if given else teach_feedback.find_notes(defaults, denied)
    if path is None and denied:
        say("macOS did not let this read the phone's notes at %s (a permission problem), so only the "
            "scorecard was used." % denied[0])
    elif path is None:
        say("The phone has sent no notes yet, so only the scorecard was used.")
    else:
        try:
            os.stat(path)
            return teach_feedback.read_notes(path)[0]
        except FileNotFoundError:
            say("There is no notes file at %s, so only the scorecard was used." % path)
        except ValueError as error:
            say("The phone's notes were not used: %s" % error)
        except OSError as error:
            say("The notes in %s could not be read (%s), so only the scorecard was used." % (path, error))
    return []


def main(argv, say=print, defaults=default_folders, now=lambda: int(time.time() * 1000)):
    parser = argparse.ArgumentParser(prog="teach_settings.py")
    parser.add_argument("--folder", default=FOLDER)
    parser.add_argument("--notes")
    try:
        options = parser.parse_args(argv)
    except SystemExit as stop:
        return stop.code if isinstance(stop.code, int) else 2
    folder = os.path.expanduser(options.folder)
    if not os.path.isdir(folder):
        say("There is no teaching folder at %s. Nothing was written." % folder)
        return 2
    try:
        root = read_scorecard(os.path.join(folder, SCORECARD))
    except Problem as error:
        say(str(error))
        return 2
    if root is None:
        say("There is no scorecard yet, so there is nothing to choose from. Run \"Score the ad "
            "skipping\" first. Nothing was written.")
        return 0
    moment, rows = now(), rows_in(root)
    if rows:
        default, shows, lines = choose(rows, read_notes(options.notes, defaults, say), moment)
    else:
        default, shows, lines = copy.deepcopy(DEFAULT), [], []
        say("The newest run in %s has no rows (it was written by an older version), so %s holds the "
            "plain default." % (SCORECARD, NAME))
    value = {"version": 1, "writtenAt": moment // 1000, "default": default, "shows": shows}
    try:
        # Written with its keys in order, so the same choice is always the same text.
        teach_store.write_json(os.path.join(folder, NAME), json.loads(json.dumps(value, sort_keys=True)))
    except OSError as error:
        say("The settings could not be written to %s: %s" % (folder, error))
        return 2
    for line in lines:
        say(line)
    if shows:
        say("Saved %s for %d show%s with settings of their own."
            % (NAME, len(shows), "" if len(shows) == 1 else "s"))
    else:
        say("No show needs settings of its own. Saved %s with the default." % NAME)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
