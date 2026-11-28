"""Tests for the end of a label computed from the exact end of its last line (teach_segments.with_times
with `ends`), and for teach_transcribe writing the word-time side file. Made-up lines only.
Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import json
import os
import subprocess
import tempfile
import unittest

import teach_label as label
import teach_segments as seg
import teach_transcribe as tt
from teach_testing import Teaching, answer, entry, transcript


def line(first, last=None):
    return {"first": first, "last": last or first, "sort": "sponsor", "who": "", "delivery": "host",
            "confidence": "high", "why": ""}


class WithTimesEndsTests(unittest.TestCase):
    LINES = [(0.0, "a"), (10.04, "b"), (20.0, "c"), (31.26, "d")]
    ENDS = [4.0, 18.46, 28.9, 33.77]

    def test_the_end_is_the_end_of_the_last_word_of_the_last_line(self):
        out = seg.with_times([line(2, 3)], self.LINES, self.ENDS)
        self.assertEqual((out[0]["start"], out[0]["end"]), (10.0, 28.9))

    def test_the_last_line_of_the_transcript_uses_its_word_end_too(self):
        out = seg.with_times([line(3, 4)], self.LINES, self.ENDS)
        self.assertEqual(out[0]["end"], 33.8)

    def test_a_line_with_no_exact_end_keeps_the_next_lines_start(self):
        out = seg.with_times([line(2, 3)], self.LINES, [4.0, 18.46, None, 33.77])
        self.assertEqual(out[0]["end"], 31.3)

    def test_an_end_that_is_not_after_the_start_is_not_used(self):
        out = seg.with_times([line(3, 3)], self.LINES, [4.0, 18.46, 19.0, 33.77])
        self.assertEqual(out[0]["end"], 31.3)

    def test_without_ends_it_is_as_before(self):
        out = seg.with_times([line(2, 3)], self.LINES)
        self.assertEqual(out[0]["end"], 31.3)

    def test_ends_that_do_not_fit_the_lines_are_ignored(self):
        out = seg.with_times([line(2, 3)], self.LINES, [1.0])
        self.assertEqual(out[0]["end"], 31.3)


class Done:
    def __init__(self, code=0, stderr=""):
        self.returncode, self.stderr = code, stderr


class TranscribeWordsTests(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.dir.cleanup)
        self.audio = os.path.join(self.dir.name, "a.mp3")
        self.out = os.path.join(self.dir.name, "a.txt")
        self.words = os.path.join(self.dir.name, "a.words.json")

    def runner(self, write_words=True, code=0):
        calls = []

        def run(command, **options):
            calls.append(command)
            options["stdout"].write("[00:00:01.0] hello\n")
            if write_words and "--words" in command:
                with open(command[command.index("--words") + 1], "w", encoding="utf-8") as handle:
                    json.dump({"version": 1, "lines": [], "words": []}, handle)
            return Done(code)
        run.calls = calls
        return run

    def test_asks_the_tool_for_the_side_file_and_keeps_it_next_to_the_transcript(self):
        run = self.runner()
        tt.transcribe_one("tool", self.audio, self.out, "en-US", runner=run, words=self.words)
        command = run.calls[0]
        self.assertEqual(command[:3], ["tool", "--locale", "en-US"])
        self.assertEqual(command[3], "--words")
        self.assertEqual(command[-1], self.audio)
        self.assertTrue(os.path.exists(self.out) and os.path.exists(self.words))
        self.assertEqual(sorted(os.listdir(self.dir.name)), ["a.txt", "a.words.json"])

    def test_without_words_the_command_is_as_before(self):
        run = self.runner()
        tt.transcribe_one("tool", self.audio, self.out, "en-US", runner=run)
        self.assertEqual(run.calls[0], ["tool", "--locale", "en-US", self.audio])

    def test_a_tool_that_made_no_side_file_still_gives_the_transcript(self):
        tt.transcribe_one("tool", self.audio, self.out, "en-US", runner=self.runner(write_words=False),
                          words=self.words)
        self.assertTrue(os.path.exists(self.out))
        self.assertFalse(os.path.exists(self.words))

    def test_a_failed_run_leaves_neither_file_nor_part(self):
        with self.assertRaises(RuntimeError):
            tt.transcribe_one("tool", self.audio, self.out, "en-US", runner=self.runner(code=1),
                              words=self.words)
        self.assertEqual(os.listdir(self.dir.name), [])

    def test_a_timeout_leaves_nothing(self):
        def slow(command, **options):
            raise subprocess.TimeoutExpired(command, 1)
        with self.assertRaises(RuntimeError):
            tt.transcribe_one("tool", self.audio, self.out, "en-US", runner=slow, words=self.words)
        self.assertEqual(os.listdir(self.dir.name), [])


class LabelEndsTests(unittest.TestCase):
    ask = staticmethod(lambda prompt: {"text": answer((2, 4)), "cost": 0.1})

    def test_label_episode_ends_a_label_where_its_last_word_ends(self):
        lines = seg.read_transcript(transcript(10))
        ends = [n + 0.8 for n in range(10)]
        made = label.label_episode(entry(1), lines, "m", self.ask, ends=ends)
        self.assertEqual((made["segments"][0]["start"], made["segments"][0]["end"]), (1.0, 3.8))

    def test_label_episode_without_ends_ends_at_the_next_line(self):
        lines = seg.read_transcript(transcript(10))
        made = label.label_episode(entry(1), lines, "m", self.ask)
        self.assertEqual(made["segments"][0]["end"], 4.0)

    def test_a_run_uses_the_side_file_when_the_episode_has_one(self):
        teaching = Teaching(self, 2)
        first, second = teaching.entries
        side = {"version": 1, "duration": 10.0, "lines": [[n, n + 0.8] for n in range(10)], "words": []}
        with open(teaching.path("transcripts", first["id"] + ".words.json"), "w") as handle:
            json.dump(side, handle)
        label.run(teaching.dir, "labels", "m", None, None, self.ask, say=lambda text: None)
        ends = []
        for item in (first, second):
            with open(teaching.label_path(item)) as handle:
                ends.append(json.load(handle)["segments"][0]["end"])
        self.assertEqual(ends, [3.8, 4.0])


if __name__ == "__main__":
    unittest.main()
