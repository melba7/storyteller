"""Tests for the two launchers that came with the backups: "Back up the teaching marks" (one backup,
checked) and "Start another big run" (a new $95 budget, started only by a typed yes). They run with
stand-in programs on a temporary PATH and home, as test_teach_night_launchers.py does. No Mac, no
network, no Claude.
Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import os
import re
import stat
import subprocess
import sys
import unittest

import teach_budget
from test_teach_night_launchers import HERE, MORE, Setup

BACKUP_NAME = "Back up the teaching marks.command"
BIG = "Start another big run.command"
SECOND_NAME = "Second downloads then gather more.command"
DATE = '''#!/bin/bash
# stand-in for date: the minute stamp of the budget name is the one the test names
case "$1" in "+%Y%m%d-%H%M") [ -n "$FAKE_STAMP" ] && { echo "$FAKE_STAMP"; exit 0; } ;; esac
exec /bin/date "$@"
'''
# What the Mac's own "Second downloads then gather more" does at its end (it is only on the Mac, so a
# stand-in plays it): gives the typed yes for the marking and starts "Gather more episodes".
SECOND = '''#!/bin/bash
echo "second started budget=$TEACH_BUDGET yes=$TEACH_YES cap=$TEACH_CAP" >> "$CALLS"
[ -n "$CHAIN" ] || exit 0
TEACH_YES=1
export TEACH_YES
exec "%s"
''' % os.path.join(HERE, MORE)


class FilesTests(unittest.TestCase):
    def test_both_are_runnable_bash_files_for_bash_3_2(self):
        for name in (BACKUP_NAME, BIG):
            path = os.path.join(HERE, name)
            self.assertTrue(os.stat(path).st_mode & stat.S_IXUSR, name)
            with open(path, encoding="utf-8") as f:
                text = f.read()
            self.assertEqual(text.splitlines()[0], "#!/bin/bash", name)
            self.assertEqual(subprocess.run(["bash", "-n", path]).returncode, 0, name)
            code = "".join(line for line in text.splitlines(True) if not line.lstrip().startswith("#"))
            for pattern in (r"declare\s+-A", r"\bmapfile\b", r"\breadarray\b", r"\$\{[A-Za-z_]+(,,|\^\^)\}",
                            r"\$\(<<", r"&>>?", r"\|&", r"\bcoproc\b", r"\bsed\s+-i\b"):
                self.assertIsNone(re.search(pattern, code), (name, pattern))
            self.assertIn("finish()", text, name)
            self.assertIn('HERE="$(cd "$(dirname "$0")" && pwd)"', text, name)
            self.assertIn("Press Return to close this window", text, name)
            self.assertLess(len(text.splitlines()), 300, name)

    def test_the_readme_lists_both(self):
        with open(os.path.join(HERE, "README.md"), encoding="utf-8") as f:
            readme = f.read()
        for name in (BACKUP_NAME, BIG):
            self.assertIn(name, readme)


class BackupLauncherTests(Setup):
    def setUp(self):
        super().setUp()
        os.makedirs(os.path.join(self.folder, "labels"))

    def test_it_makes_and_checks_one_backup_and_says_so(self):
        done = self.run_script(BACKUP_NAME)
        self.assertEqual(done.returncode, 0, done.stdout)
        self.assertEqual(self.called(), ["python3 teach_backup.py make --check --folder FOLDER"])
        self.assertIn("Done", done.stdout)
        self.assertIn(os.path.join("Storyteller Lofi", "PodcastTeachingBackups"), done.stdout)

    def test_the_real_tool_leaves_a_whole_backup_and_the_window_says_so(self):
        with open(os.path.join(self.folder, "labels", "a.json"), "w") as f:
            f.write('{"ads": []}')
        done = self.run_script(BACKUP_NAME, TEACH_TOOLS=HERE, TOOLS=HERE)
        self.assertEqual(done.returncode, 0, done.stdout)
        self.assertIn("is whole", done.stdout)
        backups = os.path.join(self.home, "Storyteller Lofi", "PodcastTeachingBackups")
        self.assertEqual(len(os.listdir(backups)), 1)

    def test_a_backup_that_fails_the_check_is_not_called_done(self):
        done = self.run_script(BACKUP_NAME, FAIL="teach_backup.py", REAL_PYTHON="")  # the stand-in fails
        self.assertEqual(done.returncode, 1)
        self.assertNotIn("Done", done.stdout)
        self.assertIn("did not work", done.stdout)

    def test_with_no_teaching_folder_it_says_so_and_runs_nothing(self):
        os.rmdir(os.path.join(self.folder, "labels"))
        os.rmdir(self.folder)
        done = self.run_script(BACKUP_NAME)
        self.assertEqual(done.returncode, 2)
        self.assertIn("There is no teaching folder", done.stdout)
        self.assertEqual(self.called(), [])

    def test_it_uses_no_claude_usage_and_is_noted_in_the_log(self):
        done = self.run_script(BACKUP_NAME)
        self.assertIn("no Claude", done.stdout)
        self.assertRegex(self.log(), r"=== \d{4}-\d\d-\d\d \d\d:\d\d backup ===")
        self.assertFalse([c for c in self.called() if "teach_label.py" in c])


class BigRunTests(Setup):
    def setUp(self):
        super().setUp()
        path = os.path.join(self.bin, "date")
        with open(path, "w") as f:
            f.write(DATE)
        os.chmod(path, 0o755)
        self.second = os.path.join(self.root, SECOND_NAME)
        with open(self.second, "w") as f:
            f.write(SECOND)
        os.chmod(self.second, 0o755)

    def run_big(self, typed="yes\n", **more):
        env = {"TEACH_SECOND": self.second, "FAKE_STAMP": "20261125-0501"}
        env.update(more)
        return self.run_script(BIG, typed=typed, **env)

    def started(self):
        return [c for c in self.called() if c.startswith("second started")]

    def test_it_says_plainly_that_it_starts_a_new_budget_and_what_it_may_cost(self):
        done = self.run_big(typed="\n")
        for text in ("NEW budget", "$95", "$0.19 an", "480 episodes", "Claude plan",
                     "between 11 at night and 7 in the morning", "type yes again"):
            self.assertIn(text, done.stdout)
        self.assertIn('read -r -p "Type yes to start a new budget of up to', self.source(BIG))

    def test_anything_but_yes_changes_nothing_and_starts_nothing(self):
        for typed in ("\n", "", "no\n", "y\n", "ye s\n", "yes please\n", "yess\n", "0\n", "1\n", "sure\n"):
            open(self.calls, "w").close()
            done = self.run_big(typed=typed)
            self.assertEqual(done.returncode, 0, (typed, done.stdout))
            self.assertEqual(self.called(), [], typed)
            self.assertIn("Nothing was started and nothing was changed.", done.stdout, typed)
            self.assertNotIn("big-run-20261125-0501", done.stdout, typed)

    def test_teach_yes_in_the_environment_does_not_answer_for_you(self):
        for value in ("1", "yes"):
            open(self.calls, "w").close()
            done = self.run_big(typed="\n", TEACH_YES=value)
            self.assertEqual(self.called(), [], value)
            self.assertIn("Nothing was started", done.stdout)

    def test_a_typed_yes_starts_the_old_launcher_under_a_new_budget_with_the_yes_given(self):
        done = self.run_big()
        self.assertEqual(done.returncode, 0, done.stdout)
        self.assertEqual(self.started(), ["second started budget=big-run-20261125-0501 yes=1 cap=95"])
        self.assertEqual(self.source(BIG).count('read -r -p "Type yes'), 1)  # it asks once

    def test_yes_is_taken_in_any_case_with_spaces_around_it(self):
        self.run_big(typed="  Yes \n")
        self.assertEqual(len(self.started()), 1)

    def test_the_budget_name_is_new_every_minute(self):
        names = []
        for stamp in ("20261125-0501", "20261125-0502", "20261126-0501"):
            open(self.calls, "w").close()
            self.run_big(FAKE_STAMP=stamp)
            names.append(re.search(r"budget=(\S+)", self.started()[0]).group(1))
        self.assertEqual(names, ["big-run-20261125-0501", "big-run-20261125-0502", "big-run-20261126-0501"])
        self.assertEqual(len(set(names)), 3)

    def test_the_budget_name_comes_from_the_clock_when_nothing_is_faked(self):
        done = self.run_big(FAKE_STAMP="")
        self.assertEqual(done.returncode, 0, done.stdout)
        self.assertRegex(self.started()[0], r"budget=big-run-\d{8}-\d{4} ")

    def test_the_name_is_one_the_budget_file_accepts_and_it_starts_from_zero(self):
        self.run_big(FAKE_STAMP="20261125-0501")
        name = re.search(r"budget=(\S+)", self.started()[0]).group(1)
        self.assertRegex(name, teach_budget.NAME)
        os.makedirs(self.folder, exist_ok=True)  # the launcher made it to write current-budget.txt
        with open(os.path.join(self.folder, "marking-spend.json"), "w") as f:
            f.write('{"version": 1, "budgets": {"big-run-1": {"dollars": 40.0, "episodes": 200}}}')
        budget = teach_budget.Budget(self.folder, name, 95)
        self.assertEqual((budget.dollars, budget.left()), (0.0, 95))

    def test_the_cap_follows_teach_cap_when_it_is_set(self):
        done = self.run_big(TEACH_CAP="40")
        self.assertIn("up to $40", done.stdout)
        self.assertIn("cap=40", self.started()[0])

    def test_the_log_says_which_budget_was_started_and_when_nothing_was(self):
        self.run_big()
        self.assertRegex(self.log(), r"=== \d{4}-\d\d-\d\d \d\d:\d\d big run: new budget big-run-20261125-0501 ===")
        self.run_big(typed="no\n")
        self.assertIn("big run: not started", self.log())

    def test_it_finds_the_old_launcher_in_the_podcast_teaching_folder_on_the_mac(self):
        wrappers = os.path.join(self.home, "Storyteller Lofi", "Podcast teaching")
        os.makedirs(wrappers)
        os.replace(self.second, os.path.join(wrappers, SECOND_NAME))
        done = self.run_script(BIG, typed="yes\n", FAKE_STAMP="20261125-0501")
        self.assertEqual(done.returncode, 0, done.stdout)
        self.assertEqual(len(self.started()), 1)

    def test_when_the_old_launcher_is_missing_it_says_so_before_asking_and_starts_nothing(self):
        done = self.run_script(BIG, typed="yes\n", TEACH_SECOND=os.path.join(self.root, "gone.command"))
        self.assertEqual(done.returncode, 2)
        self.assertIn("is missing, so nothing can be started", done.stdout)
        self.assertNotIn("NEW budget", done.stdout)
        self.assertEqual(self.called(), [])

    def written(self):
        path = os.path.join(self.folder, "current-budget.txt")
        if not os.path.exists(path):
            return None
        with open(path, "rb") as f:
            return f.read()

    def test_a_typed_yes_writes_the_new_budget_name_to_current_budget_txt_as_one_line(self):
        self.run_big()
        self.assertEqual(self.written(), b"big-run-20261125-0501\n")
        self.assertEqual([n for n in os.listdir(self.folder) if n != "current-budget.txt"], [])  # no temporary file

    def test_the_file_is_written_by_a_rename_so_it_is_never_half_written(self):
        self.assertIn("mv ", self.source(BIG))

    def test_it_replaces_the_name_of_an_earlier_run(self):
        os.makedirs(self.folder)
        with open(os.path.join(self.folder, "current-budget.txt"), "w") as f:
            f.write("big-run-20261124-1000\n")
        self.run_big()
        self.assertEqual(self.written(), b"big-run-20261125-0501\n")

    def test_without_a_typed_yes_the_file_is_not_written_and_the_folder_is_not_made(self):
        for typed in ("\n", "", "no\n", "y\n", "ye s\n"):
            self.run_big(typed=typed)
            self.assertIsNone(self.written(), typed)
            self.assertFalse(os.path.exists(self.folder), typed)

    def test_without_a_typed_yes_an_earlier_name_stays_as_it_was(self):
        os.makedirs(self.folder)
        with open(os.path.join(self.folder, "current-budget.txt"), "w") as f:
            f.write("big-run-20261124-1000\n")
        self.run_big(typed="no\n")
        self.assertEqual(self.written(), b"big-run-20261124-1000\n")

    def test_the_file_is_written_before_the_old_launcher_starts(self):
        # The stand-in reads the file when it starts, as a stopped run would find it.
        with open(self.second, "w") as f:
            f.write('#!/bin/bash\necho "second saw $(cat "%s")" >> "$CALLS"\n' % os.path.join(self.folder, "current-budget.txt"))
        self.run_big()
        self.assertEqual(self.called(), ["second saw big-run-20261125-0501"])

    def test_when_the_file_cannot_be_written_nothing_is_started(self):
        os.makedirs(os.path.dirname(self.folder), exist_ok=True)
        with open(self.folder, "w") as f:  # a file where the teaching folder should be
            f.write("in the way")
        done = self.run_big()
        self.assertEqual(done.returncode, 2, done.stdout)
        self.assertEqual(self.called(), [])
        self.assertIn("current-budget.txt", done.stdout)
        self.assertIn("nothing was started", done.stdout)

    def test_a_stopped_run_is_carried_on_by_the_night_launcher_under_the_same_budget(self):
        self.run_big(FAKE_STAMP="20261125-0501")
        done = self.run_script("Mark the new episodes at night.command")
        self.assertEqual(done.returncode, 0, done.stdout)
        self.assertIn("--budget big-run-20261125-0501", self.labelling()[-1])

    def test_the_new_budget_reaches_the_marking_through_the_whole_chain(self):
        done = self.run_big(CHAIN="1", typed="yes\n")
        self.assertEqual(done.returncode, 0, done.stdout)
        self.assertEqual(self.labelling(), [
            "python3 teach_label.py --folder FOLDER --between 23-7 --wait-hours 120 --cap 95 "
            "--budget big-run-20261125-0501 --yes"])
        self.assertEqual(len(self.labelling()), 1)


if __name__ == "__main__":
    unittest.main()
