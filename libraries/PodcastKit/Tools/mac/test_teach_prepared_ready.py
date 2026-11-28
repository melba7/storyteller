"""Tests for teach_prepared.py ready, the check the hourly job makes before it picks or marks
anything: the iCloud copy is there, a small file can really be written into its prepared folder and is
removed again, the cleaning has run, the Mac's disk has room, and iCloud has room. Each reason is one
plain line and exit 3. Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import os
import shutil
import tempfile
from unittest import mock

import teach_store as store
from test_teach_prepared import GB, QUOTA
from test_teach_prepared_clean import CleanBase


class ReadyTests(CleanBase):
    def test_everything_in_order_is_exit_0_with_nothing_said_and_nothing_copied(self):
        self.assertEqual(self.go("ready"), 0, self.said)
        self.assertEqual(self.said, [])
        self.assertEqual(self.cps(), [])

    def test_no_icloud_copy_of_the_phones_folder_is_one_line_and_exit_3(self):
        shutil.rmtree(self.dest)
        self.assertEqual(self.go("ready"), 3)
        self.assertEqual(len(self.said), 1)
        self.assertIn("no iCloud copy", self.said[0])

    def test_a_refused_write_is_one_line_naming_full_disk_access_and_exit_3(self):
        with mock.patch("tempfile.mkstemp", side_effect=PermissionError("Operation not permitted")):
            self.assertEqual(self.go("ready"), 3)
        self.assertEqual(len(self.said), 1)
        for words in ("cannot write", "Operation not permitted", "Full Disk Access", "/bin/bash"):
            self.assertIn(words, self.said[0])

    def test_a_prepared_folder_that_cannot_be_made_is_the_same_reason(self):
        os.makedirs(os.path.join(self.dest, "Podcasts"))
        with open(os.path.join(self.dest, "Podcasts", "prepared"), "w") as f:
            f.write("in the way")
        self.assertEqual(self.go("ready"), 3)
        self.assertIn("Full Disk Access", self.said[0])

    def test_the_write_test_is_a_real_dot_file_in_the_prepared_folder_and_leaves_nothing(self):
        seen = []
        real = tempfile.mkstemp

        def spy(*args, **more):
            handle, path = real(*args, **more)
            seen.append(path)
            return handle, path
        with mock.patch("tempfile.mkstemp", side_effect=spy):
            self.assertEqual(self.go("ready"), 0)
        self.assertEqual(len(seen), 1)
        self.assertEqual(os.path.dirname(seen[0]), self.prepared_folder())
        self.assertTrue(os.path.basename(seen[0]).startswith("."))
        self.assertFalse(os.path.exists(seen[0]))
        self.assertEqual(os.listdir(self.prepared_folder()), [])

    def test_a_failure_in_the_middle_of_the_write_test_leaves_nothing_behind_either(self):
        real = os.write

        def broken(handle, data):
            raise OSError(28, "No space left on device")
        with mock.patch("os.write", side_effect=broken):
            self.assertEqual(self.go("ready"), 3)
        self.assertEqual(os.listdir(self.prepared_folder()), [])
        self.assertTrue(real)

    def test_the_cleaning_runs_so_old_copies_go_and_room_comes_back(self):
        old, young = self.publish_old(1, 8), self.publish_old(2, 1)
        self.assertEqual(self.go("ready"), 0)
        self.assertFalse(self.exists(old))
        self.assertTrue(self.exists(young))
        self.assertFalse(self.mac_audio(old))

    def test_the_cleaning_has_run_even_when_the_disk_is_then_found_low(self):
        old = self.publish_old(1, 8)
        self.free = 1 * GB
        self.assertEqual(self.go("ready"), 3)
        self.assertFalse(self.exists(old))

    def test_under_15_gb_free_on_the_mac_is_one_line_and_exit_3_and_the_limit_can_change(self):
        self.free = 15 * GB - 1
        self.assertEqual(self.go("ready"), 3)
        self.assertEqual(len(self.said), 1)
        self.assertIn("15 GB", self.said[0])
        self.assertEqual(self.go("ready", "--keep-free-gb", "10"), 0)

    def test_under_2_gb_left_in_icloud_is_one_line_and_exit_3(self):
        self.quota = QUOTA % (2 * GB - 1)
        self.assertEqual(self.go("ready"), 3)
        self.assertEqual(len(self.said), 1)
        self.assertIn("2 GB", self.said[0])
        self.quota = QUOTA % (2 * GB)
        self.assertEqual(self.go("ready"), 0)

    def test_a_missing_brctl_or_words_it_does_not_understand_do_not_stop_it(self):
        for answer in (FileNotFoundError("brctl"), "nothing useful", ""):
            self.quota = answer
            self.assertEqual(self.go("ready"), 0, answer)

    def test_it_is_refused_while_another_run_holds_the_folder(self):
        with store.run_lock(self.folder.dir):
            self.assertEqual(self.go("ready"), 3)
        self.assertIn("Another teaching run", self.said[-1])
