"""Tests for teach_settings.py: a finder whose row is under 85 percent right only asks (and is off when
it is more wrong than right). Made scorecards, no files.
Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import unittest

from teach_settings_testing import FEED_A, FEED_B, MEANING, OWN, SOUNDS, WORDS, choose, rows_of, row, show


def run(finder, on_a, on_b, episodes_a=3):
    """What `choose` makes of a finder that adds (right, wrong) seconds on show A and on show B, each
    of them 1000 s of ads that were all heard before."""
    def shown(feed, episodes, right=0, wrong=0):
        return show(feed, "Show " + feed[8].upper(), episodes=episodes, ad=1000, heard=1000 - right, cut=wrong)
    base = row("Phone", shown(FEED_A, episodes_a), shown(FEED_B, 3))
    added = row(finder, shown(FEED_A, episodes_a, *on_a), shown(FEED_B, 3, *on_b))
    return choose(rows_of(base, added))


class OverallTests(unittest.TestCase):
    def test_a_finder_under_85_percent_right_over_all_shows_asks_by_default(self):
        default, shows, lines = run(OWN, (30, 20), (30, 20))
        self.assertEqual(default["finders"]["own-sound"], "ask")
        self.assertEqual(shows, [], "each show is the same as the default")
        self.assertTrue(any("own-sound" in line and "every show" in line and "85" in line for line in lines), lines)

    def test_exactly_85_percent_is_not_demoted_and_849_is(self):
        self.assertEqual(run(OWN, (85, 15), (85, 15))[0]["finders"]["own-sound"], "skip")
        self.assertEqual(run(OWN, (849, 151), (849, 151))[0]["finders"]["own-sound"], "ask")
        self.assertEqual(run(OWN, (851, 149), (851, 149))[0]["finders"]["own-sound"], "skip")

    def test_the_meaning_model_is_judged_the_same_way(self):
        default, _, _ = run(MEANING, (30, 20), (30, 20))
        self.assertEqual((default["finders"]["meaning"], default["finders"]["own-sound"]), ("ask", "skip"))

    def test_more_wrong_than_right_is_still_off_and_not_just_ask(self):
        self.assertEqual(run(OWN, (40, 60), (40, 60))[0]["finders"]["own-sound"], "off")
        self.assertEqual(run(OWN, (50, 50), (50, 50))[0]["finders"]["own-sound"], "ask")

    def test_a_finder_that_asks_by_default_stays_as_it_is(self):
        for name, what in ((SOUNDS, "repeat-sound"), (WORDS, "repeat-words")):
            default, shows, lines = run(name, (30, 20), (30, 20))
            self.assertEqual(default["finders"][what], "ask")
            self.assertEqual((shows, lines), ([], []))

    def test_a_finder_that_adds_nothing_is_not_judged(self):
        default, shows, lines = run(OWN, (0, 0), (0, 0))
        self.assertEqual((default["finders"]["own-sound"], shows, lines), ("skip", [], []))

    def test_three_marked_episodes_are_needed_over_all_shows_too(self):
        base = row("Phone", show(FEED_A, episodes=2, ad=1000, heard=1000))
        added = row(OWN, show(FEED_A, episodes=2, ad=1000, heard=970, cut=20))
        self.assertEqual(choose(rows_of(base, added))[0]["finders"]["own-sound"], "skip")


class PerShowTests(unittest.TestCase):
    def test_a_show_under_85_percent_right_gets_its_own_ask(self):
        # A: 60 right, 40 wrong. B: 940 right, none wrong. Over all shows 96 percent: skip stays.
        default, shows, lines = run(OWN, (60, 40), (940, 0))
        self.assertEqual(default["finders"]["own-sound"], "skip")
        self.assertEqual(shows, [{"feed": FEED_A, "finders": {"own-sound": "ask"}}])
        self.assertTrue(any("Show A" in line and "own-sound" in line for line in lines), lines)

    def test_a_show_at_exactly_85_percent_is_not_demoted_and_at_849_is(self):
        self.assertEqual(run(OWN, (85, 15), (940, 0))[1], [])
        self.assertEqual(run(OWN, (849, 151), (940, 0))[1], [{"feed": FEED_A, "finders": {"own-sound": "ask"}}])

    def test_a_show_with_fewer_than_three_marked_episodes_is_not_judged(self):
        self.assertEqual(run(OWN, (60, 40), (940, 0), episodes_a=2)[1], [])

    def test_a_show_whose_default_already_asks_gets_no_entry(self):
        self.assertEqual(run(WORDS, (60, 40), (940, 0))[1], [])


if __name__ == "__main__":
    unittest.main()
