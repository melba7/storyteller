"""Tests for nightly teaching: teach-nightly.sh (the job's script), its installer and its stopper. The
stand-in python3, swift and podcast-teach programs of test_teach_shell.py are used; no Mac needed.
Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import os
import plistlib
import re
import subprocess

import test_teach_shell as shell

LABEL = "com.storyteller-lofi.podcast-nightly-teaching"


class NightlyScriptTests(shell.Setup):
    def test_it_runs_the_finish_steps_in_order(self):
        done = self.run_script("teach-nightly.sh")
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        steps = [c for c in self.short() if not c.startswith("python3 teach_store.py busy")]
        self.assertEqual(steps, shell.FINISH_ORDER)

    def test_it_asks_about_the_lock_first_and_the_finish_run_holds_it_for_its_whole_length(self):
        self.run_script("teach-nightly.sh")
        calls = self.called()
        self.assertTrue(calls[0].startswith("python3 teach_store.py busy "), calls[0])
        self.assertTrue(calls[1].startswith("python3 teach_store.py hold "), calls[1])
        self.assertTrue(calls[1].endswith("teach-finish.sh"), calls[1])

    def test_when_another_run_holds_the_lock_all_along_it_skips_quietly_and_does_nothing(self):
        done = self.run_script("teach-nightly.sh", BUSY="1", TEACH_NIGHTLY_WAIT_SECONDS="0",
                               TEACH_NIGHTLY_WAIT_TRIES="3")
        self.assertEqual(done.returncode, 0)
        self.assertEqual(len(self.short()), 3)
        self.assertEqual(done.stdout.count("Waiting for it"), 1)
        self.assertEqual(self.short(), [c for c in self.short() if c.startswith("python3 teach_store.py busy")])
        self.assertNotIn("python3 teach_habits.py", " ".join(self.called()))
        self.assertEqual(done.stdout.count("tonight's teaching is skipped"), 1)
        self.assertIn("It tries again tomorrow night.", self.log())

    def test_a_run_that_takes_the_lock_between_the_question_and_the_start_is_skipped_too(self):
        # The question says free (exit 0) and the hold says busy (exit 3).
        self.program("python3", shell.PYTHON.replace(
            '  [ -n "$BUSY" ] && {', '  [ "$1" = hold ] && [ -n "$BUSY" ] && {', 1))
        done = self.run_script("teach-nightly.sh", BUSY="1", TEACH_NIGHTLY_WAIT_SECONDS="0",
                               TEACH_NIGHTLY_WAIT_TRIES="2")
        self.assertEqual(done.returncode, 0, done.stdout)
        self.assertIn("tonight's teaching is skipped", done.stdout)
        self.assertNotIn("python3 teach_habits.py", " ".join(self.called()))

    def test_it_waits_for_a_run_that_holds_the_lock_and_teaches_when_it_is_done(self):
        # Episode preparing started at 3:25 and still works at 3:30: the lock is busy for the
        # first two looks and free at the third.
        self.program("python3", shell.PYTHON.replace(
            '  [ -n "$BUSY" ] && {',
            '  [ -n "$BUSY" ] && [ "$(grep -c "teach_store.py busy" "$CALLS")" -le 2 ] && {', 1))
        done = self.run_script("teach-nightly.sh", BUSY="1", TEACH_NIGHTLY_WAIT_SECONDS="0")
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        steps = [c for c in self.short() if not c.startswith("python3 teach_store.py busy")]
        self.assertEqual(steps, shell.FINISH_ORDER)
        self.assertEqual(len(self.short()) - len(steps), 3)
        self.assertEqual(done.stdout.count("Waiting for it"), 1)
        self.assertNotIn("tonight's teaching is skipped", done.stdout)

    def test_it_looks_every_minute_for_45_minutes_unless_told_otherwise(self):
        with open(os.path.join(shell.HERE, "teach-nightly.sh"), encoding="utf-8") as f:
            text = f.read()
        self.assertIn('WAIT_SECONDS="${TEACH_NIGHTLY_WAIT_SECONDS:-60}"', text)
        self.assertIn('WAIT_TRIES="${TEACH_NIGHTLY_WAIT_TRIES:-45}"', text)

    def test_it_makes_no_call_to_claude(self):
        self.run_script("teach-nightly.sh")
        for call in self.called():
            call = call.replace(shell.HERE, "")  # the worktree's own path has ".claude" in it
            for word in ("teach_label", "teach_collect", "teach_transcribe", "teach_ahead", "teach_prepare", "claude"):
                self.assertNotIn(word, call)
        for name in ("teach-nightly.sh", "teach-finish.sh"):
            with open(os.path.join(shell.HERE, name), encoding="utf-8") as f:
                code = "".join(line for line in f if not line.lstrip().startswith("#"))
            self.assertIsNone(re.search(r"teach_label|\bclaude -|--yes|teach_ahead|teach_collect", code), name)

    def test_a_failed_publish_gives_a_non_zero_exit_for_the_job_log(self):
        done = self.run_script("teach-nightly.sh", CODES="teach_publish.py=2")
        self.assertEqual(done.returncode, 1)

    def test_a_failed_score_stops_the_settings_and_says_so_in_one_line(self):
        done = self.run_script("teach-nightly.sh", TEACH_CODES="score=137")
        self.assertNotIn("python3 teach_settings.py", " ".join(self.short()))
        self.assertEqual(done.stdout.count("The score failed, so no new settings"), 1)
        self.assertIn("exit code 137", self.log())
        self.assertIn("python3 teach_publish.py", " ".join(self.short()))


class NightlyInstallerTests(shell.Setup):
    NAME = "Install nightly teaching.command"

    # The same fake launchctl, plutil and id as the weekly installer's tests use.
    def setUp(self):
        super().setUp()
        self.later = os.path.join(self.home, ".local", "bin")
        os.makedirs(self.later)
        for name in ("claude", "swift"):
            self.program_in(self.later, name, "#!/bin/bash\nexit 0\n")
        os.remove(os.path.join(self.bin, "swift"))
        self.program_in(self.bin, "plutil", '#!/bin/bash\necho "plutil $*" >> "$CALLS"\n'
                        '[ -n "$LINT_FAILS" ] && exit 1\nexit 0\n')
        self.program_in(self.bin, "launchctl", '#!/bin/bash\necho "launchctl $*" >> "$CALLS"\nexit 0\n')
        self.program_in(self.bin, "id", "#!/bin/bash\necho 501\n")

    def program_in(self, folder, name, text):
        path = os.path.join(folder, name)
        with open(path, "w") as f:
            f.write(text)
        os.chmod(path, 0o755)

    def install(self, **more):
        env = {"HOME": self.home, "PATH": "%s:/usr/bin:/bin" % self.bin, "TMPDIR": os.path.join(self.root, "tmp"),
               "CALLS": self.calls, "LINT_FAILS": ""}
        env.update(more)
        return subprocess.run(["bash", os.path.join(shell.HERE, self.NAME)], env=env, input="yes\n\n",
                              capture_output=True, text=True, timeout=60)

    def job(self):
        self.plist = os.path.join(self.home, "Library", "LaunchAgents", LABEL + ".plist")
        with open(self.plist, "rb") as f:
            return plistlib.load(f)

    def plist_path(self):
        return os.path.join(self.home, "Library", "LaunchAgents", LABEL + ".plist")

    def test_it_runs_at_3_30_every_night_and_runs_teach_nightly(self):
        done = self.install()
        self.assertEqual(done.returncode, 0, done.stdout)
        job = self.job()
        self.assertEqual(job["Label"], LABEL)
        self.assertEqual(job["StartCalendarInterval"], {"Hour": 3, "Minute": 30})
        self.assertEqual(job["ProgramArguments"], ["/bin/bash", os.path.join(shell.HERE, "teach-nightly.sh")])
        self.assertTrue(job["StandardOutPath"].endswith("podcast-nightly-teaching.log"))
        self.assertIn("launchctl bootstrap gui/501 " + self.plist_path(), self.called())

    def test_it_is_a_different_job_from_the_weekly_and_the_preparing_ones(self):
        self.assertNotIn(LABEL, ("com.storyteller-lofi.podcast-teaching", "com.storyteller-lofi.podcast-prepare"))

    def test_it_does_not_need_claude(self):
        os.remove(os.path.join(self.later, "claude"))
        done = self.install()
        self.assertEqual(done.returncode, 0, done.stdout)
        self.assertTrue(os.path.exists(self.plist_path()))

    def test_a_missing_swift_stops_it_before_anything_is_changed(self):
        os.remove(os.path.join(self.later, "swift"))
        done = self.install()
        self.assertEqual(done.returncode, 1)
        self.assertIn("Install Xcode 26", done.stdout)
        self.assertFalse(os.path.exists(self.plist_path()))

    def test_not_typing_yes_changes_nothing(self):
        env = {"HOME": self.home, "PATH": "%s:/usr/bin:/bin" % self.bin, "CALLS": self.calls}
        done = subprocess.run(["bash", os.path.join(shell.HERE, self.NAME)], env=env, input="\n\n",
                              capture_output=True, text=True, timeout=60)
        self.assertEqual(done.returncode, 0)
        self.assertFalse(os.path.exists(self.plist_path()))

    def test_a_job_file_that_fails_the_check_is_never_put_in_place(self):
        done = self.install(LINT_FAILS="1")
        self.assertEqual(done.returncode, 1)
        self.assertFalse(os.path.exists(self.plist_path()))

    def test_installing_twice_replaces_the_job(self):
        self.install()
        self.install()
        boots = [c for c in self.called() if c.startswith("launchctl bootout")]
        self.assertEqual(len(boots), 2)
        self.assertEqual(len(os.listdir(os.path.dirname(self.plist_path()))), 1)

    def test_the_stopper_turns_the_job_off_and_removes_its_file(self):
        self.install()
        self.assertTrue(os.path.exists(self.plist_path()))
        env = {"HOME": self.home, "PATH": "%s:/usr/bin:/bin" % self.bin, "CALLS": self.calls}
        done = subprocess.run(["bash", os.path.join(shell.HERE, "Stop nightly teaching.command")], env=env,
                              input="\n", capture_output=True, text=True, timeout=60)
        self.assertEqual(done.returncode, 0, done.stdout)
        self.assertFalse(os.path.exists(self.plist_path()))
        self.assertIn("launchctl bootout gui/501/" + LABEL, self.called())
