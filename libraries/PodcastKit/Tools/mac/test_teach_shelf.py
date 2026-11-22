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
    def example(self, classes):
        return {"id": "x", "classes": classes, "buckets": [[1]] * len(classes)}

    def test_precision_and_recall(self):
        # One bucket per line decides the prediction: lines 0..5 use buckets 1..6.
        weights = {1: [5, 0, 0, 0, 0], 2: [0, 5, 0, 0, 0], 3: [0, 5, 0, 0, 0],
                   4: [0, 0, 5, 0, 0], 5: [0, 5, 0, 0, 0], 6: [5, 0, 0, 0, 0]}
        example = {"id": "x", "classes": [0, 1, 1, 2, 0, 3],
                   "buckets": [[1], [2], [3], [4], [5], [6]]}
        result = shelving.evaluate(weights, [example])
        self.assertEqual(result["episodes"], 1)
        self.assertEqual(result["lines"], 6)
        # Predicted ads: lines 1, 2, 3, 4 (not none). Real ads: 1, 2, 3, 5.
        self.assertEqual(result["anyAd"], {"precision": 0.75, "recall": 0.75})
        self.assertEqual(result["classes"]["sponsor"], {"precision": 0.6667, "recall": 1.0})
        self.assertEqual(result["classes"]["network_promo"], {"precision": 1.0, "recall": 1.0})
        self.assertEqual(result["classes"]["host_ask"], {"precision": None, "recall": 0.0})
        self.assertEqual(result["classes"]["intro_credits"], {"precision": None, "recall": None})

    def test_left_out_lines_are_not_scored(self):
        weights = {1: [5, 0, 0, 0, 0]}
        result = shelving.evaluate(weights, [{"id": "x", "classes": [0, None, None, 0],
                                           "buckets": [[1]] * 4}])
        self.assertEqual(result["lines"], 2)

    def test_no_shelf(self):
        result = shelving.evaluate({}, [])
        self.assertEqual(result["episodes"], 0)
        self.assertEqual(result["lines"], 0)
        self.assertEqual(result["anyAd"], {"precision": None, "recall": None})

    def test_the_closing_lines_say_n_a_for_nothing_to_divide(self):
        held = shelving.evaluate({}, [])
        lines = shelving.check_lines(held)
        self.assertIn("any ad precision n/a, recall n/a", lines[0])
        self.assertEqual(len(lines), 5)


if __name__ == "__main__":
    unittest.main()
