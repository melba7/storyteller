"""Tests for the cost cap and the memory of failures in teach_label.py's run: failed calls cost
money too, and episodes that failed come last, three failures give up. A fake claude.
Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import json
import os
import unittest

import teach_claude as claude
from teach_testing import Teaching, answer
from test_teach_label import RunHelpers


# MARK: Cost

def failing(cost, error=claude.ClaudeError):
    """An ask that fails the way a paid run that ended in an error does."""
    def ask(prompt):
        problem = error("broken")
        problem.cost = cost
        raise problem
    return ask


class CostTests(RunHelpers, unittest.TestCase):
    """The cap counts every call, finished episode or not."""

    def test_failed_calls_count_towards_the_cap_and_the_total(self):
        teaching = Teaching(self, 6)
        result, said = self.go(teaching, failing(2.0), cap=3.5)
        self.assertEqual((result["failed"], result["stop"]), (2, "cap"))
        self.assertAlmostEqual(result["cost"], 4.0)
        self.assertIn("$4.00", result["reason"])

    def test_answers_that_could_not_be_read_cost_too(self):
        teaching = Teaching(self, 4)
        result, _ = self.go(teaching, self.fake_ask(cost=0.6, text="no json"), cap=1.5)
        # Two bad answers per episode, 1.2 an episode: the second episode takes it past the cap.
        self.assertEqual((result["failed"], result["stop"]), (2, "cap"))
        self.assertAlmostEqual(result["cost"], 2.4)

    def test_a_usage_limit_answer_that_cost_something_is_counted(self):
        teaching = Teaching(self, 2)
        result, _ = self.go(teaching, failing(0.7, claude.UsageLimit))
        self.assertEqual(result["stop"], "usage")
        self.assertAlmostEqual(result["cost"], 0.7)

    def test_finished_episodes_are_counted_once(self):
        teaching = Teaching(self, 2)
        result, _ = self.go(teaching, self.fake_ask(cost=0.3))
        self.assertAlmostEqual(result["cost"], 0.6)


# MARK: Failures

class FailureMemoryTests(RunHelpers, unittest.TestCase):
    def failing_for(self, bad, log=None):
        def ask(prompt):
            if log is not None:
                log.append(prompt)
            if any("Episode %d" % n in prompt for n in bad):
                raise RuntimeError("broken")
            return {"text": answer((1, 2)), "cost": 0.0}
        return ask

    def test_failures_are_remembered_and_the_entry_goes_when_the_episode_succeeds(self):
        teaching = Teaching(self, 5)
        self.go(teaching, self.failing_for([1, 2, 3]))
        first, second, third = (e["id"] for e in teaching.entries[:3])
        self.assertEqual(teaching.failures(), {"version": 1, "transcribe": {},
                                               "label": {first: 1, second: 1, third: 1}})
        self.go(teaching, self.failing_for([]))
        self.assertEqual(teaching.failures()["label"], {})

    def test_the_same_three_failing_episodes_do_not_stall_every_later_run(self):
        teaching = Teaching(self, 8)
        result, _ = self.go(teaching, self.failing_for([1, 2, 3]))
        self.assertEqual((result["done"], result["stop"]), (0, "failures"))
        log = []
        result, _ = self.go(teaching, self.failing_for([1, 2, 3], log))
        # The five that never failed come first and are marked; then the failed ones are tried.
        self.assertEqual(result["done"], 5)
        self.assertEqual(result["failed"], 3)
        self.assertIsNone(result["stop"])
        self.assertTrue(all("Episode %d" % n in log[i] for i, n in enumerate(range(4, 9))))

    def test_only_a_first_failure_counts_towards_three_in_a_row(self):
        teaching = Teaching(self, 8)
        self.go(teaching, self.failing_for([1, 2, 3]))
        result, _ = self.go(teaching, self.failing_for([1, 2, 3, 4, 5, 6, 7, 8]))
        # 4 to 8 fail for the first time: three of them stop the run before the old ones are tried.
        self.assertEqual((result["failed"], result["stop"]), (3, "failures"))

    def test_a_repeat_failure_does_not_count_towards_three_in_a_row(self):
        teaching = Teaching(self, 6)
        with open(teaching.path("failures.json"), "w") as f:
            json.dump({"version": 1, "label": {teaching.entries[0]["id"]: 1, teaching.entries[1]["id"]: 1}}, f)
        # The order is 3, 4, 5, 6, 1, 2. Episodes 5 and 6 fail for the first time (two in a row);
        # 1 and 2 fail again, which is not a new kind of trouble, so the run goes on to the end.
        result, _ = self.go(teaching, self.failing_for([1, 2, 5, 6]))
        self.assertEqual((result["done"], result["failed"], result["stop"]), (2, 4, None))
        self.assertEqual(teaching.failures()["label"][teaching.entries[0]["id"]], 2)

    def test_fewer_failures_go_first(self):
        teaching = Teaching(self, 3)
        with open(teaching.path("failures.json"), "w") as f:
            json.dump({"version": 1, "label": {teaching.entries[0]["id"]: 2, teaching.entries[1]["id"]: 1}}, f)
        log = []
        self.go(teaching, self.failing_for([], log))
        self.assertEqual([n for p in log for n in (3, 2, 1) if "Episode %d" % n in p], [3, 2, 1])

    def test_an_episode_that_failed_three_times_is_left_out_and_counted(self):
        teaching = Teaching(self, 3)
        with open(teaching.path("failures.json"), "w") as f:
            json.dump({"version": 1, "label": {teaching.entries[0]["id"]: 3}}, f)
        log = []
        result, _ = self.go(teaching, self.failing_for([], log))
        self.assertEqual((result["done"], result["given_up"], len(log)), (2, 1, 2))
        self.assertFalse(os.path.exists(teaching.label_path(teaching.entries[0])))

    def test_retry_failed_includes_them_once_more(self):
        teaching = Teaching(self, 3)
        with open(teaching.path("failures.json"), "w") as f:
            json.dump({"version": 1, "label": {teaching.entries[0]["id"]: 3}}, f)
        result, _ = self.go(teaching, self.failing_for([]), retry_failed=True)
        self.assertEqual((result["done"], result["given_up"]), (3, 0))
        self.assertEqual(teaching.failures()["label"], {})

    def test_the_transcribe_step_has_its_own_counts(self):
        teaching = Teaching(self, 2)
        with open(teaching.path("failures.json"), "w") as f:
            json.dump({"version": 1, "transcribe": {teaching.entries[0]["id"]: 3}, "label": {}}, f)
        self.assertEqual(self.go(teaching, self.failing_for([]))[0]["done"], 2)


if __name__ == "__main__":
    unittest.main()
