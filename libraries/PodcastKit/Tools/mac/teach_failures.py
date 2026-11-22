"""Remembers which episodes failed in the transcribing and marking steps, in failures.json in the
teaching folder:

  {"version": 1, "transcribe": {"<id>": count}, "label": {"<id>": count}}

Without this memory the same failing episodes come first in every run, and a run that stops after
three failures in a row would stop at once, for ever. With it, episodes that never failed go first,
then the failed ones with the fewest failures, and an episode that failed three times is left out
until the run is started with --retry-failed. An entry goes when the episode later succeeds.

Run the tests: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import json
import os

from teach_store import write_json

FILE = "failures.json"
VERSION = 1
GIVE_UP_AFTER = 3
IN_A_ROW = 3


def given_up_line(count):
    """The closing sentence about the episodes that were left out."""
    return ("%d episode%s given up on after failing %d times. To try %s once more, run this step "
            "with --retry-failed." % (count, " was" if count == 1 else "s were", GIVE_UP_AFTER,
                                      "it" if count == 1 else "them"))


class Failures:
    """The failure counts of one step ("transcribe" or "label") of one teaching folder."""

    def __init__(self, folder, step):
        self.path = os.path.join(folder, FILE)
        self.step = step
        self.data = {"version": VERSION, "transcribe": {}, "label": {}}
        try:
            with open(self.path, encoding="utf-8") as handle:
                found = json.load(handle)
        except (OSError, ValueError):
            return  # no file, or a damaged one: start with an empty memory
        if isinstance(found, dict) and found.get("version") == VERSION:
            for name in ("transcribe", "label"):
                counts = found.get(name)
                if isinstance(counts, dict):
                    self.data[name] = {key: value for key, value in counts.items()
                                       if isinstance(value, int) and not isinstance(value, bool)
                                       and value > 0}

    def count(self, identifier):
        return self.data[self.step].get(identifier, 0)

    def failed(self, identifier):
        """Adds one failure and saves."""
        self.data[self.step][identifier] = self.count(identifier) + 1
        write_json(self.path, self.data)

    def succeeded(self, identifier):
        """Forgets the episode's failures, if it had any, and saves."""
        if self.data[self.step].pop(identifier, None) is not None:
            write_json(self.path, self.data)

    def split(self, items, retry_failed, key):
        """(ready, given_up): `items` in the order to work in, never-failed ones first and then
        fewer failures first (otherwise the order they came in), and the ones that failed three
        times apart, unless `retry_failed`. `key(item)` is the item's episode id."""
        ordered = sorted(items, key=lambda item: self.count(key(item)))
        if retry_failed:
            return ordered, []
        ready = [item for item in ordered if self.count(key(item)) < GIVE_UP_AFTER]
        return ready, ordered[len(ready):]
