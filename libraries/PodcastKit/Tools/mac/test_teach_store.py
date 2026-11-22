"""Tests for teach_store.py and teach_failures.py: the episode list, the atomic JSON writer, the run
lock and the memory of failures. Temporary folders only.
Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import contextlib
import io
import json
import os
import sys
import unittest
from unittest import mock

import teach_collect
import teach_failures as tfail
import teach_label
import teach_store as store
from teach_testing import Folder, entry


class ManifestTests(unittest.TestCase):
    def setUp(self):
        self.folder = Folder(self)
        self.path = self.folder.path("episodes.json")

    def write(self, text):
        with open(self.path, "w", encoding="utf-8") as handle:
            handle.write(text)

    def test_missing_file_means_no_episodes(self):
        self.assertEqual(store.load_manifest(self.folder.dir), [])

    def test_bad_files_are_refused(self):
        good = entry(0x3f2a9c1b0d4e)
        bad = ["{not json", "[]", json.dumps({"version": 2, "episodes": []}),
               json.dumps({"version": 1, "episodes": "no"}),
               json.dumps({"version": 1, "episodes": [5]}),
               json.dumps({"version": 1, "episodes": [dict(good, id="../../etc")]}),
               json.dumps({"version": 1, "episodes": [dict(good, file="../x.mp3")]}),
               json.dumps({"version": 1, "episodes": [dict(good, file="audio/ffffffffffff.mp3")]}),
               json.dumps({"version": 1, "episodes": [dict(good, bytes="many")]}),
               json.dumps({"version": 1, "episodes": [dict(good, address=7)]}),
               json.dumps({"version": 1, "episodes": [{"id": good["id"]}]}),
               json.dumps({"version": 1, "episodes": [good, good]})]
        for text in bad:
            self.write(text)
            with self.assertRaises(store.ManifestError, msg=text):
                store.load_manifest(self.folder.dir)

    def test_good_file_is_read(self):
        good = entry(0x3f2a9c1b0d4e, audio=True, bytes=5)
        self.write(json.dumps({"version": 1, "writtenAt": 1, "episodes": [good]}))
        self.assertEqual(store.load_manifest(self.folder.dir), [good])

    def test_the_names_other_tools_import_are_still_in_their_modules(self):
        self.assertIs(teach_collect.load_manifest, store.load_manifest)
        self.assertIs(teach_collect.ManifestError, store.ManifestError)
        self.assertIs(teach_collect.check_entry, store.check_entry)
        self.assertIs(teach_collect.FIELDS, store.FIELDS)
        self.assertEqual(teach_collect.FOLDER, "~/Storyteller Lofi/PodcastTeaching")
        self.assertIs(teach_label.write_json, store.write_json)
        self.assertIs(teach_label.Problem, store.Problem)

    def test_a_later_step_says_to_gather_first_when_there_is_no_file(self):
        with self.assertRaises(store.Problem) as caught:
            store.require_manifest(self.folder.dir)
        self.assertIn("Run the gather step first", str(caught.exception))

    def test_a_later_step_refuses_a_damaged_file_and_a_lenient_entry(self):
        for text in ("{nope", json.dumps({"version": 1, "episodes": [{"id": "aaaaaaaaaaaa", "feed": "f",
                                                                       "show": "s", "title": "t"}]})):
            self.write(text)
            with self.assertRaises(store.Problem, msg=text):
                store.require_manifest(self.folder.dir)

    def test_save_then_load(self):
        entries = [entry(1), entry(2, audio=True)]
        store.save_manifest(self.folder.dir, entries)
        self.assertEqual(store.load_manifest(self.folder.dir), entries)
        with open(self.path, encoding="utf-8") as handle:
            data = json.load(handle)
        self.assertEqual(data["version"], 1)
        self.assertIsInstance(data["writtenAt"], int)


class WriteJsonTests(unittest.TestCase):
    def test_writes_and_makes_the_folder(self):
        folder = Folder(self)
        path = folder.path("new", "deeper", "a.json")
        store.write_json(path, {"é": [1, 2]})
        with open(path, encoding="utf-8") as handle:
            self.assertEqual(handle.read(), json.dumps({"é": [1, 2]}, indent=1, ensure_ascii=False))
        self.assertEqual(os.listdir(os.path.dirname(path)), ["a.json"])

    def test_the_data_is_forced_to_disk_before_it_replaces_the_old_file(self):
        folder = Folder(self)
        path = folder.path("a.json")
        order = []
        real_fsync, real_replace = os.fsync, os.replace
        with mock.patch.object(store.os, "fsync", lambda fd: (order.append("fsync"), real_fsync(fd))[1]), \
                mock.patch.object(store.os, "replace", lambda a, b: (order.append("replace"), real_replace(a, b))[1]):
            store.write_json(path, {"a": 1})
        self.assertEqual(order, ["fsync", "replace"])

    def test_a_failure_keeps_the_old_file_and_leaves_no_temporary_file(self):
        folder = Folder(self)
        path = folder.path("a.json")
        store.write_json(path, {"old": True})
        with self.assertRaises(TypeError):
            store.write_json(path, {"new": object()})
        with open(path, encoding="utf-8") as handle:
            self.assertEqual(json.load(handle), {"old": True})
        self.assertEqual(os.listdir(folder.dir), ["a.json"])


class LockTests(unittest.TestCase):
    def test_a_second_run_is_refused_with_one_plain_sentence(self):
        folder = Folder(self)
        with store.run_lock(folder.dir):
            with self.assertRaises(store.Busy) as caught:
                with store.run_lock(folder.dir):
                    self.fail("the second run got the lock")
        self.assertEqual(str(caught.exception), "Another teaching run is already working in this "
                         "folder. Wait for it to finish, or close its window.")

    def test_the_lock_is_free_again_afterwards_also_after_an_error(self):
        folder = Folder(self)
        with self.assertRaises(RuntimeError):
            with store.run_lock(folder.dir):
                raise RuntimeError("boom")
        with store.run_lock(folder.dir):
            pass

    def test_the_lock_makes_the_folder(self):
        folder = Folder(self)
        with store.run_lock(folder.path("not", "yet")):
            self.assertTrue(os.path.exists(folder.path("not", "yet", ".lock")))


class BusyCheckTests(unittest.TestCase):
    """`python3 teach_store.py busy FOLDER`, which the weekly job asks before it starts."""

    def test_a_free_folder_gives_0_and_is_not_left_locked(self):
        folder = Folder(self)
        self.assertEqual(store.main(["busy", folder.dir]), 0)
        with store.run_lock(folder.dir):
            pass

    def test_a_folder_in_use_gives_3(self):
        folder = Folder(self)
        with store.run_lock(folder.dir):
            self.assertEqual(store.main(["busy", folder.dir]), 3)

    def test_bad_arguments_give_2(self):
        self.assertEqual(store.main([]), 2)
        self.assertEqual(store.main(["busy"]), 2)


class HoldTests(unittest.TestCase):
    """`python3 teach_store.py hold FOLDER COMMAND...`, which teach-finish.sh runs itself under."""

    def test_the_command_runs_with_the_lock_held_and_its_code_comes_back(self):
        folder = Folder(self)
        seen = []

        def runner(command):
            seen.append((command, store.main(["busy", folder.dir])))
            return 7

        self.assertEqual(store.hold(folder.dir, ["x", "y"], runner=runner), 7)
        self.assertEqual(seen, [(["x", "y"], 3)])
        self.assertEqual(store.main(["busy", folder.dir]), 0)  # released afterwards

    def test_a_folder_in_use_gives_3_says_so_and_runs_nothing(self):
        folder = Folder(self)
        ran = []
        said = io.StringIO()
        with store.run_lock(folder.dir), contextlib.redirect_stdout(said):
            code = store.hold(folder.dir, ["x"], runner=ran.append)
        self.assertEqual((code, ran), (3, []))
        self.assertIn("Another teaching run is already working", said.getvalue())

    def test_the_command_line_runs_a_real_command(self):
        folder = Folder(self)
        self.assertEqual(store.main(["hold", folder.dir, sys.executable, "-c", "raise SystemExit(5)"]), 5)
        self.assertEqual(store.main(["hold", folder.dir]), 2)


class FailuresTests(unittest.TestCase):
    def test_counts_are_remembered_between_runs_in_the_documented_file(self):
        folder = Folder(self)
        failures = tfail.Failures(folder.dir, "label")
        failures.failed("aaaaaaaaaaaa")
        failures.failed("aaaaaaaaaaaa")
        tfail.Failures(folder.dir, "transcribe").failed("bbbbbbbbbbbb")
        with open(folder.path("failures.json"), encoding="utf-8") as handle:
            self.assertEqual(json.load(handle), {"version": 1, "transcribe": {"bbbbbbbbbbbb": 1},
                                                 "label": {"aaaaaaaaaaaa": 2}})
        self.assertEqual(tfail.Failures(folder.dir, "label").count("aaaaaaaaaaaa"), 2)
        self.assertEqual(tfail.Failures(folder.dir, "label").count("bbbbbbbbbbbb"), 0)

    def test_success_removes_the_entry(self):
        folder = Folder(self)
        failures = tfail.Failures(folder.dir, "label")
        failures.failed("a")
        failures.succeeded("a")
        failures.succeeded("never-failed")
        with open(folder.path("failures.json"), encoding="utf-8") as handle:
            self.assertEqual(json.load(handle)["label"], {})

    def test_a_damaged_or_odd_file_starts_a_fresh_memory(self):
        folder = Folder(self)
        for text in ("{nope", "[]", json.dumps({"version": 9, "label": {"a": 5}})):
            with open(folder.path("failures.json"), "w") as handle:
                handle.write(text)
            self.assertEqual(tfail.Failures(folder.dir, "label").count("a"), 0, text)
        with open(folder.path("failures.json"), "w") as handle:
            json.dump({"version": 1, "label": {"a": 2, "b": "x", "c": -1, "d": True}}, handle)
        failures = tfail.Failures(folder.dir, "label")
        self.assertEqual([failures.count(name) for name in "abcd"], [2, 0, 0, 0])

    def test_order_never_failed_first_then_fewer_failures(self):
        folder = Folder(self)
        with open(folder.path("failures.json"), "w") as handle:
            json.dump({"version": 1, "label": {"b": 2, "d": 1, "e": 1}}, handle)
        failures = tfail.Failures(folder.dir, "label")
        ready, given_up = failures.split(list("abcde"), False, lambda item: item)
        self.assertEqual((ready, given_up), (["a", "c", "d", "e", "b"], []))

    def test_three_failures_give_up_unless_retry_failed(self):
        folder = Folder(self)
        with open(folder.path("failures.json"), "w") as handle:
            json.dump({"version": 1, "label": {"b": 3, "c": 5, "a": 2}}, handle)
        failures = tfail.Failures(folder.dir, "label")
        self.assertEqual(failures.split(list("abcd"), False, lambda item: item),
                         (["d", "a"], ["b", "c"]))
        self.assertEqual(failures.split(list("abcd"), True, lambda item: item),
                         (["d", "a", "b", "c"], []))

    def test_the_closing_line_names_the_count_and_the_option(self):
        self.assertIn("1 episode was given up on", tfail.given_up_line(1))
        self.assertIn("3 episodes were given up on", tfail.given_up_line(3))
        self.assertIn("--retry-failed", tfail.given_up_line(3))


if __name__ == "__main__":
    unittest.main()
