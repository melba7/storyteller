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
             "Stop weekly teaching.command", "Mark ads in the teaching episodes.command",
             "Mark ads when the gathering is done.command",
             "Check ads with a second download.command"]

PYTHON = """#!/bin/bash
# stand-in for python3: records the call and writes what the real tool would write
[ "$1" = "-u" ] && shift
script="$(basename "$1")"
shift
echo "python3 $script $*" >> "$CALLS"
case " $FAIL " in *" $script "*) echo "$script: pretending to fail"; exit 1 ;; esac
for pair in $CODES; do
  [ "${pair%%=*}" = "$script" ] && { echo "$script: ending with ${pair#*=}"; exit "${pair#*=}"; }
done
if [ "$script" = teach_store.py ]; then
  [ -n "$BUSY" ] && { echo "Another teaching run is already working in this folder."; exit 3; }
  if [ "$1" = hold ]; then
    shift 2
    exec "$@"
  fi
  exit 0
fi
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
  teach_snap.py) mkdir -p "$folder/labels-snapped"; echo "$RANDOM$RANDOM" > "$folder/labels-snapped/a.json" ;;
  teach_settings.py) echo "$RANDOM$RANDOM" > "$folder/show-settings.json" ;;
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
for pair in $TEACH_CODES; do
  [ "${pair%%=*}" = "$1" ] && { echo "podcast-teach $1: ending with ${pair#*=}"; exit "${pair#*=}"; }
done
case "$1" in sounds) out=ad-sounds.json ;; meaning) out=ad-meaning.json ;; score) out=scorecard.json ;; esac
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


class SyncExcludeTests(unittest.TestCase):
    """The copies of LofiMusic into iCloud must not carry temporary files or overwrite the phone's
    own notes (the files of the other tools in libraries/LofiScoreKit/Tools/mac)."""
    FILES = ("lofi-sync.sh", "fetch-sounds.sh", "make-atmosphere.sh")
    EXCLUDES = ("'.*.tmp'", "'Podcasts/phone-notes.jsonl'", "'Podcasts/phone-diary.jsonl'")

    def test_every_music_to_icloud_copy_leaves_out_temporary_files_and_the_phones_notes(self):
        folder = os.path.join(HERE, "..", "..", "..", "LofiScoreKit", "Tools", "mac")
        for name in self.FILES:
            with open(os.path.join(folder, name), encoding="utf-8") as f:
                text = f.read()
            # A command may continue on the next line after a backslash.
            commands = [c for c in re.sub(r"\\\n", " ", text).split("\n") if "rsync -a" in c
                        and '"$MUSIC/" "$ICLOUD/"' in c]
            self.assertTrue(commands, name)
            for command in commands:
                for exclude in self.EXCLUDES:
                    self.assertEqual(command.count("--exclude " + exclude), command.count("rsync -a"),
                                     name)

    @unittest.skipUnless(shutil.which("rsync"), "rsync is not installed")
    def test_rsync_with_those_excludes_skips_them(self):
        root = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, root, ignore_errors=True)
        source, target = os.path.join(root, "a"), os.path.join(root, "b")
        os.makedirs(os.path.join(source, "Podcasts"))
        os.makedirs(os.path.join(target, "Podcasts"))
        for name in ("Podcasts/phone-notes.jsonl", "Podcasts/phone-diary.jsonl", ".x.json.tmp",
                     "Podcasts/ad-model.json"):
            with open(os.path.join(source, name), "w") as f:
                f.write("mac")
        with open(os.path.join(target, "Podcasts", "phone-notes.jsonl"), "w") as f:
            f.write("phone")
        command = ["rsync", "-a"] + [a for e in self.EXCLUDES for a in ("--exclude", e.strip("'"))]
        subprocess.run(command + [source + "/", target + "/"], check=True)
        with open(os.path.join(target, "Podcasts", "phone-notes.jsonl")) as f:
            self.assertEqual(f.read(), "phone")
        self.assertFalse(os.path.exists(os.path.join(target, "Podcasts", "phone-diary.jsonl")))
        self.assertFalse(os.path.exists(os.path.join(target, ".x.json.tmp")))
        self.assertTrue(os.path.exists(os.path.join(target, "Podcasts", "ad-model.json")))


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
        self.program("caffeinate", '#!/bin/bash\nshift\nexec "$@"\n')
        open(self.calls, "w").close()

    def program(self, name, text):
        path = os.path.join(self.bin, name)
        with open(path, "w") as f:
            f.write(text)
        os.chmod(path, 0o755)

    def run_script(self, name, **more):
        env = {"HOME": self.home, "PATH": "%s:/usr/bin:/bin" % self.bin, "TEACH_TOOLS": "/stand/in/tools",
               "TEACH_KIT": self.kit, "TMPDIR": os.path.join(self.root, "tmp"), "CALLS": self.calls,
               "BIN": self.bin, "FAIL": "", "NOOP": "", "BUSY": "", "BUILD_FAILS": "", "CODES": "",
               "TEACH_CODES": ""}
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
                for line in self.called() if " teach_store.py hold" not in line]

    def log(self):
        with open(os.path.join(self.home, "Storyteller Lofi", "logs", "podcast-teaching.log")) as f:
            return f.read()


FINISH_ORDER = ["python3 teach_habits.py", "python3 teach_train.py", "python3 teach_library.py",
                "swift build -c release --product podcast-teach",
                "swift build -c release --show-bin-path", "podcast-teach sounds",
                "podcast-teach meaning", "podcast-teach score", "python3 teach_settings.py",
                "python3 teach_publish.py"]


class FinishTests(Setup):
    def test_the_steps_run_in_order_and_everything_worked(self):
        done = self.run_script("teach-finish.sh")
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertEqual(self.short(), FINISH_ORDER)
        for line in ("Habits: worked", "Model: worked", "Library: worked", "Sounds: worked",
                     "Meaning: worked", "Score: worked", "Settings: worked", "Publish: worked"):
            self.assertIn("  " + line, done.stdout)
        for number in range(1, 9):
            self.assertIn("Step %d of 8" % number, done.stdout)

    def test_the_summary_comes_last_in_the_order_of_the_steps(self):
        done = self.run_script("teach-finish.sh")
        summary = done.stdout[done.stdout.index("Summary:"):]
        labels = re.findall(r"^  (\w+): ", summary, re.M)
        self.assertEqual(labels, ["Habits", "Model", "Library", "Sounds", "Meaning", "Score",
                                  "Settings", "Publish"])

    def test_the_podcast_teach_tools_get_the_teaching_folder(self):
        self.run_script("teach-finish.sh")
        folder = os.path.join(self.home, "Storyteller Lofi", "PodcastTeaching")
        calls = self.called()
        self.assertIn("podcast-teach sounds %s" % folder, calls)
        self.assertIn("podcast-teach meaning %s" % folder, calls)
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
                               ("podcast-teach-sounds", "Sounds"), ("podcast-teach-meaning", "Meaning"),
                               ("podcast-teach-score", "Score"), ("teach_settings.py", "Settings")):
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
                                        "python3 teach_settings.py", "python3 teach_publish.py"])
        self.assertIn("podcast-teach did not build", done.stdout)
        self.assertIn("  Sounds: failed", done.stdout)
        self.assertIn("  Meaning: failed", done.stdout)
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
        self.assertIn("Step 1 of 8", log)
        self.assertIn("Summary:", log)
        self.assertIn("Publish: worked", log)
        self.assertEqual(done.returncode, 0)


class FinishLockTests(Setup):
    def test_it_runs_under_the_lock_for_its_whole_length(self):
        self.run_script("teach-finish.sh")
        holds = [c for c in self.called() if " teach_store.py hold" in c]
        self.assertEqual(len(holds), 1)
        self.assertTrue(holds[0].startswith("python3 teach_store.py hold "))
        self.assertTrue(holds[0].endswith("teach-finish.sh"), holds[0])
        # The hold is the first call, so every step is inside it.
        self.assertEqual(self.called()[0], holds[0])

    def test_another_run_in_the_folder_stops_it_with_exit_3_before_any_step(self):
        done = self.run_script("teach-finish.sh", BUSY="1")
        self.assertEqual(done.returncode, 3)
        self.assertIn("Another teaching run is already working", done.stdout)
        self.assertEqual(self.short(), [])

    def test_a_publish_that_missed_icloud_does_not_say_the_phone_has_the_results(self):
        done = self.run_script("teach-finish.sh", CODES="teach_publish.py=3")
        self.assertEqual(done.returncode, 1)
        self.assertNotIn("The results are where the phone reads them", done.stdout)
        self.assertIn("the copy into iCloud Drive did not work", done.stdout)
        self.assertIn("  Publish: failed", done.stdout)


class GatherTests(Setup):
    GATHER = "Gather episodes for teaching.command"

    def test_the_downloads_come_first_then_the_writing_down(self):
        done = self.run_script(self.GATHER)
        self.assertEqual(done.returncode, 0, done.stdout)
        names = [c.split()[1] for c in self.called()]
        self.assertEqual(names, ["teach_collect.py", "build", "build", "teach_transcribe.py"])

    def test_a_full_audio_folder_is_not_a_failure_and_is_still_written_down(self):
        done = self.run_script(self.GATHER, CODES="teach_collect.py=3")
        self.assertEqual(done.returncode, 0, done.stdout)
        self.assertIn("The size limit is reached", done.stdout)
        self.assertIn("teach_transcribe.py", " ".join(self.called()))
        self.assertIn("The size limit is reached", self.log())

    def test_downloads_that_failed_stop_it_before_the_writing_down(self):
        done = self.run_script(self.GATHER, CODES="teach_collect.py=2")
        # The sentence that says so is the prompt of the wait for Return, which only a Terminal shows.
        self.assertEqual(done.returncode, 1)
        self.assertEqual([c.split()[1] for c in self.called()], ["teach_collect.py"])


class CommandTests(Setup):
    MARK = "Mark ads in the teaching episodes.command"
    AGAIN = "Teach the phone again.command"

    def test_marking_that_finds_another_run_busy_does_not_run_the_steps_after_it(self):
        done = self.run_script(self.MARK, CODES="teach_label.py=2")
        self.assertEqual(done.returncode, 2)
        self.assertIn("the steps after marking did not run", done.stdout)
        self.assertEqual([c.split()[1] for c in self.called()], ["teach_label.py"])

    def test_marking_that_worked_runs_the_steps_after_it(self):
        done = self.run_script(self.MARK)
        self.assertEqual(done.returncode, 0, done.stdout)
        self.assertIn("python3 teach_publish.py", " ".join(self.called()))

    def test_marking_that_stopped_early_still_runs_the_steps_after_it(self):
        done = self.run_script(self.MARK, CODES="teach_label.py=3")
        self.assertEqual(done.returncode, 3)
        self.assertIn("python3 teach_publish.py", " ".join(self.called()))

    def test_not_typing_yes_runs_nothing_after_it(self):
        self.run_script(self.MARK, CODES="teach_label.py=4")
        self.assertEqual([c.split()[1] for c in self.called()], ["teach_label.py"])

    def test_teaching_again_says_so_and_stops_when_a_run_is_busy(self):
        done = self.run_script(self.AGAIN, BUSY="1")
        self.assertEqual(done.returncode, 1)
        self.assertIn("Another teaching run is already working", done.stdout)
        self.assertEqual([c.split()[1:3] for c in self.called()], [["teach_store.py", "busy"]])

    def test_teaching_again_runs_when_nothing_is_busy(self):
        done = self.run_script(self.AGAIN)
        self.assertEqual(done.returncode, 0, done.stdout)
        names = [c.split()[1] for c in self.called() if c.startswith("python3")]
        self.assertEqual(names[:2], ["teach_store.py", "teach_feedback.py"])
        self.assertIn("teach_publish.py", names)


class InstallerTests(Setup):
    NAME = "Install weekly teaching.command"

    def setUp(self):
        super().setUp()
        self.later = os.path.join(self.home, ".local", "bin")
        os.makedirs(self.later)
        for name in ("claude", "swift"):
            self.program_in(self.later, name, "#!/bin/bash\nexit 0\n")
        os.remove(os.path.join(self.bin, "swift"))
        self.program_in(self.bin, "plutil", '#!/bin/bash\necho "plutil $*" >> "$CALLS"\n'
                        '[ -n "$LINT_FAILS" ] && exit 1\nexit 0\n')
        self.program_in(self.bin, "launchctl", '#!/bin/bash\necho "launchctl $*" >> "$CALLS"\n'
                        'if [ "$1" = bootstrap ]; then\n  echo x >> "$CALLS.boot"\n'
                        '  [ -n "$BOOT_FAILS" ] && [ "$(wc -l < "$CALLS.boot")" -le "$BOOT_FAILS" ] && exit 5\n'
                        'fi\nexit 0\n')
        self.program_in(self.bin, "id", "#!/bin/bash\necho 501\n")
        self.plist = os.path.join(self.home, "Library", "LaunchAgents",
                                  "com.storyteller-lofi.podcast-teaching.plist")

    def program_in(self, folder, name, text):
        path = os.path.join(folder, name)
        with open(path, "w") as f:
            f.write(text)
        os.chmod(path, 0o755)

    def install(self, folder=None, **more):
        """Runs the installer (from `folder`, a copy of this folder) and types yes."""
        folder = folder or HERE
        env = {"HOME": self.home, "PATH": "%s:/usr/bin:/bin" % self.bin, "TMPDIR": os.path.join(self.root, "tmp"),
               "CALLS": self.calls, "LINT_FAILS": "", "BOOT_FAILS": ""}
        env.update(more)
        return subprocess.run(["bash", os.path.join(folder, self.NAME)], env=env, input="yes\n\n",
                              capture_output=True, text=True, timeout=60)

    def test_it_installs_when_claude_and_swift_are_on_the_jobs_path(self):
        done = self.install()
        self.assertEqual(done.returncode, 0, done.stdout)
        self.assertTrue(os.path.exists(self.plist))
        self.assertIn("plutil -lint", " ".join(self.called()))
        self.assertEqual([n for n in os.listdir(os.path.join(self.root, "tmp"))], [])

    def test_a_missing_claude_or_swift_stops_it_before_anything_is_changed(self):
        for missing, words in (("claude", "Install Claude Code"), ("swift", "Install Xcode 26")):
            os.remove(os.path.join(self.later, missing))
            done = self.install()
            self.assertEqual(done.returncode, 1, missing)
            self.assertIn(words, done.stdout)
            self.assertFalse(os.path.exists(self.plist), missing)
            self.program_in(self.later, missing, "#!/bin/bash\nexit 0\n")

    def test_a_job_file_that_fails_the_check_is_never_put_in_place(self):
        done = self.install(LINT_FAILS="1")
        self.assertEqual(done.returncode, 1)
        self.assertFalse(os.path.exists(self.plist))
        self.assertNotIn("launchctl bootstrap", " ".join(self.called()))
        self.assertEqual(os.listdir(os.path.join(self.root, "tmp")), [])

    def test_a_folder_name_with_xml_characters_is_escaped(self):
        odd = os.path.join(self.root, "a&b <c>")
        os.makedirs(odd)
        for name in (self.NAME, "teach-weekly.sh"):
            shutil.copy(os.path.join(HERE, name), os.path.join(odd, name))
        done = self.install(folder=odd)
        self.assertEqual(done.returncode, 0, done.stdout)
        import plistlib
        with open(self.plist, "rb") as f:
            job = plistlib.load(f)
        self.assertEqual(job["ProgramArguments"], ["/bin/bash", os.path.join(odd, "teach-weekly.sh")])

    def test_a_start_that_fails_right_after_bootout_is_tried_once_more(self):
        done = self.install(BOOT_FAILS="1")
        self.assertEqual(done.returncode, 0, done.stdout)
        self.assertEqual(len([c for c in self.called() if c.startswith("launchctl bootstrap")]), 2)

    def test_a_start_that_fails_twice_is_said(self):
        done = self.install(BOOT_FAILS="2")
        self.assertEqual(done.returncode, 1)
        self.assertIn("Could not start the job", done.stdout)


class WeeklyTests(Setup):
    def test_the_steps_run_in_order(self):
        done = self.run_script("teach-weekly.sh")
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertEqual(self.short(), [
            "python3 teach_store.py busy", "python3 teach_feedback.py",
            "python3 teach_collect.py --per-show 1 --max-gb 12",
            "swift build -c release --product podcast-transcribe",
            "swift build -c release --show-bin-path", "python3 teach_transcribe.py --tool %s/podcast-transcribe" % self.bin,
            "python3 teach_label.py --yes --limit 15 --cap 25"] + FINISH_ORDER)

    def test_marking_is_limited_by_a_cap_that_can_be_changed(self):
        self.run_script("teach-weekly.sh")
        self.assertIn("python3 teach_label.py --yes --limit 15 --cap 25", " ".join(self.short()))
        open(self.calls, "w").close()
        self.run_script("teach-weekly.sh", TEACH_CAP="9.5")
        self.assertIn("--limit 15 --cap 9.5", " ".join(self.short()))

    def test_a_full_audio_folder_ends_non_zero_with_one_plain_sentence(self):
        done = self.run_script("teach-weekly.sh", CODES="teach_collect.py=3")
        self.assertEqual(done.returncode, 1)
        self.assertIn("Nothing more can be gathered: the audio kept in the teaching folder has "
                      "reached its limit of 12 GB", done.stdout)
        self.assertIn("TEACH_MAX_GB", done.stdout)
        self.assertNotIn("Gathering did not work", done.stdout)
        self.assertIn("python3 teach_publish.py", " ".join(self.called()))  # the run goes on

    def test_the_audio_limit_can_be_changed(self):
        self.run_script("teach-weekly.sh", TEACH_MAX_GB="20")
        self.assertIn("python3 teach_collect.py --per-show 1 --max-gb 20", " ".join(self.short()))

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
        # launchd gives only the system folders. Only python3 may be found there; swift, the
        # transcriber and caffeinate live in ~/.local/bin, which the script adds to the path itself.
        later = os.path.join(self.home, ".local", "bin")
        os.makedirs(later)
        for name in ("swift", "podcast-teach", "caffeinate"):
            shutil.move(os.path.join(self.bin, name), os.path.join(later, name))
        short = os.path.join(self.root, "system")
        os.makedirs(short)
        shutil.copy(os.path.join(self.bin, "python3"), os.path.join(short, "python3"))
        done = self.run_script("teach-weekly.sh", PATH="%s:/usr/bin:/bin:/usr/sbin:/sbin" % short)
        self.assertEqual(done.returncode, 0, done.stdout)
        self.assertIn("swift build -c release --product podcast-transcribe", self.called())

    def test_a_short_path_without_the_places_it_adds_would_not_find_swift(self):
        # The same set-up with swift nowhere on the path must fail, so the test above really tests
        # the added places.
        short = os.path.join(self.root, "system")
        os.makedirs(short)
        shutil.copy(os.path.join(self.bin, "python3"), os.path.join(short, "python3"))
        os.remove(os.path.join(self.bin, "swift"))
        done = self.run_script("teach-weekly.sh", PATH="%s:/usr/bin:/bin:/usr/sbin:/sbin" % short)
        self.assertEqual(done.returncode, 1)
        self.assertIn("swift is missing", done.stdout)

    def test_the_log_gets_a_heading_with_the_date(self):
        self.run_script("teach-weekly.sh")
        self.assertRegex(self.log(), r"=== \d{4}-\d\d-\d\d \d\d:\d\d weekly teaching ===")


if __name__ == "__main__":
    unittest.main()
