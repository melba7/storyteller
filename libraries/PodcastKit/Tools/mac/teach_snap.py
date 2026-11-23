#!/usr/bin/env python3
"""Writes labels-snapped/, a copy of Claude's labels whose borders sit exactly where two downloads
of the episode differ.

Standard library only; it sends nothing anywhere and uses no key. teach_copies.py leaves a truth
file for each episode it compared, copies/<id>.truth.txt, one stretch to a line as two times such
as 0:33.480 1:02.120. Those stretches are what the host put into one download and not the other,
so their times are exact to a frame. For each label in <folder>/labels this tool writes
<folder>/labels-snapped/<id>.json:

- A label that overlaps a stretch by half of its own length or more takes the stretch's start and
  end (and the transcript lines they cover). When Claude cut one ad into several labels, they
  are joined into one: the one that overlaps most keeps its sort and its "who".
- A stretch of 10 s or more that Claude's labels do not cover by half is added as a "sponsor" with
  "confidence": "high" (a difference between two copies of one episode is measured, not guessed)
  and "who": "", and an extra key "origin": "copy" that says where it came from. That it is a
  sponsor is a guess; it could be a network promo. Shorter stretches are left out. The tools that
  read labels (training, habits, library, sounds, score) read the keys they know and ignore
  "origin". A label of Claude's that moves keeps its own confidence and gains no key.
- An episode with no truth file, or whose two downloads agreed (a truth file with no stretch), is
  copied as it was, byte for byte.

Claude's own <folder>/labels are never changed. Every label gets a snapped one, so the folder can
stand in for `labels` in the later steps (--labels labels-snapped). It prints how many borders
moved and the median seconds they moved, and how many stretches Claude had not marked.

  teach_snap.py [--folder F] [--labels labels] [--out labels-snapped]

It does not take the folder's run lock, because teach-finish.sh (which holds it) runs it. Run it
alone through `teach_store.py hold FOLDER python3 teach_snap.py ...`.

Exit codes: 0 it worked (also when there was nothing to do), 2 something is not set up (no labels
folder, a bad folder name) or a file could not be written.

Run the tests: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import argparse
import json
import math
import os
import re
import sys

import teach_segments as seg
from teach_store import FOLDER, write_json
from teach_truth import LABELS, SNAPPED, covered, overlap, read_truth, save_bytes, truth_path

ADD_SECONDS = 10.0
MOVED_SECONDS = 0.05
LABEL_FILE = re.compile(r"^([0-9a-f]{12})\.json$")
FOLDER_NAME = re.compile(r"^[A-Za-z0-9_-]{1,64}$")
WHY = "The second download of this episode differs here, so the host put something in."


def is_time(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def placed(segment, lines, start, end):
    """A copy of the segment with new times, and new line numbers when the stretch covers lines."""
    moved = dict(segment, start=round(start, 3), end=round(end, 3))
    lines_covered = covered(lines, start, end)
    if lines_covered:
        moved["first"], moved["last"] = lines_covered
    return moved


# MARK: One label

def snap_label(label, stretches, lines):
    """(new label or None, figures). None when nothing in the label has to change. The figures:
    "moved", the seconds each border that moved was moved by; "added", "short" and "unplaced", the
    stretches that Claude's labels did not cover (added as a sponsor, under 10 s, and not on any
    line of the transcript); "joined", the labels that were folded into another."""
    segments = label["segments"]
    figures = {"moved": [], "added": 0, "short": 0, "unplaced": 0, "joined": 0}
    usable = [i for i, one in enumerate(segments) if isinstance(one, dict) and is_time(one.get("start"))
              and is_time(one.get("end")) and one["end"] > one["start"]]
    claimed = {}  # stretch number -> [(overlap, label number)]
    for i in usable:
        one = segments[i]
        best = None
        for j, (start, end) in enumerate(stretches):
            shared = overlap(one["start"], one["end"], start, end)
            if shared * 2 >= one["end"] - one["start"] and (best is None or shared > best[0]):
                best = (shared, j)
        if best:
            claimed.setdefault(best[1], []).append((best[0], i))
    replaced, dropped = {}, set()
    for j, members in claimed.items():
        members.sort(key=lambda item: (-item[0], segments[item[1]]["start"]))
        keep = segments[members[0][1]]
        replaced[members[0][1]] = placed(keep, lines, *stretches[j])
        for border, now in (("start", stretches[j][0]), ("end", stretches[j][1])):
            if abs(now - keep[border]) > MOVED_SECONDS:
                figures["moved"].append(abs(now - keep[border]))
        dropped.update(i for _, i in members[1:])
    figures["joined"] = len(dropped)
    result = [replaced.get(i, one) for i, one in enumerate(segments) if i not in dropped]
    for j, (start, end) in enumerate(stretches):
        if j in claimed:
            continue
        marked = sum(overlap(segments[i]["start"], segments[i]["end"], start, end) for i in usable)
        if marked * 2 >= end - start:
            continue
        if end - start < ADD_SECONDS:
            figures["short"] += 1
        elif not covered(lines, start, end):
            figures["unplaced"] += 1
        else:
            figures["added"] += 1
            new = {"sort": "sponsor", "who": "", "delivery": "unsure", "confidence": "high", "origin": "copy",
                   "why": WHY}
            result.append(placed(new, lines, start, end))
    if not claimed and not figures["added"]:
        return None, figures
    if figures["added"]:
        result.sort(key=lambda one: one["start"] if isinstance(one, dict) and is_time(one.get("start")) else math.inf)
    return dict(label, segments=result), figures


# MARK: Files

def read_text(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as handle:
            return handle.read()
    except FileNotFoundError:
        return None


def middle(values):
    ordered = sorted(values)
    half = len(ordered) // 2
    return ordered[half] if len(ordered) % 2 else (ordered[half - 1] + ordered[half]) / 2


def snap_folder(folder, labels, out, say):
    """Writes every label of <folder>/<labels> into <folder>/<out>, snapped when it can be, and
    says what it did. Returns the totals."""
    names = sorted(name for name in os.listdir(os.path.join(folder, labels)) if LABEL_FILE.match(name))
    os.makedirs(os.path.join(folder, out), exist_ok=True)
    total = {"labels": len(names), "no_truth": 0, "agreed": 0, "compared": 0, "moved": [], "added": 0,
             "short": 0, "unplaced": 0, "joined": 0}
    for name in names:
        identifier = name[:-5]
        with open(os.path.join(folder, labels, name), "rb") as handle:
            raw = handle.read()
        new = None
        try:
            label = json.loads(raw.decode("utf-8"))
            if not isinstance(label, dict) or not isinstance(label.get("segments"), list):
                raise ValueError("it is not a label")
        except ValueError as error:
            say("The label of %s could not be read (%s), so it was copied as it is." % (identifier, error))
        else:
            truth = read_text(truth_path(folder, identifier))
            try:
                stretches = None if truth is None else read_truth(truth)
            except ValueError as error:
                say("The comparison of %s was not used: its truth file is not two times to a line (%s)."
                    % (identifier, error))
                stretches = None
            if truth is None:
                total["no_truth"] += 1
            elif stretches is not None:
                total["compared"] += 1
                total["agreed"] += 0 if stretches else 1
                lines = seg.read_transcript(read_text(os.path.join(folder, "transcripts", identifier + ".txt")) or "")
                new, figures = snap_label(label, stretches, lines)
                for key in ("added", "short", "unplaced", "joined"):
                    total[key] += figures[key]
                total["moved"] += figures["moved"]
        if new is None:
            save_bytes(os.path.join(folder, out, name), raw)
        else:
            write_json(os.path.join(folder, out, name), new)
    for name in os.listdir(os.path.join(folder, out)):
        if LABEL_FILE.match(name) and name not in names:
            os.remove(os.path.join(folder, out, name))
    return total


def report(total, labels, out, say):
    if not total["labels"]:
        say("No labels in %s yet, so nothing was written. Mark the ads first." % labels)
        return
    say("Wrote %d labels into %s. Claude's own labels in %s were not changed."
        % (total["labels"], out, labels))
    if total["no_truth"]:
        say("%d had no second download and were copied as they were." % total["no_truth"])
    if total["compared"]:
        say("%d were compared with a second download." % total["compared"])
    if total["agreed"]:
        say("In %d of those both downloads got the same ads, so no stretch differs and nothing is "
            "learned from them. That is common." % total["agreed"])
    if total["moved"]:
        say("Borders moved: %d (median %.1f s)." % (len(total["moved"]), middle(total["moved"])))
    else:
        say("No border moved.")
    unmarked = total["added"] + total["short"] + total["unplaced"]
    parts = ["%d added as sponsor" % total["added"]]
    if total["short"]:
        parts.append("%d under 10 s, left out" % total["short"])
    if total["unplaced"]:
        parts.append("%d where the transcript does not reach, left out" % total["unplaced"])
    say("Stretches Claude had not marked: %d (%s)." % (unmarked, ", ".join(parts)))
    if total["joined"]:
        say("%d labels were part of the same stretch as another one and were joined into it."
            % total["joined"])


def main(argv=None, say=print):
    parser = argparse.ArgumentParser(description="Moves Claude's label borders onto the stretches "
                                     "where two downloads of an episode differ.")
    parser.add_argument("--folder", default=FOLDER)
    parser.add_argument("--labels", default=LABELS)
    parser.add_argument("--out", default=SNAPPED)
    args = parser.parse_args(argv)
    folder = os.path.expanduser(args.folder)
    for name in (args.labels, args.out):
        if not FOLDER_NAME.match(name):
            say("%r is not a plain folder name." % name)
            return 2
    if args.labels == args.out:
        say("The folder for the snapped labels must not be the folder of Claude's labels.")
        return 2
    if not os.path.isdir(os.path.join(folder, args.labels)):
        say("There are no labels in %s. Mark the ads first." % os.path.join(folder, args.labels))
        return 2
    try:
        total = snap_folder(folder, args.labels, args.out, say)
    except OSError as error:
        say("Could not write to %s: %s" % (os.path.join(folder, args.out), error))
        return 2
    report(total, args.labels, args.out, say)
    return 0


if __name__ == "__main__":
    sys.exit(main())
