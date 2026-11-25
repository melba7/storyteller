"""Tests for probe_transcripts.py (the count of publisher transcripts in all followed shows): no
network. Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import os
import tempfile
import unittest

import probe_transcripts as scan

NS = 'xmlns:podcast="https://podcastindex.org/namespace/1.0"'


def feed(items):
    return '<?xml version="1.0"?><rss version="2.0" %s><channel><title>S</title>%s</channel></rss>' % (
        NS, "".join(items))


def item(url=None, kind="text/vtt"):
    tag = '<podcast:transcript url="%s" type="%s"/>' % (url, kind) if url else ""
    return '<item><title>E</title><enclosure url="https://a.example/e.mp3" type="audio/mpeg"/>%s</item>' % tag


class ScanFeedTests(unittest.TestCase):
    def test_counts_items_and_keeps_the_newest_address(self):
        xml = feed([item("https://a.example/new.vtt"), item(), item("https://a.example/old.vtt")])
        found = scan.scan_feed(xml)
        self.assertEqual(found["items"], 3)
        self.assertEqual(found["with"], 2)
        self.assertEqual(found["types"], ["text/vtt"])
        self.assertEqual(found["sample"], "https://a.example/new.vtt")

    def test_a_feed_without_transcripts(self):
        found = scan.scan_feed(feed([item(), item()]))
        self.assertEqual((found["items"], found["with"], found["sample"]), (2, 0, None))

    def test_only_the_newest_ten_items_count(self):
        found = scan.scan_feed(feed([item() for _ in range(12)]))
        self.assertEqual(found["items"], 10)

    def test_an_address_that_is_not_http_is_not_a_sample(self):
        found = scan.scan_feed(feed([item("file:///etc/passwd")]))
        self.assertEqual(found["with"], 1)
        self.assertIsNone(found["sample"])

    def test_a_feed_that_is_not_xml(self):
        found = scan.scan_feed("not xml")
        self.assertEqual((found["items"], found["with"], found["sample"]), (0, 0, None))


class SampleCheckTests(unittest.TestCase):
    def test_counts_words_and_ad_phrases(self):
        text = "WEBVTT\n\n00:00:01.000 --> 00:00:04.000\nThis episode is brought to you by Acme. Use promo code SHOW.\n"
        result = scan.check_sample(text)
        self.assertGreater(result["words"], 8)
        self.assertEqual(result["ad_phrases"], 2)

    def test_plain_talk_has_no_ad_phrase(self):
        self.assertEqual(scan.check_sample("We talked about trains all day.")["ad_phrases"], 0)


class ReportTests(unittest.TestCase):
    def rows(self):
        return [
            {"title": "Alpha", "error": None, "items": 10, "with": 10, "types": ["text/vtt"],
             "sample": "https://a.example/t.vtt", "words": 5000, "ad_phrases": 0},
            {"title": "Beta", "error": None, "items": 10, "with": 0, "types": [], "sample": None},
            {"title": "Gamma", "error": "timed out", "items": 0, "with": 0, "types": [], "sample": None},
        ]

    def test_summary_counts_shows(self):
        text = scan.build_report(self.rows())
        self.assertIn("1 of 2 shows read carry a publisher's transcript", text)
        self.assertIn("1 feed could not be read", text)
        self.assertIn("Alpha", text)
        self.assertIn("text/vtt", text)

    def test_says_when_a_transcript_holds_no_ad_read(self):
        self.assertIn("none of the samples", scan.build_report(self.rows()).lower())

    def test_nothing_read(self):
        self.assertIn("No feed was read", scan.build_report([]))


class CommandTests(unittest.TestCase):
    def test_reads_every_show_and_writes_the_report(self):
        with tempfile.TemporaryDirectory() as folder:
            shows = os.path.join(folder, "shows.json")
            with open(shows, "w", encoding="utf-8") as handle:
                handle.write('{"shows": [{"title": "Alpha", "feed": "https://f.example/a"},'
                             '{"title": "Dead", "feed": "https://f.example/dead"}]}')
            fed = {"https://f.example/a": feed([item("https://t.example/a.vtt")]),
                   "https://t.example/a.vtt": "hello there brought to you by"}

            def fetch(address):
                if address not in fed:
                    raise OSError("refused")
                return fed[address]

            out = os.path.join(folder, "out.txt")
            code = scan.run(shows, out, fetch=fetch, pause=0, say=lambda _: None)
            self.assertEqual(code, 0)
            with open(out, encoding="utf-8") as handle:
                text = handle.read()
            self.assertIn("1 of 1 shows read carry", text)
            self.assertIn("Dead", text)

    def test_a_missing_show_list_is_a_plain_message(self):
        said = []
        code = scan.run("/nonexistent/shows.json", "/nonexistent/out.txt", say=said.append)
        self.assertEqual(code, 2)
        self.assertIn("Sync Apple Podcasts", " ".join(said))


if __name__ == "__main__":
    unittest.main()
