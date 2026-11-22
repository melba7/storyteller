"""Tests for teach_collect.py: the order of the plan, feeds that cannot be read, a collecting run with
fakes (refreshed addresses, files too big, free space). No network and no real
sleeping. Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import gzip
import json
import os
import tempfile
import unittest

import teach_collect as tc
import teach_fetch
from teach_testing import FakeResponse, dated, entry, feed

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
    def plan(self, feeds, known=(), per_show=2, lines=None, naps=None, stats=None):
        return tc.plan(SHOWS, set(known), per_show, fetcher(feeds), 1.0,
                       (naps if naps is not None else []).append,
                       (lines if lines is not None else []).append, stats)

    def test_round_robin_order(self):
        entries = self.plan(feeds_for())
        self.assertEqual([e["title"] for e in entries], ["a3", "b3", "c3", "a2", "b2", "c2"])

    def test_entries_have_the_full_shape(self):
        entry = self.plan(feeds_for())[0]
        self.assertEqual(entry["show"], "A")
        self.assertEqual(entry["feed"], "https://f/a")
        self.assertEqual(entry["id"], tc.episode_id("https://f/a", "", "https://cdn/a3.mp3"))
        self.assertEqual(set(entry), set(tc.FIELDS))
        for key, value in (("file", None), ("bytes", 0), ("sha256", None), ("host", None), ("error", None),
                           ("size", 100)):
            self.assertEqual(entry[key], value, key)
        tc.check_entry(entry)

    def test_dead_feed_is_skipped_with_one_line(self):
        feeds = feeds_for()
        feeds["https://f/b"] = None
        lines, stats = [], {}
        entries = self.plan(feeds, lines=lines, stats=stats)
        self.assertEqual([e["title"] for e in entries], ["a3", "c3", "a2", "c2"])
        self.assertEqual(lines, ["Skipped B: its feed could not be read (dead feed)"])
        self.assertEqual(stats["shows_read"], 2)

    def test_a_feed_that_is_not_xml_is_skipped_with_one_line_and_not_counted_as_read(self):
        feeds = feeds_for()
        feeds["https://f/c"] = b"<html><body>Not a feed"
        lines, stats = [], {}
        entries = self.plan(feeds, lines=lines, stats=stats)
        self.assertEqual([e["title"] for e in entries], ["a3", "b3", "a2", "b2"])
        self.assertEqual(len(lines), 1)
        self.assertTrue(lines[0].startswith("Skipped C: its feed could not be read (it is not valid XML"), lines)
        self.assertEqual(stats["shows_read"], 2)

    def test_feeds_with_the_usual_mistakes_are_read(self):
        text = feeds_for()["https://f/a"]
        feeds = feeds_for()
        feeds["https://f/a"] = b"\n  " + text.replace("a3", "a3 &nbsp; &").encode("utf-8")
        entries = self.plan(feeds)
        self.assertEqual(entries[0]["title"], "a3 &nbsp; &")

    def test_pause_between_feeds_only(self):
        naps = []
        self.plan(feeds_for(), naps=naps)
        self.assertEqual(naps, [1.0, 1.0])

    def test_known_episodes_are_not_planned_again(self):
        known = [tc.episode_id("https://f/a", "", "https://cdn/a3.mp3")]
        entries = self.plan(feeds_for(), known=known)
        self.assertEqual([e["title"] for e in entries], ["b3", "c3", "a2", "b2", "c2"])

    def test_listed_has_every_episode_the_feeds_list_now_known_or_new(self):
        known = tc.episode_id("https://f/a", "", "https://cdn/a3.mp3")
        stats = {}
        self.plan(feeds_for(), known=[known], stats=stats)
        self.assertEqual(len(stats["listed"]), 6)
        self.assertEqual(stats["listed"][known], {"address": "https://cdn/a3.mp3", "size": 100,
                                                  "type": "audio/mpeg"})

    def test_all_shows_are_read_without_the_old_limit(self):
        shows = [{"feed": "https://f/s%d" % n, "title": "S%d" % n} for n in range(40)]
        feeds = {s["feed"]: feed(dated("x", 1, "https://cdn/%s.mp3" % s["title"])) for s in shows}
        self.assertEqual(len(tc.plan(shows, set(), 1, fetcher(feeds), 0, lambda s: None, lambda m: None)), 40)


class CollectTests(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.dir.cleanup)
        self.folder = os.path.join(self.dir.name, "teach")
        self.calls = []
        self.lines = []

    def download(self, address, path, **more):
        self.calls.append(address)
        with open(path, "wb") as handle:
            handle.write(b"x" * 100)
        return {"bytes": 100, "sha256": "ab" * 32, "host": "cdn.example.com"}

    def run_collect(self, shows=SHOWS, feeds=None, per_show=2, max_bytes=10**9, keep=0, free=10**12,
                    download=None, **more):
        return tc.collect(self.folder, shows, per_show, max_bytes, keep, fetch=fetcher(feeds or feeds_for()),
                          download=download or self.download, free_space=lambda path: free,
                          sleep=lambda seconds: None, say=self.lines.append, **more)

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
        self.assertEqual(len(tc.load_manifest(self.folder)), 6)

    def test_the_file_name_follows_the_enclosure_type_when_the_address_shows_nothing(self):
        feeds = {s["feed"]: feed(dated("x", 1, "https://cdn/%s/download" % s["title"], type="audio/mp4"))
                 for s in SHOWS[:1]}
        self.run_collect(shows=SHOWS[:1], feeds=feeds)
        self.assertTrue(self.manifest()["episodes"][0]["file"].endswith(".m4a"))

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

    def test_the_file_about_to_come_counts_against_the_free_space(self):
        # 1050 free, 1000 to keep: the entries say 100 bytes each, so none fits.
        result = self.run_collect(keep=1000, free=1050)
        self.assertEqual((result["downloaded"], result["why"]), (0, "space"))
        result = self.run_collect(keep=1000, free=1100)
        self.assertEqual((result["downloaded"], result["why"]), (6, None))

    def test_failure_is_recorded_and_tried_again_next_run(self):
        def failing(address, path, **more):
            raise OSError("server said no")
        result = self.run_collect(download=failing)
        self.assertEqual((result["downloaded"], result["failed"]), (0, 6))
        self.assertEqual(self.manifest()["episodes"][0]["error"], "server said no")
        result = self.run_collect()
        self.assertEqual((result["downloaded"], result["failed"]), (6, 0))
        self.assertIsNone(self.manifest()["episodes"][0]["error"])

    def test_one_failure_does_not_stop_the_rest(self):
        def flaky(address, path, **more):
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

    def test_the_address_of_an_episode_without_a_file_is_refreshed_from_the_feed(self):
        feeds = {SHOWS[0]["feed"]: feed(dated("x", 1, "https://cdn/x.mp3?sig=old", guid="g1", length="100"))}

        def failing(address, path, **more):
            raise OSError("expired")
        self.run_collect(shows=SHOWS[:1], feeds=feeds, download=failing)
        self.assertEqual(self.manifest()["episodes"][0]["address"], "https://cdn/x.mp3?sig=old")
        feeds = {SHOWS[0]["feed"]: feed(dated("x", 1, "https://cdn/x.mp3?sig=new", guid="g1", length="250"))}
        self.run_collect(shows=SHOWS[:1], feeds=feeds)
        episode = self.manifest()["episodes"][0]
        self.assertEqual(self.calls, ["https://cdn/x.mp3?sig=new"])
        self.assertEqual((episode["address"], len(self.manifest()["episodes"])), ("https://cdn/x.mp3?sig=new", 1))

    def test_refresh_changes_only_entries_without_a_file(self):
        done, waiting = self.entries()
        tc.refresh([done, waiting], {done["id"]: {"address": "https://new/1.mp3", "size": 7, "type": ""},
                                     waiting["id"]: {"address": "https://new/2.mp3", "size": 8, "type": ""}})
        self.assertEqual((done["address"], waiting["address"], waiting["size"]),
                         ("https://a/1.mp3", "https://new/2.mp3", 8))

    def entries(self):
        return entry(1, audio=True), entry(2)

    def test_a_file_the_feed_says_is_too_big_is_skipped_and_never_tried_again(self):
        feeds = {SHOWS[0]["feed"]: feed(dated("big", 1, "https://cdn/big.mp3", length="700000000"),
                                        dated("ok", 2, "https://cdn/ok.mp3", length="100"))}
        result = self.run_collect(shows=SHOWS[:1], feeds=feeds)
        self.assertEqual((result["downloaded"], result["skipped"], result["failed"]), (1, 1, 0))
        self.assertEqual(self.calls, ["https://cdn/ok.mp3"])
        big = [e for e in self.manifest()["episodes"] if e["title"] == "big"][0]
        self.assertEqual(big["error"], "skipped: larger than 600 MB")
        self.calls.clear()
        result = self.run_collect(shows=SHOWS[:1], feeds=feeds)
        self.assertEqual((self.calls, result["skipped"], result["waiting"]), ([], 0, 0))

    def test_a_file_the_server_says_is_too_big_is_skipped_for_good(self):
        def too_big(address, path, **more):
            self.calls.append(address)
            raise teach_fetch.TooLarge("the file is bigger than 600 MB")
        self.run_collect(download=too_big)
        self.assertEqual({e["error"] for e in self.manifest()["episodes"]}, {"skipped: larger than 600 MB"})
        self.calls.clear()
        result = self.run_collect()
        self.assertEqual((self.calls, result["downloaded"], result["waiting"]), ([], 0, 0))

    def test_the_file_limit_is_passed_to_the_download(self):
        seen = []

        def download(address, path, **more):
            seen.append(more)
            return self.download(address, path)
        self.run_collect(per_show=1, download=download, max_file=12_000_000)
        self.assertEqual(seen[0], {"max_bytes": 12_000_000})

    def test_a_download_that_stopped_early_is_a_failure_that_is_tried_again(self):
        def cut(address, path, **more):
            raise OSError("the server stopped early: 60 of 100 bytes")
        self.run_collect(per_show=1, download=cut)
        self.assertTrue(self.manifest()["episodes"][0]["error"].startswith("the server stopped early"))
        self.assertIsNone(self.manifest()["episodes"][0]["file"])
        self.assertEqual(self.run_collect(per_show=1)["downloaded"], 3)

    def test_a_feed_that_cannot_be_read_is_said_and_not_counted(self):
        feeds = feeds_for()
        feeds["https://f/b"] = b"nothing like a feed"
        result = self.run_collect(feeds=feeds)
        self.assertEqual(result["shows_read"], 2)
        self.assertEqual(len([line for line in self.lines if line.startswith("Skipped B:")]), 1)

    def test_a_gzip_feed_through_the_real_fetch_is_read(self):
        packed = gzip.compress(feeds_for()["https://f/a"].encode("utf-8"))
        data = teach_fetch.fetch_feed("https://f/a", open_url=lambda request, timeout=None:
                                      FakeResponse(packed, **{"Content-Encoding": "gzip"}))
        self.assertEqual(len(tc.feed_episodes(data, 5)), 3)


if __name__ == "__main__":
    unittest.main()
