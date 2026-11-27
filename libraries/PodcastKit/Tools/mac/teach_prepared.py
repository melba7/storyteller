#!/usr/bin/env python3
"""Episode preparing, the audio: copies the audio the Mac marked into the phone's iCloud folder, keeps
prepared.json, and cleans up after itself.

Standard library only. When the phone plays the very file the Mac marked, the Mac's times hold to
the frame, so teach-prepare.sh puts a copy of each marked episode's audio where the phone can fetch
it, and teach_ahead_ads.py then tells the phone about that copy.

  teach_prepared.py publish [--folder F] [--to ICLOUD_COPY] [--keep-free-gb 15] [--keep-days 7]
                            [--max-gb 10]
  teach_prepared.py clean   [the same options]

--to is the iCloud copy of the phone's folder that teach_publish.py also writes to (the default is
the same one, apple_podcasts_export.default_folders()[1]). Audio goes to
<to>/Podcasts/prepared/<id>.<ext>. publish cleans first (so there is room), then copies each episode
of ahead.json that has a label, has audio on this Mac, is not in the exam or on the shelf, is not
published yet and has its second download settled (a truth file, or given up on, or not an MP3; the
rule of teach_free.py), so the times the phone gets with a copy never change. An episode that is not
settled waits for a later hour. A copy is made with `cp -c` (an APFS clone, which takes no disk space), or with a
plain `cp` when that fails, into <name>.part, and renamed when it is whole; its SHA-256 (read in
chunks) and size go into prepared.json before the rename. prepared.json lives in the teaching
folder:

  {"version": 1, "episodes": [{"id": "<12 hex>", "file": "prepared/<id>.<ext>", "sha256": "<64 hex>",
                               "bytes": <int>, "published": <seconds>, "removed": <seconds or null>}]}

Stops, each said in one line (exit 3, and what was published before stays): no iCloud folder; under
--keep-free-gb free on the Mac's disk; `brctl quota` saying iCloud has less than 2 GB plus the
file's size left (a missing brctl, or words this does not understand, do not stop it).

Cleaning removes prepared audio older than --keep-days, then the oldest first until what is kept is
at most --max-gb, and before each new file enough to make room for it. With a copy, the Mac's own
audio/<id>.<ext> of that episode is deleted too and its entry in episodes.json is put right the way
teach_free.py does it, so it is never downloaded again. Hard rules: only ids that prepared.json
lists are touched, only a file named prepared/<that id>.<ext> (12 hex digits), never an episode of
exam.json or shelf.json, and never a transcript, a label, a truth file or any other file. Also
cleaned: the Mac's own audio of an episode the pick listed but that was never published and was
picked --keep-days ago, and a leftover <id>.<ext>.part of a listed id that is over a day old.
--keep-days may be 0 (everything listed goes; "Stop episode preparing.command" uses it).

prepared.json is read and written by teach_prepared_file.py and the cleaning is
teach_prepared_clean.py.

Exit codes: 0 it worked, 1 something could not be copied or removed (the rest was done), 2 a set-up
problem, 3 stopped (or another run holds the folder).

Run the tests: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import argparse
import hashlib
import math
import os
import re
import shutil
import subprocess
import sys
import time

import teach_exam
import teach_free
import teach_shelf
import teach_store
from apple_podcasts_export import default_folders
from teach_ahead_set import read_ahead
from teach_prepared_clean import GB, Tidy
from teach_second import Failures
from teach_prepared_file import FOLDER_NAME, SUBFOLDER, copies, read_prepared, write_prepared

QUOTA = re.compile(r"([0-9][0-9,]*)\s+bytes of quota remaining")
CHUNK = 1024 * 1024
KEEP_FREE_GB = 15
KEEP_DAYS = 7
MAX_GB = 10
ICLOUD_ROOM = 2 * GB  # what iCloud must have left after a file
STOPPED = 3


def icloud_copy(defaults=default_folders):
    """The iCloud copy of the phone's folder, the one teach_publish.py writes last."""
    return defaults()[-1]


# MARK: Outside the program

def run_command(command):
    """(exit code, what it printed). Raises OSError when the program cannot be started."""
    done = subprocess.run(command, capture_output=True, text=True, timeout=None if command[0] == "cp" else 30)
    return done.returncode, done.stdout + done.stderr


def disk_free(path):
    return shutil.disk_usage(path).free


def quota_left(run):
    """The bytes iCloud says it has left, or None when `brctl quota` is missing, fails or says
    something this does not understand."""
    try:
        code, text = run(["brctl", "quota"])
    except (OSError, subprocess.SubprocessError):
        return None
    found = QUOTA.search(text or "") if code == 0 else None
    return int(found.group(1).replace(",", "")) if found else None


def sha256_of(path):
    digest = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(CHUNK), b""):
            digest.update(block)
    return digest.hexdigest()


# MARK: Publishing

def waiting(folder, to):
    """The marked episodes of ahead.json with audio on this Mac that are not published (and still
    there), were not removed before and whose second download is settled, in ahead.json's order.
    Settled is the rule of teach_free.py: a truth file, or given up on, or not an MP3. Until then the
    episode waits for a later hour, so the times the phone gets with a copy never change."""
    failures = Failures(os.path.join(folder, "copies"))
    manifest = {e["id"]: e for e in teach_store.load_manifest(folder)}
    kept = set(teach_exam.read_exam(folder)) | set(teach_shelf.read_shelf(folder))
    before = {e["id"] for e in read_prepared(folder) if e["removed"] is not None}
    there = set(copies(folder, to))
    found = []
    for item in read_ahead(folder):
        one = manifest.get(item["id"])
        if (one and one["file"] and item["id"] not in kept | before | there
                and os.path.exists(os.path.join(folder, one["file"]))
                and os.path.exists(os.path.join(folder, "labels", item["id"] + ".json"))
                and (not one["file"].lower().endswith(".mp3")
                     or teach_free.second_download_settled(folder, item["id"], failures))):
            found.append(one)
    return found


def copy_one(tidy, one, run):
    """Copies one episode's audio and notes it. Returns None when it worked, else the reason."""
    source = os.path.join(tidy.folder, one["file"])
    directory = os.path.join(tidy.to, SUBFOLDER, FOLDER_NAME)
    final = os.path.join(directory, os.path.basename(one["file"]))
    part = final + ".part"
    os.makedirs(directory, exist_ok=True)
    try:
        for command in (["cp", "-c", source, part], ["cp", source, part]):
            try:
                code, text = run(command)
            except (OSError, subprocess.SubprocessError) as error:
                code, text = 1, str(error)
            if code == 0:
                break
        else:
            return text.strip() or "cp failed"
        if os.path.getsize(part) != os.path.getsize(source):
            return "the copy is not the size of the original"
        entries = read_prepared(tidy.folder)
        picked = [e.get("picked") for e in entries if e["id"] == one["id"] and e.get("picked")]
        entries = [e for e in entries if e["id"] != one["id"]]
        entries.append({"id": one["id"], "file": "%s/%s" % (FOLDER_NAME, os.path.basename(final)),
                        "sha256": sha256_of(part), "bytes": os.path.getsize(part),
                        "published": tidy.now, "removed": None})
        if picked:
            entries[-1]["picked"] = picked[0]
        write_prepared(tidy.folder, entries)  # noted before the rename, so it can always be cleaned
        os.replace(part, final)
        return None
    except OSError as error:
        return str(error)
    finally:
        if os.path.exists(part):
            os.remove(part)


def publish(tidy, options, run, free):
    tidy.clean()
    failed = 0
    for one in waiting(tidy.folder, tidy.to):
        size = os.path.getsize(os.path.join(tidy.folder, one["file"]))
        if free(tidy.folder) < options.keep_free_gb * GB:
            tidy.say("Not published: the Mac's disk has under %g GB free." % options.keep_free_gb)
            return STOPPED
        left = quota_left(run)
        if left is not None and left < ICLOUD_ROOM + size:
            tidy.say("Not published: iCloud has under 2 GB left after this file (%.1f GB left)."
                     % (left / GB))
            return STOPPED
        if size > tidy.max_bytes:
            tidy.say("Not published %s: the file is bigger than the %g GB kept in iCloud."
                     % (one["id"], options.max_gb))
            failed += 1
            continue
        tidy.clean(extra=size)
        reason = copy_one(tidy, one, run)
        if reason:
            tidy.say("The audio of %s could not be copied: %s" % (one["id"], reason))
            failed += 1
        else:
            tidy.say("Published %s: %s (%.1f MB)." % (one["id"], one["title"], size / 1e6))
    return 1 if failed or tidy.failed else 0


# MARK: Command line

def positive(text):
    value = float(text)
    if not math.isfinite(value) or value <= 0:
        raise argparse.ArgumentTypeError("%r is not a number above zero" % text)
    return value


def not_negative(text):
    value = float(text)
    if not math.isfinite(value) or value < 0:
        raise argparse.ArgumentTypeError("%r is not a number from zero up" % text)
    return value


def main(argv, say=print, now=time.time, run=run_command, free=disk_free, defaults=default_folders):
    parser = argparse.ArgumentParser(prog="teach_prepared.py")
    parser.add_argument("command", choices=("publish", "clean"))
    parser.add_argument("--folder", default=teach_store.FOLDER)
    parser.add_argument("--to")
    parser.add_argument("--keep-free-gb", type=positive, default=KEEP_FREE_GB)
    parser.add_argument("--keep-days", type=not_negative, default=KEEP_DAYS)
    parser.add_argument("--max-gb", type=positive, default=MAX_GB)
    try:
        options = parser.parse_args(argv)
    except SystemExit as stop:
        return stop.code if isinstance(stop.code, int) else 2
    folder = os.path.expanduser(options.folder)
    to = os.path.expanduser(options.to) if options.to else icloud_copy(defaults)
    tidy = Tidy(folder, to, int(now()), options, say)
    try:
        with teach_store.run_lock(folder):
            if not os.path.isdir(to):
                say("There is no iCloud copy of the phone's folder at %s, so no audio is prepared or "
                    "removed." % to)
                return STOPPED
            if options.command == "clean":
                tidy.clean()
                return 1 if tidy.failed else 0
            return publish(tidy, options, run, free)
    except teach_store.Busy:
        say("Another teaching run is already working in the teaching folder.")
        return STOPPED
    except (teach_store.Problem, teach_store.ManifestError) as error:
        say(str(error))
        return 2
    except OSError as error:
        say("The teaching folder %s cannot be used: %s" % (folder, error))
        return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
