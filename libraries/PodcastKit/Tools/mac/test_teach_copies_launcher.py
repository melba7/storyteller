"""Tests for "Check ads with a second download.command": it is run with stand-in python3, swift and
caffeinate programs on a temporary PATH and a temporary home, once for every exit code of the two
tools it starts (teach_copies.py: 0, 1, 2, 3 and another; teach_snap.py, which it starts through the
folder lock: 0, 2, 3 for another run holding the lock, and another), to check the order of the
steps, what it says and its own exit code. No Mac, no network, no Swift.
Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import os
import re
import shutil
import stat
import subprocess
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
NAME = "Check ads with a second download.command"

PYTHON = """#!/bin/bash
# stand-in for python3: records the call and ends with the code the test asks for
[ "$1" = "-u" ] && shift
script="$(basename "$1")"
shift
echo "python3 $script $*" >> "$CALLS"
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
echo "$script: ran"
exit 0
"""
SWIFT = """#!/bin/bash
echo "swift $*" >> "$CALLS"
case "$*" in *--show-bin-path*) echo "$BIN"; exit 0 ;; esac
[ -n "$BUILD_FAILS" ] && { echo "error: the build broke"; exit 1; }
exit 0
"""
CAFFEINATE = '#!/bin/bash\necho "caffeinate $*" >> "$CALLS"\nshift\nexec "$@"\n'


class Launcher(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.root, ignore_errors=True)
        self.bin = os.path.join(self.root, "bin")
        self.home = os.path.join(self.root, "home")
        self.calls = os.path.join(self.root, "calls.log")
        for folder in (self.bin, self.home):
            os.makedirs(folder)
        for name, text in (("python3", PYTHON), ("swift", SWIFT), ("caffeinate", CAFFEINATE)):
            self.program(name, text)
        open(self.calls, "w").close()
        self.folder = os.path.join(self.home, "Storyteller Lofi", "PodcastTeaching")

    def program(self, name, text):
        path = os.path.join(self.bin, name)
        with open(path, "w") as handle:
            handle.write(text)
        os.chmod(path, 0o755)

    def run_launcher(self, folder=HERE, **more):
        env = {"HOME": self.home, "PATH": "%s:/usr/bin:/bin" % self.bin, "CALLS": self.calls,
               "BIN": self.bin, "CODES": "", "BUSY": "", "BUILD_FAILS": ""}
        env.update(more)
        return subprocess.run(["bash", os.path.join(folder, NAME)], env=env, capture_output=True,
                              text=True, timeout=120, stdin=subprocess.DEVNULL)

    def called(self):
        with open(self.calls) as handle:
            return [line.strip() for line in handle if line.strip()]

    def python_calls(self):
        """The python3 calls, with the folder and this folder's path taken out."""
        return [line.replace(self.folder, "FOLDER").replace(HERE + "/", "")
                for line in self.called() if line.startswith("python3")]

    def log(self):
        with open(os.path.join(self.home, "Storyteller Lofi", "logs", "podcast-teaching.log")) as handle:
            return handle.read()


class FilesTests(unittest.TestCase):
    def test_it_is_a_runnable_bash_file_that_parses_and_keeps_to_bash_3_2(self):
        path = os.path.join(HERE, NAME)
        self.assertTrue(os.stat(path).st_mode & stat.S_IXUSR)
        with open(path, encoding="utf-8") as handle:
            text = handle.read()
        self.assertEqual(text.splitlines()[0], "#!/bin/bash")
        done = subprocess.run(["bash", "-n", path], capture_output=True, text=True)
        self.assertEqual(done.returncode, 0, done.stderr)
        code = "".join(line for line in text.splitlines(True) if not line.lstrip().startswith("#"))
        for pattern in (r"declare\s+-A", r"\bmapfile\b", r"\breadarray\b", r"\$\{[A-Za-z_]+(,,|\^\^)\}",
                        r"\$\(<<", r"&>>?", r"\|&", r"\bcoproc\b"):
            self.assertIsNone(re.search(pattern, code), pattern)
        self.assertLess(len(text.splitlines()), 300)


class StepsTests(Launcher):
    def test_the_tool_is_built_then_the_copies_are_made_then_the_labels_are_snapped(self):
        done = self.run_launcher()
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertEqual([c for c in self.called() if c.startswith("swift")],
                         ["swift build -c release --product podcast-ads", "swift build -c release --show-bin-path"])
        self.assertEqual(self.python_calls(), [
            "python3 teach_copies.py --folder FOLDER --tool %s/podcast-ads" % self.bin,
            "python3 teach_store.py hold FOLDER python3 -u teach_snap.py --folder FOLDER",
            "python3 teach_snap.py --folder FOLDER"])
        self.assertIn("Done.", done.stdout)
        self.assertIn("Teach the phone again", done.stdout)

    def test_the_copies_run_keeps_the_mac_awake(self):
        self.run_launcher()
        calls = self.called()
        first = [i for i, c in enumerate(calls) if c.startswith("caffeinate -i python3 -u")]
        self.assertEqual(len(first), 1)
        self.assertIn("teach_copies.py", calls[first[0]])

    def test_the_labels_are_snapped_under_the_folders_lock(self):
        self.run_launcher()
        hold = [c for c in self.python_calls() if "teach_store.py hold" in c]
        self.assertEqual(len(hold), 1)
        self.assertLess(self.python_calls().index(hold[0]), self.python_calls().index(
            "python3 teach_snap.py --folder FOLDER"))

    def test_everything_it_says_is_added_to_the_log_with_a_heading(self):
        self.run_launcher()
        self.assertRegex(self.log(), r"=== \d{4}-\d\d-\d\d \d\d:\d\d second downloads ===")
        self.assertIn("teach_copies.py: ran", self.log())
        self.assertIn("teach_snap.py: ran", self.log())


class CopiesExitCodeTests(Launcher):
    def test_0_goes_on_to_the_snapping_and_ends_with_0(self):
        done = self.run_launcher(CODES="teach_copies.py=0")
        self.assertEqual(done.returncode, 0)
        self.assertIn("teach_snap.py", " ".join(self.python_calls()))

    def test_3_the_limit_is_not_a_failure_the_snapping_still_runs_and_it_says_to_run_it_again(self):
        done = self.run_launcher(CODES="teach_copies.py=3")
        self.assertEqual(done.returncode, 3, done.stdout)
        self.assertIn("teach_snap.py", " ".join(self.python_calls()))
        self.assertIn("limit", done.stdout)
        self.assertIn("double-click this again", done.stdout.lower())
        self.assertNotIn("did not work", done.stdout)

    def test_1_downloads_failing_in_a_row_stop_it_before_the_snapping(self):
        done = self.run_launcher(CODES="teach_copies.py=1")
        self.assertEqual(done.returncode, 1)
        self.assertIn("in a row failed", done.stdout)
        self.assertNotIn("teach_snap.py", " ".join(self.python_calls()))

    def test_2_something_not_set_up_or_another_run_stops_it_before_the_snapping(self):
        done = self.run_launcher(CODES="teach_copies.py=2")
        self.assertEqual(done.returncode, 2)
        self.assertIn("not set up", done.stdout)
        self.assertIn("another run is working", done.stdout)
        self.assertNotIn("teach_snap.py", " ".join(self.python_calls()))

    def test_any_other_code_is_a_failure_and_stops_it_before_the_snapping(self):
        for code in ("4", "130", "137"):
            open(self.calls, "w").close()
            done = self.run_launcher(CODES="teach_copies.py=" + code)
            self.assertEqual(done.returncode, 1, code)
            self.assertIn("did not work", done.stdout, code)
            self.assertNotIn("teach_snap.py", " ".join(self.python_calls()), code)


class SnapExitCodeTests(Launcher):
    def test_0_is_done(self):
        done = self.run_launcher(CODES="teach_snap.py=0")
        self.assertEqual(done.returncode, 0)
        self.assertIn("labels-snapped", done.stdout)
        self.assertIn("Claude's own labels are unchanged", done.stdout)

    def test_2_labels_that_cannot_be_snapped_say_to_mark_the_ads_first(self):
        done = self.run_launcher(CODES="teach_snap.py=2")
        self.assertEqual(done.returncode, 2)
        self.assertIn("could not be snapped", done.stdout)
        self.assertIn("Mark ads", done.stdout)

    def test_3_another_run_holding_the_lock_says_so_and_nothing_was_written(self):
        # teach_store.py hold ends with 3 when another run holds the lock, without running the snapping.
        done = self.run_launcher(BUSY="1")
        self.assertEqual(done.returncode, 2)
        self.assertIn("Another teaching run", done.stdout)
        self.assertIn("were not written", done.stdout)
        self.assertNotIn("python3 teach_snap.py", self.called())

    def test_a_snapping_that_fails_otherwise_says_so(self):
        done = self.run_launcher(CODES="teach_snap.py=1")
        self.assertEqual(done.returncode, 1)
        self.assertIn("did not work", done.stdout)

    def test_a_limit_stop_and_a_snapping_that_failed_ends_with_the_failure(self):
        done = self.run_launcher(CODES="teach_copies.py=3 teach_snap.py=1")
        self.assertEqual(done.returncode, 1)


class SetupTests(Launcher):
    def test_a_build_that_fails_stops_it_before_any_python_runs(self):
        done = self.run_launcher(BUILD_FAILS="1")
        self.assertEqual(done.returncode, 1)
        self.assertIn("did not build", done.stdout)
        self.assertEqual(self.python_calls(), [])

    @unittest.skipIf(shutil.which("swift", path="/usr/bin:/bin"), "a real swift is installed")
    def test_without_swift_it_says_so_before_anything_runs(self):
        os.remove(os.path.join(self.bin, "swift"))
        done = self.run_launcher()
        self.assertEqual(done.returncode, 1)
        self.assertIn("swift is missing", done.stdout)
        self.assertEqual(self.python_calls(), [])

    def test_without_the_package_it_says_so(self):
        # Two folders up from here is not PodcastKit, and there is no testflight-build copy either.
        odd = os.path.join(self.root, "odd", "a", "b")
        os.makedirs(odd)
        shutil.copy(os.path.join(HERE, NAME), os.path.join(odd, NAME))
        done = self.run_launcher(folder=odd)
        self.assertEqual(done.returncode, 1)
        self.assertIn("Could not find PodcastKit", done.stdout)
        self.assertEqual(self.python_calls(), [])


if __name__ == "__main__":
    unittest.main()
