#!/usr/bin/env python3
"""The show playbook (milestone Z22): Claude reads each show's marked TRAINING episodes once and
writes the show's handoff lines into ads, its return lines, its named sponsored pieces and the
hosts' own plugs, as short phrases. Then a replay on the shelf says whether the phrases help.

Standard library only.

  teach_playbook.py build  <teaching folder> [--cap 15] [--reserve 0.60] [--min-episodes 3] [--yes]
  teach_playbook.py replay <teaching folder> --dump FILE

build sends one request for each show, over the episodes teach_cues.py learns from: marked, not on
the shelf, not in the sealed exam, no repeat of either. Each break goes with the lines just around
its start and its end. Claude's phrases are kept only when they are in the lines it was shown (a
phrase it made up is dropped and counted) and are saved as lowercase words in <folder>/playbook.json,
one entry for each show, after every show. The file holds transcript words: it stays on this Mac and
is never committed. The cap is a hard one, at most 15 dollars, checked before every request, and the
cost is saved in marking-spend.json (budget "playbook") right after every answer; a stopped or killed
run has lost nothing, and the next run goes on with the shows that have no entry yet. Shows go in
the order of their number of training episodes, the biggest first.

replay is in teach_playbook_replay.py.

Exit code: 0 done, 2 a set-up problem, 3 Claude's usage limit or not signed in, 4 you did not type
yes, 5 the cap is reached, 6 three shows in a row failed.

Run the tests: python3 -m pytest test_teach_playbook.py -q"""
import argparse
import json
import os
import subprocess
import sys
import time
from bisect import bisect_left

import teach_budget
import teach_cues
import teach_segments as seg
from teach_budget import CapReached
from teach_claude import EXTRA_FOLDERS, UsageLimit
from teach_feed import feed_key
from teach_features import tokens
from teach_label import DEFAULT_MODEL
from teach_paid import (CAP_REACHED, FAILED_IN_A_ROW, IN_A_ROW, NOT_CONFIRMED, USAGE_STOP,
                        Spender, claude_asker)
from teach_store import FOLDER, Busy, Problem, require_manifest, run_lock, write_json

FILE = "playbook.json"
BUDGET = "playbook"
HARD_CAP = 15.0
KINDS = ("handoffs", "returns", "segments", "plugs")
MIN_WORDS, MAX_WORDS, MOST_PHRASES = 2, 8, 12
PROMPT_CHARS = 60000  # about 15,000 tokens of lines for each show
MOST_EPISODES = 12
CONTEXT = 6  # lines shown before a break's start and after its end
INSIDE = 3  # lines shown at the start and at the end of the break itself
SYSTEM = """You learn how one podcast show moves into and out of advertisements and promotions, from examples marked by hand.

You get several episodes of one show. For each marked break you see the lines just before its start, its first lines, its last lines and the lines just after it. A line inside a break starts with ">". A speech recogniser wrote the lines: names can be misspelt and nothing says who is speaking.

Write short phrases, copied word for word from the lines you were given (2 to 8 words each, no more than 12 in a list), that this show repeats and that a player could use as a cue:
- "handoffs": what the hosts say just before an advertisement or promotion begins ("a word from our sponsors").
- "returns": what the hosts say when they come back ("and we're back").
- "segments": the names of sponsored pieces the show has ("the Acme minute"), as they are said.
- "plugs": how the hosts start a plug for their own things: another show, a live date, a newsletter, a membership.

Leave a list empty when the examples show nothing the show repeats. Never write a phrase that you did not read in the lines.

Answer with one JSON object and nothing else, in this shape:
{"handoffs": ["..."], "returns": ["..."], "segments": ["..."], "plugs": ["..."]}"""


# MARK: What a show is shown

def break_lines(times, spans):
    """[(first, last)] line indexes (from 0) of each break of the sorted ad spans."""
    found = []
    for start, end in teach_cues.joined(spans):
        first = min(bisect_left(times, start - 0.5), len(times) - 1)
        last = max(bisect_left(times, end - 0.5) - 1, first)
        found.append((first, last))
    return found


def shown_indexes(first, last, count):
    """The line indexes shown for one break: around its start and around its end."""
    around = set(range(max(first - CONTEXT, 0), min(first + INSIDE, last + 1)))
    around |= set(range(max(last - INSIDE + 1, first), min(last + CONTEXT + 1, count)))
    return sorted(around)


def episode_text(entry, lines, spans):
    """(the text shown for one episode, the lines in it), or None when it has no break."""
    times = [t for t, _ in lines]
    marked = break_lines(times, spans)
    if not marked:
        return None
    text, shown = "Episode: %s\n" % entry["title"], []
    for number, (first, last) in enumerate(marked, 1):
        text += "Break %d:\n" % number
        before = None
        for index in shown_indexes(first, last, len(lines)):
            if before is not None and index != before + 1:
                text += "  ...\n"
            mark = ">" if first <= index <= last else " "
            text += "%s [%s] %s\n" % (mark, seg.clock(lines[index][0]), lines[index][1])
            shown.append(lines[index][1])
            before = index
    return text, shown


def show_prompt(name, episodes):
    """(the request, the lines shown) for one show: its newest episodes first, until the text is
    as long as PROMPT_CHARS allows."""
    ordered = sorted(episodes, key=lambda e: (-(e[0]["published"] or 0), e[0]["id"]))
    text, shown = "Show: %s\n\n" % name, []
    used = 0
    for entry, lines, spans in ordered[:MOST_EPISODES]:
        made = episode_text(entry, lines, spans)
        if made is None:
            continue
        if used and used + len(made[0]) > PROMPT_CHARS:
            break
        text += made[0] + "\n"
        shown += made[1]
        used += len(made[0])
    return text, shown


# MARK: Claude's answer

def norm(text):
    return " ".join(tokens(text))


def clean(answer_text, shown):
    """({"handoffs", "returns", "segments", "plugs"}, dropped) from Claude's answer. A phrase stays
    only when it has 2 to 8 words and lies within one of the lines shown; it is saved as lowercase
    words. Raises ValueError when the answer holds no JSON object."""
    found = seg.find_object(answer_text)
    if found is None:
        raise ValueError("the answer holds no JSON object")
    lines = [" %s " % norm(text) for text in shown]
    out, dropped = {}, 0
    for kind in KINDS:
        items = found.get(kind, [])
        if not isinstance(items, list):
            dropped += 1
            items = []
        kept = []
        for item in items:
            words = norm(item) if isinstance(item, str) else ""
            count = len(words.split())
            if not MIN_WORDS <= count <= MAX_WORDS or not any(" %s " % words in line for line in lines):
                dropped += 1
            elif words not in kept and len(kept) < MOST_PHRASES:
                kept.append(words)
        out[kind] = kept
    return out, dropped


# MARK: Run

def read_playbook(folder):
    """The shows of playbook.json, [] when there is none. Raises Problem when it is damaged."""
    path = os.path.join(folder, FILE)
    if not os.path.exists(path):
        return []
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, ValueError):
        data = None
    if not isinstance(data, dict) or data.get("version") != 1 or not isinstance(data.get("shows"), list):
        raise Problem("%s is damaged, so what was made is not known. Fix it or move it away, and run "
                      "again." % path)
    return data["shows"]


def save_playbook(folder, shows, now=time.time):
    write_json(os.path.join(folder, FILE), {
        "version": 1, "writtenAt": int(now() * 1000),
        "shows": sorted(shows, key=lambda s: s["feed"])})


def build(folder, ask, budget, cap, reserve, say=print, minimum=3, labels="labels"):
    """Asks for the playbook of each show that has none yet. Returns {"done", "failed", "skipped",
    "cost", "stop"}; `stop` is None, "cap", "usage" or "failures"."""
    spender = Spender(ask, budget, cap, reserve)
    shows = read_playbook(folder)
    have = {feed_key(s["feed"]) for s in shows}
    training, _ = teach_cues.teaching_episodes(folder, labels, require_manifest(folder), say)
    groups = {}
    for one in training:
        groups.setdefault(feed_key(one[0]["feed"]), []).append(one)
    order = sorted(groups, key=lambda key: (-len(groups[key]), key))
    result = {"done": 0, "failed": 0, "skipped": 0, "cost": 0.0, "stop": None}
    in_a_row = 0
    for key in order:
        group = groups[key]
        if key in have:
            continue
        if len(group) < minimum:
            result["skipped"] += 1
            continue
        name = group[0][0]["show"]
        text, shown = show_prompt(name, group)
        try:
            reply = spender(text)
            phrases, dropped = clean(reply["text"], shown)
        except CapReached:
            result["stop"] = "cap"
            break
        except UsageLimit:
            result["stop"] = "usage"
            break
        except (RuntimeError, ValueError) as error:
            result["failed"] += 1
            in_a_row += 1
            say("%s: failed (%s)" % (name, str(error)[:150]))
            if in_a_row >= IN_A_ROW:
                result["stop"] = "failures"
                break
            continue
        in_a_row = 0
        shows.append(dict(phrases, feed=group[0][0]["feed"], show=name, episodes=len(group),
                          dropped=dropped, cost=round(reply["paid"], 6)))
        save_playbook(folder, shows)
        budget.add(0.0, 1)
        result["done"] += 1
        say("%s: %d handoffs, %d returns, %d segments, %d plugs, $%.2f." % (
            name, *(len(phrases[k]) for k in KINDS), reply["paid"]))
    result["cost"] = spender.spent
    return result


# MARK: Command line

STOPS = {"usage": USAGE_STOP, "cap": CAP_REACHED, "failures": FAILED_IN_A_ROW}


def main(argv, ask_person=input, runner=subprocess.run, environment=None, say=print,
         extra_folders=EXTRA_FOLDERS):
    parser = argparse.ArgumentParser(prog="teach_playbook.py")
    parser.add_argument("command", choices=["build", "replay"])
    parser.add_argument("folder", nargs="?", default=FOLDER)
    parser.add_argument("--cap", type=float, default=HARD_CAP)
    parser.add_argument("--reserve", type=float, default=0.60)
    parser.add_argument("--min-episodes", type=int, default=3)
    parser.add_argument("--model", default=DEFAULT_MODEL)
    parser.add_argument("--dump")
    parser.add_argument("--yes", action="store_true")
    try:
        options = parser.parse_args(argv)
    except SystemExit as stop:
        return stop.code if isinstance(stop.code, int) else 2
    folder = os.path.expanduser(options.folder)
    if options.command == "replay":
        import teach_playbook_replay
        return teach_playbook_replay.main(folder, options.dump, say)
    if not 0 < options.cap <= HARD_CAP or options.reserve < 0 or options.min_episodes < 1:
        say("The --cap must be above 0 and at most %g dollars, the --reserve zero or more and "
            "--min-episodes a whole number above zero." % HARD_CAP)
        return 2
    environment = dict(os.environ if environment is None else environment)
    try:
        require_manifest(folder)
        with run_lock(folder):
            budget = teach_budget.Budget(folder, BUDGET, options.cap)
            ask = claude_asker(SYSTEM, options.model, environment, extra_folders, runner)
            if ask is None:
                say("Claude Code was not found. Install it and sign in once by running `claude`.")
                return 2
            say("Claude reads each show's marked training episodes once and writes its playbook.")
            say("This uses the Claude plan this Mac is signed in to. %s" % budget.line())
            if not options.yes and ask_person("Type yes to start: ").strip().lower() != "yes":
                say("Nothing was sent, because you did not type yes.")
                return NOT_CONFIRMED
            result = build(folder, ask, budget, options.cap, options.reserve, say,
                           options.min_episodes)
            say("Made %d show playbooks (%d failed, %d shows with too few episodes). Spent $%.2f this "
                "run. %s" % (result["done"], result["failed"], result["skipped"], result["cost"],
                             budget.line()))
            if result["stop"]:
                say("Stopped early: %s." % result["stop"])
            return STOPS.get(result["stop"], 0)
    except (Busy, Problem) as error:
        say(str(error))
        return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
