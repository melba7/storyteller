"""Tests for ahead-ads.json in teach_publish.py: it is published like the other files (JSON, version
1, at most 4.5 MB), into every folder, and listed in teaching.json with its checksum, so the phone
can fetch it by that list. The six names in FILES stay the six the phone fetches today. No network.
Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import hashlib
import json
import os
import unittest

import teach_publish as publish
from test_teach_publish import Setup, read

NIGHT = {"version": 1, "writtenAt": 1800000000, "episodes": [
    {"feed": "https://f", "guid": "g", "title": "T", "marked": 1800000000, "ads": []}]}


class AheadAdsTests(Setup):
    def test_it_is_published_to_every_folder_and_listed_with_its_checksum(self):
        path = self.source("ahead-ads.json", NIGHT)
        self.assertEqual(self.main(self.one, self.two), 0, self.messages)
        for folder in (self.one, self.two):
            self.assertEqual(read(self.published(folder, "ahead-ads.json")), read(path))
            listed = json.loads(read(self.published(folder, "teaching.json")))["files"]
            self.assertEqual(listed["ahead-ads.json"],
                             {"sha256": hashlib.sha256(read(path)).hexdigest(), "bytes": len(read(path))})

    def test_it_is_published_with_the_other_files(self):
        self.all_sources()
        self.source("ahead-ads.json", NIGHT)
        self.assertEqual(self.main(self.one), 0, self.messages)
        files = json.loads(read(self.published(self.one, "teaching.json")))["files"]
        self.assertEqual(sorted(files), sorted(["ad-model.json", "ad-library.json", "show-habits.json",
                                                "ad-sounds.json", "ahead-ads.json"]))

    def test_a_changed_file_is_written_again_and_an_unchanged_one_is_left_alone(self):
        self.source("ahead-ads.json", NIGHT)
        self.main(self.one)
        self.messages.clear()
        self.main(self.one)
        self.assertIn("ahead-ads.json in %s: unchanged." % self.one, self.messages)
        self.source("ahead-ads.json", dict(NIGHT, writtenAt=1800000001))
        self.main(self.one)
        self.assertEqual(json.loads(read(self.published(self.one, "ahead-ads.json")))["writtenAt"],
                         1800000001)

    def test_a_missing_file_is_skipped_quietly_and_not_listed(self):
        self.source("show-settings.json", {"version": 1, "shows": []})
        self.assertEqual(self.main(self.one), 0)
        self.assertEqual([m for m in self.messages if "ahead-ads.json" in m], [])
        listed = json.loads(read(self.published(self.one, "teaching.json")))["files"]
        self.assertNotIn("ahead-ads.json", listed)

    def test_what_is_not_fit_to_publish_is_refused_and_the_old_copy_stays(self):
        self.source("ahead-ads.json", NIGHT)
        self.main(self.one)
        before = read(self.published(self.one, "ahead-ads.json"))
        for raw in (b"[]", b"{nope", json.dumps(dict(NIGHT, version=2)).encode()):
            self.source("ahead-ads.json", raw=raw)
            self.assertEqual(self.main(self.one), 2, raw)
            self.assertEqual(read(self.published(self.one, "ahead-ads.json")), before)

    def test_a_file_over_the_limit_is_refused(self):
        self.source("ahead-ads.json", NIGHT)
        self.assertEqual(self.main(self.one, limit=10), 2)
        self.assertFalse(os.path.exists(self.published(self.one, "ahead-ads.json")))

    def test_the_six_files_the_phone_fetches_today_are_unchanged(self):
        self.assertEqual([target for _, target in publish.FILES],
                         ["ad-model.json", "ad-library.json", "show-habits.json", "ad-sounds.json",
                          "ad-meaning.json", "show-settings.json"])
        self.assertEqual(publish.AHEAD, ("ahead-ads.json", "ahead-ads.json"))


if __name__ == "__main__":
    unittest.main()
