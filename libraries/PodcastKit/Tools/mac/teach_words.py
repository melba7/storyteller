#!/usr/bin/env python3
"""The time of each word of a transcript: reading the side file next to it, and writing the side
files down again for episodes that were transcribed before they existed.

Standard library only. The transcripts in <folder>/transcripts/<id>.txt keep only where each line
starts, so a label made from them can only end where the next line starts. `podcast-transcribe
--words FILE` also saves where each word and each line starts and ends, in seconds, as
<folder>/transcripts/<id>.words.json (teach_transcribe.py asks for it for every new episode). The
plain transcript is not touched, so every reader of it works as before.

This tool writes the side files for episodes that are already written down. By default only the
episodes on the shelf (shelf.json); --all takes every episode that has audio. An episode that has its
side file is skipped, so a stopped run carries on where it was. It runs the Swift tool again on the
audio (Apple's speech recognition, on this Mac, nothing is sent anywhere, nothing is paid) and
keeps only the side file: the plain transcripts and the labels are never changed.

  teach_words.py --tool PATH [--folder F] [--locale en-US] [--limit N] [--all]

Three failures in a row stop the run. Only one run works in the folder at a time.

Exit codes: 0 everything pending was done (or nothing was), 2 something is not set up, 3 it stopped
early because of failures.

Run the tests: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import argparse
import bisect
import json
import math
import os
import subprocess
import sys
import time

from teach_failures import IN_A_ROW
from teach_shelf import read_shelf
from teach_store import FOLDER, MANIFEST, Busy, ManifestError, Problem, load_manifest, run_lock
from teach_transcribe import LOCALE, TAIL_LINES, TIMEOUT, how_long, words_path

VERSION = 1
# A transcript prints a line's start cut to a tenth, so it is up to a tenth before the exact start.
START_SLACK = 0.101


def is_number(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


SWITCH = "word-ends-on"


def switch_path(folder):
    """The file whose presence turns on label ends at the last word (teach_label.py)."""
    return os.path.join(folder, SWITCH)


def switched_on(folder):
    return os.path.exists(switch_path(folder))


def read_words(path):
    """The side file as a dict, or None when it is missing or is not a version 1 file whose lines are
    pairs of numbers, in order of time."""
    try:
        with open(path, encoding="utf-8") as handle:
            data = json.load(handle)
    except (OSError, ValueError):
        return None
    if not isinstance(data, dict) or data.get("version") != VERSION or not isinstance(data.get("lines"), list):
        return None
    last = -math.inf
    for item in data["lines"]:
        if not (isinstance(item, list) and len(item) == 2 and all(is_number(x) for x in item)) \
                or item[0] < last:
            return None
        last = item[0]
    return data


def line_ends(lines, data):
    """The exact end of each transcript line, in the order of `lines` ([(seconds, text)] as
    teach_segments.read_transcript gives them), None for a line the side file does not hold. A line is
    matched by its start, which the transcript cuts to a tenth, so it is the first not yet used line of
    the side file that starts at that time or up to a tenth later."""
    starts = [item[0] for item in data["lines"]]
    at = 0
    found = []
    for seconds, _ in lines:
        at = max(at, bisect.bisect_left(starts, seconds - 0.001))
        if at < len(starts) and starts[at] - seconds < START_SLACK:
            found.append(data["lines"][at][1])
            at += 1
        else:
            found.append(None)
    return found


def word_ends(folder, identifier, lines):
    """line_ends for an episode, read from its side file; None when it has no usable one or no line
    of the transcript is in it."""
    data = read_words(words_path(folder, identifier))
    if data is None:
        return None
    found = line_ends(lines, data)
    return found if any(end is not None for end in found) else None


# MARK: Writing them down again

def write_one(tool, audio, out, locale, runner=subprocess.run, timeout=TIMEOUT):
    """Runs the tool on one audio file and keeps only its side file at `out`, through `out`.part.
    Raises RuntimeError, with the last lines of what the tool said, when it fails, runs too long or
    leaves no usable side file; nothing is left behind then."""
    part = out + ".part"
    try:
        try:
            done = runner([tool, "--locale", locale, "--words", part, audio], stdout=subprocess.DEVNULL,
                          stderr=subprocess.PIPE, text=True, timeout=timeout)
        except subprocess.TimeoutExpired:
            raise RuntimeError("took more than %d hours" % (timeout // 3600))
        except OSError as error:
            raise RuntimeError("could not run %s: %s" % (tool, error))
        if done.returncode != 0 or read_words(part) is None:
            said = (done.stderr or "").replace("\r", "\n").splitlines()
            tail = " / ".join([line.strip() for line in said if line.strip()][-TAIL_LINES:])
            raise RuntimeError("%s%s" % ("the tool left no word times" if done.returncode == 0
                                         else "the tool stopped with code %d" % done.returncode,
                                         ": " + tail if tail else ""))
        os.replace(part, out)
    finally:
        if os.path.exists(part):
            os.remove(part)


def pending(folder, episodes, shelf, everything):
    """([entries], no_audio): the episodes with audio on disk and no side file yet, in the shelf's
    order (or the episode list's with `everything`), and how many that lack only their audio."""
    by_id = {entry["id"]: entry for entry in episodes}
    chosen = episodes if everything else [by_id[i] for i in dict.fromkeys(shelf) if i in by_id]
    todo, no_audio = [], 0
    for entry in chosen:
        if os.path.exists(words_path(folder, entry["id"])):
            continue
        if entry["file"] and os.path.exists(os.path.join(folder, entry["file"])):
            todo.append(entry)
        else:
            no_audio += 1
    return todo, no_audio


def run(folder, tool, locale, limit=None, everything=False, runner=subprocess.run,
        clock=time.monotonic, say=print):
    """Writes the side files that are missing, at most `limit` of them. Answers {"done", "failed",
    "left", "no_audio", "stopped"}: `left` is how many are still missing, `stopped` is True when three
    failures in a row ended the run."""
    episodes = load_manifest(folder)
    todo, no_audio = pending(folder, episodes, [] if everything else read_shelf(folder), everything)
    result = {"done": 0, "failed": 0, "left": len(todo), "no_audio": no_audio, "stopped": False}
    if no_audio:
        say("%d episode%s have no audio any more, so their word times cannot be written down."
            % (no_audio, "" if no_audio == 1 else "s"))
    os.makedirs(os.path.join(folder, "transcripts"), exist_ok=True)
    started, in_a_row = clock(), 0
    for number, entry in enumerate(todo[:limit] if limit is not None else todo, 1):
        say("[%d/%d] %s: %s" % (number, len(todo), entry["show"], entry["title"] or entry["address"]))
        begun = clock()
        try:
            write_one(tool, os.path.join(folder, entry["file"]), words_path(folder, entry["id"]), locale,
                      runner=runner)
        except RuntimeError as error:
            result["failed"] += 1
            in_a_row += 1
            say("  failed: %s" % error)
        else:
            result["done"] += 1
            result["left"] -= 1
            in_a_row = 0
            say("  took %s" % how_long(clock() - begun))
        if in_a_row >= IN_A_ROW:
            result["stopped"] = True
            say("Stopping: %d episodes in a row failed, so something is wrong with the tool." % IN_A_ROW)
            break
    result["elapsed"] = clock() - started
    return result


def main(argv=None, runner=subprocess.run, clock=time.monotonic, say=print):
    parser = argparse.ArgumentParser(description="Writes down the word times of episodes again.")
    parser.add_argument("--tool", required=True)
    parser.add_argument("--folder", default=FOLDER)
    parser.add_argument("--locale", default=LOCALE)
    parser.add_argument("--limit", type=int)
    parser.add_argument("--all", action="store_true")
    args = parser.parse_args(argv)
    folder = os.path.expanduser(args.folder)
    tool = os.path.expanduser(args.tool)
    if not os.path.isfile(tool) or not os.access(tool, os.X_OK):
        say("The transcribing program is missing or cannot be run: %s" % tool)
        return 2
    if not os.path.exists(os.path.join(folder, MANIFEST)):
        say("There is no %s in %s yet. Gather the episodes first (teach_collect.py)." % (MANIFEST, folder))
        return 2
    try:
        with run_lock(folder):
            result = run(folder, tool, args.locale, args.limit, args.all, runner=runner, clock=clock,
                         say=say)
    except (Busy, Problem, ManifestError) as error:
        say(str(error))
        return 2
    except OSError as error:
        say("Could not write to %s: %s" % (folder, error))
        return 2
    say("\n%d written down, %d failed, %d still to do." % (result["done"], result["failed"], result["left"]))
    return 3 if result["stopped"] else 0


if __name__ == "__main__":
    sys.exit(main())
