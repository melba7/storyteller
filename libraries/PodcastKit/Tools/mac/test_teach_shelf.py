"""Tests for teach_shelf.py: which episodes go on the shelf, reading shelf.json, and the precision
and recall on the shelf. No network.
Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import json
import os
import shutil
import tempfile
import unittest

import teach_shelf as shelving
import teach_store as store
from test_teach_train import entry


class ShelfTests(unittest.TestCase):
    def test_newest_of_each_show_with_three_or_more(self):
        entries = [entry("%012x" % n, feed, pub) for n, (feed, pub) in enumerate(
            [("a", 10), ("a", 30), ("a", 20), ("b", 5), ("b", 6)], 1)]
        usable = {e["id"] for e in entries}
        self.assertEqual(shelving.choose_shelf(entries, usable, []), ["%012x" % 2])

    def test_undated_counts_oldest_and_ties_go_to_the_first(self):
        entries = [entry("%012x" % n, "a", pub) for n, pub in enumerate([None, 7, 7], 1)]
        self.assertEqual(shelving.choose_shelf(entries, {e["id"] for e in entries}, []), ["%012x" % 2])
        entries = [entry("%012x" % n, "a", pub) for n, pub in enumerate([None, None, None], 1)]
        self.assertEqual(shelving.choose_shelf(entries, {e["id"] for e in entries}, []), ["%012x" % 1])

    def test_only_usable_episodes_count(self):
        entries = [entry("%012x" % n, "a", n) for n in range(1, 4)]
        self.assertEqual(shelving.choose_shelf(entries, {"%012x" % 1, "%012x" % 2}, []), [])

    def test_a_shelved_episode_stays_and_its_show_gets_no_second(self):
        entries = [entry("%012x" % n, "a", n) for n in range(1, 5)]
        usable = {e["id"] for e in entries}
        shelf = shelving.choose_shelf(entries[:3], usable, [])
        self.assertEqual(shelf, ["%012x" % 3])
        self.assertEqual(shelving.choose_shelf(entries, usable, shelf), shelf)

    def test_reading_the_shelf_file(self):
        folder = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, folder, True)
        self.assertEqual(shelving.read_shelf(folder), [])
        path = os.path.join(folder, "shelf.json")
        with open(path, "w") as f:
            json.dump({"version": 1, "episodes": ["a", "b"]}, f)
        self.assertEqual(shelving.read_shelf(folder), ["a", "b"])
        with open(path, "w") as f:
            json.dump({"version": 2, "episodes": []}, f)
        with self.assertRaises(store.Problem):
            shelving.read_shelf(folder)


class CheckTests(unittest.TestCase):
    # One bucket per line decides the prediction: lines 0..5 use buckets 1..6.
    WEIGHTS = {1: [5, 0, 0, 0, 0], 2: [0, 5, 0, 0, 0], 3: [0, 5, 0, 0, 0],
               4: [0, 0, 5, 0, 0], 5: [0, 5, 0, 0, 0], 6: [5, 0, 0, 0, 0]}

    def example(self, classes, buckets, feed="a"):
        starts = [10.0 * i for i in range(len(classes))]
        return {"id": "x", "feed": feed, "classes": classes, "buckets": buckets, "starts": starts,
                "ends": [t + 10.0 for t in starts]}

    def test_per_line_precision_and_recall(self):
        example = self.example([0, 1, 1, 2, 0, 3], [[1], [2], [3], [4], [5], [6]])
        result = shelving.evaluate(self.WEIGHTS, [example])
        self.assertEqual(result["episodes"], 1)
        self.assertEqual(result["shows"], 1)
        self.assertEqual(result["lines"], 6)
        # Predicted ads: lines 1, 2, 3, 4 (not none). Real ads: 1, 2, 3, 5.
        self.assertEqual(result["lineAnyAd"], {"precision": 0.75, "recall": 0.75})
        self.assertEqual(result["classes"]["sponsor"], {"precision": 0.6667, "recall": 1.0})
        self.assertEqual(result["classes"]["network_promo"], {"precision": 1.0, "recall": 1.0})
        self.assertEqual(result["classes"]["host_ask"], {"precision": None, "recall": 0.0})
        self.assertEqual(result["classes"]["intro_credits"], {"precision": None, "recall": None})

    def test_any_ad_is_the_seconds_the_phone_would_cut(self):
        # Lines 2 to 5 are predicted ads and make one span, but line 5 is 30 s long and is not an
        # ad, so 60 s are cut and 30 s of them are right. Lines 2, 3, 4 and 6 are real ads (40 s).
        example = self.example([0, 1, 1, 2, 0, 3], [[1], [2], [3], [4], [5], [6]])
        example["ends"][4] = example["starts"][4] + 30.0
        result = shelving.evaluate(self.WEIGHTS, [example])
        self.assertEqual(result["predictedAdSeconds"], 60.0)
        self.assertEqual(result["anyAd"], {"precision": 0.5, "recall": 0.75})

    def test_the_shelf_size_is_counted(self):
        one = self.example([0, 1], [[1], [2]], feed="a")
        two = dict(self.example([0, 1], [[1], [2]], feed="b"), id="y")
        three = dict(self.example([0, 1], [[1], [2]], feed="b"), id="z")
        result = shelving.evaluate(self.WEIGHTS, [one, two, three])
        self.assertEqual((result["episodes"], result["shows"]), (3, 2))

    def test_left_out_lines_are_not_scored_per_line(self):
        weights = {1: [5, 0, 0, 0, 0]}
        result = shelving.evaluate(weights, [self.example([0, None, None, 0], [[1]] * 4)])
        self.assertEqual(result["lines"], 2)

    def test_no_shelf(self):
        result = shelving.evaluate({}, [])
        self.assertEqual(result["episodes"], 0)
        self.assertEqual(result["shows"], 0)
        self.assertEqual(result["lines"], 0)
        self.assertEqual(result["predictedAdSeconds"], 0)
        self.assertEqual(result["anyAd"], {"precision": None, "recall": None})

    def test_the_closing_lines_say_n_a_for_nothing_to_divide(self):
        held = shelving.evaluate({}, [])
        lines = shelving.check_lines(held)
        self.assertIn("precision n/a, recall n/a", lines[0])
        self.assertEqual(len(lines), 5)


if __name__ == "__main__":
    unittest.main()
