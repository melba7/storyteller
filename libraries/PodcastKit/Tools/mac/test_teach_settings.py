"""Tests for teach_settings.py: choosing each finder's level on each show from a made scorecard and
made notes. No files, no network. The joints are in test_teach_settings_joints.py, the reading of
the rows in test_teach_settings_rows.py, the command and the file it writes in
test_teach_settings_main.py.
Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import unittest

from teach_settings_testing import (
    DAY, FEED_A, FEED_B, MEANING, NOW, OWN, SOUNDS, WORDS, choose, entry, note, rows_of, row, show)


class DefaultTests(unittest.TestCase):
    def test_the_default_block_is_the_one_the_plan_ships(self):
        default, shows, _ = choose([])
        self.assertEqual(default, {
            "finders": {"own-sound": "skip", "repeat-sound": "ask", "repeat-words": "ask",
                        "meaning": "skip"}, "joints": True, "steadyJoints": False, "ask": 0.35})
        self.assertEqual(shows, [])

    def test_a_finder_that_has_no_row_keeps_its_default(self):
        base = row("The phone's finders", show(FEED_A, heard=40))
        default, shows, _ = choose(rows_of(base))
        self.assertEqual(default["finders"]["meaning"], "skip")
        self.assertEqual(shows, [])

    def test_a_clearly_bad_finder_is_off_everywhere_in_the_default_block(self):
        base = row("Phone", show(FEED_A, heard=40), show(FEED_B, heard=40))
        bad = row(WORDS, show(FEED_A, heard=39, cut=30), show(FEED_B, heard=39, cut=30))
        default, _, lines = choose(rows_of(base, bad))
        self.assertEqual(default["finders"]["repeat-words"], "off")
        self.assertEqual(default["finders"]["own-sound"], "skip")
        self.assertTrue(any("repeat-words" in line and "every show" in line for line in lines), lines)

    def test_a_finder_that_is_wrong_a_little_less_than_right_only_asks(self):
        base = row("Phone", show(FEED_A, heard=40))
        fine = row(OWN, show(FEED_A, heard=20, cut=19))
        default, shows, _ = choose(rows_of(base, fine))
        self.assertEqual(default["finders"]["own-sound"], "ask", "under 85 percent right, not off")
        self.assertEqual(shows, [])

    def test_a_finder_that_found_nothing_and_cut_almost_nothing_is_not_judged(self):
        # The sound and repeat finders learn from a show's earlier episodes, so a test over one unseen
        # episode of each show cannot show their gain. Nothing found and 15 s cut of 60000 s of show
        # (a fortieth of a percent) says nothing, so the finder keeps its level.
        base = row("Phone", show(FEED_A, heard=40, show_seconds=30000.0), show(FEED_B, heard=40, show_seconds=30000.0))
        quiet = row(OWN, show(FEED_A, heard=40, cut=10, show_seconds=30000.0),
                    show(FEED_B, heard=40, cut=5, show_seconds=30000.0))
        default, shows, lines = choose(rows_of(base, quiet))
        self.assertEqual(default["finders"]["own-sound"], "skip")
        self.assertEqual(shows, [])
        self.assertTrue(any("own-sound" in line and "too little to judge" in line for line in lines), lines)

    def test_a_finder_that_found_nothing_but_cut_more_of_the_show_is_still_off(self):
        # 40 s of 60000 s is over 0.05 percent: that is judged, and more wrong than right is off.
        base = row("Phone", show(FEED_A, heard=40, show_seconds=30000.0), show(FEED_B, heard=40, show_seconds=30000.0))
        loud = row(OWN, show(FEED_A, heard=40, cut=25, show_seconds=30000.0),
                   show(FEED_B, heard=40, cut=15, show_seconds=30000.0))
        self.assertEqual(choose(rows_of(base, loud))[0]["finders"]["own-sound"], "off")

    def test_the_overall_row_needs_three_marked_episodes_too(self):
        base = row("Phone", show(FEED_A, episodes=2, heard=40))
        bad = row(OWN, show(FEED_A, episodes=2, heard=40, cut=50))
        default, _, _ = choose(rows_of(base, bad))
        self.assertEqual(default["finders"]["own-sound"], "skip")


class ScorecardRuleTests(unittest.TestCase):
    def base(self):
        # B has 1000 s of ads, so a finder can gain a lot there and not be bad over all shows.
        return row("Phone", show(FEED_A, "Show A", heard=40, cut=5),
                   show(FEED_B, "Show B", ad=1000, heard=900, cut=5))

    def test_more_wrong_than_right_seconds_on_a_show_makes_the_finder_ask_there(self):
        # On A the finder gains 2 right seconds and 10 wrong ones; on B 200 right and none wrong.
        added = row(OWN, show(FEED_A, "Show A", heard=38, cut=15),
                    show(FEED_B, "Show B", ad=1000, heard=700, cut=5))
        default, shows, lines = choose(rows_of(self.base(), added))
        self.assertEqual(default["finders"]["own-sound"], "skip")
        self.assertEqual(shows, [{"feed": FEED_A, "finders": {"own-sound": "ask"}}])
        self.assertTrue(any("Show A" in line and "own-sound" in line for line in lines), lines)
        self.assertFalse(any("Show B" in line for line in lines), lines)

    def test_as_many_wrong_as_right_seconds_is_not_more_so_it_asks_and_is_not_off(self):
        # Over all shows the finder adds 10 right and 10 wrong seconds (50 percent right).
        even = row(OWN, show(FEED_A, heard=30, cut=15), show(FEED_B, ad=1000, heard=900, cut=5))
        default, shows, _ = choose(rows_of(self.base(), even))
        self.assertEqual((default["finders"]["own-sound"], shows), ("ask", []))
        # One wrong second more and it is off.
        more = row(OWN, show(FEED_A, heard=30, cut=16), show(FEED_B, ad=1000, heard=900, cut=5))
        self.assertEqual(choose(rows_of(self.base(), more))[0]["finders"]["own-sound"], "off")

    def test_a_row_that_loses_right_seconds_without_adding_wrong_ones_is_worse(self):
        # The row after hears 5 s more of the ads than the row before (it can happen to joints that
        # move a border), and cuts nothing more. On B it gains.
        lost = row(OWN, show(FEED_A, heard=45, cut=5), show(FEED_B, ad=1000, heard=0, cut=5))
        self.assertEqual(choose(rows_of(self.base(), lost))[1], [{"feed": FEED_A, "finders": {"own-sound": "ask"}}])

    def test_a_finder_that_only_adds_right_seconds_changes_nothing(self):
        added = row(OWN, show(FEED_A, heard=0, cut=5), show(FEED_B, ad=1000, heard=0, cut=5))
        self.assertEqual(choose(rows_of(self.base(), added))[1], [])

    def test_the_rows_are_cumulative_so_a_finder_is_judged_on_what_it_added(self):
        # The row before already holds 50 s of show cut by mistake. The next row's raw wrong
        # seconds (51) are above its raw right seconds (40), but the finder added 30 right
        # seconds against 1 wrong one: fine.
        before = row("Phone", show(FEED_A, heard=90, cut=50), show(FEED_B, heard=90, cut=50))
        added = row(OWN, show(FEED_A, heard=60, cut=51), show(FEED_B, heard=60, cut=51))
        self.assertEqual(choose(rows_of(before, added))[1], [])
        # The other way round. On A the raw right seconds (90) are far above the raw wrong ones
        # (20), but the finder added 5 right seconds against 20 wrong ones. B gained a lot, so the
        # row is not bad over all shows.
        before = row("Phone", show(FEED_A, heard=15), show(FEED_B, ad=1000, heard=900))
        added = row(OWN, show(FEED_A, heard=10, cut=20), show(FEED_B, ad=1000, heard=10))
        default, shows, _ = choose(rows_of(before, added))
        self.assertEqual(default["finders"]["own-sound"], "skip")
        self.assertEqual(shows, [{"feed": FEED_A, "finders": {"own-sound": "ask"}}])

    def test_each_finder_stands_on_the_row_before_it(self):
        rows = rows_of(
            row("Phone", show(FEED_A, heard=50), show(FEED_B, ad=1000, heard=990)),
            row(OWN, show(FEED_A, heard=40), show(FEED_B, ad=1000, heard=980)),  # +10 right each
            row(SOUNDS, show(FEED_A, heard=40, cut=3), show(FEED_B, ad=1000, heard=960, cut=3)),  # A: 0 right, 3 wrong
            row(WORDS, show(FEED_A, heard=30, cut=3), show(FEED_B, ad=1000, heard=950, cut=3)),  # +10 right each
            row(MEANING, show(FEED_A, heard=30, cut=40), show(FEED_B, ad=1000, heard=5, cut=3)))  # A: 37 wrong
        default, shows, _ = choose(rows)
        self.assertEqual(default["finders"], {"own-sound": "skip", "repeat-sound": "ask",
                                              "repeat-words": "ask", "meaning": "skip"})
        # repeat-sound is bad on A but already asks by default, so only the meaning model is written.
        self.assertEqual(shows, [{"feed": FEED_A, "finders": {"meaning": "ask"}}])

    def test_fewer_than_three_marked_episodes_change_nothing_for_that_show(self):
        base = row("Phone", show(FEED_A, episodes=2, heard=40), show(FEED_B, ad=1000, heard=900))
        bad = row(OWN, show(FEED_A, episodes=2, heard=40, cut=30), show(FEED_B, ad=1000, heard=0))
        notes = [note("undone", "own-sound"), note("undone", "own-sound"),
                 note("denied", "own-sound"), note("denied", "own-sound")]
        self.assertEqual(choose(rows_of(base, bad), notes)[1], [])

    def test_three_marked_episodes_are_enough(self):
        base = row("Phone", show(FEED_A, episodes=3, heard=40), show(FEED_B, ad=1000, heard=900))
        bad = row(OWN, show(FEED_A, episodes=3, heard=40, cut=30), show(FEED_B, ad=1000, heard=0))
        self.assertEqual(choose(rows_of(base, bad))[1], [{"feed": FEED_A, "finders": {"own-sound": "ask"}}])

    def test_a_show_that_is_missing_from_the_row_before_is_not_judged(self):
        base = row("Phone", show(FEED_B, ad=1000, heard=900))
        bad = row(OWN, show(FEED_A, heard=40, cut=30), show(FEED_B, ad=1000, heard=0))
        self.assertEqual(choose(rows_of(base, bad))[1], [])

    def test_a_row_with_no_row_before_it_is_not_judged(self):
        first = row(OWN, show(FEED_A, heard=40, cut=50))
        default, shows, _ = choose(rows_of(first))
        self.assertEqual((default["finders"]["own-sound"], shows), ("skip", []))

    def test_a_feed_spelt_two_ways_is_one_show(self):
        spelt = "http://www.A.example/feed/"
        base = row("Phone", show(spelt, heard=40), show(FEED_B, ad=1000, heard=900))
        bad = row(OWN, show(spelt, heard=40, cut=30), show(FEED_B, ad=1000, heard=0))
        notes = [note("undone", "meaning", feed="https://a.example/feed")] * 2
        shows = choose(rows_of(base, bad), notes)[1]
        self.assertEqual(shows, [{"feed": spelt, "finders": {"meaning": "ask", "own-sound": "ask"}}])


class NoteRuleTests(unittest.TestCase):
    def rows(self):
        return rows_of(row("Phone", show(FEED_A, "Show A", heard=40)),
                       row(OWN, show(FEED_A, "Show A", heard=30)))

    def chosen(self, *notes, now=NOW):
        entry_a = entry(choose(self.rows(), notes, now)[1], FEED_A)
        return entry_a and entry_a.get("finders")

    def test_two_undone_skips_of_one_finder_on_a_show_make_it_ask(self):
        self.assertEqual(self.chosen(note("undone", "own-sound"), note("undone", "own-sound")),
                         {"own-sound": "ask"})

    def test_one_undone_skip_changes_nothing(self):
        self.assertIsNone(self.chosen(note("undone", "own-sound")))

    def test_undone_skips_of_two_different_finders_do_not_add_up(self):
        self.assertIsNone(self.chosen(note("undone", "own-sound"), note("undone", "meaning")))

    def test_notes_of_another_show_do_not_count(self):
        self.assertIsNone(self.chosen(note("undone", "own-sound", feed=FEED_B),
                                      note("undone", "own-sound", feed=FEED_B)))

    def test_a_note_without_a_finder_or_with_an_unknown_one_is_ignored(self):
        plain = note("undone", "own-sound")
        del plain["by"]
        self.assertIsNone(self.chosen(plain, plain, note("undone", "tap"), note("undone", "tap"),
                                      note("undone", ["own-sound"])))

    def test_notes_older_than_thirty_days_are_ignored(self):
        old = note("undone", "own-sound", at=NOW - 31 * DAY)
        self.assertIsNone(self.chosen(old, old, note("undone", "own-sound")))
        self.assertEqual(self.chosen(note("undone", "own-sound", at=NOW - 30 * DAY),
                                     note("undone", "own-sound")), {"own-sound": "ask"})

    def test_two_denied_answers_of_the_last_five_switch_the_finder_off_there(self):
        self.assertEqual(self.chosen(note("denied", "meaning", at=NOW - 2 * DAY),
                                     note("denied", "meaning")), {"meaning": "off"})

    def test_only_the_last_five_answers_count(self):
        denied = [note("denied", "meaning", at=NOW - 9 * DAY), note("denied", "meaning", at=NOW - 8 * DAY)]
        yes = [note("confirmed", "meaning", at=NOW - (7 - i) * DAY) for i in range(4)]
        # Six answers: the last five hold one "not an ad", so it stays as it is.
        self.assertIsNone(self.chosen(*denied, *yes))
        # With three "yes" answers, all five are the last five and hold two "not an ad".
        self.assertEqual(self.chosen(*denied, *yes[:3]), {"meaning": "off"})

    def test_the_notes_may_come_in_any_order(self):
        newest = note("confirmed", "meaning", at=NOW - DAY)
        older = [note("denied", "meaning", at=NOW - (8 + i) * DAY) for i in range(2)]
        self.assertEqual(self.chosen(newest, *older), {"meaning": "off"})
        self.assertEqual(self.chosen(*older, newest), {"meaning": "off"})
        # Four "yes" answers since push the two denied ones out of the last five.
        since = [note("confirmed", "meaning", at=NOW - i * DAY - 1000) for i in range(1, 5)]
        self.assertIsNone(self.chosen(*older, *since))
        self.assertIsNone(self.chosen(*since, *older))

    def test_off_comes_before_ask(self):
        self.assertEqual(
            self.chosen(note("undone", "meaning"), note("undone", "meaning"),
                        note("denied", "meaning"), note("denied", "meaning")), {"meaning": "off"})

    def test_a_show_with_no_row_in_the_scorecard_is_not_touched_by_its_notes(self):
        notes = [note("undone", "own-sound", feed=FEED_B)] * 2
        self.assertEqual(choose(self.rows(), notes)[1], [])

    def test_a_finder_that_is_already_as_strict_by_default_is_not_written_again(self):
        # repeat-sound asks by default, so two undone skips add nothing; two denied answers do.
        self.assertIsNone(self.chosen(*[note("undone", "repeat-sound")] * 2))
        self.assertEqual(self.chosen(*[note("denied", "repeat-sound")] * 2), {"repeat-sound": "off"})

    def test_the_scorecard_and_the_notes_together_take_the_stricter_level(self):
        base = row("Phone", show(FEED_A, heard=40), show(FEED_B, ad=1000, heard=900))
        bad = row(OWN, show(FEED_A, heard=40, cut=30), show(FEED_B, ad=1000, heard=0))
        notes = [note("denied", "own-sound")] * 2
        self.assertEqual(choose(rows_of(base, bad), notes)[1],
                         [{"feed": FEED_A, "finders": {"own-sound": "off"}}])

    def test_a_finder_that_is_off_everywhere_needs_no_entry(self):
        base = row("Phone", show(FEED_A, heard=40))
        bad = row(OWN, show(FEED_A, heard=40, cut=50))
        default, shows, _ = choose(rows_of(base, bad), [note("denied", "own-sound")] * 2)
        self.assertEqual((default["finders"]["own-sound"], shows), ("off", []))


if __name__ == "__main__":
    unittest.main()
