"""Tests for what the nightly read-ahead added to the other teaching tools: the --only-ahead limit of
the gathering, the writing down and the marking, the marking's --reserve (it stops before a call
that would pass the cap), and the shelf that never takes an episode of ahead.json. Fakes only, no
network, no Claude. Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import json
import os
import shutil
import tempfile
import unittest

import teach_ahead_set as ahead
import teach_collect as collect
import teach_label as label
import teach_store as store
import teach_train as train
import teach_transcribe as transcribe
from teach_testing import FakeRunner, Teaching, answer, entry, printed
from test_teach_train import Folder as TrainFolder, run as run_train


def picked(item):
    return {"id": item["id"], "feed": item["feed"], "guid": item["guid"], "title": item["title"],
            "picked": 100}


class AheadSetTests(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.dir, True)

    def test_no_file_is_an_empty_list(self):
        self.assertEqual((ahead.read_ahead(self.dir), ahead.ahead_ids(self.dir)), ([], set()))

    def test_added_episodes_are_kept_in_order_and_never_twice(self):
        first, second = picked(entry(1)), picked(entry(2))
        ahead.add_ahead(self.dir, [first, second])
        joined = ahead.add_ahead(self.dir, [second, picked(entry(3))])
        self.assertEqual([e["id"] for e in joined], [first["id"], second["id"], picked(entry(3))["id"]])
        self.assertEqual(ahead.read_ahead(self.dir), joined)
        with open(os.path.join(self.dir, "ahead.json")) as f:
            self.assertEqual(json.load(f)["version"], 1)

    def test_a_damaged_file_is_a_problem_and_is_never_replaced(self):
        path = os.path.join(self.dir, "ahead.json")
        for text in ("nope", "[]", '{"version": 2, "episodes": []}',
                     '{"version": 1, "episodes": [{"id": "x"}]}'):
            with open(path, "w") as f:
                f.write(text)
            with self.assertRaises(store.Problem):
                ahead.read_ahead(self.dir)
            with self.assertRaises(store.Problem):
                ahead.add_ahead(self.dir, [picked(entry(1))])
            with open(path) as f:
                self.assertEqual(f.read(), text)


class CollectOnlyTests(unittest.TestCase):
    def test_only_the_named_episodes_are_downloaded_and_no_feed_is_read(self):
        folder = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, folder, True)
        entries = [entry(n) for n in (1, 2, 3)]
        store.save_manifest(folder, entries)
        asked, said = [], []

        def download(address, path, **more):
            asked.append(address)
            with open(path, "wb") as f:
                f.write(b"x" * 10)
            return {"bytes": 10, "sha256": "ab" * 32, "host": "cdn"}

        def no_feed(address):
            raise AssertionError("a feed was read: " + address)

        result = collect.collect(folder, [], 1, 10**9, 0, fetch=no_feed, download=download,
                                 free_space=lambda path: 10**12, sleep=lambda s: None,
                                 say=said.append, only={entries[0]["id"], entries[2]["id"]})
        self.assertEqual(asked, [entries[0]["address"], entries[2]["address"]])
        self.assertEqual((result["downloaded"], result["waiting"]), (2, 0))
        saved = {e["id"]: e for e in store.load_manifest(folder)}
        self.assertIsNone(saved[entries[1]["id"]]["file"])

    def test_the_size_limit_still_applies_to_them(self):
        folder = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, folder, True)
        entries = [entry(n, size=100) for n in (1, 2, 3)]
        store.save_manifest(folder, entries)

        def download(address, path, **more):
            with open(path, "wb") as f:
                f.write(b"x" * 100)
            return {"bytes": 100, "sha256": "ab" * 32, "host": "cdn"}

        result = collect.collect(folder, [], 1, 250, 0, download=download,
                                 free_space=lambda path: 10**12, sleep=lambda s: None,
                                 say=lambda line: None, only={e["id"] for e in entries})
        self.assertEqual((result["downloaded"], result["waiting"], result["why"]), (2, 1, "size"))


class TranscribeOnlyTests(unittest.TestCase):
    def test_only_the_named_episodes_are_written_down(self):
        folder = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, folder, True)
        entries = [entry(n, audio=True) for n in (1, 2, 3)]
        os.makedirs(os.path.join(folder, "audio"))
        for item in entries:
            with open(os.path.join(folder, item["file"]), "wb") as f:
                f.write(b"x")
        store.save_manifest(folder, entries)
        seen = []

        def runner(command, **options):
            seen.append(os.path.basename(command[-1]))
            options["stdout"].write("[00:00:01.0] hello\n")
            return type("Done", (), {"returncode": 0, "stderr": ""})()

        result = transcribe.run(folder, "tool", "en-US", None, runner=runner, say=lambda line: None,
                                only={entries[1]["id"]})
        self.assertEqual(seen, [os.path.basename(entries[1]["file"])])
        self.assertEqual((result["done"], result["left"]), (1, 0))


class LabelBase(unittest.TestCase):
    def setUp(self):
        self.said = []
        self.home = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.home, True)
        bin_folder = os.path.join(self.home, "bin")
        os.makedirs(bin_folder)
        with open(os.path.join(bin_folder, "claude"), "w") as f:
            f.write("#!/bin/sh\n")
        os.chmod(os.path.join(bin_folder, "claude"), 0o755)
        self.environment = {"HOME": self.home, "PATH": bin_folder}

    def main(self, teaching, *options, runner=None):
        runner = runner or FakeRunner(stdout=printed(answer((1, 2))))
        code = label.main(["--folder", teaching.dir, "--yes"] + list(options), runner=runner,
                          environment=self.environment, say=self.said.append, extra_folders=())
        return code, runner


class LabelOnlyTests(LabelBase):
    def test_only_ahead_marks_only_the_episodes_of_ahead_json(self):
        teaching = Teaching(self, 4)
        ahead.add_ahead(teaching.dir, [picked(teaching.entries[1]), picked(teaching.entries[3])])
        code, runner = self.main(teaching, "--only-ahead")
        self.assertEqual((code, len(runner.calls)), (0, 2))
        self.assertEqual(teaching.labels(), sorted(teaching.entries[n]["id"] + ".json" for n in (1, 3)))

    def test_without_the_flag_every_episode_is_marked_as_before(self):
        teaching = Teaching(self, 3)
        ahead.add_ahead(teaching.dir, [picked(teaching.entries[0])])
        self.assertEqual(len(self.main(teaching)[1].calls), 3)

    def test_an_episode_that_already_has_a_label_is_not_marked_twice(self):
        teaching = Teaching(self, 2)
        ahead.add_ahead(teaching.dir, [picked(e) for e in teaching.entries])
        self.main(teaching, "--only-ahead")
        again_code, again = self.main(teaching, "--only-ahead")
        self.assertEqual((again_code, len(again.calls)), (0, 0))
        self.assertIn("Nothing to do", self.said[-1])

    def test_a_damaged_ahead_file_is_a_set_up_problem(self):
        teaching = Teaching(self, 1)
        with open(os.path.join(teaching.dir, "ahead.json"), "w") as f:
            f.write("nope")
        code, runner = self.main(teaching, "--only-ahead")
        self.assertEqual((code, len(runner.calls)), (2, 0))
        self.assertIn("ahead.json", self.said[-1])


class ReserveTests(LabelBase):
    """Every call costs 0.25 here."""

    def spend(self, teaching, cap, *more):
        return self.main(teaching, "--budget", "week", "--cap", cap, *more)

    def test_without_a_reserve_the_last_call_may_pass_the_cap(self):
        teaching = Teaching(self, 6)
        code, runner = self.spend(teaching, "0.9", "--reserve", "0")
        self.assertEqual((code, len(runner.calls)), (5, 4))  # 1.00 spent against 0.90

    def test_a_reserve_stops_before_the_call_that_would_pass_the_cap(self):
        teaching = Teaching(self, 6)
        code, runner = self.spend(teaching, "0.9", "--reserve", "0.25")
        self.assertEqual((code, len(runner.calls)), (5, 3))  # 0.75 spent, the next would make 1.00
        text = "\n".join(self.said)
        self.assertIn("would pass the cap", text)
        self.assertIn("$0.25", text)
        self.assertEqual(len(teaching.labels()), 3)

    def test_the_spending_of_earlier_nights_counts(self):
        teaching = Teaching(self, 6)
        self.spend(teaching, "0.9", "--reserve", "0.25")
        code, runner = self.spend(teaching, "0.9", "--reserve", "0.25")
        self.assertEqual((code, len(runner.calls)), (5, 0))
        self.assertIn("budget is spent", "\n".join(self.said))

    def test_a_budget_with_less_left_than_the_reserve_is_spent(self):
        teaching = Teaching(self, 2)
        code, runner = self.spend(teaching, "0.2", "--reserve", "0.25")
        self.assertEqual((code, len(runner.calls)), (5, 0))

    def test_a_reserve_that_is_not_a_number_is_a_set_up_problem(self):
        teaching = Teaching(self, 1)
        for bad in ("abc", "-1", "nan"):
            self.assertEqual(self.spend(teaching, "5", "--reserve", bad)[0], 2, bad)


class ShelfTests(unittest.TestCase):
    def test_an_episode_of_ahead_is_trained_on_but_never_put_on_the_shelf(self):
        folder = TrainFolder(self)
        for n in range(3):
            folder.add("a", n)
        newest = folder.add("a", 99)
        ahead.add_ahead(folder.path, [picked(e) for e in folder.entries if e["id"] == newest])
        code, said = run_train(folder, "--min-episodes", "2")
        self.assertEqual(code, 0, said)
        self.assertEqual(folder.read("shelf.json")["episodes"], [folder.entries[2]["id"]])
        self.assertEqual(folder.read("ad-model.json")["trained"]["episodes"], 3)

    def test_without_ahead_json_the_newest_is_shelved_as_before(self):
        folder = TrainFolder(self)
        for n in range(3):
            folder.add("a", n)
        newest = folder.add("a", 99)
        run_train(folder, "--min-episodes", "2")
        self.assertEqual(folder.read("shelf.json")["episodes"], [newest])


if __name__ == "__main__":
    unittest.main()
