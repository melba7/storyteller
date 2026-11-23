"""Chooses, from the scorecard and from what the phone noted, what each new ad finder may do on each
show, and writes show-settings.json into the teaching folder. The phone reads it (see ShowTuning.swift).

Standard library only. It reads <folder>/scorecard.json (the newest run's rows, one per finder, each
with the totals of every show) and the phone's notes (the same file teach_feedback.py reads, only read
here), and writes <folder>/show-settings.json:

  {"version": 1, "writtenAt": <seconds>, "default": {"finders": {"own-sound": "skip", ...},
   "joints": true, "steadyJoints": false, "ask": 0.35}, "shows": [{"feed": "<feed address>",
   "finders": {"meaning": "ask"}, "joints": false, "steadyJoints": false}]}

The whole file is written again at every run, so a change made to it by hand is lost at the next
"Teach the phone again".

A finder's level is "skip" (it may skip, the listener can undo), "ask" (it only asks) or "off". The
rows of the scorecard are cumulative, so a finder is judged on what its row added to the row before
it. Right seconds are adSeconds - heardSeconds, wrong seconds are cutSeconds. The rules:
- A show with fewer than 3 marked episodes gets nothing of its own, whatever the numbers say.
- A finder whose row is under 85 percent right (right / (right + wrong) seconds) only asks: on every
  show when that holds over all shows and its default is "skip", and on a show when it holds there.
- A finder with more wrong than right seconds is off everywhere when that holds over all shows, and
  asks on a show when it holds there. A finder that found no ad at all and cut under
  0.05 percent of the show is not judged, over all shows and on a show (the sound and repeat finders
  learn from a show's earlier episodes, which one unseen episode of each show cannot show): it keeps
  its level.
- Two undone skips of a finder on a show among its last five answers in the notes (the last 30 days)
  make it ask there; two "not an ad" answers among the last five turn it off there. Same rule as the
  phone's own finder guard.
- Joints stay on over all shows when the "Plus joints" row OR the "Plus joints (steady files too)" row
  has more right seconds than the row before "Plus joints" and at most one in a hundred more wrong
  seconds (most podcast files are steady, and on those the plain row finds nothing); when neither does
  they are off everywhere. On a show where the plain row adds more wrong than right seconds they are
  off for that show.
- Steady files get joints too ("steadyJoints") by the owner's bar when the steady row and the row
  before it both carry a "bar" (breaks passed, skips with no ad): on when the steady row passes at
  least 3 more breaks than the row before it and adds at most 1 skip with no ad, else off. Without a
  bar on both rows, by the seconds: when the steady row pays by that test and, if the plain
  row pays as well, has more right seconds than it and at most one in a hundred more wrong ones. A
  show where the steady row adds more wrong than right seconds over "Plus joints" gets
  "steadyJoints": false.
This tool never raises a finder to "skip": a listener's "yes" does not change this file or a level,
it only teaches the phone's own memory. Only the settings are written, to the teaching folder; the
phone's notes are only read. A scorecard without rows (an older file) gives the plain default.

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

import teach_store
from apple_podcasts_export import default_folders
from teach_settings_bar import bar_decision
from teach_settings_notes import answers, read_notes
from teach_settings_rows import SCORECARD, read_scorecard, rows_in
from teach_store import FOLDER, Problem

NAME = "show-settings.json"
# The rows the scorecard writes (the wiring registers exactly these names) and what each one holds.
ROWS = {
    "Plus the meaning model": "meaning",
    "Plus the phone's own sounds": "own-sound",
    "Plus repeated sounds": "repeat-sound",
    "Plus repeated words": "repeat-words",
    "Plus joints": "joints",
    "Plus joints (steady files too)": "steady-joints",
}
FINDERS = tuple(what for what in ROWS.values() if not what.endswith("joints"))
DEFAULT = {"finders": {"own-sound": "skip", "repeat-sound": "ask", "repeat-words": "ask",
                       "meaning": "skip"}, "joints": True, "steadyJoints": False, "ask": 0.35}
STRICTNESS = {"skip": 0, "ask": 1, "off": 2}
MIN_EPISODES = 3
PRECISION_PERCENT = 85
# A finder that found no ad at all and cut under one part in this many of the show has shown nothing
# either way: the sound and repeat finders learn from a show's earlier episodes, so a test over one
# unseen episode of each show cannot show their gain.
UNJUDGED_PARTS = 2000
# Wrong seconds may rise by one in a hundred (as 101 percent of the row before) and joints still pay.
WRONG_ALLOWED_PERCENT = 101
EPSILON = 1e-6


# MARK: What the scorecard says

def gained(after, before):
    """(right seconds, wrong seconds) that `after` has over `before`: what its finder added."""
    return after.right - before.right, after.wrong - before.wrong


def worse(right, wrong):
    """More wrong than right seconds (a hair more, so sums that differ by rounding do not count)."""
    return wrong - right > EPSILON


def unjudged(right, wrong, show):
    """Nothing found and almost nothing cut (under 0.05 percent of the show): too little to judge by."""
    return abs(right) <= EPSILON and wrong * UNJUDGED_PARTS < show


def imprecise(right, wrong):
    """Under 85 percent of the seconds added are ad seconds."""
    return right + wrong > EPSILON and right * 100 < PRECISION_PERCENT * (right + wrong)


def secs(value):
    return "%d s" % round(max(0, value))


def signed(value):
    return "%+d s" % round(value)


def cost(right, wrong):
    """What added seconds come to, in words that follow "it" or "they"."""
    if right < 0:
        return "lost %s of ad found and cut %s of show by mistake" % (secs(-right), secs(wrong))
    return "cut %s of show by mistake and found only %s of ad" % (secs(wrong), secs(right))


def show_gain(after, before, key):
    """(right, wrong) seconds the row `after` added to the row `before` on the show `key`; None when
    the scorecard cannot say because the show is missing from one of them."""
    if key not in after.shows or key not in before.shows:
        return None
    return gained(after.shows[key].figures, before.shows[key].figures)


def added_on(pairs, key, what):
    """What the row of `what` added on the show `key`, or None (no such row, or the show is missing)."""
    return show_gain(*pairs[what], key) if what in pairs else None


def show_seconds(pairs, key, what):
    """The seconds of the show `key` in the row of `what` (call it only when `added_on` found it)."""
    return pairs[what][0].shows[key].figures.show


def joints_pay(row, before):
    """Whether a joints row gains: more right seconds, and at most one in a hundred more wrong ones."""
    right, _ = gained(row.total, before.total)
    return right > EPSILON and row.total.wrong * 100 <= before.total.wrong * WRONG_ALLOWED_PERCENT


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
        if what not in ("joints", "steady-joints") and row.total.episodes >= MIN_EPISODES:
            overall(what, row, before, default, lines)
    over_joints(named, pairs, default, lines)
    return default, entries(rows, pairs, named, answers(notes, now, FINDERS), default, lines), lines


def over_joints(named, pairs, default, lines):
    """Judges the joints over all shows. Most podcast files are steady, and there the plain "Plus joints"
    row finds nothing, so joints stay on when EITHER that row OR the "(steady files too)" row pays against
    the row before "Plus joints"; they go off only when neither does. Steady files are used too when the
    steady row pays and, if the plain row pays as well, finds more than it for at most the allowed wrong."""
    joints, steady = named.get("joints"), named.get("steady-joints")
    if "joints" not in pairs or joints.total.episodes < MIN_EPISODES:
        return
    before = pairs["joints"][1]
    by_bar = bar_decision(pairs["steady-joints"], lines) if steady and "steady-joints" in pairs else None
    plain_pays = joints_pay(joints, before)
    steady_pays = bool(steady) and joints_pay(steady, before)
    if not plain_pays and not steady_pays and not by_bar:
        right, wrong = gained(joints.total, before.total)
        text = "Joints are off for every show: over %d marked episodes they found %s more of the ads and " \
            "cut %s more of show by mistake" % (joints.total.episodes, signed(right), signed(wrong))
        if steady:
            right, wrong = gained(steady.total, before.total)
            text += " (%s and %s with steady files too)" % (signed(right), signed(wrong))
        default["joints"] = False
        lines.append(text + ", which is not a clear gain.")
    elif by_bar is not None:
        default["steadyJoints"] = by_bar
    elif steady_pays:
        compared = joints if plain_pays else before
        right, wrong = gained(steady.total, compared.total)
        if not plain_pays or (right > EPSILON
                              and steady.total.wrong * 100 <= joints.total.wrong * WRONG_ALLOWED_PERCENT):
            default["steadyJoints"] = True
            lines.append("Joints are used in steady files too: they found %s more of the ads and cut %s "
                         "more of show by mistake." % (signed(right), signed(wrong)))


def overall(what, row, before, default, lines):
    """Changes the default block for the finder `what`, judged over all shows."""
    right, wrong = gained(row.total, before.total)
    episodes = row.total.episodes
    if unjudged(right, wrong, row.total.show):
        if wrong > EPSILON:
            lines.append("%s stays as it is: over %d marked episodes it found no ad and cut only %s of show, "
                         "too little to judge." % (what, episodes, secs(wrong)))
    elif worse(right, wrong):
        default["finders"][what] = "off"
        lines.append("%s is off for every show: over %d marked episodes it %s."
                     % (what, episodes, cost(right, wrong)))
    elif imprecise(right, wrong) and default["finders"][what] == "skip":
        default["finders"][what] = "ask"
        lines.append("%s only asks on every show: over %d marked episodes only %d percent of the seconds it "
                     "added were ad, under the %d percent it needs (it %s)."
                     % (what, episodes, 100 * right // (right + wrong), PRECISION_PERCENT, cost(right, wrong)))


def level_of(pairs, heard, key, finder):
    """What the scorecard and the notes together let `finder` do on the show `key`: (level, why)."""
    level, why = "skip", ""
    seconds = added_on(pairs, key, finder)
    if seconds and not unjudged(*seconds, show_seconds(pairs, key, finder)) \
            and (worse(*seconds) or imprecise(*seconds)):
        level, why = "ask", "it " + cost(*seconds)
    if (key, finder) in heard and STRICTNESS[heard[key, finder][0]] > STRICTNESS[level]:
        level, why = heard[key, finder]
    return level, why


def entries(rows, pairs, named, heard, default, lines):
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
            parts.append("joints are off (they %s)" % cost(*seconds))
        elif default["steadyJoints"]:
            seconds = show_gain(named["steady-joints"], named["joints"], key)
            if seconds and worse(*seconds):
                entry["steadyJoints"] = False
                parts.append("joints in steady files are off (they %s)" % cost(*seconds))
        if len(entry) > 1:
            shows.append(entry)
            lines.append("%s: %s." % (first[key].name or first[key].feed, "; ".join(parts)))
    return shows


# MARK: Run

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
