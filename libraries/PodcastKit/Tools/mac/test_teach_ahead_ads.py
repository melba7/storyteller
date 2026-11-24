"""Tests for teach_ahead_ads.py: what the phone is told about the night's marks (ahead-ads.json): the
exact format, the kinds, the words at the start and the end of an ad, the 14 days, the episodes that
are never told (the exam, the shelf), and the size limit. No network. Run:
python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import json
import os
import shutil
import tempfile
import unittest

import teach_ahead_ads as ads
import teach_ahead_set as ahead
import teach_store as store
from teach_testing import entry

NOW = 1_800_000_000
DAY = 86400


def lines_of(count):
    """A transcript of `count` lines, line n being "word<n>a word<n>b word<n>c" at n * 10 seconds."""
    return [(n * 10.0, "word%da word%db word%dc" % (n + 1, n + 1, n + 1)) for n in range(count)]


def segment(first, last, sort="sponsor", confidence="high"):
    return {"first": first, "last": last, "sort": sort, "who": "Acme", "delivery": "host",
            "confidence": confidence, "why": "x", "start": (first - 1) * 10.0, "end": last * 10.0}


class AdsOfTests(unittest.TestCase):
    def test_a_stretch_becomes_an_ad_with_its_words_and_times(self):
        found = ads.ads_of({"segments": [segment(2, 3)]}, lines_of(10))
        self.assertEqual(found, [{"kind": "ad", "confidence": "high", "start": 10.0, "end": 30.0,
                                  "startWords": "word2a word2b word2c word3a word3b word3c",
                                  "endWords": "word2a word2b word2c word3a word3b word3c"}])
        self.assertEqual(list(found[0]), ["kind", "confidence", "start", "end", "startWords", "endWords"])

    def test_the_sorts_become_the_kinds_the_scorecard_uses(self):
        label = {"segments": [segment(1, 1, "sponsor"), segment(2, 2, "network_promo", "low"),
                              segment(3, 3, "host_ask", "medium")]}
        found = ads.ads_of(label, lines_of(5))
        self.assertEqual([(a["kind"], a["confidence"]) for a in found],
                         [("ad", "high"), ("promo", "low"), ("ownPlug", "medium")])

    def test_intro_and_credits_are_not_told_to_the_phone(self):
        label = {"segments": [segment(1, 1, "intro_credits"), segment(2, 2)]}
        self.assertEqual([a["start"] for a in ads.ads_of(label, lines_of(5))], [10.0])

    def test_the_start_has_the_first_forty_words_and_the_end_the_last_forty(self):
        lines = [(n * 10.0, " ".join("w%d_%d" % (n, k) for k in range(10))) for n in range(8)]
        found = ads.ads_of({"segments": [segment(1, 8)]}, lines)[0]
        start, end = found["startWords"].split(), found["endWords"].split()
        self.assertEqual((len(start), len(end)), (40, 40))
        self.assertEqual((start[0], start[-1]), ("w0_0", "w3_9"))
        self.assertEqual((end[0], end[-1]), ("w4_0", "w7_9"))

    def test_white_space_in_the_transcript_is_one_space(self):
        lines = [(0.0, "  one \t two  "), (5.0, "three\n")]
        found = ads.ads_of({"segments": [segment(1, 2)]}, lines)[0]
        self.assertEqual(found["startWords"], "one two three")

    def test_a_stretch_that_does_not_fit_the_transcript_is_left_out(self):
        label = {"segments": [segment(1, 99), segment(0, 2), segment(4, 3), segment(2, 2)]}
        self.assertEqual([a["start"] for a in ads.ads_of(label, lines_of(5))], [10.0])

    def test_a_label_with_no_stretches_has_no_ads(self):
        self.assertEqual(ads.ads_of({"segments": []}, lines_of(3)), [])


class Night:
    """A teaching folder with episodes that were read ahead."""

    def __init__(self, test):
        self.dir = tempfile.mkdtemp()
        test.addCleanup(shutil.rmtree, self.dir, True)
        self.entries = []
        self.said = []

    def add(self, number, marked=NOW - DAY, segments=None, label=True, transcript=True, ahead_too=True):
        item = entry(number, feed="https://mac/%d" % number, guid="g%d" % number)
        self.entries.append(item)
        store.save_manifest(self.dir, self.entries)
        if transcript:
            os.makedirs(os.path.join(self.dir, "transcripts"), exist_ok=True)
            with open(os.path.join(self.dir, "transcripts", item["id"] + ".txt"), "w") as f:
                for seconds, text in lines_of(10):
                    f.write("[00:%02d:%04.1f] %s\n" % (seconds // 60, seconds % 60, text))
        if label:
            os.makedirs(os.path.join(self.dir, "labels"), exist_ok=True)
            with open(os.path.join(self.dir, "labels", item["id"] + ".json"), "w") as f:
                json.dump({"version": 1, "episode": item["id"], "writtenAt": marked * 1000,
                           "segments": [segment(2, 3)] if segments is None else segments}, f)
        if ahead_too:
            ahead.add_ahead(self.dir, [{"id": item["id"], "feed": "https://phone/%d" % number,
                                        "guid": "phone-g%d" % number, "title": "Phone title %d" % number,
                                        "picked": marked}])
        return item

    def build(self):
        return ads.build(self.dir, NOW, self.said.append)


class BuildTests(unittest.TestCase):
    def test_the_published_file_has_exactly_the_agreed_format(self):
        night = Night(self)
        night.add(1, marked=NOW - 3600)
        built = night.build()
        self.assertEqual(built, [{
            "feed": "https://phone/1", "guid": "phone-g1", "title": "Phone title 1", "marked": NOW - 3600,
            "ads": [{"kind": "ad", "confidence": "high", "start": 10.0, "end": 30.0,
                     "startWords": "word2a word2b word2c word3a word3b word3c",
                     "endWords": "word2a word2b word2c word3a word3b word3c"}]}])
        self.assertEqual(list(built[0]), ["feed", "guid", "title", "marked", "ads"])
        self.assertIs(type(built[0]["marked"]), int)

    def test_the_phones_own_feed_and_guid_are_told_not_the_macs(self):
        night = Night(self)
        night.add(1)
        self.assertEqual((night.build()[0]["feed"], night.build()[0]["guid"]), ("https://phone/1", "phone-g1"))

    def test_an_episode_older_than_14_days_is_dropped(self):
        night = Night(self)
        night.add(1, marked=NOW - 14 * DAY - 1)
        night.add(2, marked=NOW - 14 * DAY)
        night.add(3, marked=NOW)
        self.assertEqual([e["guid"] for e in night.build()], ["phone-g2", "phone-g3"])

    def test_an_episode_with_no_ads_is_still_told(self):
        night = Night(self)
        night.add(1, segments=[])
        self.assertEqual(night.build()[0]["ads"], [])

    def test_an_episode_without_a_label_or_a_transcript_is_left_out(self):
        night = Night(self)
        night.add(1, label=False)
        night.add(2, transcript=False)
        night.add(3)
        self.assertEqual([e["guid"] for e in night.build()], ["phone-g3"])

    def test_an_episode_that_is_not_in_ahead_json_is_never_told(self):
        night = Night(self)
        night.add(1, ahead_too=False)
        self.assertEqual(night.build(), [])

    def test_an_exam_or_shelf_episode_is_never_told(self):
        night = Night(self)
        exam, shelf, plain = night.add(1), night.add(2), night.add(3)
        store.write_json(os.path.join(night.dir, "exam.json"), {"episodes": [exam["id"]]})
        store.write_json(os.path.join(night.dir, "shelf.json"), {"version": 1, "episodes": [shelf["id"]]})
        self.assertEqual([e["guid"] for e in night.build()], ["phone-g3"])
        self.assertEqual(plain["id"], night.entries[2]["id"])

    def test_a_damaged_label_is_left_out_with_one_line(self):
        night = Night(self)
        item = night.add(1)
        night.add(2)
        with open(os.path.join(night.dir, "labels", item["id"] + ".json"), "w") as f:
            f.write("{nope")
        self.assertEqual([e["guid"] for e in night.build()], ["phone-g2"])
        self.assertEqual(len(night.said), 1)
        self.assertIn(item["id"], night.said[0])


class WriteTests(unittest.TestCase):
    def read(self, night):
        with open(os.path.join(night.dir, "ahead-ads.json"), encoding="utf-8") as f:
            return json.load(f)

    def test_the_file_is_version_1_with_the_time_in_seconds(self):
        night = Night(self)
        night.add(1)
        self.assertEqual(ads.write(night.dir, NOW, night.said.append), "written")
        found = self.read(night)
        self.assertEqual(list(found), ["version", "writtenAt", "episodes"])
        self.assertEqual((found["version"], found["writtenAt"]), (1, NOW))
        self.assertEqual(found["episodes"], night.build())

    def test_nothing_to_tell_writes_no_file_and_changes_none(self):
        night = Night(self)
        self.assertEqual(ads.write(night.dir, NOW, night.said.append), "nothing")
        self.assertFalse(os.path.exists(os.path.join(night.dir, "ahead-ads.json")))

    def test_the_same_episodes_do_not_rewrite_the_file_or_change_its_time(self):
        night = Night(self)
        night.add(1)
        ads.write(night.dir, NOW, night.said.append)
        self.assertEqual(ads.write(night.dir, NOW + 5 * DAY, night.said.append), "unchanged")
        self.assertEqual(self.read(night)["writtenAt"], NOW)

    def test_dropping_an_old_episode_rewrites_the_file(self):
        night = Night(self)
        night.add(1, marked=NOW - 13 * DAY)
        night.add(2, marked=NOW)
        ads.write(night.dir, NOW, night.said.append)
        self.assertEqual(ads.write(night.dir, NOW + 2 * DAY, night.said.append), "written")
        self.assertEqual([e["guid"] for e in self.read(night)["episodes"]], ["phone-g2"])

    def test_an_old_file_with_everything_expired_becomes_an_empty_list(self):
        night = Night(self)
        night.add(1, marked=NOW)
        ads.write(night.dir, NOW, night.said.append)
        self.assertEqual(ads.write(night.dir, NOW + 20 * DAY, night.said.append), "written")
        self.assertEqual(self.read(night)["episodes"], [])

    def test_a_file_over_the_limit_drops_the_oldest_episodes_and_says_so(self):
        night = Night(self)
        for number in (1, 2, 3, 4):
            night.add(number, marked=NOW - (5 - number) * 3600)
        one = len(json.dumps(night.build()[0], separators=(",", ":"), ensure_ascii=False).encode())
        ads.write(night.dir, NOW, night.said.append, limit=3 * one + 100)
        self.assertEqual([e["guid"] for e in self.read(night)["episodes"]],
                         ["phone-g2", "phone-g3", "phone-g4"])
        self.assertTrue(any("too large" in line or "over the limit" in line for line in night.said))

    def test_the_default_limit_is_the_one_teach_publish_keeps(self):
        import teach_publish
        self.assertEqual(ads.LIMIT, teach_publish.LIMIT)


if __name__ == "__main__":
    unittest.main()
