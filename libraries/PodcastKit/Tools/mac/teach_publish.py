#!/usr/bin/env python3
"""Copies the results of the teaching run to the folders the phone reads.

Standard library only. For each destination folder it writes, into the same Podcasts subfolder
that apple_podcasts_export.py uses (<folder>/Podcasts):

  ad-model.json    from <folder>/ad-model.json    (teach_train.py)
  ad-library.json  from <folder>/ad-library.json  (teach_library.py)
  show-habits.json from <folder>/habits.json      (teach_habits.py)

  teach_publish.py [--folder F] [--to FOLDER ...]

Without --to the destinations are the ones apple_podcasts_export.py writes to: the LofiMusic
folder under ~/Storyteller Lofi and its copy in iCloud Drive. A source that does not exist is
skipped. A source is checked before it is copied: it must be JSON, an object with "version": 1 and
at most 4.5 MB (the phone refuses files over 5 MB). A file is written through a temporary file in
the same folder, and only when its content differs from what is there. A destination folder that
does not exist or cannot be written is reported and the others are still tried.

Exit code: 0 every existing source reached the first destination folder (also when there was
nothing to publish), 2 a source reached no folder or not the first one, or the arguments are wrong.

Run the tests: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import argparse
import json
import os
import sys
import tempfile

import teach_label
import teach_store
from apple_podcasts_export import default_folders

LIMIT = 4500000
SUBFOLDER = "Podcasts"
FILES = (("ad-model.json", "ad-model.json"), ("ad-library.json", "ad-library.json"),
         ("habits.json", "show-habits.json"))


def checked(path, limit=LIMIT):
    """The bytes of a source that is fit to publish. Raises ValueError (with the reason in plain
    words) when it is too large, not JSON or not a version 1 object, and OSError when it cannot
    be read."""
    size = os.path.getsize(path)
    if size > limit:
        raise ValueError("it is too large (%d bytes, the most is %d)" % (size, limit))
    with open(path, "rb") as f:
        data = f.read()
    try:
        value = json.loads(data)
    except ValueError:
        raise ValueError("it is not JSON")
    if not isinstance(value, dict) or type(value.get("version")) is not int \
            or value["version"] != 1:
        raise ValueError("it is not an object with \"version\": 1")
    return data


def write_atomically(path, data):
    """Writes `data` to `path` through a temporary file in the same folder."""
    handle, temporary = tempfile.mkstemp(dir=os.path.dirname(path), prefix=".", suffix=".tmp")
    try:
        with os.fdopen(handle, "wb") as f:
            f.write(data)
        os.replace(temporary, path)
    except BaseException:
        if os.path.exists(temporary):
            os.remove(temporary)
        raise


def put(folder, name, data, writer):
    """Puts `data` at <folder>/Podcasts/<name>: "written" or "unchanged". Raises OSError."""
    if not os.path.isdir(folder):
        raise OSError("the folder does not exist")
    directory = os.path.join(folder, SUBFOLDER)
    path = os.path.join(directory, name)
    try:
        with open(path, "rb") as f:
            if f.read() == data:
                return "unchanged"
    except OSError:
        pass
    os.makedirs(directory, exist_ok=True)
    writer(path, data)
    return "written"


def main(argv, say=print, writer=write_atomically, limit=LIMIT, defaults=default_folders):
    parser = argparse.ArgumentParser(prog="teach_publish.py")
    parser.add_argument("--folder", default=teach_store.FOLDER)
    parser.add_argument("--to", action="append", metavar="FOLDER")
    try:
        options = parser.parse_args(argv)
    except SystemExit:
        return 2
    folder = os.path.expanduser(options.folder)
    destinations = [os.path.expanduser(f) for f in options.to] if options.to else defaults()
    exit_code = 0
    for source, target in FILES:
        try:
            data = checked(os.path.join(folder, source), limit)
        except FileNotFoundError:
            say("%s: skipped, there is no %s in %s." % (target, source, folder))
            continue
        except (OSError, ValueError) as error:
            say("%s: not copied, %s is not fit to publish: %s." % (target, source, error))
            exit_code = 2
            continue
        for number, destination in enumerate(destinations):
            try:
                outcome = put(destination, target, data, writer)
            except OSError as error:
                say("%s in %s: failed (%s)." % (target, destination, error))
                outcome = None
            else:
                say("%s in %s: %s." % (target, destination, outcome))
            if number == 0 and outcome is None:
                exit_code = 2
    return exit_code


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
