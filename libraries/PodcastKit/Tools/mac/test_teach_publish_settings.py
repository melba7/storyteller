"""Tests for the per-show settings file in teach_publish.py (published when valid, no other gate) and
for the list of files it publishes, which must be the list the phone fetches. No network.
Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import json
import os
import re
import unittest

import teach_publish as publish
from test_teach_publish import Setup, read

TEACHING_TS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "..",
                           "applications", "mobile", "modules", "podcasts", "teaching.ts")


class SettingsTests(Setup):
    GOOD = {"version": 1, "writtenAt": 1700000000, "default": {"joints": True}, "shows": []}

    def test_a_valid_settings_file_is_published_with_no_other_gate(self):
        self.source("show-settings.json", self.GOOD)
        self.assertEqual(self.main(self.one, self.two), 0, self.messages)
        for folder in (self.one, self.two):
            self.assertEqual(read(self.published(folder, "show-settings.json")),
                             read(os.path.join(self.teaching, "show-settings.json")))
            self.assertIn("show-settings.json",
                          json.loads(read(self.published(folder, "teaching.json")))["files"])

    def test_it_needs_no_scorecard_and_no_held_out_check(self):
        self.source("show-settings.json", {"version": 1, "shows": []})
        self.assertEqual(self.main(self.one), 0)
        self.assertTrue(os.path.exists(self.published(self.one, "show-settings.json")))

    def test_what_the_phone_would_refuse_is_not_published_and_says_why(self):
        for value in ({"version": 1}, {"version": 1, "shows": {"a": 1}}, {"version": 1, "shows": "x"}):
            self.messages.clear()
            self.source("show-settings.json", value)
            self.assertEqual(self.main(self.one), 2, value)
            self.assertFalse(os.path.exists(self.published(self.one, "show-settings.json")))
            self.assertTrue(any("show-settings.json" in m and "list of shows" in m
                                for m in self.messages), self.messages)

    def test_a_file_that_is_not_version_1_is_refused_like_the_others(self):
        self.source("show-settings.json", {"version": 2, "shows": []})
        self.assertEqual(self.main(self.one), 2)
        self.assertFalse(os.path.exists(self.published(self.one, "show-settings.json")))

    def test_a_refused_file_leaves_the_old_published_one(self):
        self.source("show-settings.json", self.GOOD)
        self.main(self.one)
        before = read(self.published(self.one, "show-settings.json"))
        self.source("show-settings.json", raw=b"[]")
        self.assertEqual(self.main(self.one), 2)
        self.assertEqual(read(self.published(self.one, "show-settings.json")), before)

    def test_a_missing_settings_file_is_skipped_with_one_line(self):
        self.assertEqual(self.main(self.one), 0)
        said = [m for m in self.messages if "show-settings.json" in m]
        self.assertEqual(len(said), 1)
        self.assertIn("skipped", said[0])


class NamesTests(unittest.TestCase):
    def test_the_files_published_are_the_files_the_phone_fetches(self):
        with open(TEACHING_TS, encoding="utf-8") as f:
            text = f.read()
        block = re.search(r"export const TEACHING_NAMES = \[(.*?)\] as const", text, re.S).group(1)
        fetched = re.findall(r'"([^"]+)"', block)
        # The six files of FILES, then the nightly read-ahead's file (publish.AHEAD).
        self.assertEqual(fetched, [target for _, target in publish.FILES + (publish.AHEAD,)])
        self.assertEqual(len(fetched), 7)


if __name__ == "__main__":
    unittest.main()
