"""Tests for teach_backup.py: the backup of what the teaching runs have paid for (labels, snapped
labels, transcripts, second-download copies and the small JSON files of the folder), the check that
a backup can be read, and the restore into an empty folder. Temporary folders only; no Mac, no
network, no Claude.
Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import contextlib
import datetime
import fcntl
import io
import json
import os
import shutil
import subprocess
import sys
import tarfile
import tempfile
import unittest
from unittest import mock

import teach_backup as backup

HERE = os.path.dirname(os.path.abspath(__file__))
MINUTE = datetime.datetime(2026, 11, 25, 4, 30)


def minute(offset=0):
    return MINUTE + datetime.timedelta(minutes=offset)


class Setup(unittest.TestCase):
    """A teaching folder with the things that are backed up and the things that are not, inside a
    temporary root, so that the default backup folder is a sibling of it, as on the Mac."""

    def setUp(self):
        self.root = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.root, ignore_errors=True)
        self.folder = os.path.join(self.root, "PodcastTeaching")
        self.backups = os.path.join(self.root, "PodcastTeachingBackups")
        for name, text in {
                "labels/a1.json": '{"ads": [1]}', "labels/b2.json": '{"ads": []}',
                "labels-snapped/a1.json": '{"ads": [1.5]}', "labels-second/a1.json": '{"ads": [1.2]}',
                "transcripts/a1.txt": "line one\nline two\n", "transcripts/b2.txt": "hello\n",
                "copies/a1.truth.txt": "12.0 30.0\n", "copies/a1.json": "{}",
                "episodes.json": '{"version": 1, "episodes": []}', "shelf.json": "[]",
                "marking-spend.json": '{"version": 1, "budgets": {}}',
                # What is not backed up.
                "audio/a1.mp3": "sound", "meaning-cache/a1.json": "{}", "passage-cache/a1.json": "{}",
                ".lock": "", "notes.txt": "not json", ".hidden.json": "{}", ".x.part": "half",
                "labels/.y.part": "half"}.items():
            self.write(name, text)

    def write(self, name, text):
        path = os.path.join(self.folder, *name.split("/"))
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            f.write(text)

    def run_main(self, *argv):
        lines = []
        code = backup.main(list(argv), say=lines.append)
        return code, "\n".join(lines)

    def made(self, offset=0, **more):
        """Makes one backup at the given minute and returns its path."""
        backup.make_backup(self.folder, now=minute(offset), say=lambda line: None, **more)
        return os.path.join(self.backups, "teaching-%s.tar.gz" % minute(offset).strftime("%Y-%m-%d-%H%M"))

    def names_in(self, path):
        with tarfile.open(path, "r:gz") as tar:
            return sorted(member.name for member in tar if member.isreg())

    def listing(self, folder):
        found = {}
        for where, _, files in os.walk(folder):
            for name in files:
                path = os.path.join(where, name)
                with open(path, "rb") as f:
                    found[os.path.relpath(path, folder)] = (f.read(), os.stat(path).st_mtime_ns)
        return found

    def backup_files(self):
        return sorted(os.listdir(self.backups))


class MakeTests(Setup):
    def test_a_backup_holds_the_marks_the_transcripts_the_copies_and_the_small_json_files(self):
        path = self.made()
        self.assertEqual(self.names_in(path), [
            "copies/a1.json", "copies/a1.truth.txt", "episodes.json", "labels-second/a1.json",
            "labels-snapped/a1.json", "labels/a1.json", "labels/b2.json", "marking-spend.json", "shelf.json",
            "transcripts/a1.txt", "transcripts/b2.txt"])

    def test_it_leaves_out_the_audio_the_caches_the_lock_and_temporary_files(self):
        names = " ".join(self.names_in(self.made()))
        for left_out in ("audio", "cache", ".lock", "notes.txt", ".hidden", ".part"):
            self.assertNotIn(left_out, names)

    def test_what_is_in_it_is_what_the_folder_had(self):
        path = self.made()
        with tarfile.open(path, "r:gz") as tar:
            self.assertEqual(tar.extractfile("labels/a1.json").read(), b'{"ads": [1]}')
            self.assertEqual(tar.extractfile("transcripts/a1.txt").read(), b"line one\nline two\n")

    def test_the_default_place_is_next_to_the_teaching_folder_and_it_is_named_by_the_minute(self):
        path = self.made()
        self.assertEqual(self.backup_files(), ["teaching-2026-11-25-0430.tar.gz"])
        self.assertTrue(os.path.isfile(path))

    def test_to_names_another_folder(self):
        elsewhere = os.path.join(self.root, "elsewhere")
        backup.make_backup(self.folder, to=elsewhere, now=minute(), say=lambda line: None)
        self.assertEqual(os.listdir(elsewhere), ["teaching-2026-11-25-0430.tar.gz"])
        self.assertFalse(os.path.exists(self.backups))

    def test_it_prints_one_plain_line_with_the_name_the_files_and_the_size(self):
        lines = []
        backup.make_backup(self.folder, now=minute(), say=lines.append)
        self.assertEqual(len(lines), 1)
        self.assertIn("teaching-2026-11-25-0430.tar.gz: written.", lines[0])
        self.assertIn("11 files", lines[0])
        self.assertRegex(lines[0], r"\d+(\.\d)? (KB|MB)")

    def test_it_keeps_the_newest_n_and_removes_the_older_ones(self):
        for offset in range(5):
            self.made(offset, keep=3)
        self.assertEqual(self.backup_files(), ["teaching-2026-11-25-0432.tar.gz",
                                               "teaching-2026-11-25-0433.tar.gz",
                                               "teaching-2026-11-25-0434.tar.gz"])

    def test_it_keeps_14_by_default(self):
        for offset in range(16):
            self.made(offset)
        self.assertEqual(len(self.backup_files()), 14)
        self.assertEqual(self.backup_files()[0], "teaching-2026-11-25-0432.tar.gz")

    def test_it_never_deletes_the_one_off_backups_or_anything_not_named_like_its_own(self):
        os.makedirs(self.backups)
        keep_these = ["before-big-run-1-2026-11-25.tar.gz", "notes.txt", "teaching-latest.tar.gz",
                      "teaching-2026-11-25-0430.tar.gz.old", "my-teaching-2026-01-01-0000.tar.gz"]
        for name in keep_these:
            with open(os.path.join(self.backups, name), "w") as f:
                f.write("mine")
        os.makedirs(os.path.join(self.backups, "teaching-2026-01-01-0000.tar.gz"))  # a folder
        for offset in range(4):
            self.made(offset, keep=1)
        self.assertEqual(sorted(set(self.backup_files()) - set(keep_these)),
                         ["teaching-2026-01-01-0000.tar.gz", "teaching-2026-11-25-0433.tar.gz"])
        for name in keep_these:
            with open(os.path.join(self.backups, name)) as f:
                self.assertEqual(f.read(), "mine", name)

    def test_the_line_says_when_it_removed_older_backups(self):
        for offset in range(2):
            self.made(offset, keep=2)
        lines = []
        backup.make_backup(self.folder, now=minute(2), keep=2, say=lines.append)
        self.assertIn("Removed 1 older backup", lines[0])
        self.assertIn("newest 2", lines[0])

    def test_an_interrupted_write_leaves_no_backup_and_no_temporary_file_and_keeps_the_old_ones(self):
        old = self.made(0)
        real = tarfile.TarFile.addfile
        calls = []

        def breaks(tar, info, fileobj=None):
            calls.append(info.name)
            if len(calls) == 4:
                raise KeyboardInterrupt()
            return real(tar, info, fileobj)

        with mock.patch.object(tarfile.TarFile, "addfile", breaks):
            with self.assertRaises(KeyboardInterrupt):
                backup.make_backup(self.folder, now=minute(1), keep=1, say=lambda line: None)
        self.assertEqual(self.backup_files(), [os.path.basename(old)])
        self.assertEqual(self.names_in(old).count("labels/a1.json"), 1)

    def test_a_failing_rename_leaves_no_backup_and_no_temporary_file(self):
        os.makedirs(self.backups)
        with mock.patch("os.replace", side_effect=OSError("disk full")):
            with self.assertRaises(OSError):
                backup.make_backup(self.folder, now=minute(), say=lambda line: None)
        self.assertEqual(self.backup_files(), [])

    def test_it_only_reads_the_folder_and_takes_no_lock(self):
        os.remove(os.path.join(self.folder, ".lock"))
        before = self.listing(self.folder)
        self.made()
        self.assertEqual(self.listing(self.folder), before)
        self.assertFalse(os.path.exists(os.path.join(self.folder, ".lock")))
        # Another run holds the folder's lock: the backup goes on all the same.
        with open(os.path.join(self.folder, ".lock"), "a") as held:
            fcntl.flock(held.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
            self.made(1)
        self.assertEqual(len(self.backup_files()), 2)

    def test_a_file_that_is_too_large_is_left_out_and_said(self):
        self.write("transcripts/huge.txt", "x" * 100)
        lines = []
        with mock.patch.object(backup, "MAX_FILE_BYTES", 50):
            backup.make_backup(self.folder, now=minute(), say=lines.append)
        self.assertNotIn("transcripts/huge.txt", self.names_in(os.path.join(self.backups, os.listdir(self.backups)[0])))
        self.assertIn("left out", lines[0])

    def test_a_missing_folder_is_a_set_up_problem(self):
        code, said = self.run_main("make", "--folder", os.path.join(self.root, "nothing"))
        self.assertEqual(code, 2)
        self.assertIn("There is no teaching folder", said)
        self.assertFalse(os.path.exists(self.backups))

    def test_a_folder_with_nothing_to_save_writes_no_empty_backup(self):
        empty = os.path.join(self.root, "Empty")
        os.makedirs(os.path.join(empty, "audio"))
        code, said = self.run_main("make", "--folder", empty)
        self.assertEqual(code, 0)
        self.assertIn("Nothing to back up", said)
        self.assertFalse(os.path.exists(os.path.join(self.root, "PodcastTeachingBackups")))

    def test_keep_must_be_at_least_1(self):
        for value in ("0", "-2", "many"):
            with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
                self.run_main("make", "--folder", self.folder, "--keep", value)
        self.assertFalse(os.path.exists(self.backups))

    def test_make_with_check_makes_then_checks_the_new_file(self):
        code, said = self.run_main("make", "--check", "--folder", self.folder)
        self.assertEqual(code, 0, said)
        lines = said.splitlines()
        self.assertEqual(len(lines), 2)
        self.assertIn(": written.", lines[0])
        self.assertIn("is whole", lines[1])

    def test_when_the_check_of_the_new_file_fails_it_says_so_exits_1_and_removes_nothing(self):
        old = self.made(-600000)  # more than a year ago, so it is not the minute of the real run
        self.write("labels/bad.json", "{not json")
        code, said = self.run_main("make", "--check", "--folder", self.folder, "--keep", "1")
        self.assertEqual(code, 1)
        self.assertIn("labels/bad.json", said)
        self.assertIn(os.path.basename(old), self.backup_files())
        self.assertEqual(len(self.backup_files()), 2)


class CheckTests(Setup):
    def test_a_good_backup_is_whole_and_exit_0(self):
        path = self.made()
        code, said = self.run_main("check", "--file", path)
        self.assertEqual(code, 0, said)
        self.assertIn("is whole", said)
        self.assertIn("11 files", said)
        self.assertIn("8 JSON files", said)

    def test_with_the_folder_it_says_how_many_label_files_the_backup_lacks(self):
        path = self.made()
        self.write("labels/new1.json", "{}")
        self.write("labels-snapped/new1.json", "{}")
        self.write("labels-second/new1.json", "{}")
        code, said = self.run_main("check", "--file", path, "--folder", self.folder)
        self.assertEqual(code, 0, said)
        self.assertIn("3 label files", said)
        self.assertIn("lacks", said)

    def test_with_the_folder_and_nothing_missing_it_says_none(self):
        code, said = self.run_main("check", "--file", self.made(), "--folder", self.folder)
        self.assertEqual(code, 0, said)
        self.assertIn("has every label file", said)

    def test_a_truncated_backup_is_caught(self):
        path = self.made()
        with open(path, "rb") as f:
            data = f.read()
        for cut in (len(data) // 2, len(data) - 4, 10):
            with open(path, "wb") as f:
                f.write(data[:cut])
            code, said = self.run_main("check", "--file", path)
            self.assertEqual(code, 1, (cut, said))
            self.assertIn("cannot be read to the end", said)

    def test_a_flipped_byte_is_caught(self):
        path = self.made()
        with open(path, "rb") as f:
            data = bytearray(f.read())
        data[len(data) // 2] ^= 0xFF
        with open(path, "wb") as f:
            f.write(data)
        code, said = self.run_main("check", "--file", path)
        self.assertEqual(code, 1, said)

    def test_a_json_file_inside_that_does_not_parse_is_named(self):
        self.write("labels/broken.json", '{"ads": [1,')
        self.write("episodes.json", "")
        path = self.made()
        code, said = self.run_main("check", "--file", path)
        self.assertEqual(code, 1)
        self.assertIn("labels/broken.json", said)
        self.assertIn("episodes.json", said)
        self.assertIn("do not read as JSON", said)

    def test_something_that_is_not_a_backup_or_is_missing(self):
        text = os.path.join(self.root, "x.tar.gz")
        with open(text, "w") as f:
            f.write("just words")
        self.assertEqual(self.run_main("check", "--file", text)[0], 1)
        code, said = self.run_main("check", "--file", os.path.join(self.root, "none.tar.gz"))
        self.assertEqual(code, 2)
        self.assertIn("There is no backup", said)

    def test_a_backup_with_a_file_name_that_leaves_the_folder_is_not_well(self):
        path = os.path.join(self.root, "evil.tar.gz")
        with tarfile.open(path, "w:gz") as tar:
            info = tarfile.TarInfo("../outside.json")
            info.size = 2
            tar.addfile(info, io.BytesIO(b"{}"))
        code, said = self.run_main("check", "--file", path)
        self.assertEqual(code, 1)
        self.assertIn("../outside.json", said)


class RestoreTests(Setup):
    def test_it_unpacks_into_an_empty_folder_exactly_as_it_was(self):
        path = self.made()
        into = os.path.join(self.root, "restored")
        os.makedirs(into)
        code, said = self.run_main("restore", "--file", path, "--into", into)
        self.assertEqual(code, 0, said)
        self.assertIn("11 files", said)
        restored = {name: data for name, (data, _) in self.listing(into).items()}
        original = {name: data for name, (data, _) in self.listing(self.folder).items()
                    if name in self.names_in(path)}
        self.assertEqual(restored, original)

    def test_it_makes_the_folder_when_there_is_none(self):
        into = os.path.join(self.root, "new", "deeper")
        self.assertEqual(self.run_main("restore", "--file", self.made(), "--into", into)[0], 0)
        self.assertTrue(os.path.isfile(os.path.join(into, "labels", "a1.json")))

    def test_it_refuses_a_folder_that_has_anything_in_it_and_writes_nothing(self):
        path = self.made()
        into = os.path.join(self.root, "full")
        os.makedirs(into)
        with open(os.path.join(into, "mine.txt"), "w") as f:
            f.write("mine")
        code, said = self.run_main("restore", "--file", path, "--into", into)
        self.assertEqual(code, 2)
        self.assertIn("not empty", said)
        self.assertEqual(os.listdir(into), ["mine.txt"])

    def test_it_refuses_the_live_teaching_folder(self):
        path = self.made()
        before = self.listing(self.folder)
        code, said = self.run_main("restore", "--file", path, "--into", self.folder)
        self.assertEqual(code, 2)
        self.assertEqual(self.listing(self.folder), before)

    def test_it_refuses_a_file_in_place_of_a_folder(self):
        target = os.path.join(self.root, "afile")
        with open(target, "w") as f:
            f.write("x")
        self.assertEqual(self.run_main("restore", "--file", self.made(), "--into", target)[0], 2)

    def test_a_damaged_backup_unpacks_nothing(self):
        path = self.made()
        with open(path, "rb") as f:
            data = f.read()
        with open(path, "wb") as f:
            f.write(data[:len(data) // 2])
        into = os.path.join(self.root, "restored")
        code, said = self.run_main("restore", "--file", path, "--into", into)
        self.assertEqual(code, 1)
        self.assertIn("cannot be read to the end", said)
        self.assertFalse(os.path.exists(into))

    def test_a_name_that_leaves_the_folder_is_never_written(self):
        path = os.path.join(self.root, "evil.tar.gz")
        with tarfile.open(path, "w:gz") as tar:
            info = tarfile.TarInfo("../outside.json")
            info.size = 2
            tar.addfile(info, io.BytesIO(b"{}"))
        into = os.path.join(self.root, "restored")
        self.assertEqual(self.run_main("restore", "--file", path, "--into", into)[0], 1)
        self.assertFalse(os.path.exists(os.path.join(self.root, "outside.json")))


class CommandLineTests(unittest.TestCase):
    def run_tool(self, *argv):
        return subprocess.run([sys.executable, os.path.join(HERE, "teach_backup.py")] + list(argv),
                              capture_output=True, text=True, timeout=60)

    def test_no_command_is_a_usage_error(self):
        self.assertEqual(self.run_tool().returncode, 2)

    def test_the_help_says_restore_never_writes_into_the_live_folder(self):
        done = self.run_tool("restore", "--help")
        self.assertEqual(done.returncode, 0)
        self.assertIn("never writes into the live", " ".join(done.stdout.split()))
        self.assertIn("empty", done.stdout)

    def test_it_runs_end_to_end_as_a_program(self):
        root = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, root, ignore_errors=True)
        folder = os.path.join(root, "PodcastTeaching")
        os.makedirs(os.path.join(folder, "labels"))
        with open(os.path.join(folder, "labels", "a.json"), "w") as f:
            json.dump({"ads": []}, f)
        done = self.run_tool("make", "--check", "--folder", folder)
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertIn("is whole", done.stdout)
        self.assertEqual(len(os.listdir(os.path.join(root, "PodcastTeachingBackups"))), 1)


if __name__ == "__main__":
    unittest.main()
