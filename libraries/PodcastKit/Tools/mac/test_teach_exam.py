"""Tests for teach_exam.py: reading and adding to the sealed exam list.
Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import json
import os
import unittest

import teach_exam as exam
import teach_store as store
from teach_testing import Folder


class ExamTests(unittest.TestCase):
    def setUp(self):
        self.folder = Folder(self)

    def write(self, text):
        with open(self.folder.path("exam.json"), "w") as f:
            f.write(text)

    def test_no_file_is_an_empty_exam(self):
        self.assertEqual(exam.read_exam(self.folder.dir), [])

    def test_add_keeps_order_and_skips_ids_already_in(self):
        exam.add_to_exam(self.folder.dir, ["00000000000b", "00000000000a"])
        result = exam.add_to_exam(self.folder.dir, ["00000000000a", "00000000000c", "00000000000c"])
        self.assertEqual(result, ["00000000000b", "00000000000a", "00000000000c"])
        self.assertEqual(exam.read_exam(self.folder.dir), result)
        with open(self.folder.path("exam.json")) as f:
            self.assertEqual(json.load(f), {"episodes": result})

    def test_adding_nothing_writes_no_file(self):
        exam.add_to_exam(self.folder.dir, [])
        self.assertFalse(os.path.exists(self.folder.path("exam.json")))

    def test_a_damaged_file_is_a_problem_and_is_not_overwritten(self):
        for text in ("{broken", "[]", '{"episodes": "no"}', '{"episodes": [1]}',
                     '{"episodes": ["not an id"]}'):
            self.write(text)
            with self.assertRaises(store.Problem, msg=text):
                exam.read_exam(self.folder.dir)
            with self.assertRaises(store.Problem):
                exam.add_to_exam(self.folder.dir, ["00000000000a"])
            with open(self.folder.path("exam.json")) as f:
                self.assertEqual(f.read(), text)

    def test_no_temporary_file_is_left_behind(self):
        exam.add_to_exam(self.folder.dir, ["00000000000a"])
        self.assertEqual(os.listdir(self.folder.dir), ["exam.json"])


if __name__ == "__main__":
    unittest.main()
