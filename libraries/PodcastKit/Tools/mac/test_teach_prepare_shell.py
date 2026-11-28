"""Tests for the shell files of episode preparing: teach-prepare.sh is run with stand-in python3,
swift and caffeinate programs on a temporary PATH, to check the order of the steps, the weekly budget
it hands to the marking, an episode that fails not keeping the others from the phone, another run in
the folder making the hour pass quietly, and the exit code; the installer is run with stand-in
launchctl, plutil, brctl and id programs, so the job file is only read as text and never loaded, and
nothing is installed without the typed yes. No Mac, no Claude, no iCloud.
Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import os
import plistlib
import re
import shutil
import stat
import subprocess
import sys
import unittest

from teach_store import run_lock
from test_teach_ahead_shell import DATE, PYTHON
from test_teach_shell import HERE, Setup

FILES = ("teach-prepare.sh", "Install episode preparing.command", "Stop episode preparing.command")

# The stand-in tells teach_prepared.py's commands apart too (ready, publish), as it does teach_ahead.py's.
PYTHON = PYTHON.replace('[ "$script" = teach_ahead.py ] && key="$script:$1"',
                        '[ "$script" = teach_ahead.py ] && key="$script:$1"\n'
                        '[ "$script" = teach_prepared.py ] && key="$script:$1"')

# A swift that builds both programs, and fails for one of them when asked.
SWIFT = """#!/bin/bash
echo "swift $*" >> "$CALLS"
case "$*" in *--show-bin-path*) echo "$BIN"; exit 0 ;; esac
case "$*" in *"--product podcast-transcribe"*) [ -n "$TRANSCRIBER_FAILS" ] && { echo "error: broke"; exit 1; } ;; esac
case "$*" in *"--product podcast-ads"*) [ -n "$ADS_FAILS" ] && { echo "error: broke"; exit 1; } ;; esac
exit 0
"""


class ShapeTests(unittest.TestCase):
    def test_the_files_are_runnable_bash_that_parses_and_keeps_to_bash_3_2(self):
        banned = [r"declare\s+-A", r"\bmapfile\b", r"\breadarray\b", r"\$\{[A-Za-z_]+(,,|\^\^)\}",
                  r"\$\(<<", r"&>>?", r"\|&", r"\bcoproc\b"]
        for name in FILES:
            path = os.path.join(HERE, name)
            self.assertTrue(os.stat(path).st_mode & stat.S_IXUSR, name)
            with open(path, encoding="utf-8") as f:
                text = f.read()
            self.assertEqual(text.splitlines()[0], "#!/bin/bash", name)
            done = subprocess.run(["bash", "-n", path], capture_output=True, text=True)
            self.assertEqual(done.returncode, 0, "%s: %s" % (name, done.stderr))
            code = "".join(line for line in text.splitlines(True) if not line.lstrip().startswith("#"))
            for pattern in banned:
                self.assertIsNone(re.search(pattern, code), "%s uses %s" % (name, pattern))
            self.assertIsNone(re.search(r"\$\([^)]*<<", text), name)

    def test_the_nightly_read_ahead_files_are_still_there(self):
        for name in ("teach-ahead.sh", "Install nightly read-ahead.command", "Stop nightly read-ahead.command"):
            self.assertTrue(os.path.exists(os.path.join(HERE, name)), name)


class HourTests(Setup):
    def setUp(self):
        super().setUp()
        self.program("python3", PYTHON)
        self.program("date", DATE)
        self.program("swift", SWIFT)

    def hour(self, **more):
        env = {"TRANSCRIBER_FAILS": "", "ADS_FAILS": ""}
        env.update(more)
        return self.run_script("teach-prepare.sh", **env)

    def real_lock(self):
        folder = os.path.join(self.root, "teaching")
        return {"REAL_PYTHON": sys.executable, "REAL_STORE": os.path.join(HERE, "teach_store.py"),
                "PROBE": folder, "TEACH_FOLDER": folder}, folder

    def first_words(self):
        words = []
        for line in self.called():
            parts = line.split()
            if parts[0] == "python3":
                words.append(" ".join(parts[:3] if parts[1] in ("teach_ahead.py", "teach_store.py", "teach_prepared.py")
                                      else parts[:2]))
            else:
                words.append(" ".join(parts[:4]))
        return words

    def line(self, tool):
        return [c for c in self.called() if (" " + tool + " ") in (c + " ")][0]

    def log(self):
        with open(os.path.join(self.home, "Storyteller Lofi", "logs", "podcast-prepare.log")) as f:
            return f.read()

    ORDER = ["python3 teach_store.py hold", "python3 teach_prepared.py ready", "python3 teach_taps.py", "python3 teach_prepare.py",
             "python3 teach_collect.py",
             "python3 teach_ahead.py ready", "swift build -c release", "swift build -c release",
             "python3 teach_transcribe.py", "python3 teach_label.py", "swift build -c release",
             "swift build -c release", "python3 teach_copies.py", "python3 teach_snap.py",
             "python3 teach_prepared.py publish", "python3 teach_maps.py", "python3 teach_coming_publish.py",
             "python3 teach_ahead.py write", "python3 teach_publish.py"]

    def test_the_steps_run_in_order_and_everything_worked(self):
        done = self.hour()
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertEqual(self.first_words(), self.ORDER)
        self.assertIn("This run's episode preparing is done.", done.stdout)

    def test_the_other_tools_are_limited_to_the_hours_episodes(self):
        self.hour()
        for tool in ("teach_collect.py", "teach_transcribe.py", "teach_label.py", "teach_copies.py"):
            self.assertIn(" --only-ahead", self.line(tool), tool)
        for tool in ("teach_snap.py", "teach_prepared.py", "teach_publish.py", "teach_prepare.py"):
            self.assertNotIn("--only-ahead", self.line(tool), tool)

    def test_the_pick_and_the_marking_share_the_weekly_budget_cap_and_limit(self):
        self.hour()
        pick, label = self.line("teach_prepare.py"), self.line("teach_label.py")
        for words in ("pick", "--cap 35", "--estimate 0.19", "--most 6"):
            self.assertIn(words, pick)
        for words in ("--yes", "--limit 6", "--cap 35", "--reserve 1.00"):
            self.assertIn(words, label)
        self.assertIn("--estimate 0.19", pick)
        self.assertIn("--reserve 1.00", pick)
        budget = re.search(r"--budget (\S+)", pick).group(1)
        self.assertRegex(budget, r"^prepare-\d{4}-W\d{2}$")
        self.assertIn("--budget %s " % budget, label + " ")

    def test_the_budget_is_the_iso_year_and_week(self):
        week = subprocess.run(["date", "+%G-W%V"], capture_output=True, text=True).stdout.strip()
        self.hour()
        self.assertIn("--budget prepare-%s" % week, self.line("teach_label.py"))

    def test_the_tools_are_the_ones_that_were_built(self):
        self.hour()
        self.assertIn("--tool %s/podcast-transcribe" % self.bin, self.line("teach_transcribe.py"))
        self.assertIn("--tool %s/podcast-ads" % self.bin, self.line("teach_copies.py"))
        built = [c for c in self.called() if c.startswith("swift build") and "--product" in c]
        self.assertEqual([c.split()[-1] for c in built], ["podcast-transcribe", "podcast-ads"])

    def test_the_maps_are_written_with_the_built_podcast_ads_and_left_out_when_it_did_not_build(self):
        self.hour()
        self.assertIn("publish", self.line("teach_maps.py"))
        self.assertIn("--tool %s/podcast-ads" % self.bin, self.line("teach_maps.py"))
        open(self.calls, "w").close()
        self.hour(ADS_FAILS="1")
        self.assertNotIn("python3 teach_maps.py", self.first_words())
        self.assertIn("python3 teach_prepared.py publish", self.first_words())

    def test_the_audio_step_gets_the_days_and_the_gigabytes_and_they_can_be_changed(self):
        self.hour()
        self.assertTrue(self.line("teach_prepared.py publish").startswith("python3 teach_prepared.py publish "))
        for words in ("--keep-days 7", "--max-gb 10"):
            self.assertIn(words, self.line("teach_prepared.py publish"))
        self.assertIn("--own-gb 25", self.line("teach_collect.py"))
        self.assertNotIn("--max-gb", self.line("teach_collect.py"))
        open(self.calls, "w").close()
        self.hour(TEACH_PREPARE_KEEP_DAYS="3", TEACH_PREPARE_GB="5", TEACH_PREPARE_CAP="20",
                  TEACH_PREPARE_MOST="2", TEACH_PREPARE_OWN_GB="30")
        for words in ("--keep-days 3", "--max-gb 5"):
            self.assertIn(words, self.line("teach_prepared.py publish"))
        self.assertIn("--cap 20", self.line("teach_label.py"))
        self.assertIn("--reserve 1.00", self.line("teach_label.py"))
        self.assertIn("--unknown-cost 0.19", self.line("teach_label.py"))
        self.assertIn("--limit 2", self.line("teach_label.py"))
        self.assertIn("--own-gb 30", self.line("teach_collect.py"))
        self.assertNotIn("--max-gb", self.line("teach_collect.py"))

    def test_the_reserve_can_be_changed_and_the_pick_keeps_its_estimate(self):
        self.hour(TEACH_PREPARE_RESERVE="2.50", TEACH_PREPARE_ESTIMATE="0.30")
        self.assertIn("--reserve 2.50", self.line("teach_label.py"))
        self.assertIn("--unknown-cost 0.30", self.line("teach_label.py"))
        self.assertIn("--estimate 0.30", self.line("teach_prepare.py"))

    def test_a_failed_preflight_means_no_pick_no_download_no_marking_and_nothing_spent(self):
        for code in ("3", "2", "1"):
            open(self.calls, "w").close()
            done = self.hour(CODES="teach_prepared.py:ready=" + code)
            self.assertEqual(done.returncode, 1, code)
            self.assertEqual(self.first_words(), ["python3 teach_store.py hold", "python3 teach_prepared.py ready"], code)
            for tool in ("teach_prepare.py", "teach_collect.py", "teach_label.py", "swift"):
                self.assertNotIn(tool, " ".join(self.called()), code)
            self.assertIn("Nothing was picked or marked this run, so nothing was spent.", done.stdout)
            self.assertIn("Nothing was picked or marked this run", self.log())

    def test_the_preflight_is_the_first_step_and_gets_the_folder_the_days_and_the_gigabytes(self):
        self.hour(TEACH_PREPARE_KEEP_DAYS="3", TEACH_PREPARE_GB="5")
        self.assertEqual(self.first_words()[:4], ["python3 teach_store.py hold", "python3 teach_prepared.py ready",
                                                  "python3 teach_taps.py", "python3 teach_prepare.py"])
        ready = self.line("teach_prepared.py ready")
        for words in ("--folder", "--keep-days 3", "--max-gb 5"):
            self.assertIn(words, ready)

    def test_the_pick_and_the_marking_get_the_same_reserve(self):
        self.hour()
        self.assertIn("--reserve 1.00", self.line("teach_prepare.py"))
        self.assertIn("--reserve 1.00", self.line("teach_label.py"))
        open(self.calls, "w").close()
        self.hour(TEACH_PREPARE_RESERVE="3")
        self.assertIn("--reserve 3", self.line("teach_prepare.py"))
        self.assertIn("--reserve 3", self.line("teach_label.py"))

    def test_ahead_ads_are_written_after_the_audio_is_published_and_before_the_phone_is_told(self):
        self.hour()
        names = [w for w in self.first_words() if w.startswith("python3")]
        self.assertLess(names.index("python3 teach_prepared.py publish"), names.index("python3 teach_ahead.py write"))
        self.assertLess(names.index("python3 teach_ahead.py write"), names.index("python3 teach_publish.py"))
        self.assertLess(names.index("python3 teach_snap.py"), names.index("python3 teach_prepared.py publish"))
        self.assertLess(names.index("python3 teach_copies.py"), names.index("python3 teach_snap.py"))

    def test_an_hour_with_nothing_to_pick_still_finishes_earlier_work_and_is_not_an_error(self):
        done = self.hour(CODES="teach_prepare.py=3")
        self.assertEqual(done.returncode, 0, done.stdout)
        self.assertEqual(self.first_words(), self.ORDER)

    def test_an_hour_without_audio_skips_the_writing_down_and_the_marking_only(self):
        done = self.hour(CODES="teach_ahead.py:ready=3")
        self.assertEqual(done.returncode, 0, done.stdout)
        words = self.first_words()
        self.assertNotIn("python3 teach_transcribe.py", words)
        self.assertNotIn("python3 teach_label.py", words)
        self.assertEqual(words[-7:], ["python3 teach_copies.py", "python3 teach_snap.py",
                                      "python3 teach_prepared.py publish", "python3 teach_maps.py", "python3 teach_coming_publish.py",
                                      "python3 teach_ahead.py write",
                                      "python3 teach_publish.py"])

    def test_reading_the_taps_failing_never_stops_the_run(self):
        done = self.hour(FAIL="teach_taps.py")
        self.assertEqual(done.returncode, 1)
        self.assertEqual(self.first_words()[2:4], ["python3 teach_taps.py", "python3 teach_prepare.py"])
        self.assertIn("python3 teach_label.py", self.first_words())
        self.assertIn("What you tapped could not be read", done.stdout)

    def test_the_taps_are_read_before_the_pick_and_the_coming_list_is_closed_after_the_copies(self):
        self.hour()
        names = self.first_words()
        self.assertLess(names.index("python3 teach_taps.py"), names.index("python3 teach_label.py"))
        self.assertLess(names.index("python3 teach_prepare.py"), names.index("python3 teach_label.py"))
        self.assertLess(names.index("python3 teach_prepared.py publish"),
                        names.index("python3 teach_coming_publish.py"))
        self.assertLess(names.index("python3 teach_coming_publish.py"), names.index("python3 teach_ahead.py write"))

    def test_a_pick_that_fails_is_an_error_and_nothing_goes_on(self):
        done = self.hour(FAIL="teach_prepare.py")
        self.assertEqual(done.returncode, 1)
        self.assertEqual(len(self.called()), 4)  # the hold, the preflight, the taps, the pick
        self.assertIn("nothing was prepared", done.stdout)

    def test_a_failing_step_does_not_stop_the_others_so_every_other_episode_reaches_the_phone(self):
        for failing in ("teach_collect.py", "teach_transcribe.py", "teach_label.py", "teach_copies.py",
                        "teach_snap.py", "teach_prepared.py:publish", "teach_ahead.py:write", "teach_publish.py"):
            open(self.calls, "w").close()
            done = self.hour(FAIL=failing)
            self.assertEqual(done.returncode, 1, failing)
            self.assertEqual(self.first_words()[-5:], ["python3 teach_prepared.py publish", "python3 teach_maps.py", "python3 teach_coming_publish.py",
                                                       "python3 teach_ahead.py write",
                                                       "python3 teach_publish.py"], failing)
            self.assertIn("not every step worked", done.stdout, failing)

    def test_a_build_that_fails_leaves_out_only_the_step_that_needs_it(self):
        done = self.hour(TRANSCRIBER_FAILS="1")
        self.assertEqual(done.returncode, 1)
        words = self.first_words()
        self.assertNotIn("python3 teach_transcribe.py", words)
        self.assertIn("python3 teach_label.py", words)
        self.assertIn("python3 teach_copies.py", words)
        self.assertIn("podcast-transcribe did not build", done.stdout)
        open(self.calls, "w").close()
        done = self.hour(ADS_FAILS="1")
        self.assertEqual(done.returncode, 1)
        words = self.first_words()
        self.assertNotIn("python3 teach_copies.py", words)
        self.assertEqual(words[-4:], ["python3 teach_prepared.py publish", "python3 teach_coming_publish.py",
                                      "python3 teach_ahead.py write",
                                      "python3 teach_publish.py"])
        self.assertIn("python3 teach_snap.py", words)

    def test_the_weekly_cap_reached_and_a_stop_for_space_are_not_failures(self):
        done = self.hour(CODES="teach_label.py=5 teach_prepared.py:publish=3 teach_copies.py=3")
        self.assertEqual(done.returncode, 0, done.stdout)
        self.assertIn("cap of $35 is reached", done.stdout)
        self.assertEqual(self.first_words()[-1], "python3 teach_publish.py")

    def test_a_full_audio_folder_ends_non_zero_with_one_plain_sentence(self):
        done = self.hour(CODES="teach_collect.py=3")
        self.assertEqual(done.returncode, 1)
        self.assertIn("own episodes has reached its limit of 25 GB", done.stdout)
        self.assertIn("TEACH_PREPARE_OWN_GB", done.stdout)

    def test_a_publish_that_missed_icloud_is_said(self):
        done = self.hour(CODES="teach_publish.py=3")
        self.assertEqual(done.returncode, 1)
        self.assertIn("iCloud Drive did not work", done.stdout)

    def test_another_run_in_the_folder_ends_quietly_with_exit_0(self):
        done = self.hour(BUSY="1")
        self.assertEqual((done.returncode, len(self.called())), (0, 1))
        self.assertIn("Another teaching run is already working", done.stdout)

    def test_the_whole_hour_runs_under_the_folders_lock(self):
        env, folder = self.real_lock()
        done = self.hour(**env)
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        holds = [c for c in self.called() if " teach_store.py " in (c + " ")]
        self.assertEqual(len(holds), 1, holds)
        self.assertTrue(holds[0].startswith("python3 teach_store.py hold %s " % folder), holds[0])
        self.assertTrue(holds[0].endswith("teach-prepare.sh"), holds[0])
        during = [c for c in self.called() if c.startswith("lock-during")]
        self.assertEqual([c.split()[1] for c in during],
                         ["teach_prepared.py", "teach_taps.py", "teach_prepare.py", "teach_collect.py", "teach_ahead.py",
                          "teach_transcribe.py",
                          "teach_label.py", "teach_copies.py", "teach_snap.py", "teach_prepared.py",
                          "teach_maps.py", "teach_coming_publish.py", "teach_ahead.py", "teach_publish.py"])
        self.assertEqual({c.split()[2] for c in during}, {"3"}, during)
        free = subprocess.run([sys.executable, os.path.join(HERE, "teach_store.py"), "busy", folder])
        self.assertEqual(free.returncode, 0)

    def test_another_run_holding_the_real_lock_makes_the_hour_pass_quietly_before_any_step(self):
        env, folder = self.real_lock()
        with run_lock(folder):
            done = self.hour(**env)
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertIn("this run's episode preparing is skipped", done.stdout)
        self.assertNotIn("not every step worked", done.stdout)
        self.assertEqual([c.split()[1] for c in self.called()], ["teach_store.py"])
        self.assertIn("episode preparing is skipped", self.log())

    def test_it_does_not_skip_sundays(self):
        for day in ("1", "3", "7"):
            open(self.calls, "w").close()
            done = self.hour(FAKE_WEEKDAY=day)
            self.assertEqual(done.returncode, 0, day)
            self.assertEqual(self.first_words(), self.ORDER, day)

    def test_it_works_with_a_short_path_as_launchd_gives_it(self):
        later = os.path.join(self.home, ".local", "bin")
        os.makedirs(later)
        for name in ("swift", "podcast-teach", "caffeinate"):
            shutil.move(os.path.join(self.bin, name), os.path.join(later, name))
        short = os.path.join(self.root, "system")
        os.makedirs(short)
        shutil.copy(os.path.join(self.bin, "python3"), os.path.join(short, "python3"))
        done = self.hour(PATH="%s:/usr/bin:/bin:/usr/sbin:/sbin" % short)
        self.assertEqual(done.returncode, 0, done.stdout)
        self.assertIn("swift build -c release --product podcast-ads", self.called())

    def test_the_log_gets_a_heading_and_everything_said(self):
        self.hour()
        self.assertRegex(self.log(), r"=== \d{4}-\d\d-\d\d \d\d:\d\d episode preparing ===")
        self.assertIn("This run's episode preparing is done.", self.log())

    def test_only_the_pick_and_the_marking_know_about_money(self):
        self.hour()
        paid = [c for c in self.called() if "--cap" in c]
        self.assertEqual(len(paid), 2)
        self.assertTrue(all("--cap 35" in c for c in paid))

    def test_the_nightly_read_ahead_script_is_not_changed_by_any_of_this(self):
        done = self.run_script("teach-ahead.sh", FAKE_WEEKDAY="3")
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertIn("python3 teach_ahead.py pick", " ".join(self.called()))


class JobTests(Setup):
    NAME = "Install episode preparing.command"
    STOP = "Stop episode preparing.command"
    LABEL = "com.storyteller-lofi.podcast-prepare"
    OLD = "com.storyteller-lofi.podcast-read-ahead"

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
                        'if [ "$1" = print ]; then [ -n "$NIGHTLY_LOADED" ] && exit 0; exit 113; fi\n'
                        'if [ "$1" = bootstrap ]; then\n  echo x >> "$CALLS.boot"\n'
                        '  [ -n "$BOOT_FAILS" ] && [ "$(wc -l < "$CALLS.boot")" -le "$BOOT_FAILS" ] && exit 5\n'
                        'fi\nexit 0\n')
        self.program_in(self.bin, "id", "#!/bin/bash\necho 501\n")
        self.agents = os.path.join(self.home, "Library", "LaunchAgents")
        self.plist = os.path.join(self.agents, self.LABEL + ".plist")
        self.old_plist = os.path.join(self.agents, self.OLD + ".plist")

    def program_in(self, folder, name, text):
        path = os.path.join(folder, name)
        with open(path, "w") as f:
            f.write(text)
        os.chmod(path, 0o755)

    def run_file(self, name, answer="yes\n\n", folder=None, **more):
        env = {"HOME": self.home, "PATH": "%s:/usr/bin:/bin" % self.bin, "TMPDIR": os.path.join(self.root, "tmp"),
               "CALLS": self.calls, "LINT_FAILS": "", "BOOT_FAILS": "", "NIGHTLY_LOADED": ""}
        env.update(more)
        return subprocess.run(["bash", os.path.join(folder or HERE, name)], env=env, input=answer,
                              capture_output=True, text=True, timeout=60)

    def job(self):
        with open(self.plist, "rb") as f:
            return plistlib.load(f)

    def launchctl(self):
        return [c for c in self.called() if c.startswith("launchctl")]

    def test_the_job_file_runs_teach_prepare_every_20_minutes_and_nothing_else(self):
        done = self.run_file(self.NAME)
        self.assertEqual(done.returncode, 0, done.stdout)
        job = self.job()
        self.assertEqual(job["Label"], self.LABEL)
        self.assertEqual(job["ProgramArguments"], ["/bin/bash", os.path.join(HERE, "teach-prepare.sh")])
        # Every 20 minutes: minutes 5, 25 and 45 of every hour, and nothing else in each entry.
        self.assertEqual(job["StartCalendarInterval"], [{"Minute": 5}, {"Minute": 25}, {"Minute": 45}])
        logs = os.path.join(self.home, "Storyteller Lofi", "logs")
        self.assertEqual(job["StandardOutPath"], os.path.join(logs, "podcast-prepare-job.log"))
        self.assertEqual(job["StandardErrorPath"], job["StandardOutPath"])
        env = job["EnvironmentVariables"]
        self.assertEqual((env["HOME"], env["TEACH_PREPARE_KEEP_DAYS"], env["TEACH_PREPARE_GB"]),
                         (self.home, "7", "10"))
        for place in ("/usr/bin", "/opt/homebrew/bin", os.path.join(self.home, ".local", "bin"),
                      os.path.join(self.home, ".claude", "local")):
            self.assertIn(place, env["PATH"].split(":"))
        self.assertEqual(set(job), {"Label", "ProgramArguments", "StartCalendarInterval", "LowPriorityIO",
                                    "Nice", "EnvironmentVariables", "StandardOutPath", "StandardErrorPath"})

    def test_the_days_and_the_gigabytes_can_be_changed_and_must_be_whole_numbers(self):
        self.run_file(self.NAME, TEACH_PREPARE_KEEP_DAYS="3", TEACH_PREPARE_GB="5")
        env = self.job()["EnvironmentVariables"]
        self.assertEqual((env["TEACH_PREPARE_KEEP_DAYS"], env["TEACH_PREPARE_GB"]), ("3", "5"))
        os.remove(self.plist)
        for days, gb in (("x", "10"), ("7", "1.5"), ("0", "10"), ("7", "0")):
            done = self.run_file(self.NAME, TEACH_PREPARE_KEEP_DAYS=days, TEACH_PREPARE_GB=gb)
            self.assertEqual(done.returncode, 1, (days, gb))
            self.assertFalse(os.path.exists(self.plist))

    def test_it_says_in_plain_words_what_it_does_and_costs_before_it_asks_for_the_yes(self):
        done = self.run_file(self.NAME)
        words = done.stdout.split("Type yes")[0]
        for text in ("every 20 minutes", "$35 a week of Claude usage", "10 GB", "7 days", "awake and online",
                     "deletes the audio it downloaded itself", "replaces the nightly read-ahead",
                     "$0.19 an episode"):
            self.assertIn(text, words)
        self.assertIn("the oldest go", words)
        self.assertIn("keeps one dollar in reserve and marking stops at about 34 dollars", words)

    def test_the_words_follow_the_days_and_the_gigabytes_chosen(self):
        done = self.run_file(self.NAME, TEACH_PREPARE_KEEP_DAYS="14", TEACH_PREPARE_GB="20")
        words = done.stdout.split("Type yes")[0]
        self.assertIn("at most 20 GB of audio in iCloud for 14 days", words)
        self.assertNotIn("10 GB", words)

    def test_it_shows_the_free_icloud_space_when_macos_tells_it(self):
        self.program_in(self.bin, "brctl", '#!/bin/bash\necho "Quota: 12,345,678,901 bytes of quota remaining in paid account"\n')
        done = self.run_file(self.NAME)
        self.assertIn("iCloud has 12.3 GB free now", done.stdout.split("Type yes")[0])

    def test_it_says_nothing_about_free_space_when_brctl_is_missing_or_not_understood(self):
        self.assertNotIn("GB free now", self.run_file(self.NAME).stdout)
        os.remove(self.plist)
        self.program_in(self.bin, "brctl", "#!/bin/bash\necho nothing useful\n")
        self.assertNotIn("GB free now", self.run_file(self.NAME).stdout)

    def test_the_job_is_checked_and_replaced_not_added_and_never_loaded_by_a_test(self):
        self.run_file(self.NAME)
        self.assertIn("plutil -lint", " ".join(self.called()))
        self.assertEqual(self.launchctl(), ["launchctl print gui/501/" + self.OLD,
                                            "launchctl bootout gui/501/" + self.LABEL,
                                            "launchctl bootstrap gui/501 %s" % self.plist])
        self.assertEqual(os.listdir(os.path.join(self.root, "tmp")), [])

    def test_running_it_again_replaces_the_old_hourly_job_with_the_20_minute_one(self):
        os.makedirs(self.agents)
        with open(self.plist, "wb") as f:
            plistlib.dump({"Label": self.LABEL, "StartCalendarInterval": {"Minute": 5}}, f)
        done = self.run_file(self.NAME)
        self.assertEqual(done.returncode, 0, done.stdout)
        self.assertEqual(self.job()["StartCalendarInterval"], [{"Minute": 5}, {"Minute": 25}, {"Minute": 45}])
        self.assertEqual([c for c in self.launchctl() if "bootstrap" in c or "bootout gui/501/" + self.LABEL in c],
                         ["launchctl bootout gui/501/" + self.LABEL, "launchctl bootstrap gui/501 %s" % self.plist])
        self.assertEqual(os.listdir(self.agents), [self.LABEL + ".plist"])
        self.assertIn("every 20 minutes, at 5, 25 and 45 minutes past the hour", done.stdout)

    def test_anything_but_yes_changes_nothing_at_all(self):
        os.makedirs(self.agents)
        with open(self.old_plist, "w") as f:
            f.write("nightly")
        for answer in ("\n\n", "no\n\n", "y\n\n", "yes please\n\n"):
            done = self.run_file(self.NAME, answer=answer, NIGHTLY_LOADED="1")
            self.assertEqual(done.returncode, 0, answer)
            self.assertFalse(os.path.exists(self.plist), answer)
            self.assertEqual(self.launchctl(), [], answer)
            self.assertTrue(os.path.exists(self.old_plist), answer)
            self.assertIn("was not turned on", done.stdout)

    def test_a_loaded_nightly_read_ahead_is_turned_off_and_its_job_file_removed(self):
        os.makedirs(self.agents)
        with open(self.old_plist, "w") as f:
            f.write("nightly")
        done = self.run_file(self.NAME, NIGHTLY_LOADED="1")
        self.assertEqual(done.returncode, 0, done.stdout)
        self.assertEqual(self.launchctl()[:2], ["launchctl print gui/501/" + self.OLD,
                                                "launchctl bootout gui/501/" + self.OLD])
        self.assertFalse(os.path.exists(self.old_plist))
        self.assertTrue(os.path.exists(self.plist))
        self.assertIn("nightly read-ahead was on, and is turned off", done.stdout)

    def test_a_nightly_read_ahead_job_file_that_is_not_loaded_is_removed_too_and_not_booted_out(self):
        os.makedirs(self.agents)
        with open(self.old_plist, "w") as f:
            f.write("nightly")
        done = self.run_file(self.NAME)
        self.assertNotIn("launchctl bootout gui/501/" + self.OLD, self.launchctl())
        self.assertFalse(os.path.exists(self.old_plist))
        self.assertIn("job file was removed", done.stdout)

    def test_no_nightly_job_file_and_nothing_loaded_changes_nothing_about_it(self):
        done = self.run_file(self.NAME)
        self.assertNotIn("job file was removed", done.stdout)
        self.assertNotIn("launchctl bootout gui/501/" + self.OLD, self.launchctl())

    def test_a_missing_claude_or_swift_stops_it_before_anything_is_changed(self):
        for missing, words in (("claude", "Install Claude Code"), ("swift", "Install Xcode 26")):
            os.remove(os.path.join(self.later, missing))
            done = self.run_file(self.NAME, NIGHTLY_LOADED="1")
            self.assertEqual(done.returncode, 1, missing)
            self.assertIn(words, done.stdout)
            self.assertFalse(os.path.exists(self.plist), missing)
            self.assertEqual(self.launchctl(), [], missing)
            self.program_in(self.later, missing, "#!/bin/bash\nexit 0\n")

    def test_a_job_file_that_fails_the_check_is_never_put_in_place_and_nothing_is_unloaded(self):
        done = self.run_file(self.NAME, LINT_FAILS="1", NIGHTLY_LOADED="1")
        self.assertEqual(done.returncode, 1)
        self.assertFalse(os.path.exists(self.plist))
        self.assertEqual(self.launchctl(), [])
        self.assertEqual(os.listdir(os.path.join(self.root, "tmp")), [])

    def test_a_folder_name_with_xml_characters_is_escaped(self):
        odd = os.path.join(self.root, "a&b <c>")
        os.makedirs(odd)
        for name in (self.NAME, "teach-prepare.sh"):
            shutil.copy(os.path.join(HERE, name), os.path.join(odd, name))
        done = self.run_file(self.NAME, folder=odd)
        self.assertEqual(done.returncode, 0, done.stdout)
        self.assertEqual(self.job()["ProgramArguments"], ["/bin/bash", os.path.join(odd, "teach-prepare.sh")])

    def test_a_start_that_fails_right_after_bootout_is_tried_once_more_and_twice_is_said(self):
        done = self.run_file(self.NAME, BOOT_FAILS="1")
        self.assertEqual(done.returncode, 0, done.stdout)
        self.assertEqual(len([c for c in self.launchctl() if c.startswith("launchctl bootstrap")]), 2)
        done = self.run_file(self.NAME, BOOT_FAILS="9")
        self.assertEqual(done.returncode, 1)
        self.assertIn("Could not start the job", done.stdout)
        self.assertIn("removed again", done.stdout)
        self.assertFalse(os.path.exists(self.plist))

    def test_the_stopper_turns_the_job_off_and_keeps_everything_else(self):
        self.run_file(self.NAME)
        open(self.calls, "w").close()
        done = self.run_file(self.STOP, answer="\n")
        self.assertEqual(done.returncode, 0, done.stdout)
        self.assertFalse(os.path.exists(self.plist))
        self.assertEqual(self.launchctl(), ["launchctl bootout gui/501/" + self.LABEL])
        self.assertIn("Episode preparing is off", done.stdout + done.stderr)
        self.assertEqual(self.cleaning(), [])

    def cleaning(self):
        return [c for c in self.called() if c.startswith("python3 teach_prepared.py")]

    def test_the_stopper_asks_and_on_yes_cleans_with_zero_keep_days_through_the_same_tool(self):
        done = self.run_file(self.STOP, answer="yes\n\n")
        self.assertEqual(done.returncode, 0, done.stdout)
        folder = os.path.join(self.home, "Storyteller Lofi", "PodcastTeaching")
        self.assertEqual(self.cleaning(), ["python3 teach_prepared.py clean --folder %s --keep-days 0 --all-parts" % folder])
        self.assertEqual(self.launchctl(), ["launchctl bootout gui/501/" + self.LABEL])
        self.assertIn("That removed the prepared episodes from iCloud", done.stdout)

    def test_the_stopper_says_what_happened_when_the_cleaning_did_not_work(self):
        for code, words in (("3", "Nothing was removed"), ("1", "Not everything could be removed"),
                            ("2", "Not everything could be removed")):
            done = self.run_file(self.STOP, answer="yes\n\n", CODES="teach_prepared.py=" + code)
            self.assertEqual(done.returncode, 0, code)
            self.assertIn(words, done.stdout, code)
            self.assertNotIn("That removed", done.stdout, code)
            self.assertIn("stay", done.stdout, code)

    def test_the_stopper_keeps_the_copies_on_any_other_answer_and_says_they_stay(self):
        for answer in ("\n\n", "no\n\n", "y\n\n", "yes please\n\n"):
            open(self.calls, "w").close()
            done = self.run_file(self.STOP, answer=answer)
            self.assertEqual(done.returncode, 0, answer)
            self.assertEqual(self.cleaning(), [], answer)
            self.assertIn("stay", done.stdout)
            self.assertIn("take space until the job runs again or you remove them by hand", done.stdout)
            self.assertEqual(self.launchctl(), ["launchctl bootout gui/501/" + self.LABEL], answer)

    def test_the_nightly_installer_and_stopper_still_work_on_their_own_job(self):
        done = self.run_file("Install nightly read-ahead.command")
        self.assertEqual(done.returncode, 0, done.stdout)
        self.assertTrue(os.path.exists(self.old_plist))
        self.assertFalse(os.path.exists(self.plist))


if __name__ == "__main__":
    unittest.main()
