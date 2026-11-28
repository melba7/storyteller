#!/usr/bin/env python3
"""Claude's second look at the start and end of every marked break (milestone Z18), as a paid TEST
on the episodes that were downloaded twice.

Standard library only. For each such episode that has Claude's labels and a transcript, and is not
in the sealed exam, Claude gets the transcript lines from 60 s before to 60 s after a break's start
and the same around its end, with the edge the label has now, and says which line really starts
and ends the ad (or "keep"). The moved labels go to a NEW folder, <folder>/labels-second-look/;
<folder>/labels is never changed. The answer key does not come from Claude: copies/<id>.truth.txt
holds the exact places where the two downloads differ (teach_copies.py). Only breaks that lie in
such a place are sent, because only they can be scored.

  teach_second_look.py test <teaching folder> [--cap 5] [--reserve 0.20] [--limit N] [--yes]

The cap is a hard one: at most 5 dollars. It is checked before every request and the cost is saved
in marking-spend.json (budget "second-look") right after every answer, so a stopped or killed run
has lost nothing and the next run goes on with what is left. Episodes go in the order of their ids.
An episode is written only when all its breaks were asked, so a run that stops at the cap leaves
that one episode for the next run. When the run ends it writes <folder>/second-look-report.json:
edges within 1, 2 and 5 seconds of the exact ones, before and after, by kind of break, and the cost
for each episode. It holds no transcript words.

Exit code: 0 done, 2 a set-up problem, 3 Claude's usage limit or not signed in, 4 you did not type
yes, 5 the cap is reached, 6 three episodes in a row failed.

Run the tests: python3 -m pytest test_teach_second_look.py -q"""
import argparse
import copy
import json
import math
import os
import subprocess
import sys
from bisect import bisect_left, bisect_right

import teach_budget
import teach_segments as seg
from teach_budget import CapReached
from teach_claude import EXTRA_FOLDERS, UsageLimit
from teach_exam import read_exam
from teach_label import DEFAULT_MODEL
from teach_overlap import same_episode_ids
from teach_second_look_report import OUT, REPORT, report  # noqa: F401
from teach_paid import (CAP_REACHED, FAILED_IN_A_ROW, IN_A_ROW, NOT_CONFIRMED, USAGE_STOP,
                        Spender, claude_asker)
from teach_store import FOLDER, Busy, Problem, require_manifest, run_lock, write_json
from teach_train import valid_label
from teach_truth import LABELS, overlap, read_truth, truth_path

BUDGET = "second-look"
HARD_CAP = 5.0
WINDOW = 60.0
JOIN = 1.0
LONGEST = 300.0  # a stretch longer than this is not an inserted ad (teach_snap.py)
SORTS = ("sponsor", "network_promo", "host_ask")
CONFIDENCE = ("high", "medium")
SYSTEM = """You check the edges of one advertisement or promotion in a podcast transcript. A speech recogniser wrote the transcript: names can be misspelt and nothing says who is speaking. Every line starts with its number and the time it begins.

You get the lines around the start of the stretch and the lines around its end, and the line numbers the stretch has now. They were found by a first pass and may be a few lines off: too early, too late, or the lead-in and the way back left out.

Say which line is the first line of the stretch and which line is its last line. Include the lines that lead into it ("we'll be right back", "first, a word from our sponsors") and out of it ("and we're back", "welcome back"). Leave out the show's own content before and after. If an edge is already right, or you cannot tell, answer "keep" for it.

Answer with one JSON object and nothing else: {"start": 21, "end": 28}. Each value is a line number taken from the lines you were given, or "keep"."""


# MARK: Breaks and the exact edges

def eligible(item):
    start, end = item.get("start"), item.get("end")
    return item.get("sort") in SORTS and item.get("confidence") in CONFIDENCE \
        and all(isinstance(x, (int, float)) and not isinstance(x, bool) for x in (start, end)) \
        and end > start


def breaks_of(segments):
    """The breaks of a label: segments of the ad sorts with high or medium confidence, those within
    1 second of each other joined. A break is {"members": [indexes], "start", "end", "sort"}, the
    sort that of its first segment."""
    found = []
    for index in sorted((i for i, s in enumerate(segments) if eligible(s)),
                        key=lambda i: segments[i]["start"]):
        item = segments[index]
        if found and item["start"] - found[-1]["end"] <= JOIN:
            found[-1]["members"].append(index)
            found[-1]["end"] = max(found[-1]["end"], item["end"])
        else:
            found.append({"members": [index], "start": item["start"], "end": item["end"],
                          "sort": item["sort"]})
    return found


def exact_edges(breaks, stretches):
    """For each break {"start": second or None, "end": second or None}: a break belongs to the
    stretch it shares the most with, when that is half of the break or more. Of the breaks in one
    stretch only the first has the stretch's start and only the last its end."""
    owner = []
    for one in breaks:
        best, most = None, 0.0
        for number, (start, end) in enumerate(stretches):
            shared = overlap(one["start"], one["end"], start, end)
            if shared > most:
                best, most = number, shared
        owner.append(best if best is not None and most * 2 >= one["end"] - one["start"] else None)
    exact = [{"start": None, "end": None} for _ in breaks]
    for number, (start, end) in enumerate(stretches):
        mine = [i for i, o in enumerate(owner) if o == number]
        if mine:
            exact[mine[0]]["start"] = start
            exact[mine[-1]]["end"] = end
    return exact


# MARK: One break

def line_numbers(times, one):
    """The numbers (from 1) of the first and the last line of a break."""
    first = max(bisect_right(times, one["start"] + 0.5), 1)
    return first, max(bisect_left(times, one["end"] - 0.5), first)


def window(times, second):
    """The numbers of the first and the last line from a minute before the second to a minute after."""
    return bisect_left(times, second - WINDOW) + 1, bisect_right(times, second + WINDOW)


def lines_text(lines, first, last):
    return "".join("%d [%s] %s\n" % (n, seg.clock(lines[n - 1][0]), lines[n - 1][1])
                   for n in range(first, last + 1))


def question(entry, lines, one, times):
    first, last = line_numbers(times, one)
    around_start, around_end = window(times, one["start"]), window(times, one["end"])
    return ("Show: %s\nEpisode: %s\n\nThe stretch now starts at line %d [%s] and ends with line %d [%s].\n\n"
            "Lines around its start (lines %d to %d):\n%s\nLines around its end (lines %d to %d):\n%s"
            % (entry["show"], entry["title"], first, seg.clock(times[first - 1]), last,
               seg.clock(times[last - 1]), *around_start, lines_text(lines, *around_start),
               *around_end, lines_text(lines, *around_end)))


def answer_lines(text, one, times):
    """(start line, end line) from Claude's answer; None for an edge that is kept, not a whole
    number, outside the lines it was shown, or the same as now. When the new start would come
    after the new end neither moves."""
    found = seg.find_object(text) or {}
    now = line_numbers(times, one)
    chosen = []
    for key, current, span in (("start", now[0], window(times, one["start"])),
                               ("end", now[1], window(times, one["end"]))):
        value = found.get(key)
        ok = seg.whole(value) and span[0] <= value <= span[1] and value != current
        chosen.append(value if ok else None)
    if (chosen[0] or now[0]) > (chosen[1] or now[1]):
        return None, None
    return tuple(chosen)


def new_second(lines, number, end):
    """The second a line number stands for: its start, or for an end the start of the next line."""
    if not end:
        return round(lines[number - 1][0], 1)
    return round(lines[number][0] if number < len(lines) else lines[-1][0] + seg.LAST_LINE_SECONDS, 1)


def apply(segments, one, lines, start_line, end_line):
    """Moves the break's outer edges in `segments`. An edge that would reach into a segment that is
    not part of the break is left. Returns the break's new (start, end)."""
    members = one["members"]
    others = [s for i, s in enumerate(segments) if i not in members and "start" in s and "end" in s]
    low = max([s["end"] for s in others if s["end"] <= one["start"] + 1e-6] or [0.0])
    high = min([s["start"] for s in others if s["start"] >= one["end"] - 1e-6] or [math.inf])
    first, last = segments[members[0]], segments[members[-1]]
    start, end = one["start"], one["end"]
    if start_line is not None:
        second = new_second(lines, start_line, False)
        if low <= second < min(end, first["end"]):
            first["start"], first["first"], start = second, start_line, second
    if end_line is not None:
        second = new_second(lines, end_line, True)
        if max(start, last["start"]) < second <= high:
            last["end"], last["last"], end = second, end_line, second
    return start, end


# MARK: One episode and the run

def episode_inputs(folder, entry):
    """(lines, label, stretches) for an episode that can be looked at, or None."""
    identifier = entry["id"]
    try:
        with open(os.path.join(folder, "transcripts", identifier + ".txt"), encoding="utf-8") as f:
            lines = seg.read_transcript(f.read())
        with open(os.path.join(folder, LABELS, identifier + ".json"), encoding="utf-8") as f:
            label = json.load(f)
        with open(truth_path(folder, identifier), encoding="utf-8") as f:
            stretches = [s for s in read_truth(f.read()) if s[1] - s[0] <= LONGEST]
    except (OSError, ValueError):
        return None
    if not lines or not valid_label(label) or not stretches:
        return None
    return lines, label, stretches


def look_at(entry, lines, label, stretches, ask):
    """(the moved label, the episode's cost), or None when no break lies in a place the downloads
    differ. `ask(prompt)` is a Spender: it may raise CapReached or a failure, and then nothing is
    kept."""
    moved = copy.deepcopy(label)
    segments = moved["segments"]
    times = [t for t, _ in lines]
    breaks = breaks_of(label["segments"])
    exact = exact_edges(breaks, stretches)
    edges, cost, changed = [], 0.0, 0
    for one, wanted in zip(breaks, exact):
        if wanted["start"] is None and wanted["end"] is None:
            continue
        reply = ask(question(entry, lines, one, times))
        cost += reply["paid"]
        start_line, end_line = answer_lines(reply["text"], one, times)
        start, end = apply(segments, one, lines, start_line, end_line)
        changed += (start != one["start"]) + (end != one["end"])
        record = {"sort": one["sort"]}
        for name, before, after in (("start", one["start"], start), ("end", one["end"], end)):
            if wanted[name] is not None:
                record[name] = {"exact": wanted[name], "before": before, "after": after}
        edges.append(record)
    if not edges:
        return None
    moved["secondLook"] = {"version": 1, "cost": round(cost, 6), "asked": len(edges),
                           "moved": changed, "edges": edges}
    return moved, cost


def run(folder, ask, budget, cap, reserve, say=print, limit=None):
    """Looks at the waiting episodes. Returns {"done", "failed", "cost", "stop"}; `stop` is None,
    "limit", "cap", "usage" or "failures"."""
    spender = Spender(ask, budget, cap, reserve)
    entries = sorted(require_manifest(folder), key=lambda e: e["id"])
    by_id = {entry["id"]: entry for entry in entries}
    sealed = set(read_exam(folder))
    # An exam episode downloaded again under another id has the exam's words, so it is sealed too.
    sealed |= set(same_episode_ids(folder, by_id, sorted(i for i in sealed if i in by_id),
                                   [i for i in by_id if i not in sealed]))
    result = {"done": 0, "failed": 0, "cost": 0.0, "stop": None}
    tried = in_a_row = 0
    for entry in entries:
        identifier = entry["id"]
        if identifier in sealed or os.path.exists(os.path.join(folder, OUT, identifier + ".json")):
            continue
        found = episode_inputs(folder, entry)
        if found is None:
            continue
        if limit is not None and tried >= limit:
            result["stop"] = "limit"
            break
        tried += 1
        try:
            made = look_at(entry, *found, spender)
        except CapReached:
            result["stop"] = "cap"
            break
        except UsageLimit:
            result["stop"] = "usage"
            break
        except (RuntimeError, ValueError) as error:
            result["failed"] += 1
            in_a_row += 1
            say("%s: failed (%s)" % (identifier, str(error)[:150]))
            if in_a_row >= IN_A_ROW:
                result["stop"] = "failures"
                break
            continue
        in_a_row = 0
        if made is not None:
            write_json(os.path.join(folder, OUT, identifier + ".json"), made[0])
            budget.add(0.0, 1)
            result["done"] += 1
            say("%s: asked %d breaks, moved %d edges, $%.2f." % (
                identifier, made[0]["secondLook"]["asked"], made[0]["secondLook"]["moved"], made[1]))
    result["cost"] = spender.spent
    return result


# MARK: Command line

STOPS = {"usage": USAGE_STOP, "cap": CAP_REACHED, "failures": FAILED_IN_A_ROW}


def main(argv, ask_person=input, runner=subprocess.run, environment=None, say=print,
         extra_folders=EXTRA_FOLDERS):
    parser = argparse.ArgumentParser(prog="teach_second_look.py")
    parser.add_argument("command", choices=["test"])
    parser.add_argument("folder", nargs="?", default=FOLDER)
    parser.add_argument("--cap", type=float, default=HARD_CAP)
    parser.add_argument("--reserve", type=float, default=0.20)
    parser.add_argument("--limit", type=int)
    parser.add_argument("--model", default=DEFAULT_MODEL)
    parser.add_argument("--yes", action="store_true")
    try:
        options = parser.parse_args(argv)
    except SystemExit as stop:
        return stop.code if isinstance(stop.code, int) else 2
    if not 0 < options.cap <= HARD_CAP or options.reserve < 0 or (options.limit or 1) < 1:
        say("The --cap must be above 0 and at most %g dollars, the --reserve zero or more and the "
            "--limit a whole number above zero." % HARD_CAP)
        return 2
    folder = os.path.expanduser(options.folder)
    environment = dict(os.environ if environment is None else environment)
    try:
        require_manifest(folder)
        with run_lock(folder):
            budget = teach_budget.Budget(folder, BUDGET, options.cap)
            ask = claude_asker(SYSTEM, options.model, environment, extra_folders, runner)
            if ask is None:
                say("Claude Code was not found. Install it and sign in once by running `claude`.")
                return 2
            say("Claude looks again at the edges of the marked breaks in the episodes downloaded twice.")
            say("This uses the Claude plan this Mac is signed in to. %s" % budget.line())
            if not options.yes and ask_person("Type yes to start: ").strip().lower() != "yes":
                say("Nothing was sent, because you did not type yes.")
                return NOT_CONFIRMED
            try:
                result = run(folder, ask, budget, options.cap, options.reserve, say, options.limit)
            finally:
                report(folder, say)
            say("Done %d episodes (%d failed). Spent $%.2f this run. %s"
                % (result["done"], result["failed"], result["cost"], budget.line()))
            if result["stop"]:
                say("Stopped early: %s." % result["stop"])
            return STOPS.get(result["stop"], 0)
    except (Busy, Problem) as error:
        say(str(error))
        return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
