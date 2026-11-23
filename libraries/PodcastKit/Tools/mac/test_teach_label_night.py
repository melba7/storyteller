"""Tests for the night marking in teach_label.py: --only-exam, --between, --wait-hours and the
opening message. A fake claude, a fake clock, no real waiting.
Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import os
import shutil
import tempfile
import unittest
from datetime import datetime, timedelta

import teach_claude as claude
import teach_exam
import teach_label as label
import teach_night as night
from teach_testing import FakeRunner, Teaching, answer, printed
from test_teach_night import FakeTime


def run(teaching, ask, waiter=None, **more):
    said = []
    result = label.run(teaching.dir, more.pop("labels", "labels"), "m", more.pop("limit", None),
                       more.pop("cap", None), ask, say=said.append, waiter=waiter, **more)
    return result, said


class OnlyExamTests(unittest.TestCase):
    def test_only_exam_episodes_are_marked_in_the_order_of_exam_json(self):
        teaching = Teaching(self, 4)
        ids = [e["id"] for e in teaching.entries]
        teach_exam.add_to_exam(teaching.dir, [ids[2], ids[0]])
        asked = []

        def ask(prompt):
            asked.append(prompt)
            return {"text": answer((1, 2)), "cost": 0.1}

        result, _ = run(teaching, ask, only_exam=True)
        self.assertEqual(result["done"], 2)
        self.assertEqual(teaching.labels(), sorted([ids[0] + ".json", ids[2] + ".json"]))
        self.assertIn("Episode 3", asked[0])
        self.assertIn("Episode 1", asked[1])

    def test_without_the_option_exam_episodes_are_marked_like_the_rest(self):
        teaching = Teaching(self, 2)
        teach_exam.add_to_exam(teaching.dir, [teaching.entries[0]["id"]])
        result, _ = run(teaching, lambda prompt: {"text": answer((1, 2)), "cost": 0.0})
        self.assertEqual(result["done"], 2)

    def test_the_second_marking_goes_to_its_own_folder_and_respects_the_limit(self):
        teaching = Teaching(self, 4)
        teach_exam.add_to_exam(teaching.dir, [e["id"] for e in teaching.entries])
        ask = lambda prompt: {"text": answer((1, 2)), "cost": 0.0}  # noqa: E731
        run(teaching, ask, only_exam=True)
        result, _ = run(teaching, ask, labels="labels-second", limit=2, only_exam=True)
        self.assertEqual((result["done"], result["stop"]), (2, "limit"))
        self.assertEqual(len(teaching.labels("labels-second")), 2)
        self.assertEqual(teaching.labels("labels-second"),
                         sorted(e["id"] + ".json" for e in teaching.entries[:2]))


class WindowTests(unittest.TestCase):
    def test_the_clock_is_checked_before_every_episode(self):
        teaching = Teaching(self, 4)
        fake = FakeTime(22)
        started = []

        def ask(prompt):
            started.append(fake.now)
            fake.now += timedelta(hours=3)
            return {"text": answer((1, 2)), "cost": 0.0}

        waiter = night.Waiter((23, 7), None, fake.clock, fake.sleep, lambda line: None)
        result, _ = run(teaching, ask, waiter)
        self.assertEqual(result["done"], 4)
        self.assertEqual(started, [datetime(2026, 1, 10, 23), datetime(2026, 1, 11, 2),
                                   datetime(2026, 1, 11, 5), datetime(2026, 1, 11, 23)])

    def test_a_stop_by_the_cap_does_not_wait_for_the_night(self):
        teaching = Teaching(self, 3)
        fake = FakeTime(23)
        waiter = night.Waiter((23, 7), None, fake.clock, fake.sleep, lambda line: None)

        def ask(prompt):
            fake.now = datetime(2026, 1, 10, 12)  # the work took until noon
            return {"text": answer((1, 2)), "cost": 2.0}

        result, _ = run(teaching, ask, waiter, cap=1.0)
        self.assertEqual((result["done"], result["stop"]), (1, "cap"))
        self.assertEqual(fake.naps, [])


class AllowanceTests(unittest.TestCase):
    def limited(self, times, cost=0.0, message="usage limit reached"):
        """An ask that hits the usage limit `times` times, then marks."""
        state = {"left": times, "prompts": []}

        def ask(prompt):
            state["prompts"].append(prompt)
            if state["left"]:
                state["left"] -= 1
                error = claude.UsageLimit(message)
                error.cost = cost
                raise error
            return {"text": answer((1, 2)), "cost": 0.1}
        ask.state = state
        return ask

    def waiter(self, fake, hours):
        return night.Waiter(None, hours, fake.clock, fake.sleep, lambda line: None)

    def test_it_waits_and_tries_the_same_episode_again_and_nothing_counts_as_a_failure(self):
        teaching = Teaching(self, 2)
        fake, ask = FakeTime(1), self.limited(2, cost=0.2)
        result, _ = run(teaching, ask, self.waiter(fake, 5))
        self.assertEqual((result["done"], result["failed"], result["stop"]), (2, 0, None))
        self.assertEqual(sum(fake.naps), 2 * 1800)
        prompts = ask.state["prompts"]
        self.assertEqual(prompts[0], prompts[1])  # the same episode, three tries
        self.assertEqual(prompts[1], prompts[2])
        self.assertFalse(os.path.exists(teaching.path("failures.json")))
        self.assertAlmostEqual(result["cost"], 0.2 + 0.2 + 0.1 + 0.1)

    def test_it_stops_when_the_waiting_hours_are_used_up(self):
        teaching = Teaching(self, 3)
        fake, ask = FakeTime(1), self.limited(99)
        result, _ = run(teaching, ask, self.waiter(fake, 1))
        self.assertEqual((result["done"], result["failed"], result["stop"]), (0, 0, "usage"))
        self.assertEqual(sum(fake.naps), 3600)
        self.assertEqual(len(ask.state["prompts"]), 3)
        self.assertFalse(os.path.exists(teaching.path("failures.json")))

    def test_without_wait_hours_it_stops_as_before(self):
        teaching = Teaching(self, 2)
        fake, ask = FakeTime(1), self.limited(1)
        result, _ = run(teaching, ask, self.waiter(fake, None))
        self.assertEqual((result["stop"], fake.naps), ("usage", []))

    def test_not_being_signed_in_stops_at_once(self):
        for message in ("Not logged in. Please run /login", "invalid API key", "OAuth token expired"):
            teaching = Teaching(self, 2)
            fake, ask = FakeTime(1), self.limited(1, message=message)
            result, _ = run(teaching, ask, self.waiter(fake, 5))
            self.assertEqual((result["stop"], fake.naps), ("usage", []), message)

    def test_the_cap_still_stops_a_run_that_waited(self):
        teaching = Teaching(self, 3)
        fake, ask = FakeTime(1), self.limited(1, cost=3.0)
        result, _ = run(teaching, ask, self.waiter(fake, 5), cap=2.0)
        self.assertEqual((result["done"], result["stop"]), (1, "cap"))


class SignedOutTests(unittest.TestCase):
    def test_signed_out_wording_is_told_apart_from_the_usage_limit(self):
        self.assertTrue(claude.is_signed_out("Not logged in"))
        self.assertTrue(claude.is_signed_out("Invalid API key"))
        self.assertFalse(claude.is_signed_out("Claude AI usage limit reached"))
        self.assertFalse(claude.is_signed_out("429 rate limit"))


class MainTests(unittest.TestCase):
    def setUp(self):
        self.said = []
        self.home = tempfile.mkdtemp()
        self.addCleanup(lambda: shutil.rmtree(self.home, ignore_errors=True))
        bin_folder = os.path.join(self.home, "bin")
        os.makedirs(bin_folder)
        with open(os.path.join(bin_folder, "claude"), "w") as f:
            f.write("#!/bin/sh\n")
        os.chmod(os.path.join(bin_folder, "claude"), 0o755)
        self.environment = {"HOME": self.home, "PATH": bin_folder}
        self.fake = FakeTime(23)

    def main(self, teaching, *options, typed="yes", runner=None):
        questions = []

        def ask_person(question):
            questions.append(question)
            return typed

        runner = runner or FakeRunner(stdout=printed(answer((1, 2))))
        code = label.main(["--folder", teaching.dir] + list(options), ask_person=ask_person,
                          runner=runner, environment=self.environment, say=self.said.append,
                          extra_folders=(), clock=self.fake.clock, sleep=self.fake.sleep)
        return code, questions, runner

    def test_the_opening_message_says_the_hours_and_the_cap(self):
        teaching = Teaching(self, 1)
        self.main(teaching, "--between", "23-7", "--wait-hours", "120", "--cap", "95")
        text = "\n".join(self.said)
        self.assertIn("23:00 and 07:00", text)
        self.assertIn("$95.00", text)
        self.assertIn("120 hours", text)

    def test_the_opening_message_is_as_before_without_the_new_options(self):
        teaching = Teaching(self, 1)
        self.main(teaching)
        text = "\n".join(self.said)
        self.assertNotIn("between", text)
        self.assertNotIn("hours", text)
        self.assertNotIn("cap", text.lower())

    def test_nothing_is_marked_without_a_yes_and_nothing_waits(self):
        teaching = Teaching(self, 1)
        self.fake.now = datetime(2026, 1, 10, 12)
        code, _, runner = self.main(teaching, "--between", "23-7", typed="no")
        self.assertEqual((code, len(runner.calls), self.fake.naps), (4, 0, []))

    def test_outside_the_hours_it_waits_then_marks(self):
        teaching = Teaching(self, 1)
        self.fake.now = datetime(2026, 1, 10, 12)
        code, _, runner = self.main(teaching, "--between", "23-7")
        self.assertEqual((code, len(runner.calls)), (0, 1))
        self.assertEqual(sum(self.fake.naps), 11 * 3600)

    def test_only_exam_with_no_exam_says_so_and_asks_nothing(self):
        teaching = Teaching(self, 2)
        code, questions, runner = self.main(teaching, "--only-exam")
        self.assertEqual((code, questions, len(runner.calls)), (0, [], 0))
        self.assertIn("exam", self.said[0])

    def test_only_exam_marks_only_the_exam(self):
        teaching = Teaching(self, 3)
        teach_exam.add_to_exam(teaching.dir, [teaching.entries[1]["id"]])
        code, _, runner = self.main(teaching, "--only-exam")
        self.assertEqual((code, len(runner.calls)), (0, 1))
        self.assertEqual(teaching.labels(), [teaching.entries[1]["id"] + ".json"])
        self.assertIn("1 episodes are waiting", "\n".join(self.said))

    def test_a_damaged_exam_file_is_a_set_up_problem(self):
        teaching = Teaching(self, 1)
        with open(teaching.path("exam.json"), "w") as f:
            f.write("nope")
        self.assertEqual(self.main(teaching, "--only-exam")[0], 2)

    def test_bad_hours_are_a_set_up_problem(self):
        teaching = Teaching(self, 1)
        for options in (["--between", "7-7"], ["--between", "night"], ["--wait-hours", "0"],
                        ["--wait-hours", "x"], ["--wait-hours", "nan"]):
            code, questions, runner = self.main(teaching, *options)
            self.assertEqual((code, questions, len(runner.calls)), (2, [], 0), options)

    def test_wait_hours_reach_the_run(self):
        teaching = Teaching(self, 1)
        limit = FakeRunner(stdout=printed("usage limit reached", is_error=True), returncode=1)
        code, _, _ = self.main(teaching, "--wait-hours", "1", runner=limit)
        self.assertEqual(code, 3)
        self.assertEqual(sum(self.fake.naps), 3600)
        self.assertEqual(len(limit.calls), 3)


if __name__ == "__main__":
    unittest.main()
