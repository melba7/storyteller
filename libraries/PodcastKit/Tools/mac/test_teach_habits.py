"""Tests for teach_habits.py: ad blocks, the opening rule, the medians per show, damaged labels and
the written file. No network.
Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import json
import os
import shutil
import tempfile
import unittest

import teach_habits as habits
from teach_testing import entry


def span(start, end, sort="sponsor", confidence="high"):
    return {"first": 1, "last": 1, "start": start, "end": end, "sort": sort, "who": "",
            "delivery": "host", "confidence": confidence, "why": ""}


def label(episode, feed, *segments, show="Show"):
    return {"version": 1, "episode": episode, "feed": feed, "show": show,
            "segments": list(segments)}


class BlockTests(unittest.TestCase):
    def test_only_high_and_medium_sponsors_and_promos_count(self):
        facts = habits.facts_of(label("a", "f", span(0, 10, confidence="low"),
                                      span(20, 30, sort="host_ask"),
                                      span(40, 50, sort="intro_credits"),
                                      span(60, 70, sort="network_promo", confidence="medium"),
                                      span(200, 210)))
        self.assertEqual(facts["blocks"], [(60, 70), (200, 210)])

    def test_blocks_join_within_twenty_seconds(self):
        facts = habits.facts_of(label("a", "f", span(100, 130), span(150, 160), span(180.1, 190)))
        self.assertEqual(facts["blocks"], [(100, 160), (180.1, 190)])

    def test_segments_in_any_order(self):
        facts = habits.facts_of(label("a", "f", span(150, 160), span(100, 130)))
        self.assertEqual(facts["blocks"], [(100, 160)])

    def test_opening_within_ninety_seconds(self):
        self.assertTrue(habits.facts_of(label("a", "f", span(90, 120)))["opens"])
        self.assertFalse(habits.facts_of(label("a", "f", span(90.1, 120)))["opens"])
        facts = habits.facts_of(label("a", "f", span(5, 30), span(40, 60), span(500, 520)))
        self.assertEqual(facts["opening"], (5, 60))
        self.assertEqual(len(facts["blocks"]), 2)

    def test_only_the_first_block_can_be_the_opening(self):
        facts = habits.facts_of(label("a", "f", span(200, 220), span(300, 310)))
        self.assertFalse(facts["opens"])
        self.assertIsNone(facts["opening"])

    def test_ad_seconds_add_up_the_ads(self):
        facts = habits.facts_of(label("a", "f", span(0, 30), span(100, 160)))
        self.assertEqual(facts["ad_seconds"], 90)


class MedianTests(unittest.TestCase):
    def test_odd_even_and_empty(self):
        self.assertEqual(habits.median([3, 1, 2]), 2)
        self.assertEqual(habits.median([4, 1, 2, 3]), 2.5)
        self.assertIsNone(habits.median([]))


class SummaryTests(unittest.TestCase):
    def test_per_show_numbers(self):
        labels = [label("1", "feedA", span(10, 40), span(600, 660)),
                  label("2", "feedA", span(500, 530)),
                  label("3", "feedA", span(20, 50), span(300, 330), span(900, 960)),
                  label("4", "feedA", span(0, 20)),
                  label("5", "feedB")]
        shows = habits.summarize(labels, {"feedA": "Show A"})
        a = [s for s in shows if s["feed"] == "feedA"][0]
        self.assertEqual((a["title"], a["episodes"], a["opensWithAd"]), ("Show A", 4, 3))
        self.assertEqual((a["openingStarts"], a["openingEnds"]), (10, 40))
        self.assertEqual(a["breaks"], 1.5)
        self.assertEqual(a["adSeconds"], 60)

    def test_a_show_with_no_openings_has_nulls(self):
        shows = habits.summarize([label("1", "f", span(500, 530)), label("2", "f")], {})
        self.assertEqual((shows[0]["opensWithAd"], shows[0]["openingStarts"],
                          shows[0]["openingEnds"]), (0, None, None))
        self.assertEqual((shows[0]["breaks"], shows[0]["adSeconds"]), (0.5, 15))

    def test_title_falls_back_to_the_labels_show(self):
        shows = habits.summarize([label("1", "f", show="From label")], {})
        self.assertEqual(shows[0]["title"], "From label")

    def test_shows_that_open_with_an_ad_most_often_come_first(self):
        labels = [label("1", "rare", span(500, 520)), label("2", "often", span(5, 20)),
                  label("3", "often", span(900, 920))]
        self.assertEqual([s["feed"] for s in habits.summarize(labels, {})], ["often", "rare"])


class MainTests(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp()
        self.addCleanup(lambda: shutil.rmtree(self.dir, ignore_errors=True))
        self.said = []

    def episodes(self, content=None):
        data = content if content is not None else {
            "version": 1, "episodes": [entry(0xaaaaaaaaaaaa, feed="feedA", show="Show A", title="t")]}
        with open(os.path.join(self.dir, "episodes.json"), "w") as f:
            f.write(data if isinstance(data, str) else json.dumps(data))

    def put(self, name, value, labels="labels"):
        os.makedirs(os.path.join(self.dir, labels), exist_ok=True)
        with open(os.path.join(self.dir, labels, name), "w") as f:
            f.write(value if isinstance(value, str) else json.dumps(value))

    def main(self, *options):
        return habits.main(["--folder", self.dir] + list(options), say=self.said.append)

    def test_writes_habits_and_prints_a_table(self):
        self.episodes()
        self.put("aaaaaaaaaaaa.json", label("aaaaaaaaaaaa", "feedA", span(5, 30)))
        self.assertEqual(self.main(), 0)
        with open(os.path.join(self.dir, "habits.json")) as f:
            written = json.load(f)
        self.assertEqual(written["version"], 1)
        self.assertIsInstance(written["writtenAt"], int)
        self.assertEqual(list(written["shows"][0]),
                         ["feed", "title", "episodes", "opensWithAd", "openingStarts",
                          "openingEnds", "breaks", "adSeconds"])
        self.assertEqual(written["shows"][0]["title"], "Show A")
        self.assertTrue(any("Show A" in line and "1 of 1" in line for line in self.said))
        self.assertEqual([n for n in os.listdir(self.dir) if n.endswith(".part")], [])

    def test_damaged_labels_are_skipped_with_one_line(self):
        self.episodes()
        self.put("good.json", label("good", "feedA", span(5, 30)))
        self.put("broken.json", "{nope")
        self.put("shape.json", {"version": 1, "feed": "f", "segments": "no"})
        self.put("segment.json", {"version": 1, "feed": "f", "segments": [{"start": "x"}]})
        self.put("list.json", [1])
        self.put("notes.txt", "ignored")
        self.assertEqual(self.main(), 0)
        self.assertEqual(len([s for s in self.said if "Skipping" in s]), 4)
        with open(os.path.join(self.dir, "habits.json")) as f:
            self.assertEqual(json.load(f)["shows"][0]["episodes"], 1)

    def test_no_labels_yet_is_fine(self):
        self.episodes()
        self.assertEqual(self.main(), 0)
        self.assertTrue(any("No labels yet" in line for line in self.said))
        self.assertFalse(os.path.exists(os.path.join(self.dir, "habits.json")))

    def test_another_labels_folder(self):
        self.episodes()
        self.put("a.json", label("a", "feedA", span(5, 30)), labels="other")
        self.assertEqual(self.main("--labels", "other"), 0)
        self.assertTrue(os.path.exists(os.path.join(self.dir, "habits.json")))

    def test_set_up_problems_are_exit_two(self):
        self.assertEqual(self.main(), 2)
        self.assertIn("Run the gather step first", self.said[-1])
        self.episodes("not json")
        self.assertEqual(self.main(), 2)

    def test_an_episode_list_with_short_entries_is_refused(self):
        self.episodes({"version": 1, "episodes": [{"id": "aaaaaaaaaaaa", "feed": "feedA",
                                                   "show": "Show A", "title": "t"}]})
        self.assertEqual(self.main(), 2)


if __name__ == "__main__":
    unittest.main()
