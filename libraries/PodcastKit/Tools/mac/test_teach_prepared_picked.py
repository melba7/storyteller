"""Tests for the episodes the pick listed in prepared.json before any file: the pick writes them,
the cleaning deletes the Mac's own audio of one that is old and was never published, and the cleaning
removes old leftover .part files of listed ids. The hard rules hold: only listed ids, never the exam
or the shelf, never anything but audio. Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import json
import os
import unittest

import teach_ahead_set as ahead
import teach_prepared_file as pfile
import teach_store as store
from test_teach_prepare import SHOW, Prepare, feed_of
from test_teach_prepared import DAY, NOW, Base
from test_teach_prepared_clean import CleanBase


class PickWritesTests(Prepare):
    def test_what_the_pick_takes_is_listed_as_picked_with_no_file(self):
        self.write_queue([self.queued_one()])
        feeds = {SHOW["feed"]: feed_of(("a1", "A", 5, "https://cdn/a1.mp3"))}
        self.assertEqual(self.run_pick(feeds=feeds), 0)
        found = pfile.read_prepared(self.folder)
        self.assertEqual([e["id"] for e in found], [e["id"] for e in self.manifest()])
        self.assertEqual(len(found), 2)
        for one in found:
            self.assertEqual((one["file"], one["sha256"], one["bytes"], one["published"], one["picked"],
                              one["removed"]), (None, None, 0, None, 1_800_000_000, None))

    def test_a_second_pick_does_not_list_an_episode_twice(self):
        feeds = {SHOW["feed"]: feed_of(("a1", "A", 5, "https://cdn/a1.mp3"))}
        self.run_pick(feeds=feeds)
        feeds = {SHOW["feed"]: feed_of(("a1", "A", 5, "https://cdn/a1.mp3"), ("a2", "B", 6, "https://cdn/a2.mp3"))}
        self.run_pick(feeds=feeds)
        self.assertEqual(len(pfile.read_prepared(self.folder)), 2)

    def test_a_pick_that_finds_nothing_writes_no_file(self):
        self.run_pick(feeds={SHOW["feed"]: feed_of()})
        self.assertFalse(os.path.exists(os.path.join(self.folder, "prepared.json")))

    def test_a_damaged_prepared_json_stops_the_pick_with_nothing_changed(self):
        with open(os.path.join(self.folder, "prepared.json"), "w") as f:
            f.write("nope")
        feeds = {SHOW["feed"]: feed_of(("a1", "A", 5, "https://cdn/a1.mp3"))}
        self.assertEqual(self.run_pick(feeds=feeds), 2)
        self.assertEqual((self.manifest(), ahead.read_ahead(self.folder)), ([], []))

    @staticmethod
    def queued_one():
        from test_teach_ahead import queued
        return queued(1)


class PickedCleaningTests(CleanBase):
    def picked(self, number, days, ahead_too=True, **more):
        """An episode the pick took `days` ago that was never published; its audio is on the Mac."""
        item = self.episode(number, ahead_too=ahead_too, **more)
        found = pfile.read_prepared(self.folder.dir)
        found.append({"id": item["id"], "file": None, "sha256": None, "bytes": 0, "published": None,
                      "picked": NOW - int(days * DAY), "removed": None})
        pfile.write_prepared(self.folder.dir, found)
        return item

    def test_the_macs_audio_of_an_old_picked_episode_goes_and_its_entry_is_put_right(self):
        old, young = self.picked(1, 7.1), self.picked(2, 6.9)
        self.assertEqual(self.go("clean"), 0, self.said)
        self.assertFalse(self.mac_audio(old))
        self.assertTrue(self.mac_audio(young))
        manifest = {e["id"]: e for e in store.load_manifest(self.folder.dir)}
        self.assertEqual((manifest[old["id"]]["file"], manifest[old["id"]]["bytes"]), (None, 0))
        self.assertTrue(manifest[old["id"]]["error"].startswith("skipped:"))
        self.assertEqual((self.state(old)["removed"], self.state(young)["removed"]), (NOW, None))

    def test_nothing_in_icloud_and_no_other_file_is_touched_for_a_picked_episode(self):
        old = self.picked(1, 20)
        for folder, name in (("transcripts", ".txt"), ("copies", ".truth.txt")):
            os.makedirs(self.folder.path(folder), exist_ok=True)
            with open(self.folder.path(folder, old["id"] + name), "w") as f:
                f.write("kept")
        self.go("clean")
        for folder, name in (("transcripts", ".txt"), ("copies", ".truth.txt"), ("labels", ".json")):
            self.assertTrue(os.path.exists(self.folder.path(folder, old["id"] + name)), folder)
        self.assertFalse(os.path.isdir(self.prepared_folder()))

    def test_an_episode_the_nightly_read_ahead_picked_is_not_listed_so_it_is_not_touched(self):
        nightly = self.episode(5)  # in ahead.json and the manifest, not in prepared.json
        self.picked(1, 20)
        self.go("clean", "--keep-days", "0")
        self.assertTrue(self.mac_audio(nightly))

    def test_an_exam_or_shelf_episode_that_is_listed_as_picked_is_never_touched(self):
        exam, shelf = self.picked(1, 20), self.picked(2, 20)
        with open(self.folder.path("exam.json"), "w") as f:
            json.dump({"version": 1, "episodes": [exam["id"]]}, f)
        with open(self.folder.path("shelf.json"), "w") as f:
            json.dump({"version": 1, "episodes": [shelf["id"]]}, f)
        self.go("clean")
        self.assertTrue(self.mac_audio(exam) and self.mac_audio(shelf))

    def test_an_episode_that_was_published_is_not_treated_as_a_picked_one(self):
        item = self.picked(1, 3)
        self.go()  # it is settled, so it is published, and the entry keeps when it was picked
        found = self.state(item)
        self.assertEqual((found["file"], found["published"], found["picked"]),
                         ("prepared/%s.mp3" % item["id"], NOW, NOW - 3 * DAY))
        self.assertTrue(self.exists(item))

    def test_publishing_cleans_first_so_an_old_picked_episode_is_not_published(self):
        item = self.picked(1, 20)
        self.go()
        self.assertFalse(self.exists(item))
        self.assertFalse(self.mac_audio(item))

    def test_a_removed_picked_episode_is_never_published_later(self):
        old = self.picked(1, 20)
        self.go("clean")
        self.assertEqual(self.go(), 0)
        self.assertEqual(self.on_dest(), [])
        self.assertTrue(old)


class LeftoverPartTests(CleanBase):
    def part(self, name, age_days, number=None):
        os.makedirs(self.prepared_folder(), exist_ok=True)
        path = os.path.join(self.prepared_folder(), name)
        with open(path, "wb") as f:
            f.write(b"half")
        os.utime(path, (NOW - age_days * DAY, NOW - age_days * DAY))
        return path

    def test_an_old_leftover_part_of_a_listed_id_is_removed_and_a_young_one_stays(self):
        item = self.publish_old(1, 1)
        old = self.part(item["id"] + ".mp3.part", 1.1)
        young = self.part("%s.m4a.part" % item["id"], 0.5)
        self.go("clean")
        self.assertFalse(os.path.exists(old))
        self.assertTrue(os.path.exists(young))
        self.assertTrue(self.exists(item))

    def test_only_that_name_of_a_listed_id_is_removed(self):
        item = self.publish_old(1, 1)
        stranger = "%012x" % 99
        keep = [self.part(stranger + ".mp3.part", 5), self.part("notes.txt", 5),
                self.part(item["id"] + ".txt.part", 5), self.part(item["id"] + ".mp3.part.part", 5),
                self.part("ABCDEF012345.mp3.part", 5), self.part(item["id"] + ".mp3.partial", 5)]
        self.go("clean")
        self.assertTrue(all(os.path.exists(path) for path in keep))

    def test_a_leftover_of_an_exam_or_shelf_id_stays(self):
        item = self.publish_old(1, 1)
        with open(self.folder.path("exam.json"), "w") as f:
            json.dump({"version": 1, "episodes": [item["id"]]}, f)
        path = self.part(item["id"] + ".mp3.part", 5)
        self.go("clean")
        self.assertTrue(os.path.exists(path))

    def test_all_parts_removes_every_part_of_that_exact_form_of_any_age_and_nothing_else(self):
        item = self.publish_old(1, 1)
        stranger = "%012x" % 99
        gone = [self.part(item["id"] + ".mp3.part", 0.01), self.part(stranger + ".m4a.part", 5)]
        keep = [self.part("notes.txt", 5), self.part(item["id"] + ".txt.part", 5),
                self.part("ABCDEF012345.mp3.part", 5), self.part(item["id"] + ".mp3.partial", 5)]
        self.go("clean", "--all-parts")
        self.assertFalse(any(os.path.exists(path) for path in gone))
        self.assertTrue(all(os.path.exists(path) for path in keep))
        self.assertTrue(self.exists(item))  # the copy itself is only cleaned by age and size

    def test_all_parts_leaves_the_part_of_an_exam_or_shelf_episode_and_other_folders_alone(self):
        item = self.publish_old(1, 1)
        with open(self.folder.path("shelf.json"), "w") as f:
            json.dump({"version": 1, "episodes": [item["id"]]}, f)
        path = self.part(item["id"] + ".mp3.part", 5)
        elsewhere = os.path.join(self.dest, "Podcasts", "%012x.mp3.part" % 7)
        with open(elsewhere, "wb") as f:
            f.write(b"x")
        self.go("clean", "--all-parts")
        self.assertTrue(os.path.exists(path) and os.path.exists(elsewhere))

    def test_keep_days_zero_removes_every_listed_copy_by_the_same_rules(self):
        items = [self.publish_old(n, 0.001) for n in (1, 2)]
        self.go("clean", "--keep-days", "0")
        self.assertEqual([self.exists(i) for i in items], [False, False])
        self.assertEqual([self.mac_audio(i) for i in items], [False, False])


if __name__ == "__main__":
    unittest.main()
