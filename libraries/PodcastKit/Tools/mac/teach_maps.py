#!/usr/bin/env python3
"""Episode preparing, the maps: writes a small map of each prepared copy into the phone's iCloud
folder, so a phone that plays another download of the episode can carry the Mac's marks over.

Standard library only. The show's own audio is the same MP3 frames in every download of an
episode; only the inserted ads differ. The map holds one byte for each frame of the copy the Mac
marked and the marks in that copy's seconds (about 185 KB for an hour). The phone lines its own
audio up against it: what matches carries the marks over exactly, and what matches nothing is an ad
only the phone got. The map is written by the Swift tool `podcast-ads --map` (EpisodeMapCommand in
PodcastKit), so the Mac and the phone cut frames with the same code.

  teach_maps.py publish --tool PATH [--folder F] [--to ICLOUD_COPY]

publish makes <to>/Podcasts/maps/<id>.json for each prepared copy that is an MP3 file, is in the
iCloud copy now (teach_prepared_file.copies) and has no map of that very file yet. The marks are
the ones ahead-ads.json tells with the copy (the snapped label when there is one), those Claude was
sure of ("high" and "medium"); the others stay questions the phone finds by their words. It also
removes the maps of copies that are gone: only files named <12 hex>.json in that folder.
teach_ahead_ads.py then names each map in its episode's entry
(`"map": "maps/<id>.json"`), a key that older builds of the app ignore.

Nothing here stops a run. Exit codes: 0 it worked, 1 a map could not be made or removed (the rest
was done), 2 a set-up problem, 3 there is no iCloud copy of the phone's folder.

Run the tests: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import argparse
import json
import os
import re
import subprocess
import sys
import tempfile

import teach_ahead_ads
import teach_prepared_file
import teach_store
from apple_podcasts_export import default_folders
from teach_ahead_set import read_ahead
from teach_publish import SUBFOLDER

FOLDER_NAME = "maps"
NAME = re.compile(r"^([0-9a-f]{12})\.json$")
SURE = ("high", "medium")
STOPPED = 3


def run_command(command):
    """(exit code, what it printed). Raises OSError when the program cannot be started."""
    done = subprocess.run(command, capture_output=True, text=True, timeout=300)
    return done.returncode, done.stdout + done.stderr


def map_of(to, identifier):
    return os.path.join(to, SUBFOLDER, FOLDER_NAME, identifier + ".json")


def made_for(path):
    """The SHA-256 of the copy the map at `path` was made of, or None when there is no map there
    that can be read."""
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, ValueError):
        return None
    sha = data.get("sha256") if isinstance(data, dict) and data.get("version") == 1 else None
    return sha if isinstance(sha, str) else None


def maps(folder, to):
    """{id: "maps/<id>.json"} of the prepared copies in the iCloud copy `to` whose map is there and
    was made of that very file. teach_ahead_ads.py tells the phone about exactly these."""
    found = {}
    for identifier, copy in teach_prepared_file.copies(folder, to).items():
        if made_for(map_of(to, identifier)) == copy["sha256"]:
            found[identifier] = "%s/%s.json" % (FOLDER_NAME, identifier)
    return found


def marks_of(folder, identifier, say):
    """The marks the map carries: the sure ads of the episode's label, as ahead-ads.json tells them
    with a copy. Raises OSError or ValueError when the label or the transcript cannot be used."""
    label, lines = teach_ahead_ads.read_prepared_label(folder, identifier, say)
    return [{"start": ad["start"], "end": ad["end"], "kind": ad["kind"]}
            for ad in teach_ahead_ads.ads_of(label, lines) if ad["confidence"] in SURE]


def clean(to, keep, say):
    """Removes the maps whose copy is gone. Returns how many could not be removed."""
    directory = os.path.join(to, SUBFOLDER, FOLDER_NAME)
    failed = 0
    try:
        names = os.listdir(directory)
    except OSError:
        return 0
    for name in names:
        found = NAME.match(name)
        if not found or found.group(1) in keep:
            continue
        try:
            os.remove(os.path.join(directory, name))
        except OSError as error:
            say("The map %s could not be removed: %s" % (name, error))
            failed += 1
    return failed


def make_one(folder, to, tool, item, copy, run, say):
    """Writes the map of one copy. Returns None when it worked, else the reason."""
    try:
        marks = marks_of(folder, item["id"], say)
    except (OSError, ValueError) as error:
        return "its label or transcript cannot be used (%s)" % error
    handle, marks_file = tempfile.mkstemp(prefix="map-marks-", suffix=".json")
    try:
        with os.fdopen(handle, "w", encoding="utf-8") as f:
            json.dump(marks, f)
        os.makedirs(os.path.dirname(map_of(to, item["id"])), exist_ok=True)
        try:
            code, text = run([tool, "--map", os.path.join(to, SUBFOLDER, copy["file"]),
                              "--out", map_of(to, item["id"]), "--marks", marks_file,
                              "--sha256", copy["sha256"], "--feed", item["feed"], "--guid", item["guid"]])
        except (OSError, subprocess.SubprocessError) as error:
            code, text = 1, str(error)
        if code != 0:
            return (text.strip().splitlines() or ["the map tool failed"])[-1]
        if made_for(map_of(to, item["id"])) != copy["sha256"]:
            return "the map tool wrote no map of this file"
        return None
    except OSError as error:
        return str(error)
    finally:
        os.remove(marks_file)


def publish(folder, to, tool, say, run=run_command):
    copies = teach_prepared_file.copies(folder, to)
    failed = clean(to, set(copies), say)
    for item in read_ahead(folder):
        copy = copies.get(item["id"])
        if not copy or not copy["file"].lower().endswith(".mp3"):
            continue
        if made_for(map_of(to, item["id"])) == copy["sha256"]:
            continue
        reason = make_one(folder, to, tool, item, copy, run, say)
        if reason:
            say("No map of %s: %s." % (item["id"], reason))
            failed += 1
        else:
            say("Map of %s: %s (%d KB)." % (item["id"], item["title"],
                                            (os.path.getsize(map_of(to, item["id"])) + 512) // 1024))
    return 1 if failed else 0


def main(argv, say=print, run=run_command, defaults=default_folders):
    parser = argparse.ArgumentParser(prog="teach_maps.py")
    parser.add_argument("command", choices=("publish",))
    parser.add_argument("--tool", required=True)
    parser.add_argument("--folder", default=teach_store.FOLDER)
    parser.add_argument("--to")
    try:
        options = parser.parse_args(argv)
    except SystemExit as stop:
        return stop.code if isinstance(stop.code, int) else 2
    folder = os.path.expanduser(options.folder)
    to = os.path.expanduser(options.to) if options.to else defaults()[-1]
    if not os.path.isdir(to):
        say("There is no iCloud copy of the phone's folder at %s, so no map is written." % to)
        return STOPPED
    try:
        return publish(folder, to, options.tool, say, run)
    except teach_store.Problem as error:
        say(str(error))
        return 2
    except OSError as error:
        say("The teaching folder %s cannot be used: %s" % (folder, error))
        return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
