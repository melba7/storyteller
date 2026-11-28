"""Tells the phone which episodes are coming, and stops telling it when they are done.

Standard library only.

  announce(...)   called by teach_prepare.py pick right after it picked episodes, before any
                  download or marking: lists them in coming.json (teach_coming.py), writes
                  ahead-ads.json with them in "coming" and copies that file (and the list
                  teaching.json) to the Mac's folder and the iCloud copy, the same way
                  teach_publish.py does.
  settle          teach_coming_publish.py settle [--folder F]: run by teach-prepare.sh once the
                  copies are in iCloud and before ahead-ads.json is written for the last time. An
                  episode with its copy is in "episodes" now and leaves "coming"; one without
                  (the marking or the copy failed) is dropped, so the phone does not wait for it.
                  It empties coming.json and says how many of each.

Nothing here stops a run: a folder that cannot be written is said in one line and the run goes on.
The phone waits at most 2 hours from "since" anyway.

Run the tests: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import argparse
import os
import sys
import time

import teach_ahead_ads
import teach_coming
import teach_prepared_file
import teach_publish
import teach_store
from apple_podcasts_export import default_folders
from teach_ahead import plural


def publish(folder, destinations, now, say):
    """Copies <folder>/ahead-ads.json to each destination, with teaching.json. Said, never raised."""
    try:
        data = teach_publish.checked(os.path.join(folder, teach_ahead_ads.FILE))
        teach_publish.ahead_shape(data)
    except (OSError, ValueError) as error:
        say("The coming list was not copied: %s." % error)
        return
    for destination in destinations:
        try:
            teach_publish.put(destination, teach_ahead_ads.FILE, data, teach_publish.write_atomically)
            teach_publish.update_list(destination, teach_publish.write_atomically, lambda: int(now() * 1000))
        except OSError as error:
            say("The coming list did not reach %s (%s)." % (destination, error))


def announce(folder, picked, say, defaults=default_folders, now=time.time):
    """Lists `picked` as coming and tells the phone, before the marking starts."""
    if not picked:
        return
    destinations = defaults()
    try:
        teach_coming.add_coming(folder, picked, now())
        teach_ahead_ads.write(folder, int(now()), say, to=destinations[-1])
    except (OSError, teach_store.Problem) as error:
        say("The phone was not told which episodes are coming (%s)." % error)
        return
    publish(folder, destinations, now, say)
    say("%s told to the phone as coming." % plural(len(picked), "episode was", "episodes were"))


def settle(folder, say, defaults=default_folders, now=time.time):
    """Empties coming.json. Returns (how many have their copy, how many were dropped)."""
    entries = teach_coming.read_coming(folder)
    if not entries:
        return 0, 0
    try:
        ready = teach_prepared_file.copies(folder, defaults()[-1])
    except teach_store.Problem as error:
        say(str(error))
        ready = {}
    done = sum(1 for one in entries if one["id"] in ready)
    teach_coming.write_coming(folder, [])
    say("Coming: %d now have the Mac's copy and %d were dropped because they did not get one."
        % (done, len(entries) - done))
    return done, len(entries) - done


def main(argv, say=print, defaults=default_folders, now=time.time):
    parser = argparse.ArgumentParser(prog="teach_coming_publish.py")
    parser.add_argument("command", choices=("settle",))
    parser.add_argument("--folder", default=teach_store.FOLDER)
    try:
        options = parser.parse_args(argv)
    except SystemExit as stop:
        return stop.code if isinstance(stop.code, int) else 2
    try:
        settle(os.path.expanduser(options.folder), say, defaults, now)
    except OSError as error:
        say("The coming list could not be emptied (%s)." % error)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
