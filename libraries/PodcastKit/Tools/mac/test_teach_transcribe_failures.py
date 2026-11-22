"""Tests for the memory of failures in teach_transcribe.py: failed episodes come last, only a first
failure counts towards three in a row, three failures give an episode up, --retry-failed asks for
it again. A fake transcriber; no real program.
Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import json
import os

import teach_transcribe as tt
from test_teach_transcribe import Base, FakeRunner, entry


class FailureMemoryTests(Base):
    def names(self, entries, *numbers):
        return [os.path.basename(entries[n - 1]["file"]) for n in numbers]

    def remembered(self, step="transcribe"):
        with open(os.path.join(self.folder, "failures.json"), encoding="utf-8") as handle:
            return json.load(handle)[step]

    def test_failures_are_remembered_and_forgotten_when_the_episode_succeeds(self):
        entries = [entry(n) for n in range(1, 4)]
        self.add(entries)
        self.run_all(FakeRunner(fail=self.names(entries, 1, 2)))
        self.assertEqual(self.remembered(), {entries[0]["id"]: 1, entries[1]["id"]: 1})
        self.run_all(FakeRunner())
        self.assertEqual(self.remembered(), {})

    def test_the_same_three_failing_episodes_do_not_stall_every_later_run(self):
        entries = [entry(n) for n in range(1, 9)]
        self.add(entries)
        runner = FakeRunner(fail=self.names(entries, 1, 2, 3))
        self.assertTrue(self.run_all(runner)["stopped"])
        runner = FakeRunner(fail=self.names(entries, 1, 2, 3))
        result = self.run_all(runner)
        self.assertEqual((result["done"], result["failed"], result["stopped"]), (5, 3, False))
        self.assertEqual([os.path.basename(c[-1]) for c in runner.calls[:5]], self.names(entries, 4, 5, 6, 7, 8))

    def test_only_a_first_failure_counts_towards_three_in_a_row(self):
        entries = [entry(n) for n in range(1, 7)]
        self.add(entries)
        self.run_all(FakeRunner(fail=self.names(entries, 1, 2)), limit=2)
        # Order now: 3 to 6 (never failed), then 1 and 2. 5 and 6 fail for the first time, then 1
        # and 2 fail again: four failures at the end, but only two of them are new.
        result = self.run_all(FakeRunner(fail=self.names(entries, 1, 2, 5, 6)))
        self.assertEqual((result["done"], result["failed"], result["stopped"]), (2, 4, False))

    def test_an_episode_that_failed_three_times_is_left_out_and_counted(self):
        entries = [entry(n) for n in range(1, 4)]
        self.add(entries)
        with open(os.path.join(self.folder, "failures.json"), "w") as handle:
            json.dump({"version": 1, "transcribe": {entries[0]["id"]: 3}, "label": {}}, handle)
        runner = FakeRunner()
        result = self.run_all(runner)
        self.assertEqual((result["done"], result["given_up"], len(runner.calls)), (2, 1, 2))
        self.assertFalse(os.path.exists(self.transcript(entries[0])))

    def test_retry_failed_includes_them_once_more_and_success_forgets_them(self):
        entries = [entry(n) for n in range(1, 4)]
        self.add(entries)
        with open(os.path.join(self.folder, "failures.json"), "w") as handle:
            json.dump({"version": 1, "transcribe": {entries[0]["id"]: 3}, "label": {}}, handle)
        result = tt.run(self.folder, "tool", "en-US", None, runner=FakeRunner(), clock=self.clock,
                        say=self.lines.append, retry_failed=True)
        self.assertEqual((result["done"], result["given_up"]), (3, 0))
        self.assertEqual(self.remembered(), {})

    def test_the_label_steps_counts_are_not_touched(self):
        entries = [entry(1)]
        self.add(entries)
        with open(os.path.join(self.folder, "failures.json"), "w") as handle:
            json.dump({"version": 1, "transcribe": {}, "label": {"aaaaaaaaaaaa": 2}}, handle)
        self.run_all(FakeRunner(fail=self.names(entries, 1)))
        self.assertEqual(self.remembered("label"), {"aaaaaaaaaaaa": 2})

    def main(self, *extra):
        tool = os.path.join(self.folder, "podcast-transcribe")
        with open(tool, "w") as handle:
            handle.write("#!/bin/sh\n")
        os.chmod(tool, 0o755)
        return tt.main(["--tool", tool, "--folder", self.folder] + list(extra), runner=FakeRunner(),
                       clock=self.clock, say=self.lines.append)

    def test_the_closing_lines_name_how_many_were_given_up_on(self):
        entries = [entry(1), entry(2)]
        self.add(entries)
        with open(os.path.join(self.folder, "failures.json"), "w") as handle:
            json.dump({"version": 1, "transcribe": {entries[0]["id"]: 3}, "label": {}}, handle)
        self.assertEqual(self.main(), 0)
        self.assertIn("1 episode was given up on", self.lines[-1])
        self.assertIn("--retry-failed", self.lines[-1])
        self.lines.clear()
        self.assertEqual(self.main("--retry-failed"), 0)
        self.assertFalse(any("given up" in line for line in self.lines))
        self.assertTrue(os.path.exists(self.transcript(entries[0])))
