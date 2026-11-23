"""Tests that the tools which read labels still read a snapped label, and what each does with the
stretches that only the copies found: they carry "confidence": "medium" and "origin": "copy".
The training, the habits and the score take "high" and "medium", so they learn from them; the
library and the sound prints take only "high", so a guessed sort is not spread to the phone. The
Python readers are imported and run on a snapped file. The Swift readers are pinned by the lines of
their source that decide it (TeachingFolder.swift decodes only sort, start, end and confidence from
a segment, so "origin" is ignored there; AdSoundCommand.swift reads a segment as a dictionary).
Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import json
import os
import unittest

import teach_habits
import teach_library
import teach_segments as seg
import teach_snap
import teach_train
from test_teach_snap import Base, segment

SOURCES = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "Sources")


class SnappedLabelReaderTests(Base):
    def setUp(self):
        super().setUp()
        self.label([segment(7, 12, 30.0, 60.0)])
        self.truth(("0:33.480", "1:02.120"), ("3:20.000", "3:50.000"))
        self.assertEqual(self.run_main(), 0)
        self.one = self.snapped()
        self.moved, self.added = self.one["segments"]
        with open(self.folder.path("transcripts", self.id + ".txt"), encoding="utf-8") as handle:
            self.lines = seg.read_transcript(handle.read())

    def test_the_added_stretch_says_where_it_came_from_and_is_medium(self):
        self.assertEqual((self.added["origin"], self.added["confidence"]), ("copy", "medium"))
        self.assertNotIn("origin", self.moved)
        self.assertEqual(self.moved["confidence"], "high")

    def test_the_label_is_valid_for_the_training_and_the_added_lines_are_sponsor_lines(self):
        self.assertTrue(teach_train.valid_label(self.one))
        classes = teach_train.line_classes(self.one["segments"], 120)
        self.assertEqual({classes[n - 1] for n in range(self.added["first"], self.added["last"] + 1)},
                         {teach_train.CLASSES.index("sponsor")})

    def test_the_habits_count_the_added_stretch_as_an_ad(self):
        self.assertTrue(teach_habits.valid(self.one))
        facts = teach_habits.facts_of(self.one)
        self.assertEqual(len(facts["blocks"]), 2)
        self.assertAlmostEqual(facts["ad_seconds"], (62.12 - 33.48) + 30.0, places=2)

    def test_the_library_leaves_the_added_stretch_out_but_can_use_the_moved_label(self):
        self.assertFalse(teach_library.usable(self.added, self.lines))
        self.assertTrue(teach_library.usable(self.moved, self.lines))

    def test_the_file_is_plain_json_with_the_keys_the_swift_reader_takes(self):
        with open(self.folder.path("labels-snapped", self.id + ".json"), encoding="utf-8") as handle:
            raw = json.load(handle)
        for one in raw["segments"]:
            self.assertIsInstance(one["sort"], str)
            self.assertIsInstance(one["confidence"], str)
            self.assertIsInstance(one["start"], float)
            self.assertIsInstance(one["end"], float)


class SwiftReaderTests(unittest.TestCase):
    """The lines of the Swift sources that this tool's choice of "medium" depends on."""

    def source(self, *names):
        with open(os.path.join(SOURCES, *names), encoding="utf-8") as handle:
            return handle.read()

    def test_the_score_takes_high_and_medium(self):
        self.assertIn('case "high", "medium": truth.append(stretch)', self.source("PodcastAds", "TeachingFolder.swift"))

    def test_the_sound_prints_take_only_high(self):
        self.assertIn('segment["confidence"] as? String == "high"',
                      self.source("PodcastAudioMatch", "AdSoundCommand.swift"))

    def test_the_segment_decoder_reads_only_the_four_keys(self):
        self.assertIn("private enum Keys: String, CodingKey { case sort, start, end, confidence }",
                      self.source("PodcastAds", "TeachingFolder.swift"))


class LimitsMatchTests(unittest.TestCase):
    def test_the_longest_stretch_is_the_longest_ad_the_library_takes(self):
        self.assertEqual(teach_snap.MAX_STRETCH_SECONDS, teach_library.MAX_SECONDS)


if __name__ == "__main__":
    unittest.main()
