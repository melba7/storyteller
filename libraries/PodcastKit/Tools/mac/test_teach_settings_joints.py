"""Tests for teach_settings.py: the joints rows. No files, no network.
Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import unittest

from teach_settings_testing import (
    FEED_A, FEED_B, JOINTS, MEANING, STEADY, choose, rows_of, row, show, total)


class JointsTests(unittest.TestCase):
    def test_joints_are_on_by_default_and_steady_ones_off(self):
        default, shows, _ = choose([])
        self.assertEqual((default["joints"], default["steadyJoints"], shows), (True, False, []))

    def test_joints_that_cost_more_than_they_gain_on_a_show_are_off_for_that_show(self):
        base = row(MEANING, show(FEED_A, "Show A", heard=30), show(FEED_B, heard=30))
        joints = row(JOINTS, show(FEED_A, "Show A", heard=29, cut=8), show(FEED_B, heard=21))
        default, shows, lines = choose(rows_of(base, joints))
        self.assertTrue(default["joints"])
        self.assertEqual(shows, [{"feed": FEED_A, "joints": False}])
        self.assertTrue(any("Show A" in line and "joints" in line for line in lines), lines)

    def test_joints_that_cost_more_than_they_gain_overall_are_off_everywhere(self):
        base = row(MEANING, show(FEED_A, heard=30))
        joints = row(JOINTS, show(FEED_A, heard=29, cut=8))
        default, shows, _ = choose(rows_of(base, joints))
        self.assertEqual((default["joints"], default["steadyJoints"], shows), (False, False, []))

    def steady(self, before_joints, before_steady, cut_joints, cut_steady):
        base = row(MEANING, whole=total(ad=1000, heard=500))
        joints = row(JOINTS, whole=total(ad=1000, heard=100, cut=cut_joints, before=before_joints))
        steady = row(STEADY, whole=total(ad=1000, heard=100, cut=cut_steady, before=before_steady))
        return choose(rows_of(base, joints, steady))[0]["steadyJoints"]

    def test_steady_files_join_in_when_they_hear_less_before_the_skip_for_about_the_same_wrong(self):
        self.assertTrue(self.steady(40, 30, 100, 100))
        self.assertTrue(self.steady(40, 30, 100, 101))
        self.assertTrue(self.steady(40, 0, 0, 0))

    def test_steady_files_stay_out_when_they_hear_as_much_or_cost_more(self):
        self.assertFalse(self.steady(40, 40, 100, 100))
        self.assertFalse(self.steady(40, 45, 100, 100))
        self.assertFalse(self.steady(40, 30, 100, 102))
        self.assertFalse(self.steady(40, 30, 0, 1))

    def test_steady_files_need_both_rows(self):
        base = row(MEANING, whole=total(ad=1000, heard=500))
        only_steady = row(STEADY, whole=total(ad=1000, heard=100, before=1))
        only_joints = row(JOINTS, whole=total(ad=1000, heard=100, before=9))
        self.assertFalse(choose(rows_of(base, only_steady))[0]["steadyJoints"])
        self.assertFalse(choose(rows_of(base, only_joints))[0]["steadyJoints"])

    def test_steady_files_need_joints_to_be_on(self):
        base = row(MEANING, whole=total(heard=30))
        joints = row(JOINTS, whole=total(heard=29, cut=8, before=40))
        steady = row(STEADY, whole=total(heard=29, cut=8, before=10))
        default = choose(rows_of(base, joints, steady))[0]
        self.assertEqual((default["joints"], default["steadyJoints"]), (False, False))


if __name__ == "__main__":
    unittest.main()
