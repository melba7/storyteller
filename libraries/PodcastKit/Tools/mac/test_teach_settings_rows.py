"""Tests for teach_settings_rows.py: reading the rows of the newest scorecard run. No files, no network.
Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import unittest

import teach_settings_rows as rows
from teach_settings_testing import FEED_A, OWN, card, row, show, total


class ReadingTests(unittest.TestCase):
    def test_a_run_without_rows_has_none(self):
        self.assertEqual(rows.rows_in({"version": 1, "runs": [{"at": 1, "title": "t", "total": total()}]}), [])
        self.assertEqual(rows.rows_in({"version": 1, "runs": []}), [])
        self.assertEqual(rows.rows_in({"version": 1}), [])

    def test_only_the_newest_run_is_read(self):
        newest = {"version": 1, "runs": [
            {"at": 1, "title": "old", "total": total(), "rows": [row(OWN, show(FEED_A))]},
            {"at": 2, "title": "new", "total": total()}]}
        self.assertEqual(rows.rows_in(newest), [])

    def test_damaged_rows_and_shows_are_skipped_not_fatal(self):
        good = row(OWN, show(FEED_A, heard=5))
        odd = [7, None, "x", {"name": 4}, {"name": OWN, "total": "x", "shows": []},
               {"name": "Plus x", "total": total(), "shows": [None, {"feed": 3}, {"feed": ""},
                                                              {"feed": FEED_A, "total": {"adSeconds": "x"}}]},
               {"name": "Plus y", "total": {"episodes": 3}}]
        found = rows.rows_in(card(*odd, good))
        self.assertEqual([r.name for r in found], ["Plus x", OWN])
        self.assertEqual(found[0].shows, {})
        self.assertEqual(found[1].total.right, 95)

    def test_numbers_that_cannot_be_used_leave_the_row_out(self):
        bad = total()
        bad["cutSeconds"] = float("nan")
        worse = total()
        worse["adSeconds"] = True
        found = rows.rows_in(card(row("a", whole=bad), row("b", whole=worse), row("c", whole=total())))
        self.assertEqual([r.name for r in found], ["c"])

    def test_a_total_saved_before_the_heard_before_number_reads_with_zero(self):
        old = total()
        del old["heardBeforeSeconds"]
        self.assertEqual(rows.rows_in(card(row("a", whole=old)))[0].total.before, 0)

    def test_the_figures_are_right_wrong_and_before(self):
        whole = total(3, ad=120, heard=30, cut=7, before=5)
        found = rows.rows_in(card(row("a", whole=whole)))[0].total
        self.assertEqual((found.episodes, found.right, found.wrong, found.before), (3, 90, 7, 5))

    def test_a_feed_that_comes_twice_in_a_row_is_added_up(self):
        found = rows.rows_in(card(row("a", show(FEED_A, heard=10), show(FEED_A + "/", heard=5))))[0]
        self.assertEqual(len(found.shows), 1)
        self.assertEqual(list(found.shows.values())[0].figures.right, 185)


if __name__ == "__main__":
    unittest.main()
