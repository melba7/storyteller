"""Tests for the launcher "Free space and start the next run": it runs "Free up space from the teaching
audio" as a step of a chain, asks one typed yes for a NEW budget of up to $95, and starts "Gather more
episodes for teaching" on the newest 30 of each show with the marking allowed at any hour. The two steps are
stand-ins that write down how they were called and exit with the code a test asks for, so nothing is
deleted, downloaded or marked and no Claude is used.
Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import os
import re
import shutil
import stat
import subprocess
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
NAME = "Free space and start the next run.command"
FREE = "Free up space from the teaching audio.command"
MORE = "Gather more episodes for teaching.command"
STEP = """#!/bin/bash
case "$(basename "$0")" in
  Free*) echo "free chain=${TEACH_CHAIN:-}" >> "$CALLS"; exit "${FREE_CODE:-0}" ;;
  Gather*) echo "more chain=${TEACH_CHAIN:-} per_show=${TEACH_PER_SHOW:-} max_gb=${TEACH_MAX_GB:-} budget=${TEACH_BUDGET:-} cap=${TEACH_CAP:-} yes=${TEACH_YES:-} between=${TEACH_BETWEEN:-}" >> "$CALLS"; exit "${MORE_CODE:-0}" ;;
esac
"""


class FileTests(unittest.TestCase):
    def test_it_is_a_runnable_bash_file_for_bash_3_2(self):
        path = os.path.join(HERE, NAME)
        self.assertTrue(os.stat(path).st_mode & stat.S_IXUSR)
        with open(path, encoding="utf-8") as f:
            text = f.read()
        self.assertEqual(text.splitlines()[0], "#!/bin/bash")
        self.assertEqual(subprocess.run(["bash", "-n", path]).returncode, 0)
        code = "".join(line for line in text.splitlines(True) if not line.lstrip().startswith("#"))
        for pattern in (r"declare\s+-A", r"\bmapfile\b", r"\breadarray\b", r"\$\{[A-Za-z_]+(,,|\^\^)\}",
                        r"\$\(<<", r"&>>?", r"\|&", r"\bcoproc\b", r"\bsed\s+-i\b"):
            self.assertIsNone(re.search(pattern, code), pattern)
        self.assertIn("finish()", text)
        self.assertIn('HERE="$(cd "$(dirname "$0")" && pwd)"', text)
        self.assertLess(len(text.splitlines()), 300)

    def test_the_readme_lists_it(self):
        with open(os.path.join(HERE, "README.md"), encoding="utf-8") as f:
            self.assertIn(NAME, f.read())


class LauncherTests(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.root, ignore_errors=True)
        self.tools = os.path.join(self.root, "tools")
        os.makedirs(self.tools)
        self.home = os.path.join(self.root, "home")
        self.folder = os.path.join(self.home, "Storyteller Lofi", "PodcastTeaching")
        shutil.copyfile(os.path.join(HERE, NAME), os.path.join(self.tools, NAME))
        for name in (FREE, MORE):
            path = os.path.join(self.tools, name)
            with open(path, "w") as handle:
                handle.write(STEP)
            os.chmod(path, os.stat(path).st_mode | stat.S_IXUSR)
        self.calls = os.path.join(self.root, "calls.txt")

    def run_launcher(self, typed="yes\n\n", **extra):
        env = {"HOME": self.home, "PATH": "/usr/bin:/bin", "CALLS": self.calls}
        env.update(extra)
        return subprocess.run(["/bin/bash", os.path.join(self.tools, NAME)], input=typed, env=env,
                              capture_output=True, text=True, timeout=60)

    def ran(self):
        if not os.path.exists(self.calls):
            return []
        with open(self.calls) as handle:
            return [line.strip() for line in handle if line.strip()]

    def budget_file(self):
        with open(os.path.join(self.folder, "current-budget.txt")) as handle:
            return handle.read().strip()

    def log(self):
        with open(os.path.join(self.home, "Storyteller Lofi", "logs", "podcast-teaching.log")) as handle:
            return handle.read()


class AskingTests(LauncherTests):
    def test_the_notice_says_what_goes_the_money_and_that_marking_starts_at_once(self):
        result = self.run_launcher("no\n\n")
        for words in ("$95", "newest 30 of each show", "any hour", "type all", "type yes"):
            self.assertIn(words, result.stdout)

    def test_a_yes_for_the_money_starts_the_gathering_and_the_marking_under_a_new_budget(self):
        result = self.run_launcher()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        free, more = self.ran()
        self.assertEqual(free, "free chain=1")
        match = re.fullmatch(r"more chain= per_show=30 max_gb=80 budget=(big-run-\d{8}-\d{4}) cap=95 yes=1 "
                             r"between=0-24", more)
        self.assertIsNotNone(match, more)
        self.assertEqual(self.budget_file(), match.group(1))
        self.assertIn("new budget " + match.group(1), self.log())

    def test_the_money_is_asked_after_the_freeing_and_never_before(self):
        result = self.run_launcher()
        self.assertLess(result.stdout.index("Step 1 of 2"), result.stdout.index("Step 2 of 2"))
        self.assertLess(result.stdout.index("Step 2 of 2"), result.stdout.index("NEW budget"))
        self.assertNotIn("NEW budget", result.stdout[:result.stdout.index("Step 1 of 2")])

    def test_anything_but_yes_starts_no_run_and_writes_no_budget(self):
        for typed in ("\n", "", "no\n", "y\n", "ye s\n", "yes please\n", "all\n"):
            if os.path.exists(self.calls):
                os.remove(self.calls)
            result = self.run_launcher(typed)
            self.assertEqual(result.returncode, 0, typed)
            self.assertEqual(self.ran(), ["free chain=1"], typed)
            self.assertIn("Nothing was started", result.stdout, typed)
            self.assertFalse(os.path.exists(os.path.join(self.folder, "current-budget.txt")), typed)

    def test_teach_yes_in_the_environment_does_not_answer_for_you(self):
        result = self.run_launcher("\n", TEACH_YES="1", TEACH_CHAIN="1")
        self.assertEqual(self.ran(), ["free chain=1"])
        self.assertIn("Nothing was started", result.stdout)

    def test_the_cap_can_be_changed_but_a_bad_value_goes_back_to_95(self):
        self.run_launcher(TEACH_CAP="40")
        self.assertIn("cap=40", self.ran()[1])
        os.remove(self.calls)
        self.run_launcher(TEACH_CAP="lots")
        self.assertIn("cap=95", self.ran()[1])


class StepTests(LauncherTests):
    def test_a_backup_that_was_not_good_stops_everything(self):
        result = self.run_launcher(FREE_CODE="1")
        self.assertEqual(self.ran(), ["free chain=1"])
        self.assertIn("backup", result.stdout)
        self.assertEqual(result.returncode, 1)

    def test_a_run_that_is_still_working_stops_everything_and_says_to_wait(self):
        result = self.run_launcher(FREE_CODE="3")
        self.assertEqual(self.ran(), ["free chain=1"])
        self.assertIn("still working", result.stdout)
        self.assertEqual(result.returncode, 3)

    def test_a_freeing_that_could_not_look_at_the_folder_stops_everything(self):
        result = self.run_launcher(FREE_CODE="2")
        self.assertEqual(self.ran(), ["free chain=1"])
        self.assertEqual(result.returncode, 2)

    def test_a_partial_delete_still_goes_on_to_the_run_and_says_so(self):
        result = self.run_launcher(FREE_CODE="4")
        self.assertEqual(len(self.ran()), 2)
        self.assertIn("some files could not be deleted", result.stdout)

    def test_a_missing_step_starts_nothing(self):
        os.remove(os.path.join(self.tools, MORE))
        result = self.run_launcher()
        self.assertEqual(self.ran(), [])
        self.assertEqual(result.returncode, 2)
        self.assertIn("missing", result.stdout)

    def test_a_budget_file_that_cannot_be_written_starts_nothing(self):
        os.makedirs(os.path.dirname(self.folder))
        with open(self.folder, "w") as handle:  # a plain file where the teaching folder should be
            handle.write("not a folder")
        result = self.run_launcher()
        self.assertEqual(self.ran(), ["free chain=1"])
        self.assertEqual(result.returncode, 2)
        self.assertIn("Could not write", result.stdout)


if __name__ == "__main__":
    unittest.main()
