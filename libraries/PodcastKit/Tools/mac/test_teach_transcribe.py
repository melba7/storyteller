"""Tests for teach_transcribe.py: which episodes are waiting, running the transcriber (a fake one),
the progress lines, stopping after three failures in a row, and the exit codes. No real program
is run. Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import json
import os
import subprocess
import tempfile
import unittest

import teach_store as store
import teach_transcribe as tt


def entry(number, audio=True, size=1000):
    identifier = "%012x" % number
    return {"id": identifier, "feed": "https://f", "show": "Show", "guid": "", "title": "Episode %d" % number,
            "published": None, "seconds": None, "address": "https://a/%d.mp3" % number, "size": None,
            "file": "audio/%s.mp3" % identifier if audio else None, "bytes": size if audio else 0,
            "sha256": None, "host": None, "error": None}


class Completed:
    def __init__(self, code=0, stderr=""):
        self.returncode = code
        self.stderr = stderr


class FakeRunner:
    """Stands in for subprocess.run: writes `text` to the stdout file, or fails for the audio files
    whose names are in `fail`."""
    def __init__(self, text="[00:00:01.0] hello\n", fail=(), stderr="progress 100%\n"):
        self.text, self.fail, self.stderr, self.calls = text, set(fail), stderr, []

    def __call__(self, command, **options):
        self.calls.append(command)
        if os.path.basename(command[-1]) in self.fail:
            return Completed(1, "line1\nline2\nline3\nline4\nline5\nline6\nSpeech model missing\n")
        options["stdout"].write(self.text)
        return Completed(0, self.stderr)


class Base(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.dir.cleanup)
        self.folder = self.dir.name
        os.makedirs(os.path.join(self.folder, "audio"))
        self.lines = []
        self.clock_value = 0.0

    def clock(self):
        self.clock_value += 60.0
        return self.clock_value

    def add(self, entries):
        for item in entries:
            if item["file"]:
                with open(os.path.join(self.folder, item["file"]), "wb") as handle:
                    handle.write(b"x")
        store.save_manifest(self.folder, entries)

    def transcript(self, item):
        return os.path.join(self.folder, "transcripts", item["id"] + ".txt")

    def run_all(self, runner, limit=None):
        return tt.run(self.folder, "tool", "en-US", limit, runner=runner, clock=self.clock, say=self.lines.append)


class PendingTests(Base):
    def test_rules(self):
        entries = [entry(1), entry(2, audio=False), entry(3), entry(4), entry(5)]
        self.add(entries)
        os.remove(os.path.join(self.folder, entries[2]["file"]))  # the audio is gone
        os.makedirs(os.path.join(self.folder, "transcripts"))
        with open(self.transcript(entries[3]), "w") as handle:  # already transcribed
            handle.write("x")
        self.assertEqual([e["id"] for e in tt.pending(self.folder, entries)], [entries[0]["id"], entries[4]["id"]])


class TranscribeOneTests(Base):
    def setUp(self):
        super().setUp()
        self.audio = os.path.join(self.folder, "audio", "a.mp3")
        self.out = os.path.join(self.folder, "a.txt")

    def test_success_writes_transcript_without_part(self):
        runner = FakeRunner()
        tt.transcribe_one("tool", self.audio, self.out, "de-DE", runner=runner)
        self.assertEqual(runner.calls, [["tool", "--locale", "de-DE", self.audio]])
        with open(self.out, encoding="utf-8") as handle:
            self.assertEqual(handle.read(), "[00:00:01.0] hello\n")
        self.assertFalse(os.path.exists(self.out + ".part"))

    def test_failure_reports_the_tail_of_stderr(self):
        runner = FakeRunner(fail=["a.mp3"])
        with self.assertRaises(RuntimeError) as caught:
            tt.transcribe_one("tool", self.audio, self.out, "en-US", runner=runner)
        message = str(caught.exception)
        self.assertIn("Speech model missing", message)
        self.assertIn("line3", message)
        self.assertNotIn("line1", message)
        self.assertFalse(os.path.exists(self.out))
        self.assertFalse(os.path.exists(self.out + ".part"))

    def test_empty_output_is_a_failure(self):
        with self.assertRaises(RuntimeError):
            tt.transcribe_one("tool", self.audio, self.out, "en-US", runner=FakeRunner(text=""))
        self.assertFalse(os.path.exists(self.out))
        self.assertFalse(os.path.exists(self.out + ".part"))

    def test_timeout_is_a_failure(self):
        def slow(command, **options):
            raise subprocess.TimeoutExpired(command, 1)
        with self.assertRaises(RuntimeError):
            tt.transcribe_one("tool", self.audio, self.out, "en-US", runner=slow)
        self.assertFalse(os.path.exists(self.out + ".part"))


class RunTests(Base):
    def test_transcribes_everything_pending_and_prints_progress(self):
        entries = [entry(n) for n in range(1, 4)]
        self.add(entries)
        result = self.run_all(FakeRunner())
        self.assertEqual((result["done"], result["failed"], result["stopped"]), (3, 0, False))
        self.assertTrue(all(os.path.exists(self.transcript(e)) for e in entries))
        text = "\n".join(self.lines)
        self.assertIn("[1/3] Show: Episode 1", text)
        self.assertIn("[3/3] Show: Episode 3", text)
        self.assertIn("left", text)

    def test_limit(self):
        self.add([entry(n) for n in range(1, 5)])
        runner = FakeRunner()
        result = self.run_all(runner, limit=2)
        self.assertEqual((result["done"], len(runner.calls)), (2, 2))
        self.assertIn("[2/2]", "\n".join(self.lines))

    def test_a_failure_is_reported_and_the_run_carries_on(self):
        entries = [entry(n) for n in range(1, 4)]
        self.add(entries)
        runner = FakeRunner(fail=[os.path.basename(entries[1]["file"])])
        result = self.run_all(runner)
        self.assertEqual((result["done"], result["failed"], result["stopped"]), (2, 1, False))
        self.assertIn("Speech model missing", "\n".join(self.lines))
        self.assertFalse(os.path.exists(self.transcript(entries[1])))

    def test_three_failures_in_a_row_stop_the_run(self):
        entries = [entry(n) for n in range(1, 7)]
        self.add(entries)
        runner = FakeRunner(fail=[os.path.basename(e["file"]) for e in entries[:3]])
        result = self.run_all(runner)
        self.assertEqual((result["done"], result["failed"], result["stopped"]), (0, 3, True))
        self.assertEqual(len(runner.calls), 3)

    def test_failures_that_are_not_in_a_row_do_not_stop_it(self):
        entries = [entry(n) for n in range(1, 8)]
        self.add(entries)
        fail = [os.path.basename(entries[n]["file"]) for n in (0, 1, 3, 4)]
        result = self.run_all(FakeRunner(fail=fail))
        self.assertEqual((result["done"], result["failed"], result["stopped"]), (3, 4, False))

    def test_a_later_run_does_only_what_is_left(self):
        entries = [entry(n) for n in range(1, 4)]
        self.add(entries)
        self.run_all(FakeRunner(), limit=1)
        runner = FakeRunner()
        result = self.run_all(runner)
        self.assertEqual(result["done"], 2)
        self.assertEqual(len(runner.calls), 2)
        self.assertEqual(self.run_all(FakeRunner())["done"], 0)

    def test_time_left_in_words(self):
        self.assertEqual(tt.how_long(12000), "3 h 20 min")
        self.assertEqual(tt.how_long(300), "5 min")
        self.assertEqual(tt.how_long(40), "under a minute")


class MainTests(Base):
    def setUp(self):
        super().setUp()
        self.tool = os.path.join(self.folder, "podcast-transcribe")
        with open(self.tool, "w") as handle:
            handle.write("#!/bin/sh\n")
        os.chmod(self.tool, 0o755)

    def main(self, *extra, runner=None):
        return tt.main(["--tool", self.tool, "--folder", self.folder] + list(extra),
                       runner=runner or FakeRunner(), clock=self.clock, say=self.lines.append)

    def test_nothing_to_do_is_0(self):
        self.add([])
        self.assertEqual(self.main(), 0)

    def test_everything_done_is_0(self):
        self.add([entry(1)])
        self.assertEqual(self.main(), 0)

    def test_no_manifest_is_2(self):
        self.assertEqual(self.main(), 2)

    def test_damaged_manifest_is_2(self):
        with open(os.path.join(self.folder, "episodes.json"), "w") as handle:
            json.dump({"version": 9}, handle)
        self.assertEqual(self.main(), 2)

    def test_missing_tool_is_2(self):
        self.add([entry(1)])
        os.remove(self.tool)
        self.assertEqual(self.main(), 2)

    def test_tool_that_cannot_run_is_2(self):
        self.add([entry(1)])
        os.chmod(self.tool, 0o644)
        self.assertEqual(self.main(), 2)

    def test_a_second_run_in_the_same_folder_is_refused_with_exit_2(self):
        self.add([entry(1)])
        runner = FakeRunner()
        with store.run_lock(self.folder):
            self.assertEqual(self.main(runner=runner), 2)
        self.assertEqual((runner.calls, self.lines), ([], [store.BUSY]))

    def test_stopping_after_failures_is_3(self):
        entries = [entry(n) for n in range(1, 5)]
        self.add(entries)
        runner = FakeRunner(fail=[os.path.basename(e["file"]) for e in entries])
        self.assertEqual(self.main(runner=runner), 3)


if __name__ == "__main__":
    unittest.main()
