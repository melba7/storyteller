"""Tests that the tools which read labels still read a snapped label: its added stretches carry
"origin": "copy" next to "confidence": "high", which the readers must ignore or use as they use
any sure stretch. teach_train, teach_habits and teach_library are imported and run on a snapped
file. (The phone's Swift reader, TeachingFolder.swift, decodes only sort, start, end and
confidence from a segment, so a further key is ignored there; AdSoundCommand.swift reads a
segment as a dictionary by key.)
Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import json

import teach_habits
import teach_library
import teach_segments as seg
import teach_train
from test_teach_snap import Base, segment


class SnappedLabelReaderTests(Base):
    def setUp(self):
        super().setUp()
        self.label([segment(7, 12, 30.0, 60.0)])
        self.truth(("0:33.480", "1:02.120"), ("3:20.000", "3:50.000"))
        self.assertEqual(self.run_main(), 0)
        self.one = self.snapped()
        self.added = self.one["segments"][1]

    def test_the_added_stretch_is_marked_as_coming_from_the_copies_and_is_sure(self):
        self.assertEqual((self.added["origin"], self.added["confidence"]), ("copy", "high"))
        self.assertNotIn("origin", self.one["segments"][0])

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

    def test_the_library_can_use_the_added_stretch(self):
        with open(self.folder.path("transcripts", self.id + ".txt"), encoding="utf-8") as handle:
            lines = seg.read_transcript(handle.read())
        self.assertTrue(teach_library.usable(self.added, lines))

    def test_the_file_is_plain_json_with_the_keys_the_swift_reader_takes(self):
        with open(self.folder.path("labels-snapped", self.id + ".json"), encoding="utf-8") as handle:
            raw = json.load(handle)
        for one in raw["segments"]:
            self.assertIsInstance(one["sort"], str)
            self.assertIsInstance(one["confidence"], str)
            self.assertIsInstance(one["start"], float)
            self.assertIsInstance(one["end"], float)


if __name__ == "__main__":
    import unittest
    unittest.main()
