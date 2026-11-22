#!/usr/bin/env python3
"""Writes down what is said in the episodes that teach_collect.py gathered, for the teaching run
that later marks ads.

Standard library only. It reads episodes.json in the teaching folder (default ~/Storyteller
Lofi/PodcastTeaching) and, for each episode that has audio and no transcript yet, runs the Swift
tool `podcast-transcribe` (Apple's speech recognition, on this Mac, nothing is sent anywhere) and
saves its lines as transcripts/<id>.txt. A transcript is only saved when the tool finished, so a
stopped run carries on where it was. Three failures in a row stop the run, because then
something is wrong with the tool, not with an episode.

  teach_transcribe.py --tool PATH [--folder F] [--locale en-US] [--limit N]

Exit codes: 0 everything pending was done (or nothing was), 2 something is not set up (no
episodes.json, a damaged one, or the tool is missing or not a program), 3 it stopped early
because of failures.

Run the tests: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import argparse
import os
import subprocess
import sys
import time

import teach_collect as collect

LOCALE = "en-US"
TIMEOUT = 3 * 60 * 60
STOP_AFTER = 3
TAIL_LINES = 5


def pending(folder, episodes):
    """The episodes that have an audio file on disk and no transcript yet, in list order."""
    return [entry for entry in episodes
            if entry["file"] and os.path.exists(os.path.join(folder, entry["file"]))
            and not os.path.exists(os.path.join(folder, "transcripts", entry["id"] + ".txt"))]


def transcribe_one(tool, audio, out, locale, runner=subprocess.run, timeout=TIMEOUT):
    """Runs the tool on one audio file and saves its lines to `out`, through `out`.part. Raises
    RuntimeError, with the last lines of what the tool said on standard error, when it fails, runs
    too long or prints nothing; no transcript is left behind then."""
    part = out + ".part"
    try:
        with open(part, "w", encoding="utf-8") as handle:
            try:
                done = runner([tool, "--locale", locale, audio], stdout=handle,
                              stderr=subprocess.PIPE, text=True, timeout=timeout)
            except subprocess.TimeoutExpired:
                raise RuntimeError("took more than %d hours" % (timeout // 3600))
            except OSError as error:
                raise RuntimeError("could not run %s: %s" % (tool, error))
        if done.returncode != 0 or os.path.getsize(part) == 0:
            # The tool shows progress with carriage returns, so split on both kinds of line end.
            said = (done.stderr or "").replace("\r", "\n").splitlines()
            tail = " / ".join([line.strip() for line in said if line.strip()][-TAIL_LINES:])
            raise RuntimeError("%s%s" % ("the tool printed nothing" if done.returncode == 0
                                         else "the tool stopped with code %d" % done.returncode,
                                         ": " + tail if tail else ""))
        os.replace(part, out)
    finally:
        if os.path.exists(part):
            os.remove(part)


def how_long(seconds):
    """A length of time in words: "3 h 20 min", "5 min" or "under a minute"."""
    if seconds < 60:
        return "under a minute"
    minutes = int(round(seconds / 60))
    if minutes < 60:
        return "%d min" % minutes
    return "%d h %d min" % (minutes // 60, minutes % 60) if minutes % 60 else "%d h" % (minutes // 60)


def run(folder, tool, locale, limit, runner=subprocess.run, clock=time.monotonic, say=print):
    """Transcribes the pending episodes, at most `limit` of them (None for all). Answers
    {"done", "failed", "left", "stopped"}: `left` is how many are still pending and `stopped` is
    True when three failures in a row ended the run."""
    episodes = collect.load_manifest(folder)
    todo = pending(folder, episodes)
    if limit is not None:
        todo = todo[:limit]
    os.makedirs(os.path.join(folder, "transcripts"), exist_ok=True)
    result = {"done": 0, "failed": 0, "left": len(todo), "stopped": False}
    total_bytes = sum(entry["bytes"] for entry in todo)
    started = clock()
    handled = 0
    in_a_row = 0
    for number, entry in enumerate(todo, 1):
        say("[%d/%d] %s: %s" % (number, len(todo), entry["show"], entry["title"] or entry["address"]))
        begun = clock()
        try:
            transcribe_one(tool, os.path.join(folder, entry["file"]),
                           os.path.join(folder, "transcripts", entry["id"] + ".txt"), locale, runner=runner)
        except RuntimeError as error:
            result["failed"] += 1
            in_a_row += 1
            say("  failed: %s" % error)
        else:
            result["done"] += 1
            in_a_row = 0
        handled += entry["bytes"]
        result["left"] = len(todo) - number
        now = clock()
        line = "  took %s" % how_long(now - begun)
        if handled and now > started and result["left"]:
            rate = handled / (now - started)
            line += "; about %s left" % how_long((total_bytes - handled) / rate)
        say(line)
        if in_a_row >= STOP_AFTER:
            result["stopped"] = True
            say("Stopping: %d episodes in a row failed, so something is wrong with the tool." % STOP_AFTER)
            break
    return result


def main(argv=None, runner=subprocess.run, clock=time.monotonic, say=print):
    parser = argparse.ArgumentParser(description="Transcribes the gathered episodes.")
    parser.add_argument("--tool", required=True)
    parser.add_argument("--folder", default=collect.FOLDER)
    parser.add_argument("--locale", default=LOCALE)
    parser.add_argument("--limit", type=int)
    args = parser.parse_args(argv)
    folder = os.path.expanduser(args.folder)
    tool = os.path.expanduser(args.tool)
    if not os.path.isfile(tool) or not os.access(tool, os.X_OK):
        say("The transcribing program is missing or cannot be run: %s" % tool)
        return 2
    if not os.path.exists(os.path.join(folder, collect.MANIFEST)):
        say("There is no %s in %s yet. Gather the episodes first (teach_collect.py)." % (collect.MANIFEST, folder))
        return 2
    try:
        result = run(folder, tool, args.locale, args.limit, runner=runner, clock=clock, say=say)
    except collect.ManifestError as error:
        say(str(error))
        return 2
    except OSError as error:
        say("Could not write to %s: %s" % (folder, error))
        return 2
    say("\n%d transcribed, %d failed, %d still to do." % (result["done"], result["failed"], result["left"]))
    return 3 if result["stopped"] else 0


if __name__ == "__main__":
    sys.exit(main())
