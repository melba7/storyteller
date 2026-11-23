"""Tests that teach_habits.py leaves the sealed exam (exam.json) out.
Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import json
import os
import unittest

import teach_exam
import test_teach_habits as base
from test_teach_habits import label, span


class HabitsExamTests(unittest.TestCase):
    setUp = base.MainTests.setUp
    episodes = base.MainTests.episodes
    put = base.MainTests.put
    main = base.MainTests.main

    def test_the_labels_of_exam_episodes_do_not_count(self):
        self.episodes()
        self.put("aaaaaaaaaaaa.json", label("aaaaaaaaaaaa", "feedA", span(5, 30)))
        self.put("bbbbbbbbbbbb.json", label("bbbbbbbbbbbb", "feedA", span(500, 530)))
        teach_exam.add_to_exam(self.dir, ["bbbbbbbbbbbb"])
        self.assertEqual(self.main(), 0)
        with open(os.path.join(self.dir, "habits.json")) as f:
            shows = json.load(f)["shows"]
        self.assertEqual((shows[0]["episodes"], shows[0]["opensWithAd"]), (1, 1))

    def test_only_exam_labels_is_the_same_as_no_labels(self):
        self.episodes()
        self.put("aaaaaaaaaaaa.json", label("aaaaaaaaaaaa", "feedA", span(5, 30)))
        teach_exam.add_to_exam(self.dir, ["aaaaaaaaaaaa"])
        self.assertEqual(self.main(), 0)
        self.assertIn("No labels yet", self.said[-1])
        self.assertFalse(os.path.exists(os.path.join(self.dir, "habits.json")))

    def test_a_damaged_exam_file_is_a_set_up_problem(self):
        self.episodes()
        self.put("aaaaaaaaaaaa.json", label("aaaaaaaaaaaa", "feedA", span(5, 30)))
        with open(os.path.join(self.dir, "exam.json"), "w") as f:
            f.write("nope")
        self.assertEqual(self.main(), 2)
        self.assertIn("exam.json", self.said[-1])
