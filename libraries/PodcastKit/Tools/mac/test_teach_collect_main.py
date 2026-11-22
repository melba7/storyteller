"""Tests for the command line of teach_collect.py: exit codes, --list, the lock and the closing
lines. No network and no real sleeping.
Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import json
import os
import tempfile
import unittest

import teach_collect as tc
import teach_fetch
import teach_store as store
import teach_testing
from test_teach_collect import SHOWS, feeds_for, fetcher


class MainTests(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.dir.cleanup)
        self.folder = os.path.join(self.dir.name, "teach")
        self.shows = os.path.join(self.dir.name, "shows.json")
        with open(self.shows, "w", encoding="utf-8") as handle:
            json.dump({"shows": SHOWS[:1]}, handle)

    def run_main(self, *extra, **more):
        more.setdefault("say", lambda line: None)
        return tc.main(["--folder", self.folder, "--shows", self.shows] + list(extra),
                       fetch=fetcher(feeds_for()), sleep=lambda s: None, **more)

    def test_damaged_manifest_is_left_alone_and_gives_2(self):
        os.makedirs(self.folder)
        path = os.path.join(self.folder, "episodes.json")
        with open(path, "w", encoding="utf-8") as handle:
            handle.write("{broken")
        self.assertEqual(self.run_main(), 2)
        with open(path, encoding="utf-8") as handle:
            self.assertEqual(handle.read(), "{broken")

    def test_unreadable_shows_file_gives_2(self):
        os.remove(self.shows)
        self.assertEqual(self.run_main(), 2)

    def test_folder_that_cannot_be_written_gives_2(self):
        blocker = os.path.join(self.dir.name, "file")
        with open(blocker, "w") as handle:
            handle.write("x")
        self.folder = os.path.join(blocker, "inside")
        self.assertEqual(self.run_main(), 2)

    def test_list_writes_nothing(self):
        self.assertEqual(self.run_main("--list"), 0)
        self.assertFalse(os.path.exists(self.folder))

    def test_list_counts(self):
        lines = []
        self.assertEqual(self.run_main("--list", say=lines.append), 0)
        text = "\n".join(lines)
        self.assertIn("1 show", text)
        self.assertIn("3 episodes", text)  # the fake feed has 3, fewer than --per-show's 4
        self.assertIn("0.0 GB", text)

    def test_run_with_failures_still_exits_0(self):
        def failing(address, path, **more):
            raise OSError("nope")
        self.assertEqual(self.run_main(download=failing), 0)

    def test_a_second_run_in_the_same_folder_is_refused_with_exit_2(self):
        lines = []
        with store.run_lock(self.folder):
            self.assertEqual(self.run_main(say=lines.append), 2)
        self.assertEqual(lines, ["Another teaching run is already working in this folder. Wait for it "
                                 "to finish, or close its window."])
        self.assertFalse(os.path.exists(os.path.join(self.folder, "episodes.json")))

    def test_the_size_limit_on_kept_audio_gives_its_own_exit_code(self):
        # 60 MB of audio is kept already and the limit is 0.05 GB, so the new episodes wait.
        os.makedirs(self.folder)
        store.save_manifest(self.folder, [teach_testing.entry(1, audio=True, bytes=60_000_000)])
        lines = []
        code = self.run_main("--max-gb", "0.05", download=lambda a, p, **m: self.fail("no download"),
                             say=lines.append)
        self.assertEqual(code, tc.SIZE_LIMIT)
        self.assertTrue(any("size limit on all kept audio" in line for line in lines), lines)

    def test_free_disk_space_is_not_the_size_limit(self):
        self.assertEqual(self.run_main("--keep-free-gb", "100000000",
                                       download=lambda a, p, **m: self.fail("no download")), 0)

    def test_the_lock_is_free_after_a_run(self):
        self.assertEqual(self.run_main(download=lambda a, p, **m: self.fail("no download wanted")), 0)
        with store.run_lock(self.folder):
            pass

    def test_the_closing_lines_count_files_that_are_too_big(self):
        def too_big(address, path, **more):
            raise teach_fetch.TooLarge("big")
        lines = []
        self.assertEqual(self.run_main(download=too_big, say=lines.append), 0)
        self.assertTrue(any("3 were left out for good" in line for line in lines), lines)


if __name__ == "__main__":
    unittest.main()
