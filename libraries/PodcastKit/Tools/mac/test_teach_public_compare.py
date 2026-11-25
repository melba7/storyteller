"""Tests for teach_public_compare.py: does the word model do better on the held-out shelf when it also
learns from the marked public transcripts? It builds two scratch folders of symbolic links and trains in
each, here with a stand-in trainer. No Claude, no network.
Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import json
import os
import shutil
import tempfile
import unittest

import teach_public_compare as compare
import teach_store as store
from teach_testing import entry


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(text)


class Folders(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.root, ignore_errors=True)
        self.main = os.path.join(self.root, "main")
        self.public = os.path.join(self.root, "public")
        self.work = os.path.join(self.root, "work")
        self.main_entries = [entry(1), entry(2)]
        self.public_entries = [entry(101, host="sporc"), entry(102, host="sporc"), entry(103, host="sporc")]
        store.save_manifest(self.main, self.main_entries)
        store.save_manifest(self.public, self.public_entries)
        for item in self.main_entries:
            write(os.path.join(self.main, "transcripts", item["id"] + ".txt"), "[00:00:01.0] hi\n")
            write(os.path.join(self.main, "labels-snapped", item["id"] + ".json"), "{}")
        # Public episode 103 has no label yet, 102 has no transcript.
        for item in self.public_entries[:2]:
            write(os.path.join(self.public, "labels", item["id"] + ".json"), '{"public": true}')
        for item in (self.public_entries[0], self.public_entries[2]):
            write(os.path.join(self.public, "transcripts", item["id"] + ".txt"), "[00:00:01.0] public\n")
        write(os.path.join(self.main, "shelf.json"), '{"version": 1, "episodes": ["x"]}')
        write(os.path.join(self.main, "exam.json"), '{"episodes": ["y"]}')

    def ids(self, folder):
        return sorted(item["id"] for item in store.load_manifest(folder))

    def test_the_base_folder_has_only_the_main_episodes(self):
        base, _ = compare.make_folders(self.main, self.public, self.work, "labels-snapped")
        self.assertEqual(self.ids(base), sorted(item["id"] for item in self.main_entries))

    def test_the_public_folder_adds_only_episodes_with_a_label_and_a_transcript(self):
        _, mixed = compare.make_folders(self.main, self.public, self.work, "labels-snapped")
        added = set(self.ids(mixed)) - {item["id"] for item in self.main_entries}
        self.assertEqual(added, {self.public_entries[0]["id"]})

    def test_files_are_links_so_nothing_is_copied_and_the_live_folders_are_not_written(self):
        _, mixed = compare.make_folders(self.main, self.public, self.work, "labels-snapped")
        transcript = os.path.join(mixed, "transcripts", self.public_entries[0]["id"] + ".txt")
        self.assertTrue(os.path.islink(transcript))
        self.assertTrue(os.path.islink(os.path.join(mixed, "labels-snapped", self.public_entries[0]["id"] + ".json")))
        self.assertFalse(os.path.exists(os.path.join(self.main, "ad-model.json")))
        self.assertFalse(os.path.exists(os.path.join(self.public, "ad-model.json")))

    def test_the_shelf_and_the_exam_are_copied_so_they_stay_out_of_training(self):
        for folder in compare.make_folders(self.main, self.public, self.work, "labels-snapped"):
            for name in ("shelf.json", "exam.json"):
                with open(os.path.join(folder, name), encoding="utf-8") as handle:
                    self.assertTrue(handle.read())

    def test_making_the_folders_again_starts_clean(self):
        compare.make_folders(self.main, self.public, self.work, "labels-snapped")
        write(os.path.join(self.work, "with-public", "stale.txt"), "x")
        _, mixed = compare.make_folders(self.main, self.public, self.work, "labels-snapped")
        self.assertFalse(os.path.exists(os.path.join(mixed, "stale.txt")))

    def test_no_labelled_public_episode_is_said_plainly(self):
        shutil.rmtree(os.path.join(self.public, "labels"))
        said = []
        code = compare.run(self.main, self.public, self.work, "labels-snapped", None, say=said.append,
                           train=lambda folder: 0)
        self.assertEqual(code, 2)
        self.assertIn("Mark the public transcripts", " ".join(said))


class Report(unittest.TestCase):
    def model(self, precision, recall, episodes):
        return {"trained": {"episodes": episodes, "shelf": 63, "heldOut": {
            "episodes": 63, "predictedAdSeconds": 17000.0, "adSeconds": 19000.0,
            "anyAd": {"precision": precision, "recall": recall},
            "lineAnyAd": {"precision": precision, "recall": recall}}}}

    def test_the_table_shows_both_and_the_change(self):
        text = compare.report(self.model(0.90, 0.80, 700), self.model(0.93, 0.84, 760))
        self.assertIn("700", text)
        self.assertIn("760", text)
        self.assertIn("+3.0", text)
        self.assertIn("+4.0", text)

    def test_a_worse_result_is_signed_too(self):
        self.assertIn("-2.0", compare.report(self.model(0.90, 0.80, 700), self.model(0.88, 0.80, 760)))

    def test_it_says_when_a_model_has_no_held_out_numbers(self):
        text = compare.report({"trained": {"episodes": 5}}, self.model(0.9, 0.8, 7))
        self.assertIn("no held-out numbers", text)


class Run(unittest.TestCase):
    def test_trains_in_both_folders_and_prints_the_comparison(self):
        main = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, main, ignore_errors=True)
        public = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, public, ignore_errors=True)
        work = os.path.join(main, "work-out")
        item, other = entry(1), entry(101, host="sporc")
        store.save_manifest(main, [item])
        store.save_manifest(public, [other])
        write(os.path.join(main, "transcripts", item["id"] + ".txt"), "[00:00:01.0] a\n")
        write(os.path.join(main, "labels-snapped", item["id"] + ".json"), "{}")
        write(os.path.join(public, "transcripts", other["id"] + ".txt"), "[00:00:01.0] b\n")
        write(os.path.join(public, "labels", other["id"] + ".json"), "{}")
        trained = []

        def train(folder):
            trained.append(os.path.basename(folder))
            model = {"trained": {"episodes": 1 + len(store.load_manifest(folder)), "heldOut": {
                "episodes": 63, "predictedAdSeconds": 1.0, "adSeconds": 1.0,
                "anyAd": {"precision": 0.9, "recall": 0.8}, "lineAnyAd": {"precision": 0.9, "recall": 0.8}}}}
            write(os.path.join(folder, "ad-model.json"), json.dumps(model))
            return 0

        said = []
        code = compare.run(main, public, work, "labels-snapped", None, say=said.append, train=train)
        self.assertEqual(code, 0, said)
        self.assertEqual(sorted(trained), ["base", "with-public"])
        self.assertIn("with the public marks", "\n".join(said).lower())

    def test_a_trainer_that_writes_no_model_is_said(self):
        main = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, main, ignore_errors=True)
        public = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, public, ignore_errors=True)
        item = entry(101, host="sporc")
        store.save_manifest(main, [])
        store.save_manifest(public, [item])
        write(os.path.join(public, "transcripts", item["id"] + ".txt"), "[00:00:01.0] b\n")
        write(os.path.join(public, "labels", item["id"] + ".json"), "{}")
        said = []
        code = compare.run(main, public, os.path.join(main, "w"), "labels", None, say=said.append,
                           train=lambda folder: 0)
        self.assertEqual(code, 2)
        self.assertIn("wrote no model", " ".join(said))

    def test_a_trainer_that_fails_stops_the_comparison(self):
        main = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, main, ignore_errors=True)
        public = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, public, ignore_errors=True)
        item = entry(101, host="sporc")
        store.save_manifest(main, [])
        store.save_manifest(public, [item])
        write(os.path.join(public, "transcripts", item["id"] + ".txt"), "[00:00:01.0] b\n")
        write(os.path.join(public, "labels", item["id"] + ".json"), "{}")
        said = []
        code = compare.run(main, public, os.path.join(main, "w"), "labels", None, say=said.append,
                           train=lambda folder: 2)
        self.assertEqual(code, 2)


if __name__ == "__main__":
    unittest.main()
