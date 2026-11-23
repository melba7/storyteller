"""Tests for teach_settings.py: steady joints decided by the owner's bar (breaks passed and skips with
no ad) when the scorecard rows carry one. No files, no network.
Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import unittest

from teach_settings_testing import (
    FEED_A, FEED_B, JOINTS, MEANING, STEADY, choose, rows_of, row, show, total)


def barred(item, passed, skips, breaks=219):
    return dict(item, bar={"breaks": breaks, "passed": passed, "noAdSkips": skips, "causes": {}})


def rows(joints=(100, 75), steady=(103, 76), heard=(490, 480), cut=(100, 100)):
    """The row before, a joints row and a steady row, each with a bar `(passed, noAdSkips)`. The
    seconds are what the older rule reads: `heard` and `cut` of the joints row and the steady row."""
    def whole(heard, cut):
        return total(3, ad=1000, heard=heard, cut=cut)
    return rows_of(
        barred(row(MEANING, whole=whole(500, 100)), 100, 75),
        barred(row(JOINTS, whole=whole(heard[0], cut[0])), *joints),
        barred(row(STEADY, whole=whole(heard[1], cut[1])), *steady))


class BarTests(unittest.TestCase):
    def test_three_more_breaks_and_one_more_skip_with_no_ad_turn_steady_joints_on(self):
        default, _, lines = choose(rows((100, 75), (103, 76)))
        self.assertTrue(default["steadyJoints"])
        self.assertTrue(default["joints"])
        self.assertTrue(any("breaks" in line and "steady" in line for line in lines), lines)

    def test_two_more_breaks_are_not_enough_even_when_the_seconds_would_say_yes(self):
        default, _, _ = choose(rows((100, 75), (102, 75)))
        self.assertFalse(default["steadyJoints"])

    def test_two_more_skips_with_no_ad_are_too_many_even_when_the_seconds_would_say_yes(self):
        default, _, _ = choose(rows((100, 75), (110, 77)))
        self.assertFalse(default["steadyJoints"])

    def test_fewer_skips_with_no_ad_and_many_more_breaks_are_fine(self):
        self.assertTrue(choose(rows((100, 75), (130, 70)))[0]["steadyJoints"])

    def test_the_bar_decides_even_when_the_seconds_say_nothing_gained(self):
        default, _, _ = choose(rows((100, 75), (104, 75), heard=(500, 500)))
        self.assertTrue(default["steadyJoints"])
        # Steady joints need joints: they are on too.
        self.assertTrue(default["joints"])

    def test_the_joints_row_is_the_row_it_is_compared_with(self):
        # The plain joints row already gained 5 breaks; the steady row adds only 2 over it.
        self.assertFalse(choose(rows((105, 75), (107, 75)))[0]["steadyJoints"])
        self.assertTrue(choose(rows((105, 75), (108, 75)))[0]["steadyJoints"])

    def test_without_a_bar_on_both_rows_the_seconds_decide_as_before(self):
        plain = rows_of(
            row(MEANING, whole=total(3, ad=1000, heard=500, cut=100)),
            row(JOINTS, whole=total(3, ad=1000, heard=490, cut=100)),
            row(STEADY, whole=total(3, ad=1000, heard=480, cut=100)))
        self.assertTrue(choose(plain)[0]["steadyJoints"])
        one = rows_of(
            row(MEANING, whole=total(3, ad=1000, heard=500, cut=100)),
            row(JOINTS, whole=total(3, ad=1000, heard=490, cut=100)),
            barred(row(STEADY, whole=total(3, ad=1000, heard=480, cut=100)), 90, 75))
        self.assertTrue(choose(one)[0]["steadyJoints"])

    def test_a_bar_that_is_not_numbers_counts_as_none(self):
        broken = rows_of(
            row(MEANING, whole=total(3, ad=1000, heard=500, cut=100)),
            dict(row(JOINTS, whole=total(3, ad=1000, heard=490, cut=100)), bar={"passed": "x"}),
            dict(row(STEADY, whole=total(3, ad=1000, heard=480, cut=100)), bar=[1, 2]))
        self.assertTrue(choose(broken)[0]["steadyJoints"])

    def test_a_show_where_steady_files_cost_more_than_they_gain_still_gets_its_own_off_switch(self):
        base = barred(row(MEANING, show(FEED_A, "Show A", ad=1000, heard=500, cut=1000),
                          show(FEED_B, ad=1000, heard=500, cut=1000)), 100, 75)
        joints = barred(row(JOINTS, show(FEED_A, "Show A", ad=1000, heard=500, cut=1000),
                            show(FEED_B, ad=1000, heard=500, cut=1000)), 100, 75)
        steady = barred(row(STEADY, show(FEED_A, "Show A", ad=1000, heard=495, cut=1020),
                            show(FEED_B, ad=1000, heard=450, cut=1000)), 110, 75)
        default, shows, _ = choose(rows_of(base, joints, steady))
        self.assertTrue(default["steadyJoints"])
        self.assertEqual(shows, [{"feed": FEED_A, "steadyJoints": False}])


if __name__ == "__main__":
    unittest.main()
