"""Tests for round-z.sh, the one-shot script of round Z, and for the switch that lets it install
the two jobs with nobody at the keyboard (TEACH_INSTALL_YES=1). The script is copied into a
stand-in clone in a temporary HOME and run with stand-in python3, swift, podcast-teach, launchctl
and plutil programs; the lock is the real one of teach_store.py and the copying is the real tar.
No Mac, no Claude, nothing paid.
Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import json
import os
import shutil
import subprocess
import sys
import threading
import time

import test_teach_shell as shell
from teach_store import run_lock

HERE = shell.HERE
PREPARE = "Install episode preparing.command"
NIGHTLY = "Install nightly teaching.command"
SCORE = "Score the ad skipping.command"

# Says in $LOCKS whether the teaching folder's lock is held by somebody (3) or free (0).
PROBE = ('echo "%s $(env -u TEACH_LOCK_HELD "$REAL_PYTHON" "$REAL_STORE" busy "$PROBED" > /dev/null; echo $?)"'
         ' >> "$LOCKS"')

# python3: the lock tool and the summary writer are the real ones, every other tool is recorded.
PYTHON = """#!/bin/bash
[ "$1" = "-u" ] && shift
script="$(basename "$1")"
case "$script" in teach_store.py|-) exec "$REAL_PYTHON" "$@" ;; esac
shift
echo "python3 $script $*" >> "$CALLS"
""" + PROBE % "$script" + """
case " $FAIL " in *" $script:$1 "*) echo "$script $1: pretending to fail"; exit 7 ;; esac
exit 0
"""

# tar: the real one, after saying whether the lock is held while the tools are packed.
TAR = '#!/bin/bash\ncase "$*" in *-cf*) ' + PROBE % "tar" + ' ;; esac\nexec "$REAL_TAR" "$@"\n'


class RoundSetup(shell.Setup):
    def setUp(self):
        super().setUp()
        self.lofi = os.path.join(self.home, "Storyteller Lofi")
        self.source = os.path.join(self.lofi, "testflight-build", "libraries", "PodcastKit")
        self.copy = os.path.join(self.lofi, "podcast-teaching-tools", "storyteller", "libraries", "PodcastKit")
        self.folder = os.path.join(self.lofi, "PodcastTeaching")
        self.locks = os.path.join(self.root, "locks.log")
        mac = os.path.join(self.source, "Tools", "mac")
        os.makedirs(mac)
        for name in ("round-z.sh", "teach_store.py", PREPARE, NIGHTLY, SCORE, "teach-prepare.sh", "teach-nightly.sh"):
            shutil.copy(os.path.join(HERE, name), mac)
        self.write(os.path.join(self.source, "Package.swift"), "// new\n")
        self.write(os.path.join(self.source, ".build", "release", "junk"), "the clone's build\n")
        self.write(os.path.join(self.source, "Tools", ".build", "junk"), "a deeper build\n")
        self.program("python3", PYTHON)
        self.program("tar", TAR)
        self.program("plutil", '#!/bin/bash\necho "plutil $*" >> "$CALLS"\nexit 0\n')
        # launchctl says whether the lock is held when it stops a job (bootout).
        self.program("launchctl", '#!/bin/bash\necho "launchctl $*" >> "$CALLS"\n'
                     'case "$1" in print) exit 1 ;; bootout) ' + PROBE % "bootout" + ' ;; esac\nexit 0\n')
        self.program("id", "#!/bin/bash\necho 501\n")
        later = os.path.join(self.home, ".local", "bin")
        os.makedirs(later)
        for name in ("claude", "swift"):
            shutil.copy(os.path.join(self.bin, "id"), os.path.join(later, name))

    def write(self, path, text):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w") as f:
            f.write(text)

    def env(self, **more):
        env = {"HOME": self.home, "PATH": "%s:/usr/bin:/bin" % self.bin, "TMPDIR": os.path.join(self.root, "tmp"),
               "CALLS": self.calls, "LOCKS": self.locks, "BIN": self.bin, "FAIL": "", "NOOP": "", "BUILD_FAILS": "",
               "TEACH_CODES": "", "REAL_PYTHON": sys.executable, "REAL_TAR": shutil.which("tar"),
               "REAL_STORE": os.path.join(HERE, "teach_store.py"), "PROBED": self.folder,
               "ROUND_Z_WAIT_SECONDS": "1", "ROUND_Z_WAIT_TRIES": "3"}
        env.update(more)
        return env

    def round(self, **more):
        return subprocess.run(["bash", os.path.join(self.source, "Tools", "mac", "round-z.sh")], env=self.env(**more),
                              capture_output=True, text=True, timeout=120, stdin=subprocess.DEVNULL)

    def summary(self):
        with open(os.path.join(self.lofi, "logs", "round-z-summary.json")) as f:
            return json.load(f)

    def tools(self):
        """The calls of the tools, without the folder and without the installers' checks."""
        return [line.replace(self.folder, "F").replace(self.bin, "BIN") for line in self.called()
                if not line.startswith(("plutil", "launchctl print", "launchctl bootout"))]

    def locked(self):
        with open(self.locks) as f:
            return dict(line.split() for line in f if line.strip())


class InstallerSwitchTests(RoundSetup):
    def install(self, name, **more):
        return subprocess.run(["bash", os.path.join(HERE, name)], env=self.env(**more), capture_output=True,
                              text=True, timeout=60, stdin=subprocess.DEVNULL)

    def plist(self, label):
        return os.path.join(self.home, "Library", "LaunchAgents", "com.storyteller-lofi.%s.plist" % label)

    def test_the_switch_installs_each_job_with_nothing_typed(self):
        for name, label in ((PREPARE, "podcast-prepare"), (NIGHTLY, "podcast-nightly-teaching")):
            done = self.install(name, TEACH_INSTALL_YES="1")
            self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
            self.assertTrue(os.path.exists(self.plist(label)), name)
            self.assertIn("launchctl bootstrap gui/501 " + self.plist(label), self.called())
            self.assertIn("TEACH_INSTALL_YES", done.stdout)
            self.assertNotIn("Type yes", done.stdout)

    def test_without_the_switch_or_with_another_value_nothing_is_installed(self):
        for name, label in ((PREPARE, "podcast-prepare"), (NIGHTLY, "podcast-nightly-teaching")):
            for more in ({}, {"TEACH_INSTALL_YES": ""}, {"TEACH_INSTALL_YES": "yes"}, {"TEACH_INSTALL_YES": "0"}):
                done = self.install(name, **more)
                self.assertEqual(done.returncode, 0, done.stdout)
                self.assertFalse(os.path.exists(self.plist(label)), (name, more))
                self.assertIn("was not turned on", done.stdout)


class RoundTests(RoundSetup):
    ORDER = ["launchctl bootstrap gui/501 %s", "launchctl bootstrap gui/501 %s",
             "swift build -c release --product podcast-teach", "swift build -c release --show-bin-path",
             "podcast-teach score F --stream",
             "python3 teach_second_look.py test F --cap 5 --yes",
             "python3 teach_playbook.py build F --cap 15 --yes",
             "swift build -c release --product podcast-teach", "swift build -c release --show-bin-path",
             "podcast-teach score F --dump F/shelf-dump.json",
             "python3 teach_playbook.py replay F --dump F/shelf-dump.json",
             "swift build -c release --product podcast-transcribe",
             "swift build -c release --product podcast-teach", "swift build -c release --show-bin-path",
             "podcast-teach score F --labels labels-snapped --stream --week",
             "python3 teach_end_score.py --folder F",
             "swift build -c release --show-bin-path",
             "python3 teach_words.py --folder F --tool BIN/podcast-transcribe --no-lock",
             "python3 teach_end_score.py --folder F --switch-on-pass"]

    def order(self):
        agents = os.path.join(self.home, "Library", "LaunchAgents")
        jobs = [os.path.join(agents, "com.storyteller-lofi.%s.plist" % label)
                for label in ("podcast-prepare", "podcast-nightly-teaching")]
        return [self.ORDER[0] % jobs[0], self.ORDER[1] % jobs[1]] + self.ORDER[2:]

    def test_the_steps_run_in_order_and_the_run_ends_with_0(self):
        done = self.round()
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertEqual(self.tools(), self.order())
        headings = [line for line in done.stdout.splitlines() if line.startswith("=== ")]
        self.assertEqual([h.split(".")[0] for h in headings[1:]],
                         ["=== %d" % n for n in range(1, 9)] + ["=== Summary ==="])
        # The long step is the last one, after the maps.
        self.assertIn("8. Word-exact ends", headings[-2])
        self.assertIn("Every step worked.", done.stdout)

    def test_the_tools_copy_is_updated_without_build_folders_and_keeps_its_own(self):
        self.write(os.path.join(self.copy, ".build", "release", "mine"), "the copy's build\n")
        self.write(os.path.join(self.copy, "Package.swift"), "// old\n")
        self.write(os.path.join(self.copy, "Tools", "mac", "only-here.txt"), "kept\n")
        done = self.round()
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        with open(os.path.join(self.copy, "Package.swift")) as f:
            self.assertEqual(f.read(), "// new\n")
        self.assertEqual(os.listdir(os.path.join(self.copy, ".build", "release")), ["mine"])
        self.assertFalse(os.path.exists(os.path.join(self.copy, "Tools", ".build")))
        self.assertTrue(os.path.exists(os.path.join(self.copy, "Tools", "mac", "only-here.txt")))
        self.assertTrue(os.access(os.path.join(self.copy, "Tools", "mac", SCORE), os.X_OK))

    def test_the_jobs_are_installed_from_the_tools_copy(self):
        self.round()
        with open(os.path.join(self.home, "Library", "LaunchAgents", "com.storyteller-lofi.podcast-prepare.plist")) as f:
            self.assertIn(os.path.join(self.copy, "Tools", "mac", "teach-prepare.sh"), f.read())

    def test_the_lock_is_held_for_the_copy_and_every_tool_and_free_afterwards(self):
        done = self.round()
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        # The rewrite of the shelf's words (hours long, and only side files of old episodes) runs
        # without the lock, so episode preparing goes on meanwhile.
        # The installers hold it too, so stopping the old job never ends a preparing run half way.
        self.assertEqual(self.locked(), {"tar": "3", "bootout": "3", "teach_second_look.py": "3",
                                         "teach_playbook.py": "3", "teach_end_score.py": "3",
                                         "teach_words.py": "0"})
        boots = [line for line in self.called() if line.startswith("launchctl bootout")]
        self.assertEqual(len(boots), 2)
        with run_lock(self.folder):
            pass

    def test_a_lock_held_by_another_run_is_waited_for(self):
        ready, go = threading.Event(), threading.Event()

        def other_run():
            with run_lock(self.folder):
                ready.set()
                go.wait(30)

        thread = threading.Thread(target=other_run)
        thread.start()
        ready.wait(10)
        threading.Timer(1.5, go.set).start()
        began = time.time()
        done = self.round(ROUND_Z_WAIT_TRIES="30")
        thread.join()
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertGreaterEqual(time.time() - began, 1.4)
        self.assertIn("Another teaching run is working in the teaching folder. Waiting for it", done.stdout)
        self.assertEqual(self.locked()["tar"], "3")
        self.assertTrue(os.path.exists(os.path.join(self.copy, "Package.swift")))

    def test_a_lock_that_never_comes_free_fails_the_step_and_copies_nothing(self):
        self.write(os.path.join(self.copy, "Package.swift"), "// old\n")
        with run_lock(self.folder):
            done = self.round(ROUND_Z_WAIT_SECONDS="0", ROUND_Z_WAIT_TRIES="2")
        self.assertEqual(done.returncode, 1)
        with open(os.path.join(self.copy, "Package.swift")) as f:
            self.assertEqual(f.read(), "// old\n")
        self.assertIn("still working after 2 checks", done.stdout)
        first = self.summary()["steps"][0]
        self.assertEqual((first["step"], first["code"]), ("Update the Mac's tools", 3))
        self.assertNotIn("teach_second_look.py", " ".join(self.called()))

    def test_when_the_tools_copy_fails_the_jobs_are_not_installed_and_the_rest_still_runs(self):
        # The packing stops half way, so the tools copy may be half new and half old.
        self.program("tar", '#!/bin/bash\ncase "$*" in *-cf*) echo "tar: the disk is full" >&2; exit 1 ;; esac\n'
                     'exec "$REAL_TAR" "$@"\n')
        os.makedirs(os.path.join(self.copy, "Tools", "mac"))
        done = self.round()
        self.assertEqual(done.returncode, 1)
        self.assertNotIn("launchctl", " ".join(self.called()))
        self.assertFalse(os.path.exists(os.path.join(self.home, "Library", "LaunchAgents")))
        self.assertEqual(done.stdout.count("so the two jobs are not installed again"), 1)
        self.assertNotIn("No commands were given", done.stdout.split("=== 3.")[0])
        steps = [step["step"] for step in self.summary()["steps"]]
        self.assertEqual(steps[:2], ["Update the Mac's tools", "Score the ad skipping"])
        self.assertNotIn("Install episode preparing", steps)
        self.assertIn("python3 teach_second_look.py test F --cap 5 --yes", self.tools())
        headings = [line for line in done.stdout.splitlines() if line.startswith("=== ")]
        self.assertEqual(len(headings), 10)

    def test_a_failed_step_says_its_code_and_the_next_ones_still_run(self):
        done = self.round(FAIL="teach_second_look.py:test teach_playbook.py:build", TEACH_CODES="score=137")
        self.assertEqual(done.returncode, 1)
        self.assertEqual(self.tools(), self.order())
        self.assertIn("Claude's second look test ended with exit code 7. The steps after it still run.", done.stdout)
        self.assertIn("exit code 137", done.stdout)
        codes = dict((s["step"], s["code"]) for s in self.summary()["steps"])
        self.assertEqual(codes["Claude's second look test"], 7)
        self.assertEqual(codes["Build the show playbook"], 7)
        self.assertEqual(codes["Score the ad skipping"], 1)
        self.assertEqual(codes["Score the shelf for the replay"], 137)
        self.assertEqual(codes["Replay the playbook on the shelf"], 0)
        self.assertIn("failed with exit code 7: Claude's second look test", done.stdout)
        self.assertIn("worked: Replay the playbook on the shelf", done.stdout)

    def test_the_summary_file_has_each_step_with_its_code_and_seconds(self):
        self.round()
        summary = self.summary()
        self.assertEqual([s["step"] for s in summary["steps"]],
                         ["Update the Mac's tools", "Install episode preparing", "Install nightly teaching",
                          "Score the ad skipping", "Claude's second look test", "Build the show playbook",
                          "Build the scoring tool", "Score the shelf for the replay",
                          "Replay the playbook on the shelf", "Build the transcriber",
                          "Build the scoring tool again", "Score the week-before sounds row",
                          "Measure the ends before the rewrite",
                          "Write down the words of the shelf episodes again",
                          "Measure the ends again and switch on if the bar passes"])
        for step in summary["steps"]:
            self.assertEqual(set(step), {"step", "code", "seconds"})
            self.assertEqual(step["code"], 0)
            self.assertIsInstance(step["seconds"], int)
        self.assertEqual(summary["failed"], 0)
        self.assertLessEqual(summary["startedAt"], summary["endedAt"])

    def test_what_the_tools_print_is_in_the_steps_log(self):
        self.round(FAIL="teach_second_look.py:test")
        with open(os.path.join(self.lofi, "logs", "round-z-steps.log")) as f:
            log = f.read()
        self.assertIn("teach_second_look.py test: pretending to fail", log)
        self.assertIn("=== 7. Maps for the copies already prepared ===", log)

    def test_nothing_waits_for_typed_input(self):
        # Standard input is a pipe that nobody writes to and nobody closes: a step that read from
        # it would wait for ever, and the timeout would fail the test.
        with open(os.path.join(self.root, "out.txt"), "w") as out:
            run = subprocess.Popen(["bash", os.path.join(self.source, "Tools", "mac", "round-z.sh")], env=self.env(),
                                   stdin=subprocess.PIPE, stdout=out, stderr=subprocess.STDOUT)
            try:
                self.assertEqual(run.wait(timeout=120), 0)
            finally:
                run.kill()
                run.stdin.close()
        self.assertEqual(self.tools(), self.order())

    def test_it_is_runnable_bash_3_2_with_no_model_names(self):
        path = os.path.join(HERE, "round-z.sh")
        self.assertTrue(os.access(path, os.X_OK))
        with open(path, encoding="utf-8") as f:
            text = f.read()
        self.assertEqual(text.splitlines()[0], "#!/bin/bash")
        for word in ("declare -A", "mapfile", "readarray", "&>", "|&", "coproc", "set -x",
                     "opus", "sonnet", "haiku", "--model"):
            self.assertNotIn(word, text)
