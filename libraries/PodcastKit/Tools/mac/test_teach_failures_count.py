"""Tests for the count command of teach_failures.py (the launchers print it).
Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import unittest

import teach_failures as failures
from teach_testing import Folder


class CountTests(unittest.TestCase):
    def test_it_counts_the_episodes_on_the_list_of_a_step(self):
        folder, said = Folder(self), []
        failures.Failures(folder.dir, "label").failed("000000000001")
        failures.Failures(folder.dir, "label").failed("000000000002")
        failures.Failures(folder.dir, "transcribe").failed("000000000003")
        self.assertEqual(failures.main(["count", "--folder", folder.dir], say=said.append), 0)
        self.assertEqual(said, [2])
        failures.main(["count", "--folder", folder.dir, "--step", "transcribe"], say=said.append)
        self.assertEqual(said[-1], 1)

    def test_no_file_is_none_and_a_bad_command_is_a_set_up_problem(self):
        folder, said = Folder(self), []
        failures.main(["count", "--folder", folder.dir], say=said.append)
        self.assertEqual(said, [0])
        self.assertEqual(failures.main(["nonsense"], say=said.append), 2)


if __name__ == "__main__":
    unittest.main()
