"""Tests for what the nightly read-ahead's marking counts against its weekly cap: a call whose cost is
not known (it timed out, died without a result or printed no cost) counts as one expected call (the
--reserve, 0.19 dollars), and every call is written in the budget file at once, so a run that stops half
way through an episode has not lost what it spent. Without a --reserve (the big teaching runs) an
unknown cost counts as nothing, as before. A fake claude, no network, no real money.
Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import json
import os
import unittest

import teach_ahead_set as ahead
import teach_budget
import teach_claude as claude
import teach_label as label
from teach_testing import FakeRunner, Teaching, answer, printed, timeout
from test_teach_ahead_flags import LabelBase, picked

ESTIMATE = 0.19


def no_cost(result="ok", is_error=False):
    """What claude prints when its result has no total_cost_usd."""
    return json.dumps({"type": "result", "is_error": is_error, "result": result})


class CostKnowledgeTests(unittest.TestCase):
    """teach_claude.ask_claude says when a run could not tell what it cost."""

    def ask(self, runner):
        return claude.ask_claude("system", "prompt", "model", "/bin/claude", runner=runner,
                                 environment={}, folder=os.path.join(os.environ.get("TMPDIR", "/tmp"),
                                                                     "lofi-claude-code-test"))

    def failure(self, runner):
        with self.assertRaises(claude.ClaudeError) as caught:
            self.ask(runner)
        return caught.exception

    def test_a_run_that_timed_out_has_an_unknown_cost(self):
        error = self.failure(FakeRunner(raises=timeout()))
        self.assertEqual((error.cost, error.cost_unknown), (0.0, True))

    def test_a_run_that_could_not_be_started_cost_nothing(self):
        error = self.failure(FakeRunner(raises=OSError("no such file")))
        self.assertEqual((error.cost, error.cost_unknown), (0.0, False))

    def test_a_run_that_ended_without_a_result_has_an_unknown_cost(self):
        error = self.failure(FakeRunner(stdout="", stderr="Killed", returncode=137))
        self.assertTrue(error.cost_unknown)

    def test_a_usage_limit_or_a_sign_in_error_without_a_result_used_nothing(self):
        for words in ("Claude AI usage limit reached", "Not logged in"):
            with self.assertRaises(claude.UsageLimit) as caught:
                self.ask(FakeRunner(stdout="", stderr=words, returncode=1))
            self.assertFalse(caught.exception.cost_unknown, words)

    def test_an_error_result_that_says_its_cost_is_known_even_when_it_is_nothing(self):
        for cost in (0.0, 0.3):
            error = self.failure(FakeRunner(stdout=printed("broke", cost=cost, is_error=True), returncode=1))
            self.assertEqual((error.cost, error.cost_unknown), (cost, False))

    def test_an_error_result_with_no_cost_is_unknown(self):
        error = self.failure(FakeRunner(stdout=no_cost("broke", is_error=True), returncode=1))
        self.assertEqual((error.cost, error.cost_unknown), (0.0, True))

    def test_an_answer_with_no_cost_is_marked_unknown_and_one_with_a_cost_is_as_before(self):
        self.assertEqual(self.ask(FakeRunner(stdout=no_cost("hello"))),
                         {"text": "hello", "cost": 0.0, "cost_unknown": True})
        self.assertEqual(self.ask(FakeRunner(stdout=printed("hello", cost=0.5))),
                         {"text": "hello", "cost": 0.5})
        self.assertEqual(self.ask(FakeRunner(stdout=printed("hello", cost=0.0))),
                         {"text": "hello", "cost": 0.0})

    def test_a_cost_that_is_not_a_sane_number_is_unknown(self):
        for cost in ("1.0", None, -1, float("nan"), float("inf"), True):
            out = self.ask(FakeRunner(stdout=json.dumps({"type": "result", "result": "x",
                                                         "total_cost_usd": cost}, allow_nan=True)))
            self.assertEqual((out["cost"], out.get("cost_unknown")), (0.0, True), repr(cost))


class CountingTests(unittest.TestCase):
    """teach_label.run counts and records the cost of every call."""

    def setUp(self):
        self.said = []

    def run_label(self, teaching, ask, cap=10, reserve=ESTIMATE, name="ahead-2026-W48"):
        budget = teach_budget.Budget(teaching.dir, name, cap)
        result = label.run(teaching.dir, "labels", "m", None, cap, ask, say=self.said.append,
                           budget=budget, reserve=reserve)
        return result, budget

    def spent(self, teaching, name="ahead-2026-W48"):
        path = teaching.path("marking-spend.json")
        if not os.path.exists(path):
            return None
        with open(path) as f:
            return json.load(f)["budgets"].get(name)

    @staticmethod
    def unknown_failure(prompt):
        error = claude.ClaudeError("claude took longer than 900 seconds")
        error.cost, error.cost_unknown = 0.0, True
        raise error

    def test_a_call_that_timed_out_counts_as_one_expected_call(self):
        teaching = Teaching(self, 6)
        result, budget = self.run_label(teaching, self.unknown_failure)
        # Three episodes in a row fail and the run stops: three calls were made.
        self.assertEqual((result["failed"], result["stop"]), (3, "failures"))
        self.assertAlmostEqual(result["cost"], 3 * ESTIMATE)
        self.assertAlmostEqual(budget.dollars, 3 * ESTIMATE)
        self.assertEqual(self.spent(teaching), {"dollars": round(3 * ESTIMATE, 6), "episodes": 0})

    def test_without_a_reserve_an_unknown_cost_counts_nothing_as_before(self):
        teaching = Teaching(self, 6)
        result, _ = self.run_label(teaching, self.unknown_failure, reserve=0.0)
        self.assertEqual(result["cost"], 0.0)
        self.assertIsNone(self.spent(teaching))

    def test_calls_that_keep_timing_out_run_into_the_cap_instead_of_costing_nothing(self):
        teaching = Teaching(self, 6)
        # 0.38 spent after two calls, and a third would make 0.57: over the cap of 0.5.
        result, budget = self.run_label(teaching, self.unknown_failure, cap=0.5)
        self.assertEqual((result["failed"], result["stop"]), (2, "cap"))
        self.assertAlmostEqual(budget.dollars, 2 * ESTIMATE)

    def test_an_answer_that_printed_no_cost_counts_as_one_expected_call(self):
        teaching = Teaching(self, 2)
        ask = lambda prompt: {"text": answer((1, 2)), "cost": 0.0, "cost_unknown": True}  # noqa: E731
        result, _ = self.run_label(teaching, ask)
        self.assertEqual(result["done"], 2)
        self.assertAlmostEqual(result["cost"], 2 * ESTIMATE)
        self.assertEqual(self.spent(teaching), {"dollars": round(2 * ESTIMATE, 6), "episodes": 2})

    def test_a_cost_the_run_reported_is_counted_as_it_is_even_below_the_estimate(self):
        teaching = Teaching(self, 2)
        result, _ = self.run_label(teaching, lambda prompt: {"text": answer((1, 2)), "cost": 0.05})
        self.assertAlmostEqual(result["cost"], 0.10)
        error = claude.ClaudeError("broke")
        error.cost, error.cost_unknown = 0.0, False

        def reported_nothing(prompt):
            raise error

        teaching = Teaching(self, 2)
        result, _ = self.run_label(teaching, reported_nothing)
        self.assertEqual(result["cost"], 0.0)

    def test_an_unknown_cost_is_never_counted_less_than_what_was_printed(self):
        teaching = Teaching(self, 1)
        error = claude.ClaudeError("broke")
        error.cost, error.cost_unknown = 0.5, True

        def raising(prompt):
            raise error

        result, _ = self.run_label(teaching, raising)
        self.assertAlmostEqual(result["cost"], 0.5)

    def test_what_a_call_cost_is_in_the_budget_file_before_the_next_call(self):
        teaching = Teaching(self, 1)
        seen = []

        def ask(prompt):
            seen.append(self.spent(teaching))
            return {"text": "no json", "cost": 0.25}

        # Both answers of the episode cannot be read, so the episode fails after two calls.
        self.run_label(teaching, ask)
        self.assertEqual(seen, [None, {"dollars": 0.25, "episodes": 0}])

    def test_a_run_that_is_killed_half_way_through_an_episode_has_not_lost_its_calls(self):
        teaching = Teaching(self, 1)
        calls = []

        def ask(prompt):
            calls.append(prompt)
            if len(calls) == 2:
                raise KeyboardInterrupt  # the run is stopped during the second call
            return {"text": "no json", "cost": 0.25}

        with self.assertRaises(KeyboardInterrupt):
            self.run_label(teaching, ask)
        self.assertEqual(self.spent(teaching), {"dollars": 0.25, "episodes": 0})

    def test_a_marked_episode_is_counted_once_and_the_episode_is_counted(self):
        teaching = Teaching(self, 3)
        result, budget = self.run_label(teaching, lambda prompt: {"text": answer((1, 2)), "cost": 0.3})
        self.assertEqual(result["done"], 3)
        self.assertEqual(self.spent(teaching), {"dollars": 0.9, "episodes": 3})
        self.assertAlmostEqual(budget.dollars, 0.9)
        self.assertEqual(budget.episodes, 3)

    def test_a_failed_call_that_cost_nothing_writes_no_file(self):
        teaching = Teaching(self, 1)
        error = claude.ClaudeError("broke")

        def free(prompt):
            raise error

        self.run_label(teaching, free, reserve=0.0)
        self.assertFalse(os.path.exists(teaching.path("marking-spend.json")))


class NightlyMarkingTests(LabelBase):
    """The same through teach_label.py's command line, as teach-ahead.sh runs it."""

    NIGHT = ("--only-ahead", "--budget", "ahead-2026-W48", "--cap", "10", "--reserve", "0.19")

    def spent(self, teaching):
        with open(teaching.path("marking-spend.json")) as f:
            return json.load(f)["budgets"]["ahead-2026-W48"]

    def teaching(self, count):
        teaching = Teaching(self, count)
        ahead.add_ahead(teaching.dir, [picked(e) for e in teaching.entries])
        return teaching

    def test_calls_that_time_out_are_counted_in_the_weeks_budget(self):
        teaching = self.teaching(5)
        code, runner = self.main(teaching, *self.NIGHT, runner=FakeRunner(raises=timeout()))
        self.assertEqual((code, len(runner.calls)), (6, 3))  # three episodes in a row failed
        self.assertAlmostEqual(self.spent(teaching)["dollars"], 3 * 0.19)

    def test_answers_that_print_no_cost_are_counted_in_the_weeks_budget(self):
        teaching = self.teaching(3)
        code, runner = self.main(teaching, *self.NIGHT, runner=FakeRunner(stdout=no_cost(answer((1, 2)))))
        self.assertEqual((code, len(runner.calls)), (0, 3))
        self.assertEqual(self.spent(teaching), {"dollars": round(3 * 0.19, 6), "episodes": 3})

    def test_a_week_of_timeouts_ends_at_the_cap(self):
        teaching = self.teaching(8)
        code, runner = self.main(teaching, "--only-ahead", "--budget", "ahead-2026-W48", "--cap", "0.5",
                                 "--reserve", "0.19", runner=FakeRunner(raises=timeout()))
        self.assertEqual((code, len(runner.calls)), (5, 2))
        self.assertIn("would pass the cap", "\n".join(self.said))

    def test_a_night_with_costs_reported_is_counted_as_before(self):
        teaching = self.teaching(2)
        code, runner = self.main(teaching, *self.NIGHT,
                                 runner=FakeRunner(stdout=printed(answer((1, 2)), cost=0.25)))
        self.assertEqual(code, 0)
        self.assertEqual(self.spent(teaching), {"dollars": 0.5, "episodes": 2})


if __name__ == "__main__":
    unittest.main()
