"""Tests for "Write down the word times again.command": it builds only the transcriber, runs the two
tools in order, costs nothing (no Claude, no key) and never touches the transcripts or the marks.
The script is read, not run. Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import os
import re
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
LAUNCHER = os.path.join(HERE, "Write down the word times again.command")


class LauncherTests(unittest.TestCase):
    def setUp(self):
        with open(LAUNCHER, encoding="utf-8") as handle:
            self.text = handle.read()

    def test_it_can_be_double_clicked(self):
        self.assertTrue(os.access(LAUNCHER, os.X_OK))
        self.assertTrue(self.text.startswith("#!/bin/bash\n"))

    def test_it_writes_down_then_scores(self):
        words = self.text.index('"$HERE/teach_words.py"')
        scored = self.text.index('"$HERE/teach_end_score.py"')
        self.assertLess(self.text.index("--product podcast-transcribe"), words)
        self.assertLess(words, scored)

    def test_it_spends_nothing(self):
        code = "\n".join(line for line in self.text.splitlines() if not line.startswith("#"))
        for word in ("teach_label", "claude", "--yes", "curl", "ANTHROPIC"):
            self.assertNotIn(word, code)

    def test_the_whole_shelf_is_the_default_and_everything_needs_a_switch(self):
        self.assertIn('[ "$TEACH_WORDS_ALL" = 1 ] && ALL="--all"', self.text)
        self.assertEqual(len(re.findall(r'--all"', self.text)), 1)


if __name__ == "__main__":
    unittest.main()
