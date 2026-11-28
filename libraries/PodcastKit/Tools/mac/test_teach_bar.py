"""Tests for teach_bar.py: the bar's pass and fail causes and the skips with no ad, on made-up
stretches. Run: python3 -m pytest test_teach_bar.py -q"""
import unittest

import teach_bar as bar


class BarTests(unittest.TestCase):
    def score(self, truth, skips, maybe=(), duration=1000.0):
        return bar.score(truth, maybe, skips, duration)

    def test_an_exact_skip_passes(self):
        total = self.score([(100, 140)], [(100, 140)])
        self.assertEqual((total["breaks"], total["passed"]), (1, 1))

    def test_within_five_seconds_each_side_passes(self):
        self.assertEqual(self.score([(100, 140)], [(104, 144)])["passed"], 1)
        self.assertEqual(self.score([(100, 140)], [(106, 140)])["causes"], {"startsLate": 1})

    def test_no_skip_is_missed(self):
        self.assertEqual(self.score([(100, 140)], [])["causes"], {"missed": 1})

    def test_a_short_stretch_is_not_a_break(self):
        self.assertEqual(self.score([(100, 109)], [])["breaks"], 0)

    def test_marked_stretches_one_second_apart_are_one_break(self):
        self.assertEqual(self.score([(100, 120), (120.5, 140)], [(100, 140)])["breaks"], 1)

    def test_cutting_show_before_the_break_is_starts_early(self):
        self.assertEqual(self.score([(100, 140)], [(90, 140)])["causes"], {"startsEarly": 1})

    def test_cutting_show_after_the_break_is_lands_too_far(self):
        self.assertEqual(self.score([(100, 140)], [(100, 150)])["causes"], {"landsTooFar": 1})

    def test_a_skip_on_a_neutral_stretch_is_not_a_wrong_skip(self):
        total = self.score([(100, 140)], [(100, 140), (300, 320)], maybe=[(300, 320)])
        self.assertEqual(total["noAdSkips"], 0)

    def test_a_skip_with_no_ad_is_counted(self):
        total = self.score([(100, 140)], [(100, 140), (300, 320)])
        self.assertEqual(total["noAdSkips"], 1)


if __name__ == "__main__":
    unittest.main()
