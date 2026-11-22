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
         ("habits.json", "show-habits.json"))


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
            f.write(raw if raw is not None else json.dumps(value or {"version": 1, "n": name})
                    .encode("utf-8"))
        return path

    def all_sources(self):
        for name, _ in NAMES:
            self.source(name)

    def main(self, *folders, **kw):
        arguments = ["--folder", self.teaching]
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
        self.assertEqual(len([m for m in self.messages if "written" in m]), 6)

    def test_unchanged_content_is_not_written_again(self):
        self.all_sources()
        self.main(self.one)
        path = self.published(self.one, "ad-model.json")
        os.utime(path, (1000, 1000))
        self.messages.clear()
        self.assertEqual(self.main(self.one), 0)
        self.assertEqual(os.stat(path).st_mtime, 1000)
        self.assertEqual(len([m for m in self.messages if "unchanged" in m]), 3)

    def test_the_writer_is_not_called_for_unchanged_content(self):
        self.all_sources()
        calls = []

        def counting(path, data):
            calls.append(path)
            publish.write_atomically(path, data)

        self.main(self.one, writer=counting)
        self.assertEqual(len(calls), 3)
        self.main(self.one, writer=counting)
        self.assertEqual(len(calls), 3)
        self.source("ad-library.json", {"version": 1, "n": "changed"})
        self.main(self.one, writer=counting)
        self.assertEqual(len(calls), 4)
        self.assertTrue(calls[-1].endswith("ad-library.json"))
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
        self.assertEqual(len(self.messages), 3)
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
        self.assertEqual(len(os.listdir(os.path.join(self.one, "Podcasts"))), 3)
        self.assertFalse(os.path.exists(missing))
        self.assertTrue(any("not there" in m and "does not exist" in m for m in self.messages))

    def test_a_missing_first_destination_is_exit_2_though_the_second_got_the_files(self):
        self.all_sources()
        missing = os.path.join(self.root, "not there")
        self.assertEqual(self.main(missing, self.one), 2)
        self.assertEqual(len(os.listdir(os.path.join(self.one, "Podcasts"))), 3)

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
        self.assertEqual(len(os.listdir(os.path.join(self.two, "Podcasts"))), 3)
        self.assertEqual(len([m for m in self.messages if "failed" in m]), 3)
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
                             ["ad-library.json", "ad-model.json", "show-habits.json"])

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


if __name__ == "__main__":
    unittest.main()
