"""Tests for the command line of teach_label.py: the confirmation, the exit codes, the lock and the
closing lines. A fake claude; no network. The folders claude is looked for in are injected, so a
claude installed on this Mac does not matter.
Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import json
import os
import shutil
import tempfile
import unittest
from types import SimpleNamespace

import teach_label as label
import teach_store as store
from teach_testing import FakeRunner, Teaching, answer, printed


class MainTests(unittest.TestCase):
    def setUp(self):
        self.said = []
        self.home = tempfile.mkdtemp()
        self.addCleanup(lambda: shutil.rmtree(self.home, ignore_errors=True))
        bin_folder = os.path.join(self.home, "bin")
        os.makedirs(bin_folder)
        self.claude = os.path.join(bin_folder, "claude")
        with open(self.claude, "w") as f:
            f.write("#!/bin/sh\n")
        os.chmod(self.claude, 0o755)
        self.environment = {"HOME": self.home, "PATH": bin_folder}

    def main(self, teaching, *options, typed="yes", runner=None):
        questions = []

        def ask_person(question):
            questions.append(question)
            return typed

        runner = runner or FakeRunner(stdout=printed(answer((1, 2))))
        code = label.main(["--folder", teaching.dir] + list(options), ask_person=ask_person,
                          runner=runner, environment=self.environment, say=self.said.append,
                          extra_folders=())
        return code, questions, runner

    def test_typed_yes_marks_everything(self):
        teaching = Teaching(self, 2)
        code, questions, runner = self.main(teaching)
        self.assertEqual((code, len(questions), len(runner.calls)), (0, 1, 2))
        self.assertEqual(len(teaching.labels()), 2)
        text = "\n".join(self.said)
        self.assertIn("2 episodes", text)
        self.assertIn("claude-opus-5-5", text)
        self.assertIn("estimate", text)
        self.assertIn("allowance", text)

    def test_the_model_option_reaches_claude(self):
        teaching = Teaching(self, 1)
        _, _, runner = self.main(teaching, "--model", "other-model")
        self.assertIn("other-model", runner.calls[0][0])

    def test_anything_but_yes_marks_nothing_and_has_its_own_exit_code(self):
        teaching = Teaching(self, 2)
        for typed in ("no", "", "y", "yes please"):
            self.said.clear()
            code, _, runner = self.main(teaching, typed=typed)
            self.assertEqual((code, len(runner.calls), teaching.labels()), (4, 0, []), typed)
            self.assertIn("Nothing was marked", self.said[-1])
        self.assertEqual(label.NOT_CONFIRMED, 4)

    def test_no_answer_at_all_is_not_confirmed(self):
        teaching = Teaching(self, 1)

        def closed(question):
            raise EOFError
        code = label.main(["--folder", teaching.dir], ask_person=closed, runner=FakeRunner(),
                          environment=self.environment, say=self.said.append, extra_folders=())
        self.assertEqual(code, 4)

    def test_yes_option_skips_the_question(self):
        teaching = Teaching(self, 1)
        code, questions, runner = self.main(teaching, "--yes")
        self.assertEqual((code, questions, len(runner.calls)), (0, [], 1))

    def test_nothing_waiting_is_fine_and_asks_nothing(self):
        teaching = Teaching(self, 1)
        self.main(teaching)
        code, questions, runner = self.main(teaching)
        self.assertEqual((code, questions, len(runner.calls)), (0, [], 0))

    def test_limit_reached_is_exit_zero(self):
        teaching = Teaching(self, 3)
        code, _, _ = self.main(teaching, "--limit", "1")
        self.assertEqual((code, len(teaching.labels())), (0, 1))

    def test_stopped_early_is_exit_three(self):
        teaching = Teaching(self, 3)
        limit = FakeRunner(stdout=printed("usage limit reached", is_error=True), returncode=1)
        self.assertEqual(self.main(teaching, runner=limit)[0], 3)
        cap = FakeRunner(stdout=printed(answer((1, 2)), cost=2.0))
        self.assertEqual(self.main(teaching, "--cap", "1.5", runner=cap)[0], 3)
        broken = FakeRunner(stdout="junk", returncode=1)
        teaching = Teaching(self, 4)
        self.assertEqual(self.main(teaching, runner=broken)[0], 3)

    def test_set_up_problems_are_exit_two(self):
        empty = SimpleNamespace(dir=tempfile.mkdtemp())
        self.addCleanup(lambda: shutil.rmtree(empty.dir, ignore_errors=True))
        self.assertEqual(self.main(empty)[0], 2)
        self.assertIn("Run the gather step first", self.said[-1])
        teaching = Teaching(self, 1)
        for bad in ("abc", "-1", "nan"):
            self.assertEqual(self.main(teaching, "--cap", bad)[0], 2, bad)
        self.environment["PATH"] = os.path.join(self.home, "nothing")
        self.assertEqual(self.main(teaching)[0], 2)

    def test_episodes_file_problems(self):
        teaching = Teaching(self, 1)
        path = os.path.join(teaching.dir, "episodes.json")
        for content in ("not json", json.dumps({"version": 2, "episodes": []}),
                        json.dumps({"version": 1, "episodes": "no"}), json.dumps([1])):
            with open(path, "w") as f:
                f.write(content)
            self.assertEqual(self.main(teaching)[0], 2, content)

    def test_entries_that_are_not_full_entries_are_refused_like_everywhere_else(self):
        teaching = Teaching(self, 1)
        with open(os.path.join(teaching.dir, "episodes.json"), "w") as f:
            json.dump({"version": 1, "episodes": [{"id": "000000000001", "feed": "f", "show": "s",
                                                   "title": "t"}]}, f)
        self.assertEqual(self.main(teaching)[0], 2)

    def test_a_second_run_in_the_same_folder_is_refused_before_anything_is_asked(self):
        teaching = Teaching(self, 2)
        with store.run_lock(teaching.dir):
            code, questions, runner = self.main(teaching)
        self.assertEqual((code, questions, len(runner.calls), teaching.labels()), (2, [], 0, []))
        self.assertEqual(self.said[-1], store.BUSY)

    def test_the_lock_is_free_after_a_run(self):
        teaching = Teaching(self, 1)
        self.main(teaching)
        with store.run_lock(teaching.dir):
            pass

    def test_the_closing_lines_say_how_many_were_given_up_on(self):
        teaching = Teaching(self, 3)
        with open(teaching.path("failures.json"), "w") as f:
            json.dump({"version": 1, "label": {teaching.entries[0]["id"]: 3}}, f)
        code, _, runner = self.main(teaching)
        self.assertEqual((code, len(runner.calls), len(teaching.labels())), (0, 2, 2))
        self.assertIn("1 episode was given up on", self.said[-1])
        self.assertIn("--retry-failed", self.said[-1])
        code, _, runner = self.main(teaching, "--retry-failed")
        self.assertEqual((code, len(runner.calls), len(teaching.labels())), (0, 1, 3))

    def test_nothing_to_do_still_names_the_ones_given_up_on(self):
        teaching = Teaching(self, 1)
        with open(teaching.path("failures.json"), "w") as f:
            json.dump({"version": 1, "label": {teaching.entries[0]["id"]: 3}}, f)
        code, questions, _ = self.main(teaching)
        self.assertEqual((code, questions), (0, []))
        self.assertIn("given up on", self.said[-1])

    def test_a_failed_calls_cost_is_in_the_reported_total(self):
        teaching = Teaching(self, 4)
        runner = FakeRunner(stdout=printed("broken", cost=2.0, is_error=True), returncode=1)
        code, _, _ = self.main(teaching, "--cap", "3.5", runner=runner)
        self.assertEqual(code, 3)
        self.assertTrue(any("Cost as Claude counts it: $4.00" in line for line in self.said), self.said)


if __name__ == "__main__":
    unittest.main()
