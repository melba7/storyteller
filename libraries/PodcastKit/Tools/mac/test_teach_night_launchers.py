"""Tests for the launchers of the bigger teaching runs: the numbers "Gather episodes for teaching"
takes from the environment, "Gather more episodes for teaching", "Mark the new episodes at night" and
"Gather the exam episodes". They run with stand-in python3, swift and caffeinate programs on a
temporary PATH and home, to check which commands run, in which order, and that nothing is marked
without a typed yes. No Mac, no network, no Claude.
Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import os
import re
import shutil
import stat
import subprocess
import tempfile
import unittest

from test_teach_shell import PYTHON, SWIFT, TEACH

HERE = os.path.dirname(os.path.abspath(__file__))
GATHER = "Gather episodes for teaching.command"
MORE = "Gather more episodes for teaching.command"
NIGHT = "Mark the new episodes at night.command"
MARK = "Mark ads in the teaching episodes.command"
EXAM = "Gather the exam episodes.command"
NEW = [MORE, NIGHT, EXAM]
CAFFEINATE = '#!/bin/bash\necho "caffeinate $*" >> "$CALLS"\nshift\nexec "$@"\n'
# The step before the launchers' own: what the gathering does is played by the stand-in python3.
COLLECT = "python3 teach_collect.py --folder FOLDER"


class Setup(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.root, ignore_errors=True)
        self.bin = os.path.join(self.root, "bin")
        self.home = os.path.join(self.root, "home")
        self.calls = os.path.join(self.root, "calls.log")
        for folder in (self.bin, self.home, os.path.join(self.root, "tmp")):
            os.makedirs(folder)
        for name, text in (("python3", PYTHON), ("swift", SWIFT), ("podcast-teach", TEACH),
                           ("caffeinate", CAFFEINATE)):
            path = os.path.join(self.bin, name)
            with open(path, "w") as f:
                f.write(text)
            os.chmod(path, 0o755)
        open(self.calls, "w").close()
        self.folder = os.path.join(self.home, "Storyteller Lofi", "PodcastTeaching")

    def run_script(self, name, typed="", **more):
        env = {"HOME": self.home, "PATH": "%s:/usr/bin:/bin" % self.bin, "TMPDIR": os.path.join(self.root, "tmp"),
               "CALLS": self.calls, "BIN": self.bin, "FAIL": "", "NOOP": "", "BUSY": "",
               "BUILD_FAILS": "", "CODES": "", "TEACH_CODES": ""}
        env.update(more)
        return subprocess.run(["bash", os.path.join(HERE, name)], env=env, input=typed,
                              capture_output=True, text=True, timeout=120)

    def source(self, name):
        with open(os.path.join(HERE, name), encoding="utf-8") as f:
            return f.read()

    def called(self):
        with open(self.calls) as f:
            return [line.strip().replace(self.folder, "FOLDER") for line in f if line.strip()]

    def python_calls(self):
        return [c for c in self.called() if c.startswith("python3 teach_")
                and not c.startswith("python3 teach_store.py")]

    def labelling(self):
        return [c for c in self.called() if c.startswith("python3 teach_label.py")]

    def log(self):
        with open(os.path.join(self.home, "Storyteller Lofi", "logs", "podcast-teaching.log")) as f:
            return f.read()


class FilesTests(unittest.TestCase):
    def test_the_new_launchers_are_runnable_bash_files_for_bash_3_2(self):
        for name in NEW:
            path = os.path.join(HERE, name)
            self.assertTrue(os.stat(path).st_mode & stat.S_IXUSR, name)
            with open(path, encoding="utf-8") as f:
                text = f.read()
            self.assertEqual(text.splitlines()[0], "#!/bin/bash", name)
            self.assertEqual(subprocess.run(["bash", "-n", path]).returncode, 0, name)
            code = "".join(line for line in text.splitlines(True) if not line.lstrip().startswith("#"))
            for pattern in (r"declare\s+-A", r"\bmapfile\b", r"\breadarray\b", r"\$\{[A-Za-z_]+(,,|\^\^)\}",
                            r"\$\(<<", r"&>>?", r"\|&", r"\bcoproc\b"):
                self.assertIsNone(re.search(pattern, code), (name, pattern))
            self.assertIn("finish()", text, name)
            self.assertIn('HERE="$(cd "$(dirname "$0")" && pwd)"', text, name)
            self.assertLess(len(text.splitlines()), 300, name)


class GatherEnvironmentTests(Setup):
    def test_without_the_variables_it_runs_as_before(self):
        done = self.run_script(GATHER)
        self.assertEqual(done.returncode, 0, done.stdout)
        self.assertEqual(self.python_calls()[0], COLLECT)
        self.assertIn("up to 12 GB", done.stdout)

    def test_the_numbers_come_from_the_environment(self):
        done = self.run_script(GATHER, TEACH_PER_SHOW="12", TEACH_MAX_GB="40")
        self.assertEqual(self.python_calls()[0], COLLECT + " --per-show 12 --max-gb 40")
        self.assertIn("up to 40 GB", done.stdout)
        self.assertNotIn("12 GB", done.stdout)

    def test_the_exam_flag_only_for_exactly_1(self):
        self.run_script(GATHER, TEACH_EXAM="1")
        self.assertEqual(self.python_calls()[0], COLLECT + " --exam")
        open(self.calls, "w").close()
        self.run_script(GATHER, TEACH_EXAM="0")
        self.assertEqual(self.python_calls()[0], COLLECT)

    def test_after_is_started_instead_of_waiting_for_return(self):
        after = os.path.join(self.root, "after.command")
        with open(after, "w") as f:
            f.write('#!/bin/bash\necho "after started yes=$TEACH_YES" >> "$CALLS"\necho AFTER-RAN\n')
        os.chmod(after, 0o755)
        done = self.run_script(GATHER, TEACH_AFTER=after)
        self.assertEqual(done.returncode, 0, done.stdout)
        self.assertIn("AFTER-RAN", done.stdout)
        self.assertNotIn("Press Return", done.stdout)
        self.assertEqual(self.called()[-1], "after started yes=")
        self.assertIn("Carrying on", self.log())

    def test_after_is_also_started_when_the_size_limit_stopped_step_1(self):
        after = os.path.join(self.root, "after.command")
        with open(after, "w") as f:
            f.write('#!/bin/bash\necho after >> "$CALLS"\n')
        os.chmod(after, 0o755)
        self.run_script(GATHER, TEACH_AFTER=after, CODES="teach_collect.py=3")
        self.assertEqual(self.called()[-1], "after")

    def test_after_is_not_started_when_a_step_did_not_work(self):
        after = os.path.join(self.root, "after.command")
        with open(after, "w") as f:
            f.write('#!/bin/bash\necho after >> "$CALLS"\n')
        os.chmod(after, 0o755)
        for codes in ("teach_collect.py=2", "teach_transcribe.py=1", "teach_transcribe.py=3"):
            open(self.calls, "w").close()
            done = self.run_script(GATHER, TEACH_AFTER=after, CODES=codes)
            self.assertNotIn("after", self.called(), codes)
            self.assertEqual(done.returncode, 1, codes)


class MoreTests(Setup):
    def test_it_asks_once_and_only_gathers_without_a_yes(self):
        for typed in ("\n", "no\n", "y\n", ""):
            open(self.calls, "w").close()
            done = self.run_script(MORE, typed=typed)
            self.assertEqual(self.python_calls(), [COLLECT + " --per-show 12 --max-gb 40",
                                                  "python3 teach_transcribe.py --folder FOLDER --tool %s/podcast-transcribe"
                                                  % self.bin], typed)
            self.assertEqual(self.labelling(), [], typed)
            self.assertNotIn("teach-finish", " ".join(self.called()))

    def test_it_explains_the_numbers_in_plain_words(self):
        done = self.run_script(MORE)
        for text in ("about 500 more episodes", "newest 12", "40 GB", "15 GB", "11 at night",
                     "7 in the morning", "$95"):
            self.assertIn(text, done.stdout)

    def test_a_typed_yes_gathers_then_marks_at_night_then_works_out_the_results(self):
        done = self.run_script(MORE, typed="yes\n")
        self.assertEqual(done.returncode, 0, done.stdout)
        self.assertEqual(self.python_calls(), [
            COLLECT + " --per-show 12 --max-gb 40",
            "python3 teach_transcribe.py --folder FOLDER --tool %s/podcast-transcribe" % self.bin,
            "python3 teach_label.py --folder FOLDER --between 23-7 --wait-hours 120 --cap 95 --yes",
            "python3 teach_habits.py --folder FOLDER", "python3 teach_train.py --folder FOLDER",
            "python3 teach_library.py --folder FOLDER", "python3 teach_settings.py --folder FOLDER",
            "python3 teach_publish.py --folder FOLDER"])
        self.assertEqual(self.source(MORE).count('read -r -p "Type yes'), 1)  # asked once at the start

    def test_yes_is_taken_in_any_case_with_spaces(self):
        self.run_script(MORE, typed="  YES \n")
        self.assertEqual(len(self.labelling()), 1)

    def test_teach_yes_in_the_environment_does_not_ask_and_includes_the_marking(self):
        done = self.run_script(MORE, TEACH_YES="1")
        self.assertNotIn("Type yes", done.stdout)
        self.assertEqual(len(self.labelling()), 1)

    def test_teach_yes_other_than_1_does_not_count_as_a_yes_here(self):
        self.run_script(MORE, typed="\n", TEACH_YES="0")
        self.assertEqual(self.labelling(), [])

    def test_it_never_gathers_the_exam(self):
        self.run_script(MORE, typed="\n", TEACH_EXAM="1")
        self.assertNotIn("--exam", self.python_calls()[0])

    def test_when_the_gathering_fails_nothing_is_marked(self):
        self.run_script(MORE, typed="yes\n", CODES="teach_collect.py=2")
        self.assertEqual(self.labelling(), [])

    def test_it_is_noted_in_the_log(self):
        self.run_script(MORE, typed="yes\n")
        self.assertRegex(self.log(), r"=== \d{4}-\d\d-\d\d \d\d:\d\d gather more: with the marking at night ===")


class NightTests(Setup):
    def test_it_marks_between_23_and_7_with_the_wait_and_the_cap_then_works_out_the_results(self):
        done = self.run_script(NIGHT)
        self.assertEqual(done.returncode, 0, done.stdout)
        self.assertEqual(self.labelling(),
                         ["python3 teach_label.py --folder FOLDER --between 23-7 --wait-hours 120 --cap 95"])
        self.assertIn("python3 teach_publish.py --folder FOLDER", self.called())

    def test_the_numbers_can_be_changed_from_the_environment(self):
        self.run_script(NIGHT, TEACH_BETWEEN="22-6", TEACH_WAIT_HOURS="48", TEACH_CAP="10")
        self.assertEqual(self.labelling(),
                         ["python3 teach_label.py --folder FOLDER --between 22-6 --wait-hours 48 --cap 10"])

    def test_with_teach_yes_the_tool_is_not_asked_to_confirm_again(self):
        self.run_script(NIGHT, TEACH_YES="1")
        self.assertEqual(self.labelling(),
                         ["python3 teach_label.py --folder FOLDER --between 23-7 --wait-hours 120 --cap 95 --yes"])

    def test_without_teach_yes_nothing_is_passed_to_skip_the_question(self):
        self.run_script(NIGHT)
        self.assertNotIn("--yes", self.labelling()[0])

    def test_the_mac_stays_awake_for_the_whole_marking(self):
        self.run_script(NIGHT)
        self.assertTrue(any(c.startswith("caffeinate -i python3 -u") and "teach_label.py" in c
                            for c in self.called()), self.called())

    def test_not_typing_yes_runs_nothing_after_it(self):
        self.run_script(NIGHT, CODES="teach_label.py=4")
        self.assertEqual(self.python_calls(), [self.labelling()[0]])

    def test_stopped_early_still_works_out_what_was_marked(self):
        done = self.run_script(NIGHT, CODES="teach_label.py=3")
        self.assertEqual(done.returncode, 3)
        self.assertIn("python3 teach_publish.py --folder FOLDER", self.called())

    def test_a_marking_that_could_not_start_does_not_run_the_steps_after_it(self):
        done = self.run_script(NIGHT, CODES="teach_label.py=2")
        self.assertEqual(done.returncode, 2)
        self.assertEqual(self.python_calls(), [self.labelling()[0]])

    def test_everything_is_added_to_the_log(self):
        self.run_script(NIGHT)
        self.assertRegex(self.log(), r"=== \d{4}-\d\d-\d\d \d\d:\d\d mark ads ===")


class ExamTests(Setup):
    FIRST = "python3 teach_label.py --folder FOLDER --only-exam --between 23-7 --wait-hours 120 --cap 14 --yes"
    SECOND = ("python3 teach_label.py --folder FOLDER --only-exam --labels labels-second --limit 15 "
              "--between 23-7 --wait-hours 120 --cap 4 --yes")

    def test_it_explains_in_plain_words(self):
        done = self.run_script(EXAM)
        for text in ("about 60 brand-new episodes", "apart as", "exam", "11 at night", "$18",
                     "15 of", "second time"):
            self.assertIn(text, done.stdout)

    def test_without_a_yes_it_only_gathers_the_exam_and_marks_nothing(self):
        for typed in ("\n", "no\n", ""):
            open(self.calls, "w").close()
            done = self.run_script(EXAM, typed=typed)
            self.assertEqual(self.python_calls()[0], COLLECT + " --per-show 2 --max-gb 46 --exam", typed)
            self.assertEqual(self.labelling(), [], typed)
            self.assertIn("Nothing will be marked", done.stdout)

    def test_a_typed_yes_gathers_then_marks_the_exam_then_marks_15_again_and_learns_nothing(self):
        done = self.run_script(EXAM, typed="yes\n")
        self.assertEqual(done.returncode, 0, done.stdout)
        self.assertEqual(self.python_calls(), [
            COLLECT + " --per-show 2 --max-gb 46 --exam",
            "python3 teach_transcribe.py --folder FOLDER --tool %s/podcast-transcribe" % self.bin,
            self.FIRST, self.SECOND])
        self.assertNotIn("teach-finish", " ".join(self.called()))
        self.assertIn("The exam is ready to be scored.", done.stdout)
        self.assertEqual(self.source(EXAM).count('read -r -p "Type yes'), 1)

    def test_teach_yes_in_the_environment_does_not_ask(self):
        done = self.run_script(EXAM, TEACH_YES="1")
        self.assertNotIn("Type yes", done.stdout)
        self.assertEqual(len(self.labelling()), 2)

    def test_the_marking_part_alone_marks_nothing_without_a_yes(self):
        done = self.run_script(EXAM, TEACH_EXAM_STAGE="night")
        self.assertEqual(self.python_calls(), [])
        self.assertIn("Nothing was marked", done.stdout)

    def test_the_second_marking_waits_for_the_first_to_finish(self):
        done = self.run_script(EXAM, typed="yes\n", CODES="teach_label.py=3")
        self.assertEqual(self.labelling(), [self.FIRST])
        self.assertEqual(done.returncode, 3)
        self.assertIn("Double-click again to carry on", done.stdout)

    def test_a_marking_that_could_not_start_stops_it(self):
        done = self.run_script(EXAM, typed="yes\n", CODES="teach_label.py=2")
        self.assertEqual((self.labelling(), done.returncode), ([self.FIRST], 2))

    def test_a_gathering_that_failed_marks_nothing(self):
        self.run_script(EXAM, typed="yes\n", CODES="teach_collect.py=2")
        self.assertEqual(self.labelling(), [])

    def test_the_mac_stays_awake_for_both_markings(self):
        self.run_script(EXAM, typed="yes\n")
        awake = [c for c in self.called() if c.startswith("caffeinate -i python3 -u") and "teach_label.py" in c]
        self.assertEqual(len(awake), 2)

    def test_everything_is_added_to_the_log(self):
        self.run_script(EXAM, typed="yes\n")
        self.assertRegex(self.log(), r"=== \d{4}-\d\d-\d\d \d\d:\d\d exam: marking ===")
        self.assertIn("Step 2 of 2: marking 15 of the exam episodes a second time", self.log())


if __name__ == "__main__":
    unittest.main()
