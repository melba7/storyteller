"""Tests for the shell files of the teaching run: every .command and .sh file must parse (bash -n)
and keep to what the Mac's bash 3.2 can run; teach-finish.sh and teach-weekly.sh are run with
stand-in python3, swift and podcast-teach programs on a temporary PATH, to check the order of the
steps, that a failing step does not stop the later ones, and the exit code. No Mac needed.
Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import glob
import os
import re
import shutil
import stat
import subprocess
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
SHELL_FILES = sorted(glob.glob(os.path.join(HERE, "*.command")) + glob.glob(os.path.join(HERE, "*.sh")))
NEW_FILES = ["teach-finish.sh", "teach-weekly.sh", "Teach the phone again.command",
             "Score the ad skipping.command", "Install weekly teaching.command",
             "Stop weekly teaching.command", "Mark ads in the teaching episodes.command"]

PYTHON = """#!/bin/bash
# stand-in for python3: records the call and writes what the real tool would write
[ "$1" = "-u" ] && shift
script="$(basename "$1")"
shift
echo "python3 $script $*" >> "$CALLS"
case " $FAIL " in *" $script "*) echo "$script: pretending to fail"; exit 1 ;; esac
[ "$script" = teach_store.py ] && { [ -n "$BUSY" ] && exit 3; exit 0; }
folder=""
while [ $# -gt 0 ]; do
  [ "$1" = "--folder" ] && folder="$2"
  shift
done
case " $NOOP " in *" $script "*) echo "$script: nothing to do"; exit 0 ;; esac
mkdir -p "$folder"
case "$script" in
  teach_habits.py) echo "$RANDOM$RANDOM" > "$folder/habits.json" ;;
  teach_train.py) echo "$RANDOM$RANDOM" > "$folder/ad-model.json" ;;
  teach_library.py) echo "$RANDOM$RANDOM" > "$folder/ad-library.json" ;;
  teach_publish.py) echo "ad-model.json in somewhere: written." ;;
esac
exit 0
"""

SWIFT = """#!/bin/bash
echo "swift $*" >> "$CALLS"
case "$*" in *--show-bin-path*) echo "$BIN"; exit 0 ;; esac
[ -n "$BUILD_FAILS" ] && { echo "error: the build broke"; exit 1; }
exit 0
"""

TEACH = """#!/bin/bash
echo "podcast-teach $*" >> "$CALLS"
case " $FAIL " in *" podcast-teach-$1 "*) echo "podcast-teach $1: pretending to fail"; exit 2 ;; esac
case "$1" in sounds) out=ad-sounds.json ;; score) out=scorecard.json ;; esac
case " $NOOP " in *" podcast-teach-$1 "*) exit 0 ;; esac
echo "$RANDOM$RANDOM" > "$2/$out"
exit 0
"""


class SyntaxTests(unittest.TestCase):
    def test_there_are_shell_files(self):
        self.assertGreaterEqual(len(SHELL_FILES), 15)
        for name in NEW_FILES:
            self.assertIn(os.path.join(HERE, name), SHELL_FILES)

    def test_every_file_parses_with_bash_n(self):
        for path in SHELL_FILES:
            done = subprocess.run(["bash", "-n", path], capture_output=True, text=True)
            self.assertEqual(done.returncode, 0, "%s: %s" % (path, done.stderr))

    def test_the_new_files_can_be_run_and_start_with_bash(self):
        for name in NEW_FILES:
            path = os.path.join(HERE, name)
            self.assertTrue(os.stat(path).st_mode & stat.S_IXUSR, name)
            with open(path, encoding="utf-8") as f:
                self.assertEqual(f.readline().strip(), "#!/bin/bash", name)

    def test_the_new_files_keep_to_what_bash_3_2_has(self):
        banned = [r"declare\s+-A", r"\bmapfile\b", r"\breadarray\b", r"\$\{[A-Za-z_]+(,,|\^\^)\}",
                  r"\$\(<<", r"&>>?", r"\|&", r"\bcoproc\b"]
        for name in NEW_FILES:
            with open(os.path.join(HERE, name), encoding="utf-8") as f:
                text = "".join(line for line in f if not line.lstrip().startswith("#"))
            for pattern in banned:
                self.assertIsNone(re.search(pattern, text), "%s uses %s" % (name, pattern))

    def test_no_here_document_inside_a_command_substitution_and_no_apostrophe_in_one(self):
        for name in NEW_FILES:
            with open(os.path.join(HERE, name), encoding="utf-8") as f:
                text = f.read()
            self.assertIsNone(re.search(r"\$\([^)]*<<", text), name)
            for body in re.findall(r"<<'?(\w+)'?\n(.*?)\n\1\n", text, re.S):
                self.assertNotIn("'", body[1], name)


class Setup(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.root, ignore_errors=True)
        self.bin = os.path.join(self.root, "bin")
        self.home = os.path.join(self.root, "home")
        self.kit = os.path.join(self.root, "kit")
        self.calls = os.path.join(self.root, "calls.log")
        for folder in (self.bin, self.home, self.kit, os.path.join(self.root, "tmp")):
            os.makedirs(folder)
        with open(os.path.join(self.kit, "Package.swift"), "w") as f:
            f.write("// stand-in\n")
        self.program("python3", PYTHON)
        self.program("swift", SWIFT)
        self.program("podcast-teach", TEACH)
        open(self.calls, "w").close()

    def program(self, name, text):
        path = os.path.join(self.bin, name)
        with open(path, "w") as f:
            f.write(text)
        os.chmod(path, 0o755)

    def run_script(self, name, **more):
        env = {"HOME": self.home, "PATH": "%s:/usr/bin:/bin" % self.bin, "TEACH_TOOLS": "/stand/in/tools",
               "TEACH_KIT": self.kit, "TMPDIR": os.path.join(self.root, "tmp"), "CALLS": self.calls,
               "BIN": self.bin, "FAIL": "", "NOOP": "", "BUSY": "", "BUILD_FAILS": ""}
        env.update(more)
        return subprocess.run(["bash", os.path.join(HERE, name)], env=env, capture_output=True,
                              text=True, timeout=120, stdin=subprocess.DEVNULL)

    def called(self):
        with open(self.calls) as f:
            return [line.strip() for line in f if line.strip()]

    def short(self):
        """The calls, each as its tool and first words, without the folder arguments."""
        folder = os.path.join(self.home, "Storyteller Lofi", "PodcastTeaching")
        return [line.replace(" --folder " + folder, "").replace(" " + folder, "")
                for line in self.called()]

    def log(self):
        with open(os.path.join(self.home, "Storyteller Lofi", "logs", "podcast-teaching.log")) as f:
            return f.read()


FINISH_ORDER = ["python3 teach_habits.py", "python3 teach_train.py", "python3 teach_library.py",
                "swift build -c release --product podcast-teach",
                "swift build -c release --show-bin-path", "podcast-teach sounds",
                "podcast-teach score", "python3 teach_publish.py"]


class FinishTests(Setup):
    def test_the_steps_run_in_order_and_everything_worked(self):
        done = self.run_script("teach-finish.sh")
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertEqual(self.short(), FINISH_ORDER)
        for line in ("Habits: worked", "Model: worked", "Library: worked", "Sounds: worked",
                     "Score: worked", "Publish: worked"):
            self.assertIn("  " + line, done.stdout)
        for number in range(1, 7):
            self.assertIn("Step %d of 6" % number, done.stdout)

    def test_the_summary_comes_last_in_the_order_of_the_steps(self):
        done = self.run_script("teach-finish.sh")
        summary = done.stdout[done.stdout.index("Summary:"):]
        labels = re.findall(r"^  (\w+): ", summary, re.M)
        self.assertEqual(labels, ["Habits", "Model", "Library", "Sounds", "Score", "Publish"])

    def test_the_podcast_teach_tools_get_the_teaching_folder(self):
        self.run_script("teach-finish.sh")
        folder = os.path.join(self.home, "Storyteller Lofi", "PodcastTeaching")
        calls = self.called()
        self.assertIn("podcast-teach sounds %s" % folder, calls)
        self.assertIn("podcast-teach score %s" % folder, calls)

    def test_a_failing_step_is_said_and_the_later_ones_still_run(self):
        done = self.run_script("teach-finish.sh", FAIL="teach_train.py")
        self.assertEqual(done.returncode, 0, done.stdout)
        self.assertEqual(self.short(), FINISH_ORDER)
        self.assertIn("  Model: failed", done.stdout)
        self.assertIn("Model did not work", done.stdout)
        self.assertIn("  Library: worked", done.stdout)
        self.assertIn("  Publish: worked", done.stdout)

    def test_every_step_may_fail_without_stopping_the_next(self):
        for failing, label in (("teach_habits.py", "Habits"), ("teach_library.py", "Library"),
                               ("podcast-teach-sounds", "Sounds"), ("podcast-teach-score", "Score")):
            open(self.calls, "w").close()
            done = self.run_script("teach-finish.sh", FAIL=failing)
            self.assertEqual(done.returncode, 0, failing)
            self.assertEqual(self.short(), FINISH_ORDER, failing)
            self.assertIn("  %s: failed" % label, done.stdout)

    def test_a_failing_publish_exits_1(self):
        done = self.run_script("teach-finish.sh", FAIL="teach_publish.py")
        self.assertEqual(done.returncode, 1)
        self.assertIn("  Publish: failed", done.stdout)
        self.assertEqual(self.short(), FINISH_ORDER)

    def test_when_the_build_fails_both_swift_steps_are_left_out_and_publish_still_runs(self):
        done = self.run_script("teach-finish.sh", BUILD_FAILS="1")
        self.assertEqual(done.returncode, 0, done.stdout)
        self.assertEqual(self.short(), ["python3 teach_habits.py", "python3 teach_train.py",
                                        "python3 teach_library.py",
                                        "swift build -c release --product podcast-teach",
                                        "python3 teach_publish.py"])
        self.assertIn("podcast-teach did not build", done.stdout)
        self.assertIn("  Sounds: failed", done.stdout)
        self.assertIn("  Score: failed", done.stdout)
        self.assertIn("  Publish: worked", done.stdout)

    @unittest.skipIf(shutil.which("swift", path="/usr/bin:/bin"), "a real swift is installed")
    def test_without_swift_the_swift_steps_are_left_out(self):
        os.remove(os.path.join(self.bin, "swift"))
        done = self.run_script("teach-finish.sh")
        self.assertEqual(done.returncode, 0, done.stdout)
        self.assertIn("swift is missing", done.stdout)
        self.assertNotIn("podcast-teach sounds", " ".join(self.called()))

    def test_without_the_package_the_swift_steps_are_left_out(self):
        os.remove(os.path.join(self.kit, "Package.swift"))
        done = self.run_script("teach-finish.sh", HOME=self.home)
        self.assertIn("Could not find PodcastKit", done.stdout)
        self.assertIn("  Sounds: failed", done.stdout)
        self.assertEqual(done.returncode, 0)

    def test_a_step_that_makes_nothing_new_is_nothing_to_do(self):
        done = self.run_script("teach-finish.sh", NOOP="teach_train.py teach_publish.py podcast-teach-score")
        self.assertEqual(done.returncode, 0)
        self.assertIn("  Model: nothing to do", done.stdout)
        self.assertIn("  Publish: nothing to do", done.stdout)
        self.assertIn("  Score: nothing to do", done.stdout)
        self.assertIn("  Habits: worked", done.stdout)

    def test_a_step_that_writes_the_same_file_again_is_nothing_to_do(self):
        folder = os.path.join(self.home, "Storyteller Lofi", "PodcastTeaching")
        os.makedirs(folder)
        with open(os.path.join(folder, "habits.json"), "w") as f:
            f.write("same\n")
        self.program("python3", PYTHON.replace('echo "$RANDOM$RANDOM" > "$folder/habits.json"',
                                               'echo same > "$folder/habits.json"'))
        done = self.run_script("teach-finish.sh")
        self.assertIn("  Habits: nothing to do", done.stdout)

    def test_everything_is_added_to_the_log(self):
        done = self.run_script("teach-finish.sh")
        log = self.log()
        self.assertIn("Step 1 of 6", log)
        self.assertIn("Summary:", log)
        self.assertIn("Publish: worked", log)
        self.assertEqual(done.returncode, 0)


class WeeklyTests(Setup):
    def test_the_steps_run_in_order(self):
        done = self.run_script("teach-weekly.sh")
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertEqual(self.short(), [
            "python3 teach_store.py busy", "python3 teach_feedback.py",
            "python3 teach_collect.py --per-show 1",
            "swift build -c release --product podcast-transcribe",
            "swift build -c release --show-bin-path", "python3 teach_transcribe.py --tool %s/podcast-transcribe" % self.bin,
            "python3 teach_label.py --yes --limit 15"] + FINISH_ORDER)

    def test_the_transcriber_is_the_one_that_was_built(self):
        self.run_script("teach-weekly.sh")
        line = [c for c in self.called() if "teach_transcribe.py" in c][0]
        self.assertIn("--tool %s/podcast-transcribe" % self.bin, line)

    def test_another_run_in_the_folder_ends_quietly_with_exit_0(self):
        done = self.run_script("teach-weekly.sh", BUSY="1")
        self.assertEqual(done.returncode, 0)
        self.assertEqual(len(self.called()), 1)
        self.assertIn("Another teaching run is already working", done.stdout)

    def test_a_failing_step_does_not_stop_the_others_but_the_exit_code_says_so(self):
        for failing in ("teach_feedback.py", "teach_collect.py", "teach_transcribe.py", "teach_label.py"):
            open(self.calls, "w").close()
            done = self.run_script("teach-weekly.sh", FAIL=failing)
            self.assertEqual(done.returncode, 1, failing)
            names = [c.split()[1] for c in self.called() if c.startswith("python3")]
            self.assertEqual(names[-1], "teach_publish.py", failing)
            self.assertIn("teach_library.py", names, failing)
            self.assertIn("not every step worked", done.stdout, failing)

    def test_a_failing_build_leaves_out_the_transcriber_and_goes_on(self):
        done = self.run_script("teach-weekly.sh", BUILD_FAILS="1")
        self.assertEqual(done.returncode, 1)
        self.assertNotIn("teach_transcribe.py", " ".join(self.called()))
        self.assertIn("python3 teach_label.py --folder", " ".join(self.called()))
        self.assertIn("The transcriber did not build", done.stdout)

    def test_it_works_with_a_short_path_as_launchd_gives_it(self):
        done = self.run_script("teach-weekly.sh", PATH="%s:/usr/bin:/bin" % self.bin)
        self.assertEqual(done.returncode, 0, done.stdout)

    def test_the_log_gets_a_heading_with_the_date(self):
        self.run_script("teach-weekly.sh")
        self.assertRegex(self.log(), r"=== \d{4}-\d\d-\d\d \d\d:\d\d weekly teaching ===")


if __name__ == "__main__":
    unittest.main()
