#!/usr/bin/env python3
"""Downloads a second copy of each marked episode and finds where it differs from the first, for
teach_snap.py.

Standard library only. Hosts that put ads into a download give two listeners different ads, and
the Swift tool `podcast-ads --truth-from-copies` lists, to the frame, where two downloads of one
episode differ. Those stretches are what the host put in. For each episode that has a label in
<folder>/labels and an MP3 file in <folder>/audio, this tool downloads the audio address from
episodes.json once more, runs that tool on the two files, keeps what it printed as
<folder>/copies/<id>.truth.txt and deletes the second copy, also when the tool fails, the run is
stopped or the Mac loses power in the middle (the next run clears what was left). Nothing is sent
anywhere but the episode's own audio address. It needs no key and no account, and the downloaded
file is not kept. The second download asks as "a second listener", the name the probe in
"Compare two downloads of an episode" uses for its second copy, so the host sees another listener
than the one that made the first copy.

  teach_copies.py --tool PATH [--folder F] [--max 40] [--max-gb 3] [--retry-failed]

--max is the most episodes to download in one run (one that fails counts: it was asked for) and
--max-gb the most traffic, counted from the size of each first copy, and the download itself is cut
off at what is left of it. An episode that was compared is not downloaded again; delete its file in
copies/ to compare it again. Two downloads often get the same ads: then no stretch differs and
nothing is learned for that episode, which is said plainly. The audio files are never touched, and
the tool is given a link to the audio inside copies/ so that it writes nothing beside the audio.

Failures are remembered in copies/failed.json: episodes that never failed come first, one that
failed three times is left out (--retry-failed asks for those again), and three in a row that had
never failed stop the run. Only one run works in the folder at a time (the folder's run lock).

Exit codes: 0 it ran, or there was nothing to do; 1 it stopped because several downloads in a row
failed; 2 something is not set up (no tool, no episodes.json, another run is working in the
folder, a folder that cannot be written); 3 it ran but a limit stopped it with episodes waiting,
which is not a failure; 130 you stopped it.

Run the tests: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import argparse
import math
import os
import re
import signal
import subprocess
import sys
import time

import probe_shows as probe
import teach_fetch as fetching
from teach_failures import GIVE_UP_AFTER, IN_A_ROW, given_up_line
from teach_second import Failures, compare, plural, tell
from teach_store import FOLDER, MANIFEST, Busy, ManifestError, load_manifest, run_lock
from teach_truth import COPIES, LABELS, save_bytes, truth_path

MAX_EPISODES = 40
MAX_GB = 3
MOST_EPISODES = 100_000  # the biggest --max that is taken
MOST_GB = 1000  # the biggest --max-gb that is taken
GB = 1_000_000_000
LIMIT_REACHED = 3
LEFTOVER = re.compile(r"^[0-9a-f]{12}\.(second|first)\.|\.part$")


def positive_int(text):
    if not re.fullmatch(r"[0-9]{1,9}", text) or not 1 <= int(text) <= MOST_EPISODES:
        raise argparse.ArgumentTypeError("%r is not a whole number from 1 to %d" % (text, MOST_EPISODES))
    return int(text)


def positive_number(text):
    try:
        value = float(text)
    except ValueError:
        value = math.nan
    if not 0 < value <= MOST_GB:  # also false for nan, and inf is over the most
        raise argparse.ArgumentTypeError("%r is not a number above 0 and at most %d" % (text, MOST_GB))
    return value


# MARK: A run

def waiting(folder, entries, failures, retry_failed):
    """(todo, left): the episodes to download, never-failed first, and how many were left out and
    why. An episode is wanted when it has a label, an MP3 file on disk and no truth file yet."""
    left = {"marked": 0, "not_mp3": 0, "before": 0, "given_up": 0}
    todo = []
    for entry in entries:
        name = entry["file"]
        if (not name or not os.path.exists(os.path.join(folder, name))
                or not os.path.exists(os.path.join(folder, LABELS, entry["id"] + ".json"))):
            continue
        left["marked"] += 1
        if not name.lower().endswith(".mp3"):
            left["not_mp3"] += 1
        elif os.path.exists(truth_path(folder, entry["id"])):
            left["before"] += 1
        else:
            todo.append(entry)
    todo.sort(key=lambda entry: failures.count(entry["id"]))
    if not retry_failed:
        ready = [entry for entry in todo if failures.count(entry["id"]) < GIVE_UP_AFTER]
        left["given_up"], todo = len(todo) - len(ready), ready
    return todo, left


def run(folder, tool, max_episodes, max_bytes, download=fetching.download, open_url=None,
        runner=subprocess.run, sleep=time.sleep, say=print, retry_failed=False, pause=probe.PAUSE):
    """Compares the waiting episodes until a limit stops it. Answers {"tried", "found",
    "stretches", "agreed", "same", "no_frame", "failed", "waiting", "why", "stopped"}; `why` is
    None, "count" or "size", and `stopped` is True when failures in a row ended the run."""
    entries = load_manifest(folder)
    copies = os.path.join(folder, COPIES)
    os.makedirs(copies, exist_ok=True)
    for name in os.listdir(copies):
        if LEFTOVER.search(name):  # what a run that was killed left behind
            try:
                os.remove(os.path.join(copies, name))
            except OSError:
                pass
    failures = Failures(copies)
    todo, left = waiting(folder, entries, failures, retry_failed)
    if left["before"]:
        say("%s compared before (to compare %s again, delete %s file in copies)." % (
            plural(left["before"], "episode was", "episodes were"), "it" if left["before"] == 1 else "them",
            "its" if left["before"] == 1 else "their"))
    if left["not_mp3"]:
        say("%s, so left out: only MP3 files can be compared." % plural(left["not_mp3"], "is not an MP3 file", "are not MP3 files"))
    if left["given_up"]:
        say(given_up_line(left["given_up"]))
    if not left["marked"]:
        say("No marked episode has an audio file on disk, so there is nothing to compare.")
    elif not todo:
        say("Nothing to do.")
    result = {"tried": 0, "found": 0, "stretches": 0, "agreed": 0, "same": 0, "no_frame": 0,
              "failed": 0, "waiting": 0, "why": None, "stopped": False}
    spent = in_a_row = 0
    for position, entry in enumerate(todo):
        if result["tried"] >= max_episodes:
            result["why"] = "count"
        elif spent + entry["bytes"] > max_bytes:
            result["why"] = "size"
        if result["why"]:
            result["waiting"] = len(todo) - position
            break
        if result["tried"]:
            sleep(pause)
        result["tried"] += 1
        say("[%d/%d] %s: %s" % (result["tried"], min(len(todo), max_episodes), entry["show"],
                                entry["title"] or entry["address"]))
        remaining = max_bytes - spent
        try:
            outcome = compare(entry, folder, tool, download, open_url, runner,
                              min(fetching.MAX_FILE, remaining))
        except fetching.TooLarge as error:
            if remaining < fetching.MAX_FILE:  # it is the budget that ran out, not the file that is odd
                say("  stopped: the file is bigger than what is left of the traffic limit.")
                result["why"], result["waiting"] = "size", len(todo) - position
                break
            outcome = RuntimeError("did not download: %s" % error)
        except Exception as error:  # one bad episode must not stop the rest
            outcome = error
        if isinstance(outcome, Exception):
            say("  failed: %s" % (str(outcome) or outcome.__class__.__name__))
            result["failed"] += 1
            spent += entry["bytes"]
            if failures.count(entry["id"]) == 0:
                in_a_row += 1
            failures.failed(entry["id"])
            if in_a_row >= IN_A_ROW:
                result["stopped"] = True
                say("Stopping: %d episodes in a row failed, so something is wrong with the connection "
                    "or the tool." % IN_A_ROW)
                break
            continue
        in_a_row = 0
        spent += outcome["bytes"]
        failures.succeeded(entry["id"])
        save_bytes(truth_path(folder, entry["id"]), outcome["text"].encode("utf-8"))
        result["stretches"] += len(outcome["stretches"])
        result[{"found": "found", "agree": "agreed"}.get(outcome["kind"], outcome["kind"])] += 1
        tell(outcome, say)
    return result


def close(result, args, say):
    compared = result["found"] + result["agreed"] + result["same"] + result["no_frame"]
    say("\n%s compared: %d with differing stretches (%d in all), %d got the same ads, %d failed." % (
        plural(compared, "episode", "episodes"), result["found"], result["stretches"],
        result["agreed"] + result["same"], result["failed"]))
    if result["no_frame"]:
        say("%d could not be compared because the host makes a new file for every download."
            % result["no_frame"])
    if result["agreed"] + result["same"]:
        say("Two downloads that got the same ads teach nothing. That is common.")
    if result["waiting"]:
        why = ("the limit of %d episodes was reached" % args.max if result["why"] == "count"
               else "the %g GB limit on traffic was reached" % args.max_gb)
        say("%d %s still waiting because %s." % (result["waiting"], "is" if result["waiting"] == 1 else "are", why))


def main(argv=None, download=fetching.download, runner=subprocess.run, sleep=time.sleep, say=print,
         open_url=None):
    parser = argparse.ArgumentParser(description="Downloads a second copy of the marked episodes.")
    parser.add_argument("--tool", required=True)
    parser.add_argument("--folder", default=FOLDER)
    parser.add_argument("--max", type=positive_int, default=MAX_EPISODES)
    parser.add_argument("--max-gb", type=positive_number, default=MAX_GB)
    parser.add_argument("--retry-failed", action="store_true")
    args = parser.parse_args(argv)
    folder = os.path.expanduser(args.folder)
    tool = os.path.expanduser(args.tool)
    if not os.path.isfile(tool) or not os.access(tool, os.X_OK):
        say("The comparing program is missing or cannot be run: %s" % tool)
        return 2
    if not os.path.exists(os.path.join(folder, MANIFEST)):
        say("There is no %s in %s yet. Gather the episodes first (teach_collect.py)." % (MANIFEST, folder))
        return 2
    say("Second downloads of at most %s and %g GB of traffic. Nothing is sent but each episode's own "
        "audio address." % (plural(args.max, "marked episode", "marked episodes"), args.max_gb))
    try:
        with run_lock(folder):
            result = run(folder, tool, args.max, int(round(args.max_gb * GB)), download=download,
                         open_url=open_url, runner=runner, sleep=sleep, say=say,
                         retry_failed=args.retry_failed)
    except Busy as error:
        say(str(error))
        return 2
    except ManifestError as error:
        say(str(error))
        return 2
    except OSError as error:
        say("Could not write to %s: %s" % (folder, error))
        return 2
    except KeyboardInterrupt:
        say("\nStopped. The second copy was deleted; what was finished is kept.")
        return 130
    if result["tried"]:
        close(result, args, say)
    if result["stopped"]:
        return 1
    return LIMIT_REACHED if result["why"] else 0


def stop(number, frame):
    """A closed window or a stop from outside ends the run the way Control-C does, so the second
    copy is deleted."""
    raise KeyboardInterrupt


if __name__ == "__main__":
    for name in ("SIGTERM", "SIGHUP"):
        signal.signal(getattr(signal, name), stop)
    sys.exit(main())
