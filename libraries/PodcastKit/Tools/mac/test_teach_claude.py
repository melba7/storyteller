"""Tests for teach_claude.py: finding claude, one claude run (against a fake runner), the wording
that means "usage limit or not signed in", and the fixed working folder. No real claude.
Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import json
import os
import shutil
import tempfile
import unittest

import teach_claude as claude
from teach_testing import FakeRunner, printed, timeout


class FindClaudeTests(unittest.TestCase):
    def make(self, folder):
        os.makedirs(folder, exist_ok=True)
        path = os.path.join(folder, "claude")
        with open(path, "w") as f:
            f.write("#!/bin/sh\n")
        os.chmod(path, 0o755)
        return path

    def home(self):
        home = tempfile.mkdtemp()
        self.addCleanup(lambda: shutil.rmtree(home, ignore_errors=True))
        return home

    def test_path_first_then_the_install_folders_given(self):
        home = self.home()
        env = {"HOME": home, "PATH": os.path.join(home, "none") + ":" + os.path.join(home, "bin")}
        self.assertIsNone(claude.find_claude(env, extra_folders=(".local/bin",)))
        local = self.make(os.path.join(home, ".local", "bin"))
        self.assertEqual(claude.find_claude(env, extra_folders=(".local/bin",)), local)
        on_path = self.make(os.path.join(home, "bin"))
        self.assertEqual(claude.find_claude(env, extra_folders=(".local/bin",)), on_path)

    def test_absolute_folders_are_looked_in_as_they_are(self):
        home = self.home()
        folder = os.path.join(self.home(), "installed")
        path = self.make(folder)
        self.assertEqual(claude.find_claude({"HOME": home, "PATH": ""}, extra_folders=(folder,)), path)
        self.assertIsNone(claude.find_claude({"HOME": home, "PATH": ""}, extra_folders=()))

    def test_the_default_folders_are_the_swift_codes(self):
        self.assertEqual(claude.EXTRA_FOLDERS, (".local/bin", ".claude/local", "/opt/homebrew/bin",
                                                "/usr/local/bin"))

    def test_a_file_that_is_not_executable_is_not_found(self):
        home = self.home()
        path = self.make(os.path.join(home, "bin"))
        os.chmod(path, 0o644)
        self.assertIsNone(claude.find_claude({"HOME": home, "PATH": os.path.join(home, "bin")}, extra_folders=()))


class UsageLimitWordingTests(unittest.TestCase):
    def test_usage_rate_and_signed_out_wording_is_matched(self):
        for message in ("Claude AI usage limit reached|1760000000", "429 rate limit", "rate_limit_error",
                        "5-hour limit reached", "You've hit your limit - resets 5pm",
                        "Weekly limit reached", "Too many requests", "API Error: 429",
                        "Not logged in", "Please run /login", "Invalid API key", "OAuth token expired"):
            self.assertTrue(claude.is_usage_limit(message), message)

    def test_other_talk_of_limits_is_not_matched(self):
        for message in ("context limit reached", "Prompt is too long: context limit exceeded",
                        "FATAL ERROR: heap limit Allocation failed", "JavaScript heap out of memory (limit 4096)",
                        "MaxListenersExceededWarning: Possible EventEmitter memory leak detected. 11 "
                        "abort listeners added. Use events.setMaxListeners() to increase limit",
                        "the file size limit", "generate a separate moderate answer", "overloaded_error"):
            self.assertFalse(claude.is_usage_limit(message), message)


class AskClaudeTests(unittest.TestCase):
    def setUp(self):
        self.folder = os.path.join(tempfile.mkdtemp(), "lofi-claude-code")
        self.addCleanup(lambda: shutil.rmtree(os.path.dirname(self.folder), ignore_errors=True))

    def ask(self, runner, system="SYS", prompt="PROMPT", environment=None):
        return claude.ask_claude(system, prompt, "claude-test", "/bin/claude", runner=runner,
                                 environment=environment if environment is not None else {},
                                 folder=self.folder)

    def test_exact_arguments_prompt_on_stdin_and_environment(self):
        runner = FakeRunner(stdout=printed("hello", 0.5))
        out = self.ask(runner, environment={"ANTHROPIC_API_KEY": "secret", "HOME": "/h"})
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
        self.assertEqual(out, {"text": "hello", "cost": 0.5})

    def test_every_run_starts_in_the_same_empty_folder_which_stays(self):
        runner = FakeRunner(stdout=printed())
        self.ask(runner)
        self.ask(runner)
        self.assertEqual([call[1]["cwd"] for call in runner.calls], [self.folder, self.folder])
        self.assertTrue(runner.folder_was_empty)
        self.assertTrue(os.path.isdir(self.folder))

    def test_the_default_folder_is_one_fixed_folder_like_the_swift_codes(self):
        self.assertEqual(os.path.basename(claude.WORKING_FOLDER), "lofi-claude-code")
        self.assertEqual(os.path.dirname(claude.WORKING_FOLDER), tempfile.gettempdir())

    def test_a_folder_that_cannot_be_made_is_a_plain_failure(self):
        blocker = os.path.join(os.path.dirname(self.folder), "file")
        with open(blocker, "w") as f:
            f.write("x")
        with self.assertRaises(claude.ClaudeError):
            claude.ask_claude("S", "P", "m", "/bin/claude", runner=FakeRunner(stdout=printed()),
                              environment={}, folder=os.path.join(blocker, "inside"))

    def test_the_callers_environment_is_not_changed(self):
        env = {"ANTHROPIC_API_KEY": "secret"}
        self.ask(FakeRunner(stdout=printed()), environment=env)
        self.assertEqual(env, {"ANTHROPIC_API_KEY": "secret"})

    def test_cost_is_zero_when_absent(self):
        runner = FakeRunner(stdout=json.dumps({"type": "result", "result": "hi"}))
        self.assertEqual(self.ask(runner)["cost"], 0.0)

    def test_reads_the_last_line_when_there_are_several(self):
        runner = FakeRunner(stdout='{"type": "system"}\n' + printed("last") + "\n")
        self.assertEqual(self.ask(runner)["text"], "last")

    def usage_error(self, message, **kwargs):
        return FakeRunner(stdout=printed(message, is_error=True), returncode=1, **kwargs)

    def test_usage_limit_kinds(self):
        for message in ("Claude AI usage limit reached", "429 rate limit", "Not logged in",
                        "Please run /login", "Invalid API key", "OAuth token expired"):
            with self.assertRaises(claude.UsageLimit, msg=message):
                self.ask(self.usage_error(message))

    def test_other_errors_are_plain_runtime_errors(self):
        cases = [self.usage_error("something broke"),
                 self.usage_error("context limit reached"),
                 self.usage_error("FATAL ERROR: heap limit Allocation failed"),
                 FakeRunner(stdout=printed("fine"), returncode=1),
                 FakeRunner(stdout=printed("bad", is_error=True)),
                 FakeRunner(stdout="not json", stderr="oops", returncode=1),
                 FakeRunner(stdout="", stderr="MaxListenersExceededWarning: Possible EventEmitter "
                                              "memory leak. Use setMaxListeners() to increase limit", returncode=1),
                 FakeRunner(stdout=printed("overloaded_error", is_error=True), returncode=1),
                 FakeRunner(raises=timeout()),
                 FakeRunner(raises=OSError("gone"))]
        for runner in cases:
            with self.assertRaises(RuntimeError) as caught:
                self.ask(runner)
            self.assertNotIsInstance(caught.exception, claude.UsageLimit)
            self.assertNotIn("PROMPT", str(caught.exception))

    def test_usage_limit_in_the_raw_output_when_there_is_no_result_object(self):
        for runner in (FakeRunner(stdout="Claude AI usage limit reached|1760000000", returncode=1),
                       FakeRunner(stdout="Claude AI usage limit reached", stderr="Warning: node thing",
                                  returncode=1),
                       FakeRunner(stderr="Error: Not logged in", returncode=1),
                       FakeRunner(stdout="x" * 500 + " usage limit reached " + "y" * 500, returncode=1)):
            with self.assertRaises(claude.UsageLimit):
                self.ask(runner)

    def test_a_failed_run_carries_what_it_cost(self):
        runner = FakeRunner(stdout=printed("usage limit reached", cost=1.5, is_error=True), returncode=1)
        with self.assertRaises(claude.UsageLimit) as caught:
            self.ask(runner)
        self.assertEqual(caught.exception.cost, 1.5)
        with self.assertRaises(claude.ClaudeError) as caught:
            self.ask(FakeRunner(stdout=printed("broke", cost=0.75, is_error=True), returncode=1))
        self.assertEqual(caught.exception.cost, 0.75)

    def test_no_result_text_is_an_error(self):
        runner = FakeRunner(stdout=json.dumps({"type": "result", "is_error": False}))
        with self.assertRaises(RuntimeError):
            self.ask(runner)


if __name__ == "__main__":
    unittest.main()
