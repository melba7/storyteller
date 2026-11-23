"""Tests for teach_settings.py: the joints rows, and the steady files. No files, no network.
Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import unittest

from teach_settings_testing import (
    FEED_A, FEED_B, JOINTS, MEANING, STEADY, choose, rows_of, row, show, total)


def pair(joints, steady=None, episodes=3):
    """The row before (1000 s of ads, 500 s heard, 100 s of show cut by mistake) then a joints row that
    has `joints` = (heard, cut), and a steady row with `steady` = (heard, cut) when it is given."""
    def whole(heard, cut):
        return total(episodes, ad=1000, heard=heard, cut=cut)
    rows = [row(MEANING, whole=whole(500, 100)), row(JOINTS, whole=whole(*joints))]
    if steady:
        rows.append(row(STEADY, whole=whole(*steady)))
    return choose(rows_of(*rows))[0]


class JointsTests(unittest.TestCase):
    def test_joints_are_on_by_default_and_steady_ones_off(self):
        default, shows, _ = choose([])
        self.assertEqual((default["joints"], default["steadyJoints"], shows), (True, False, []))

    def test_joints_stay_on_when_heard_seconds_fall_and_wrong_ones_rise_by_at_most_one_in_a_hundred(self):
        self.assertTrue(pair((490, 100))["joints"])
        self.assertTrue(pair((490, 90))["joints"])
        self.assertTrue(pair((490, 101))["joints"], "1 in 100 more is allowed")
        self.assertTrue(pair((499.5, 100))["joints"])

    def test_joints_are_off_everywhere_when_wrong_seconds_rise_by_more(self):
        self.assertFalse(pair((490, 102))["joints"])
        self.assertFalse(pair((490, 109))["joints"], "10 s found, 9 s cut by mistake on 100 s")
        self.assertFalse(pair((400, 150))["joints"])

    def test_joints_that_change_nothing_or_lose_ground_are_off(self):
        self.assertFalse(pair((500, 100))["joints"])
        self.assertFalse(pair((510, 100))["joints"], "more heard than before")

    def test_joints_with_fewer_than_three_marked_episodes_change_nothing(self):
        self.assertTrue(pair((500, 100), episodes=2)["joints"])

    def test_without_a_joints_row_or_a_row_before_it_nothing_changes(self):
        self.assertTrue(choose(rows_of(row(MEANING, whole=total(heard=500))))[0]["joints"])
        self.assertTrue(choose(rows_of(row(JOINTS, whole=total(heard=500))))[0]["joints"])

    def test_joints_that_cost_more_than_they_gain_on_a_show_are_off_for_that_show(self):
        # Over all shows the joints find 10 s and cut 8 s more of 2000 s already cut: fine overall.
        base = row(MEANING, show(FEED_A, "Show A", ad=1000, heard=500, cut=1000),
                   show(FEED_B, ad=1000, heard=500, cut=1000))
        joints = row(JOINTS, show(FEED_A, "Show A", ad=1000, heard=499, cut=1008),
                     show(FEED_B, ad=1000, heard=491, cut=1000))
        default, shows, lines = choose(rows_of(base, joints))
        self.assertTrue(default["joints"])
        self.assertEqual(shows, [{"feed": FEED_A, "joints": False}])
        self.assertTrue(any("Show A" in line and "joints" in line for line in lines), lines)


class SteadyTests(unittest.TestCase):
    def test_steady_files_join_in_when_they_hear_less_in_all_for_about_the_same_wrong(self):
        self.assertTrue(pair((490, 100), (480, 100))["steadyJoints"])
        self.assertTrue(pair((490, 100), (480, 101))["steadyJoints"])
        self.assertTrue(pair((490, 0), (480, 0))["steadyJoints"])

    def test_steady_files_stay_out_when_they_hear_as_much_or_cost_more(self):
        self.assertFalse(pair((490, 100), (490, 100))["steadyJoints"])
        self.assertFalse(pair((490, 100), (495, 100))["steadyJoints"])
        self.assertFalse(pair((490, 100), (480, 102))["steadyJoints"])
        self.assertFalse(pair((490, 0), (480, 1))["steadyJoints"])

    def test_less_heard_before_the_skip_does_not_count_when_more_is_heard_in_all(self):
        # 5 s less heard before the skip but 20 s more heard in all.
        base = row(MEANING, whole=total(ad=1000, heard=500, cut=100))
        joints = row(JOINTS, whole=total(ad=1000, heard=490, cut=100, before=40))
        steady = row(STEADY, whole=total(ad=1000, heard=510, cut=100, before=35))
        self.assertFalse(choose(rows_of(base, joints, steady))[0]["steadyJoints"])

    def test_steady_files_need_both_rows(self):
        base = row(MEANING, whole=total(ad=1000, heard=500, cut=100))
        only_steady = row(STEADY, whole=total(ad=1000, heard=400, cut=100))
        only_joints = row(JOINTS, whole=total(ad=1000, heard=400, cut=100))
        self.assertFalse(choose(rows_of(base, only_steady))[0]["steadyJoints"])
        self.assertFalse(choose(rows_of(base, only_joints))[0]["steadyJoints"])

    def test_steady_files_are_off_when_joints_are_off(self):
        default = pair((500, 100), (500, 100))
        self.assertEqual((default["joints"], default["steadyJoints"]), (False, False))


class SteadyOnlyTests(unittest.TestCase):
    """Most podcast files are steady: the plain joints row finds nothing there and the steady row does."""

    def choose(self, joints, steady=None, episodes=3):
        base = row(MEANING, whole=total(episodes, ad=1000, heard=500, cut=100))
        rows = [base, row(JOINTS, whole=total(episodes, ad=1000, heard=joints[0], cut=joints[1]))]
        if steady:
            rows.append(row(STEADY, whole=total(episodes, ad=1000, heard=steady[0], cut=steady[1])))
        return choose(rows_of(*rows))

    def test_a_joints_row_that_finds_nothing_does_not_switch_joints_off_when_the_steady_row_pays(self):
        # The joints row is equal to the row before it. The steady row catches 60 s more, no more wrong.
        default, shows, lines = self.choose((500, 100), (440, 100))
        self.assertEqual((default["joints"], default["steadyJoints"], shows), (True, True, []))
        self.assertTrue(any("Joints are used in steady files too" in line for line in lines), lines)
        self.assertFalse(any("Joints are off" in line for line in lines), lines)

    def test_when_neither_row_pays_joints_and_steady_files_are_off(self):
        default, _, lines = self.choose((500, 100), (500, 100))
        self.assertEqual((default["joints"], default["steadyJoints"]), (False, False))
        self.assertTrue(any("Joints are off for every show" in line for line in lines), lines)
        self.assertFalse(any("steady files too" in line.lower() and "used" in line for line in lines), lines)
        # No steady row at all: the plain row alone decides, as before.
        self.assertFalse(self.choose((500, 100))[0]["joints"])

    def test_when_the_plain_row_pays_and_the_steady_row_adds_nothing_steady_files_stay_out(self):
        default, _, lines = self.choose((440, 100), (440, 100))
        self.assertEqual((default["joints"], default["steadyJoints"]), (True, False))
        self.assertFalse(any("steady files too" in line for line in lines), lines)

    def test_a_steady_row_that_gains_with_too_many_wrong_seconds_does_not_save_the_joints(self):
        # 60 s more caught, but 102 s cut by mistake on 100 s before: it does not pay, nor does the plain row.
        default, _, _ = self.choose((500, 100), (440, 102))
        self.assertEqual((default["joints"], default["steadyJoints"]), (False, False))
        # One in a hundred more is allowed.
        default, _, _ = self.choose((500, 100), (440, 101))
        self.assertEqual((default["joints"], default["steadyJoints"]), (True, True))

    def test_the_steady_row_has_to_pay_against_the_row_before_the_joints_row_not_against_the_joints_row(self):
        # The plain row pays a little. The steady row beats it on right seconds but cuts 1 s over the
        # allowance of the row before: it does not pay, so steady files stay out and joints stay on.
        default, _, _ = self.choose((490, 100), (440, 102))
        self.assertEqual((default["joints"], default["steadyJoints"]), (True, False))

    def test_when_only_the_steady_row_pays_it_is_the_one_that_is_used_even_if_it_is_no_better_than_plain(self):
        # The plain row finds as much but cuts 10 percent more by mistake, so it does not pay. The
        # steady row finds the same and cuts no more: joints on, with steady files too.
        default, _, _ = self.choose((440, 110), (440, 100))
        self.assertEqual((default["joints"], default["steadyJoints"]), (True, True))

    def test_with_both_paying_steady_files_need_more_right_seconds_than_plain_and_not_more_wrong(self):
        self.assertTrue(self.choose((490, 100), (480, 101))[0]["steadyJoints"])
        self.assertFalse(self.choose((490, 100), (480, 102))[0]["steadyJoints"])
        self.assertFalse(self.choose((490, 100), (490, 100))[0]["steadyJoints"])

    def test_the_wrong_allowance_of_steady_files_is_measured_against_the_plain_joints_row(self):
        # The plain row cuts 50 s by mistake (the row before 100 s). The steady row pays against the row
        # before, but may cut only one in a hundred more than the plain row: 50.5 s, not 51 s.
        self.assertTrue(self.choose((490, 50), (480, 50.5))[0]["steadyJoints"])
        self.assertFalse(self.choose((490, 50), (480, 51))[0]["steadyJoints"])

    def test_fewer_than_three_marked_episodes_change_nothing(self):
        default, _, _ = self.choose((500, 100), (440, 100), episodes=2)
        self.assertEqual((default["joints"], default["steadyJoints"]), (True, False))

    def test_a_show_whose_plain_joints_row_is_flat_keeps_joints_when_steady_files_pay(self):
        base = row(MEANING, show(FEED_A, ad=1000, heard=500, cut=1000), show(FEED_B, ad=1000, heard=500, cut=1000))
        joints = row(JOINTS, show(FEED_A, ad=1000, heard=500, cut=1000), show(FEED_B, ad=1000, heard=500, cut=1000))
        steady = row(STEADY, show(FEED_A, ad=1000, heard=450, cut=1000), show(FEED_B, ad=1000, heard=450, cut=1000))
        default, shows, _ = choose(rows_of(base, joints, steady))
        self.assertEqual((default["joints"], default["steadyJoints"], shows), (True, True, []))


class SteadyPerShowTests(unittest.TestCase):
    def test_a_show_where_the_steady_row_does_worse_than_the_joints_row_is_off_for_steady(self):
        base = row(MEANING, show(FEED_A, ad=1000, heard=500, cut=1000), show(FEED_B, "Show B", ad=1000, heard=500, cut=1000))
        joints = row(JOINTS, show(FEED_A, ad=1000, heard=400, cut=1000), show(FEED_B, "Show B", ad=1000, heard=400, cut=1000))
        steady = row(STEADY, show(FEED_A, ad=1000, heard=390, cut=1000),
                     show(FEED_B, "Show B", ad=1000, heard=405, cut=1000))
        default, shows, lines = choose(rows_of(base, joints, steady))
        self.assertTrue(default["steadyJoints"], "5 s more heard over all shows is a gain of 5 s")
        self.assertEqual(shows, [{"feed": FEED_B, "steadyJoints": False}])
        self.assertTrue(any("Show B" in line and "steady" in line for line in lines), lines)

    def test_a_show_with_joints_off_needs_no_steady_entry(self):
        base = row(MEANING, show(FEED_A, ad=1000, heard=500, cut=1000), show(FEED_B, ad=1000, heard=500, cut=1000))
        joints = row(JOINTS, show(FEED_A, ad=1000, heard=505, cut=1000), show(FEED_B, ad=1000, heard=300, cut=1000))
        steady = row(STEADY, show(FEED_A, ad=1000, heard=520, cut=1000), show(FEED_B, ad=1000, heard=280, cut=1000))
        default, shows, _ = choose(rows_of(base, joints, steady))
        self.assertEqual((default["joints"], default["steadyJoints"]), (True, True))
        self.assertEqual(shows, [{"feed": FEED_A, "joints": False}])

    def test_steady_files_are_not_judged_per_show_when_they_are_off_overall(self):
        base = row(MEANING, show(FEED_A, ad=1000, heard=500, cut=1000))
        joints = row(JOINTS, show(FEED_A, ad=1000, heard=400, cut=1000))
        steady = row(STEADY, show(FEED_A, ad=1000, heard=420, cut=1000))
        default, shows, _ = choose(rows_of(base, joints, steady))
        self.assertEqual((default["steadyJoints"], shows), (False, []))


if __name__ == "__main__":
    unittest.main()
