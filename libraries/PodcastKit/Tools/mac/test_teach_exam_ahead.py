"""Tests for the "newer than everything gathered" rule of the exam when the nightly read-ahead has
put episodes in the teaching set (teach_exam.pick_new, and teach_collect.py --exam): an episode that
was read ahead counts like any other with a published time, and one that has no time blocks the
exam for its feed, so the exam can never take an episode that came out before an episode the model
was taught on. No network. Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import os
import tempfile
import unittest
from email.utils import parsedate_to_datetime

import teach_collect as tc
import teach_exam
from teach_ahead_set import add_ahead
from teach_testing import dated, entry, feed
from test_teach_collect import SHOWS, feeds_for, fetcher


def day(number):
    """The published time (seconds) that `dated` gives an episode of day `number`."""
    return int(parsedate_to_datetime("Mon, %02d Jan 2024 10:00:00 +0000" % number).timestamp())


class PickNewTests(unittest.TestCase):
    A, B = "https://f/a", "https://f/b"

    def planned(self, *spec):
        return [entry(n, feed=f, published=when) for n, f, when in spec]

    def ids(self, picked):
        return [e["id"] for e in picked]

    def test_an_ahead_episode_with_a_time_counts_like_any_other_entry(self):
        known = [entry(1, feed=self.A, published=day(6))]
        planned = self.planned((2, self.A, day(6)), (3, self.A, day(7)), (4, self.B, day(2)))
        picked = teach_exam.pick_new(known, planned, [], 10, ahead={known[0]["id"]})
        self.assertEqual(self.ids(picked), [planned[1]["id"], planned[2]["id"]])

    def test_an_ahead_episode_with_no_time_blocks_the_exam_for_its_feed_only(self):
        known = [entry(1, feed=self.A, published=None)]
        planned = self.planned((2, self.A, day(7)), (3, self.B, day(7)))
        picked = teach_exam.pick_new(known, planned, [], 10, ahead={known[0]["id"]})
        self.assertEqual(self.ids(picked), [planned[1]["id"]])

    def test_another_spelling_of_the_same_feed_is_blocked_too(self):
        known = [entry(1, feed="http://www.f/a/", published=None)]
        planned = self.planned((2, "https://f/a", day(7)))
        self.assertEqual(teach_exam.pick_new(known, planned, [], 10, ahead={known[0]["id"]}), [])

    def test_an_entry_with_no_time_that_was_not_read_ahead_blocks_nothing(self):
        # As before: only the nightly read-ahead's episodes are known to be taught on without a time.
        known = [entry(1, feed=self.A, published=None)]
        planned = self.planned((2, self.A, day(7)))
        self.assertEqual(self.ids(teach_exam.pick_new(known, planned, [], 10)), [planned[0]["id"]])
        self.assertEqual(self.ids(teach_exam.pick_new(known, planned, [], 10, ahead={"x" * 12})),
                         [planned[0]["id"]])

    def test_the_newest_time_of_the_feed_wins_whichever_entry_it_comes_from(self):
        known = [entry(1, feed=self.A, published=day(3)), entry(2, feed=self.A, published=day(5))]
        planned = self.planned((3, self.A, day(4)), (4, self.A, day(6)))
        picked = teach_exam.pick_new(known, planned, [], 10, ahead={known[1]["id"]})
        self.assertEqual(self.ids(picked), [planned[1]["id"]])


class ExamRunTests(unittest.TestCase):
    """The same rule through teach_collect.py's exam run: episodes.json and ahead.json on disk."""

    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.dir.cleanup)
        self.folder = os.path.join(self.dir.name, "teach")
        self.lines = []

    def download(self, address, path, **more):
        with open(path, "wb") as handle:
            handle.write(b"x" * 100)
        return {"bytes": 100, "sha256": "ab" * 32, "host": "cdn.example.com"}

    def collect(self, feeds, per_show, **more):
        return tc.collect(self.folder, SHOWS, per_show, 10**9, 0, fetch=fetcher(feeds),
                          download=self.download, free_space=lambda path: 10**12,
                          sleep=lambda seconds: None, say=self.lines.append, **more)

    def gather_before(self):
        """A normal run: each feed has days 1 to 5 and the newest three (3 to 5) are gathered."""
        feeds = {s["feed"]: feed(*[dated("%s%d" % (s["feed"][-1], n), n,
                                         "https://cdn/%s%d.mp3" % (s["feed"][-1], n))
                                   for n in range(1, 6)]) for s in SHOWS}
        self.collect(feeds, 3)

    def read_ahead(self, published):
        """Puts an episode of show A that the nightly read-ahead picked in the teaching set."""
        mine = tc.new_entry("A", "https://f/a", {"guid": "ahead-guid", "title": "ahead",
                            "published": published, "seconds": None, "address": "https://cdn/ahead.mp3",
                            "size": None})
        tc.save_manifest(self.folder, tc.load_manifest(self.folder) + [mine])
        add_ahead(self.folder, [{"id": mine["id"], "feed": "https://f/a", "guid": "ahead-guid",
                                 "title": "ahead", "picked": 1}])

    def exam_titles(self):
        names = {e["id"]: e["title"] for e in tc.load_manifest(self.folder)}
        return [names[i] for i in teach_exam.read_exam(self.folder)]

    def test_the_exam_takes_only_episodes_newer_than_a_read_ahead_one_with_a_time(self):
        self.gather_before()
        self.read_ahead(day(6))
        self.collect(feeds_for(per_show=7), 7, exam=True)
        # a6 is not newer than the ahead episode of day 6, so show A gives only a7.
        self.assertEqual(self.exam_titles(), ["a7", "b7", "c7", "b6", "c6"])

    def test_a_read_ahead_episode_with_no_time_keeps_its_feed_out_of_the_exam(self):
        self.gather_before()
        self.read_ahead(None)
        self.collect(feeds_for(per_show=7), 7, exam=True)
        self.assertEqual(self.exam_titles(), ["b7", "c7", "b6", "c6"])


if __name__ == "__main__":
    unittest.main()
