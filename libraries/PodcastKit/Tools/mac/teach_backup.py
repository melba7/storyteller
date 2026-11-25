"""Backups of what the teaching runs have paid for.

Claude's marks cost about $0.19 an episode and live only in the teaching folder, so this makes a
copy of them that a bad disk, a wrong delete or a bug cannot take with it. Standard library only.

  python3 teach_backup.py make --folder F [--to DIR] [--keep N] [--check]
      Writes DIR/teaching-YYYY-MM-DD-HHMM.tar.gz (DIR is "PodcastTeachingBackups" next to the
      teaching folder unless --to says otherwise) and keeps the newest N (14) of these. It holds
      labels/, labels-snapped/, labels-second/, transcripts/, copies/ and sound-bank/ and every .json file
      of the folder itself.
      The audio, the caches and anything hidden are left out: they are large or can be made again.
      With --check the new file is checked straight away (see below), and nothing old is removed
      when that check fails.
  python3 teach_backup.py check --file BACKUP [--folder F]
      Reads the backup to its very end, parses every JSON file in it and, with --folder, says how
      many label files the folder has that the backup lacks (marked since). Exit 0 only when the
      backup is whole.
  python3 teach_backup.py restore --file BACKUP --into DIR
      Unpacks a backup into an empty folder. It never writes into the live teaching folder.

It takes no lock and only reads the teaching folder, so marking and training may run meanwhile.
A backup is written to a temporary name and renamed when whole, so a stop leaves no half-written
teaching-*.tar.gz. Only files named teaching-YYYY-MM-DD-HHMM.tar.gz are ever removed; the
before-*.tar.gz made by hand and anything else in DIR stay.

Exit codes: 0 well, 1 a backup that is not whole or could not be written, 2 something to set right
first (no such folder or file, a folder that is not empty).

Run the tests: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import argparse
import datetime
import gzip
import io
import json
import os
import re
import sys
import tarfile
import tempfile
import zlib

from teach_store import FOLDER

BACKUPS = "PodcastTeachingBackups"
KEEP = 14
# The folders that are backed up whole; of the teaching folder itself only the .json files are.
FOLDERS = ("labels", "labels-snapped", "labels-second", "transcripts", "copies", "sound-bank")
LABEL_FOLDERS = ("labels", "labels-snapped", "labels-second")
OWN_NAME = re.compile(r"^teaching-\d{4}-\d{2}-\d{2}-\d{4}\.tar\.gz$")
# A file over this is left out and said, so a stray big file cannot swell every backup.
MAX_FILE_BYTES = 50 * 1024 * 1024


class Problem(Exception):
    """Something to set right first (exit code 2)."""


# MARK: What goes in

def files_to_back_up(folder):
    """[(name inside the backup, path)] of the regular, not hidden files to save, in order."""
    found = []
    for name in sorted(os.listdir(folder)):
        path = os.path.join(folder, name)
        if name.endswith(".json") and not name.startswith(".") and is_plain_file(path):
            found.append((name, path))
    for top in FOLDERS:
        for where, folders, files in os.walk(os.path.join(folder, top)):
            folders[:] = sorted(d for d in folders if not d.startswith("."))
            for name in sorted(files):
                path = os.path.join(where, name)
                if not name.startswith(".") and is_plain_file(path):
                    found.append((os.path.relpath(path, folder).replace(os.sep, "/"), path))
    return found


def is_plain_file(path):
    return os.path.isfile(path) and not os.path.islink(path)


def read_file(path):
    """(bytes, modified time) of a file, or None when it is gone, unreadable or too large. The
    bytes are read whole so that a file that changes meanwhile cannot break the archive."""
    try:
        with open(path, "rb") as handle:
            data = handle.read(MAX_FILE_BYTES + 1)
            modified = os.fstat(handle.fileno()).st_mtime
    except OSError:
        return None
    return None if len(data) > MAX_FILE_BYTES else (data, modified)


def size_text(size):
    return "%.1f MB" % (size / 1e6) if size >= 1e5 else "%.1f KB" % (size / 1e3)


# MARK: Make

def make_backup(folder, to=None, keep=KEEP, now=None, say=print, check=False):
    """Writes one backup and removes the old ones past `keep`. Returns 0, or 1 when `check` found
    the new file not whole (then nothing old is removed). Raises Problem when there is no folder."""
    folder = os.path.abspath(os.path.expanduser(folder))
    if not os.path.isdir(folder):
        raise Problem("There is no teaching folder at %s." % folder)
    to = os.path.abspath(os.path.expanduser(to)) if to else os.path.join(os.path.dirname(folder), BACKUPS)
    files = files_to_back_up(folder)
    if not files:
        say("Nothing to back up yet: %s has no marks, transcripts or JSON files." % folder)
        return 0
    os.makedirs(to, exist_ok=True)
    name = "teaching-%s.tar.gz" % (now or datetime.datetime.now()).strftime("%Y-%m-%d-%H%M")
    final = os.path.join(to, name)
    handle, partial = tempfile.mkstemp(dir=to, prefix=".teaching-", suffix=".part")
    saved = left_out = 0
    try:
        with os.fdopen(handle, "wb") as raw:
            with tarfile.open(fileobj=raw, mode="w:gz") as tar:
                for arcname, path in files:
                    read = read_file(path)
                    if read is None:
                        left_out += 1
                        continue
                    info = tarfile.TarInfo(arcname)
                    info.size, info.mtime, info.mode = len(read[0]), read[1], 0o644
                    tar.addfile(info, io.BytesIO(read[0]))
                    saved += 1
            raw.flush()
            os.fsync(raw.fileno())
        os.replace(partial, final)
    except BaseException:
        if os.path.exists(partial):
            os.remove(partial)
        raise
    line = "%s: written. %d files, %s, in %s." % (name, saved, size_text(os.path.getsize(final)), to)
    if left_out:
        line += " %d too large or unreadable files were left out." % left_out
    said = ""
    if check:
        ok, said = check_backup(final, folder)
        if not ok:
            say(line)
            say("The new backup is not good: %s. Nothing older was removed." % said)
            return 1
    removed = prune(to, keep)
    if removed:
        line += " Removed %d older backup%s (the newest %d are kept)." % (
            removed, "" if removed == 1 else "s", keep)
    say(line)
    if said:
        say(said)
    return 0


def prune(to, keep):
    """Removes the oldest of the files named like this tool's own, past the newest `keep`.
    Returns how many went."""
    mine = sorted(n for n in os.listdir(to) if OWN_NAME.match(n) and is_plain_file(os.path.join(to, n)))
    old = mine[:-keep] if len(mine) > keep else []
    for name in old:
        os.remove(os.path.join(to, name))
    return len(old)


# MARK: Check

def safe_name(name):
    parts = name.split("/")
    return bool(name) and not name.startswith("/") and "" not in parts and ".." not in parts


def check_backup(path, folder=None):
    """(True, a sentence about what is in it) when the backup reads to its end and every JSON file
    in it parses, else (False, what is wrong). With `folder` the sentence also says how many label
    files the folder has that the backup lacks."""
    try:
        with gzip.open(path, "rb") as stream:  # to the end, which also checks the gzip's own sum
            while stream.read(1 << 20):
                pass
        names, bad_json, bad_names = [], [], []
        with tarfile.open(path, "r:gz") as tar:
            for member in tar:
                if not member.isreg():
                    continue
                data = tar.extractfile(member).read()
                if not safe_name(member.name):
                    bad_names.append(member.name)
                names.append(member.name)
                if member.name.endswith(".json"):
                    try:
                        json.loads(data.decode("utf-8"))
                    except ValueError:
                        bad_json.append(member.name)
    except (OSError, EOFError, zlib.error, tarfile.TarError) as error:
        return False, "it cannot be read to the end (%s)" % error
    if bad_names:
        return False, "it has a file that would be unpacked outside the folder (%s)" % ", ".join(bad_names[:3])
    if bad_json:
        more = " and %d more" % (len(bad_json) - 3) if len(bad_json) > 3 else ""
        return False, "JSON files in it do not read as JSON: %s%s" % (", ".join(sorted(bad_json)[:3]), more)
    json_count = sum(1 for n in names if n.endswith(".json"))
    said = "%s is whole: %d files read to the end, %d JSON files all read." % (
        os.path.basename(path), len(names), json_count)
    if folder is not None:
        missing = len(label_files(os.path.expanduser(folder)) - set(names))
        said += (" The folder has %d label file%s that it lacks (marked after it was made)."
                 % (missing, "" if missing == 1 else "s") if missing
                 else " The folder has every label file that it holds.")
    return True, said


def label_files(folder):
    """The names (as in a backup) of the label files in a teaching folder."""
    found = set()
    for top in LABEL_FOLDERS:
        try:
            for name in os.listdir(os.path.join(folder, top)):
                if not name.startswith(".") and is_plain_file(os.path.join(folder, top, name)):
                    found.add("%s/%s" % (top, name))
        except OSError:
            pass
    return found


# MARK: Restore

def restore_backup(path, into, say=print):
    """Unpacks a whole backup into an empty (or new) folder. Raises Problem when the folder is not
    empty; returns 1, having written nothing, when the backup is not whole."""
    into = os.path.abspath(os.path.expanduser(into))
    if os.path.exists(into) and (not os.path.isdir(into) or os.listdir(into)):
        raise Problem("%s is not empty (or not a folder), so nothing was unpacked. Restore only writes "
                      "into a new or empty folder, never into the live teaching folder." % into)
    ok, said = check_backup(path)
    if not ok:
        say("The backup is not good: %s. Nothing was unpacked." % said)
        return 1
    count = 0
    with tarfile.open(path, "r:gz") as tar:
        for member in tar:
            if not member.isreg():
                continue
            target = os.path.join(into, *member.name.split("/"))
            os.makedirs(os.path.dirname(target), exist_ok=True)
            with open(target, "wb") as out:
                out.write(tar.extractfile(member).read())
            os.utime(target, (member.mtime, member.mtime))
            count += 1
    say("Unpacked %d files into %s. The live teaching folder was not touched." % (count, into))
    return 0


# MARK: Command line

def positive(text):
    try:
        number = int(text)
    except ValueError:
        number = 0
    if number < 1:
        raise argparse.ArgumentTypeError("must be a whole number of 1 or more")
    return number


def main(argv=None, say=print):
    parser = argparse.ArgumentParser(description="Backups of the teaching folder's marks, "
                                     "transcripts and small JSON files (not the audio or caches).")
    commands = parser.add_subparsers(dest="command", required=True)
    make = commands.add_parser("make", help="write a new backup and keep the newest few")
    make.add_argument("--folder", default=FOLDER, help="the teaching folder (it is only read)")
    make.add_argument("--to", help="where the backups go (default: PodcastTeachingBackups next to the folder)")
    make.add_argument("--keep", type=positive, default=KEEP, help="how many teaching-*.tar.gz to keep (14)")
    make.add_argument("--check", action="store_true", help="check the new backup straight away")
    check = commands.add_parser("check", help="read a backup to its end and parse its JSON files")
    check.add_argument("--file", required=True)
    check.add_argument("--folder", help="also say how many label files this folder has that it lacks")
    restore = commands.add_parser("restore", help="unpack a backup into an empty folder",
                                  description="Unpacks a backup into an EMPTY folder (or one that "
                                  "does not exist yet). It never writes into the live teaching folder: "
                                  "copy back by hand what you need from the folder it makes.")
    restore.add_argument("--file", required=True)
    restore.add_argument("--into", required=True, help="an empty or new folder")
    args = parser.parse_args(argv)
    try:
        if args.command == "make":
            try:
                return make_backup(args.folder, args.to, args.keep, check=args.check, say=say)
            except OSError as error:
                say("The backup could not be written: %s" % error)
                return 1
        path = os.path.expanduser(args.file)
        if not os.path.isfile(path):
            raise Problem("There is no backup at %s." % path)
        if args.command == "check":
            ok, said = check_backup(path, args.folder)
            say(said if ok else "%s is NOT good: %s." % (os.path.basename(path), said))
            return 0 if ok else 1
        return restore_backup(path, args.into, say)
    except Problem as error:
        say(str(error))
        return 2


if __name__ == "__main__":
    sys.exit(main())
