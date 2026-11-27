"""The cleaning of the prepared audio (teach_prepared.py): what is too old or too much goes, from the
iCloud folder and from this Mac, and nothing else ever does. See teach_prepared.py for the rules.

Standard library only.

Run the tests: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import os

import teach_exam
import teach_free
import teach_shelf
import teach_store
from teach_prepared_file import SUBFOLDER, name_belongs, read_prepared, write_prepared

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
        for one in sorted((e for e in entries if e["removed"] is None), key=lambda e: e["published"]):
            if not name_belongs(one):
                self.say("Left alone: %s in prepared.json is not a name it removes." % one["file"])
            elif one["id"] not in kept:
                found.append(one)
        return found

    def remove(self, entries, manifest, one):
        """Removes one copy and the Mac's own audio of the episode, then notes it. False when the
        copy could not be removed (said; nothing else is changed)."""
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

    def clean(self, extra=0):
        """Removes what is too old, then the oldest until what is kept plus `extra` bytes fits.
        Returns how many copies went."""
        entries = read_prepared(self.folder)
        manifest = teach_store.load_manifest(self.folder)
        gone = 0
        candidates = self.removable(entries)
        for one in [e for e in candidates if self.now - e["published"] > self.keep_seconds]:
            gone += self.remove(entries, manifest, one)
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
