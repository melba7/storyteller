"""Tests that teach_publish.py publishes a version 2 word model like a version 1 one, and still
refuses every other file that is not version 1. No network.
Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import os

import teach_publish as publish
from test_teach_publish import Setup, model, read
from teach_features import bucket


def two(precision=0.9):
    value = model(precision)
    value["version"] = 2
    value["buckets"] = 4194304
    value["weights"] = {str(bucket("#bias", 4194304)): [4.0, 0, 0, 0, 0]}
    return value


class VersionTwoTests(Setup):
    def test_a_version_2_model_is_published(self):
        self.source("ad-model.json", two())
        self.assertEqual(self.main(self.one), 0)
        self.assertEqual(read(self.published(self.one, "ad-model.json")),
                         read(os.path.join(self.teaching, "ad-model.json")))

    def test_a_version_2_model_with_a_weak_check_is_not_published(self):
        self.source("ad-model.json", two(0.4))
        self.main(self.one)
        self.assertFalse(os.path.exists(self.published(self.one, "ad-model.json")))
        self.assertIn("precision", self.messages[0])

    def test_only_the_model_may_be_version_2(self):
        path = self.source("ad-library.json", {"version": 2, "ads": []})
        with self.assertRaises(ValueError):
            publish.checked(path)
        self.assertEqual(self.main(self.one), 2)
        self.assertFalse(os.path.exists(self.published(self.one, "ad-library.json")))

    def test_checked_names_the_versions_it_takes(self):
        path = self.source("ad-model.json", {"version": 3})
        with self.assertRaises(ValueError) as error:
            publish.checked(path, versions=(1, 2))
        self.assertIn("1 or 2", str(error.exception))
