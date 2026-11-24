"""Tests for the Mac's marks of the next episodes (ahead-ads.json) in teach_publish.py: published when
the phone would take it, with no scorecard gate, and listed in teaching.json. No network.
Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import json
import os
import unittest

from test_teach_publish import Setup, read

GOOD = {"version": 1, "writtenAt": 1700000000, "episodes": [
    {"feed": "https://a.test/feed", "guid": "g1", "title": "One", "marked": 1700000000,
     "ads": [{"kind": "ad", "confidence": "high", "start": 10.0, "end": 40.0,
              "startWords": "this episode is brought to you by", "endWords": "use the code"}]}]}


class AheadTests(Setup):
    def test_the_marks_are_published_and_listed_with_no_other_gate(self):
        self.source("ahead-ads.json", GOOD)
        self.assertEqual(self.main(self.one, self.two), 0, self.messages)
        for folder in (self.one, self.two):
            self.assertEqual(read(self.published(folder, "ahead-ads.json")),
                             read(os.path.join(self.teaching, "ahead-ads.json")))
            self.assertIn("ahead-ads.json",
                          json.loads(read(self.published(folder, "teaching.json")))["files"])

    def test_a_file_with_no_list_of_episodes_is_not_published_and_says_why(self):
        for value in ({"version": 1}, {"version": 1, "episodes": {"a": 1}}, {"version": 1, "episodes": "x"}):
            self.messages.clear()
            self.source("ahead-ads.json", value)
            self.assertEqual(self.main(self.one), 2, value)
            self.assertFalse(os.path.exists(self.published(self.one, "ahead-ads.json")))
            self.assertTrue(any("ahead-ads.json" in m and "list of episodes" in m
                                for m in self.messages), self.messages)

    def test_a_refused_file_leaves_the_old_published_one(self):
        self.source("ahead-ads.json", GOOD)
        self.main(self.one)
        before = read(self.published(self.one, "ahead-ads.json"))
        self.source("ahead-ads.json", raw=b"[]")
        self.assertEqual(self.main(self.one), 2)
        self.assertEqual(read(self.published(self.one, "ahead-ads.json")), before)

    def test_no_marks_yet_is_skipped_with_one_line(self):
        self.assertEqual(self.main(self.one), 0)
        said = [m for m in self.messages if "ahead-ads.json" in m]
        self.assertEqual(len(said), 1)
        self.assertIn("skipped", said[0])


if __name__ == "__main__":
    unittest.main()
