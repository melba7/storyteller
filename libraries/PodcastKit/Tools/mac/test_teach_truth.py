"""Tests for teach_truth.py (reading a truth file, which transcript lines a stretch covers, saving
bytes) and the rules every tool of the second-download check keeps: Python 3.9 grammar, no key,
no network of their own, files of a sensible size.
Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import ast
import os
import re
import tempfile
import unittest

import teach_truth as truth

HEADER = "# Ads marked from the differences between two downloads of one episode.\n"


class TruthFileTests(unittest.TestCase):
    def test_it_reads_what_the_swift_tool_prints(self):
        text = HEADER + "0:33.480 1:02.120\n1:02:03.500 1:03:00.250\n# Left out: nothing\n\n"
        self.assertEqual(truth.read_truth(text), [(33.48, 62.12), (3723.5, 3780.25)])

    def test_comments_only_give_no_stretch(self):
        self.assertEqual(truth.read_truth(HEADER + "# The two files have no frame in common\n"), [])
        self.assertEqual(truth.read_truth(""), [])

    def test_a_line_that_is_not_two_times_is_refused_with_its_number(self):
        for bad in ("0:10.000\n", "ten twenty\n", "0:20.000 0:10.000\n", "0:10.000 0:10.000\n",
                    "0:10.000 0:99.000\n", "0:10.000 0:20.000 0:30.000\n", "1e5:00 2:00\n"):
            with self.assertRaises(ValueError, msg=bad) as caught:
                truth.read_truth(HEADER + bad)
            self.assertIn("Line 2", str(caught.exception))

    def test_a_number_too_big_to_be_a_time_is_refused(self):
        with self.assertRaises(ValueError):
            truth.read_truth("0:10.000 " + "9" * 400 + ":00.000\n")

    def test_stretches_come_back_in_order(self):
        self.assertEqual(truth.read_truth("2:00.000 2:30.000\n1:00.000 1:20.000\n"),
                         [(60.0, 80.0), (120.0, 150.0)])


class CoverTests(unittest.TestCase):
    LINES = [(n * 5.0, "line") for n in range(20)]

    def test_lines_that_are_half_covered_or_more_are_in(self):
        # Line 7 starts at 30 and line 13 at 60. 33.48 covers 1.52 s of line 7 (under half): out.
        self.assertEqual(truth.covered(self.LINES, 33.48, 62.12), (8, 12))
        self.assertEqual(truth.covered(self.LINES, 32.0, 62.6), (7, 13))

    def test_a_stretch_inside_one_line_takes_that_line(self):
        self.assertEqual(truth.covered(self.LINES, 31.0, 33.0), (7, 7))

    def test_a_stretch_after_the_last_line_touches_nothing(self):
        self.assertIsNone(truth.covered(self.LINES, 500.0, 600.0))
        self.assertIsNone(truth.covered([], 1.0, 5.0))

    def test_the_last_line_lasts_five_seconds(self):
        self.assertEqual(truth.covered(self.LINES, 95.0, 100.0), (20, 20))
        self.assertIsNone(truth.covered(self.LINES, 100.0, 110.0))


class SaveTests(unittest.TestCase):
    def test_bytes_are_saved_whole_and_no_temporary_file_is_left(self):
        with tempfile.TemporaryDirectory() as folder:
            path = os.path.join(folder, "a.json")
            truth.save_bytes(path, b"one")
            truth.save_bytes(path, b"two")
            with open(path, "rb") as handle:
                self.assertEqual(handle.read(), b"two")
            self.assertEqual(os.listdir(folder), ["a.json"])


class CodeRulesTests(unittest.TestCase):
    """The Mac has Python 3.9 and no key, and these tools talk to nobody but the episode's address."""
    HERE = os.path.dirname(os.path.abspath(__file__))
    TOOLS = ("teach_truth.py", "teach_snap.py", "teach_second.py", "teach_copies.py")
    BANNED = ("urllib", "socket", "http.client", "environ", "getpass", "keychain", "input(", "claude",
              "Authorization", "api_key")

    def source(self, name):
        with open(os.path.join(self.HERE, name), encoding="utf-8") as handle:
            return handle.read()

    def test_the_tools_parse_with_the_grammar_of_python_3_9(self):
        for name in self.TOOLS:
            ast.parse(self.source(name), feature_version=(3, 9))

    def test_a_newer_grammar_would_be_caught_by_that_check(self):
        with self.assertRaises(SyntaxError):
            ast.parse("match x:\n    case 1:\n        pass\n", feature_version=(3, 9))

    def test_the_tools_have_no_key_no_environment_and_no_network_of_their_own(self):
        for name in self.TOOLS:
            for word in self.BANNED:
                self.assertNotIn(word, self.source(name), "%s: %s" % (name, word))

    def test_the_two_tools_that_run_no_program_do_not_import_subprocess(self):
        for name in ("teach_truth.py", "teach_snap.py"):
            self.assertIsNone(re.search(r"\bsubprocess\b", self.source(name)), name)

    def test_files_stay_under_about_300_lines(self):
        for name in self.TOOLS + ("test_teach_snap.py", "test_teach_truth.py", "test_teach_copies.py",
                                  "test_teach_copies_limits.py", "test_teach_copies_launcher.py",
                                  "test_teach_snap_readers.py", "test_teach_snap_files.py"):
            self.assertLess(len(self.source(name).splitlines()), 340, name)


if __name__ == "__main__":
    unittest.main()
