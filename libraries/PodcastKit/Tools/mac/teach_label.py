#!/usr/bin/env python3
"""Has Claude mark every advertisement and promotion in the transcripts of the teaching run, one
episode at a time, and saves one label file per episode.

Standard library only. It reads <folder>/episodes.json (written by the gather step) and
<folder>/transcripts/<id>.txt, and writes <folder>/<labels>/<id>.json as soon as each episode is
done. An episode that already has a label is not asked again, so a stopped run carries on where it
stopped. Each episode is one or a few `claude -p` runs, set up the way the app's Swift code
(ClaudeCodeTransport) sets them up (see teach_claude.py), so it runs on the Claude plan this Mac
is signed in to and shares its usage allowance. Nothing is sent anywhere else.

  teach_label.py [--folder F] [--labels labels] [--model NAME] [--limit N] [--cap DOLLARS]
                 [--budget NAME] [--reserve DOLLARS] [--unknown-cost DOLLARS] [--retry-failed] [--yes] [--only-exam]
                 [--only-ahead] [--between START-END] [--wait-hours H]

Without --yes it says what it is about to do and waits for you to type yes. It stops when --limit
episodes have been tried (one that failed counts, because it was sent and cost something), when the cost so far (every call counts, also the ones that failed) reaches
--cap, when Claude says the usage limit is reached or it is not signed in, or after three
episodes in a row that had never failed before failed. Failures are remembered in failures.json:
episodes that never failed come first, an episode that failed three times is left out (--retry-failed
asks for those again) and the closing lines say how many.

--only-ahead marks only the episodes in ahead.json (the nightly read-ahead, teach_ahead.py).
--reserve DOLLARS is what the next call is expected to cost: the cap is checked as if that much were
already spent, so the run stops before a call that would pass the cap and says so (default 0, the
cap is then only checked against what has been spent). A call whose cost is not known (it timed out,
died without a result or printed no cost, though it may have used the plan's allowance) is counted
as that much too, so it cannot pass the cap unseen; with no --reserve it counts nothing, as before.
--unknown-cost DOLLARS is what such a call is counted as instead of the reserve (default: the reserve).
Every call that cost something is written in the --budget file at once, not after the episode.
--only-exam marks only the episodes in exam.json (the sealed exam, see teach_exam.py), in its order.
--labels labels-second with --only-exam --limit 15 is how some of them are marked a second time:
only an exam episode that already has a first label is marked again, and the limit is the number of
exam episodes with a second label in all, those already held included.
--between 23-7 gives the local clock hours in which it may work (it may cross midnight). The clock is
checked before every call to Claude (each part of an episode and each retry), and outside the hours
it waits in steps of at most ten minutes until they begin. --wait-hours H: when Claude says the usage
limit is reached it does not stop but waits 30 minutes and tries the same episode again, asking
only for the parts of it that are still missing, for at most H hours of waiting in all, then stops
as below. Waiting for the allowance is not a failure of the episode. Not being signed in stops at
once. --cap is checked before every call, and is the cost limit of this one run. With --budget NAME
it is the limit of all the runs together under that name (see teach_budget.py).

Exit code: 0 everything waiting was marked, there was nothing to do, or --limit was reached;
2 a set-up problem, or another run is working in the folder; 3 stopped early because the usage
limit wait ran out or Claude is not signed in; 4 you did not type yes; 5 the cap or the budget is
reached; 6 stopped early because three episodes in a row failed.

Run the tests: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import argparse
import math
import os
import subprocess
import sys
import time
from datetime import datetime

import teach_budget
import teach_night
import teach_segments as seg
from teach_ahead_set import ahead_ids
from teach_budget import CapReached
from teach_claude import (EXTRA_FOLDERS, SignedOut, UsageLimit, ask_claude, find_claude,
                          is_signed_out)
from teach_failures import IN_A_ROW, Failures, given_up_line
from teach_label_files import (candidates, cap_text, counts_text, held_second,  # noqa: F401
                               waiting)
from teach_store import FOLDER, Busy, Problem, require_manifest, run_lock, write_json  # noqa: F401
from teach_words import switched_on, word_ends

DEFAULT_MODEL = "claude-opus-5-5"
NOT_CONFIRMED = 4
CAP_REACHED = 5
FAILED_IN_A_ROW = 6
STOP_CODES = {"usage": 3, "cap": CAP_REACHED, "failures": FAILED_IN_A_ROW}


# MARK: Marking

def label_episode(entry, lines, model, ask, limit=seg.PART_CHARS, now=time.time, kept=None, ends=None):
    """The label for one episode. `ask(prompt)` returns {"text", "cost"}. An answer that cannot be
    read is asked for once more; the second failure raises ValueError. `kept` is a dict that holds
    the answered parts, so that trying the episode again asks only for the missing ones. `ends` is
    the exact end of each line when the episode has its word times (teach_words.word_ends): a label
    then ends where its last word ends, not where the next line starts."""
    kept = {} if kept is None else kept
    segments, dropped, cost = [], 0, 0.0
    for first, last in seg.parts(lines, limit):
        if (first, last) not in kept:
            question = seg.prompt(entry["show"], entry["title"], lines, first, last)
            paid = 0.0
            for attempt in (1, 2):
                reply = ask(question)
                paid += reply["cost"]
                try:
                    found, lost = seg.parse(reply["text"], first, last)
                    break
                except ValueError:
                    if attempt == 2:
                        raise
            kept[(first, last)] = (found, lost, paid)
        found, lost, paid = kept[(first, last)]
        segments += found
        dropped += lost
        cost += paid
    return {"version": 1, "prompt": seg.PROMPT_VERSION, "model": model, "episode": entry["id"],
            "feed": entry["feed"], "show": entry["show"], "lines": len(lines),
            "length": seg.episode_length(entry, lines), "segments": seg.with_times(seg.merge(segments), lines, ends),
            "dropped": dropped, "cost": cost, "writtenAt": int(now() * 1000)}


def run(folder, labels, model, limit, cap, ask, say=print, retry_failed=False, only_exam=False,
        waiter=None, budget=None, only=None, reserve=0.0, unknown_cost=None):
    """Marks the waiting episodes. Returns {"done", "failed", "cost", "given_up", "stop",
    "reason"}; `stop` is None, "limit", "cap", "usage" or "failures". `cost` is what every call
    cost in this run, also the calls of episodes that failed or were stopped. The cap (with a
    `budget`, the budget's total, what it spent before this run included) is checked before every
    call. The `waiter` (teach_night.py) waits for the night hours before every call, and for the
    usage allowance to come back: the same episode is then tried again, with the parts already
    answered kept, and that waiting is not a failure of the episode. A `budget` is written down
    after every call that cost something (so a run that is stopped half way through an episode has
    not lost it), and the episode is counted when it is marked. With `only` (a set of ids) only
    those episodes are marked. The cap is checked with `reserve` added to what has been spent, and
    a call whose cost is not known (it timed out, or Claude printed no cost: `cost_unknown`) is
    counted as `reserve`, the cost of one call, because it may have used the plan's allowance. With
    no `reserve` such a call counts what it printed, which is nothing. `unknown_cost` counts such a
    call as that much instead of `reserve` (None means the reserve)."""
    waiter = waiter or teach_night.Waiter(say=say)
    items, given_up, empty = candidates(folder, labels, retry_failed, only_exam, only)
    for episode_id in empty:
        say("Skipping %s: its transcript has no usable lines." % episode_id)
    failures = Failures(folder, "label")
    result = {"done": 0, "failed": 0, "cost": 0.0, "given_up": len(given_up), "stop": None,
              "reason": ""}
    before = budget.dollars if budget else 0.0

    def charge(paid, unknown):
        """Counts what one call cost, and writes it in the budget at once."""
        if unknown:
            paid = max(paid, reserve if unknown_cost is None else unknown_cost)
        result["cost"] += paid
        if budget and paid > 0:
            budget.add(paid, 0)

    def counted(prompt):
        if cap is not None and before + result["cost"] + reserve >= cap:
            raise CapReached()
        waiter.for_window()
        try:
            reply = ask(prompt)
        except Exception as error:  # a failed call still cost what it cost
            charge(getattr(error, "cost", 0.0), getattr(error, "cost_unknown", False))
            raise
        charge(reply["cost"], reply.get("cost_unknown", False))
        return reply

    def settle(marked):
        """Counts the episode in the budget when it was marked (what its calls cost is in already)."""
        if budget and marked:
            budget.add(0.0, 1)

    def stopped(kind, reason):
        result["stop"], result["reason"] = kind, reason
        return result

    on = switched_on(folder)  # label ends at the last word only once word-ends-on is there
    in_a_row = 0
    attempted = held_second(folder, labels, only_exam)
    for number, (item, lines) in enumerate(items, 1):
        if limit is not None and attempted >= limit:
            return stopped("limit", "Stopped: the limit of %d episodes was reached." % limit)
        if cap is not None and before + result["cost"] + reserve >= cap:
            return stopped("cap", cap_text(budget, before + result["cost"], cap, reserve))
        name = "%d of %d: %s, %s" % (number, len(items), item["show"], item["title"])
        attempted += 1  # an episode that fails still cost a call, so it counts towards --limit
        kept = {}
        try:
            while True:
                try:
                    made = label_episode(item, lines, model, counted, kept=kept,
                                         ends=word_ends(folder, item["id"], lines) if on else None)
                    break
                except UsageLimit as error:
                    if isinstance(error, SignedOut) or is_signed_out(str(error)) \
                            or not waiter.for_allowance():
                        raise
        except CapReached:
            settle(False)
            return stopped("cap", cap_text(budget, before + result["cost"], cap, reserve))
        except UsageLimit as error:
            settle(False)
            return stopped("usage", "Stopped: Claude's usage limit is reached or it is not signed in "
                           "(%s). Everything done so far is saved." % str(error)[:150])
        except (RuntimeError, ValueError) as error:
            settle(False)
            result["failed"] += 1
            if failures.count(item["id"]) == 0:
                in_a_row += 1
            failures.failed(item["id"])
            say("%s: failed (%s)" % (name, str(error)[:150]))
            if in_a_row >= IN_A_ROW:
                return stopped("failures", "Stopped: %d episodes in a row failed." % IN_A_ROW)
            continue
        in_a_row = 0
        write_json(os.path.join(folder, labels, item["id"] + ".json"), made)
        failures.succeeded(item["id"])
        settle(True)
        result["done"] += 1
        say("%s: %s. Cost so far $%.2f." % (name, counts_text(made), result["cost"]))
    return result


# MARK: Command line

def positive_number(text):
    value = float(text)
    if not math.isfinite(value) or value <= 0:
        raise ValueError(text)
    return value


def non_negative_number(text):
    value = float(text)
    if not math.isfinite(value) or value < 0:
        raise ValueError(text)
    return value


def main(argv, ask_person=input, runner=subprocess.run, environment=None, say=print,
         extra_folders=EXTRA_FOLDERS, clock=datetime.now, sleep=time.sleep):
    environment = dict(os.environ if environment is None else environment)
    parser = argparse.ArgumentParser(prog="teach_label.py")
    parser.add_argument("--folder", default=FOLDER)
    parser.add_argument("--labels", default="labels")
    parser.add_argument("--model", default=DEFAULT_MODEL)
    parser.add_argument("--limit", type=int)
    parser.add_argument("--cap")
    parser.add_argument("--budget")
    parser.add_argument("--retry-failed", action="store_true")
    parser.add_argument("--yes", action="store_true")
    parser.add_argument("--only-exam", action="store_true")
    parser.add_argument("--only-ahead", action="store_true")
    parser.add_argument("--reserve", default="0")
    parser.add_argument("--unknown-cost")
    parser.add_argument("--between")
    parser.add_argument("--wait-hours")
    options = parser.parse_args(argv)
    folder = os.path.expanduser(options.folder)
    try:
        cap = positive_number(options.cap) if options.cap is not None else None
        if options.limit is not None and options.limit < 1:
            raise ValueError("limit")
    except ValueError:
        say("The --cap must be a number of dollars above zero and the --limit a whole number "
            "above zero.")
        return 2
    try:
        reserve = non_negative_number(options.reserve)
    except ValueError:
        say("The --reserve must be a number of dollars, zero or more.")
        return 2
    try:
        unknown_cost = non_negative_number(options.unknown_cost) if options.unknown_cost is not None else None
    except ValueError:
        say("The --unknown-cost must be a number of dollars, zero or more.")
        return 2
    if options.budget is not None and cap is None:
        say("A --budget needs a --cap: the cap is the budget's total for all the runs.")
        return 2
    try:
        window = teach_night.parse_window(options.between) if options.between is not None else None
        hours = positive_number(options.wait_hours) if options.wait_hours is not None else None
    except ValueError:
        say("The --between must be two clock hours like 23-7 (not the same hour twice) and the "
            "--wait-hours a number of hours above zero.")
        return 2
    waiter = teach_night.Waiter(window, hours, clock, sleep, say)
    try:
        require_manifest(folder)
        with run_lock(folder):
            return marking(folder, options, cap, ask_person, runner, environment, say, extra_folders,
                           waiter, reserve, unknown_cost)
    except Busy as error:
        say(str(error))
        return 2
    except Problem as error:
        say(str(error))
        return 2


def marking(folder, options, cap, ask_person, runner, environment, say, extra_folders, waiter,
            reserve=0.0, unknown_cost=None):
    """Everything main does once the folder is locked."""
    budget = teach_budget.Budget(folder, options.budget, cap) if options.budget is not None else None
    only = ahead_ids(folder) if options.only_ahead else None
    items, given_up, _ = candidates(folder, options.labels, options.retry_failed, options.only_exam,
                                    only)
    if not items:
        say("Nothing to do: every %sepisode with a transcript already has a label."
            % ("exam " if options.only_exam else ""))
        if given_up:
            say(given_up_line(len(given_up)))
        return 0
    claude = find_claude(environment, extra_folders)
    if claude is None:
        say("Claude Code was not found. Install it and sign in once by running `claude`.")
        return 2
    room = options.limit - held_second(folder, options.labels, options.only_exam) \
        if options.limit else None
    if room is not None and room < 1:
        say("Nothing to do: the limit of %d episodes is already reached." % options.limit)
        return 0
    if budget and budget.left() <= reserve:
        say(budget.line())
        say("The budget is spent. Nothing more is marked under it.")
        return CAP_REACHED
    chosen = items[:room] if room else items
    characters = sum(len(text) for _, lines in chosen for _, text in lines)
    say("%d episodes are waiting to be marked (%d this run), with %s."
        % (len(items), len(chosen), options.model))
    say("That is roughly {:,} tokens to read (an estimate: characters divided by 4)."
        .format(characters // 4))
    say("This uses the Claude plan this Mac is signed in to and shares its usage allowance.")
    if options.only_exam:
        say("Only the episodes of the sealed exam are marked.")
    if waiter.window == (0, 24):
        say("It marks at any hour.")
    elif waiter.window:
        say("It marks only between %s, local time, and waits outside those hours."
            % teach_night.window_text(waiter.window))
    if options.wait_hours is not None:
        say("When the usage allowance is used up it waits and tries again, for up to %g hours in all."
            % float(options.wait_hours))
    if budget:
        say(budget.line())
    elif cap is not None:
        say("The cost of this run is capped at $%.2f." % cap)
    if not options.yes:
        try:
            typed = ask_person("Type yes to start: ")
        except EOFError:
            typed = ""
        if typed.strip().lower() != "yes":
            say("Nothing was marked, because you did not type yes.")
            return NOT_CONFIRMED

    def ask(prompt):
        return ask_claude(seg.SYSTEM, prompt, options.model, claude, runner=runner,
                          environment=environment)

    result = run(folder, options.labels, options.model, options.limit, cap, ask, say=say,
                 retry_failed=options.retry_failed, only_exam=options.only_exam, waiter=waiter,
                 budget=budget, only=only, reserve=reserve, unknown_cost=unknown_cost)
    say("Marked %d episodes (%d failed). Cost as Claude counts it: $%.2f."
        % (result["done"], result["failed"], result["cost"]))
    if result["reason"]:
        say(result["reason"])
    if budget:
        say(budget.line())
    if result["given_up"]:
        say(given_up_line(result["given_up"]))
    return STOP_CODES.get(result["stop"], 0)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
