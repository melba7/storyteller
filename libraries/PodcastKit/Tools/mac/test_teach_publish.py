"""Tests for teach_publish.py: checking a source, writing into several folders, leaving unchanged
files alone, damaged or missing sources and folders, and the exit codes. No network.
Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import json
import os
import shutil
import tempfile
import unittest

import teach_publish as publish

NAMES = (("ad-model.json", "ad-model.json"), ("ad-library.json", "ad-library.json"),
         ("habits.json", "show-habits.json"), ("ad-sounds.json", "ad-sounds.json"))
GOOD = {"version": 1, "trained": {"heldOut": {"anyAd": {"precision": 0.9, "recall": 0.5}}}}


def model(precision):
    return {"version": 1, "trained": {"heldOut": {"anyAd": {"precision": precision}}}}


def read(path):
    with open(path, "rb") as f:
        return f.read()


class Setup(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.root, ignore_errors=True)
        self.teaching = os.path.join(self.root, "teaching")
        os.makedirs(self.teaching)
        self.one = self.destination("one")
        self.two = self.destination("two")
        self.messages = []

    def destination(self, name):
        path = os.path.join(self.root, name)
        os.makedirs(path)
        return path

    def say(self, text):
        self.messages.append(text)

    def source(self, name, value=None, raw=None):
        path = os.path.join(self.teaching, name)
        with open(path, "wb") as f:
            if value is None and name == "ad-model.json":
                value = GOOD
            f.write(raw if raw is not None else json.dumps(value or {"version": 1, "n": name})
                    .encode("utf-8"))
        return path

    def all_sources(self):
        for name, _ in NAMES:
            self.source(name)

    def main(self, *folders, extra=(), **kw):
        arguments = ["--folder", self.teaching] + list(extra)
        for folder in folders:
            arguments += ["--to", folder]
        return publish.main(arguments, say=self.say, **kw)

    def published(self, folder, name):
        return os.path.join(folder, "Podcasts", name)


class CheckTests(Setup):
    def test_a_valid_source_is_returned_as_its_bytes(self):
        path = self.source("ad-model.json", {"version": 1, "x": [1]})
        self.assertEqual(publish.checked(path), read(path))

    def test_it_must_be_json(self):
        path = self.source("ad-model.json", raw=b"{nope")
        with self.assertRaises(ValueError):
            publish.checked(path)
        path = self.source("ad-model.json", raw=b"\xff\xfe")
        with self.assertRaises(ValueError):
            publish.checked(path)

    def test_it_must_be_an_object_with_version_1(self):
        for value in ([1], {"version": 2}, {"x": 1}, {"version": "1"}, {"version": True},
                      {"version": 1.5}):
            path = self.source("ad-model.json", value)
            with self.assertRaises(ValueError, msg=repr(value)):
                publish.checked(path)

    def test_it_may_be_at_most_the_size_limit(self):
        path = self.source("ad-model.json", {"version": 1})
        size = os.path.getsize(path)
        self.assertEqual(publish.checked(path, limit=size), read(path))
        with self.assertRaises(ValueError):
            publish.checked(path, limit=size - 1)

    def test_the_limit_is_4_5_megabytes(self):
        self.assertEqual(publish.LIMIT, 4500000)


class PublishTests(Setup):
    def test_every_source_goes_to_every_folder(self):
        self.all_sources()
        self.assertEqual(self.main(self.one, self.two), 0, self.messages)
        for folder in (self.one, self.two):
            for source, target in NAMES:
                self.assertEqual(read(self.published(folder, target)),
                                 read(os.path.join(self.teaching, source)))
        self.assertEqual(len([m for m in self.messages if "written" in m]), 10)

    def test_unchanged_content_is_not_written_again(self):
        self.all_sources()
        self.main(self.one)
        path = self.published(self.one, "ad-model.json")
        os.utime(path, (1000, 1000))
        self.messages.clear()
        self.assertEqual(self.main(self.one), 0)
        self.assertEqual(os.stat(path).st_mtime, 1000)
        self.assertEqual(len([m for m in self.messages if "unchanged" in m]), 5)

    def test_the_writer_is_not_called_for_unchanged_content(self):
        self.all_sources()
        calls = []

        def counting(path, data):
            calls.append(path)
            publish.write_atomically(path, data)

        self.main(self.one, writer=counting)
        self.assertEqual(len(calls), 5)
        self.main(self.one, writer=counting)
        self.assertEqual(len(calls), 5)
        self.source("ad-library.json", {"version": 1, "n": "changed"})
        self.main(self.one, writer=counting)
        self.assertEqual(len(calls), 7)
        self.assertTrue(calls[-2].endswith("ad-library.json"))
        self.assertTrue(calls[-1].endswith("teaching.json"))
        self.assertIn(b"changed", read(self.published(self.one, "ad-library.json")))

    def test_a_missing_source_is_skipped_with_one_line(self):
        self.source("habits.json")
        self.assertEqual(self.main(self.one, self.two), 0)
        self.assertTrue(os.path.exists(self.published(self.one, "show-habits.json")))
        self.assertFalse(os.path.exists(self.published(self.one, "ad-model.json")))
        skipped = [m for m in self.messages if "ad-model.json" in m]
        self.assertEqual(len(skipped), 1)
        self.assertIn("skipped", skipped[0])

    def test_nothing_to_publish_exits_0(self):
        self.assertEqual(self.main(self.one), 0)
        self.assertEqual(len(self.messages), 4)
        self.assertEqual(os.listdir(self.one), [])

    def test_an_invalid_source_is_refused_and_says_why(self):
        self.all_sources()
        self.source("ad-model.json", raw=b"{nope")
        self.assertEqual(self.main(self.one, self.two), 2)
        self.assertFalse(os.path.exists(self.published(self.one, "ad-model.json")))
        self.assertTrue(os.path.exists(self.published(self.one, "ad-library.json")))
        self.assertTrue(any("ad-model.json" in m and "not JSON" in m for m in self.messages))

    def test_a_too_large_source_is_refused(self):
        self.source("ad-model.json", {"version": 1, "pad": "x" * 100})
        self.assertEqual(self.main(self.one, limit=50), 2)
        self.assertFalse(os.path.exists(self.published(self.one, "ad-model.json")))
        self.assertTrue(any("too large" in m for m in self.messages))

    def test_a_refused_source_does_not_remove_the_old_published_file(self):
        self.source("ad-model.json")
        self.main(self.one)
        before = read(self.published(self.one, "ad-model.json"))
        self.source("ad-model.json", raw=b"[]")
        self.assertEqual(self.main(self.one), 2)
        self.assertEqual(read(self.published(self.one, "ad-model.json")), before)

    def test_a_missing_destination_is_reported_and_the_other_gets_its_files(self):
        self.all_sources()
        missing = os.path.join(self.root, "not there")
        self.assertEqual(self.main(self.one, missing), 0)
        self.assertEqual(len(os.listdir(os.path.join(self.one, "Podcasts"))), 5)
        self.assertFalse(os.path.exists(missing))
        self.assertTrue(any("not there" in m and "does not exist" in m for m in self.messages))

    def test_a_missing_first_destination_is_exit_2_though_the_second_got_the_files(self):
        self.all_sources()
        missing = os.path.join(self.root, "not there")
        self.assertEqual(self.main(missing, self.one), 2)
        self.assertEqual(len(os.listdir(os.path.join(self.one, "Podcasts"))), 5)

    def test_nowhere_to_write_is_exit_2(self):
        self.all_sources()
        self.assertEqual(self.main(os.path.join(self.root, "nope")), 2)

    def test_a_folder_that_cannot_be_written_is_reported_and_the_others_still_tried(self):
        self.all_sources()

        def failing(path, data):
            if path.startswith(self.one):
                raise PermissionError("Operation not permitted")
            publish.write_atomically(path, data)

        self.assertEqual(self.main(self.one, self.two, writer=failing), 2)
        self.assertEqual(len(os.listdir(os.path.join(self.two, "Podcasts"))), 5)
        self.assertEqual(len([m for m in self.messages if "failed" in m]), 5)
        self.assertTrue(any("Operation not permitted" in m for m in self.messages))

    def test_a_failing_second_folder_does_not_change_exit_0(self):
        self.all_sources()

        def failing(path, data):
            if path.startswith(self.two):
                raise OSError("no iCloud")
            publish.write_atomically(path, data)

        self.assertEqual(self.main(self.one, self.two, writer=failing), 0)

    def test_no_temporary_file_is_left_behind(self):
        self.all_sources()
        self.main(self.one, self.two)
        self.main(self.one, self.two)
        for folder in (self.one, self.two):
            self.assertEqual(sorted(os.listdir(os.path.join(folder, "Podcasts"))),
                             ["ad-library.json", "ad-model.json", "ad-sounds.json", "show-habits.json",
                              "teaching.json"])

    def test_a_failed_replace_leaves_no_temporary_file(self):
        folder = os.path.join(self.root, "Podcasts")
        os.makedirs(folder)
        target = os.path.join(folder, "x.json")
        os.makedirs(target)  # a folder where the file should go, so the replace fails
        with self.assertRaises(OSError):
            publish.write_atomically(target, b"{}")
        self.assertEqual(os.listdir(folder), ["x.json"])

    def test_the_default_destinations_are_the_podcast_export_folders(self):
        seen = []

        def defaults():
            seen.append(True)
            return [self.one]

        self.all_sources()
        self.assertEqual(publish.main(["--folder", self.teaching], say=self.say,
                                      defaults=defaults), 0)
        self.assertEqual(seen, [True])
        self.assertTrue(os.path.exists(self.published(self.one, "ad-model.json")))

    def test_the_real_default_folders_come_from_the_export_tool(self):
        import apple_podcasts_export
        self.assertEqual(publish.default_folders(), apple_podcasts_export.default_folders())

    def test_bad_arguments_exit_2(self):
        self.assertEqual(publish.main(["--nonsense"], say=self.say), 2)


class WeakModelTests(Setup):
    def test_a_model_below_the_bar_is_not_copied_but_the_others_are(self):
        self.all_sources()
        self.source("ad-model.json", model(0.62))
        self.assertEqual(self.main(self.one), 0, self.messages)
        self.assertFalse(os.path.exists(self.published(self.one, "ad-model.json")))
        self.assertTrue(os.path.exists(self.published(self.one, "ad-library.json")))
        said = [m for m in self.messages if "ad-model.json" in m]
        self.assertEqual(len(said), 1)
        self.assertIn("62%", said[0])
        self.assertIn("85%", said[0])
        self.assertNotIn("ad-model.json", json.loads(
            read(self.published(self.one, "teaching.json")))["files"])

    def test_exactly_the_bar_is_good_enough(self):
        self.source("ad-model.json", model(0.85))
        self.assertEqual(self.main(self.one), 0)
        self.assertTrue(os.path.exists(self.published(self.one, "ad-model.json")))

    def test_a_missing_or_null_check_is_weak(self):
        for value in ({"version": 1}, model(None), {"version": 1, "trained": {"heldOut": []}},
                      model("high"), model(True)):
            self.messages.clear()
            self.source("ad-model.json", value)
            self.assertEqual(self.main(self.one), 0, value)
            self.assertFalse(os.path.exists(self.published(self.one, "ad-model.json")), value)
            self.assertEqual(len(self.messages), 4, value)
            self.assertIn("no precision", [m for m in self.messages if "ad-model" in m][0])

    def test_a_model_already_there_is_left_alone(self):
        self.source("ad-model.json", model(0.9))
        self.main(self.one)
        before = read(self.published(self.one, "ad-model.json"))
        self.source("ad-model.json", model(0.4))
        self.assertEqual(self.main(self.one), 0)
        self.assertEqual(read(self.published(self.one, "ad-model.json")), before)
        self.assertIn("ad-model.json", json.loads(
            read(self.published(self.one, "teaching.json")))["files"])

    def test_the_bar_can_be_changed(self):
        self.source("ad-model.json", model(0.62))
        self.assertEqual(self.main(self.one, extra=("--min-precision", "0.6")), 0)
        self.assertTrue(os.path.exists(self.published(self.one, "ad-model.json")))

    def test_a_bad_bar_exits_2(self):
        for text in ("2", "-0.1", "lots"):
            self.assertEqual(self.main(self.one, extra=("--min-precision", text)), 2, text)


class TeachingListTests(Setup):
    def list_of(self, folder):
        return json.loads(read(self.published(folder, "teaching.json")))

    def test_it_lists_the_files_with_hash_and_size(self):
        import hashlib
        self.all_sources()
        self.assertEqual(self.main(self.one, self.two), 0)
        for folder in (self.one, self.two):
            listing = self.list_of(folder)
            self.assertEqual(listing["version"], 1)
            self.assertIsInstance(listing["writtenAt"], int)
            self.assertEqual(sorted(listing["files"]), ["ad-library.json", "ad-model.json",
                                                         "ad-sounds.json", "show-habits.json"])
            data = read(self.published(folder, "ad-model.json"))
            self.assertEqual(listing["files"]["ad-model.json"],
                             {"sha256": hashlib.sha256(data).hexdigest(), "bytes": len(data)})

    def test_it_lists_what_is_there_now_not_what_was_copied(self):
        os.makedirs(os.path.join(self.one, "Podcasts"))
        with open(self.published(self.one, "ad-library.json"), "wb") as f:
            f.write(b"older")
        self.source("habits.json")
        self.assertEqual(self.main(self.one), 0)
        self.assertEqual(sorted(self.list_of(self.one)["files"]),
                         ["ad-library.json", "show-habits.json"])

    def test_it_is_not_written_again_when_the_files_part_is_the_same(self):
        self.all_sources()
        times = iter([1000, 2000, 3000])
        self.main(self.one, now=lambda: next(times))
        path = self.published(self.one, "teaching.json")
        first = read(path)
        self.main(self.one, now=lambda: next(times))
        self.assertEqual(read(path), first)
        self.source("habits.json", {"version": 1, "n": "new"})
        self.main(self.one, now=lambda: next(times))
        self.assertEqual(self.list_of(self.one)["writtenAt"], 2000)

    def test_nothing_published_and_no_podcasts_folder_writes_no_list(self):
        self.assertEqual(self.main(self.one), 0)
        self.assertFalse(os.path.exists(os.path.join(self.one, "Podcasts")))

    def test_a_list_that_cannot_be_written_is_reported(self):
        self.all_sources()

        def failing(path, data):
            if path.endswith("teaching.json"):
                raise OSError("disk full")
            publish.write_atomically(path, data)

        self.assertEqual(self.main(self.one, self.two, writer=failing), 2)
        self.assertTrue(any("teaching.json" in m and "disk full" in m for m in self.messages))
        self.assertTrue(os.path.exists(self.published(self.two, "ad-model.json")))


if __name__ == "__main__":
    unittest.main()
