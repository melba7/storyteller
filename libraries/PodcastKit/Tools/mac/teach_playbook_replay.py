"""The replay of the show playbook (teach_playbook.py replay): what the bar says on the shelf before
and after the playbook's phrases are used as cue rules.

Standard library only. No evaluator of the phone can take extra phrases without a change in Swift
(the opening-line and return-line cues of AdCues.swift read ad-cues.json only), so this is the
simplest replay in Python over a score dump (`podcast-teach score <folder> --dump FILE`, which holds
for each episode what was found, the marked ads and the neutral stretches, no transcript words). It
scores with teach_bar.py, a port of the bar of AdBar.swift. The replay reads only the episodes on
the shelf; a dump line of an exam episode or of an episode off the shelf is left out.

The rules, from the show's phrases (a "cue line" is a transcript line that contains one of them):
- A skip that starts up to 60 s after a start cue line (a handoff, a segment name or a plug) starts
  at the nearest such line before it.
- A skip that ends up to 30 s before or after a return cue line, which lies more than 10 s after
  the skip's start, ends at that line.
- A start cue line with no skip within 15 s after it makes a new skip from the line to the first
  return cue line 10 to 180 s after it; with no such line nothing is added.
The limits were fixed before the replay and not tuned on the shelf.

Run the tests: python3 -m pytest test_teach_playbook.py -q"""
import json
import os
import time

import teach_bar as bar
import teach_segments as seg
from teach_exam import read_exam
from teach_feed import feed_key
from teach_features import tokens
from teach_playbook import read_playbook
from teach_shelf import read_shelf
from teach_store import Problem, write_json

FILE = "playbook-replay.json"
PULL, TRIM, EXTEND, NEAR, AFTER_MIN, AHEAD, MIN_AD = 60.0, 30.0, 30.0, 15.0, 10.0, 180.0, 10.0
KEEP_MORE = 4
SKIP_LEVELS = ("sure", "unsure")


def is_kept(passed_more, wrong_more):
    """Kept when at least 4 more breaks pass and no more skips land where there is no ad."""
    return passed_more >= KEEP_MORE and wrong_more <= 0


def cue_seconds(lines, phrases):
    """The seconds of the transcript lines that contain one of the phrases as whole words."""
    wanted = [" %s " % p for p in phrases]
    return [second for second, text in lines
            if any(p in " %s " % " ".join(tokens(text)) for p in wanted)]


def with_cues(skips, starts, returns):
    """The skips after the three rules above, sorted."""
    moved = []
    for start, end in skips:
        before = [c for c in starts if start - PULL <= c < start - 0.5]
        if before:
            start = max(before)
        near = [r for r in returns if end - TRIM <= r <= end + EXTEND and r > start + AFTER_MIN]
        if near:
            end = min(near, key=lambda r: abs(r - end))
        moved.append((start, end))
    for cue in starts:
        if any(s < cue + NEAR and e > cue for s, e in moved):
            continue
        back = [r for r in returns if cue + AFTER_MIN < r <= cue + AHEAD]
        if back:
            moved.append((cue, min(back)))
    return sorted(moved)


def add_up(total, one):
    total["breaks"] += one["breaks"]
    total["passed"] += one["passed"]
    total["noAdSkips"] += one["noAdSkips"]
    for cause, number in one["causes"].items():
        total["causes"][cause] = total["causes"].get(cause, 0) + number


def empty():
    return {"breaks": 0, "passed": 0, "causes": {}, "noAdSkips": 0}


def read_dump(path):
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, ValueError) as error:
        raise Problem("The score dump %s cannot be read: %s" % (path, error))
    if not isinstance(data, list):
        raise Problem("The score dump %s is not a list of episodes." % path)
    return data


def stretches(items):
    return [(float(i["start"]), float(i["end"])) for i in items]


def replay(folder, dump_path, say=print, now=time.time):
    """Scores the shelf episodes of the dump as they are and with the playbook's cue rules, writes
    playbook-replay.json and says the summary. Returns the result."""
    shelf, sealed = set(read_shelf(folder)), set(read_exam(folder))
    books = {feed_key(s["feed"]): s for s in read_playbook(folder)}
    result = {"before": empty(), "after": empty(), "episodes": 0, "byShow": {}}
    for item in read_dump(dump_path):
        try:
            identifier = item["id"]
            if identifier in sealed or identifier not in shelf:
                continue
            truth, maybe = stretches(item["truth"]), stretches(item["maybe"])
            skips = [(f["start"], f["end"]) for f in item["found"]
                     if f["confidence"] in SKIP_LEVELS and f["end"] > f["start"]]
            duration = float(item["duration"])
            book = books.get(feed_key(item["feed"]))
        except (KeyError, TypeError, ValueError):
            raise Problem("The score dump holds an episode that is not shaped as `score --dump` writes.")
        after_skips = skips
        if book:
            try:
                with open(os.path.join(folder, "transcripts", identifier + ".txt"), encoding="utf-8") as f:
                    lines = seg.read_transcript(f.read())
            except OSError:
                lines = []
            starts = cue_seconds(lines, book["handoffs"] + book["segments"] + book["plugs"])
            after_skips = with_cues(skips, starts, cue_seconds(lines, book["returns"]))
        before = bar.score(truth, maybe, skips, duration)
        after = bar.score(truth, maybe, after_skips, duration)
        result["episodes"] += 1
        for name, one in (("before", before), ("after", after)):
            add_up(result[name], one)
        show = result["byShow"].setdefault(item.get("show", ""), {"before": empty(), "after": empty()})
        add_up(show["before"], before)
        add_up(show["after"], after)
    more = result["after"]["passed"] - result["before"]["passed"]
    wrong = result["after"]["noAdSkips"] - result["before"]["noAdSkips"]
    result.update(passedMore=more, wrongSkipsMore=wrong, kept=is_kept(more, wrong),
                  writtenAt=int(now() * 1000), limits={"pull": PULL, "trim": TRIM, "extend": EXTEND,
                                                       "near": NEAR, "ahead": AHEAD},
                  evaluator="a Python replay over the score dump (teach_bar.py), because no "
                            "evaluator of the phone takes extra cue phrases without a change in Swift")
    write_json(os.path.join(folder, FILE), result)
    say("Playbook replay on %d shelf episodes (%s)." % (result["episodes"], result["evaluator"]))
    say("Breaks passed: %d of %d before, %d after (%+d). Skips where there is no ad: %d before, %d "
        "after (%+d)." % (result["before"]["passed"], result["before"]["breaks"],
                          result["after"]["passed"], more, result["before"]["noAdSkips"],
                          result["after"]["noAdSkips"], wrong))
    say("The rule to keep it: at least %d more breaks and no more wrong skips: %s."
        % (KEEP_MORE, "met" if result["kept"] else "not met"))
    return result


def main(folder, dump, say=print):
    """The replay command: exit code 0 it worked, 2 a set-up problem."""
    if not dump:
        say("replay needs --dump FILE, the file `podcast-teach score <folder> --dump FILE` writes.")
        return 2
    try:
        replay(folder, os.path.expanduser(dump), say)
    except Problem as error:
        say(str(error))
        return 2
    return 0
