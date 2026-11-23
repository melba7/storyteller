"""The small helpers of the marking run (teach_label.py): which episodes are waiting for a label,
how many second labels are already held, and the lines it says about them.

Standard library only.

Run the tests: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import os

import teach_exam
import teach_segments as seg
from teach_failures import Failures
from teach_store import require_manifest


def waiting(folder, labels, only_exam=False):
    """([(entry, lines)], [ids with no usable lines]): the episodes in episodes.json order that
    have a transcript and no label yet. With `only_exam` only the episodes in exam.json, in its
    order, and for the second marking (`labels` is labels-second) only those that already have a
    first label. Raises Problem when episodes.json or exam.json is missing or damaged."""
    found, empty = [], []
    items = require_manifest(folder)
    if only_exam:
        by_id = {item["id"]: item for item in items}
        items = [by_id[i] for i in teach_exam.read_exam(folder) if i in by_id]
        if labels == teach_exam.SECOND:
            items = [item for item in items if teach_exam.has(folder, teach_exam.FIRST, item["id"])]
    for item in items:
        if os.path.exists(os.path.join(folder, labels, item["id"] + ".json")):
            continue
        try:
            with open(os.path.join(folder, "transcripts", item["id"] + ".txt"),
                      encoding="utf-8", errors="replace") as f:
                lines = seg.read_transcript(f.read())
        except OSError:
            continue
        if lines:
            found.append((item, lines))
        else:
            empty.append(item["id"])
    return found, empty


def held_second(folder, labels, only_exam):
    """How many exam episodes already have a label in the second marking's folder (0 for any other
    marking): they count towards its --limit."""
    if not (only_exam and labels == teach_exam.SECOND):
        return 0
    return sum(1 for i in teach_exam.read_exam(folder) if teach_exam.has(folder, labels, i))


def counts_text(label):
    """"2 sponsor, 1 host_ask", or "no stretches found"."""
    parts = ["%d %s" % (n, sort) for sort in seg.SORTS
             for n in [sum(1 for s in label["segments"] if s["sort"] == sort)] if n]
    return ", ".join(parts) or "no stretches found"


def candidates(folder, labels, retry_failed, only_exam=False):
    """(ready, given_up, empty): the waiting episodes in the order to work in (never failed first,
    then fewer failures first), the ones left out after three failures, and ids with no lines."""
    items, empty = waiting(folder, labels, only_exam)
    ready, given_up = Failures(folder, "label").split(items, retry_failed, lambda item: item[0]["id"])
    return ready, given_up, empty


def cap_text(budget, spent, cap):
    if budget:
        return ("Stopped: the budget \"%s\" has spent $%.2f of $%.2f. Nothing more is marked under it."
                % (budget.name, spent, cap))
    return "Stopped: the cost so far, $%.2f, reached the cap of $%.2f." % (spent, cap)
