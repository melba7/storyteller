"""Tests that teach_prepared.py publishes an episode's audio only once its second download is
settled (a truth file, given up on after three failures, or not an MP3), so the times the phone gets
with a copy never change afterwards; and that an episode that waits is published on a later run.
Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import json
import os

from test_teach_prepared import Base


class SettledTests(Base):
    def failed(self, item, count):
        os.makedirs(self.folder.path("copies"), exist_ok=True)
        with open(self.folder.path("copies", "failed.json"), "w") as f:
            json.dump({"version": 1, "failed": {item["id"]: count}}, f)

    def test_an_mp3_with_no_second_download_yet_waits(self):
        self.episode(1, settled=False)
        self.assertEqual(self.go(), 0, self.said)
        self.assertEqual((self.cps(), self.on_dest(), self.listed()), ([], [], []))

    def test_a_waiting_episode_is_published_on_a_later_run_once_a_truth_file_exists(self):
        item = self.episode(1, settled=False)
        self.go()
        os.makedirs(self.folder.path("copies"))
        with open(self.folder.path("copies", item["id"] + ".truth.txt"), "w") as f:
            f.write("0:33.480 1:02.120\n")
        self.assertEqual(self.go(), 0, self.said)
        self.assertEqual(self.on_dest(), [item["id"] + ".mp3"])

    def test_an_episode_whose_comparison_was_given_up_on_is_published(self):
        item = self.episode(1, settled=False)
        self.failed(item, 3)
        self.go()
        self.assertEqual(self.on_dest(), [item["id"] + ".mp3"])

    def test_one_or_two_failures_are_not_giving_up(self):
        item = self.episode(1, settled=False)
        self.failed(item, 2)
        self.go()
        self.assertEqual(self.on_dest(), [])

    def test_a_file_that_is_not_an_mp3_needs_no_second_download(self):
        item = self.episode(1, settled=False, extension="m4a")
        self.go()
        self.assertEqual(self.on_dest(), [item["id"] + ".m4a"])

    def test_a_waiting_episode_does_not_keep_a_settled_one_from_being_published(self):
        self.episode(1, settled=False)
        ready = self.episode(2)
        self.go()
        self.assertEqual(self.on_dest(), [ready["id"] + ".mp3"])
