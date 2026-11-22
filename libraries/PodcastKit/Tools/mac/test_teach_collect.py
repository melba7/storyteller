"""Tests for teach_collect.py: choosing episodes from a feed, the order of the plan, the download of
a whole file (against a fake answer), and a collecting run with fakes. No network and no real
sleeping. Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import hashlib
import io
import json
import os
import tempfile
import unittest

import teach_collect as tc

ITUNES = 'xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd"'


def feed(*items):
    """A feed with items given as dicts: title, date, address, guid, duration, length, type."""
    body = ""
    for item in items:
        body += "<item><title>%s</title>" % item.get("title", "")
        if item.get("guid"):
            body += "<guid>%s</guid>" % item["guid"]
        if item.get("date"):
            body += "<pubDate>%s</pubDate>" % item["date"]
        if item.get("duration"):
            body += "<itunes:duration>%s</itunes:duration>" % item["duration"]
        if item.get("address"):
            body += '<enclosure url="%s" type="%s" length="%s"/>' % (
                item["address"], item.get("type", "audio/mpeg"), item.get("length", ""))
        body += "</item>"
    return '<?xml version="1.0"?><rss %s><channel><title>Show</title>%s</channel></rss>' % (ITUNES, body)


def dated(title, day, address, **more):
    return dict(title=title, date="Mon, %02d Jan 2024 10:00:00 +0000" % day, address=address, **more)


class FakeResponse(io.BytesIO):
    def __init__(self, data, content_type="audio/mpeg", url="https://cdn.example.com/a.mp3"):
        super().__init__(data)
        self.headers = {"Content-Type": content_type}
        self._url = url

    def geturl(self):
        return self._url


def opener(data, **more):
    seen = {}

    def open_url(request, timeout=None):
        seen["request"] = request
        seen["timeout"] = timeout
        return FakeResponse(data, **more)
    open_url.seen = seen
    return open_url


class EpisodeIdTests(unittest.TestCase):
    def test_id_is_twelve_hex_digits_of_sha1(self):
        expected = hashlib.sha1("https://a/feed\nguid-1".encode("utf-8")).hexdigest()[:12]
        self.assertEqual(tc.episode_id("https://a/feed", "guid-1", "https://a/x.mp3"), expected)

    def test_address_is_used_without_guid(self):
        expected = hashlib.sha1("f\nhttps://a/x.mp3".encode("utf-8")).hexdigest()[:12]
        self.assertEqual(tc.episode_id("f", "", "https://a/x.mp3"), expected)


class FeedEpisodesTests(unittest.TestCase):
    def test_newest_first_by_date(self):
        xml = feed(dated("Old", 1, "https://a/1.mp3"), dated("New", 9, "https://a/9.mp3"),
                   dated("Mid", 5, "https://a/5.mp3"))
        result = tc.feed_episodes(xml, 2)
        self.assertEqual([e["title"] for e in result], ["New", "Mid"])

    def test_undated_come_after_dated_in_feed_order(self):
        xml = feed(dict(title="U1", address="https://a/u1.mp3"), dated("D", 3, "https://a/d.mp3"),
                   dict(title="U2", address="https://a/u2.mp3"))
        self.assertEqual([e["title"] for e in tc.feed_episodes(xml, 5)], ["D", "U1", "U2"])

    def test_each_address_once_and_no_audio_skipped(self):
        xml = feed(dated("A", 5, "https://a/x.mp3"), dated("B", 4, "https://a/x.mp3"),
                   dict(title="Text", date="Mon, 09 Jan 2024 10:00:00 +0000"),
                   dated("FTP", 8, "ftp://a/f.mp3"), dated("C", 3, "https://a/c.mp3"))
        self.assertEqual([e["title"] for e in tc.feed_episodes(xml, 5)], ["A", "C"])

    def test_video_enclosure_skipped(self):
        xml = feed(dated("Video", 9, "https://a/v.mp4", type="video/mp4"), dated("Audio", 1, "https://a/a.mp3"))
        self.assertEqual([e["title"] for e in tc.feed_episodes(xml, 5)], ["Audio"])

    def test_fields(self):
        xml = feed(dated("T", 2, "https://a/t.mp3", guid="g1", duration="1:02:03", length="12345"))
        episode = tc.feed_episodes(xml, 1)[0]
        self.assertEqual(episode["guid"], "g1")
        self.assertEqual(episode["seconds"], 3723)
        self.assertEqual(episode["size"], 12345)
        self.assertEqual(episode["address"], "https://a/t.mp3")
        self.assertIsInstance(episode["published"], int)

    def test_missing_or_bad_length_is_unknown(self):
        for length in ("", "0", "-5", "abc", "1.5"):
            xml = feed(dated("T", 2, "https://a/t.mp3", length=length))
            self.assertIsNone(tc.feed_episodes(xml, 1)[0]["size"], length)

    def test_three_duration_forms_and_junk(self):
        cases = {"1:02:03": 3723, "45:10": 2710, "1800": 1800, "soon": None, "1:2:3:4": None, "": None}
        for text, seconds in cases.items():
            xml = feed(dated("T", 2, "https://a/t.mp3", duration=text))
            self.assertEqual(tc.feed_episodes(xml, 1)[0]["seconds"], seconds, text)

    def test_no_date_gives_null_published(self):
        xml = feed(dict(title="U", address="https://a/u.mp3"))
        self.assertIsNone(tc.feed_episodes(xml, 1)[0]["published"])

    def test_broken_xml_gives_empty_list(self):
        self.assertEqual(tc.feed_episodes("<rss><channel>", 3), [])


SHOWS = [{"feed": "https://f/%s" % name, "title": name.upper()} for name in "abc"]


def feeds_for(shows=SHOWS, per_show=3):
    """A feed per show with `per_show` episodes, the newest being number `per_show`."""
    result = {}
    for show in shows:
        name = show["feed"][-1]
        result[show["feed"]] = feed(*[
            dated("%s%d" % (name, n), n, "https://cdn/%s%d.mp3" % (name, n), length="100")
            for n in range(1, per_show + 1)])
    return result


def fetcher(feeds):
    def fetch(address):
        if feeds.get(address) is None:
            raise OSError("dead feed")
        return feeds[address]
    return fetch


class PlanTests(unittest.TestCase):
    def plan(self, feeds, known=(), per_show=2, lines=None, naps=None):
        return tc.plan(SHOWS, set(known), per_show, fetcher(feeds), 1.0,
                       (naps if naps is not None else []).append, (lines if lines is not None else []).append)

    def test_round_robin_order(self):
        entries = self.plan(feeds_for())
        self.assertEqual([e["title"] for e in entries], ["a3", "b3", "c3", "a2", "b2", "c2"])

    def test_entries_have_the_full_shape(self):
        entry = self.plan(feeds_for())[0]
        self.assertEqual(entry["show"], "A")
        self.assertEqual(entry["feed"], "https://f/a")
        self.assertEqual(entry["id"], tc.episode_id("https://f/a", "", "https://cdn/a3.mp3"))
        for key, value in (("file", None), ("bytes", 0), ("sha256", None), ("host", None), ("error", None),
                           ("size", 100)):
            self.assertEqual(entry[key], value, key)

    def test_dead_feed_is_skipped_with_one_line(self):
        feeds = feeds_for()
        feeds["https://f/b"] = None
        lines = []
        entries = self.plan(feeds, lines=lines)
        self.assertEqual([e["title"] for e in entries], ["a3", "c3", "a2", "c2"])
        self.assertEqual(len([line for line in lines if "B" in line]), 1)

    def test_pause_between_feeds_only(self):
        naps = []
        self.plan(feeds_for(), naps=naps)
        self.assertEqual(naps, [1.0, 1.0])

    def test_known_episodes_are_not_planned_again(self):
        known = [tc.episode_id("https://f/a", "", "https://cdn/a3.mp3")]
        entries = self.plan(feeds_for(), known=known)
        self.assertEqual([e["title"] for e in entries], ["b3", "c3", "a2", "b2", "c2"])

    def test_all_shows_are_read_without_the_old_limit(self):
        shows = [{"feed": "https://f/s%d" % n, "title": "S%d" % n} for n in range(40)]
        feeds = {s["feed"]: feed(dated("x", 1, "https://cdn/%s.mp3" % s["title"])) for s in shows}
        self.assertEqual(len(tc.plan(shows, set(), 1, fetcher(feeds), 0, lambda s: None, lambda m: None)), 40)


class DownloadTests(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.dir.cleanup)
        self.path = os.path.join(self.dir.name, "x.mp3")

    def test_saves_file_and_reports_hash_bytes_host(self):
        data = b"abc" * 1000
        open_url = opener(data, url="https://cdn.example.com/final.mp3")
        info = tc.download("https://a/x.mp3", self.path, open_url=open_url)
        self.assertEqual(info, {"bytes": 3000, "sha256": hashlib.sha256(data).hexdigest(),
                                "host": "cdn.example.com"})
        with open(self.path, "rb") as handle:
            self.assertEqual(handle.read(), data)
        self.assertFalse(os.path.exists(self.path + ".part"))

    def test_request_headers_and_read_timeout(self):
        open_url = opener(b"data")
        tc.download("https://a/x.mp3", self.path, open_url=open_url)
        request = open_url.seen["request"]
        self.assertEqual(request.get_header("Accept-encoding"), "identity")
        self.assertEqual(request.get_header("User-agent"), tc.probe.USER_AGENT)
        self.assertEqual(open_url.seen["timeout"], 30)

    def assert_fails(self, open_url, **more):
        with self.assertRaises((OSError, ValueError)):
            tc.download("https://a/x.mp3", self.path, open_url=open_url, **more)
        self.assertFalse(os.path.exists(self.path))
        self.assertFalse(os.path.exists(self.path + ".part"))

    def test_empty_file_fails(self):
        self.assert_fails(opener(b""))

    def test_too_big_fails(self):
        self.assert_fails(opener(b"x" * 50), max_bytes=40)

    def test_text_answer_fails(self):
        self.assert_fails(opener(b"<html>sorry</html>", content_type="text/html; charset=utf-8"))

    def test_too_slow_fails(self):
        ticks = iter(range(0, 100000, 700))
        self.assert_fails(opener(b"x" * 100), clock=lambda: next(ticks), chunk=10)

    def test_network_error_leaves_no_part(self):
        def broken(request, timeout=None):
            raise OSError("reset")
        self.assert_fails(broken)

    def test_a_half_file_is_not_resumed(self):
        with open(self.path + ".part", "wb") as handle:
            handle.write(b"old half")
        tc.download("https://a/x.mp3", self.path, open_url=opener(b"fresh"))
        with open(self.path, "rb") as handle:
            self.assertEqual(handle.read(), b"fresh")


class CollectTests(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.dir.cleanup)
        self.folder = os.path.join(self.dir.name, "teach")
        self.calls = []

    def download(self, address, path):
        self.calls.append(address)
        with open(path, "wb") as handle:
            handle.write(b"x" * 100)
        return {"bytes": 100, "sha256": "ab" * 32, "host": "cdn.example.com"}

    def run_collect(self, shows=SHOWS, feeds=None, per_show=2, max_bytes=10**9, keep=0, free=10**12,
                    download=None):
        return tc.collect(self.folder, shows, per_show, max_bytes, keep, fetch=fetcher(feeds or feeds_for()),
                          download=download or self.download, free_space=lambda path: free,
                          sleep=lambda seconds: None, say=lambda line: None)

    def manifest(self):
        with open(os.path.join(self.folder, "episodes.json"), encoding="utf-8") as handle:
            return json.load(handle)

    def test_downloads_and_writes_manifest(self):
        result = self.run_collect()
        self.assertEqual((result["downloaded"], result["failed"], result["waiting"], result["bytes"]),
                         (6, 0, 0, 600))
        data = self.manifest()
        self.assertEqual(data["version"], 1)
        self.assertIsInstance(data["writtenAt"], int)
        first = data["episodes"][0]
        self.assertEqual(first["file"], "audio/%s.mp3" % first["id"])
        self.assertEqual((first["bytes"], first["host"], first["error"]), (100, "cdn.example.com", None))
        self.assertTrue(os.path.exists(os.path.join(self.folder, first["file"])))

    def test_extension_from_address(self):
        self.assertEqual(tc.audio_name("abc", "https://a/x.M4A?token=1"), "audio/abc.m4a")
        self.assertEqual(tc.audio_name("abc", "https://a/x.flac"), "audio/abc.mp3")
        self.assertEqual(tc.audio_name("abc", "https://a/download"), "audio/abc.mp3")

    def test_second_run_downloads_nothing_again_even_if_files_are_gone(self):
        self.run_collect()
        for name in os.listdir(os.path.join(self.folder, "audio")):
            os.remove(os.path.join(self.folder, "audio", name))
        self.calls.clear()
        result = self.run_collect()
        self.assertEqual((self.calls, result["downloaded"]), ([], 0))

    def test_stops_at_the_size_limit(self):
        result = self.run_collect(max_bytes=250)  # entries say size 100: two fit, the third does not
        self.assertEqual((result["downloaded"], result["waiting"], result["why"]), (2, 4, "size"))
        self.assertEqual(len([e for e in self.manifest()["episodes"] if e["file"]]), 2)

    def test_stops_at_the_free_space_limit(self):
        result = self.run_collect(keep=1000, free=999)
        self.assertEqual((result["downloaded"], result["waiting"], result["why"]), (0, 6, "space"))
        self.assertEqual(len(self.manifest()["episodes"]), 6)

    def test_failure_is_recorded_and_tried_again_next_run(self):
        def failing(address, path):
            raise OSError("server said no")
        result = self.run_collect(download=failing)
        self.assertEqual((result["downloaded"], result["failed"]), (0, 6))
        self.assertEqual(self.manifest()["episodes"][0]["error"], "server said no")
        result = self.run_collect()
        self.assertEqual((result["downloaded"], result["failed"]), (6, 0))
        self.assertIsNone(self.manifest()["episodes"][0]["error"])

    def test_one_failure_does_not_stop_the_rest(self):
        def flaky(address, path):
            if address.endswith("b3.mp3"):
                raise ValueError("empty")
            return self.download(address, path)
        result = self.run_collect(download=flaky)
        self.assertEqual((result["downloaded"], result["failed"]), (5, 1))

    def test_new_episodes_are_added_at_the_end(self):
        self.run_collect(per_show=1)
        self.run_collect(per_show=2)
        titles = [e["title"] for e in self.manifest()["episodes"]]
        self.assertEqual(titles, ["a3", "b3", "c3", "a2", "b2", "c2"])


class ManifestTests(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.dir.cleanup)
        self.path = os.path.join(self.dir.name, "episodes.json")

    def write(self, text):
        with open(self.path, "w", encoding="utf-8") as handle:
            handle.write(text)

    def good_entry(self, **more):
        entry = {"id": "3f2a9c1b0d4e", "feed": "https://f", "show": "S", "guid": "", "title": "",
                 "published": None, "seconds": None, "address": "https://a/x.mp3", "size": None,
                 "file": None, "bytes": 0, "sha256": None, "host": None, "error": None}
        entry.update(more)
        return entry

    def test_missing_file_means_no_episodes(self):
        self.assertEqual(tc.load_manifest(self.dir.name), [])

    def test_bad_files_are_refused(self):
        entry = self.good_entry()
        bad = ["{not json", "[]", json.dumps({"version": 2, "episodes": []}),
               json.dumps({"version": 1, "episodes": "no"}),
               json.dumps({"version": 1, "episodes": [5]}),
               json.dumps({"version": 1, "episodes": [dict(entry, id="../../etc")]}),
               json.dumps({"version": 1, "episodes": [dict(entry, file="../x.mp3")]}),
               json.dumps({"version": 1, "episodes": [dict(entry, file="audio/ffffffffffff.mp3")]}),
               json.dumps({"version": 1, "episodes": [dict(entry, bytes="many")]}),
               json.dumps({"version": 1, "episodes": [dict(entry, address=7)]}),
               json.dumps({"version": 1, "episodes": [entry, entry]})]
        for text in bad:
            self.write(text)
            with self.assertRaises(tc.ManifestError, msg=text):
                tc.load_manifest(self.dir.name)

    def test_good_file_is_read(self):
        entry = self.good_entry(file="audio/3f2a9c1b0d4e.mp3", bytes=5)
        self.write(json.dumps({"version": 1, "writtenAt": 1, "episodes": [entry]}))
        self.assertEqual(tc.load_manifest(self.dir.name), [entry])


class MainTests(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.dir.cleanup)
        self.folder = os.path.join(self.dir.name, "teach")
        self.shows = os.path.join(self.dir.name, "shows.json")
        with open(self.shows, "w", encoding="utf-8") as handle:
            json.dump({"shows": SHOWS[:1]}, handle)

    def run_main(self, *extra, **more):
        more.setdefault("say", lambda line: None)
        return tc.main(["--folder", self.folder, "--shows", self.shows] + list(extra),
                       fetch=fetcher(feeds_for()), sleep=lambda s: None, **more)

    def test_damaged_manifest_is_left_alone_and_gives_2(self):
        os.makedirs(self.folder)
        path = os.path.join(self.folder, "episodes.json")
        with open(path, "w", encoding="utf-8") as handle:
            handle.write("{broken")
        self.assertEqual(self.run_main(), 2)
        with open(path, encoding="utf-8") as handle:
            self.assertEqual(handle.read(), "{broken")

    def test_unreadable_shows_file_gives_2(self):
        os.remove(self.shows)
        self.assertEqual(self.run_main(), 2)

    def test_folder_that_cannot_be_written_gives_2(self):
        blocker = os.path.join(self.dir.name, "file")
        with open(blocker, "w") as handle:
            handle.write("x")
        self.folder = os.path.join(blocker, "inside")
        self.assertEqual(self.run_main(), 2)

    def test_list_writes_nothing(self):
        self.assertEqual(self.run_main("--list"), 0)
        self.assertFalse(os.path.exists(self.folder))

    def test_list_counts(self):
        lines = []
        self.assertEqual(self.run_main("--list", say=lines.append), 0)
        text = "\n".join(lines)
        self.assertIn("1 show", text)
        self.assertIn("3 episodes", text)  # the fake feed has 3, fewer than --per-show's 4
        self.assertIn("0.0 GB", text)

    def test_run_with_failures_still_exits_0(self):
        def failing(address, path):
            raise OSError("nope")
        self.assertEqual(self.run_main(download=failing), 0)


if __name__ == "__main__":
    unittest.main()
