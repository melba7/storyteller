"""Tests for teach_label.py: finding claude, one claude run (against a fake runner), marking one
episode, the whole run and the confirmation. No network, no real claude, no sleeping.
Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import json
import os
import subprocess
import tempfile
import unittest
from types import SimpleNamespace

import teach_label as label
import teach_segments as seg


# MARK: Helpers

def printed(result="ok", cost=0.25, is_error=False):
    return json.dumps({"type": "result", "is_error": is_error, "result": result,
                       "total_cost_usd": cost})


class FakeRunner:
    """Stands in for subprocess.run: records each call and returns the given output."""

    def __init__(self, stdout="", stderr="", returncode=0, raises=None):
        self.stdout, self.stderr, self.returncode, self.raises = stdout, stderr, returncode, raises
        self.calls = []
        self.folder_was_empty = None

    def __call__(self, args, **kwargs):
        self.calls.append((args, kwargs))
        self.folder_was_empty = os.listdir(kwargs["cwd"]) == []
        if self.raises:
            raise self.raises
        return SimpleNamespace(returncode=self.returncode, stdout=self.stdout, stderr=self.stderr)


def ask_with(runner, system="SYS", prompt="PROMPT", environment=None):
    return label.ask_claude(system, prompt, "claude-test", "/bin/claude", runner=runner,
                            environment=environment if environment is not None else {})


def answer(*spans, sort="sponsor", who="Acme"):
    """Claude's answer text for (first, last) spans."""
    return json.dumps({"segments": [
        {"first": a, "last": b, "sort": sort, "who": who, "delivery": "host",
         "confidence": "high", "why": "x"} for a, b in spans]})


def transcript(count, start=0.0):
    return "".join("[00:%02d:%04.1f] line %d\n" % ((start + n) // 60, (start + n) % 60, n + 1)
                   for n in range(count))


def entry(number, show="Show"):
    return {"id": "%012x" % number, "feed": "https://feed/%d" % number, "show": show,
            "title": "Episode %d" % number}


class Teaching:
    """A temporary teaching folder."""

    def __init__(self, test, count, with_transcripts=None):
        self.dir = tempfile.mkdtemp()
        test.addCleanup(lambda: __import__("shutil").rmtree(self.dir, ignore_errors=True))
        self.entries = [entry(n) for n in range(1, count + 1)]
        with open(os.path.join(self.dir, "episodes.json"), "w") as f:
            json.dump({"version": 1, "writtenAt": 1, "episodes": self.entries}, f)
        os.makedirs(os.path.join(self.dir, "transcripts"))
        for item in self.entries:
            self.write_transcript(item, transcript(10) if with_transcripts is None
                                  else with_transcripts)

    def write_transcript(self, item, text):
        with open(os.path.join(self.dir, "transcripts", item["id"] + ".txt"), "w") as f:
            f.write(text)

    def label_path(self, item, labels="labels"):
        return os.path.join(self.dir, labels, item["id"] + ".json")

    def labels(self, labels="labels"):
        folder = os.path.join(self.dir, labels)
        return sorted(os.listdir(folder)) if os.path.isdir(folder) else []


# MARK: find_claude and ask_claude

class FindClaudeTests(unittest.TestCase):
    def make(self, folder):
        os.makedirs(folder, exist_ok=True)
        path = os.path.join(folder, "claude")
        with open(path, "w") as f:
            f.write("#!/bin/sh\n")
        os.chmod(path, 0o755)
        return path

    def test_path_first_then_home_folders(self):
        home = tempfile.mkdtemp()
        self.addCleanup(lambda: __import__("shutil").rmtree(home, ignore_errors=True))
        env = {"HOME": home, "PATH": os.path.join(home, "none") + ":" + os.path.join(home, "bin")}
        self.assertIsNone(label.find_claude(env))
        local = self.make(os.path.join(home, ".local", "bin"))
        self.assertEqual(label.find_claude(env), local)
        on_path = self.make(os.path.join(home, "bin"))
        self.assertEqual(label.find_claude(env), on_path)

    def test_a_file_that_is_not_executable_is_not_found(self):
        home = tempfile.mkdtemp()
        self.addCleanup(lambda: __import__("shutil").rmtree(home, ignore_errors=True))
        path = self.make(os.path.join(home, "bin"))
        os.chmod(path, 0o644)
        self.assertIsNone(label.find_claude({"HOME": home, "PATH": os.path.join(home, "bin")}))


class AskClaudeTests(unittest.TestCase):
    def test_exact_arguments_prompt_on_stdin_and_environment(self):
        runner = FakeRunner(stdout=printed("hello", 0.5))
        out = ask_with(runner, environment={"ANTHROPIC_API_KEY": "secret", "HOME": "/h"})
        args, kwargs = runner.calls[0]
        self.assertEqual(args, ["/bin/claude", "-p", "--output-format", "json",
                                "--no-session-persistence", "--tools", "", "--strict-mcp-config",
                                "--disable-slash-commands", "--model", "claude-test",
                                "--system-prompt", "SYS"])
        self.assertEqual(kwargs["input"], "PROMPT")
        self.assertNotIn("PROMPT", " ".join(args))
        self.assertNotIn("ANTHROPIC_API_KEY", kwargs["env"])
        self.assertEqual(kwargs["env"]["ENABLE_CLAUDEAI_MCP_SERVERS"], "false")
        self.assertEqual(kwargs["env"]["HOME"], "/h")
        self.assertEqual(kwargs["timeout"], 900)
        self.assertTrue(runner.folder_was_empty)
        self.assertFalse(os.path.exists(kwargs["cwd"]))
        self.assertEqual(out, {"text": "hello", "cost": 0.5})

    def test_the_callers_environment_is_not_changed(self):
        env = {"ANTHROPIC_API_KEY": "secret"}
        ask_with(FakeRunner(stdout=printed()), environment=env)
        self.assertEqual(env, {"ANTHROPIC_API_KEY": "secret"})

    def test_cost_is_zero_when_absent(self):
        runner = FakeRunner(stdout=json.dumps({"type": "result", "result": "hi"}))
        self.assertEqual(ask_with(runner)["cost"], 0.0)

    def test_reads_the_last_line_when_there_are_several(self):
        runner = FakeRunner(stdout='{"type": "system"}\n' + printed("last") + "\n")
        self.assertEqual(ask_with(runner)["text"], "last")

    def usage_error(self, message, **kwargs):
        return FakeRunner(stdout=printed(message, is_error=True), returncode=1, **kwargs)

    def test_usage_limit_kinds(self):
        for message in ("Claude AI usage limit reached", "429 rate limit", "Not logged in",
                        "Please run /login", "Invalid API key", "OAuth token expired"):
            with self.assertRaises(label.UsageLimit, msg=message):
                ask_with(self.usage_error(message))

    def test_other_errors_are_plain_runtime_errors(self):
        cases = [self.usage_error("something broke"),
                 FakeRunner(stdout=printed("fine"), returncode=1),
                 FakeRunner(stdout=printed("bad", is_error=True)),
                 FakeRunner(stdout="not json", stderr="oops", returncode=1),
                 FakeRunner(stdout=printed("overloaded_error", is_error=True), returncode=1),
                 FakeRunner(raises=subprocess.TimeoutExpired("claude", 900)),
                 FakeRunner(raises=OSError("gone"))]
        for runner in cases:
            with self.assertRaises(RuntimeError) as caught:
                ask_with(runner)
            self.assertNotIsInstance(caught.exception, label.UsageLimit)
            self.assertNotIn("PROMPT", str(caught.exception))

    def test_no_result_text_is_an_error(self):
        runner = FakeRunner(stdout=json.dumps({"type": "result", "is_error": False}))
        with self.assertRaises(RuntimeError):
            ask_with(runner)


# MARK: label_episode

class LabelEpisodeTests(unittest.TestCase):
    def lines(self, count):
        return seg.read_transcript(transcript(count))

    def test_one_part(self):
        asked = []

        def ask(prompt):
            asked.append(prompt)
            return {"text": answer((2, 4)), "cost": 0.1}

        result = label.label_episode(entry(1), self.lines(10), "m1", ask, now=lambda: 5.0)
        self.assertEqual(len(asked), 1)
        self.assertEqual((result["version"], result["prompt"], result["model"]), (1, "t1", "m1"))
        self.assertEqual((result["episode"], result["feed"], result["show"]),
                         ("000000000001", "https://feed/1", "Show"))
        self.assertEqual((result["lines"], result["length"]), (10, 9.0))
        self.assertEqual(result["segments"][0]["start"], 1.0)
        self.assertEqual(result["segments"][0]["end"], 4.0)
        self.assertEqual((result["dropped"], result["cost"], result["writtenAt"]), (0, 0.1, 5000))

    def test_two_parts_join_a_stretch_split_at_the_boundary(self):
        # Each line's text is 6 to 7 characters, so a limit of 20 gives about three lines a part.
        lines = self.lines(6)
        ranges = seg.parts(lines, 20)
        self.assertEqual(len(ranges), 2)
        first_part, second_part = ranges
        replies = [answer((first_part[1] - 1, first_part[1])),
                   answer((second_part[0], second_part[0] + 1))]
        prompts = []

        def ask(prompt):
            prompts.append(prompt)
            return {"text": replies[len(prompts) - 1], "cost": 0.2}

        result = label.label_episode(entry(1), lines, "m", ask, limit=20)
        self.assertEqual(len(prompts), 2)
        self.assertIn("lines %d to %d of 6" % second_part, prompts[1])
        self.assertEqual(len(result["segments"]), 1)
        self.assertEqual((result["segments"][0]["first"], result["segments"][0]["last"]),
                         (first_part[1] - 1, second_part[0] + 1))
        self.assertAlmostEqual(result["cost"], 0.4)

    def test_a_bad_answer_is_asked_for_once_more(self):
        replies = ["no json at all", answer((1, 2))]
        asked = []

        def ask(prompt):
            asked.append(prompt)
            return {"text": replies[len(asked) - 1], "cost": 0.1}

        result = label.label_episode(entry(1), self.lines(5), "m", ask)
        self.assertEqual(len(asked), 2)
        self.assertEqual(len(result["segments"]), 1)
        self.assertAlmostEqual(result["cost"], 0.2)

    def test_two_bad_answers_raise(self):
        with self.assertRaises(ValueError):
            label.label_episode(entry(1), self.lines(5), "m",
                                lambda prompt: {"text": "nope", "cost": 0.0})


# MARK: run

class RunTests(unittest.TestCase):
    def fake_ask(self, cost=0.1, text=None, log=None):
        def ask(prompt):
            if log is not None:
                log.append(prompt)
            return {"text": text or answer((1, 2)), "cost": cost}
        return ask

    def go(self, teaching, ask, **options):
        said = []
        settings = {"labels": "labels", "model": "m", "limit": None, "cap": None}
        settings.update(options)
        result = label.run(teaching.dir, settings["labels"], settings["model"], settings["limit"],
                           settings["cap"], ask, say=said.append)
        return result, said

    def test_writes_a_label_per_episode_and_reports(self):
        teaching = Teaching(self, 2)
        result, said = self.go(teaching, self.fake_ask())
        self.assertEqual(teaching.labels(), [e["id"] + ".json" for e in teaching.entries])
        with open(teaching.label_path(teaching.entries[0])) as f:
            self.assertEqual(json.load(f)["episode"], teaching.entries[0]["id"])
        self.assertEqual(result["done"], 2)
        self.assertIsNone(result["stop"])
        self.assertIn("1 of 2", said[0])
        self.assertIn("Episode 1", said[0])
        self.assertIn("1 sponsor", said[0])
        self.assertIn("$0.10", said[0])
        self.assertIn("$0.20", said[1])

    def test_no_temporary_files_are_left(self):
        teaching = Teaching(self, 1)
        self.go(teaching, self.fake_ask())
        self.assertTrue(all(name.endswith(".json") for name in teaching.labels()))

    def test_resumes_without_asking_again(self):
        teaching = Teaching(self, 3)
        self.go(teaching, self.fake_ask(), limit=2)
        log = []
        result, _ = self.go(teaching, self.fake_ask(log=log))
        self.assertEqual((len(log), result["done"]), (1, 1))
        self.assertEqual(len(teaching.labels()), 3)

    def test_a_second_labels_folder_is_independent(self):
        teaching = Teaching(self, 1)
        self.go(teaching, self.fake_ask())
        log = []
        self.go(teaching, self.fake_ask(log=log), labels="other")
        self.assertEqual(len(log), 1)
        self.assertEqual(len(teaching.labels("other")), 1)

    def test_episodes_without_a_transcript_are_not_waiting(self):
        teaching = Teaching(self, 2)
        os.remove(os.path.join(teaching.dir, "transcripts", teaching.entries[0]["id"] + ".txt"))
        log = []
        self.go(teaching, self.fake_ask(log=log))
        self.assertEqual(len(log), 1)

    def test_a_transcript_without_lines_is_skipped_with_one_line(self):
        teaching = Teaching(self, 2)
        teaching.write_transcript(teaching.entries[0], "nothing usable\n")
        result, said = self.go(teaching, self.fake_ask())
        self.assertEqual(result["done"], 1)
        self.assertEqual(len([s for s in said if "no usable lines" in s]), 1)

    def test_limit(self):
        teaching = Teaching(self, 3)
        result, _ = self.go(teaching, self.fake_ask(), limit=2)
        self.assertEqual((result["done"], result["stop"]), (2, "limit"))
        self.assertEqual(len(teaching.labels()), 2)

    def test_cap(self):
        teaching = Teaching(self, 4)
        result, said = self.go(teaching, self.fake_ask(cost=0.5), cap=1.0)
        self.assertEqual((result["done"], result["stop"]), (2, "cap"))
        self.assertIn("$1.00", said[-1])

    def test_usage_limit_stops_at_once_and_keeps_the_work(self):
        teaching = Teaching(self, 4)
        calls = []

        def ask(prompt):
            calls.append(prompt)
            if len(calls) == 3:
                raise label.UsageLimit("usage limit reached")
            return {"text": answer((1, 2)), "cost": 0.1}

        result, said = self.go(teaching, ask)
        self.assertEqual((result["done"], result["stop"]), (2, "usage"))
        self.assertEqual(len(calls), 3)
        self.assertEqual(len(teaching.labels()), 2)

    def test_three_failures_in_a_row_stop(self):
        teaching = Teaching(self, 6)

        def ask(prompt):
            raise RuntimeError("broken")

        result, _ = self.go(teaching, ask)
        self.assertEqual((result["done"], result["failed"], result["stop"]), (0, 3, "failures"))

    def test_a_success_resets_the_failure_count(self):
        teaching = Teaching(self, 6)
        calls = []

        def ask(prompt):
            calls.append(prompt)
            if len(calls) in (1, 2, 4, 5):
                raise RuntimeError("broken")
            return {"text": answer((1, 2)), "cost": 0.0}

        result, _ = self.go(teaching, ask)
        self.assertEqual((result["done"], result["failed"], result["stop"]), (2, 4, None))


# MARK: main

class MainTests(unittest.TestCase):
    def setUp(self):
        self.said = []
        self.home = tempfile.mkdtemp()
        self.addCleanup(lambda: __import__("shutil").rmtree(self.home, ignore_errors=True))
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
                          runner=runner, environment=self.environment, say=self.said.append)
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

    def test_anything_but_yes_does_nothing(self):
        teaching = Teaching(self, 2)
        for typed in ("no", "", "y", "yes please"):
            code, _, runner = self.main(teaching, typed=typed)
            self.assertEqual((code, len(runner.calls), teaching.labels()), (0, 0, []), typed)

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
        self.addCleanup(lambda: __import__("shutil").rmtree(empty.dir, ignore_errors=True))
        self.assertEqual(self.main(empty)[0], 2)
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

    def test_entries_without_a_usable_id_are_left_out(self):
        teaching = Teaching(self, 1)
        path = os.path.join(teaching.dir, "episodes.json")
        with open(path, "w") as f:
            json.dump({"version": 1, "episodes": [{"id": "../x"}, {"id": 5}, "text", {},
                                                  entry(1)]}, f)
        self.assertEqual([e["id"] for e in label.read_episodes(teaching.dir)], ["000000000001"])


if __name__ == "__main__":
    unittest.main()
