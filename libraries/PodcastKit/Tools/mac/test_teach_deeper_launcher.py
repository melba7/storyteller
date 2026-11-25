"""Tests for "Gather deeper and mark tonight": it explains the deeper run, asks for a typed yes, waits
until the teaching folder is free, then starts "Gather more episodes for teaching" with the newest 24 of
each show, 80 GB, the budget from current-budget.txt and the yes given. It runs with the stand-in
programs of test_teach_night_launchers.py on a temporary PATH and home, and the whole chain after it
is played by them too. No Mac, no network, no Claude.
Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import os
import re
import stat
import subprocess
import unittest

from test_teach_night_launchers import COLLECT, HERE, Setup

NAME = "Gather deeper and mark tonight.command"
# The stand-in python3 of the other tests answers "busy" with the environment's BUSY. This one answers
# busy the first BUSY_TIMES times it is asked and free after that, so a wait can be seen to end.
PYTHON_WAITING = '''#!/bin/bash
[ "$1" = "-u" ] && shift
case "$(basename "$1")" in teach_store.py)
  if [ "$2" = busy ]; then
    count="$(cat "$CALLS.busy" 2> /dev/null || echo 0)"
    count=$((count + 1))
    echo "$count" > "$CALLS.busy"
    if [ "$count" -le "${BUSY_TIMES:-0}" ]; then
      echo "python3 teach_store.py busy $3" >> "$CALLS"
      exit 3
    fi
  fi ;;
esac
exec "$BIN/python3-base" "$@"
'''
SLEEP = '#!/bin/bash\necho "sleep $*" >> "$CALLS"\n'


class FilesTests(unittest.TestCase):
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


class DeeperTests(Setup):
    def setUp(self):
        super().setUp()
        os.rename(os.path.join(self.bin, "python3"), os.path.join(self.bin, "python3-base"))
        for name, text in (("python3", PYTHON_WAITING), ("sleep", SLEEP)):
            path = os.path.join(self.bin, name)
            with open(path, "w") as f:
                f.write(text)
            os.chmod(path, 0o755)

    def run_deeper(self, typed="yes\n", **more):
        return self.run_script(NAME, typed=typed, **more)

    def put_budget_file(self, content):
        os.makedirs(self.folder, exist_ok=True)
        with open(os.path.join(self.folder, "current-budget.txt"), "wb") as f:
            f.write(content if isinstance(content, bytes) else content.encode())

    def test_it_explains_the_deeper_run_in_plain_words(self):
        done = self.run_deeper(typed="\n")
        for text in ("newest 24 episodes of each show", "about 500 more", "about 25 GB", "less than 15 GB free",
                     "between 11 at night and 7 in the morning", "$95", "big-run-1", "plugged in",
                     "Control-C"):
            self.assertIn(text, done.stdout)

    def test_anything_but_yes_starts_nothing_and_does_not_even_look_at_the_folder(self):
        for typed in ("\n", "", "no\n", "y\n", "ye s\n", "yes please\n", "sure\n", "1\n"):
            open(self.calls, "w").close()
            done = self.run_deeper(typed=typed)
            self.assertEqual(done.returncode, 0, typed)
            self.assertEqual(self.called(), [], typed)
            self.assertIn("Nothing was started, because you did not type yes.", done.stdout, typed)

    def test_teach_yes_in_the_environment_does_not_answer_for_you(self):
        done = self.run_deeper(typed="\n", TEACH_YES="1")
        self.assertEqual(self.called(), [])
        self.assertIn("Nothing was started", done.stdout)
        self.assertEqual(self.source(NAME).count('read -r -p "Type yes'), 1)

    def test_a_typed_yes_gathers_the_newest_24_up_to_80_gb_then_marks_at_night_under_the_budget(self):
        done = self.run_deeper(typed="  YES \n")
        self.assertEqual(done.returncode, 0, done.stdout)
        calls = self.python_calls()
        self.assertEqual(calls[0], COLLECT + " --per-show 24 --max-gb 80")
        self.assertEqual(calls[1], "python3 teach_transcribe.py --folder FOLDER --tool %s/podcast-transcribe" % self.bin)
        self.assertEqual(self.labelling(), ["python3 teach_label.py --folder FOLDER --between 23-7 --wait-hours 120 "
                                            "--cap 95 --budget big-run-1 --yes"])
        self.assertIn("python3 teach_publish.py --folder FOLDER", self.called())

    def test_the_yes_is_given_so_nothing_asks_a_second_time(self):
        done = self.run_deeper()
        self.assertNotIn("include the marking", done.stdout)
        self.assertEqual(len(self.labelling()), 1)
        self.assertEqual(self.source(NAME).count("read -r -p"), 2)  # the yes, and Press Return at the end

    def test_it_waits_while_the_folder_is_busy_with_one_plain_line_and_then_runs(self):
        done = self.run_deeper(BUSY_TIMES="3")
        self.assertEqual(done.returncode, 0, done.stdout)
        self.assertEqual(done.stdout.count("Another teaching step is still working in the folder"), 1)
        self.assertEqual(self.called().count("sleep 60"), 3)
        order = self.called()
        busy = [i for i, c in enumerate(order) if c.startswith("python3 teach_store.py busy")]
        self.assertEqual(len(busy), 4)  # busy three times, then free
        gathering = COLLECT + " --per-show 24 --max-gb 80"
        self.assertLess(busy[-1], order.index(gathering))  # the gathering starts only after the folder is free
        self.assertEqual(order.count(gathering), 1)
        self.assertIn("Another teaching step is still working", self.log())

    def test_a_free_folder_does_not_wait_or_say_anything_about_waiting(self):
        done = self.run_deeper()
        self.assertEqual(self.called().count("sleep 60"), 0)
        self.assertNotIn("still working", done.stdout)
        self.assertEqual(len([c for c in self.called() if c.startswith("python3 teach_store.py busy")]), 1)

    def test_it_asks_about_the_teaching_folder_itself(self):
        self.run_deeper()
        self.assertIn("python3 teach_store.py busy FOLDER", self.called())

    def test_a_folder_check_that_fails_for_another_reason_starts_nothing_and_does_not_loop(self):
        done = self.run_deeper(CODES="teach_store.py=2")
        self.assertEqual(done.returncode, 2, done.stdout)
        self.assertEqual(self.called().count("sleep 60"), 0)
        self.assertEqual(self.labelling(), [])
        self.assertEqual(self.python_calls(), [])
        self.assertIn("could not be checked", done.stdout)

    def test_the_budget_is_the_name_in_current_budget_txt(self):
        self.put_budget_file("big-run-20261125-0501\n")
        done = self.run_deeper()
        self.assertIn("--budget big-run-20261125-0501 --yes", self.labelling()[0])
        self.assertIn("big-run-20261125-0501", done.stdout)

    def test_a_missing_or_odd_file_means_big_run_1(self):
        cases = (None, "", "\n", "has a space\n", "../../x\n", "x" * 41 + "\n", "--cap 1\n", "-x\n", b"\xff\x00junk\n",
                 "big.run\n")
        for content in cases:
            open(self.calls, "w").close()
            if content is not None:
                self.put_budget_file(content)
            self.run_deeper()
            self.assertIn("--budget big-run-1 --yes", self.labelling()[0], repr(content))

    def test_the_name_is_trimmed_and_only_its_first_line_counts(self):
        self.put_budget_file("  big-run-a1\r\nsecond\n")
        self.run_deeper()
        self.assertIn("--budget big-run-a1 --yes", self.labelling()[0])

    def test_an_explicit_teach_budget_still_wins(self):
        self.put_budget_file("big-run-20261125-0501\n")
        done = self.run_deeper(TEACH_BUDGET="again")
        self.assertIn("--budget again --yes", self.labelling()[0])
        self.assertIn("again", done.stdout)

    def test_it_never_changes_the_budget_file(self):
        self.put_budget_file("big-run-a1\n")
        self.run_deeper()
        with open(os.path.join(self.folder, "current-budget.txt")) as f:
            self.assertEqual(f.read(), "big-run-a1\n")

    def test_it_is_noted_in_the_log(self):
        self.run_deeper()
        self.assertRegex(self.log(), r"=== \d{4}-\d\d-\d\d \d\d:\d\d gather deeper: newest 24 of each show, marking at night ===")


if __name__ == "__main__":
    unittest.main()
