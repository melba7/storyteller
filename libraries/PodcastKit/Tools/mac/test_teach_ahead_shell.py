"""Tests for the shell files of the nightly read-ahead: teach-ahead.sh is run with stand-in python3,
swift and caffeinate programs on a temporary PATH, to check the order of the steps, the weekly budget
it hands to the marking, a night that has nothing to do, a failing step and the exit code; the
installer is run with stand-in launchctl, plutil and id programs, so the job file it writes is only
read as text and never loaded, and the stopper the same. No Mac, no Claude, no iCloud.
Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import os
import plistlib
import re
import shutil
import subprocess
import sys
import unittest

from teach_store import run_lock
from test_teach_shell import HERE, Setup

# The stand-in tells scripts apart by name, and teach_ahead.py by its first word too (pick, ready,
# write): FAIL and CODES name them as "teach_ahead.py:pick". With REAL_STORE and PROBE set, teach_store.py
# is the real one (so the lock is real) and every other tool asks the real lock, while it runs, whether
# the folder PROBE is busy, and writes "lock-during <tool> <exit code>" (3 is busy) to the calls.
PYTHON = """#!/bin/bash
[ "$1" = "-u" ] && shift
script="$(basename "$1")"
shift
echo "python3 $script $*" >> "$CALLS"
if [ -n "$REAL_STORE" ]; then
  [ "$script" = teach_store.py ] && exec "$REAL_PYTHON" "$REAL_STORE" "$@"
  # The probe plays a stranger: without the marker that `hold` gives the tools it started.
  env -u TEACH_LOCK_HELD "$REAL_PYTHON" "$REAL_STORE" busy "$PROBE" > /dev/null
  echo "lock-during $script $?" >> "$CALLS"
fi
key="$script"
[ "$script" = teach_ahead.py ] && key="$script:$1"
case " $FAIL " in *" $key "*) echo "$key: pretending to fail"; exit 1 ;; esac
for pair in $CODES; do
  [ "${pair%%=*}" = "$key" ] && { echo "$key: ending with ${pair#*=}"; exit "${pair#*=}"; }
done
if [ "$script" = teach_store.py ]; then
  [ -n "$BUSY" ] && exit 3
  if [ "$1" = hold ]; then
    shift 2
    exec "$@"
  fi
  exit 0
fi
exit 0
"""

# A stand-in for date that says it is a Wednesday (FAKE_WEEKDAY changes the day), so the tests do not
# depend on the day they run on; everything else it passes on to the real one.
DATE = """#!/bin/bash
[ "$1" = "+%u" ] && { echo "${FAKE_WEEKDAY:-3}"; exit 0; }
exec /bin/date "$@"
"""

class NightTests(Setup):
    def setUp(self):
        super().setUp()
        self.program("python3", PYTHON)
        self.program("date", DATE)
        self.name = "teach-ahead.sh"

    def night(self, **more):
        return self.run_script(self.name, **more)

    def real_lock(self):
        """The environment that makes teach_store.py real and the folder the one to probe."""
        folder = os.path.join(self.root, "teaching")
        return {"REAL_PYTHON": sys.executable, "REAL_STORE": os.path.join(HERE, "teach_store.py"),
                "PROBE": folder, "TEACH_FOLDER": folder}, folder

    def first_words(self):
        """Each call as its tool and, for teach_ahead.py, its command, without the options."""
        words = []
        for line in self.called():
            parts = line.split()
            if parts[0] == "python3":
                words.append(" ".join(parts[:3] if parts[1] == "teach_ahead.py" else parts[:2]))
            else:
                words.append(" ".join(parts[:4]))
        return words

    def line(self, tool):
        return [c for c in self.called() if (" " + tool + " ") in (c + " ")][0]

    def log(self):
        with open(os.path.join(self.home, "Storyteller Lofi", "logs", "podcast-read-ahead.log")) as f:
            return f.read()

    def test_the_steps_run_in_order_and_everything_worked(self):
        done = self.night()
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertEqual(self.first_words(),
                         ["python3 teach_store.py", "python3 teach_ahead.py pick",
                          "python3 teach_collect.py", "python3 teach_ahead.py ready",
                          "swift build -c release", "swift build -c release", "python3 teach_transcribe.py",
                          "python3 teach_label.py", "python3 teach_ahead.py write",
                          "python3 teach_publish.py"])
        self.assertIn("Tonight's read-ahead is done.", done.stdout)

    def test_the_other_tools_are_limited_to_the_nights_episodes(self):
        self.night()
        for tool in ("teach_collect.py", "teach_transcribe.py", "teach_label.py"):
            self.assertIn(" --only-ahead", self.line(tool), tool)
        self.assertNotIn("--only-ahead", self.line("teach_publish.py"))

    def test_the_marking_gets_the_weekly_budget_the_cap_the_reserve_and_the_limit(self):
        self.night()
        label = self.line("teach_label.py")
        self.assertRegex(label, r"--budget ahead-\d{4}-W\d{2} ")
        for words in ("--yes", "--limit 8", "--cap 10", "--reserve 0.19"):
            self.assertIn(words, label)
        pick = self.line("teach_ahead.py")
        budget = re.search(r"--budget (\S+)", pick).group(1)
        self.assertIn("--budget %s " % budget, label + " ")
        self.assertTrue(all(w in pick for w in ("--cap 10", "--estimate 0.19", "--most 8")))

    def test_the_budget_is_the_iso_year_and_week(self):
        week = subprocess.run(["date", "+%G-W%V"], capture_output=True, text=True).stdout.strip()
        self.night()
        self.assertIn("--budget ahead-%s" % week, self.line("teach_label.py"))

    def test_the_limits_can_be_changed(self):
        self.night(TEACH_AHEAD_CAP="4.5", TEACH_AHEAD_ESTIMATE="0.3", TEACH_AHEAD_MOST="5",
                   TEACH_MAX_GB="20")
        label = self.line("teach_label.py")
        for words in ("--limit 5", "--cap 4.5", "--reserve 0.3"):
            self.assertIn(words, label)
        self.assertIn("--max-gb 20", self.line("teach_collect.py"))

    def test_the_transcriber_is_the_one_that_was_built(self):
        self.night()
        self.assertIn("--tool %s/podcast-transcribe" % self.bin, self.line("teach_transcribe.py"))

    def test_a_night_with_no_queue_does_nothing_and_ends_with_exit_0(self):
        done = self.night(CODES="teach_ahead.py:pick=3")
        self.assertEqual(done.returncode, 0)
        self.assertEqual(self.first_words(), ["python3 teach_store.py", "python3 teach_ahead.py pick"])

    def test_a_night_with_no_budget_left_does_the_same(self):
        # pick says so and ends with 3 when the weekly cap leaves no room.
        done = self.night(CODES="teach_ahead.py:pick=3")
        self.assertEqual((done.returncode, len(self.called())), (0, 2))

    def test_a_night_without_audio_stops_before_the_writing_down_and_the_marking(self):
        done = self.night(CODES="teach_ahead.py:ready=3")
        self.assertEqual(done.returncode, 0, done.stdout)
        self.assertEqual(self.first_words()[-1], "python3 teach_ahead.py ready")
        self.assertNotIn("swift", " ".join(self.called()))

    def test_a_pick_that_fails_is_an_error_and_nothing_goes_on(self):
        done = self.night(FAIL="teach_ahead.py:pick")
        self.assertEqual(done.returncode, 1)
        self.assertEqual(len(self.called()), 2)
        self.assertIn("nothing was read ahead", done.stdout)

    def test_another_run_in_the_folder_ends_quietly_with_exit_0(self):
        done = self.night(BUSY="1")
        self.assertEqual((done.returncode, len(self.called())), (0, 1))
        self.assertIn("Another teaching run is already working", done.stdout)

    def test_the_whole_night_runs_under_the_folders_lock(self):
        env, folder = self.real_lock()
        done = self.night(**env)
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        # The first call is the hold, the only one, and it starts this same file again.
        holds = [c for c in self.called() if " teach_store.py " in (c + " ")]
        self.assertEqual(len(holds), 1, holds)
        self.assertTrue(holds[0].startswith("python3 teach_store.py hold %s " % folder), holds[0])
        self.assertTrue(holds[0].endswith("teach-ahead.sh"), holds[0])
        self.assertEqual(self.called()[0], holds[0])
        # While every step ran, a second run would have found the folder busy (exit code 3): the lock
        # is held between the steps too, not only during one of them.
        during = [c for c in self.called() if c.startswith("lock-during")]
        self.assertEqual([c.split()[1] for c in during],
                         ["teach_ahead.py", "teach_collect.py", "teach_ahead.py", "teach_transcribe.py",
                          "teach_label.py", "teach_ahead.py", "teach_publish.py"])
        self.assertEqual({c.split()[2] for c in during}, {"3"}, during)
        # And it is let go at the end.
        free = subprocess.run([sys.executable, os.path.join(HERE, "teach_store.py"), "busy", folder])
        self.assertEqual(free.returncode, 0)

    def test_another_run_holding_the_real_lock_ends_it_quietly_before_any_step(self):
        env, folder = self.real_lock()
        with run_lock(folder):
            done = self.night(**env)
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertIn("Another teaching run is already working", done.stdout)
        self.assertIn("tonight's read-ahead is skipped", done.stdout)
        self.assertNotIn("not every step worked", done.stdout)
        self.assertEqual([c.split()[1] for c in self.called()], ["teach_store.py"])
        self.assertIn("tonight's read-ahead is skipped", self.log())

    def test_a_sunday_morning_does_nothing_so_it_never_meets_the_weekly_run_at_3(self):
        done = self.night(FAKE_WEEKDAY="7")
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertEqual(self.called(), [])  # not even the lock is taken
        self.assertIn("Sunday", done.stdout)
        self.assertIn("3:00", done.stdout)
        self.assertIn("Sunday", self.log())

    def test_every_other_day_of_the_week_runs(self):
        for day in ("1", "2", "3", "4", "5", "6"):
            open(self.calls, "w").close()
            done = self.night(FAKE_WEEKDAY=day, CODES="teach_ahead.py:pick=3")
            self.assertEqual(done.returncode, 0, day)
            self.assertEqual(self.first_words(), ["python3 teach_store.py", "python3 teach_ahead.py pick"], day)

    def test_the_weekly_cap_reached_is_not_a_failure(self):
        done = self.night(CODES="teach_label.py=5")
        self.assertEqual(done.returncode, 0, done.stdout)
        self.assertIn("cap of $10 is reached", done.stdout)
        self.assertEqual(self.first_words()[-1], "python3 teach_publish.py")

    def test_a_failing_step_does_not_stop_the_others_but_the_exit_code_says_so(self):
        for failing in ("teach_collect.py", "teach_transcribe.py", "teach_label.py",
                        "teach_ahead.py:write", "teach_publish.py"):
            open(self.calls, "w").close()
            done = self.night(FAIL=failing)
            self.assertEqual(done.returncode, 1, failing)
            self.assertEqual(self.first_words()[-1], "python3 teach_publish.py", failing)
            self.assertIn("not every step worked", done.stdout, failing)

    def test_a_full_audio_folder_ends_non_zero_with_one_plain_sentence(self):
        done = self.night(CODES="teach_collect.py=3")
        self.assertEqual(done.returncode, 1)
        self.assertIn("reached its limit of 12 GB", done.stdout)
        self.assertIn("TEACH_MAX_GB", done.stdout)

    def test_a_publish_that_missed_icloud_is_said(self):
        done = self.night(CODES="teach_publish.py=3")
        self.assertEqual(done.returncode, 1)
        self.assertIn("iCloud Drive did not work", done.stdout)

    def test_a_failing_build_leaves_out_the_transcriber_and_goes_on(self):
        done = self.night(BUILD_FAILS="1")
        self.assertEqual(done.returncode, 1)
        self.assertNotIn("teach_transcribe.py", " ".join(self.called()))
        self.assertIn("python3 teach_label.py", " ".join(self.called()))
        self.assertIn("The transcriber did not build", done.stdout)

    def test_it_works_with_a_short_path_as_launchd_gives_it(self):
        later = os.path.join(self.home, ".local", "bin")
        os.makedirs(later)
        for name in ("swift", "podcast-teach", "caffeinate"):
            shutil.move(os.path.join(self.bin, name), os.path.join(later, name))
        short = os.path.join(self.root, "system")
        os.makedirs(short)
        shutil.copy(os.path.join(self.bin, "python3"), os.path.join(short, "python3"))
        done = self.night(PATH="%s:/usr/bin:/bin:/usr/sbin:/sbin" % short)
        self.assertEqual(done.returncode, 0, done.stdout)
        self.assertIn("swift build -c release --product podcast-transcribe", self.called())

    def test_the_log_gets_a_heading_and_everything_said(self):
        self.night()
        self.assertRegex(self.log(), r"=== \d{4}-\d\d-\d\d \d\d:\d\d nightly read-ahead ===")
        self.assertIn("Tonight's read-ahead is done.", self.log())

    def test_it_asks_for_nothing_that_costs_money_except_the_marking(self):
        self.night()
        paid = [c for c in self.called() if "--cap" in c]
        self.assertEqual(len(paid), 2)  # the pick (to count the room) and the marking
        self.assertTrue(all("--cap 10" in c for c in paid))


class JobTests(Setup):
    NAME = "Install nightly read-ahead.command"
    STOP = "Stop nightly read-ahead.command"

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
                                  "com.storyteller-lofi.podcast-read-ahead.plist")

    def program_in(self, folder, name, text):
        path = os.path.join(folder, name)
        with open(path, "w") as f:
            f.write(text)
        os.chmod(path, 0o755)

    def run_file(self, name, answer="yes\n\n", folder=None, **more):
        env = {"HOME": self.home, "PATH": "%s:/usr/bin:/bin" % self.bin, "TMPDIR": os.path.join(self.root, "tmp"),
               "CALLS": self.calls, "LINT_FAILS": "", "BOOT_FAILS": ""}
        env.update(more)
        return subprocess.run(["bash", os.path.join(folder or HERE, name)], env=env, input=answer,
                              capture_output=True, text=True, timeout=60)

    def job(self):
        with open(self.plist, "rb") as f:
            return plistlib.load(f)

    def test_the_job_file_runs_teach_ahead_every_night_at_2_and_nothing_else(self):
        done = self.run_file(self.NAME)
        self.assertEqual(done.returncode, 0, done.stdout)
        job = self.job()
        self.assertEqual(job["Label"], "com.storyteller-lofi.podcast-read-ahead")
        self.assertEqual(job["ProgramArguments"], ["/bin/bash", os.path.join(HERE, "teach-ahead.sh")])
        self.assertEqual(job["StartCalendarInterval"], {"Hour": 2, "Minute": 0})  # no weekday: every night
        logs = os.path.join(self.home, "Storyteller Lofi", "logs")
        self.assertEqual(job["StandardOutPath"], os.path.join(logs, "podcast-read-ahead-job.log"))
        self.assertEqual(job["StandardErrorPath"], job["StandardOutPath"])
        self.assertEqual(job["EnvironmentVariables"]["HOME"], self.home)
        for place in ("/usr/bin", "/opt/homebrew/bin", os.path.join(self.home, ".local", "bin"),
                      os.path.join(self.home, ".claude", "local")):
            self.assertIn(place, job["EnvironmentVariables"]["PATH"].split(":"))
        self.assertEqual(set(job), {"Label", "ProgramArguments", "StartCalendarInterval", "LowPriorityIO",
                                    "Nice", "EnvironmentVariables", "StandardOutPath", "StandardErrorPath"})

    def test_it_names_the_weekly_cap_and_the_cost_before_it_asks_for_the_yes(self):
        done = self.run_file(self.NAME)
        words = done.stdout.split("Type yes")[0]
        self.assertIn("$10 a week", words)
        self.assertIn("$0.19 an episode", words)
        self.assertIn("up to 8", words)
        self.assertIn("2:00", words)

    def test_the_job_is_checked_and_replaced_not_added_and_never_loaded_by_a_test(self):
        self.run_file(self.NAME)
        calls = self.called()
        self.assertIn("plutil -lint", " ".join(calls))
        self.assertEqual([c for c in calls if c.startswith("launchctl")],
                         ["launchctl bootout gui/501/com.storyteller-lofi.podcast-read-ahead",
                          "launchctl bootstrap gui/501 %s" % self.plist])
        self.assertEqual(os.listdir(os.path.join(self.root, "tmp")), [])

    def test_anything_but_yes_changes_nothing(self):
        for answer in ("\n\n", "no\n\n", "y\n\n", "yes please\n\n"):
            done = self.run_file(self.NAME, answer=answer)
            self.assertEqual(done.returncode, 0, answer)
            self.assertFalse(os.path.exists(self.plist), answer)
            self.assertEqual([c for c in self.called() if c.startswith("launchctl")], [])
            self.assertIn("was not turned on", done.stdout)

    def test_a_missing_claude_or_swift_stops_it_before_anything_is_changed(self):
        for missing, words in (("claude", "Install Claude Code"), ("swift", "Install Xcode 26")):
            os.remove(os.path.join(self.later, missing))
            done = self.run_file(self.NAME)
            self.assertEqual(done.returncode, 1, missing)
            self.assertIn(words, done.stdout)
            self.assertFalse(os.path.exists(self.plist), missing)
            self.program_in(self.later, missing, "#!/bin/bash\nexit 0\n")

    def test_a_job_file_that_fails_the_check_is_never_put_in_place(self):
        done = self.run_file(self.NAME, LINT_FAILS="1")
        self.assertEqual(done.returncode, 1)
        self.assertFalse(os.path.exists(self.plist))
        self.assertNotIn("launchctl bootstrap", " ".join(self.called()))
        self.assertEqual(os.listdir(os.path.join(self.root, "tmp")), [])

    def test_a_folder_name_with_xml_characters_is_escaped(self):
        odd = os.path.join(self.root, "a&b <c>")
        os.makedirs(odd)
        for name in (self.NAME, "teach-ahead.sh"):
            shutil.copy(os.path.join(HERE, name), os.path.join(odd, name))
        done = self.run_file(self.NAME, folder=odd)
        self.assertEqual(done.returncode, 0, done.stdout)
        self.assertEqual(self.job()["ProgramArguments"], ["/bin/bash", os.path.join(odd, "teach-ahead.sh")])

    def test_a_start_that_fails_right_after_bootout_is_tried_once_more_and_twice_is_said(self):
        done = self.run_file(self.NAME, BOOT_FAILS="1")
        self.assertEqual(done.returncode, 0, done.stdout)
        self.assertEqual(len([c for c in self.called() if c.startswith("launchctl bootstrap")]), 2)
        done = self.run_file(self.NAME, BOOT_FAILS="9")
        self.assertEqual(done.returncode, 1)
        self.assertIn("Could not start the job", done.stdout)

    def test_the_stopper_turns_the_job_off_and_keeps_everything_else(self):
        self.run_file(self.NAME)
        open(self.calls, "w").close()
        done = self.run_file(self.STOP, answer="\n")
        self.assertEqual(done.returncode, 0, done.stdout)
        self.assertFalse(os.path.exists(self.plist))
        self.assertEqual([c for c in self.called() if c.startswith("launchctl")],
                         ["launchctl bootout gui/501/com.storyteller-lofi.podcast-read-ahead"])
        self.assertIn("The nightly read-ahead is off", done.stdout + done.stderr)


if __name__ == "__main__":
    unittest.main()
