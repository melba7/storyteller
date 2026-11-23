"""Tests for the two newest files of teach_publish.py: the meaning model (published only when the
held-out check AND the scorecard say it helps) and the per-show settings (published when valid).
No network. Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import json
import os
import re
import unittest

import teach_publish as publish
import teach_settings
from test_teach_publish import ENOUGH, Setup, read

ROW = "Plus the meaning model"
BEFORE = "Plus repeated words"
WRITTEN = 1_700_000_000_000  # when the meaning model was trained (milliseconds)
TEACHING_TS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "..",
                           "applications", "mobile", "modules", "podcasts", "teaching.ts")


def meaning(precision=0.9, written=WRITTEN, **held):
    """ad-meaning.json as far as the gate reads it."""
    trained = {"heldOut": dict(ENOUGH, anyAd={"precision": precision}, **held)}
    if written is not None:
        trained["writtenAt"] = written
    return {"version": 1, "language": "en", "trained": trained}


def sorts(host=(0, 0), promo=(0, 0), sponsor=(0, 0)):
    """The per-sort part of a total: each sort as (seconds of it marked, seconds still heard)."""
    named = {"host_ask": host, "network_promo": promo, "sponsor": sponsor, "intro_credits": (0, 0)}
    return {name: {"ads": 1, "caught": 1, "seconds": a, "heardSeconds": b}
            for name, (a, b) in named.items()}


def row(name, right, wrong, per_sort=None):
    """A scorecard row that has `right` right seconds and `wrong` wrong ones (300 s of ads in all)."""
    total = {"episodes": 6, "ads": 5, "caught": 4, "adSeconds": 300.0, "heardSeconds": 300.0 - right,
             "cutSeconds": float(wrong), "bySort": per_sort or sorts()}
    return {"name": name, "total": total, "shows": []}


def card(*rows, at=WRITTEN + 1000):
    """A scorecard: an old run that would pass, then the newest run with `rows`."""
    good = [row(BEFORE, 100, 5, sorts(host=(100, 100))), row(ROW, 150, 8, sorts(host=(100, 60)))]
    return {"version": 1, "runs": [{"at": 1, "title": "old", "total": {}, "rows": good},
                                   {"at": at, "title": "new", "total": {}, "rows": list(rows)}]}


# Before: 100 right seconds, 5 wrong, nothing found of host_ask. With the meaning model: 50 more
# right seconds (40 of them host_ask) and 3 more wrong, a precision of 94 percent.
PASSES = card(row(BEFORE, 100, 5, sorts(host=(100, 100))), row(ROW, 150, 8, sorts(host=(100, 60))))


class MeaningGateTests(Setup):
    def scorecard(self, value):
        with open(os.path.join(self.teaching, "scorecard.json"), "w") as f:
            json.dump(value, f)

    def publish_meaning(self, extra=()):
        self.assertEqual(self.main(self.one, self.two, extra=extra), 0, self.messages)

    def said(self):
        return [m for m in self.messages if m.startswith("ad-meaning.json:")]

    def not_published(self, *words):
        for folder in (self.one, self.two):
            self.assertFalse(os.path.exists(self.published(folder, "ad-meaning.json")))
        said = self.said()
        self.assertEqual(len(said), 1, self.messages)
        self.assertIn("The meaning model was not published", said[0])
        for word in words:
            self.assertIn(word, said[0])

    def test_a_model_that_passes_both_checks_goes_to_every_folder_and_the_list(self):
        self.source("ad-meaning.json", meaning())
        self.scorecard(PASSES)
        self.publish_meaning()
        for folder in (self.one, self.two):
            self.assertEqual(read(self.published(folder, "ad-meaning.json")),
                             read(os.path.join(self.teaching, "ad-meaning.json")))
            self.assertIn("ad-meaning.json",
                          json.loads(read(self.published(folder, "teaching.json")))["files"])

    def test_with_no_scorecard_it_is_not_published_and_says_so(self):
        self.source("ad-meaning.json", meaning())
        self.source("habits.json")
        self.publish_meaning()
        self.not_published("there is no scorecard", "Score the ad skipping")
        self.assertTrue(os.path.exists(self.published(self.one, "show-habits.json")))

    def test_a_scorecard_without_rows_is_not_enough(self):
        self.source("ad-meaning.json", meaning())
        self.scorecard({"version": 1, "runs": [{"at": WRITTEN + 1, "title": "t", "total": {}}]})
        self.publish_meaning()
        self.not_published("no row \"%s\"" % ROW)

    def test_a_scorecard_with_the_other_rows_but_not_this_one_is_not_enough(self):
        self.source("ad-meaning.json", meaning())
        self.scorecard(card(row("Today's ad skipping", 100, 5), row(BEFORE, 110, 5)))
        self.publish_meaning()
        self.not_published("no row \"%s\"" % ROW)

    def test_only_the_newest_run_counts(self):
        self.source("ad-meaning.json", meaning())
        self.scorecard(card(row(BEFORE, 100, 5)))  # the older run in card() would pass
        self.publish_meaning()
        self.not_published("no row")

    def test_a_row_with_nothing_before_it_is_not_enough(self):
        self.source("ad-meaning.json", meaning())
        self.scorecard(card(row(ROW, 150, 8, sorts(host=(100, 60)))))
        self.publish_meaning()
        self.not_published("no row before")

    def test_a_damaged_scorecard_is_not_a_failure_but_the_model_waits(self):
        self.source("ad-meaning.json", meaning())
        with open(os.path.join(self.teaching, "scorecard.json"), "w") as f:
            f.write("{nope")
        self.publish_meaning()
        self.not_published("scorecard could not be used", "not valid JSON")
        self.assertNotIn("Nothing was written", self.said()[0])

    def test_a_row_that_adds_no_right_seconds_is_not_published(self):
        self.source("ad-meaning.json", meaning())
        self.scorecard(card(row(BEFORE, 100, 5, sorts(host=(100, 100))),
                            row(ROW, 100, 5, sorts(host=(100, 100)))))
        self.publish_meaning()
        self.not_published("added no right seconds")

    def test_what_it_adds_must_be_85_percent_right(self):
        self.source("ad-meaning.json", meaning())
        # 50 right seconds more, 20 wrong ones more: 71 percent.
        self.scorecard(card(row(BEFORE, 100, 5, sorts(host=(100, 100))),
                            row(ROW, 150, 25, sorts(host=(100, 60)))))
        self.publish_meaning()
        self.not_published("71.4%", "85%")

    def test_exactly_85_percent_is_enough_and_the_bar_can_be_changed(self):
        self.source("ad-meaning.json", meaning())
        self.scorecard(card(row(BEFORE, 100, 5, sorts(host=(100, 100))),
                            row(ROW, 185, 20, sorts(host=(100, 20)))))  # 85 right, 15 wrong
        self.publish_meaning()
        self.assertTrue(os.path.exists(self.published(self.one, "ad-meaning.json")))
        for folder in (self.one, self.two):
            os.remove(self.published(folder, "ad-meaning.json"))
        self.messages.clear()
        self.scorecard(card(row(BEFORE, 100, 5, sorts(host=(100, 100))),
                            row(ROW, 185, 21, sorts(host=(100, 20)))))  # 85 right, 16 wrong
        self.publish_meaning()
        self.not_published("84.2%")
        self.messages.clear()
        self.publish_meaning(extra=("--min-precision", "0.8"))
        self.assertTrue(os.path.exists(self.published(self.one, "ad-meaning.json")))

    def test_it_must_add_right_seconds_for_host_ask_or_network_promo(self):
        self.source("ad-meaning.json", meaning())
        # More ad seconds are found, but all of them are "sponsor" ones the word model could find.
        self.scorecard(card(row(BEFORE, 100, 5, sorts(sponsor=(200, 150))),
                            row(ROW, 150, 8, sorts(sponsor=(200, 100)))))
        self.publish_meaning()
        self.not_published("host_ask", "network_promo")

    def test_a_gain_in_either_of_the_two_sorts_is_enough(self):
        self.source("ad-meaning.json", meaning())
        self.scorecard(card(row(BEFORE, 100, 5, sorts(promo=(80, 80))),
                            row(ROW, 150, 8, sorts(promo=(80, 30)))))
        self.publish_meaning()
        self.assertTrue(os.path.exists(self.published(self.one, "ad-meaning.json")))

    def test_a_row_with_no_numbers_per_sort_is_not_published(self):
        self.source("ad-meaning.json", meaning())
        plain = card(row(BEFORE, 100, 5), row(ROW, 150, 8))
        for one in plain["runs"][-1]["rows"]:
            del one["total"]["bySort"]
        self.scorecard(plain)
        self.publish_meaning()
        self.not_published("per sort")

    def test_a_scorecard_older_than_the_model_does_not_count(self):
        self.source("ad-meaning.json", meaning(written=WRITTEN))
        self.scorecard(card(row(BEFORE, 100, 5, sorts(host=(100, 100))),
                            row(ROW, 150, 8, sorts(host=(100, 60))), at=WRITTEN - 1))
        self.publish_meaning()
        self.not_published("older than the meaning model", "Score the ad skipping")

    def test_a_model_with_no_time_in_it_is_judged_by_the_scorecard_alone(self):
        self.source("ad-meaning.json", meaning(written=None))
        self.scorecard(PASSES)
        self.publish_meaning()
        self.assertTrue(os.path.exists(self.published(self.one, "ad-meaning.json")))

    def test_a_weak_held_out_check_stops_it_whatever_the_scorecard_says(self):
        self.scorecard(PASSES)
        for value, words in ((meaning(0.7), "70%"), (meaning(episodes=3, shows=2), "has 3 from 2"),
                             (meaning(predictedAdSeconds=100), "600 seconds"),
                             ({"version": 1}, "no precision")):
            self.messages.clear()
            self.source("ad-meaning.json", value)
            self.publish_meaning()
            self.not_published(words)

    def test_both_reasons_are_said_in_one_line(self):
        self.source("ad-meaning.json", meaning(0.5))
        self.publish_meaning()
        self.not_published("precision of 50%", "no scorecard")

    def test_a_copy_already_published_is_left_alone_and_stays_listed(self):
        self.source("ad-meaning.json", meaning())
        self.scorecard(PASSES)
        self.publish_meaning()
        before = read(self.published(self.one, "ad-meaning.json"))
        self.source("ad-meaning.json", dict(meaning(), changed=True))
        self.scorecard(card(row(BEFORE, 100, 5), row(ROW, 100, 5)))
        self.messages.clear()
        self.publish_meaning()
        self.assertEqual(read(self.published(self.one, "ad-meaning.json")), before)
        self.assertEqual(read(self.published(self.two, "ad-meaning.json")), before)
        self.assertEqual(len(self.said()), 1)
        self.assertIn("left as it is", self.said()[0])
        self.assertIn("ad-meaning.json",
                      json.loads(read(self.published(self.one, "teaching.json")))["files"])

    def test_a_meaning_file_that_is_not_json_is_refused_like_the_others(self):
        self.source("ad-meaning.json", raw=b"{nope")
        self.scorecard(PASSES)
        self.assertEqual(self.main(self.one), 2)
        self.assertFalse(os.path.exists(self.published(self.one, "ad-meaning.json")))
        self.assertTrue(any("ad-meaning.json" in m and "not JSON" in m for m in self.messages))

    def test_a_missing_meaning_file_is_skipped_with_one_line(self):
        self.scorecard(PASSES)
        self.publish_meaning()
        said = [m for m in self.messages if "ad-meaning.json" in m]
        self.assertEqual(len(said), 1)
        self.assertIn("skipped", said[0])

    def test_the_row_name_is_the_one_the_settings_tool_knows(self):
        self.assertEqual(teach_settings.ROWS[ROW], "meaning")


class SettingsTests(Setup):
    GOOD = {"version": 1, "writtenAt": 1700000000, "default": {"joints": True}, "shows": []}

    def test_a_valid_settings_file_is_published_with_no_other_gate(self):
        self.source("show-settings.json", self.GOOD)
        self.assertEqual(self.main(self.one, self.two), 0, self.messages)
        for folder in (self.one, self.two):
            self.assertEqual(read(self.published(folder, "show-settings.json")),
                             read(os.path.join(self.teaching, "show-settings.json")))
            self.assertIn("show-settings.json",
                          json.loads(read(self.published(folder, "teaching.json")))["files"])

    def test_it_needs_no_scorecard_and_no_held_out_check(self):
        self.source("show-settings.json", {"version": 1, "shows": []})
        self.assertEqual(self.main(self.one), 0)
        self.assertTrue(os.path.exists(self.published(self.one, "show-settings.json")))

    def test_what_the_phone_would_refuse_is_not_published_and_says_why(self):
        for value in ({"version": 1}, {"version": 1, "shows": {"a": 1}}, {"version": 1, "shows": "x"}):
            self.messages.clear()
            self.source("show-settings.json", value)
            self.assertEqual(self.main(self.one), 2, value)
            self.assertFalse(os.path.exists(self.published(self.one, "show-settings.json")))
            self.assertTrue(any("show-settings.json" in m and "list of shows" in m
                                for m in self.messages), self.messages)

    def test_a_file_that_is_not_version_1_is_refused_like_the_others(self):
        self.source("show-settings.json", {"version": 2, "shows": []})
        self.assertEqual(self.main(self.one), 2)
        self.assertFalse(os.path.exists(self.published(self.one, "show-settings.json")))

    def test_a_refused_file_leaves_the_old_published_one(self):
        self.source("show-settings.json", self.GOOD)
        self.main(self.one)
        before = read(self.published(self.one, "show-settings.json"))
        self.source("show-settings.json", raw=b"[]")
        self.assertEqual(self.main(self.one), 2)
        self.assertEqual(read(self.published(self.one, "show-settings.json")), before)

    def test_a_missing_settings_file_is_skipped_with_one_line(self):
        self.assertEqual(self.main(self.one), 0)
        said = [m for m in self.messages if "show-settings.json" in m]
        self.assertEqual(len(said), 1)
        self.assertIn("skipped", said[0])


class NamesTests(unittest.TestCase):
    def test_the_files_published_are_the_files_the_phone_fetches(self):
        with open(TEACHING_TS, encoding="utf-8") as f:
            text = f.read()
        block = re.search(r"export const TEACHING_NAMES = \[(.*?)\] as const", text, re.S).group(1)
        fetched = re.findall(r'"([^"]+)"', block)
        self.assertEqual(fetched, [target for _, target in publish.FILES])
        self.assertEqual(len(fetched), 6)


if __name__ == "__main__":
    unittest.main()
