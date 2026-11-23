"""Tests for the exam options of teach_collect.py (--exam, --exam-most): only episodes newer than
everything gathered before, the exam list written first, the wanted list ignored, --list.
No network and no real sleeping. Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import json
import os
import tempfile
import unittest

import teach_collect as tc
import teach_exam
from teach_testing import dated, feed
from test_teach_collect import SHOWS, feeds_for, fetcher
from test_teach_collect_wanted import want


def bigger_feeds():
    """Seven episodes per show, day 1 to 7; the first run takes the newest three (days 5 to 7)."""
    return feeds_for(per_show=7)


class ExamCollectTests(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.dir.cleanup)
        self.folder = os.path.join(self.dir.name, "teach")
        self.lines = []
        self.downloaded = []

    def download(self, address, path, **more):
        self.downloaded.append(address)
        with open(path, "wb") as handle:
            handle.write(b"x" * 100)
        return {"bytes": 100, "sha256": "ab" * 32, "host": "cdn.example.com"}

    def collect(self, feeds, per_show, download=None, **more):
        return tc.collect(self.folder, SHOWS, per_show, 10**9, 0, fetch=fetcher(feeds),
                          download=download or self.download, free_space=lambda path: 10**12,
                          sleep=lambda seconds: None, say=self.lines.append, **more)

    def titles(self):
        return [e["title"] for e in tc.load_manifest(self.folder)]

    def gather_before(self, days=5):
        """A normal run first: the feeds have `days` episodes, the folder holds the newest three of
        every show, so older ones are still unknown."""
        feeds = {s["feed"]: feed(*[dated("%s%d" % (s["feed"][-1], n), n,
                                         "https://cdn/%s%d.mp3" % (s["feed"][-1], n))
                                   for n in range(1, days + 1)]) for s in SHOWS}
        self.collect(feeds, 3)
        self.downloaded.clear()

    def test_only_episodes_newer_than_everything_gathered_are_taken(self):
        self.gather_before()
        result = self.collect(bigger_feeds(), 7, exam=True)
        self.assertEqual(result["downloaded"], 6)
        exam = teach_exam.read_exam(self.folder)
        names = {e["id"]: e["title"] for e in tc.load_manifest(self.folder)}
        self.assertEqual([names[i] for i in exam], ["a7", "b7", "c7", "a6", "b6", "c6"])
        self.assertNotIn("a2", self.titles())  # older than a5: not an exam episode, not gathered

    def test_exam_most_keeps_the_round_robin_order_and_counts_what_is_in_the_exam(self):
        self.gather_before()
        self.collect(bigger_feeds(), 7, exam=True, exam_most=4)
        names = {e["id"]: e["title"] for e in tc.load_manifest(self.folder)}
        self.assertEqual([names[i] for i in teach_exam.read_exam(self.folder)],
                         ["a7", "b7", "c7", "a6"])
        self.collect(bigger_feeds(), 7, exam=True, exam_most=4)  # nothing more fits
        self.assertEqual(len(teach_exam.read_exam(self.folder)), 4)

    def test_a_second_exam_run_tops_up_to_the_most(self):
        self.gather_before()
        self.collect(bigger_feeds(), 7, exam=True, exam_most=2)
        feeds = feeds_for(per_show=9)
        self.collect(feeds, 9, exam=True, exam_most=5)
        self.assertEqual(len(teach_exam.read_exam(self.folder)), 5)

    def test_an_episode_with_no_published_time_is_not_taken(self):
        feeds = {s["feed"]: feed({"title": "undated", "address": "https://cdn/%s.mp3" % s["title"]},
                                 dated("dated", 3, "https://cdn/d%s.mp3" % s["title"]))
                 for s in SHOWS}
        self.collect(feeds, 2, exam=True)
        self.assertEqual(self.titles(), ["dated"] * 3)

    def test_the_first_run_in_an_empty_folder_takes_every_dated_episode(self):
        self.collect(feeds_for(), 2, exam=True)
        self.assertEqual(len(teach_exam.read_exam(self.folder)), 6)

    def test_the_exam_list_exists_before_episodes_json_is_saved_and_before_any_download(self):
        self.gather_before()
        seen = []
        real_save = tc.save_manifest

        def saving(folder, entries):
            seen.append(("save", teach_exam.read_exam(folder)))
            real_save(folder, entries)

        def stopping(address, path, **more):
            seen.append(("download", teach_exam.read_exam(self.folder)))
            raise KeyboardInterrupt

        tc.save_manifest = saving
        try:
            with self.assertRaises(KeyboardInterrupt):
                self.collect(bigger_feeds(), 7, download=stopping, exam=True)
        finally:
            tc.save_manifest = real_save
        self.assertEqual(len(seen[0][1]), 6)
        self.assertEqual(seen[0][0], "save")
        self.assertEqual(len(seen[-1][1]), 6)
        # The run stopped half way, yet every exam episode is on the list.
        self.assertEqual({e["id"] for e in tc.load_manifest(self.folder)} & set(
            teach_exam.read_exam(self.folder)), set(teach_exam.read_exam(self.folder)))

    def waiting_from_before(self):
        """A normal run whose downloads all failed: nine episodes (days 3 to 5) wait for audio."""
        def failing(address, path, **more):
            raise OSError("no network")

        tc.collect(self.folder, SHOWS, 3, 10**9, 0, fetch=fetcher(feeds_for(per_show=5)),
                   download=failing, free_space=lambda path: 10**12, sleep=lambda s: None,
                   say=self.lines.append)

    def test_an_exam_run_downloads_the_exam_episodes_first_even_when_others_wait(self):
        self.waiting_from_before()
        tc.collect(self.folder, SHOWS, 7, 10**9, 0, fetch=fetcher(feeds_for(per_show=7)),
                   download=self.download, free_space=lambda path: 10**12, sleep=lambda s: None,
                   say=self.lines.append, exam=True, exam_most=3)
        self.assertEqual(self.downloaded[:3], ["https://cdn/a7.mp3", "https://cdn/b7.mp3",
                                               "https://cdn/c7.mp3"])
        self.assertEqual(len(self.downloaded), 12)  # the ones that waited follow, the size allowing

    def test_the_size_limit_is_used_on_the_exam_episodes_before_the_ones_that_waited(self):
        self.waiting_from_before()
        result = tc.collect(self.folder, SHOWS, 7, 300, 0, fetch=fetcher(feeds_for(per_show=7)),
                            download=self.download, free_space=lambda path: 10**12,
                            sleep=lambda s: None, say=self.lines.append, exam=True, exam_most=3)
        self.assertEqual((result["downloaded"], result["why"], result["waiting"]), (3, "size", 9))
        with_audio = {e["title"] for e in tc.load_manifest(self.folder) if e["file"]}
        self.assertEqual(with_audio, {"a7", "b7", "c7"})

    def test_a_normal_run_still_downloads_in_list_order(self):
        self.waiting_from_before()
        tc.collect(self.folder, SHOWS, 7, 10**9, 0, fetch=fetcher(feeds_for(per_show=7)),
                   download=self.download, free_space=lambda path: 10**12, sleep=lambda s: None,
                   say=self.lines.append)
        self.assertEqual(self.downloaded[:3], ["https://cdn/a5.mp3", "https://cdn/b5.mp3", "https://cdn/c5.mp3"])

    def test_the_wanted_list_is_ignored_for_an_exam_run(self):
        self.collect(feeds_for(per_show=5), 1)  # a5, b5 and c5 are gathered
        old = want("https://f/a", "", "https://cdn/a1.mp3")
        self.collect(feeds_for(per_show=5), 1, exam=True, wanted=[old])
        self.assertNotIn("a1", self.titles())
        self.collect(feeds_for(per_show=5), 1, wanted=[old])  # a normal run does take it
        self.assertIn("a1", self.titles())

    def test_a_normal_run_does_not_touch_the_exam(self):
        self.collect(feeds_for(), 2)
        self.assertFalse(os.path.exists(os.path.join(self.folder, "exam.json")))


class ExamCommandTests(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.dir.cleanup)
        self.folder = os.path.join(self.dir.name, "teach")
        self.shows = os.path.join(self.dir.name, "shows.json")
        with open(self.shows, "w", encoding="utf-8") as handle:
            json.dump({"shows": SHOWS}, handle)
        self.lines = []

    def main(self, *extra, download=None):
        return tc.main(["--folder", self.folder, "--shows", self.shows] + list(extra),
                       fetch=fetcher(feeds_for(per_show=5)), sleep=lambda s: None,
                       download=download or (lambda a, p, **m: self.fail("no download")),
                       say=self.lines.append)

    def test_list_with_exam_says_how_many_exam_episodes_a_run_would_take(self):
        self.assertEqual(self.main("--list", "--exam", "--per-show", "2", "--exam-most", "4"), 0)
        self.assertTrue(any("would take 4 exam episodes" in line for line in self.lines), self.lines)
        self.assertFalse(os.path.exists(self.folder))

    def test_list_without_exam_is_unchanged(self):
        self.assertEqual(self.main("--list"), 0)
        self.assertFalse(any("exam" in line for line in self.lines))

    def test_exam_most_must_be_a_whole_number_above_zero(self):
        for bad in ("0", "-3", "x"):
            with self.assertRaises(SystemExit):
                self.main("--exam", "--exam-most", bad)

    def test_a_damaged_exam_file_stops_the_run_with_exit_2(self):
        os.makedirs(self.folder)
        with open(os.path.join(self.folder, "exam.json"), "w") as f:
            f.write("nope")
        self.assertEqual(self.main("--exam"), 2)
        self.assertFalse(os.path.exists(os.path.join(self.folder, "episodes.json")))

    def test_the_closing_lines_say_how_many_went_into_the_exam(self):
        code = self.main("--exam", "--per-show", "1", "--max-gb", "0")
        self.assertEqual(code, tc.SIZE_LIMIT)  # nothing may be downloaded, yet the list is kept
        self.assertTrue(any("3 new episodes were put in the exam (3 in all)" in line
                            for line in self.lines), self.lines)
        self.assertEqual(len(teach_exam.read_exam(self.folder)), 3)


if __name__ == "__main__":
    unittest.main()
