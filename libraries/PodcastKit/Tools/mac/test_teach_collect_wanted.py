"""Tests for the wanted list in teach_collect.py (wanted.json from teach_feedback.py): wanted
episodes are planned first, looked up by guid or audio address, and left out with a plain line when
they are gone. No network and no real sleeping.
Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import json
import os
import tempfile
import unittest

import teach_collect as tc
import teach_wanted
from teach_testing import dated, feed
from test_teach_collect import SHOWS, feeds_for, fetcher

A, B, OTHER = "https://f/a", "https://f/b", "https://elsewhere/feed"


def want(feed_address, guid="", address="", title="Wanted"):
    return {"feed": feed_address, "guid": guid, "title": title, "address": address,
            "missed": 1, "undone": 0, "last": 1}


class FeedsWithGuids:
    """Feeds in which every episode has a guid: g<show><n>."""

    def __init__(self):
        self.feeds = {}
        for show in SHOWS:
            name = show["feed"][-1]
            self.feeds[show["feed"]] = feed(*[
                dated("%s%d" % (name, n), n, "https://cdn/%s%d.mp3" % (name, n), guid="g%s%d" % (name, n))
                for n in range(1, 4)])
        self.feeds[OTHER] = feed(dated("far1", 1, "https://far/1.mp3", guid="gfar1"),
                                 dated("far2", 2, "https://far/2.mp3", guid="gfar2"))


class PlanWantedTests(unittest.TestCase):
    def plan(self, wanted, feeds=None, per_show=1, known=(), most=20, lines=None, naps=None):
        feeds = feeds if feeds is not None else FeedsWithGuids().feeds
        return tc.plan(SHOWS, set(known), per_show, fetcher(feeds), 1.0,
                       (naps if naps is not None else []).append,
                       (lines if lines is not None else []).append, None, wanted=wanted,
                       wanted_most=most)

    def test_wanted_episodes_come_before_the_newest_ones_whatever_per_show_says(self):
        titles = [e["title"] for e in self.plan([want(B, "gb1"), want(A, "ga2")])]
        self.assertEqual(titles, ["b1", "a2", "a3", "b3", "c3"])

    def test_a_wanted_episode_without_a_guid_is_found_by_its_audio_address(self):
        feeds = feeds_for()  # no guids in these feeds, so the entries have empty guids
        entries = self.plan([want(A, "", "https://cdn/a1.mp3")], feeds=feeds)
        self.assertEqual(entries[0]["title"], "a1")
        self.assertEqual(entries[0]["address"], "https://cdn/a1.mp3")

    def test_an_episode_with_the_guid_is_not_confused_with_another_address(self):
        entries = self.plan([want(A, "ga1", "https://cdn/b3.mp3")])
        self.assertEqual(entries[0]["title"], "a1")

    def test_the_entry_has_the_normal_shape_and_the_followed_shows_name(self):
        entry = self.plan([want(A, "ga1")])[0]
        self.assertEqual((entry["show"], entry["feed"], entry["guid"]), ("A", A, "ga1"))
        self.assertEqual(entry["id"], tc.episode_id(A, "ga1", "https://cdn/a1.mp3"))
        tc.check_entry(entry)

    def test_a_feed_that_is_not_followed_is_fetched_too_and_named_by_itself(self):
        feeds = FeedsWithGuids().feeds
        asked = []
        plain = fetcher(feeds)

        def counting(address):
            asked.append(address)
            return plain(address)

        entries = tc.plan(SHOWS, set(), 1, counting, 0, lambda s: None, lambda m: None, None,
                          wanted=[want(OTHER, "gfar1"), want(OTHER, "gfar2")], wanted_most=20)
        self.assertEqual([e["title"] for e in entries[:2]], ["far1", "far2"])
        self.assertEqual(entries[0]["show"], "Show")  # the feed's own title, from teach_testing.feed
        self.assertEqual(sorted(asked), sorted([s["feed"] for s in SHOWS] + [OTHER]))
        tc.check_entry(entries[0])

    def test_a_followed_feed_is_fetched_only_once(self):
        feeds = FeedsWithGuids().feeds
        asked = []
        plain = fetcher(feeds)

        def counting(address):
            asked.append(address)
            return plain(address)

        tc.plan(SHOWS, set(), 1, counting, 0, lambda s: None, lambda m: None, None,
                wanted=[want(A, "ga1"), want(A, "ga2")], wanted_most=20)
        self.assertEqual(asked.count(A), 1)

    def test_an_episode_that_is_gone_is_skipped_with_one_plain_line(self):
        lines = []
        entries = self.plan([want(A, "gone", title="Old news")], lines=lines)
        self.assertEqual([e["title"] for e in entries], ["a3", "b3", "c3"])
        self.assertEqual(len(lines), 1)
        self.assertIn("Old news", lines[0])
        self.assertIn("no longer in its feed", lines[0])

    def test_an_episode_already_gathered_is_skipped_quietly(self):
        known = [tc.episode_id(A, "ga2", "https://cdn/a2.mp3")]
        lines = []
        entries = self.plan([want(A, "ga2")], known=known, lines=lines)
        self.assertEqual([e["title"] for e in entries], ["a3", "b3", "c3"])
        self.assertEqual(lines, [])

    def test_an_episode_wanted_twice_or_also_the_newest_is_planned_once(self):
        entries = self.plan([want(A, "ga3"), want(A, "ga3")])
        self.assertEqual([e["title"] for e in entries], ["a3", "b3", "c3"])

    def test_at_most_that_many_are_planned(self):
        wanted = [want(A, "ga1"), want(A, "ga2"), want(B, "gb1")]
        titles = [e["title"] for e in self.plan(wanted, most=2)]
        self.assertEqual(titles[:2], ["a1", "a2"])
        self.assertNotIn("b1", titles)

    def test_skipped_ones_do_not_use_up_the_limit(self):
        wanted = [want(A, "gone"), want(A, "ga1"), want(A, "ga2")]
        titles = [e["title"] for e in self.plan(wanted, most=2)]
        self.assertEqual(titles[:2], ["a1", "a2"])

    def test_a_wanted_feed_that_cannot_be_read_is_said_and_the_rest_goes_on(self):
        feeds = FeedsWithGuids().feeds
        feeds[OTHER] = None
        lines = []
        entries = self.plan([want(OTHER, "gfar1", title="Far one"), want(A, "ga1")], feeds=feeds,
                            lines=lines)
        self.assertEqual(entries[0]["title"], "a1")
        self.assertEqual(len(lines), 1)
        self.assertIn("Far one", lines[0])
        self.assertIn("could not be read", lines[0])

    def test_without_wanted_the_plan_is_as_before(self):
        self.assertEqual([e["title"] for e in self.plan([])], ["a3", "b3", "c3"])

    def test_the_pause_also_comes_between_the_extra_feeds(self):
        naps = []
        self.plan([want(OTHER, "gfar1")], naps=naps)
        self.assertEqual(naps, [1.0, 1.0, 1.0])


class LoadWantedTests(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.dir.cleanup)
        self.lines = []

    def write(self, value=None, raw=None):
        with open(os.path.join(self.dir.name, "wanted.json"), "w", encoding="utf-8") as f:
            f.write(raw if raw is not None else json.dumps(value))

    def load(self):
        return teach_wanted.load_wanted(self.dir.name, self.lines.append)

    def test_no_file_means_nothing_wanted_and_no_line(self):
        self.assertEqual(self.load(), [])
        self.assertEqual(self.lines, [])

    def test_a_good_file_gives_its_episodes_in_order(self):
        self.write({"version": 1, "writtenAt": 1, "episodes": [want(A, "x"), want(B, "", "https://b/1.mp3")]})
        self.assertEqual([w["feed"] for w in self.load()], [A, B])
        self.assertEqual(self.lines, [])

    def test_a_damaged_file_is_ignored_with_one_line(self):
        for raw in ("{nope", "[]", json.dumps({"version": 2, "episodes": []}),
                    json.dumps({"version": 1, "episodes": "no"})):
            self.lines.clear()
            self.write(raw=raw)
            self.assertEqual(self.load(), [], raw)
            self.assertEqual(len(self.lines), 1, raw)
            self.assertIn("wanted.json", self.lines[0])
            self.assertIn("ignored", self.lines[0])

    def test_an_entry_that_cannot_be_used_is_left_out(self):
        good = want(A, "x")
        self.write({"version": 1, "episodes": [5, {"feed": 3}, dict(good, guid=None),
                                               dict(good, guid="", address=""), good]})
        self.assertEqual(self.load(), [good])

    def test_an_unreadable_file_is_ignored_with_one_line(self):
        os.makedirs(os.path.join(self.dir.name, "wanted.json"))
        self.assertEqual(self.load(), [])
        self.assertEqual(len(self.lines), 1)


class CollectWantedTests(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.dir.cleanup)
        self.folder = os.path.join(self.dir.name, "teach")
        self.shows = os.path.join(self.dir.name, "shows.json")
        with open(self.shows, "w", encoding="utf-8") as handle:
            json.dump({"shows": SHOWS[:1]}, handle)
        self.feeds = FeedsWithGuids().feeds
        self.downloaded = []
        self.lines = []

    def download(self, address, path, **more):
        self.downloaded.append(address)
        with open(path, "wb") as handle:
            handle.write(b"x")
        return {"bytes": 1, "sha256": "ab" * 32, "host": "cdn"}

    def wanted(self, *episodes):
        os.makedirs(self.folder, exist_ok=True)
        with open(os.path.join(self.folder, "wanted.json"), "w", encoding="utf-8") as f:
            json.dump({"version": 1, "writtenAt": 1, "episodes": list(episodes)}, f)

    def run_main(self, *extra):
        return tc.main(["--folder", self.folder, "--shows", self.shows, "--per-show", "1"]
                       + list(extra), fetch=fetcher(self.feeds), download=self.download,
                       sleep=lambda s: None, say=self.lines.append)

    def test_the_wanted_episodes_are_downloaded_first_and_added_to_the_list(self):
        self.wanted(want(A, "ga1"), want(OTHER, "gfar2"))
        self.assertEqual(self.run_main(), 0, self.lines)
        self.assertEqual(self.downloaded, ["https://cdn/a1.mp3", "https://far/2.mp3", "https://cdn/a3.mp3"])
        with open(os.path.join(self.folder, "episodes.json"), encoding="utf-8") as f:
            data = json.load(f)
        self.assertEqual(set(data), {"version", "writtenAt", "episodes"})
        self.assertEqual(len(data["episodes"]), 3)

    def test_the_wanted_option_limits_them(self):
        self.wanted(want(A, "ga1"), want(A, "ga2"))
        self.run_main("--wanted", "1")
        self.assertEqual(self.downloaded, ["https://cdn/a1.mp3", "https://cdn/a3.mp3"])

    def test_the_default_is_20(self):
        self.feeds[OTHER] = feed(*[dated("far%d" % n, n % 28 + 1, "https://far/%d.mp3" % n,
                                         guid="gfar%d" % n) for n in range(30)])
        self.wanted(*[want(OTHER, "gfar%d" % n) for n in range(30)])
        self.run_main("--list")
        self.assertTrue(any("21 episodes" in line for line in self.lines), self.lines)

    def test_a_damaged_wanted_file_is_ignored_with_one_line_and_the_run_goes_on(self):
        os.makedirs(self.folder)
        with open(os.path.join(self.folder, "wanted.json"), "w") as f:
            f.write("{nope")
        self.assertEqual(self.run_main(), 0)
        self.assertEqual(self.downloaded, ["https://cdn/a3.mp3"])
        self.assertEqual(len([line for line in self.lines if "wanted.json" in line]), 1)

    def test_a_bad_wanted_option_is_refused(self):
        with self.assertRaises(SystemExit):
            self.run_main("--wanted", "many")


if __name__ == "__main__":
    unittest.main()
