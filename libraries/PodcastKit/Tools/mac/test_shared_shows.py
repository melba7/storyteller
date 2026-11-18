"""Tests for shared_shows.py: choosing the episodes from a feed, the downloads of a file's start
(against a small server on this computer), the preparation of a run and the report table. No
network. Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import json
import os
import tempfile
import threading
import unittest
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import shared_shows as shared


def feed(*items):
    """A feed with items given as (title, date or None, address or None)."""
    body = ""
    for title, date, address in items:
        body += "<item><title>%s</title>" % title
        if date:
            body += "<pubDate>%s</pubDate>" % date
        if address:
            body += '<enclosure url="%s" type="audio/mpeg"/>' % address
        body += "</item>"
    return '<?xml version="1.0"?><rss><channel><title>Show</title>%s</channel></rss>' % body


FEED = feed(
    ("Old", "Mon, 01 Jan 2024 10:00:00 +0000", "https://traffic.megaphone.fm/old.mp3"),
    ("Newer", "Tue, 05 Mar 2024 10:00:00 +0000", "https://dts.podtrac.com/newer.mp3"),
    ("No audio", "Fri, 08 Mar 2024 10:00:00 +0000", None),
    ("Middle", "Mon, 05 Feb 2024 10:00:00 +0000", "https://traffic.megaphone.fm/middle.mp3"),
)

# What `podcast-ads --shared` printed for a made-up pair: two runs, the first with a reservoir
# reset at both of its ends in both episodes.
SHARED = """Frames that are the same bytes in two episodes

First episode: 1-1.mp3
  0:48.1 long, 1843 MP3 frames, 128 kbps at the start. Reservoir resets: 2 (about one every 0.4 min). Changes of encoding: 0.
Second episode: 1-2.mp3
  0:42.3 long, 1623 MP3 frames, 128 kbps at the start. Reservoir resets: 2 (about one every 0.4 min). Changes of encoding: 0.

Stretches of 3 s or more that are the same bytes in both episodes (2):

Run 1: 30.0 s, 1150 frames
  In the first episode: 0:07.8 to 0:37.8 (frames 300 to 1449)
    start: a reservoir reset right at the edge
    end: a reservoir reset right at the edge
  In the second episode: 0:02.0 to 0:32.1 (frames 80 to 1229)
    start: a reservoir reset 1 frame after it
    end: a change of encoding (128 kbps, 44100 Hz, stereo becomes 64 kbps, 44100 Hz, stereo)

Run 2: 5.0 s, 192 frames
  In the first episode: 0:40.5 to 0:45.5 (frames 1551 to 1742)
    start: a reservoir reset right at the edge
    end: nothing within 2 frames
  In the second episode: 0:37.3 to 0:42.3 (frames 1431 to 1622)
    start: nothing within 2 frames
    end: nothing within 2 frames

Summary
  Stretches of 3 s or more: 2. Of 10 s or more: 1.
"""

NONE = """Frames that are the same bytes in two episodes

First episode: 2-1.mp3
  0:48.3 long, 1850 MP3 frames, 128 kbps at the start. Reservoir resets: none. Changes of encoding: 0.
Second episode: 2-2.mp3
  1:52.3 long, 4300 MP3 frames, 128 kbps at the start. Reservoir resets: none. Changes of encoding: 0.

No stretch of 3 s or more is the same bytes in both episodes.

Summary
  Stretches of 3 s or more: 0. Of 10 s or more: 0.
"""


class ChooseEpisodeTests(unittest.TestCase):
    def test_the_two_newest_episodes_with_audio_come_first_newest_first(self):
        self.assertEqual(
            shared.newest_enclosures(FEED),
            ["https://dts.podtrac.com/newer.mp3", "https://traffic.megaphone.fm/middle.mp3"])

    def test_a_count_of_three_gives_three(self):
        self.assertEqual(len(shared.newest_enclosures(FEED, 3)), 3)
        self.assertEqual(len(shared.newest_enclosures(FEED, 9)), 3)

    def test_without_dates_the_first_items_are_the_newest(self):
        xml = feed(("A", None, "https://a.example/1.mp3"), ("B", None, "https://a.example/2.mp3"),
                   ("C", None, "https://a.example/3.mp3"))
        self.assertEqual(shared.newest_enclosures(xml),
                         ["https://a.example/1.mp3", "https://a.example/2.mp3"])

    def test_two_items_with_one_address_are_one_episode(self):
        xml = feed(("A", "Tue, 05 Mar 2024 10:00:00 +0000", "https://a.example/1.mp3"),
                   ("A again", "Mon, 04 Mar 2024 10:00:00 +0000", "https://a.example/1.mp3"))
        self.assertEqual(shared.newest_enclosures(xml), ["https://a.example/1.mp3"])

    def test_bad_feeds_give_nothing(self):
        self.assertEqual(shared.newest_enclosures("not xml"), [])
        self.assertEqual(shared.newest_enclosures("<rss><channel></channel></rss>"), [])

    def test_shows_with_fewer_than_two_episodes_are_skipped_and_failing_feeds_do_not_stop_it(self):
        def fetch(address):
            if "bad" in address:
                raise OSError("down")
            if "one" in address:
                return feed(("Only", None, "https://one.example/1.mp3"))
            return FEED
        shows = [{"feed": "https://bad.example/f", "title": "Bad"},
                 {"feed": "https://one.example/f", "title": "One"},
                 {"feed": "https://ok.example/f", "title": "Ok"}]
        notes = []
        found = shared.find_candidates(shows, fetch=fetch, pause=0, say=notes.append)
        self.assertEqual([c["title"] for c in found], ["Ok"])
        self.assertEqual(found[0]["addresses"][0], "https://dts.podtrac.com/newer.mp3")
        self.assertEqual(len(notes), 2)

    def test_three_shows_from_different_hosts_ad_hosts_first(self):
        def candidate(title, host):
            return {"title": title, "address": "https://%s/a.mp3" % host,
                    "addresses": ["https://%s/a.mp3" % host, "https://%s/b.mp3" % host]}
        items = [candidate("Plain", "files.plain.example"), candidate("Plain2", "files.plain.example"),
                 candidate("Acast", "sphinx.acast.com"), candidate("Mega", "traffic.megaphone.fm"),
                 candidate("Omny", "traffic.omny.fm")]
        self.assertEqual([c["title"] for c in shared.choose_shows(items)], ["Mega", "Acast", "Omny"])


class Server:
    """A small server on this computer that sends a file of `size` bytes (byte n is n % 251),
    honouring the Range header or not, and keeps the headers it was asked with."""
    def __init__(self, size, honour_range=True):
        outer = self
        self.size = size
        self.seen = []

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def do_GET(self):
                outer.seen.append(dict(self.headers))
                if self.path == "/missing.mp3":
                    self.send_error(404)
                    return
                body = bytes(n % 251 for n in range(outer.size))
                wanted = self.headers.get("Range")
                if wanted and honour_range:
                    last = min(int(wanted.split("-")[1]), outer.size - 1)
                    chunk = body[:last + 1]
                    self.send_response(206)
                    self.send_header("Content-Range", "bytes 0-%d/%d" % (last, outer.size))
                else:
                    chunk = body
                    self.send_response(200)
                self.send_header("Content-Length", str(len(chunk)))
                self.end_headers()
                try:
                    self.wfile.write(chunk)
                except OSError:
                    pass  # the reader stopped early, as it should

        self.httpd = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.address = "http://127.0.0.1:%d/ep.mp3" % self.httpd.server_address[1]
        threading.Thread(target=self.httpd.serve_forever, daemon=True).start()

    def close(self):
        self.httpd.shutdown()
        self.httpd.server_close()


DIRECT = urllib.request.build_opener(urllib.request.ProxyHandler({})).open  # no proxy: it is local


class DownloadTests(unittest.TestCase):
    def fetch(self, size, limit, honour_range=True):
        server = Server(size, honour_range)
        self.addCleanup(server.close)
        folder = tempfile.TemporaryDirectory()
        self.addCleanup(folder.cleanup)
        path = os.path.join(folder.name, "a.mp3")
        info = shared.download_head(server.address, path, limit=limit, open_url=DIRECT)
        with open(path, "rb") as handle:
            return info, handle.read(), server

    def test_only_the_first_bytes_are_asked_for_and_kept(self):
        info, data, server = self.fetch(size=300_000, limit=100_000)
        self.assertEqual(len(data), 100_000)
        self.assertEqual(data[:300], bytes(n % 251 for n in range(300)))
        self.assertEqual((info["bytes"], info["status"], info["total"]), (100_000, 206, 300_000))
        self.assertEqual(info["note"], "")
        self.assertEqual(server.seen[0]["Range"], "bytes=0-99999")
        self.assertIn("StorytellerLofi", server.seen[0]["User-Agent"])

    def test_a_server_that_ignores_the_range_is_stopped_at_the_limit_and_noted(self):
        info, data, _ = self.fetch(size=300_000, limit=100_000, honour_range=False)
        self.assertEqual(len(data), 100_000)
        self.assertEqual(info["status"], 200)
        self.assertIn("ignored", info["note"])

    def test_a_file_shorter_than_the_limit_is_kept_whole(self):
        info, data, _ = self.fetch(size=5_000, limit=100_000, honour_range=False)
        self.assertEqual(len(data), 5_000)
        self.assertEqual(info["note"], "")

    def test_a_missing_file_raises(self):
        server = Server(10)
        self.addCleanup(server.close)
        with tempfile.TemporaryDirectory() as folder:
            with self.assertRaises(OSError):
                shared.download_head(server.address.replace("ep.mp3", "missing.mp3"),
                                     os.path.join(folder, "a.mp3"), limit=100, open_url=DIRECT)


class PrepareTests(unittest.TestCase):
    def run_prepare(self, downloads_fail=()):
        feeds = {
            "https://mega.example/f": feed(("n", "Tue, 05 Mar 2024 10:00:00 +0000", "https://traffic.megaphone.fm/2.mp3"),
                                           ("o", "Mon, 04 Mar 2024 10:00:00 +0000", "https://traffic.megaphone.fm/1.mp3")),
            "https://acast.example/f": feed(("n", "Tue, 05 Mar 2024 10:00:00 +0000", "https://sphinx.acast.com/2.mp3"),
                                            ("o", "Mon, 04 Mar 2024 10:00:00 +0000", "https://sphinx.acast.com/1.mp3")),
        }
        shows = [{"feed": "https://acast.example/f", "title": "Acast show"},
                 {"feed": "https://mega.example/f", "title": "Mega show"}]
        asked = []

        def download(address, path, **_):
            asked.append(address)
            if address in downloads_fail:
                raise OSError("timed out")
            with open(path, "wb") as handle:
                handle.write(b"x" * 10)
            return {"bytes": 10, "status": 206, "total": 99, "note": "", "host": "cdn.example.com"}

        pauses = []
        folder = tempfile.TemporaryDirectory()
        self.addCleanup(folder.cleanup)
        count = shared.prepare(folder.name, shows, fetch=lambda feed_address: feeds[feed_address],
                               download=download, pause=0, sleep=pauses.append, say=lambda *_: None)
        return folder.name, count, asked, pauses

    def test_it_downloads_the_two_newest_episodes_of_each_show_one_at_a_time_with_pauses(self):
        work, count, asked, pauses = self.run_prepare()
        self.assertEqual(count, 2)
        self.assertEqual(asked, ["https://traffic.megaphone.fm/2.mp3", "https://traffic.megaphone.fm/1.mp3",
                                 "https://sphinx.acast.com/2.mp3", "https://sphinx.acast.com/1.mp3"])
        self.assertEqual(len(pauses), 3)  # between the four downloads, none before the first
        with open(os.path.join(work, "pairs.tsv")) as handle:
            lines = [line.rstrip("\n").split("\t") for line in handle]
        self.assertEqual([line[0] for line in lines], ["1", "2"])
        self.assertEqual(lines[0][1:], [os.path.join(work, "1-1.mp3"), os.path.join(work, "1-2.mp3")])
        with open(os.path.join(work, "shows.json")) as handle:
            saved = json.load(handle)
        self.assertEqual([show["title"] for show in saved], ["Mega show", "Acast show"])
        self.assertEqual(saved[0]["host"], "cdn.example.com")

    def test_a_show_whose_download_fails_is_kept_for_the_report_but_not_compared(self):
        work, count, _, _ = self.run_prepare(downloads_fail=("https://sphinx.acast.com/1.mp3",))
        self.assertEqual(count, 1)
        with open(os.path.join(work, "pairs.tsv")) as handle:
            self.assertEqual([line.split("\t")[0] for line in handle], ["1"])
        with open(os.path.join(work, "shows.json")) as handle:
            saved = json.load(handle)
        self.assertFalse(saved[1]["ready"])
        self.assertIn("timed out", saved[1]["episodes"][1]["error"])


class ReportTests(unittest.TestCase):
    def test_a_shared_output_is_read_into_runs_the_longest_and_the_marked_ends(self):
        info = shared.parse_shared(SHARED)
        self.assertIsNone(info["error"])
        self.assertEqual(info["runs"], 2)
        self.assertEqual(info["longest"], 30.0)
        # Run 1 has a reset or a seam at both ends in both episodes; run 2 only at one start.
        self.assertEqual(info["both_ends"], [1, 1])

    def test_no_run(self):
        info = shared.parse_shared(NONE)
        self.assertEqual((info["error"], info["runs"], info["longest"], info["both_ends"]),
                         (None, 0, 0.0, [0, 0]))

    def test_a_failed_comparison_gives_its_reason(self):
        info = shared.parse_shared("No MP3 frames in 3-1.mp3 (not an MP3 file, or a web page was saved).\n")
        self.assertIn("No MP3 frames", info["error"])
        self.assertIn("no result", shared.parse_shared("")["error"])

    def row(self, title, host, info):
        return shared.table_line(title, host, info)

    def test_table_lines(self):
        line = self.row("Show", "cdn.example.com", shared.parse_shared(SHARED))
        for part in ("Show", "cdn.example.com", "2", "30.0 s", "1 / 1"):
            self.assertIn(part, line)
        none = self.row("Show", "cdn.example.com", shared.parse_shared(NONE))
        self.assertIn("0", none)
        self.assertIn("none", none)
        failed = self.row("Show", "?", shared.parse_shared(""))
        self.assertIn("FAILED", failed)

    def test_the_report_says_what_was_downloaded_and_ends_with_the_table(self):
        with tempfile.TemporaryDirectory() as work:
            shows = [
                {"number": 1, "title": "One", "host": "cdn.example.com", "ready": True,
                 "episodes": [
                     {"address": "https://a.example/2.mp3", "file": "x", "bytes": 20_000_000, "status": 206,
                      "total": 57_000_000, "note": "", "error": None},
                     {"address": "https://a.example/1.mp3", "file": "y", "bytes": 20_000_000, "status": 200,
                      "total": None, "note": "the server ignored the Range request", "error": None}]},
                {"number": 2, "title": "Two", "host": "slow.example.com", "ready": False,
                 "episodes": [
                     {"address": "https://b.example/2.mp3", "file": "x", "bytes": 20_000_000, "status": 206,
                      "total": None, "note": "", "error": None},
                     {"address": "https://b.example/1.mp3", "file": None, "bytes": 0, "status": None,
                      "total": None, "note": "", "error": "timed out"}]},
            ]
            with open(os.path.join(work, "shows.json"), "w") as handle:
                json.dump(shows, handle)
            with open(os.path.join(work, "1.txt"), "w") as handle:
                handle.write(SHARED)
            report = shared.build_report(work)
        head, table = report.split("\n" + shared.TABLE_HEADING + "\n")
        self.assertIn("first 20 MB", head)
        self.assertIn("pre-roll", head)
        self.assertIn("https://a.example/2.mp3", head)
        self.assertIn("ignored the Range", head)
        self.assertIn("Run 1: 30.0 s", head)
        self.assertIn("timed out", head)
        self.assertIn("30.0 s", table)
        self.assertIn("FAILED", table)
        self.assertTrue(table.rstrip().splitlines()[-1].startswith("Two"))


if __name__ == "__main__":
    unittest.main()
