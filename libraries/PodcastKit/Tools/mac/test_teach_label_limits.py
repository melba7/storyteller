"""Tests for the limits of teach_label.py's run: no call outside the night hours (also a retry after
a usage-limit wait), a retry that keeps the parts already answered, the cap before every call, the
budget across runs, the second marking of the exam and the exit codes that tell the stops apart.
A fake claude, a fake clock, no real waiting.
Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import json
import os
import shutil
import tempfile
import unittest
from datetime import datetime, timedelta

import teach_claude as claude
import teach_exam
import teach_label as label
import teach_night as night
from teach_testing import FakeRunner, Teaching, answer, printed, transcript
from test_teach_night import FakeTime

TWO_PARTS = "".join("[00:00:%02d.0] %s\n" % (n, "x" * 150000) for n in range(2))


def limited(error=claude.UsageLimit, cost=0.0):
    problem = error("usage limit reached")
    problem.cost = cost
    return problem


def run(teaching, ask, waiter=None, budget=None, **more):
    said = []
    result = label.run(teaching.dir, more.pop("labels", "labels"), "m", more.pop("limit", None),
                       more.pop("cap", None), ask, say=said.append, waiter=waiter, budget=budget,
                       **more)
    return result, said


def spend(teaching):
    with open(teaching.path("marking-spend.json")) as f:
        return json.load(f)["budgets"]


class WindowTests(unittest.TestCase):
    def waiter(self, fake, hours=None):
        return night.Waiter((23, 7), hours, fake.clock, fake.sleep, lambda line: None)

    def test_a_limit_hit_at_the_end_of_the_night_is_not_retried_in_the_daytime(self):
        teaching = Teaching(self, 1)
        fake = FakeTime(6, 45)
        started = []

        def ask(prompt):
            started.append(fake.now)
            if fake.now < datetime(2026, 1, 10, 14):
                raise limited()
            return {"text": answer((1, 2)), "cost": 0.1}

        result, _ = run(teaching, ask, self.waiter(fake, 20))
        self.assertEqual(result["done"], 1)
        self.assertTrue(all(night.in_window(when.hour, (23, 7)) for when in started), started)
        self.assertEqual(started, [datetime(2026, 1, 10, 6, 45), datetime(2026, 1, 10, 23)])

    def test_the_second_part_of_an_episode_waits_for_the_night_too(self):
        teaching = Teaching(self, 1, with_transcripts=TWO_PARTS)
        fake = FakeTime(6, 59)
        started = []

        def ask(prompt):
            started.append(fake.now)
            fake.now += timedelta(minutes=2)
            return {"text": answer((1, 1)), "cost": 0.1}

        result, _ = run(teaching, ask, self.waiter(fake))
        self.assertEqual(result["done"], 1)
        self.assertEqual(started, [datetime(2026, 1, 10, 6, 59), datetime(2026, 1, 10, 23)])


class KeptPartsTests(unittest.TestCase):
    def test_a_retry_after_the_wait_asks_only_for_the_missing_parts(self):
        teaching = Teaching(self, 1, with_transcripts=TWO_PARTS)
        fake = FakeTime(1)
        prompts, state = [], {"limit": 1}

        def ask(prompt):
            prompts.append(prompt)
            if len(prompts) == 2 and state["limit"]:
                state["limit"] = 0
                raise limited(cost=0.3)
            if prompt == prompts[0]:
                return {"text": answer((1, 1), who="A"), "cost": 0.5}
            return {"text": answer((2, 2), who="B"), "cost": 0.5}

        waiter = night.Waiter(None, 5, fake.clock, fake.sleep, lambda line: None)
        result, _ = run(teaching, ask, waiter)
        self.assertEqual(len(prompts), 3)  # part 1, part 2 (limit), part 2 again
        self.assertEqual(prompts[1], prompts[2])
        self.assertNotEqual(prompts[0], prompts[1])
        self.assertAlmostEqual(result["cost"], 0.5 + 0.3 + 0.5)
        with open(teaching.label_path(teaching.entries[0])) as f:
            made = json.load(f)
        self.assertEqual(len(made["segments"]), 2)  # one stretch from each part
        self.assertAlmostEqual(made["cost"], 1.0)  # the paid part 1 is in the label's cost

    def test_the_kept_parts_are_not_kept_for_the_next_episode(self):
        teaching = Teaching(self, 2, with_transcripts=TWO_PARTS)
        prompts = []

        def ask(prompt):
            prompts.append(prompt)
            return {"text": answer((1, 1)), "cost": 0.1}

        run(teaching, ask)
        self.assertEqual(len(prompts), 4)


class CapBeforeEveryCallTests(unittest.TestCase):
    def test_the_second_part_is_not_asked_when_the_first_reached_the_cap(self):
        teaching = Teaching(self, 2, with_transcripts=TWO_PARTS)
        prompts = []

        def ask(prompt):
            prompts.append(prompt)
            return {"text": answer((1, 1)), "cost": 1.0}

        result, said = run(teaching, ask, cap=1.0)
        self.assertEqual((len(prompts), result["done"], result["failed"], result["stop"]),
                         (1, 0, 0, "cap"))
        self.assertAlmostEqual(result["cost"], 1.0)
        self.assertEqual(teaching.labels(), [])
        self.assertIn("$1.00", result["reason"])

    def test_a_retry_of_an_unreadable_answer_is_not_asked_after_the_cap(self):
        teaching = Teaching(self, 1)
        prompts = []

        def ask(prompt):
            prompts.append(prompt)
            return {"text": "no json", "cost": 2.0}

        result, _ = run(teaching, ask, cap=1.0)
        self.assertEqual((len(prompts), result["stop"], result["failed"]), (1, "cap", 0))


class BudgetRunTests(unittest.TestCase):
    def budget(self, teaching, cap, name="exam"):
        import teach_budget
        return teach_budget.Budget(teaching.dir, name, cap)

    def test_the_file_is_written_after_every_marked_episode(self):
        teaching = Teaching(self, 3)
        seen = []

        def ask(prompt):
            seen.append(spend(teaching)["exam"] if os.path.exists(teaching.path("marking-spend.json")) else None)
            return {"text": answer((1, 2)), "cost": 1.0}

        run(teaching, ask, budget=self.budget(teaching, 10), cap=10)
        self.assertEqual(seen, [None, {"dollars": 1.0, "episodes": 1}, {"dollars": 2.0, "episodes": 2}])
        self.assertEqual(spend(teaching), {"exam": {"dollars": 3.0, "episodes": 3}})

    def test_the_cap_is_the_total_across_runs(self):
        teaching = Teaching(self, 6)
        ask = lambda prompt: {"text": answer((1, 2)), "cost": 1.0}  # noqa: E731
        first, _ = run(teaching, ask, budget=self.budget(teaching, 2.5), cap=2.5)
        self.assertEqual((first["done"], first["stop"]), (3, "cap"))
        calls = []

        def counting(prompt):
            calls.append(prompt)
            return ask(prompt)

        second, said = run(teaching, counting, budget=self.budget(teaching, 2.5), cap=2.5)
        self.assertEqual((second["done"], second["stop"], calls), (0, "cap", []))
        self.assertIn("exam", second["reason"])
        self.assertIn("$3.00", second["reason"])
        self.assertEqual(spend(teaching), {"exam": {"dollars": 3.0, "episodes": 3}})

    def test_a_failed_episode_that_cost_something_is_written_down(self):
        teaching = Teaching(self, 1)

        def ask(prompt):
            raise limited(claude.ClaudeError, cost=2.0)

        result, _ = run(teaching, ask, budget=self.budget(teaching, 10), cap=10)
        self.assertEqual(result["failed"], 1)
        self.assertEqual(spend(teaching), {"exam": {"dollars": 2.0, "episodes": 0}})

    def test_a_failed_episode_that_cost_nothing_writes_nothing(self):
        teaching = Teaching(self, 1)

        def ask(prompt):
            raise limited(claude.ClaudeError)

        run(teaching, ask, budget=self.budget(teaching, 10), cap=10)
        self.assertFalse(os.path.exists(teaching.path("marking-spend.json")))

    def test_what_a_usage_limit_stop_cost_is_written_down(self):
        teaching = Teaching(self, 2)

        def ask(prompt):
            raise limited(cost=0.7)

        result, _ = run(teaching, ask, budget=self.budget(teaching, 10), cap=10)
        self.assertEqual(result["stop"], "usage")
        self.assertEqual(spend(teaching), {"exam": {"dollars": 0.7, "episodes": 0}})

    def test_without_a_budget_no_file_is_made(self):
        teaching = Teaching(self, 1)
        run(teaching, lambda prompt: {"text": answer((1, 2)), "cost": 1.0}, cap=5)
        self.assertFalse(os.path.exists(teaching.path("marking-spend.json")))


class SecondMarkingTests(unittest.TestCase):
    def teaching(self, count, first, second):
        teaching = Teaching(self, count)
        ids = [e["id"] for e in teaching.entries]
        teach_exam.add_to_exam(teaching.dir, ids)
        for folder, chosen in (("labels", first), ("labels-second", second)):
            os.makedirs(teaching.path(folder), exist_ok=True)
            for number in chosen:
                with open(teaching.path(folder, ids[number] + ".json"), "w") as f:
                    f.write("{}")
        return teaching, ids

    def test_the_limit_counts_the_second_labels_already_held(self):
        teaching, ids = self.teaching(5, first=[0, 1, 2, 3, 4], second=[0, 1])
        result, _ = run(teaching, lambda prompt: {"text": answer((1, 2)), "cost": 0.0},
                        labels="labels-second", limit=3, only_exam=True)
        self.assertEqual((result["done"], result["stop"]), (1, "limit"))
        self.assertEqual(len(teaching.labels("labels-second")), 3)

    def test_nothing_more_is_marked_when_the_limit_is_already_held(self):
        teaching, _ = self.teaching(5, first=[0, 1, 2, 3, 4], second=[0, 1, 2])
        calls = []
        result, _ = run(teaching, lambda prompt: calls.append(prompt) or {"text": "", "cost": 0.0},
                        labels="labels-second", limit=3, only_exam=True)
        self.assertEqual((calls, result["done"], result["stop"]), ([], 0, "limit"))

    def test_only_an_episode_with_a_first_label_gets_a_second_one(self):
        teaching, ids = self.teaching(4, first=[1, 3], second=[])
        result, _ = run(teaching, lambda prompt: {"text": answer((1, 2)), "cost": 0.0},
                        labels="labels-second", limit=15, only_exam=True)
        self.assertEqual(result["done"], 2)
        self.assertEqual(teaching.labels("labels-second"), sorted(ids[i] + ".json" for i in (1, 3)))

    def test_the_first_marking_is_not_limited_that_way(self):
        teaching, _ = self.teaching(3, first=[], second=[0])
        result, _ = run(teaching, lambda prompt: {"text": answer((1, 2)), "cost": 0.0},
                        limit=2, only_exam=True)
        self.assertEqual(result["done"], 2)


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

    def main(self, teaching, *options, runner=None):
        runner = runner or FakeRunner(stdout=printed(answer((1, 2)), cost=1.0))
        code = label.main(["--folder", teaching.dir, "--yes"] + list(options), ask_person=input,
                          runner=runner, environment=self.environment, say=self.said.append,
                          extra_folders=(), clock=self.fake.clock, sleep=self.fake.sleep)
        return code, runner

    def text(self):
        return "\n".join(self.said)

    def test_the_cap_has_its_own_exit_code_and_so_do_the_other_stops(self):
        self.assertEqual(self.main(Teaching(self, 4), "--cap", "1.5")[0], 5)
        limit = FakeRunner(stdout=printed("usage limit reached", is_error=True), returncode=1)
        self.assertEqual(self.main(Teaching(self, 4), runner=limit)[0], 3)
        broken = FakeRunner(stdout="junk", returncode=1)
        self.assertEqual(self.main(Teaching(self, 4), runner=broken)[0], 6)

    def test_the_budget_needs_a_cap_and_a_good_name(self):
        teaching = Teaching(self, 1)
        for options in (["--budget", "exam"], ["--budget", "a b", "--cap", "5"]):
            code, runner = self.main(teaching, *options)
            self.assertEqual((code, len(runner.calls)), (2, 0), options)

    def test_a_run_says_what_the_budget_has_spent_and_what_is_left(self):
        teaching = Teaching(self, 4)
        self.main(teaching, "--cap", "2.5", "--budget", "exam", "--limit", "1")
        self.main(teaching, "--cap", "2.5", "--budget", "exam", "--limit", "1")
        text = self.text()
        self.assertIn("Budget \"exam\": $0.00 of $2.50 spent so far on 0 episodes, $2.50 left.", text)
        self.assertIn("Budget \"exam\": $1.00 of $2.50 spent so far on 1 episode, $1.50 left.", text)
        self.assertIn("$2.00 of $2.50", self.said[-1])  # the closing line

    def test_a_spent_budget_ends_the_run_at_once_with_the_cap_code(self):
        teaching = Teaching(self, 4)
        self.assertEqual(self.main(teaching, "--cap", "1", "--budget", "exam")[0], 5)
        code, runner = self.main(teaching, "--cap", "1", "--budget", "exam")
        self.assertEqual((code, len(runner.calls)), (5, 0))
        self.assertIn("spent", self.said[-1])
        self.assertIn("Nothing more is marked under it", self.said[-1])

    def test_a_damaged_spending_file_is_a_set_up_problem_and_nothing_is_marked(self):
        teaching = Teaching(self, 1)
        with open(teaching.path("marking-spend.json"), "w") as f:
            f.write("nope")
        code, runner = self.main(teaching, "--cap", "5", "--budget", "exam")
        self.assertEqual((code, len(runner.calls)), (2, 0))
        with open(teaching.path("marking-spend.json")) as f:
            self.assertEqual(f.read(), "nope")

    def test_without_a_budget_every_run_has_its_own_cap(self):
        teaching = Teaching(self, 6)
        self.assertEqual(self.main(teaching, "--cap", "1.5")[0], 5)
        code, runner = self.main(teaching, "--cap", "1.5")
        self.assertEqual((code, len(runner.calls)), (5, 2))

    def test_a_second_marking_announces_how_many_it_will_do(self):
        teaching = Teaching(self, 4)
        teach_exam.add_to_exam(teaching.dir, [e["id"] for e in teaching.entries])
        self.main(teaching, "--only-exam", "--limit", "3")
        self.said.clear()
        code, runner = self.main(teaching, "--only-exam", "--labels", "labels-second", "--limit", "2")
        self.assertEqual((code, len(runner.calls)), (0, 2))
        self.assertIn("3 episodes are waiting to be marked (2 this run)", self.text())
        code, runner = self.main(teaching, "--only-exam", "--labels", "labels-second", "--limit", "2")
        self.assertEqual((code, len(runner.calls)), (0, 0))
        self.assertIn("Nothing to do", self.said[-1])


class SignedOutTests(unittest.TestCase):
    def test_a_login_message_anywhere_in_the_output_is_signed_out_not_a_limit_to_wait_out(self):
        runner = FakeRunner(stdout="Please run /login first", stderr="x" * 600, returncode=1)
        with self.assertRaises(claude.SignedOut) as caught:
            claude.ask_claude("s", "p", "m", "claude", runner=runner, environment={})
        self.assertIsInstance(caught.exception, claude.UsageLimit)

    def test_the_run_stops_at_once_on_it_without_waiting(self):
        teaching = Teaching(self, 2)
        fake = FakeTime(1)

        def ask(prompt):
            raise claude.SignedOut("claude exited 1 without a result: nothing useful")

        waiter = night.Waiter(None, 5, fake.clock, fake.sleep, lambda line: None)
        result, _ = run(teaching, ask, waiter)
        self.assertEqual((result["stop"], fake.naps), ("usage", []))

    def test_a_usage_limit_is_still_waited_out(self):
        runner = FakeRunner(stdout="", stderr="Claude AI usage limit reached", returncode=1)
        with self.assertRaises(claude.UsageLimit) as caught:
            claude.ask_claude("s", "p", "m", "claude", runner=runner, environment={})
        self.assertNotIsInstance(caught.exception, claude.SignedOut)


if __name__ == "__main__":
    unittest.main()
