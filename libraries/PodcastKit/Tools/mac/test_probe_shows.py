"""Tests for probe_shows.py: the pure parts, with no network. Run:
python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import json
import os
import tempfile
import unittest

import probe_shows as probe

FEED = """<?xml version="1.0"?><rss><channel><title>Show</title>
<item><title>Old</title><pubDate>Mon, 01 Jan 2024 10:00:00 +0000</pubDate>
<enclosure url="https://traffic.megaphone.fm/old.mp3" type="audio/mpeg"/></item>
<item><title>New</title><pubDate>Tue, 05 Mar 2024 10:00:00 +0000</pubDate>
<enclosure url="https://dts.podtrac.com/new.mp3" type="audio/mpeg"/></item>
<item><title>No audio</title><pubDate>Wed, 06 Mar 2024 10:00:00 +0000</pubDate></item>
</channel></rss>"""

DIFFERING = """Episode address: https://x/y.mp3
Copy A: User-Agent "a"
  host after redirects: stitcher.example.com   (path: x -> y)
Frames that are byte-identical in both copies, in the same order: 900 (87 %)
Ranges that differ and then join again (candidate inserted ads):
  copy A 0:10 to 0:40 (30.0 s), copy B nothing
  copy A 5:00 to 5:30 (30.0 s), copy B 5:00 to 5:45 (45.0 s)
"""

SAME = """Copy A: User-Agent "a"
  host after redirects: cdn.example.com   (path: x -> y)
The two copies are byte for byte the same: this host gave both listeners the same file.
"""

REENCODED = """  host after redirects: enc.example.com
Frames that are byte-identical in both copies, in the same order: 0 (0 % of the shorter copy)
Ranges that differ and then join again: none.
"""


class PickTests(unittest.TestCase):
    def test_newest_enclosure_uses_the_latest_date_and_skips_items_without_audio(self):
        self.assertEqual(probe.newest_enclosure(FEED), "https://dts.podtrac.com/new.mp3")

    def test_without_dates_the_first_item_is_newest(self):
        feed = ('<rss><channel><item><enclosure url="https://a.example/1.mp3"/></item>'
                '<item><enclosure url="https://a.example/2.mp3"/></item></channel></rss>')
        self.assertEqual(probe.newest_enclosure(feed), "https://a.example/1.mp3")

    def test_bad_feeds_give_none(self):
        self.assertIsNone(probe.newest_enclosure("not xml"))
        self.assertIsNone(probe.newest_enclosure("<rss><channel></channel></rss>"))

    def test_choose_takes_one_per_host_and_prefers_ad_hosts(self):
        items = [
            {"title": "Plain", "address": "https://files.plain.example/a.mp3"},
            {"title": "Plain2", "address": "https://files.plain.example/b.mp3"},
            {"title": "Acast", "address": "https://sphinx.acast.com/a.mp3"},
            {"title": "Mega", "address": "https://traffic.megaphone.fm/a.mp3"},
        ]
        chosen = [c["title"] for c in probe.choose(items)]
        self.assertEqual(chosen, ["Mega", "Acast", "Plain"])

    def test_choose_stops_at_the_limit(self):
        items = [{"title": str(i), "address": "https://h%d.example/a.mp3" % i} for i in range(20)]
        self.assertEqual(len(probe.choose(items)), 8)

    def test_find_candidates_skips_failing_feeds(self):
        def fetch(feed):
            if "bad" in feed:
                raise OSError("down")
            return FEED
        shows = [{"feed": "https://bad.example/f", "title": "Bad"},
                 {"feed": "https://ok.example/f", "title": "Ok"}]
        notes = []
        found = probe.find_candidates(shows, fetch=fetch, pause=0, say=notes.append)
        self.assertEqual([c["title"] for c in found], ["Ok"])
        self.assertEqual(len(notes), 1)

    def test_load_shows_reads_feed_and_title(self):
        with tempfile.TemporaryDirectory() as folder:
            path = os.path.join(folder, "a.json")
            with open(path, "w") as handle:
                json.dump({"shows": [{"feed": "https://f.example/rss", "title": "T"},
                                     {"feed": "", "title": "none"}], "finished": []}, handle)
            self.assertEqual(probe.load_shows(path), [{"feed": "https://f.example/rss", "title": "T"}])


class SummaryTests(unittest.TestCase):
    def test_differing_copies(self):
        info = probe.parse_probe(DIFFERING)
        self.assertEqual((info["host"], info["ranges"], info["matched"], info["percent"]),
                         ("stitcher.example.com", 2, 900, 87))
        line = probe.summary_line("Show", info)
        self.assertIn("differ in 2 ranges", line)
        self.assertIn("share 900 frames (87 %)", line)

    def test_same_bytes(self):
        line = probe.summary_line("Show", probe.parse_probe(SAME))
        self.assertIn("cdn.example.com", line)
        self.assertIn("same bytes", line)

    def test_reencoded(self):
        line = probe.summary_line("Show", probe.parse_probe(REENCODED))
        self.assertIn("share no frames", line)

    def test_failure(self):
        line = probe.summary_line("Show", probe.parse_probe("Copy A did not download: timeout"))
        self.assertIn("FAILED: did not download", line)

    def test_report_joins_outputs_and_ends_with_the_table(self):
        with tempfile.TemporaryDirectory() as folder:
            with open(os.path.join(folder, "picks.tsv"), "w") as handle:
                handle.write("One\thttps://a.example/1.mp3\nTwo\thttps://b.example/2.mp3\n")
            with open(os.path.join(folder, "1.txt"), "w") as handle:
                handle.write(SAME)
            report = probe.build_report(folder)  # 2.txt is missing: a failed probe
        self.assertIn("Summary", report)
        self.assertIn("same bytes", report.split("Summary")[1])
        self.assertIn("FAILED: no result", report.split("Summary")[1])


if __name__ == "__main__":
    unittest.main()
