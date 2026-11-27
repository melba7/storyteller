"""Tests for the cleaning of teach_prepared.py: prepared audio older than --keep-days goes, then
the oldest first until the total is under --max-gb; the Mac's own audio of a removed episode goes
too and its entry in episodes.json is put right; and what is never touched: an id that
prepared.json does not list, a name that is not <12 hex>.<ext>, an episode of the exam or the shelf,
and any other file. Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import json
import os

import teach_free
import teach_prepared as prepared
import teach_store as store
from test_teach_prepared import DAY, GB, NOW, Base

SMALL = "0.000003"  # --max-gb: 3000 bytes


class CleanBase(Base):
    def publish_old(self, number, days, size=1000):
        """An episode that was published `days` ago: its copy is in iCloud and in prepared.json."""
        item = self.episode(number, size=size)
        os.makedirs(self.prepared_folder(), exist_ok=True)
        name = "%s.mp3" % item["id"]
        with open(os.path.join(self.prepared_folder(), name), "wb") as f:
            f.write(b"x" * size)
        found = prepared.read_prepared(self.folder.dir)
        found.append({"id": item["id"], "file": "prepared/" + name, "sha256": "a" * 64, "bytes": size,
                      "published": NOW - int(days * DAY), "removed": None})
        prepared.write_prepared(self.folder.dir, found)
        return item

    def exists(self, item):
        return os.path.exists(os.path.join(self.prepared_folder(), item["id"] + ".mp3"))

    def mac_audio(self, item):
        return os.path.exists(self.folder.path(item["file"]))

    def state(self, item):
        return [e for e in self.listed() if e["id"] == item["id"]][0]


class AgeTests(CleanBase):
    def test_audio_older_than_seven_days_goes_and_younger_stays(self):
        old, young = self.publish_old(1, 7.1), self.publish_old(2, 6.9)
        self.assertEqual(self.go("clean"), 0, self.said)
        self.assertFalse(self.exists(old))
        self.assertTrue(self.exists(young))
        self.assertEqual((self.state(old)["removed"], self.state(young)["removed"]), (NOW, None))

    def test_keep_days_can_be_changed(self):
        item = self.publish_old(1, 4)
        self.go("clean", "--keep-days", "5")
        self.assertTrue(self.exists(item))
        self.go("clean", "--keep-days", "3")
        self.assertFalse(self.exists(item))

    def test_the_macs_own_audio_goes_too_and_the_entry_is_put_right(self):
        old = self.publish_old(1, 8)
        self.go("clean")
        self.assertFalse(self.mac_audio(old))
        entry = [e for e in store.load_manifest(self.folder.dir) if e["id"] == old["id"]][0]
        self.assertEqual((entry["file"], entry["bytes"], entry["error"]),
                         (None, 0, teach_free.FREED))
        self.assertTrue(entry["error"].startswith("skipped:"))

    def test_the_audio_is_not_downloaded_again_after_that(self):
        import teach_collect
        old = self.publish_old(1, 8)
        self.go("clean")
        entries = store.load_manifest(self.folder.dir)
        self.assertTrue(teach_collect.is_skipped([e for e in entries if e["id"] == old["id"]][0]))

    def test_the_transcript_the_label_and_the_truth_of_a_removed_episode_stay(self):
        old = self.publish_old(1, 8)
        for folder, name in (("transcripts", ".txt"), ("copies", ".truth.txt"), ("labels-snapped", ".json")):
            os.makedirs(self.folder.path(folder), exist_ok=True)
            with open(self.folder.path(folder, old["id"] + name), "w") as f:
                f.write("kept")
        self.go("clean")
        for folder, name in (("transcripts", ".txt"), ("copies", ".truth.txt"), ("labels-snapped", ".json"),
                             ("labels", ".json")):
            self.assertTrue(os.path.exists(self.folder.path(folder, old["id"] + name)), folder)

    def test_an_episode_whose_copy_is_already_gone_is_still_put_right(self):
        old = self.publish_old(1, 8)
        os.remove(os.path.join(self.prepared_folder(), old["id"] + ".mp3"))
        self.assertEqual(self.go("clean"), 0)
        self.assertEqual(self.state(old)["removed"], NOW)
        self.assertFalse(self.mac_audio(old))

    def test_a_removed_entry_is_not_worked_on_again(self):
        old = self.publish_old(1, 8)
        self.go("clean")
        with open(os.path.join(self.folder.dir, "prepared.json")) as f:
            first = f.read()
        self.go("clean")
        with open(os.path.join(self.folder.dir, "prepared.json")) as f:
            self.assertEqual(f.read(), first)
        self.assertTrue(old)

    def test_an_episode_that_was_removed_is_never_published_again(self):
        old = self.publish_old(1, 8)
        self.go("clean")
        self.assertEqual(self.go(), 0)
        self.assertFalse(self.exists(old))
        self.assertEqual(self.cps(), [])


class SizeTests(CleanBase):
    def test_the_oldest_go_first_until_the_total_is_under_the_limit(self):
        items = [self.publish_old(n, 6 - n * 0.5) for n in range(1, 6)]  # 5.5, 5.0, 4.5, 4.0, 3.5 days
        self.go("clean", "--max-gb", SMALL)
        self.assertEqual([self.exists(i) for i in items], [False, False, True, True, True])

    def test_exactly_at_the_limit_is_under_it(self):
        items = [self.publish_old(n, n) for n in range(1, 4)]
        self.go("clean", "--max-gb", SMALL)
        self.assertEqual([self.exists(i) for i in items], [True, True, True])

    def test_the_size_counts_what_prepared_json_says_for_files_that_are_there(self):
        gone = self.publish_old(1, 5)
        os.remove(os.path.join(self.prepared_folder(), gone["id"] + ".mp3"))
        items = [self.publish_old(n, 4 - n * 0.1, size=1500) for n in range(2, 4)]
        self.go("clean", "--max-gb", SMALL)
        self.assertEqual([self.exists(i) for i in items], [True, True])

    def test_room_is_made_before_a_new_file_is_copied(self):
        old = self.publish_old(1, 3, size=2000)
        new = self.episode(2, size=2000)
        before = []
        real = self.runner

        def watch(command):
            if command[0] == "cp":
                before.append(self.exists(old))
            return real(command)
        self.runner = watch
        self.assertEqual(self.go("publish", "--max-gb", SMALL), 0, self.said)
        self.assertEqual(before, [False])  # the old copy was gone when the new one was written
        self.assertEqual(self.on_dest(), [new["id"] + ".mp3"])

    def test_a_file_bigger_than_the_whole_limit_is_left_out_and_said_and_nothing_is_removed(self):
        old = self.publish_old(1, 3, size=1000)
        self.episode(2, size=5000)
        self.assertEqual(self.go("publish", "--max-gb", SMALL), 1)
        self.assertTrue(self.exists(old))
        self.assertTrue(any("bigger than" in line for line in self.said))

    def test_publishing_cleans_by_age_first(self):
        old = self.publish_old(1, 9)
        new = self.episode(2)
        self.go()
        self.assertFalse(self.exists(old))
        self.assertEqual(self.on_dest(), [new["id"] + ".mp3"])


class SafetyTests(CleanBase):
    def everything_is_old(self):
        self.go("clean", "--keep-days", "0.0001", "--max-gb", "0.000000001")

    def test_only_ids_listed_in_prepared_json_are_ever_touched(self):
        listed = self.publish_old(1, 20)
        stranger = self.episode(2)  # in the manifest and the folder, but not in prepared.json
        os.makedirs(self.prepared_folder(), exist_ok=True)
        extras = [stranger["id"] + ".mp3", "%012x.m4a" % 99, "notes.txt", stranger["id"] + ".mp3.part",
                  "ABCDEF012345.mp3"]
        for name in extras:
            with open(os.path.join(self.prepared_folder(), name), "wb") as f:
                f.write(b"mine")
        self.everything_is_old()
        self.assertFalse(self.exists(listed))
        self.assertEqual(sorted(set(self.on_dest()) & set(extras)), sorted(extras))
        self.assertTrue(self.mac_audio(stranger))
        manifest = {e["id"]: e for e in store.load_manifest(self.folder.dir)}
        self.assertEqual(manifest[stranger["id"]]["file"], stranger["file"])

    def test_a_name_that_is_not_12_hex_and_an_extension_is_never_removed(self):
        item = self.publish_old(1, 20)
        bad = ["prepared/%s.mp3.part" % item["id"], "prepared/../transcripts/%s.txt" % item["id"],
               "prepared/abc.mp3", "prepared/%s.txt" % item["id"], "audio/%s.mp3" % item["id"],
               "/etc/passwd", "prepared/%s.mp3/" % item["id"], "prepared/%012x.mp3" % 77]
        os.makedirs(self.folder.path("transcripts"), exist_ok=True)
        with open(self.folder.path("transcripts", item["id"] + ".txt"), "w") as f:
            f.write("transcript")
        os.makedirs(self.prepared_folder(), exist_ok=True)
        with open(os.path.join(self.prepared_folder(), "%012x.mp3" % 77), "w") as f:
            f.write("not mine to remove under this id")
        found = []
        for number, name in enumerate(bad):
            found.append({"id": "%012x" % (500 + number) if number % 2 else item["id"], "file": name,
                          "sha256": "b" * 64, "bytes": 5, "published": NOW - 30 * DAY, "removed": None})
        # Entries whose id is the listed one, with a file that does not belong to it.
        found = [dict(e, id=item["id"]) for e in found]
        prepared.write_prepared(self.folder.dir, found)
        self.everything_is_old()
        self.assertTrue(self.exists(item))
        self.assertTrue(os.path.exists(self.folder.path("transcripts", item["id"] + ".txt")))
        self.assertTrue(os.path.exists(os.path.join(self.prepared_folder(), "%012x.mp3" % 77)))
        self.assertTrue(self.mac_audio(item))
        self.assertTrue(all(e["removed"] is None for e in self.listed()))
        self.assertTrue(any("not a name it removes" in line for line in self.said))

    def test_an_entry_whose_name_is_for_another_id_is_not_removed(self):
        one, two = self.publish_old(1, 20), self.publish_old(2, 20)
        found = prepared.read_prepared(self.folder.dir)
        found[0]["file"] = "prepared/%s.mp3" % two["id"]
        prepared.write_prepared(self.folder.dir, found)
        self.go("clean", "--keep-days", "7")
        self.assertTrue(self.exists(one))
        self.assertTrue(self.mac_audio(one))
        self.assertFalse(self.exists(two))

    def test_an_episode_of_the_exam_or_the_shelf_is_never_removed(self):
        exam, shelf, plain = self.publish_old(1, 20), self.publish_old(2, 20), self.publish_old(3, 20)
        with open(self.folder.path("exam.json"), "w") as f:
            json.dump({"version": 1, "episodes": [exam["id"]]}, f)
        with open(self.folder.path("shelf.json"), "w") as f:
            json.dump({"version": 1, "episodes": [shelf["id"]]}, f)
        self.everything_is_old()
        self.assertEqual([self.exists(exam), self.exists(shelf), self.exists(plain)], [True, True, False])
        self.assertTrue(self.mac_audio(exam) and self.mac_audio(shelf))
        self.assertFalse(self.mac_audio(plain))

    def test_audio_the_mac_downloaded_for_the_teaching_set_is_not_touched_without_a_copy(self):
        taught = self.episode(9, ahead_too=False)
        self.publish_old(1, 20)
        self.everything_is_old()
        self.assertTrue(self.mac_audio(taught))

    def test_a_file_that_cannot_be_removed_is_said_and_keeps_its_entry_and_the_macs_audio(self):
        item = self.publish_old(1, 20)
        real = os.remove

        def refuse(path):
            if path.endswith(item["id"] + ".mp3") and "prepared" in path:
                raise PermissionError("not allowed")
            return real(path)
        os.remove = refuse
        self.addCleanup(setattr, os, "remove", real)
        self.assertEqual(self.go("clean"), 1)
        os.remove = real
        self.assertTrue(self.exists(item))
        self.assertTrue(self.mac_audio(item))
        self.assertIsNone(self.state(item)["removed"])
        self.assertTrue(any("could not be removed" in line for line in self.said))

    def test_no_icloud_folder_removes_nothing_and_says_so(self):
        item = self.publish_old(1, 20)
        import shutil
        shutil.rmtree(self.dest)
        self.assertEqual(self.go("clean"), 3)
        self.assertTrue(self.mac_audio(item))
        self.assertIsNone(self.state(item)["removed"])


if __name__ == "__main__":
    import unittest
    unittest.main()
