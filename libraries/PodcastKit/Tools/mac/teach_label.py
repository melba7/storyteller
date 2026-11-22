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
                 [--retry-failed] [--yes]

Without --yes it says what it is about to do and waits for you to type yes. It stops when --limit
episodes have been tried (one that failed counts, because it was sent and cost something), when the cost so far (every call counts, also the ones that failed) reaches
--cap, when Claude says the usage limit is reached or it is not signed in, or after three
episodes in a row that had never failed before failed. Failures are remembered in failures.json:
episodes that never failed come first, an episode that failed three times is left out (--retry-failed
asks for those again) and the closing lines say how many.

Exit code: 0 everything waiting was marked, there was nothing to do, or --limit was reached;
2 a set-up problem, or another run is working in the folder; 3 stopped early; 4 you did not type yes.

Run the tests: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import argparse
import math
import os
import subprocess
import sys
import time

import teach_segments as seg
from teach_claude import EXTRA_FOLDERS, UsageLimit, ask_claude, find_claude
from teach_failures import IN_A_ROW, Failures, given_up_line
from teach_store import FOLDER, Busy, Problem, require_manifest, run_lock, write_json  # noqa: F401

DEFAULT_MODEL = "claude-opus-5-5"
NOT_CONFIRMED = 4


# MARK: Files

def waiting(folder, labels):
    """([(entry, lines)], [ids with no usable lines]): the episodes in episodes.json order that
    have a transcript and no label yet. Raises Problem when episodes.json is missing or damaged."""
    found, empty = [], []
    for item in require_manifest(folder):
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


# MARK: Marking

def label_episode(entry, lines, model, ask, limit=seg.PART_CHARS, now=time.time):
    """The label for one episode. `ask(prompt)` returns {"text", "cost"}. An answer that cannot be
    read is asked for once more; the second failure raises ValueError."""
    segments, dropped, cost = [], 0, 0.0
    for first, last in seg.parts(lines, limit):
        question = seg.prompt(entry["show"], entry["title"], lines, first, last)
        for attempt in (1, 2):
            reply = ask(question)
            cost += reply["cost"]
            try:
                found, lost = seg.parse(reply["text"], first, last)
                break
            except ValueError:
                if attempt == 2:
                    raise
        segments += found
        dropped += lost
    return {"version": 1, "prompt": seg.PROMPT_VERSION, "model": model, "episode": entry["id"],
            "feed": entry["feed"], "show": entry["show"], "lines": len(lines),
            "length": seg.episode_length(entry, lines), "segments": seg.with_times(seg.merge(segments), lines),
            "dropped": dropped, "cost": cost, "writtenAt": int(now() * 1000)}


def counts_text(label):
    """"2 sponsor, 1 host_ask", or "no stretches found"."""
    parts = ["%d %s" % (n, sort) for sort in seg.SORTS
             for n in [sum(1 for s in label["segments"] if s["sort"] == sort)] if n]
    return ", ".join(parts) or "no stretches found"


def candidates(folder, labels, retry_failed):
    """(ready, given_up, empty): the waiting episodes in the order to work in (never failed first,
    then fewer failures first), the ones left out after three failures, and ids with no lines."""
    items, empty = waiting(folder, labels)
    ready, given_up = Failures(folder, "label").split(items, retry_failed, lambda item: item[0]["id"])
    return ready, given_up, empty


def run(folder, labels, model, limit, cap, ask, say=print, retry_failed=False):
    """Marks the waiting episodes. Returns {"done", "failed", "cost", "given_up", "stop",
    "reason"}; `stop` is None, "limit", "cap", "usage" or "failures". `cost` is what every call
    cost, also the calls of episodes that failed or were stopped."""
    items, given_up, empty = candidates(folder, labels, retry_failed)
    for episode_id in empty:
        say("Skipping %s: its transcript has no usable lines." % episode_id)
    failures = Failures(folder, "label")
    result = {"done": 0, "failed": 0, "cost": 0.0, "given_up": len(given_up), "stop": None,
              "reason": ""}

    def counted(prompt):
        try:
            reply = ask(prompt)
        except Exception as error:  # a failed call still cost what it cost
            result["cost"] += getattr(error, "cost", 0.0)
            raise
        result["cost"] += reply["cost"]
        return reply

    in_a_row = 0
    attempted = 0
    for number, (item, lines) in enumerate(items, 1):
        stop = None
        if limit is not None and attempted >= limit:
            stop = ("limit", "Stopped: the limit of %d episodes was reached." % limit)
        elif cap is not None and result["cost"] >= cap:
            stop = ("cap", "Stopped: the cost so far, $%.2f, reached the cap of $%.2f."
                    % (result["cost"], cap))
        if stop:
            result["stop"], result["reason"] = stop
            return result
        name = "%d of %d: %s, %s" % (number, len(items), item["show"], item["title"])
        attempted += 1  # an episode that fails still cost a call, so it counts towards --limit
        try:
            made = label_episode(item, lines, model, counted)
        except UsageLimit as error:
            result["stop"] = "usage"
            result["reason"] = ("Stopped: Claude's usage limit is reached or it is not signed in "
                                "(%s). Everything done so far is saved." % str(error)[:150])
            return result
        except (RuntimeError, ValueError) as error:
            result["failed"] += 1
            if failures.count(item["id"]) == 0:
                in_a_row += 1
            failures.failed(item["id"])
            say("%s: failed (%s)" % (name, str(error)[:150]))
            if in_a_row >= IN_A_ROW:
                result["stop"] = "failures"
                result["reason"] = "Stopped: %d episodes in a row failed." % IN_A_ROW
                return result
            continue
        in_a_row = 0
        write_json(os.path.join(folder, labels, item["id"] + ".json"), made)
        failures.succeeded(item["id"])
        result["done"] += 1
        say("%s: %s. Cost so far $%.2f." % (name, counts_text(made), result["cost"]))
    return result


# MARK: Command line

def positive_number(text):
    value = float(text)
    if not math.isfinite(value) or value <= 0:
        raise ValueError(text)
    return value


def main(argv, ask_person=input, runner=subprocess.run, environment=None, say=print,
         extra_folders=EXTRA_FOLDERS):
    environment = dict(os.environ if environment is None else environment)
    parser = argparse.ArgumentParser(prog="teach_label.py")
    parser.add_argument("--folder", default=FOLDER)
    parser.add_argument("--labels", default="labels")
    parser.add_argument("--model", default=DEFAULT_MODEL)
    parser.add_argument("--limit", type=int)
    parser.add_argument("--cap")
    parser.add_argument("--retry-failed", action="store_true")
    parser.add_argument("--yes", action="store_true")
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
        require_manifest(folder)
        with run_lock(folder):
            return marking(folder, options, cap, ask_person, runner, environment, say, extra_folders)
    except Busy as error:
        say(str(error))
        return 2
    except Problem as error:
        say(str(error))
        return 2


def marking(folder, options, cap, ask_person, runner, environment, say, extra_folders):
    """Everything main does once the folder is locked."""
    items, given_up, _ = candidates(folder, options.labels, options.retry_failed)
    if not items:
        say("Nothing to do: every episode with a transcript already has a label.")
        if given_up:
            say(given_up_line(len(given_up)))
        return 0
    claude = find_claude(environment, extra_folders)
    if claude is None:
        say("Claude Code was not found. Install it and sign in once by running `claude`.")
        return 2
    chosen = items[:options.limit] if options.limit else items
    characters = sum(len(text) for _, lines in chosen for _, text in lines)
    say("%d episodes are waiting to be marked (%d this run), with %s."
        % (len(items), len(chosen), options.model))
    say("That is roughly {:,} tokens to read (an estimate: characters divided by 4)."
        .format(characters // 4))
    say("This uses the Claude plan this Mac is signed in to and shares its usage allowance.")
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
                 retry_failed=options.retry_failed)
    say("Marked %d episodes (%d failed). Cost as Claude counts it: $%.2f."
        % (result["done"], result["failed"], result["cost"]))
    if result["reason"]:
        say(result["reason"])
    if result["given_up"]:
        say(given_up_line(result["given_up"]))
    return 3 if result["stop"] in ("cap", "usage", "failures") else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
