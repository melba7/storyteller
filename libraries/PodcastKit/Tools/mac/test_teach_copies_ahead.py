"""Tests that teach_copies.py --only-ahead compares only the episodes of ahead.json that have no
truth file yet, and that without the option everything is as before.
Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import os

import teach_ahead_set as ahead
import teach_truth
from test_teach_copies import STRETCH, Base


class OnlyAheadTests(Base):
    def put_ahead(self, *items):
        ahead.add_ahead(self.folder.dir, [{"id": i["id"], "feed": "https://f", "guid": "g",
                                           "title": "t", "picked": 1} for i in items])

    def addresses(self):
        return [call["address"] for call in self.net.calls]

    def test_only_the_episodes_of_ahead_json_are_downloaded_a_second_time(self):
        items = [self.add(n) for n in range(1, 5)]
        self.put_ahead(items[1], items[3])
        self.assertEqual(self.go("--only-ahead"), 0)
        self.assertEqual(self.addresses(), [items[1]["address"], items[3]["address"]])

    def test_an_ahead_episode_that_has_a_truth_file_is_not_compared_again(self):
        items = [self.add(n) for n in range(1, 3)]
        self.put_ahead(*items)
        os.makedirs(self.folder.path("copies"))
        teach_truth.save_bytes(teach_truth.truth_path(self.folder.dir, items[0]["id"]), STRETCH.encode())
        self.go("--only-ahead")
        self.assertEqual(self.addresses(), [items[1]["address"]])

    def test_without_the_option_every_marked_episode_is_compared_as_before(self):
        items = [self.add(n) for n in range(1, 4)]
        self.put_ahead(items[0])
        self.go()
        self.assertEqual(len(self.net.calls), 3)

    def test_with_no_ahead_json_nothing_is_compared(self):
        self.add(1)
        self.assertEqual(self.go("--only-ahead"), 0)
        self.assertEqual(self.net.calls, [])
        self.assertIn("No marked episode has an audio file on disk, so there is nothing to compare.", self.said)

    def test_a_damaged_ahead_json_is_a_set_up_problem(self):
        self.add(1)
        with open(self.folder.path("ahead.json"), "w") as f:
            f.write("nope")
        self.assertEqual(self.go("--only-ahead"), 2)
        self.assertEqual(self.net.calls, [])
