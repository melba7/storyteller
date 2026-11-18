"""Tests for the transcript count in probe_shows.py: no network. Run:
python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import os
import tempfile
import unittest

import probe_shows as probe

NS = 'xmlns:podcast="https://podcastindex.org/namespace/1.0"'
OLD_NS = 'xmlns:podcast="https://github.com/Podcastindex-org/podcast-namespace/blob/main/docs/1.0.md"'


def feed(items, namespace=NS):
    body = "".join(items)
    return '<?xml version="1.0"?><rss version="2.0" %s><channel><title>S</title>%s</channel></rss>' % (
        namespace, body)


def item(transcripts=(), audio="https://a.example/e.mp3"):
    tags = "".join('<podcast:transcript url="https://a.example/t" type="%s"/>' % kind
                   for kind in transcripts)
    return '<item><title>E</title><enclosure url="%s" type="audio/mpeg"/>%s</item>' % (audio, tags)


class TranscriptTypesTests(unittest.TestCase):
    def test_reads_each_type_once_from_the_items(self):
        xml = feed([item(["text/vtt", "application/json"]), item(["TEXT/VTT"])])
        self.assertEqual(probe.transcript_types(xml), ["application/json", "text/vtt"])

    def test_a_feed_without_transcripts_has_none(self):
        self.assertEqual(probe.transcript_types(feed([item(), item()])), [])

    def test_the_older_namespace_counts_too(self):
        self.assertEqual(probe.transcript_types(feed([item(["text/plain"])], OLD_NS)), ["text/plain"])

    def test_a_transcript_tag_of_another_namespace_does_not_count(self):
        xml = ('<rss xmlns:x="https://example.com/ns"><channel><item>'
               '<x:transcript type="text/vtt"/></item></channel></rss>')
        self.assertEqual(probe.transcript_types(xml), [])

    def test_a_missing_type_is_unknown(self):
        xml = feed(['<item><podcast:transcript url="https://a.example/t"/></item>'])
        self.assertEqual(probe.transcript_types(xml), ["unknown"])

    def test_only_the_newest_ten_items_are_read(self):
        items = [item() for _ in range(probe.TRANSCRIPT_ITEMS)] + [item(["text/vtt"])]
        self.assertEqual(probe.transcript_types(feed(items)), [])

    def test_a_feed_that_is_not_xml_has_none(self):
        self.assertEqual(probe.transcript_types("not xml"), [])


class TranscriptSummaryTests(unittest.TestCase):
    def test_counts_shows_and_types(self):
        found = {"A": ["text/vtt"], "B": ["application/json", "text/vtt"], "C": [], "D": []}
        text = probe.transcript_summary(found)
        self.assertIn("2 of 4 shows", text)
        self.assertIn("text/vtt 2", text)
        self.assertIn("application/json 1", text)
        self.assertIn("A, B", text)

    def test_says_when_the_idea_is_not_worth_building(self):
        text = probe.transcript_summary({"A": ["text/vtt"], "B": [], "C": []})
        self.assertIn("1 of 3 shows", text)
        self.assertIn("fewer than 3", text)

    def test_says_when_it_is_worth_building(self):
        found = {name: ["text/vtt"] for name in "ABC"}
        self.assertNotIn("fewer than 3", probe.transcript_summary(found))

    def test_no_feeds_read_is_said_plainly(self):
        self.assertIn("No feed was read", probe.transcript_summary({}))


class PickAndReportTests(unittest.TestCase):
    def test_find_candidates_fills_the_transcripts_of_each_feed_read(self):
        feeds = {
            "https://a.example/feed": feed([item(["text/vtt"], "https://x.example/a.mp3")]),
            "https://b.example/feed": feed([item([], "https://y.example/b.mp3")]),
        }
        shows = [{"feed": address, "title": "Show " + address[8]} for address in feeds]
        found = {}
        candidates = probe.find_candidates(
            shows, fetch=lambda address: feeds[address], pause=0, say=lambda *_: None,
            transcripts=found)
        self.assertEqual(len(candidates), 2)
        self.assertEqual(found, {"Show a": ["text/vtt"], "Show b": []})

    def test_a_feed_that_fails_is_not_counted(self):
        def fetch(address):
            raise OSError("down")
        found = {}
        probe.find_candidates(
            [{"feed": "https://a.example/feed", "title": "A"}], fetch=fetch, pause=0,
            say=lambda *_: None, transcripts=found)
        self.assertEqual(found, {})

    def test_the_report_carries_the_count_when_the_pick_saved_it(self):
        with tempfile.TemporaryDirectory() as folder:
            with open(os.path.join(folder, "picks.tsv"), "w") as handle:
                handle.write("One\thttps://a.example/1.mp3\n")
            with open(os.path.join(folder, probe.TRANSCRIPTS_FILE), "w") as handle:
                handle.write("Publisher transcripts: 2 of 4 shows\n")
            report = probe.build_report(folder)
            self.assertIn("Publisher transcripts: 2 of 4 shows", report)
            self.assertTrue(report.index("Summary") < report.index("Publisher transcripts"))

    def test_the_report_without_the_count_is_as_before(self):
        with tempfile.TemporaryDirectory() as folder:
            with open(os.path.join(folder, "picks.tsv"), "w") as handle:
                handle.write("One\thttps://a.example/1.mp3\n")
            self.assertNotIn("Publisher transcripts", probe.build_report(folder))


if __name__ == "__main__":
    unittest.main()
