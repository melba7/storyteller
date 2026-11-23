"""Tests that teach_copies.py puts the exam episodes first, then the shelf episodes, then the
rest, each group in its usual order, and that --max still cuts the list after that.
Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import json
import os

import teach_exam
from test_teach_copies import Base


class OrderTests(Base):
    def numbers(self):
        return [int(call["address"].rsplit("/", 1)[1][:-4]) for call in self.net.calls]

    def shelf(self, *items):
        with open(self.folder.path("shelf.json"), "w") as f:
            json.dump({"version": 1, "episodes": [i["id"] for i in items]}, f)

    def test_exam_first_then_shelf_then_the_rest_each_in_their_order(self):
        items = [self.add(n) for n in range(1, 8)]
        teach_exam.add_to_exam(self.folder.dir, [items[5]["id"], items[2]["id"]])
        self.shelf(items[6], items[1])
        self.assertEqual(self.go(), 0)
        # The exam in the order of episodes.json (3, 6), the shelf (2, 7), then 1, 4, 5.
        self.assertEqual(self.numbers(), [3, 6, 2, 7, 1, 4, 5])

    def test_an_episode_on_both_lists_counts_as_exam(self):
        items = [self.add(n) for n in range(1, 4)]
        teach_exam.add_to_exam(self.folder.dir, [items[2]["id"]])
        self.shelf(items[1], items[2])
        self.go()
        self.assertEqual(self.numbers(), [3, 2, 1])

    def test_the_limit_cuts_after_the_ordering(self):
        items = [self.add(n) for n in range(1, 6)]
        teach_exam.add_to_exam(self.folder.dir, [items[4]["id"]])
        self.shelf(items[3])
        self.assertEqual(self.go("--max", "2"), 3)
        self.assertEqual(self.numbers(), [5, 4])

    def test_failed_before_still_goes_last_within_its_group(self):
        items = [self.add(n) for n in range(1, 4)]
        teach_exam.add_to_exam(self.folder.dir, [e["id"] for e in items])
        self.net.fail.add(items[0]["address"])
        self.go("--max", "1")  # episode 1 is tried first and fails
        self.net.calls.clear()
        self.net.fail.clear()
        self.go()
        self.assertEqual(self.numbers(), [2, 3, 1])

    def test_without_lists_the_order_is_as_before(self):
        for n in range(1, 4):
            self.add(n)
        self.go()
        self.assertEqual(self.numbers(), [1, 2, 3])

    def test_a_damaged_exam_or_shelf_file_is_a_set_up_problem(self):
        self.add(1)
        for name in ("exam.json", "shelf.json"):
            with open(self.folder.path(name), "w") as f:
                f.write("nope")
            self.assertEqual(self.go(), 2, name)
            self.assertIn(name, self.said[-1])
            os.remove(self.folder.path(name))
        self.assertEqual(self.net.calls, [])
