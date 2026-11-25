"""Tests for "Write down and mark together": the loop that writes down a few episodes, has Claude mark
them, and goes on, so the marking starts within minutes. It runs with the stand-in programs of
test_teach_night_launchers.py on a temporary PATH and home; the stand-in transcriber writes one
transcript file for each pending episode, up to the --limit it is given. No Mac, no network, no Claude.
Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import os
import re
import stat
import subprocess
import unittest

from test_teach_night_launchers import HERE, Setup

NAME = "Write down and mark together.command"
# Wraps the base stand-in python3: answers "busy" the first BUSY_TIMES times it is asked and free after
# that, and lets the stand-in transcriber write as many transcripts as are pending (a count kept in
# $PENDING_FILE), at most its --limit.
PYTHON_TOGETHER = '''#!/bin/bash
ARGS=("$@")
[ "$1" = "-u" ] && shift
script="$(basename "$1")"
if [ "$script" = teach_store.py ] && [ "$2" = busy ]; then
  count="$(cat "$CALLS.busy" 2> /dev/null || echo 0)"
  count=$((count + 1))
  echo "$count" > "$CALLS.busy"
  if [ "$count" -le "${BUSY_TIMES:-0}" ]; then
    echo "python3 teach_store.py busy $3" >> "$CALLS"
    exit 3
  fi
fi
"$BIN/python3-base" "${ARGS[@]}"
code=$?
if [ "$script" = teach_transcribe.py ] && [ "$code" = 0 ]; then
  limit=1000; folder=""
  while [ $# -gt 0 ]; do
    [ "$1" = "--limit" ] && limit="$2"
    [ "$1" = "--folder" ] && folder="$2"
    shift
  done
  pending="$(cat "$PENDING_FILE" 2> /dev/null || echo 0)"
  [ "$pending" -gt "$limit" ] && made="$limit" || made="$pending"
  mkdir -p "$folder/transcripts"
  have="$(ls "$folder/transcripts" | wc -l | tr -d ' ')"
  i=0
  while [ "$i" -lt "$made" ]; do
    i=$((i + 1))
    echo "line" > "$folder/transcripts/t$((have + i)).txt"
  done
  echo $((pending - made)) > "$PENDING_FILE"
fi
exit "$code"
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


class TogetherTests(Setup):
    def setUp(self):
        super().setUp()
        os.rename(os.path.join(self.bin, "python3"), os.path.join(self.bin, "python3-base"))
        for name, text in (("python3", PYTHON_TOGETHER), ("sleep", SLEEP)):
            path = os.path.join(self.bin, name)
            with open(path, "w") as f:
                f.write(text)
            os.chmod(path, 0o755)
        self.pending = os.path.join(self.root, "pending")

    def start(self, pending=45, typed="yes\n", **more):
        os.makedirs(self.folder, exist_ok=True)
        with open(self.pending, "w") as f:
            f.write(str(pending))
        return self.run_script(NAME, typed=typed, PENDING_FILE=self.pending, **more)

    def steps(self):
        """The transcriber and the marking calls, in order, as short words."""
        out = []
        for call in self.called():
            if call.startswith("python3 teach_transcribe.py"):
                out.append("write")
            elif call.startswith("python3 teach_label.py"):
                out.append("mark")
        return out

    def transcribing(self):
        return [c for c in self.called() if c.startswith("python3 teach_transcribe.py")]

    def test_it_writes_down_a_batch_marks_it_and_goes_on_until_nothing_is_left(self):
        done = self.start(pending=45)
        self.assertEqual(done.returncode, 0, done.stdout)
        # 20 + 20 + 5 written down, then one empty batch that also marks what is left.
        self.assertEqual(self.steps(), ["write", "mark"] * 4)
        self.assertEqual(len(os.listdir(os.path.join(self.folder, "transcripts"))), 45)
        self.assertIn("python3 teach_publish.py --folder FOLDER", self.called())  # the steps after marking
        self.assertIn("Done.", done.stdout)

    def test_the_batches_are_20_episodes_and_marking_is_at_any_hour_under_the_budget(self):
        self.start(pending=5)
        self.assertEqual(self.transcribing()[0],
                         "python3 teach_transcribe.py --folder FOLDER --tool %s/podcast-transcribe --limit 20" % self.bin)
        self.assertEqual(
            [c for c in self.called() if c.startswith("python3 teach_label.py")][0],
            "python3 teach_label.py --folder FOLDER --between 0-24 --wait-hours 120 --cap 95 "
            "--budget big-run-1 --yes")

    def test_the_batch_size_and_the_budget_can_be_changed(self):
        os.makedirs(self.folder, exist_ok=True)
        with open(os.path.join(self.folder, "current-budget.txt"), "w") as f:
            f.write("big-run-20261125-0501\n")
        self.start(pending=5, TEACH_CHUNK="7")
        self.assertIn("--limit 7", self.transcribing()[0])
        self.assertIn("--budget big-run-20261125-0501 --yes", [c for c in self.called() if "teach_label" in c][0])
        self.start(pending=5, TEACH_CHUNK="abc")
        self.assertIn("--limit 20", self.transcribing()[-1])

    def test_anything_but_yes_starts_nothing(self):
        for typed in ("\n", "no\n", "y\n", "ye s\n", "yes please\n"):
            open(self.calls, "w").close()
            done = self.start(typed=typed)
            self.assertEqual(done.returncode, 0, typed)
            self.assertEqual(self.called(), [], typed)

    def test_it_backs_up_once_at_the_start_and_not_in_every_batch(self):
        self.start(pending=45)
        calls = self.called()
        first_batch = calls.index(self.transcribing()[0])
        last_batch = max(i for i, c in enumerate(calls) if c.startswith("python3 teach_transcribe.py"))
        backups = [i for i, c in enumerate(calls) if c.startswith("python3 teach_backup.py make")]
        self.assertEqual([i for i in backups if i < first_batch], backups[:1])
        self.assertEqual([i for i in backups if first_batch < i < last_batch], [])

    def test_it_waits_while_another_run_holds_the_folder_and_says_so_once(self):
        done = self.start(pending=5, BUSY_TIMES="3")
        self.assertEqual(done.returncode, 0, done.stdout)
        self.assertEqual(done.stdout.count("Another teaching run is still working"), 1)
        self.assertEqual(self.called().count("sleep 10"), 3)
        order = self.called()
        last_busy = max(i for i, c in enumerate(order) if c.startswith("python3 teach_store.py busy"))
        self.assertLess(last_busy, order.index(self.transcribing()[0]))

    def test_the_spending_limit_stops_the_batches_but_the_steps_after_marking_still_run(self):
        done = self.start(pending=45, CODES="teach_label.py=5")
        self.assertEqual(self.steps(), ["write", "mark"])
        self.assertIn("python3 teach_publish.py --folder FOLDER", self.called())
        self.assertIn("spending limit", done.stdout)
        self.assertEqual(done.returncode, 3)

    def test_episodes_that_keep_failing_to_be_written_down_stop_it_and_the_marks_are_used(self):
        done = self.start(pending=45, CODES="teach_transcribe.py=3")
        self.assertEqual(self.steps(), ["write"])
        self.assertIn("python3 teach_publish.py --folder FOLDER", self.called())
        self.assertIn("several episodes in a row failed", done.stdout)

    def test_a_tool_that_is_not_set_up_stops_everything_without_the_steps_after_marking(self):
        done = self.start(pending=45, CODES="teach_transcribe.py=2")
        self.assertEqual(self.steps(), ["write"])
        self.assertNotIn("python3 teach_publish.py --folder FOLDER", self.called())
        self.assertEqual(done.returncode, 2)
        open(self.calls, "w").close()
        done = self.start(pending=45, CODES="teach_label.py=2")
        self.assertEqual(self.steps(), ["write", "mark"])
        self.assertNotIn("python3 teach_publish.py --folder FOLDER", self.called())

    def test_the_transcriber_not_building_stops_before_any_batch(self):
        done = self.start(pending=45, BUILD_FAILS="1")
        self.assertEqual(self.steps(), [])
        self.assertIn("did not build", done.stdout)

    def test_it_is_noted_in_the_log(self):
        self.start(pending=5)
        self.assertRegex(self.log(), r"=== \d{4}-\d\d-\d\d \d\d:\d\d write down and mark together: 20 at a time ===")


if __name__ == "__main__":
    unittest.main()
