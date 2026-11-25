"""Tests for teach_pace.py: reading the phone's diary for the plays that were ready and for how
fast the phone transcribes. Temporary folders only, no network.
Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import json
import os
import shutil
import tempfile
import unittest
from unittest import mock

import teach_pace as pace


def diary(what, at=1700000000.0, episode="ab12cd34", kind="diary"):
    return {"episode": episode, "kind": kind, "time": at, "what": what}


# Twelve plays (7 ready, 3 partly, 2 streams) and three transcriptions (two in front, 5400 s of
# audio in 450 s, one in the background, 3000 s in 150 s), among the lines the diary always holds.
SAMPLE = (
    [diary("play: ready")] * 7
    + [diary("play: partly, transcript to 240 s"), diary("play: partly, transcript to 0 s"),
       diary("play: partly, transcript to 1800 s")]
    + [diary("play: stream")] * 2
    + [diary("1800 s of audio in 150.0 s, front"), diary("3600 s of audio in 300.0 s, front"),
       diary("3000 s of audio in 150.0 s, background")]
    + [diary("first skip"), diary("head scan: the file cannot be read"),
       {"v": 1, "kind": "skip", "episode": "ab12cd34", "what": "play: ready"}]
)


class Setup(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.root, ignore_errors=True)
        self.mac = os.path.join(self.root, "mac")
        self.cloud = os.path.join(self.root, "cloud")
        self.said = []

    def put(self, folder, lines=SAMPLE, raw=None):
        directory = os.path.join(folder, "Podcasts")
        os.makedirs(directory, exist_ok=True)
        path = os.path.join(directory, "phone-diary.jsonl")
        with open(path, "wb") as f:
            f.write(raw if raw is not None else
                    "".join(json.dumps(line) + "\n" for line in lines).encode("utf-8"))
        return path

    def run_main(self, *extra):
        # The Mac's own copy comes first in the list, as apple_podcasts_export gives it.
        return pace.main(list(extra), say=self.said.append, defaults=lambda: [self.mac, self.cloud])

    def text(self):
        return "\n".join(self.said)


class ReadingTests(unittest.TestCase):
    def test_a_play_line_says_how_the_episode_stood(self):
        self.assertEqual(pace.read_line(json.dumps(diary("play: ready"))), ("play", "ready"))
        self.assertEqual(pace.read_line(json.dumps(diary("play: stream"))), ("play", "stream"))
        self.assertEqual(
            pace.read_line(json.dumps(diary("play: partly, transcript to 240 s"))),
            ("play", "partly"))

    def test_a_transcription_line_has_the_audio_the_work_and_where_it_ran(self):
        self.assertEqual(
            pace.read_line(json.dumps(diary("3600 s of audio in 214.3 s, front"))),
            ("speed", 3600.0, 214.3, "front"))
        self.assertEqual(
            pace.read_line(json.dumps(diary("180 s of audio in 9.0 s, background"))),
            ("speed", 180.0, 9.0, "background"))

    def test_other_lines_are_not_measurements(self):
        other = [
            json.dumps(diary("first skip")), json.dumps(diary("play: ready", kind="skip")),
            json.dumps(diary("play: someday")), json.dumps(diary("0 s of audio in 5.0 s, front")),
            json.dumps(diary("90 s of audio in 0.0 s, front")),
            json.dumps(diary("90 s of audio in 4.0 s, nowhere")),
            json.dumps({"kind": "diary", "time": 1}), json.dumps(diary(5)), "[]", "5", "{nope", "",
        ]
        for line in other:
            self.assertIsNone(pace.read_line(line), line)


class CountingTests(unittest.TestCase):
    def lines(self):
        return [json.dumps(line) for line in SAMPLE]

    def test_the_share_of_plays_that_were_ready(self):
        counted = pace.count(self.lines())
        self.assertEqual(counted.plays, {"ready": 7, "partly": 3, "stream": 2})
        self.assertAlmostEqual(counted.ready_share(), 7 / 12)

    def test_the_speech_pace_is_the_audio_over_the_work(self):
        counted = pace.count(self.lines())
        self.assertAlmostEqual(counted.speech(), 8400 / 600)
        self.assertAlmostEqual(counted.speech("front"), 12.0)
        self.assertAlmostEqual(counted.speech("background"), 20.0)
        self.assertEqual(counted.runs("front"), 2)

    def test_with_nothing_measured_the_numbers_are_none(self):
        counted = pace.count([json.dumps(diary("first skip"))])
        self.assertIsNone(counted.ready_share())
        self.assertIsNone(counted.speech())
        self.assertIsNone(counted.speech("front"))


class RunTests(Setup):
    def test_it_prints_the_share_of_ready_plays_and_the_speech_pace(self):
        self.put(self.cloud)
        self.assertEqual(self.run_main(), 0, self.said)
        text = self.text()
        self.assertIn("Plays that started: 12 (ready 7, partly 3, stream 2).", text)
        self.assertIn("Share of plays that were ready: 58% (7 of 12).", text)
        self.assertIn("Speech pace: 14.0 s of audio per second of work", text)
        self.assertIn("3 transcriptions", text)
        self.assertIn("front 12.0 (2 runs), background 20.0 (1 run)", text)

    def test_it_says_which_pace_to_replay_the_shelf_at(self):
        self.put(self.cloud)
        self.assertEqual(self.run_main(), 0, self.said)
        # A stream is played in front of the phone, so the front pace is the one to use.
        self.assertIn("score <teaching folder> --stream --speech 12", self.text())

    def test_the_overall_pace_is_the_one_to_replay_when_nothing_ran_in_front(self):
        self.put(self.cloud, [diary("3000 s of audio in 150.0 s, background")])
        self.assertEqual(self.run_main(), 0, self.said)
        self.assertIn("--stream --speech 20", self.text())
        self.assertIn("The diary has no play lines yet.", self.text())

    def test_a_diary_with_plays_and_no_transcriptions_says_so(self):
        self.put(self.cloud, [diary("play: ready"), diary("play: stream")])
        self.assertEqual(self.run_main(), 0, self.said)
        self.assertIn("Share of plays that were ready: 50% (1 of 2).", self.text())
        self.assertIn("no transcription is in the diary yet", self.text())
        self.assertNotIn("--speech", self.text())

    def test_the_icloud_copy_is_read_before_the_macs_own(self):
        self.put(self.mac, [diary("play: stream")])
        self.put(self.cloud, [diary("play: ready")])
        self.assertEqual(self.run_main(), 0, self.said)
        self.assertIn("Plays that started: 1 (ready 1, partly 0, stream 0).", self.text())

    def test_the_diary_option_reads_that_file(self):
        path = self.put(self.root, [diary("play: stream"), diary("play: stream")])
        self.assertEqual(self.run_main("--diary", path), 0, self.said)
        self.assertIn("Share of plays that were ready: 0% (0 of 2).", self.text())

    def test_a_line_that_is_not_json_is_skipped(self):
        self.put(self.cloud, raw=b'{"kind": "diary", "what": "play: ready"}\nnot json\n\xff\xfe\n')
        self.assertEqual(self.run_main(), 0, self.said)
        self.assertIn("1 of 1", self.text())

    def test_no_diary_is_not_an_error(self):
        self.assertEqual(self.run_main(), 0, self.said)
        self.assertIn("The phone has sent no diary yet", self.text())
        self.assertEqual(self.run_main("--diary", os.path.join(self.root, "none.jsonl")), 0)
        self.assertIn("There is no diary file at", self.said[-1])

    def test_a_diary_with_no_measurement_says_so(self):
        self.put(self.cloud, [diary("first skip")])
        self.assertEqual(self.run_main(), 0, self.said)
        self.assertIn("The diary has no play lines yet.", self.text())
        self.assertIn("no transcription is in the diary yet", self.text())

    def test_a_denied_folder_says_so_and_a_file_that_is_too_big_is_not_read(self):
        def stat(path, *args, **kwargs):
            raise PermissionError(1, "Operation not permitted")
        with mock.patch.object(pace.teach_feedback.os, "stat", stat):
            self.assertEqual(self.run_main(), 2)
        self.assertIn("Full Disk Access", self.text())
        self.said.clear()
        path = self.put(self.cloud)
        with mock.patch.object(pace, "FILE_LIMIT", 10):
            self.assertEqual(self.run_main(), 2)
        self.assertIn("too big", self.text())
        self.assertTrue(os.path.exists(path))


if __name__ == "__main__":
    unittest.main()
