"""Tests for teach_words.py: reading the word-time side file next to a transcript, matching its lines
to the transcript's lines, and writing the side files down again for the shelf (with a fake
transcriber). Only made-up lines are used. Run: python3 -m unittest discover -s
libraries/PodcastKit/Tools/mac"""
import json
import os
import subprocess
import tempfile
import unittest

import teach_store as store
import teach_words as words


def side(lines, version=1):
    """A side file: `lines` is [(start, end)], and every line gets one word of its own length."""
    return {"version": version, "duration": 100.0, "lines": [list(item) for item in lines],
            "words": [list(item) for item in lines]}


def entry(number, audio=True):
    identifier = "%012x" % number
    return {"id": identifier, "feed": "https://f", "show": "Show", "guid": "", "title": "Episode %d" % number,
            "published": None, "seconds": None, "address": "https://a/%d.mp3" % number, "size": None,
            "file": "audio/%s.mp3" % identifier if audio else None, "bytes": 1 if audio else 0,
            "sha256": None, "host": None, "error": None}


class LineEndsTests(unittest.TestCase):
    TEXT = [(0.0, "a"), (12.3, "b"), (30.0, "c")]

    def test_each_line_gets_the_end_of_its_last_word(self):
        # The transcript prints a start cut to a tenth (12.34 is 12.3); the side file is exact.
        data = side([(0.0, 5.123), (12.34, 20.456), (30.0, 41.0)])
        self.assertEqual(words.line_ends(self.TEXT, data), [5.123, 20.456, 41.0])

    def test_a_line_that_is_not_in_the_side_file_gets_none(self):
        data = side([(0.0, 5.0), (30.0, 41.0)])
        self.assertEqual(words.line_ends(self.TEXT, data), [5.0, None, 41.0])

    def test_a_start_that_is_far_from_every_line_is_not_matched(self):
        data = side([(0.5, 5.0), (12.9, 20.0), (30.5, 41.0)])
        self.assertEqual(words.line_ends(self.TEXT, data), [None, None, None])

    def test_two_lines_never_share_one_entry(self):
        data = side([(12.34, 20.0)])
        self.assertEqual(words.line_ends([(12.3, "a"), (12.3, "b")], data), [20.0, None])


class ReadTests(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.dir.cleanup)
        os.makedirs(os.path.join(self.dir.name, "transcripts"))

    def put(self, text):
        with open(words.words_path(self.dir.name, "a" * 12), "w", encoding="utf-8") as handle:
            handle.write(text)

    def test_the_path_is_next_to_the_transcript(self):
        self.assertEqual(words.words_path("F", "abc"), os.path.join("F", "transcripts", "abc.words.json"))

    def test_no_file_gives_none(self):
        self.assertIsNone(words.word_ends(self.dir.name, "a" * 12, [(0.0, "a")]))

    def test_a_damaged_or_other_version_file_gives_none(self):
        for text in ("{", "[]", json.dumps(side([(0.0, 1.0)], version=2)),
                     json.dumps({"version": 1, "lines": [[0.0]]}),
                     json.dumps({"version": 1, "lines": [[0.0, "x"]]}),
                     json.dumps({"version": 1, "lines": [[0.0, float("nan")]]})):
            self.put(text)
            self.assertIsNone(words.word_ends(self.dir.name, "a" * 12, [(0.0, "a")]), text)

    def test_a_good_file_gives_the_ends(self):
        self.put(json.dumps(side([(0.0, 4.5)])))
        self.assertEqual(words.word_ends(self.dir.name, "a" * 12, [(0.0, "a")]), [4.5])


class FakeRunner:
    """Stands in for subprocess.run: writes a side file to the path after --words."""
    def __init__(self, fail=(), write=True):
        self.fail, self.write, self.calls = set(fail), write, []

    def __call__(self, command, **options):
        self.calls.append((command, options))
        audio = command[-1]
        if os.path.basename(audio) in self.fail:
            return subprocess.CompletedProcess(command, 1, stderr="no speech model\n")
        if self.write:
            with open(command[command.index("--words") + 1], "w", encoding="utf-8") as handle:
                json.dump(side([(0.0, 1.0)]), handle)
        return subprocess.CompletedProcess(command, 0, stderr="100%\n")


class RedoTests(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.dir.cleanup)
        self.folder = self.dir.name
        os.makedirs(os.path.join(self.folder, "audio"))
        os.makedirs(os.path.join(self.folder, "transcripts"))
        self.said = []

    def add(self, entries, shelf):
        for item in entries:
            if item["file"]:
                with open(os.path.join(self.folder, item["file"]), "wb") as handle:
                    handle.write(b"x")
        store.save_manifest(self.folder, entries)
        with open(os.path.join(self.folder, "shelf.json"), "w", encoding="utf-8") as handle:
            json.dump({"version": 1, "episodes": shelf}, handle)

    def run_redo(self, runner, **options):
        return words.run(self.folder, "tool", "en-US", runner=runner, say=self.said.append, **options)

    def test_writes_the_side_file_of_each_shelf_episode_and_leaves_the_transcript_alone(self):
        episodes = [entry(1), entry(2)]
        self.add(episodes, [episodes[0]["id"], episodes[1]["id"]])
        text = os.path.join(self.folder, "transcripts", episodes[0]["id"] + ".txt")
        with open(text, "w", encoding="utf-8") as handle:
            handle.write("[00:00:01.0] hello\n")
        runner = FakeRunner()
        result = self.run_redo(runner)
        self.assertEqual((result["done"], result["failed"], result["left"]), (2, 0, 0))
        for item in episodes:
            self.assertTrue(os.path.exists(words.words_path(self.folder, item["id"])))
        with open(text, encoding="utf-8") as handle:
            self.assertEqual(handle.read(), "[00:00:01.0] hello\n")
        self.assertEqual(os.listdir(os.path.join(self.folder, "transcripts")).count(
            episodes[1]["id"] + ".txt"), 0, "no transcript is made for an episode that had none")
        command = runner.calls[0][0]
        self.assertEqual((command[0], command[1:3], command[3]), ("tool", ["--locale", "en-US"], "--words"))

    def test_an_episode_that_has_its_side_file_is_skipped(self):
        episodes = [entry(1), entry(2)]
        self.add(episodes, [e["id"] for e in episodes])
        with open(words.words_path(self.folder, episodes[0]["id"]), "w", encoding="utf-8") as handle:
            json.dump(side([(0.0, 1.0)]), handle)
        runner = FakeRunner()
        result = self.run_redo(runner)
        self.assertEqual((result["done"], len(runner.calls)), (1, 1))
        self.assertTrue(runner.calls[0][0][-1].endswith(episodes[1]["id"] + ".mp3"))

    def test_only_the_shelf_is_written_down_unless_everything_is_asked_for(self):
        episodes = [entry(1), entry(2)]
        self.add(episodes, [episodes[0]["id"]])
        self.assertEqual(self.run_redo(FakeRunner())["done"], 1)
        self.assertEqual(self.run_redo(FakeRunner(), everything=True)["done"], 1)

    def test_an_episode_without_audio_is_counted_and_left_out(self):
        episodes = [entry(1, audio=False), entry(2)]
        self.add(episodes, [e["id"] for e in episodes])
        result = self.run_redo(FakeRunner())
        self.assertEqual((result["done"], result["no_audio"]), (1, 1))
        self.assertTrue(any("no audio" in line for line in self.said))

    def test_limit_stops_early(self):
        episodes = [entry(n) for n in (1, 2, 3)]
        self.add(episodes, [e["id"] for e in episodes])
        result = self.run_redo(FakeRunner(), limit=2)
        self.assertEqual((result["done"], result["left"]), (2, 1))

    def test_a_failure_leaves_no_file_and_three_in_a_row_stop_the_run(self):
        episodes = [entry(n) for n in (1, 2, 3, 4)]
        self.add(episodes, [e["id"] for e in episodes])
        runner = FakeRunner(fail=[os.path.basename(e["file"]) for e in episodes[:3]])
        result = self.run_redo(runner)
        self.assertEqual((result["failed"], result["stopped"], len(runner.calls)), (3, True, 3))
        self.assertEqual(os.listdir(os.path.join(self.folder, "transcripts")), [])

    def test_a_tool_that_wrote_no_side_file_is_a_failure(self):
        episodes = [entry(1)]
        self.add(episodes, [episodes[0]["id"]])
        result = self.run_redo(FakeRunner(write=False))
        self.assertEqual((result["done"], result["failed"]), (0, 1))

    def test_a_missing_shelf_means_nothing_is_written_down(self):
        store.save_manifest(self.folder, [entry(1)])
        result = self.run_redo(FakeRunner())
        self.assertEqual((result["done"], result["left"]), (0, 0))


class MainTests(unittest.TestCase):
    def test_a_tool_that_is_missing_is_a_set_up_problem(self):
        with tempfile.TemporaryDirectory() as folder:
            lines = []
            code = words.main(["--tool", os.path.join(folder, "none"), "--folder", folder], say=lines.append)
            self.assertEqual(code, 2)
            self.assertIn("missing", lines[0])

    def test_no_episode_list_is_a_set_up_problem(self):
        with tempfile.TemporaryDirectory() as folder:
            tool = os.path.join(folder, "tool")
            with open(tool, "w", encoding="utf-8") as handle:
                handle.write("#!/bin/sh\n")
            os.chmod(tool, 0o755)
            lines = []
            self.assertEqual(words.main(["--tool", tool, "--folder", folder], say=lines.append), 2)
            self.assertIn("episodes.json", lines[0])


if __name__ == "__main__":
    unittest.main()
