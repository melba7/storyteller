"""Tests for teach_settings.py and Apple's on-device model: it is one more finder, "apple-model", that
asks by default. A show gets "skip" only when the scorecard's what-if row (every Apple answer skipping)
passes at least 3 more breaks on that show than the last finder row and adds at most 1 skip with no
ad. No files, no network.
Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import unittest

import teach_settings_rows as reading
from teach_settings_testing import (
    APPLE, APPLE_ALL, DAY, FEED_A, FEED_B, NOW, OWN, bar, card, choose, entry, note, row, rows_of, show)

SKIPPING = {"apple-model": "skip"}


def three(last, phone, what_if):
    """The last finder row, the phone's Apple row and the what-if row, each made of shows."""
    return rows_of(row("Plus per-show settings", *last), row(APPLE, *phone), row(APPLE_ALL, *what_if))


def gains(more, skips, base=(10, 4)):
    """Rows where the what-if row's show passes `more` more breaks and adds `skips` more skips with no
    ad than the row before it (which stands for the phone's Apple row too: Apple asks by default)."""
    plain = [show(FEED_A, "Show A", bar=bar(*base))]
    return three(plain, plain, [show(FEED_A, "Show A", bar=bar(base[0] + more, base[1] + skips))])


class DefaultTests(unittest.TestCase):
    def test_apple_asks_in_the_default_block(self):
        self.assertEqual(choose([])[0]["finders"]["apple-model"], "ask")
        self.assertEqual(choose(gains(5, 0))[0]["finders"]["apple-model"], "ask", "never raised for every show")

    def test_no_rows_for_apple_leave_it_asking_everywhere(self):
        default, shows, lines = choose(rows_of(row("Plus per-show settings", show(FEED_A, bar=bar(10, 4)))))
        self.assertEqual(default["finders"]["apple-model"], "ask")
        self.assertEqual(shows, [])
        self.assertFalse(any("apple-model" in line for line in lines), lines)


class BarTests(unittest.TestCase):
    def test_three_more_breaks_and_one_more_skip_with_no_ad_let_the_show_skip(self):
        default, shows, lines = choose(gains(3, 1))
        self.assertEqual(shows, [{"feed": FEED_A, "finders": SKIPPING}])
        self.assertEqual(default["finders"]["apple-model"], "ask")
        said = [line for line in lines if "Show A" in line and "apple-model" in line]
        self.assertEqual(len(said), 1, lines)
        self.assertIn("3 more", said[0])
        self.assertIn("+1", said[0])

    def test_two_more_breaks_are_not_enough_so_the_show_keeps_asking(self):
        self.assertEqual(choose(gains(2, 0))[1], [])

    def test_two_more_skips_with_no_ad_are_too_many(self):
        self.assertEqual(choose(gains(9, 2))[1], [])

    def test_fewer_skips_with_no_ad_and_many_more_breaks_are_fine(self):
        self.assertEqual(choose(gains(6, -1))[1], [{"feed": FEED_A, "finders": SKIPPING}])

    def test_each_show_is_judged_by_its_own_bar(self):
        plain = [show(FEED_A, "Show A", bar=bar(10, 4)), show(FEED_B, "Show B", bar=bar(10, 4))]
        both = [show(FEED_A, "Show A", bar=bar(14, 4)), show(FEED_B, "Show B", bar=bar(11, 4))]
        self.assertEqual(choose(three(plain, plain, both))[1], [{"feed": FEED_A, "finders": SKIPPING}])

    def test_the_comparison_is_with_the_last_finder_row_not_with_the_phones_apple_row(self):
        # The run that made the card already let the show skip: the phone's Apple row has the gain
        # in it. The what-if row is still judged against the row before that one.
        plain = [show(FEED_A, "Show A", bar=bar(10, 4))]
        skipping = [show(FEED_A, "Show A", bar=bar(14, 4))]
        self.assertEqual(choose(three(plain, skipping, skipping))[1], [{"feed": FEED_A, "finders": SKIPPING}])
        # And where the what-if row has no gain over the finders, the phone's row does not give one.
        self.assertEqual(choose(three(plain, skipping, plain))[1], [])

    def test_a_show_with_no_bar_or_no_breaks_keeps_asking(self):
        plain = [show(FEED_A, "Show A", bar=bar(10, 4))]
        self.assertEqual(choose(three(plain, plain, [show(FEED_A, "Show A")]))[1], [])
        self.assertEqual(choose(three([show(FEED_A, "Show A")], plain, plain))[1], [])
        self.assertEqual(choose(three(plain, plain, [show(FEED_A, "Show A", bar=bar(15, 4, breaks=0))]))[1], [])

    def test_a_show_missing_from_a_row_keeps_asking(self):
        plain = [show(FEED_A, "Show A", bar=bar(10, 4))]
        self.assertEqual(choose(three(plain, plain, [show(FEED_B, "Show B", bar=bar(20, 4))]))[1], [])

    def test_a_show_with_fewer_than_three_marked_episodes_gets_nothing_of_its_own(self):
        plain = [show(FEED_A, "Show A", episodes=2, bar=bar(10, 4))]
        better = [show(FEED_A, "Show A", episodes=2, bar=bar(20, 4))]
        self.assertEqual(choose(three(plain, plain, better))[1], [])

    def test_the_seconds_do_not_judge_apple(self):
        # The what-if row cuts a lot of show by mistake, by the seconds: the bar is what counts, and
        # the default block and the other finders' levels are not changed by it.
        plain = [show(FEED_A, "Show A", ad=500, heard=300, cut=10, bar=bar(10, 4))]
        loud = [show(FEED_A, "Show A", ad=500, heard=100, cut=400, bar=bar(15, 5))]
        default, shows, _ = choose(three(plain, plain, loud))
        self.assertEqual(default["finders"], {
            "apple-model": "ask", "own-sound": "skip", "repeat-sound": "ask", "repeat-words": "ask",
            "meaning": "skip"})
        self.assertEqual(shows, [{"feed": FEED_A, "finders": SKIPPING}])

    def test_a_show_keeps_its_other_finder_changes_beside_apple(self):
        def shows(a_heard, a_cut, b_heard, passed):
            return [show(FEED_A, "Show A", heard=a_heard, cut=a_cut, bar=bar(passed, 4)),
                    show(FEED_B, "Show B", ad=1000, heard=b_heard, cut=5, bar=bar(10, 4))]
        rows = rows_of(row("Plus per-show settings", *shows(40, 5, 900, 10)),
                       row(OWN, *shows(38, 15, 700, 10)),
                       row(APPLE, *shows(38, 15, 700, 10)),
                       row(APPLE_ALL, *shows(38, 15, 700, 15)))
        self.assertEqual(choose(rows)[1], [
            {"feed": FEED_A, "finders": {"apple-model": "skip", "own-sound": "ask"}}])


class NotesTests(unittest.TestCase):
    def test_two_undone_apple_skips_keep_the_show_asking_whatever_the_bar_says(self):
        notes = [note("undone", "apple-model"), note("undone", "apple-model", at=NOW - 2 * DAY)]
        default, shows, _ = choose(gains(6, 0), notes)
        self.assertEqual(shows, [])
        self.assertEqual(default["finders"]["apple-model"], "ask")

    def test_two_not_an_ad_answers_turn_apple_off_on_that_show(self):
        notes = [note("denied", "apple-model"), note("denied", "apple-model", at=NOW - 2 * DAY)]
        self.assertEqual(choose(gains(6, 0), notes)[1], [{"feed": FEED_A, "finders": {"apple-model": "off"}}])

    def test_notes_alone_can_turn_apple_off_where_the_scorecard_says_nothing(self):
        plain = [show(FEED_A, "Show A", bar=bar(10, 4))]
        notes = [note("denied", "apple-model"), note("denied", "apple-model", at=NOW - 2 * DAY)]
        shows = choose(rows_of(row("Plus per-show settings", *plain)), notes)[1]
        self.assertEqual(entry(shows, FEED_A), {"feed": FEED_A, "finders": {"apple-model": "off"}})

    def test_answers_about_another_finder_do_not_count_for_apple(self):
        notes = [note("denied", "meaning"), note("denied", "meaning", at=NOW - 2 * DAY)]
        shows = choose(gains(6, 0), notes)[1]
        self.assertEqual(entry(shows, FEED_A)["finders"], {"apple-model": "skip", "meaning": "off"})


class ReadingTests(unittest.TestCase):
    def test_a_show_keeps_its_own_bar(self):
        found = reading.rows_in(card(row("a", show(FEED_A, bar=bar(7, 2, breaks=9)))))[0]
        self.assertEqual(list(found.shows.values())[0].bar, reading.Bar(9, 7, 2))

    def test_a_show_without_a_bar_or_with_a_bad_one_has_none(self):
        bad = show(FEED_A)
        bad["bar"] = {"breaks": 9, "passed": "x", "noAdSkips": 2}
        found = reading.rows_in(card(row("a", show(FEED_B), bad)))[0]
        self.assertEqual([each.bar for each in found.shows.values()], [None, None])

    def test_a_feed_that_comes_twice_has_its_bars_added_up(self):
        twice = row("a", show(FEED_A, bar=bar(7, 2, breaks=9)), show(FEED_A + "/", bar=bar(1, 1, breaks=3)))
        self.assertEqual(list(reading.rows_in(card(twice))[0].shows.values())[0].bar, reading.Bar(12, 8, 3))
        one_missing = row("a", show(FEED_A, bar=bar(7, 2, breaks=9)), show(FEED_A + "/"))
        self.assertIsNone(list(reading.rows_in(card(one_missing))[0].shows.values())[0].bar)


if __name__ == "__main__":
    unittest.main()
