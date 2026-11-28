"""Tests for the "coming" array of ahead-ads.json: the pick writes it before anything is marked, in the
Mac's folder and the iCloud copy, the file stays version 1 with "episodes" as it was, an episode
leaves it when its copy is published and is dropped when it did not get one, and a folder that cannot
be written never stops the pick. Made-up shows only.
Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import json
import os
import unittest

import teach_ahead_ads as ads
import teach_coming
import teach_coming_publish as publish
from test_teach_ahead_ads import NOW as ADS_NOW, Night
from test_teach_ahead_ads_copy import CopyBase
from test_teach_prepare import NOW, SHOW, Prepare, feed_of

FEEDS = {SHOW["feed"]: feed_of(("a1", "A", 5, "https://cdn/a1.mp3"), ("a2", "B", 6, "https://cdn/a2.mp3"))}


def read(folder):
    with open(os.path.join(folder, "Podcasts", "ahead-ads.json")) as f:
        return json.load(f)


class PickTests(Prepare):
    def test_the_pick_writes_the_coming_entries_into_both_folders(self):
        self.assertEqual(self.run_pick(feeds=FEEDS), 0, self.said)
        want = [{"feed": SHOW["feed"], "guid": "a1", "since": NOW},
                {"feed": SHOW["feed"], "guid": "a2", "since": NOW}]
        for folder in (self.mac, self.icloud):
            data = read(folder)
            self.assertEqual(data["coming"], want)
            self.assertEqual((data["version"], data["episodes"]), (1, []))
            self.assertEqual(list(data), ["version", "writtenAt", "episodes", "coming"])
        self.assertEqual([one["guid"] for one in teach_coming.read_coming(self.folder)], ["a1", "a2"])

    def test_it_is_written_before_any_marking_is_possible(self):
        self.run_pick(feeds=FEEDS)
        # The pick is the only step that has run: no audio, no transcript, no label exists yet.
        for name in ("labels", "transcripts", "audio"):
            self.assertFalse(os.path.exists(os.path.join(self.folder, name)), name)
        self.assertEqual(len(read(self.icloud)["coming"]), 2)

    def test_the_list_of_files_the_phone_checks_knows_the_new_file(self):
        self.run_pick(feeds=FEEDS)
        with open(os.path.join(self.icloud, "Podcasts", "teaching.json")) as f:
            self.assertIn("ahead-ads.json", json.load(f)["files"])

    def test_a_pick_that_takes_nothing_writes_no_coming(self):
        self.run_pick(feeds={SHOW["feed"]: feed_of()})
        self.assertFalse(os.path.exists(os.path.join(self.mac, "Podcasts", "ahead-ads.json")))

    def test_a_folder_that_cannot_be_written_is_said_and_the_pick_still_works(self):
        os.rmdir(os.path.join(self.icloud, "Podcasts"))
        os.rmdir(self.icloud)
        self.assertEqual(self.run_pick(feeds=FEEDS), 0, self.said)
        self.assertEqual(len(read(self.mac)["coming"]), 2)
        self.assertTrue(any("did not reach" in line for line in self.said), self.said)
        self.assertEqual(len(self.manifest()), 2)

    def test_a_second_pick_keeps_the_first_since(self):
        self.run_pick(feeds=FEEDS)
        later = dict(FEEDS)
        later[SHOW["feed"]] = feed_of(("a1", "A", 5, "https://cdn/a1.mp3"), ("a2", "B", 6, "https://cdn/a2.mp3"),
                                      ("a3", "C", 7, "https://cdn/a3.mp3"))
        self.run_pick(feeds=later)
        self.assertEqual([(one["guid"], one["since"]) for one in teach_coming.read_coming(self.folder)],
                         [("a1", NOW), ("a2", NOW), ("a3", NOW)])


class SettleTests(CopyBase):
    def coming(self, *items):
        teach_coming.add_coming(self.night.dir, [{"id": i["id"], "feed": i["feed"], "guid": i["guid"]}
                                                 for i in items], ADS_NOW - 60)

    def written(self):
        ads.write(self.night.dir, ADS_NOW, self.night.said.append, to=self.to)
        with open(os.path.join(self.night.dir, ads.FILE)) as f:
            return json.load(f)

    def settle(self):
        return publish.settle(self.night.dir, self.night.said.append, lambda: ["unused", self.to],
                              lambda: ADS_NOW)

    def test_an_entry_is_in_coming_until_its_copy_is_published(self):
        item = self.night.add(1)
        self.coming(item)
        self.assertEqual(self.written()["coming"],
                         [{"feed": item["feed"], "guid": item["guid"], "since": ADS_NOW - 60}])
        self.publish(item)
        data = self.written()
        self.assertNotIn("coming", data)
        self.assertEqual(data["episodes"][0]["copy"]["bytes"], 2000)

    def test_settling_counts_the_copy_and_drops_the_episode_whose_marking_failed(self):
        good, failed = self.night.add(1), self.night.add(2)
        self.coming(good, failed)
        self.publish(good)
        self.assertEqual(self.settle(), (1, 1))
        self.assertIn("Coming: 1 now have the Mac's copy and 1 were dropped", " ".join(self.night.said))
        self.assertEqual(teach_coming.read_coming(self.night.dir), [])
        self.assertNotIn("coming", self.written())

    def test_an_episode_marked_but_without_a_copy_is_dropped_too(self):
        item = self.night.add(1)
        self.coming(item)
        self.assertEqual(self.settle(), (0, 1))
        data = self.written()
        self.assertNotIn("coming", data)
        self.assertEqual(len(data["episodes"]), 1)
        self.assertNotIn("copy", data["episodes"][0])

    def test_settling_with_nothing_coming_says_nothing_and_changes_nothing(self):
        self.assertEqual(self.settle(), (0, 0))
        self.assertEqual(self.night.said, [])

    def test_a_damaged_coming_file_counts_as_empty(self):
        with open(os.path.join(self.night.dir, teach_coming.FILE), "w") as f:
            f.write("nope")
        self.assertEqual(teach_coming.read_coming(self.night.dir), [])
        self.assertEqual(self.settle(), (0, 0))


class OldReadersTests(unittest.TestCase):
    def test_episodes_and_version_are_where_an_older_build_looks(self):
        """The phone's decoder reads version and episodes by name and ignores other keys."""
        night = Night(self)
        item = night.add(1)
        teach_coming.add_coming(night.dir, [{"id": item["id"], "feed": item["feed"], "guid": item["guid"]}], 5)
        ads.write(night.dir, ADS_NOW, night.said.append)
        with open(os.path.join(night.dir, ads.FILE)) as f:
            data = json.load(f)
        self.assertEqual(data["version"], 1)
        self.assertEqual(len(data["episodes"]), 1)
        self.assertEqual(data["coming"], [{"feed": item["feed"], "guid": item["guid"], "since": 5}])


if __name__ == "__main__":
    unittest.main()
