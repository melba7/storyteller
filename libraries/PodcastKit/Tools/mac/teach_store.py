"""The files the teaching tools share: the teaching folder, the episode list (episodes.json), the
one atomic JSON writer and the lock that keeps two runs from working in the folder at once.

Standard library only. teach_collect, teach_transcribe, teach_label and teach_habits all read and
write through this module, so there is one folder name, one version number and one way of saving.

`python3 teach_store.py busy FOLDER` exits 3 when another run holds the lock on FOLDER and 0 when it
is free (teach-weekly.sh asks this before it starts). `python3 teach_store.py hold FOLDER COMMAND...`
runs the command while holding the lock (teach-finish.sh does, for its whole length) and exits with
the command's code, or 3 when another run holds the lock.

Run the tests: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import contextlib
import fcntl
import json
import os
import re
import subprocess
import sys
import tempfile
import time

FOLDER = "~/Storyteller Lofi/PodcastTeaching"
MANIFEST = "episodes.json"
VERSION = 1
LOCK = ".lock"
BUSY = ("Another teaching run is already working in this folder. Wait for it to finish, or close "
        "its window.")
AUDIO_EXTENSIONS = ("mp3", "m4a", "aac", "ogg", "opus", "wav")
ID_PATTERN = re.compile(r"^[0-9a-f]{12}$")
FILE_PATTERN = re.compile(r"^audio/([0-9a-f]{12})\.(%s)$" % "|".join(AUDIO_EXTENSIONS))
# The fields every entry of episodes.json has and the kinds of value each may hold.
FIELDS = {"id": (str,), "feed": (str,), "show": (str,), "guid": (str,), "title": (str,),
          "published": (int, float, type(None)), "seconds": (int, float, type(None)),
          "address": (str,), "size": (int, type(None)), "file": (str, type(None)),
          "bytes": (int,), "sha256": (str, type(None)), "host": (str, type(None)),
          "error": (str, type(None))}


class ManifestError(ValueError):
    """episodes.json exists but cannot be trusted."""


class Problem(Exception):
    """A set-up problem: the run cannot start (exit code 2)."""


class Busy(Exception):
    """Another run holds the lock on the teaching folder."""


# MARK: Episode list

def check_entry(entry):
    """Raises ManifestError when an entry of episodes.json is not shaped as the contract says."""
    if not isinstance(entry, dict):
        raise ManifestError("an episode is not an object")
    for field, kinds in FIELDS.items():
        value = entry.get(field)
        if field not in entry or not isinstance(value, kinds) or isinstance(value, bool):
            raise ManifestError("an episode has a bad or missing \"%s\"" % field)
    if not ID_PATTERN.match(entry["id"]):
        raise ManifestError("an episode has an id that is not 12 hex digits")
    if not entry["address"].startswith(("http://", "https://")) or entry["bytes"] < 0:
        raise ManifestError("an episode has a bad address or size")
    if entry["file"] is not None:
        match = FILE_PATTERN.match(entry["file"])
        if not match or match.group(1) != entry["id"]:
            raise ManifestError("an episode's file name does not match its id")


def load_manifest(folder):
    """The entries of <folder>/episodes.json, or [] when there is no such file. Raises
    ManifestError when it is not valid JSON, has another version or is not shaped as expected."""
    path = os.path.join(folder, MANIFEST)
    try:
        with open(path, encoding="utf-8") as handle:
            data = json.load(handle)
    except FileNotFoundError:
        return []
    except (OSError, ValueError) as error:
        raise ManifestError("%s cannot be read: %s" % (path, error))
    if not isinstance(data, dict) or data.get("version") != VERSION or not isinstance(data.get("episodes"), list):
        raise ManifestError("%s is not a version %d episode list" % (path, VERSION))
    ids = set()
    for entry in data["episodes"]:
        check_entry(entry)
        if entry["id"] in ids:
            raise ManifestError("%s lists an episode twice" % path)
        ids.add(entry["id"])
    return data["episodes"]


def require_manifest(folder):
    """load_manifest for the steps after gathering: a missing episodes.json is a Problem that says
    to run the gather step first, and a damaged one is a Problem with the reason."""
    if not os.path.exists(os.path.join(folder, MANIFEST)):
        raise Problem("There is no %s in %s. Run the gather step first." % (MANIFEST, folder))
    try:
        return load_manifest(folder)
    except ManifestError as error:
        raise Problem(str(error))


def write_json(path, value):
    """Writes `value` as JSON to `path` through a temporary file in the same folder, forced to disk
    before it replaces the old file, so a crash or a power cut leaves the old file or the new one."""
    folder = os.path.dirname(path) or "."
    os.makedirs(folder, exist_ok=True)
    handle, temporary = tempfile.mkstemp(dir=folder, prefix=".", suffix=".part")
    try:
        with os.fdopen(handle, "w", encoding="utf-8") as out:
            json.dump(value, out, indent=1, ensure_ascii=False)
            out.flush()
            os.fsync(out.fileno())
        os.replace(temporary, path)
    except BaseException:
        if os.path.exists(temporary):
            os.remove(temporary)
        raise


def save_manifest(folder, entries):
    """Writes episodes.json, so it is never half-written."""
    write_json(os.path.join(folder, MANIFEST),
               {"version": VERSION, "writtenAt": int(time.time() * 1000), "episodes": entries})


# MARK: Lock

@contextlib.contextmanager
def run_lock(folder):
    """Holds an exclusive lock on <folder>/.lock for the length of the `with` block, making the
    folder first. Raises Busy (with the sentence to show) when another run already holds it. The
    lock goes when the block ends or the program stops, however it stops."""
    os.makedirs(folder, exist_ok=True)
    handle = open(os.path.join(folder, LOCK), "a")
    try:
        try:
            fcntl.flock(handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise Busy(BUSY)
        yield
    finally:
        handle.close()


def hold(folder, command, runner=subprocess.call):
    """Runs `command` while holding the folder's run lock, and returns its exit code. When another
    run holds the lock it says so and returns 3 without running anything."""
    try:
        with run_lock(folder):
            return runner(command)
    except Busy as error:
        print(error)
        return 3
    except OSError as error:
        print("The teaching folder %s cannot be used: %s" % (folder, error))
        return 1


def main(argv):
    """The command line: `busy FOLDER` (exit code 0 the folder is free, 3 another run is working in
    it) and `hold FOLDER COMMAND...` (runs the command with the lock held, see `hold`). 2 when the
    arguments are wrong."""
    if len(argv) == 2 and argv[0] == "busy":
        try:
            with run_lock(os.path.expanduser(argv[1])):
                return 0
        except Busy:
            return 3
    if len(argv) >= 3 and argv[0] == "hold":
        return hold(os.path.expanduser(argv[1]), argv[2:])
    print("Usage: teach_store.py busy FOLDER | teach_store.py hold FOLDER COMMAND...")
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
