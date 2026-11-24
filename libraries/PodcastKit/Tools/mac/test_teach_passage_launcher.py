"""Tests for "Teach the passage model.command": it runs teach_passage.py with the python of the
python-mood environment, under the lock of the teaching folder, with the mood work's caches, and says
in plain words how each ending went. Stand-in python3, caffeinate and venv python programs on a
temporary PATH and home, so no torch, no Mac and no sentence model.
Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import os
import re
import stat
import unittest

from test_teach_shell import HERE, Setup

NAME = "Teach the passage model.command"
VENV_PYTHON = """#!/bin/bash
# stand-in for the python of the python-mood environment
if [ "$1" = "-I" ]; then
  [ -n "$NO_TORCH" ] && exit 1
  exit 0
fi
echo "venv-python $*" >> "$CALLS"
echo "HF_HOME=$HF_HOME TOKENIZERS_PARALLELISM=$TOKENIZERS_PARALLELISM" >> "$CALLS"
[ -n "$PRINTS" ] && echo "$PRINTS"
exit "${TOOL_CODE:-0}"
"""


class LauncherTests(Setup):
    def setUp(self):
        super().setUp()
        self.root_folder = os.path.join(self.home, "Storyteller Lofi")
        self.folder = os.path.join(self.root_folder, "PodcastTeaching")
        os.makedirs(self.folder)
        self.venv(VENV_PYTHON)

    def venv(self, text):
        path = os.path.join(self.root_folder, "python-mood", "bin", "python")
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w") as f:
            f.write(text)
        os.chmod(path, 0o755)

    def run_launcher(self, **more):
        env = {"CALLS": self.calls, "TOOLS": HERE, "REAL_PYTHON": ""}
        env.update(more)
        return self.run_script(NAME, **env)

    def test_it_runs_the_trainer_with_the_venvs_python_under_the_folders_lock(self):
        done = self.run_launcher(PRINTS="Wrote passage-model.json with the answers for 2 shelf episodes.")
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        calls = self.called()
        self.assertIn("python3 teach_store.py hold %s caffeinate -i %s/python-mood/bin/python -u %s/teach_passage.py "
                      "--folder %s --epochs 8" % (self.folder, self.root_folder, HERE, self.folder), calls)
        self.assertIn("venv-python -u %s/teach_passage.py --folder %s --epochs 8" % (HERE, self.folder), calls)

    def test_it_uses_the_caches_of_the_mood_work_and_keeps_to_the_folder(self):
        self.run_launcher()
        self.assertIn("HF_HOME=%s/.cache/huggingface TOKENIZERS_PARALLELISM=false" % self.root_folder,
                      self.called())

    def test_a_good_run_says_done_and_what_to_read_next_in_the_trials_own_terms(self):
        done = self.run_launcher(PRINTS="Wrote passage-model.json.")
        self.assertIn("Done. The answers are in %s/passage-model.json" % self.folder, done.stdout)
        for words in ("Score the ad skipping", "Plus the passage model", "10 more breaks", "labels-snapped",
                      "2 more skips"):
            self.assertIn(words, done.stdout)
        self.assertIn("trial", done.stdout)

    def test_the_snapped_labels_are_used_when_there_are_some(self):
        self.run_launcher()
        self.assertNotIn("--labels", " ".join(c for c in self.called() if c.startswith("venv-python")))
        os.makedirs(os.path.join(self.folder, "labels-snapped"))
        done = self.run_launcher()
        self.assertIn("--labels labels-snapped", " ".join(self.called()))
        self.assertIn("labels in labels-snapped", done.stdout)

    def test_the_most_passes_can_be_set(self):
        self.run_launcher(TEACH_EPOCHS="3")
        self.assertIn("--epochs 3", " ".join(c for c in self.called() if c.startswith("venv-python")))

    def test_what_it_prints_is_added_to_the_log(self):
        self.run_launcher(PRINTS="an embedding line")
        self.assertIn("an embedding line", self.log())
        self.assertIn("passage ===", self.log())

    def test_too_few_episodes_is_said_and_not_called_done(self):
        done = self.run_launcher(PRINTS="Only 3 episodes are marked, so no answers were written.")
        self.assertEqual(done.returncode, 0)
        self.assertIn("Nothing was learned", done.stdout)
        self.assertNotIn("Done. The answers are in", done.stdout)

    def test_a_set_up_problem_points_at_what_the_tool_printed(self):
        done = self.run_launcher(PRINTS="There is no shelf.json", TOOL_CODE="2")
        self.assertEqual(done.returncode, 2, done.stdout)
        self.assertIn("There is no shelf.json", done.stdout)
        for words in ("what the tool printed above", "no shelf yet", "sentence model could not be loaded"):
            self.assertIn(words, done.stdout)

    def test_another_run_in_the_folder_is_said_and_nothing_is_run(self):
        done = self.run_launcher(BUSY="1")
        self.assertEqual(done.returncode, 1, done.stdout)
        self.assertIn("Another teaching run is already working", done.stdout)
        self.assertFalse([c for c in self.called() if c.startswith("venv-python")])

    def test_any_other_ending_says_to_double_click_again_because_the_vectors_are_kept(self):
        done = self.run_launcher(TOOL_CODE="1")
        self.assertEqual(done.returncode, 1)
        self.assertIn("what was embedded is kept", done.stdout)

    def test_no_environment_no_torch_or_no_folder_stops_before_anything_runs(self):
        done = self.run_launcher(NO_TORCH="1")
        self.assertEqual(done.returncode, 2)
        self.assertIn("no numpy, torch or transformers", done.stdout)
        os.remove(os.path.join(self.root_folder, "python-mood", "bin", "python"))
        done = self.run_launcher()
        self.assertEqual(done.returncode, 2)
        self.assertIn("python-mood environment is not set up", done.stdout)
        self.assertIn("finetune.sh", done.stdout)
        self.venv(VENV_PYTHON)
        os.rmdir(self.folder)
        done = self.run_launcher()
        self.assertEqual(done.returncode, 2)
        self.assertIn("no teaching folder", done.stdout)
        self.assertFalse([c for c in self.called() if c.startswith("venv-python")])

    def test_the_file_can_be_run_and_keeps_to_what_the_macs_bash_has(self):
        path = os.path.join(HERE, NAME)
        self.assertTrue(os.stat(path).st_mode & stat.S_IXUSR)
        with open(path, encoding="utf-8") as f:
            text = f.read()
        self.assertEqual(text.splitlines()[0], "#!/bin/bash")
        code = "".join(line for line in text.splitlines(True) if not line.lstrip().startswith("#"))
        for pattern in (r"declare\s+-A", r"\bmapfile\b", r"\breadarray\b", r"\$\{[A-Za-z_]+(,,|\^\^)\}",
                        r"\$\(<<", r"&>>?", r"\|&", r"\bcoproc\b"):
            self.assertIsNone(re.search(pattern, code), pattern)


if __name__ == "__main__":
    unittest.main()
