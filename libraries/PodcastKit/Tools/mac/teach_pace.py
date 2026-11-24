#!/usr/bin/env python3
"""Reads the phone's diary and says how often a play started with the episode ready and how fast
the phone really transcribes, so the stream replay can use a measured speech pace.

Standard library only. The phone writes Podcasts/phone-diary.jsonl into its linked folder (the
iCloud copy of LofiMusic): the skip log, the ad finder's diary and the play diary (PlayDiary.swift).
The play diary has two kinds of line, both with "kind": "diary":

  "what": "play: ready" | "play: partly, transcript to 240 s" | "play: stream"
      one line for every play that starts: the episode's ads were finished, its transcript was
      only partly made, or it played as a stream
  "what": "3600 s of audio in 214.3 s, front" (or ", background")
      one line for every finished transcription: the audio it did, the seconds it took, and
      whether the app was open or iOS gave it a background turn

  teach_pace.py [--diary FILE]

The diary is looked for in the iCloud copy first, then in the Mac's own copy (or read from
--diary). The tool prints the share of plays that were ready and the speech pace (seconds of audio
per second of work), and the `podcast-teach score ... --stream --speech N` to replay the shelf at
it. It writes nothing. Having no diary is not an error.

Exit code: 0 it worked (also with no diary), 2 a set-up problem.

Run the tests: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import argparse
import json
import os
import re
import sys

import teach_feedback
from apple_podcasts_export import default_folders

DIARY = os.path.join("Podcasts", "phone-diary.jsonl")
FILE_LIMIT = 8 * 1024 * 1024
PLAY = re.compile(r"^play: (?:(ready|stream)|(partly), transcript to \d+ s)$")
SPEED = re.compile(r"^(\d+) s of audio in (\d+(?:\.\d+)?) s, (front|background)$")


# MARK: Reading

def read_line(line):
    """("play", "ready" | "partly" | "stream") or ("speed", audio seconds, work seconds, "front" |
    "background") for a diary line of the play diary, else None (any other line, or one that is
    not JSON)."""
    try:
        one = json.loads(line)
    except (ValueError, RecursionError):
        return None
    if not isinstance(one, dict) or one.get("kind") != "diary" or not isinstance(one.get("what"), str):
        return None
    found = PLAY.match(one["what"])
    if found:
        return ("play", found.group(1) or found.group(2))
    found = SPEED.match(one["what"])
    if found and float(found.group(1)) > 0 and float(found.group(2)) > 0:
        return ("speed", float(found.group(1)), float(found.group(2)), found.group(3))
    return None


class Counted:
    """The plays by how the episode stood, and the transcriptions as (audio, work, where)."""

    def __init__(self):
        self.plays = {"ready": 0, "partly": 0, "stream": 0}
        self.speeds = []

    def total_plays(self):
        return sum(self.plays.values())

    def ready_share(self):
        """The share of plays that were ready, or None when there is no play."""
        return self.plays["ready"] / self.total_plays() if self.total_plays() else None

    def _runs(self, where):
        return [s for s in self.speeds if where is None or s[2] == where]

    def runs(self, where=None):
        return len(self._runs(where))

    def speech(self, where=None):
        """Seconds of audio per second of work over the runs (all, or those in `where`), or None
        when there is none. Long runs weigh more than short ones."""
        runs = self._runs(where)
        work = sum(s[1] for s in runs)
        return sum(s[0] for s in runs) / work if work else None


def count(lines):
    """What the lines of a diary say about plays and transcriptions."""
    counted = Counted()
    for line in lines:
        one = read_line(line)
        if one is None:
            continue
        if one[0] == "play":
            counted.plays[one[1]] += 1
        else:
            counted.speeds.append(one[1:])
    return counted


# MARK: Saying

def plural(number, word):
    return "%d %s%s" % (number, word, "" if number == 1 else "s")


def summary(counted):
    """The lines to print."""
    lines = []
    plays = counted.plays
    if counted.total_plays():
        lines.append("Plays that started: %d (ready %d, partly %d, stream %d)."
                     % (counted.total_plays(), plays["ready"], plays["partly"], plays["stream"]))
        lines.append("Share of plays that were ready: %d%% (%d of %d)."
                     % (round(counted.ready_share() * 100), plays["ready"], counted.total_plays()))
    else:
        lines.append("The diary has no play lines yet.")
    overall = counted.speech()
    if overall is None:
        lines.append("No speech pace yet: no transcription is in the diary yet.")
        return lines
    audio = sum(s[0] for s in counted.speeds)
    work = sum(s[1] for s in counted.speeds)
    lines.append("Speech pace: %.1f s of audio per second of work (%s: %d s of audio in %d s)."
                 % (overall, plural(counted.runs(), "transcription"), round(audio), round(work)))
    where = ["%s %.1f (%s)" % (name, counted.speech(name), plural(counted.runs(name), "run"))
             for name in ("front", "background") if counted.runs(name)]
    lines.append("  " + ", ".join(where) + ".")
    # A stream is played with the app open, so its replay uses the pace of the runs in front.
    front = counted.speech("front")
    use = front if front is not None else overall
    lines.append("Replay the shelf at the %s pace: podcast-teach score <teaching folder> --stream "
                 "--speech %g" % ("front" if front is not None else "overall", max(0.1, round(use, 1))))
    return lines


# MARK: Run

def main(argv, say=print, defaults=default_folders):
    parser = argparse.ArgumentParser(prog="teach_pace.py")
    parser.add_argument("--diary")
    try:
        options = parser.parse_args(argv)
    except SystemExit as stop:
        return stop.code if isinstance(stop.code, int) else 2
    denied = []
    path = (os.path.expanduser(options.diary) if options.diary
            else teach_feedback.find_notes(defaults, denied, DIARY))
    if denied and path is None:
        say("macOS did not let this read the phone's diary at %s (a permission problem). Give "
            "/bin/bash Full Disk Access once: System Settings > Privacy & Security > Full Disk "
            "Access > +, press Cmd-Shift-G, type /bin/bash, add it and switch it on." % denied[0])
        return 2
    if path is None or not os.path.exists(path):
        say("There is no diary file at %s, so there is nothing to measure." % path if options.diary
            else "The phone has sent no diary yet, so there is nothing to measure.")
        return 0
    try:
        if os.path.getsize(path) > FILE_LIMIT:
            say("The diary is bigger than %d MB, which is too big to read. Move it away and run "
                "this again." % (FILE_LIMIT // 1024 // 1024))
            return 2
        with open(path, "rb") as handle:
            lines = [raw.decode("utf-8", "replace") for raw in handle.read().splitlines()]
    except OSError as error:
        say("The diary in %s could not be read: %s" % (path, error))
        return 2
    for line in summary(count(lines)):
        say(line)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
