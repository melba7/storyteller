"""Tests that teach-finish.sh builds podcast-teach before the model step and gives it to the
trainer (--fit-tool). The stand-in programs are those of test_teach_shell.py. No network.
Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import test_teach_shell as shell


class FitToolTests(shell.Setup):
    def train_calls(self):
        return [line for line in self.called() if line.startswith("python3 teach_train.py")]

    def test_the_model_step_gets_the_built_tool(self):
        self.run_script("teach-finish.sh")
        self.assertEqual(len(self.train_calls()), 1)
        self.assertIn(" --fit-tool %s/podcast-teach" % self.bin, self.train_calls()[0])

    def test_the_tool_is_built_before_the_model_step(self):
        self.run_script("teach-finish.sh")
        order = self.short()
        self.assertLess(order.index("swift build -c release --product podcast-teach"),
                        order.index("python3 teach_train.py"))
        self.assertEqual(order.count("swift build -c release --product podcast-teach"), 1)

    def test_when_the_build_fails_the_model_is_trained_without_the_tool_and_says_so(self):
        done = self.run_script("teach-finish.sh", BUILD_FAILS="1")
        self.assertEqual(len(self.train_calls()), 1)
        self.assertNotIn("--fit-tool", self.train_calls()[0])
        self.assertIn("so the model is trained the old way (version 1)", done.stdout)
        self.assertIn("  Model: worked", done.stdout)

    def test_a_failing_model_step_is_still_a_failed_step_not_a_stop(self):
        done = self.run_script("teach-finish.sh", FAIL="teach_train.py")
        self.assertIn("  Model: failed", done.stdout)
        self.assertIn("  Sounds: worked", done.stdout)


if __name__ == "__main__":
    import unittest
    unittest.main()
