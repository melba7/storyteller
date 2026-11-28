#!/usr/bin/env python3
"""Scores where Claude's labels begin and end against the places where two downloads of an episode
differ, and shows what the word times do to the ends.

Standard library only; it sends nothing anywhere, uses no key and costs nothing. teach_copies.py
leaves copies/<id>.truth.txt for each episode it compared: one stretch to a line, the exact times
(to a frame) where the host put something into one download and not the other. For each such stretch
that Claude's labels in <folder>/labels cover (the rule of teach_snap.py: a label belongs to the
stretch it overlaps most, when it overlaps it by half of its own length or more, and a stretch of
over 300 s is left out) the stretch's edges are the earliest label's start and the latest label's end,
and the tool counts how many lie within 1, 2 and 5 seconds of the exact edge:

- "starts": where the label starts (a line's start; the word times do not change it);
- "endsBefore": where the label ends when it ends where the next line starts (what the marking did
  until the word times existed);
- "endsAfter": where it ends when it ends where its last word ends (teach_words.py), for an episode
  that has its side file transcripts/<id>.words.json, and as before for one that has not.

The label's ends are worked out again from its line numbers ("first", "last") and the transcript, so
Claude is not asked again and nothing is changed: it only reads. The sealed exam is not scored. The
plan's bar is that ends within 5 s reach 95 in 100 ("bar"). "withWordTimes" says the same for only
the episodes that have word times, so a run that has written down only some of them is still read
right. The report is saved as JSON (--out, default <folder>/end-edges.json) and said in a few lines.

  teach_end_score.py [--folder F] [--labels labels] [--out FILE]

Exit codes: 0 it worked (also when there was nothing to score), 2 something is not set up.

Run the tests: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import argparse
import json
import os
import re
import sys

import teach_exam
import teach_segments as seg
from teach_snap import FOLDER_NAME, MAX_STRETCH_SECONDS, claims, is_time
from teach_store import FOLDER, Problem, write_json
from teach_truth import LABELS, read_truth, truth_path
from teach_words import word_ends

LABEL_FILE = re.compile(r"^([0-9a-f]{12})\.json$")
WITHIN = (1, 2, 5)
BAR = 0.95
VERSION = 1


def read_text(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as handle:
            return handle.read()
    except OSError:
        return None


def usable_segments(label):
    """The segments of a label that have line numbers and times, as copies."""
    found = []
    for item in label.get("segments", []):
        if isinstance(item, dict) and isinstance(item.get("first"), int) and isinstance(item.get("last"), int) \
                and not isinstance(item.get("first"), bool) and not isinstance(item.get("last"), bool) \
                and item["first"] >= 1 and item["last"] >= item["first"]:
            found.append(dict(item))
    return found


def edges(segments, lines, ends, stretches):
    """[(truth start, truth end, label start, end before, end after)] for each stretch that labels
    cover. `ends` are the exact line ends, or None."""
    segments = [item for item in segments if item["last"] <= len(lines)]
    before = seg.with_times(segments, lines)
    after = seg.with_times(segments, lines, ends)
    usable = [i for i, item in enumerate(before) if is_time(item["start"]) and item["end"] > item["start"]]
    found = []
    for j, members in sorted(claims(before, usable, stretches).items()):
        first = min(members, key=lambda i: before[i]["start"])
        last = max(members, key=lambda i: before[i]["end"])
        found.append((stretches[j][0], stretches[j][1], before[first]["start"], before[last]["end"],
                      after[last]["end"]))
    return found


class Counts:
    """How many edges lie within each number of seconds of the exact one."""

    def __init__(self):
        self.total = 0
        self.within = {seconds: 0 for seconds in WITHIN}

    def add(self, distance):
        self.total += 1
        for seconds in WITHIN:
            self.within[seconds] += distance <= seconds + 1e-9

    def report(self):
        out = {}
        for seconds in WITHIN:
            out["within%d" % seconds] = self.within[seconds]
        for seconds in WITHIN:
            out["share%d" % seconds] = round(self.within[seconds] / self.total, 4) if self.total else None
        return out


def score(folder, labels=LABELS, say=print):
    """The report, a dict, for the labels in <folder>/<labels>."""
    exam = set(teach_exam.read_exam(folder))
    names = sorted(name for name in os.listdir(os.path.join(folder, labels)) if LABEL_FILE.match(name))
    episodes = {"labelled": len(names), "withTruth": 0, "scored": 0, "noTranscript": 0, "withWordTimes": 0,
                "exam": 0}
    stretches = {"differing": 0, "marked": 0, "notMarked": 0, "tooLong": 0}
    starts, before, after = Counts(), Counts(), Counts()
    with_words = {"marked": 0, "starts": Counts(), "endsBefore": Counts(), "endsAfter": Counts()}
    for name in names:
        identifier = name[:-5]
        if identifier in exam:
            episodes["exam"] += 1
            continue
        truth = read_text(truth_path(folder, identifier))
        if truth is None:
            continue
        try:
            differing = read_truth(truth)
            with open(os.path.join(folder, labels, name), encoding="utf-8") as handle:
                label = json.load(handle)
            if not isinstance(label, dict) or not isinstance(label.get("segments"), list):
                raise ValueError("it is not a label")
        except (OSError, ValueError) as error:
            say("%s was left out: %s" % (identifier, str(error)[:120]))
            continue
        episodes["withTruth"] += 1
        text = read_text(os.path.join(folder, "transcripts", identifier + ".txt"))
        lines = seg.read_transcript(text) if text is not None else []
        if not lines:
            episodes["noTranscript"] += 1
            continue
        episodes["scored"] += 1
        wanted = [one for one in differing if one[1] - one[0] <= MAX_STRETCH_SECONDS]
        stretches["tooLong"] += len(differing) - len(wanted)
        stretches["differing"] += len(wanted)
        ends = word_ends(folder, identifier, lines)
        episodes["withWordTimes"] += ends is not None
        found = edges(usable_segments(label), lines, ends, wanted)
        stretches["marked"] += len(found)
        stretches["notMarked"] += len(wanted) - len(found)
        for truth_start, truth_end, start, end_before, end_after in found:
            starts.add(abs(start - truth_start))
            before.add(abs(end_before - truth_end))
            after.add(abs(end_after - truth_end))
            if ends is not None:
                with_words["marked"] += 1
                with_words["starts"].add(abs(start - truth_start))
                with_words["endsBefore"].add(abs(end_before - truth_end))
                with_words["endsAfter"].add(abs(end_after - truth_end))
    share = after.report()["share5"]
    return {"version": VERSION, "labels": labels, "episodes": episodes, "stretches": stretches,
            "starts": starts.report(), "endsBefore": before.report(), "endsAfter": after.report(),
            "withWordTimes": {"marked": with_words["marked"], "endsBefore": with_words["endsBefore"].report(),
                              "endsAfter": with_words["endsAfter"].report()},
            "bar": {"edge": "ends within 5 s", "needed": BAR, "share": share,
                    "met": share is not None and share >= BAR}}


def percent(share):
    return "n/a" if share is None else "%.0f%%" % (share * 100)


def lines_of(report):
    """The report in plain sentences."""
    episodes, stretches = report["episodes"], report["stretches"]
    out = ["%d of %d labelled episodes have a second download and a transcript; %d of them have word "
           "times." % (episodes["scored"], episodes["labelled"], episodes["withWordTimes"]),
           "%d stretches differ between downloads: Claude's labels cover %d, %d are not covered, %d "
           "are over 300 s and left out." % (stretches["differing"] + stretches["tooLong"],
                                           stretches["marked"], stretches["notMarked"],
                                           stretches["tooLong"])]
    for key, what in (("starts", "starts"), ("endsBefore", "ends from the next line (before)"),
                      ("endsAfter", "ends from the last word (after)")):
        one = report[key]
        out.append("Label %s: %s within 1 s, %s within 2 s, %s within 5 s."
                   % (what, percent(one["share1"]), percent(one["share2"]), percent(one["share5"])))
    bar = report["bar"]
    out.append("The bar is %s of the ends within 5 s: %s%s." % (
        percent(bar["needed"]), "reached" if bar["met"] else "not reached",
        "" if bar["share"] is None else " (%s)" % percent(bar["share"])))
    if episodes["withWordTimes"] < episodes["scored"]:
        out.append("Only %d of %d scored episodes have word times, so \"after\" is as \"before\" for the "
                   "others. Write the rest down with teach_words.py." % (episodes["withWordTimes"],
                                                                         episodes["scored"]))
    return out


def main(argv=None, say=print):
    parser = argparse.ArgumentParser(description="Scores Claude's label edges against the exact edges.")
    parser.add_argument("--folder", default=FOLDER)
    parser.add_argument("--labels", default=LABELS)
    parser.add_argument("--out")
    args = parser.parse_args(argv)
    folder = os.path.expanduser(args.folder)
    if not FOLDER_NAME.match(args.labels) or not os.path.isdir(os.path.join(folder, args.labels)):
        say("There are no labels in %s. Mark the ads first." % os.path.join(folder, args.labels))
        return 2
    try:
        report = score(folder, args.labels, say)
        write_json(os.path.expanduser(args.out) if args.out else os.path.join(folder, "end-edges.json"), report)
    except Problem as error:
        say(str(error))
        return 2
    except OSError as error:
        say("Could not read or write in %s: %s" % (folder, error))
        return 2
    for line in lines_of(report):
        say(line)
    return 0


if __name__ == "__main__":
    sys.exit(main())
