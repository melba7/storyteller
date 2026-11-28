"""Tests for teach_second_look.py: which episodes are sent, what is sent, how a moved edge is
written, the cap, the spend file after every request, and the report's numbers. A fake client
stands in for Claude; made-up transcript lines only; nothing is sent anywhere.
Run: python3 -m pytest test_teach_second_look.py -q"""
import json
import os
import unittest

import teach_budget
import teach_second_look as look
import teach_testing
from teach_testing import FakeRunner, printed


def stamp(seconds):
    return "[%02d:%02d:%04.1f]" % (seconds // 3600, seconds % 3600 // 60, seconds % 60)


def segment(first, last, start, end, sort="sponsor", confidence="high"):
    return {"first": first, "last": last, "sort": sort, "who": "Acme", "delivery": "host",
            "confidence": confidence, "why": "x", "start": start, "end": end}


# Line n (from 1) starts at (n - 1) * 5 seconds and says "line n".
BREAK_ONE = segment(21, 28, 100.0, 140.0)  # exact: 95.48 to 140.12
BREAK_TWO = segment(61, 68, 300.0, 340.0, sort="host_ask")  # exact: 290.48 to 340.0
TRUTH = "# two downloads\n1:35.480 2:20.120\n4:50.480 5:40.000\n"


class FakeClaude:
    """Answers each question from `answers` (a list of dicts or raw texts), 0.5 dollars each."""

    def __init__(self, answers=None, cost=0.5):
        self.answers = list(answers or [])
        self.cost = cost
        self.prompts = []

    def __call__(self, prompt):
        self.prompts.append(prompt)
        item = self.answers.pop(0) if self.answers else {"start": "keep", "end": "keep"}
        return {"text": item if isinstance(item, str) else json.dumps(item), "cost": self.cost}


class Setup(unittest.TestCase):
    def setUp(self):
        self.folder = teach_testing.Folder(self)
        self.entries = []
        self.said = []

    def say(self, line):
        self.said.append(line)

    def write(self, name, text):
        path = self.folder.path(*name.split("/"))
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(text)

    def episode(self, number, segments=(BREAK_ONE,), truth=TRUTH, marker="line", feed=None):
        item = teach_testing.entry(number, feed=feed or "https://feed/%d" % number)
        self.entries.append(item)
        self.folder.write_manifest(self.entries)
        self.write("transcripts/%s.txt" % item["id"], "".join(
            "%s %s %d\n" % (stamp(n * 5), marker, n + 1) for n in range(120)))
        self.write("labels/%s.json" % item["id"], json.dumps(
            {"version": 1, "episode": item["id"], "show": "Show", "length": 600.0,
             "segments": list(segments)}))
        if truth is not None:
            self.write("copies/%s.truth.txt" % item["id"], truth)
        return item["id"]

    def spent(self):
        return teach_budget.read_all(self.folder.dir).get(look.BUDGET, {}).get("dollars", 0.0)

    def moved(self, identifier):
        with open(self.folder.path(look.OUT, identifier + ".json"), encoding="utf-8") as handle:
            return json.load(handle)

    def run_look(self, ask, cap=5.0, reserve=0.0, limit=None):
        budget = teach_budget.Budget(self.folder.dir, look.BUDGET, cap)
        return look.run(self.folder.dir, ask, budget, cap, reserve, say=self.say, limit=limit)


class Choosing(Setup):
    def test_an_episode_without_truth_labels_or_transcript_is_not_sent(self):
        self.episode(1, truth=None)
        self.episode(2, truth="# the two downloads were the same\n")
        third = self.episode(3)
        os.remove(self.folder.path("labels", third + ".json"))
        fourth = self.episode(4)
        os.remove(self.folder.path("transcripts", fourth + ".txt"))
        claude = FakeClaude()
        self.run_look(claude)
        self.assertEqual(claude.prompts, [])

    def test_exam_episodes_are_never_sent(self):
        sealed = self.episode(1, marker="EXAMWORD")
        self.episode(2)
        self.write("exam.json", json.dumps({"episodes": [sealed]}))
        claude = FakeClaude()
        self.run_look(claude)
        self.assertEqual(len(claude.prompts), 1)
        self.assertNotIn("EXAMWORD", claude.prompts[0])
        self.assertFalse(os.path.exists(self.folder.path(look.OUT, sealed + ".json")))

    def test_episodes_go_in_a_fixed_order(self):
        for number in (3, 1, 2):
            self.episode(number)
        claude = FakeClaude()
        self.run_look(claude)
        self.assertEqual([p.split("\n")[1] for p in claude.prompts], ["Episode: Episode %d" % n for n in (1, 2, 3)])

    def test_a_break_that_no_second_download_differs_at_is_not_sent(self):
        self.episode(1, segments=(BREAK_ONE, segment(81, 88, 400.0, 440.0)))
        claude = FakeClaude()
        self.run_look(claude)
        self.assertEqual(len(claude.prompts), 1)

    def test_a_low_confidence_label_is_not_a_break(self):
        self.episode(1, segments=(segment(21, 28, 100.0, 140.0, confidence="low"),))
        claude = FakeClaude()
        self.run_look(claude)
        self.assertEqual(claude.prompts, [])


class Asking(Setup):
    def test_only_the_lines_a_minute_around_each_edge_are_sent(self):
        self.episode(1)
        claude = FakeClaude()
        self.run_look(claude)
        prompt = claude.prompts[0]
        self.assertIn("] line 9\n", prompt)  # 40 s, a minute before the start at 100 s
        self.assertIn("] line 41\n", prompt)  # 200 s, a minute after the end at 140 s
        self.assertNotIn("] line 8\n", prompt)
        self.assertNotIn("] line 42\n", prompt)

    def test_the_prompt_names_the_current_edges(self):
        self.episode(1)
        claude = FakeClaude()
        self.run_look(claude)
        self.assertIn("line 21", claude.prompts[0])
        self.assertIn("line 28", claude.prompts[0])


class Moving(Setup):
    def test_a_moved_start_is_written_to_a_new_folder_and_labels_stay(self):
        identifier = self.episode(1)
        with open(self.folder.path("labels", identifier + ".json"), "rb") as handle:
            before = handle.read()
        self.run_look(FakeClaude([{"start": 20, "end": "keep"}]))
        with open(self.folder.path("labels", identifier + ".json"), "rb") as handle:
            self.assertEqual(handle.read(), before)
        first = self.moved(identifier)["segments"][0]
        self.assertEqual((first["first"], first["start"], first["last"], first["end"]), (20, 95.0, 28, 140.0))

    def test_a_moved_end_is_the_start_of_the_line_after_the_last_ad_line(self):
        identifier = self.episode(1)
        self.run_look(FakeClaude([{"start": "keep", "end": 27}]))
        first = self.moved(identifier)["segments"][0]
        self.assertEqual((first["last"], first["end"], first["start"]), (27, 135.0, 100.0))

    def test_a_line_outside_the_window_keeps_the_edge(self):
        identifier = self.episode(1)
        self.run_look(FakeClaude([{"start": 2, "end": 90}]))
        first = self.moved(identifier)["segments"][0]
        self.assertEqual((first["start"], first["end"]), (100.0, 140.0))

    def test_an_answer_that_is_not_json_keeps_both_edges_and_still_costs(self):
        identifier = self.episode(1)
        self.run_look(FakeClaude(["I could not decide."]))
        first = self.moved(identifier)["segments"][0]
        self.assertEqual((first["start"], first["end"]), (100.0, 140.0))
        self.assertEqual(self.spent(), 0.5)

    def test_a_start_after_the_end_moves_neither(self):
        identifier = self.episode(1)
        self.run_look(FakeClaude([{"start": 30, "end": 22}]))
        first = self.moved(identifier)["segments"][0]
        self.assertEqual((first["start"], first["end"]), (100.0, 140.0))

    def test_an_edge_is_not_moved_into_the_next_segment(self):
        neighbour = segment(31, 33, 150.0, 165.0, sort="network_promo")
        identifier = self.episode(1, segments=(BREAK_ONE, neighbour), truth="1:35.480 2:20.120\n")
        self.run_look(FakeClaude([{"start": "keep", "end": 31}]))
        self.assertEqual(self.moved(identifier)["segments"][0]["end"], 140.0)


class Spending(Setup):
    def test_the_cap_stops_the_run_and_the_unfinished_episode_is_not_written(self):
        identifier = self.episode(1, segments=(BREAK_ONE, BREAK_TWO))
        claude = FakeClaude(cost=1.0)
        result = self.run_look(claude, cap=1.0)
        self.assertEqual(result["stop"], "cap")
        self.assertEqual(len(claude.prompts), 1)
        self.assertFalse(os.path.exists(self.folder.path(look.OUT, identifier + ".json")))

    def test_the_cap_with_a_reserve_stops_before_a_call_that_could_pass_it(self):
        first = self.episode(1, segments=(BREAK_ONE, BREAK_TWO))
        second = self.episode(2, segments=(BREAK_ONE, BREAK_TWO))
        claude = FakeClaude(cost=0.4)
        result = self.run_look(claude, cap=1.0, reserve=0.3)
        self.assertEqual(result["stop"], "cap")
        self.assertEqual(len(claude.prompts), 2)  # 0.0 and 0.4 plus 0.3 are below 1.0; 0.8 is not
        self.assertTrue(os.path.exists(self.folder.path(look.OUT, first + ".json")))
        self.assertFalse(os.path.exists(self.folder.path(look.OUT, second + ".json")))

    def test_the_spend_is_written_after_every_request(self):
        self.episode(1, segments=(BREAK_ONE, BREAK_TWO))
        self.episode(2)
        seen = []

        def ask(prompt):
            seen.append(self.spent())
            if len(seen) == 3:
                raise KeyboardInterrupt()
            return {"text": "{}", "cost": 0.25}
        with self.assertRaises(KeyboardInterrupt):
            self.run_look(ask)
        self.assertEqual(seen, [0.0, 0.25, 0.5])  # the third request died: only two are recorded
        self.assertEqual(self.spent(), 0.5)

    def test_a_failed_request_still_counts_what_it_cost(self):
        self.episode(1)

        def ask(prompt):
            error = RuntimeError("boom")
            error.cost = 0.3
            raise error
        self.run_look(ask)
        self.assertEqual(self.spent(), 0.3)

    def test_a_spent_budget_sends_nothing(self):
        self.episode(1)
        teach_budget.Budget(self.folder.dir, look.BUDGET, 5.0).add(5.0, 3)
        claude = FakeClaude()
        result = self.run_look(claude)
        self.assertEqual((claude.prompts, result["stop"]), ([], "cap"))

    def test_the_limit_stops_after_that_many_episodes(self):
        for number in (1, 2, 3):
            self.episode(number)
        claude = FakeClaude()
        result = self.run_look(claude, limit=2)
        self.assertEqual((len(claude.prompts), result["stop"]), (2, "limit"))


class Reporting(Setup):
    def test_the_report_counts_edges_within_1_2_and_5_seconds_by_kind(self):
        first = self.episode(1, segments=(BREAK_ONE, BREAK_TWO))
        # Break one: start 100 -> 95 (exact 95.48: off 4.52 then 0.48); end kept (140 vs 140.12).
        # Break two: start kept (300 vs 290.48: off 9.52 both times); end 340 -> 330 (exact 340.0:
        # off 0.0 before, 10.0 after: the second look made it worse).
        claude = FakeClaude([{"start": 20, "end": "keep"}, {"start": "keep", "end": 66}])
        self.run_look(claude)
        report = look.report(self.folder.dir, say=self.say)
        self.assertEqual(report["edges"], 4)
        self.assertEqual(report["within"]["1"], {"before": 2, "after": 2})
        self.assertEqual(report["within"]["2"], {"before": 2, "after": 2})
        self.assertEqual(report["within"]["5"], {"before": 3, "after": 2})
        self.assertEqual(report["gainPer100"], -25.0)
        self.assertEqual(report["byKind"]["sponsor"]["within"]["1"], {"before": 1, "after": 2})
        self.assertEqual(report["byKind"]["host_ask"]["within"]["1"], {"before": 1, "after": 0})
        self.assertEqual(report["worseKinds"], ["host_ask"])
        self.assertEqual(report["cost"], 1.0)
        self.assertEqual(report["perEpisode"][0]["id"], first)
        self.assertEqual(report["perEpisode"][0]["cost"], 1.0)

    def test_the_summary_says_whether_the_rule_is_met(self):
        self.episode(1)
        self.run_look(FakeClaude([{"start": 20, "end": "keep"}]))
        look.report(self.folder.dir, say=self.say)
        text = "\n".join(self.said)
        self.assertIn("within 5 s", text)
        self.assertIn("$0.50", text)

    def test_the_report_file_is_new_and_holds_no_transcript_words(self):
        self.episode(1, marker="SECRETWORD")
        self.run_look(FakeClaude())
        look.report(self.folder.dir, say=self.say)
        with open(self.folder.path(look.REPORT), encoding="utf-8") as handle:
            self.assertNotIn("SECRETWORD", handle.read())

    def test_only_new_files_are_made(self):
        self.episode(1)
        before = {os.path.join(d, f) for d, _, fs in os.walk(self.folder.dir) for f in fs}
        self.run_look(FakeClaude([{"start": 20, "end": 27}]))
        look.report(self.folder.dir, say=self.say)
        after = {os.path.join(d, f) for d, _, fs in os.walk(self.folder.dir) for f in fs}
        new = {os.path.relpath(p, self.folder.dir) for p in after - before}
        self.assertEqual(before - after, set())
        self.assertTrue(all(n.startswith(("labels-second-look", look.REPORT, "marking-spend",
                                          ".lock")) for n in new), new)


class Command(Setup):
    def install_claude(self):
        path = os.path.join(self.folder.dir, "claude")
        with open(path, "w") as handle:
            handle.write("#!/bin/sh\n")
        os.chmod(path, 0o755)
        return {"PATH": self.folder.dir, "HOME": self.folder.dir, "ANTHROPIC_API_KEY": "x"}

    def test_main_asks_through_claude_and_stops_at_the_cap(self):
        self.episode(1, segments=(BREAK_ONE, BREAK_TWO))
        runner = FakeRunner(stdout=printed('{"start": "keep", "end": "keep"}', cost=0.6))
        code = look.main(["test", self.folder.dir, "--cap", "1", "--reserve", "0.5", "--yes"],
                         runner=runner, environment=self.install_claude(), say=self.say)
        self.assertEqual(code, 5)
        self.assertEqual(len(runner.calls), 1)
        self.assertEqual(self.spent(), 0.6)
        self.assertNotIn("ANTHROPIC_API_KEY", runner.calls[0][1]["env"])
        self.assertNotIn("ANTHROPIC_API_KEY", "\n".join(self.said))

    def test_main_needs_a_yes(self):
        self.episode(1)
        runner = FakeRunner()
        code = look.main(["test", self.folder.dir, "--cap", "1"], ask_person=lambda _: "no",
                         runner=runner, environment=self.install_claude(), say=self.say)
        self.assertEqual((code, runner.calls), (4, []))

    def test_a_cap_above_five_dollars_is_refused(self):
        self.episode(1)
        self.assertEqual(look.main(["test", self.folder.dir, "--cap", "6", "--yes"], say=self.say), 2)

    def test_the_report_is_written_when_the_run_ends(self):
        self.episode(1)
        runner = FakeRunner(stdout=printed('{"start": 20, "end": "keep"}', cost=0.2))
        code = look.main(["test", self.folder.dir, "--cap", "2", "--yes"], runner=runner,
                         environment=self.install_claude(), say=self.say)
        self.assertEqual(code, 0)
        self.assertTrue(os.path.exists(self.folder.path(look.REPORT)))


if __name__ == "__main__":
    unittest.main()
