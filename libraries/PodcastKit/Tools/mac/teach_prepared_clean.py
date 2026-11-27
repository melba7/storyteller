"""The cleaning of the prepared audio (teach_prepared.py): what is too old or too much goes, from the
iCloud folder and from this Mac, and nothing else ever does. See teach_prepared.py for the rules.

Standard library only.

Run the tests: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import os
import re

import teach_exam
import teach_free
import teach_shelf
import teach_store
from teach_prepared_file import SUBFOLDER, name_belongs, read_prepared, write_prepared
from teach_store import AUDIO_EXTENSIONS

LEFTOVER = re.compile(r"^([0-9a-f]{12})\.(%s)\.part$" % "|".join(AUDIO_EXTENSIONS))
PART_SECONDS = 86400  # a .part younger than this may be a copy that is being made

GB = 1_000_000_000


class Tidy:
    """What cleaning needs: the folders, the clock and the limits."""

    def __init__(self, folder, to, now, options, say):
        self.folder, self.to, self.now, self.say = folder, to, now, say
        self.keep_seconds = options.keep_days * 86400
        self.max_bytes = int(options.max_gb * GB)
        self.failed = 0

    def protected(self):
        return set(teach_exam.read_exam(self.folder)) | set(teach_shelf.read_shelf(self.folder))

    def present(self, one):
        return os.path.exists(os.path.join(self.to, SUBFOLDER, one["file"]))

    def removable(self, entries):
        """The entries that may be removed at all, oldest first: not removed yet, not of the exam
        or the shelf, and with a name that belongs to the id."""
        kept = self.protected()
        found = []
        for one in sorted((e for e in entries if e["removed"] is None and e["file"] is not None),
                          key=lambda e: e["published"]):
            if not name_belongs(one):
                self.say("Left alone: %s in prepared.json is not a name it removes." % one["file"])
            elif one["id"] not in kept:
                found.append(one)
        return found

    def remove(self, entries, manifest, one):
        """Removes one copy (an episode that was only picked has none) and the Mac's own audio of
        the episode, then notes it. False when the copy could not be removed (said; nothing else is
        changed)."""
        if one["file"] is not None:
            try:
                os.remove(os.path.join(self.to, SUBFOLDER, one["file"]))
            except FileNotFoundError:
                pass
            except OSError as error:
                self.say("The prepared copy %s could not be removed: %s" % (one["file"], error))
                self.failed += 1
                return False
        for item in manifest:
            if item["id"] == one["id"] and item["file"]:
                try:
                    teach_free.drop_audio(self.folder, item)
                except OSError as error:
                    self.say("The Mac's own audio of %s could not be deleted: %s" % (one["id"], error))
                    self.failed += 1
                else:
                    teach_store.save_manifest(self.folder, manifest)
        one["removed"] = self.now
        write_prepared(self.folder, entries)
        return True

    def stale_picks(self, entries):
        """The episodes that were only picked, never published, and were picked at least the keep
        time ago, not of the exam or the shelf: their audio on this Mac goes."""
        kept = self.protected()
        return [one for one in entries if one["removed"] is None and one["file"] is None
                and one["id"] not in kept and self.now - one["picked"] >= self.keep_seconds]

    def leftovers(self, entries):
        """Removes <id>.<ext>.part files of the prepared folder whose id prepared.json lists, the
        id is not of the exam or the shelf, and that are over a day old. Nothing else."""
        folder = os.path.join(self.to, SUBFOLDER, "prepared")
        listed = {one["id"] for one in entries} - self.protected()
        try:
            names = os.listdir(folder)
        except OSError:
            return 0
        gone = 0
        for name in names:
            found = LEFTOVER.match(name)
            path = os.path.join(folder, name)
            try:
                if found and found.group(1) in listed and self.now - os.path.getmtime(path) > PART_SECONDS:
                    os.remove(path)
                    gone += 1
            except OSError as error:
                self.say("The leftover %s could not be removed: %s" % (name, error))
                self.failed += 1
        return gone

    def clean(self, extra=0):
        """Removes what is too old, then the oldest until what is kept plus `extra` bytes fits.
        Returns how many copies went."""
        entries = read_prepared(self.folder)
        manifest = teach_store.load_manifest(self.folder)
        gone = 0
        candidates = self.removable(entries)
        for one in [e for e in candidates if self.now - e["published"] >= self.keep_seconds]:
            gone += self.remove(entries, manifest, one)
        picks = sum(self.remove(entries, manifest, one) for one in self.stale_picks(entries))
        if picks:
            self.say("Deleted the audio of %d picked %s that never reached iCloud."
                     % (picks, "episode" if picks == 1 else "episodes"))
        gone += self.leftovers(entries)
        candidates = [e for e in candidates if e["removed"] is None]
        kept = sum(e["bytes"] for e in candidates if self.present(e))
        for one in candidates:
            if kept + extra <= self.max_bytes:
                break
            present = self.present(one)
            if self.remove(entries, manifest, one):
                gone += 1
                kept -= one["bytes"] if present else 0
        if gone:
            self.say("Removed %d prepared %s." % (gone, "copy" if gone == 1 else "copies"))
        return gone
