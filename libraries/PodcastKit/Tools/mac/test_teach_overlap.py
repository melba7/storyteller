"""Tests for teach_overlap.py: a training episode that repeats a shelf episode is found by feed key
and guid, by audio hash or by shared 5-word runs. No network.
Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import os
import shutil
import tempfile
import unittest

import teach_overlap as overlap


def entry(identifier, feed="https://a.test/feed", guid="", sha=None):
    return {"id": identifier, "feed": feed, "guid": guid, "sha256": sha}


class OverlapTests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.folder, True)
        os.makedirs(os.path.join(self.folder, "transcripts"))

    def transcript(self, identifier, text):
        with open(os.path.join(self.folder, "transcripts", identifier + ".txt"), "w") as f:
            f.write("\n".join("[00:00:%02d.0] %s" % (n, line) for n, line in enumerate(text)))

    def found(self, entries, shelf, candidates):
        return overlap.same_episode_ids(self.folder, {e["id"]: e for e in entries}, shelf,
                                        candidates)

    def test_the_same_feed_key_and_guid_is_the_same_episode(self):
        shelf = entry("s", "https://www.A.test/feed/", "g1")
        again = entry("c", "http://a.test/feed", "g1")
        other = entry("d", "http://a.test/feed", "g2")
        self.assertEqual(self.found([shelf, again, other], ["s"], ["c", "d"]), ["c"])

    def test_an_empty_guid_never_matches(self):
        self.assertEqual(self.found([entry("s"), entry("c")], ["s"], ["c"]), [])

    def test_the_same_audio_hash_is_the_same_episode(self):
        shelf = entry("s", "https://a.test/1", "g1", sha="ab" * 32)
        again = entry("c", "https://b.test/2", "g2", sha="ab" * 32)
        other = entry("d", "https://b.test/3", "g3", sha="cd" * 32)
        self.assertEqual(self.found([shelf, again, other], ["s"], ["c", "d"]), ["c"])

    def test_more_than_half_the_five_word_runs_in_common(self):
        words = ["w%d" % n for n in range(40)]
        self.transcript("s", [" ".join(words)])
        self.transcript("c", [" ".join(words[:30] + ["x%d" % n for n in range(10)])])
        self.transcript("d", [" ".join(words[:15] + ["y%d" % n for n in range(25)])])
        entries = [entry("s", "https://a/1", "1"), entry("c", "https://b/1", "2"),
                   entry("d", "https://c/1", "3")]
        self.assertEqual(self.found(entries, ["s"], ["c", "d"]), ["c"])

    def test_a_missing_transcript_is_not_a_match(self):
        entries = [entry("s", "https://a/1", "1"), entry("c", "https://b/1", "2")]
        self.assertEqual(self.found(entries, ["s"], ["c"]), [])


if __name__ == "__main__":
    unittest.main()
