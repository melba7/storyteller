"""Tests for teach_playbook.py (build) and teach_playbook_replay.py (replay on a score dump): one
request for each show, training episodes only, phrases that must be in the lines shown, the cap, the
spend after every request, resuming, and the replay's numbers on a made-up tiny folder. A fake
client stands in for Claude; made-up transcript lines only; nothing is sent anywhere.
Run: python3 -m pytest test_teach_playbook.py -q"""
import json
import os
import unittest

import teach_budget
import teach_playbook as play
import teach_playbook_replay as replay
import teach_testing
from teach_testing import FakeRunner, printed

FEED = "https://show/a"
START = "this episode is brought to you by"
BACK = "and we are back"
PLUG = "check out our other show"


def stamp(seconds):
    return "[%02d:%02d:%04.1f]" % (seconds // 3600, seconds % 3600 // 60, seconds % 60)


def talk(number, index, marker):
    return "%s w%dx%d something else" % (marker, number, index)


class FakeClaude:
    """Answers each request from `answers` (dicts or raw texts), `cost` dollars each."""

    def __init__(self, answers=None, cost=0.5):
        self.answers = list(answers or [])
        self.cost = cost
        self.prompts = []

    def __call__(self, prompt):
        self.prompts.append(prompt)
        item = self.answers.pop(0) if self.answers else {}
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

    def episode(self, number, feed=FEED, marker="talk", plug_at=None, ad=(100.0, 140.0), show="Show"):
        """An episode with a line every 10 s (line n starts at (n - 1) * 10): an ad from 100 s to
        140 s that is opened by START and left by BACK, and, when asked, a plug line at `plug_at`."""
        item = teach_testing.entry(number, feed=feed, show=show, title="Episode %d" % number,
                                   published=1000 + number)
        self.entries.append(item)
        self.folder.write_manifest(self.entries)
        lines = []
        for n in range(1, 41):
            second = (n - 1) * 10.0
            text = talk(number, n, marker)
            if second == ad[0]:
                text = START + " acme number%d" % number
            if second == ad[1]:
                text = BACK + " with more number%d" % number
            if plug_at is not None and second == plug_at:
                text = PLUG + " number%d" % number
            if plug_at is not None and second == plug_at + 40:
                text = BACK + " again number%d" % number
            lines.append("%s %s" % (stamp(second), text))
        self.write("transcripts/%s.txt" % item["id"], "\n".join(lines) + "\n")
        segment = {"first": 11, "last": 14, "sort": "sponsor", "confidence": "high",
                   "start": ad[0], "end": ad[1]}
        self.write("labels/%s.json" % item["id"], json.dumps(
            {"version": 1, "episode": item["id"], "length": 400.0, "segments": [segment]}))
        return item["id"]

    def spent(self, name=play.BUDGET):
        return teach_budget.read_all(self.folder.dir).get(name, {}).get("dollars", 0.0)

    def playbook(self):
        with open(self.folder.path(play.FILE), encoding="utf-8") as handle:
            return json.load(handle)

    def run_build(self, ask, cap=15.0, reserve=0.0, minimum=3):
        budget = teach_budget.Budget(self.folder.dir, play.BUDGET, cap)
        return play.build(self.folder.dir, ask, budget, cap, reserve, say=self.say, minimum=minimum)

    def training(self, count=4, feed=FEED, first=1, marker="talk", show="Show"):
        return [self.episode(first + n, feed=feed, marker=marker, show=show) for n in range(count)]


GOOD = {"handoffs": [START, "a phrase that is nowhere in the lines"], "returns": [BACK],
        "segments": [], "plugs": []}


class Building(Setup):
    def test_one_request_for_each_show_over_its_training_episodes(self):
        self.training(4)
        self.training(3, feed="https://show/b", first=10, marker="otherwords", show="Other")
        claude = FakeClaude([GOOD, GOOD])
        result = self.run_build(claude)
        self.assertEqual((len(claude.prompts), result["done"]), (2, 2))
        self.assertIn("Episode 1", claude.prompts[0])
        self.assertNotIn("otherwords", claude.prompts[0])
        self.assertIn("otherwords", claude.prompts[1])

    def test_the_shelf_and_the_exam_are_never_sent(self):
        self.training(4)
        shelved = self.episode(5, marker="SHELFWORD")
        sealed = self.episode(6, marker="EXAMWORD")
        self.write("shelf.json", json.dumps({"version": 1, "episodes": [shelved]}))
        self.write("exam.json", json.dumps({"episodes": [sealed]}))
        claude = FakeClaude([GOOD])
        self.run_build(claude)
        self.assertEqual(len(claude.prompts), 1)
        for word in ("SHELFWORD", "EXAMWORD"):
            self.assertNotIn(word, claude.prompts[0])

    def test_the_prompt_holds_the_lines_around_each_break(self):
        self.training(3)
        claude = FakeClaude([GOOD])
        self.run_build(claude)
        prompt = claude.prompts[0]
        self.assertIn(START, prompt)
        self.assertIn(BACK, prompt)
        self.assertNotIn("w1x40", prompt)  # a line far from every break is not sent

    def test_a_show_with_too_few_training_episodes_is_not_asked(self):
        self.training(2)
        claude = FakeClaude([GOOD])
        result = self.run_build(claude)
        self.assertEqual((claude.prompts, result["done"]), ([], 0))

    def test_phrases_must_be_in_the_lines_shown_and_are_saved_as_words(self):
        self.training(3)
        answer = {"handoffs": [START.upper() + "!", "nowhere at all in it"], "returns": [BACK, BACK],
                  "segments": ["x"], "plugs": 5}
        self.run_build(FakeClaude([answer]))
        show = self.playbook()["shows"][0]
        self.assertEqual((show["handoffs"], show["returns"], show["segments"], show["plugs"]),
                         ([START], [BACK], [], []))
        self.assertEqual((show["feed"], show["episodes"], show["dropped"]), (FEED, 3, 3))

    def test_an_answer_that_is_not_json_saves_nothing_for_the_show_but_costs(self):
        self.training(3)
        result = self.run_build(FakeClaude(["no idea"]))
        self.assertEqual(result["failed"], 1)
        self.assertFalse(os.path.exists(self.folder.path(play.FILE)))
        self.assertEqual(self.spent(), 0.5)

    def test_a_show_already_in_the_playbook_is_not_asked_again(self):
        self.training(3)
        self.run_build(FakeClaude([GOOD]))
        claude = FakeClaude([GOOD])
        self.run_build(claude)
        self.assertEqual(claude.prompts, [])

    def test_the_cap_stops_the_run_and_the_first_show_is_kept(self):
        self.training(3)
        self.training(3, feed="https://show/b", first=10, show="Other")
        claude = FakeClaude([GOOD, GOOD], cost=1.0)
        result = self.run_build(claude, cap=1.0)
        self.assertEqual((result["stop"], len(claude.prompts)), ("cap", 1))
        self.assertEqual(len(self.playbook()["shows"]), 1)
        self.assertEqual(self.spent(), 1.0)

    def test_the_reserve_stops_before_a_request_that_could_pass_the_cap(self):
        self.training(3)
        self.training(3, feed="https://show/b", first=10, show="Other")
        claude = FakeClaude([GOOD, GOOD], cost=0.4)
        result = self.run_build(claude, cap=1.0, reserve=0.7)
        self.assertEqual((result["stop"], len(claude.prompts)), ("cap", 1))

    def test_the_spend_is_written_after_every_request(self):
        self.training(3)
        self.training(3, feed="https://show/b", first=10, show="Other")
        seen = []

        def ask(prompt):
            seen.append(self.spent())
            if len(seen) == 2:
                raise KeyboardInterrupt()
            return {"text": json.dumps(GOOD), "cost": 0.25}
        with self.assertRaises(KeyboardInterrupt):
            self.run_build(ask)
        self.assertEqual(seen, [0.0, 0.25])
        self.assertEqual(len(self.playbook()["shows"]), 1)

    def test_only_the_playbook_and_the_spend_file_are_made(self):
        self.training(3)
        before = {os.path.join(d, f) for d, _, fs in os.walk(self.folder.dir) for f in fs}
        self.run_build(FakeClaude([GOOD]))
        after = {os.path.join(d, f) for d, _, fs in os.walk(self.folder.dir) for f in fs}
        self.assertEqual(before - after, set())
        self.assertEqual({os.path.relpath(p, self.folder.dir) for p in after - before},
                         {play.FILE, "marking-spend.json"})

    def test_the_cap_has_a_ceiling_of_fifteen_dollars(self):
        self.training(3)
        self.assertEqual(play.main(["build", self.folder.dir, "--cap", "16", "--yes"], say=self.say), 2)


class Command(Setup):
    def install_claude(self):
        path = os.path.join(self.folder.dir, "claude")
        with open(path, "w") as handle:
            handle.write("#!/bin/sh\n")
        os.chmod(path, 0o755)
        return {"PATH": self.folder.dir, "HOME": self.folder.dir, "ANTHROPIC_API_KEY": "x"}

    def test_main_builds_through_claude_without_a_key(self):
        self.training(3)
        runner = FakeRunner(stdout=printed(json.dumps(GOOD), cost=0.5))
        code = play.main(["build", self.folder.dir, "--cap", "15", "--yes"], runner=runner,
                         environment=self.install_claude(), say=self.say)
        self.assertEqual(code, 0)
        self.assertNotIn("ANTHROPIC_API_KEY", runner.calls[0][1]["env"])
        self.assertEqual(self.playbook()["shows"][0]["handoffs"], [START])

    def test_main_needs_a_yes(self):
        self.training(3)
        runner = FakeRunner()
        code = play.main(["build", self.folder.dir], ask_person=lambda _: "", runner=runner,
                         environment=self.install_claude(), say=self.say)
        self.assertEqual((code, runner.calls), (4, []))


# MARK: Replay

def found(start, end, confidence="sure"):
    return {"start": start, "end": end, "kind": "sponsor", "confidence": confidence}


class Replaying(Setup):
    def shelf(self, identifier_a, identifier_b):
        self.write("shelf.json", json.dumps({"version": 1, "episodes": [identifier_a, identifier_b]}))

    def entry_of(self, identifier, found_list, truth=(), feed=FEED):
        return {"id": identifier, "feed": feed, "show": "Show", "duration": 400.0, "found": found_list,
                "truth": [{"start": a, "end": b, "sort": "sponsor"} for a, b in truth], "maybe": []}

    def setup_pair(self, playbook=None):
        a = self.episode(5)
        b = self.episode(7, plug_at=190.0, ad=(900.0, 910.0))
        self.shelf(a, b)
        self.write(play.FILE, json.dumps(playbook or {"version": 1, "shows": [
            {"feed": FEED, "show": "Show", "episodes": 4, "handoffs": [START], "returns": [BACK],
             "segments": [], "plugs": [PLUG]}]}))
        dump = [self.entry_of(a, [found(112.0, 140.0)], truth=[(100.0, 140.0)]),
                self.entry_of(b, [])]
        self.write("dump.json", json.dumps(dump))
        return a, b

    def run_replay(self):
        return replay.replay(self.folder.dir, self.folder.path("dump.json"), say=self.say)

    def test_a_late_start_is_pulled_back_to_the_handoff_line_and_a_plug_adds_a_wrong_skip(self):
        self.setup_pair()
        result = self.run_replay()
        self.assertEqual((result["before"]["breaks"], result["before"]["passed"]), (1, 0))
        self.assertEqual((result["after"]["breaks"], result["after"]["passed"]), (1, 1))
        self.assertEqual((result["before"]["noAdSkips"], result["after"]["noAdSkips"]), (0, 1))
        self.assertEqual((result["passedMore"], result["wrongSkipsMore"], result["kept"]), (1, 1, False))

    def test_the_rule_needs_four_more_breaks_and_no_more_wrong_skips(self):
        a = self.episode(5)
        b = self.episode(7)
        self.shelf(a, b)
        self.write(play.FILE, json.dumps({"version": 1, "shows": [
            {"feed": FEED, "show": "Show", "episodes": 4, "handoffs": [START], "returns": [BACK],
             "segments": [], "plugs": []}]}))
        both = [(100.0, 140.0)]
        dump = [self.entry_of(i, [found(112.0, 140.0)], truth=both) for i in (a, b)]
        # Two episodes, one break each: two more pass. The rule asks four, so it is not met.
        self.write("dump.json", json.dumps(dump))
        self.assertEqual(self.run_replay()["passedMore"], 2)
        self.assertFalse(self.run_replay()["kept"])
        self.assertTrue(replay.is_kept(4, 0))
        self.assertFalse(replay.is_kept(4, 1))
        self.assertFalse(replay.is_kept(3, 0))

    def test_episodes_that_are_not_on_the_shelf_are_left_out(self):
        a, b = self.setup_pair()
        training = self.episode(1)
        dump = json.loads(open(self.folder.path("dump.json")).read())
        dump.append(self.entry_of(training, [], truth=[(100.0, 140.0)]))
        self.write("dump.json", json.dumps(dump))
        self.assertEqual(self.run_replay()["episodes"], 2)

    def test_an_exam_episode_in_the_dump_is_never_read(self):
        a, b = self.setup_pair()
        sealed = self.episode(6, marker="EXAMWORD")
        self.write("exam.json", json.dumps({"episodes": [sealed]}))
        self.write("shelf.json", json.dumps({"version": 1, "episodes": [a, b, sealed]}))
        dump = json.loads(open(self.folder.path("dump.json")).read())
        dump.append(self.entry_of(sealed, [], truth=[(100.0, 140.0)]))
        self.write("dump.json", json.dumps(dump))
        self.assertEqual(self.run_replay()["episodes"], 2)

    def test_a_show_with_no_playbook_is_scored_as_it_is(self):
        a, b = self.setup_pair({"version": 1, "shows": []})
        result = self.run_replay()
        self.assertEqual(result["before"], result["after"])

    def test_the_result_is_written_to_a_new_file_and_says_how_it_was_made(self):
        self.setup_pair()
        self.run_replay()
        with open(self.folder.path(replay.FILE), encoding="utf-8") as handle:
            result = json.load(handle)
        self.assertIn("score dump", result["evaluator"])
        self.assertIn("not met", "\n".join(self.said))

    def test_main_replays_from_a_dump(self):
        self.setup_pair()
        code = play.main(["replay", self.folder.dir, "--dump", self.folder.path("dump.json")],
                         say=self.say)
        self.assertEqual(code, 0)
        self.assertTrue(os.path.exists(self.folder.path(replay.FILE)))

    def test_a_missing_dump_is_a_set_up_problem(self):
        self.setup_pair()
        self.assertEqual(play.main(["replay", self.folder.dir, "--dump", self.folder.path("none.json")],
                                   say=self.say), 2)


if __name__ == "__main__":
    unittest.main()
