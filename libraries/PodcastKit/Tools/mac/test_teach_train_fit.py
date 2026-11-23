"""Tests for the version 2 model that teach_train.py writes, and for the fit by `podcast-teach fit`
(teach_fit.py). The fit tool is a small stand-in program, so no Swift is needed; with the real
tool built, set TEACH_FIT_TOOL to its path and one more test runs it. No network.
Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import json
import os
import stat
import sys
import unittest

import teach_features as ft
import teach_fit
import teach_train as train
from test_teach_train import Folder, run, toy_folder
from teach_phone_rule import refusals

STAND_IN = """#!%s
import json, os, sys
here = os.path.dirname(os.path.abspath(__file__))
config = json.load(open(os.path.join(here, "config.json")))
args = sys.argv[1:]
with open(os.path.join(here, "calls.json"), "a") as f:
    f.write(json.dumps(args) + "\\n")
if config.get("fail"):
    print("the stand-in is told to fail")
    sys.exit(config["fail"])
lines = open(args[1]).read().split("\\n")
with open(os.path.join(here, "header.txt"), "w") as f:
    f.write(lines[0] + "\\n" + str(len([l for l in lines[1:] if l])))
counts = {}
for line in lines[1:]:
    parts = line.split()
    for b in parts[1:]:
        counts.setdefault(b, [0] * 5)[int(parts[0])] += 1
weights = {}
for b, five in counts.items():
    if sum(five) >= 3:
        top = five.index(max(five))
        weights[b] = [-1.0 if c == 0 and top else (1.0 if c == top and top else 0.0) for c in range(5)]
if config.get("garbage"):
    open(args[2], "w").write("not json")
else:
    json.dump({"bias": config.get("bias", [5.0, 0, 0, 0, 0]), "weights": weights, "iterations": 7,
               "objective": 12.5}, open(args[2], "w"))
print("Pass 7: objective 12.5.")
"""


class Setup(unittest.TestCase):
    def tool(self, **config):
        folder = Folder(self)
        path = os.path.join(folder.path, "stand-in")
        os.makedirs(path)
        script = os.path.join(path, "podcast-teach")
        with open(script, "w") as f:
            f.write(STAND_IN % sys.executable)
        os.chmod(script, os.stat(script).st_mode | stat.S_IXUSR)
        with open(os.path.join(path, "config.json"), "w") as f:
            json.dump(config, f)
        self.stand_in = path
        return script

    def calls(self):
        with open(os.path.join(self.stand_in, "calls.json")) as f:
            return [json.loads(line) for line in f if line.strip()]


class FitToolTests(Setup):
    def test_the_tool_is_called_with_the_fixed_settings_and_its_fit_is_written_as_version_2(self):
        folder = toy_folder(self, 8)
        code, said = run(folder, "--min-episodes", "3", "--fit-tool", self.tool())
        self.assertEqual(code, 0, said)
        args = self.calls()[0]
        self.assertEqual(args[0], "fit")
        self.assertEqual(args[3:], ["--c", "0.1", "--min-count", "3", "--class-cap", "5",
                                    "--iterations", "300"])
        model = folder.read("ad-model.json")
        self.assertEqual((model["version"], model["buckets"]), (2, 4194304))
        self.assertEqual(refusals(model), [])
        self.assertEqual(model["trained"]["fitter"], "lbfgs")
        self.assertEqual(model["trained"]["iterations"], 7)
        self.assertFalse([s for s in said if "weaker" in s])
        self.assertIn("Pass 7: objective 12.5.", said)

    def test_the_examples_file_lists_every_line_without_the_bias_bucket(self):
        folder = toy_folder(self, 8)
        run(folder, "--min-episodes", "3", "--fit-tool", self.tool())
        with open(os.path.join(self.stand_in, "header.txt")) as f:
            header, count = f.read().split("\n")
        self.assertEqual(header, "buckets 4194304 classes 5")
        self.assertEqual(int(count), folder.read("ad-model.json")["trained"]["lines"])

    def test_the_example_lines_have_the_class_and_the_distinct_buckets_only(self):
        path = os.path.join(Folder(self).path, "examples.txt")
        bias = ft.bucket("#bias", ft.BUCKETS_V2)
        teach_fit.write_examples(path, [(2, [3, bias, 9]), (0, [bias]), (1, [])], ft.BUCKETS_V2, bias)
        with open(path) as f:
            self.assertEqual(f.read(), "buckets 4194304 classes 5\n2 3 9\n0\n1\n")

    def test_the_temporary_files_are_removed(self):
        folder = toy_folder(self, 8)
        run(folder, "--min-episodes", "3", "--fit-tool", self.tool())
        self.assertFalse([n for n in os.listdir(folder.path) if n.startswith(".fit-")])

    def test_a_tool_that_fails_is_a_setup_problem_and_nothing_is_written(self):
        folder = toy_folder(self, 8)
        code, said = run(folder, "--min-episodes", "3", "--fit-tool", self.tool(fail=3))
        self.assertEqual(code, 2)
        self.assertIn("exit code 3", said[-1])
        self.assertFalse(os.path.exists(folder.file("ad-model.json")))
        self.assertFalse(os.path.exists(folder.file("shelf.json")))
        self.assertFalse([n for n in os.listdir(folder.path) if n.startswith(".fit-")])

    def test_a_missing_tool_and_an_unreadable_answer_are_setup_problems(self):
        folder = toy_folder(self, 8)
        code, said = run(folder, "--min-episodes", "3", "--fit-tool", "/no/such/podcast-teach")
        self.assertEqual(code, 2)
        self.assertIn("cannot be run", said[-1])
        code, said = run(folder, "--min-episodes", "3", "--fit-tool", self.tool(garbage=True))
        self.assertEqual(code, 2)
        self.assertIn("could not be read", said[-1])
        self.assertFalse(os.path.exists(folder.file("ad-model.json")))

    def test_a_fitted_bias_that_does_not_call_an_empty_line_plain_is_raised_and_said(self):
        folder = toy_folder(self, 8)
        code, said = run(folder, "--min-episodes", "3",
                         "--fit-tool", self.tool(bias=[0.2, -0.1, 0.3, 0.1, -0.5]))
        self.assertEqual(code, 0)
        self.assertEqual(len([s for s in said if "first bias number was raised" in s]), 1)
        model = folder.read("ad-model.json")
        self.assertEqual(refusals(model), [])
        row = model["weights"][str(ft.bucket("#bias", ft.BUCKETS_V2))]
        self.assertGreater(row[0], 0.3)
        self.assertEqual(row[1:], [-0.1, 0.3, 0.1, -0.5])
        self.assertGreaterEqual(teach_fit.plain_probability(row), 0.5)

    def test_a_good_bias_is_kept_and_not_mentioned(self):
        folder = toy_folder(self, 8)
        _, said = run(folder, "--min-episodes", "3", "--fit-tool", self.tool(bias=[1.5, 0, 0, 0, 0]))
        self.assertEqual(folder.read("ad-model.json")["weights"][
            str(ft.bucket("#bias", ft.BUCKETS_V2))], [1.5, 0.0, 0.0, 0.0, 0.0])
        self.assertFalse([s for s in said if "raised" in s])

    def test_plain_bias_raises_just_enough(self):
        row, raised = teach_fit.plain_bias([-1, 2, 3, 1, 0])
        self.assertTrue(raised)
        self.assertGreaterEqual(teach_fit.plain_probability(row), 0.5)
        lower = list(row)
        lower[0] = round(lower[0] - 0.0002, 4)
        self.assertLess(teach_fit.plain_probability(lower), 0.5)
        self.assertEqual(teach_fit.plain_bias([5, 0, 0, 0, 0]), ([5.0, 0.0, 0.0, 0.0, 0.0], False))


class WithoutTheToolTests(unittest.TestCase):
    def test_the_built_in_loop_says_its_result_is_weaker_and_still_writes_version_2(self):
        folder = toy_folder(self, 8)
        code, said = run(folder, "--min-episodes", "3")
        self.assertEqual(code, 0)
        self.assertEqual(len([s for s in said if "weaker" in s]), 1)
        model = folder.read("ad-model.json")
        self.assertEqual((model["version"], model["buckets"]), (2, 4194304))
        self.assertEqual(model["trained"]["fitter"], "adagrad")
        self.assertEqual(refusals(model), [])


class ModelFileVersionTwoTests(unittest.TestCase):
    def flat(self, values, size=ft.BUCKETS_V2):
        weights = train.new_weights(size)
        for b, five in values.items():
            weights[b * 5:b * 5 + 5] = train.array("d", five)
        return weights

    def build(self, values, **named):
        text = train.build_model(self.flat(values), {"writtenAt": 5}, lambda w: {"w": len(w)},
                                 version=2, size=ft.BUCKETS_V2, **named)
        return json.loads(text), text

    def test_the_shape_is_version_2_with_the_big_bucket_count(self):
        model, _ = self.build({4000000: [0.123456, 0, 0, 0, -0.00004]})
        self.assertEqual((model["version"], model["buckets"]), (2, 4194304))
        self.assertEqual(model["weights"], {"4000000": [0.1235, 0.0, 0.0, 0.0, -0.0]})

    def test_the_default_caps_for_version_2(self):
        self.assertEqual(train.MAX_BUCKETS_V2, 80000)
        self.assertEqual(train.MAX_BYTES, 4500000)

    def test_the_biggest_rows_are_kept_and_the_bias_row_always(self):
        bias = ft.bucket("#bias", ft.BUCKETS_V2)
        values = {b: [0, b / 10.0, 0, 0, 0] for b in range(1, 11)}
        values[bias] = [0.5, 0, 0, 0, 0]
        model, _ = self.build(values, max_buckets=3)
        self.assertEqual(sorted(model["weights"], key=int), ["9", "10", str(bias)])


class CheckVersionTwoTests(unittest.TestCase):
    def test_the_check_in_the_model_is_made_with_the_version_2_decoder(self):
        folder = toy_folder(self, 8)
        run(folder, "--min-episodes", "3")
        model = folder.read("ad-model.json")
        weights = {int(k): v for k, v in model["weights"].items()}
        shelf = folder.read("shelf.json")["episodes"]
        entries = [e for e in folder.entries if e["id"] in shelf]
        shelved = [train.load_episode(folder.path, "labels", e, print, 2, ft.BUCKETS_V2) for e in entries]
        self.assertEqual(model["trained"]["heldOut"], train.evaluate(weights, shelved, 2))


@unittest.skipUnless(os.environ.get("TEACH_FIT_TOOL"), "set TEACH_FIT_TOOL to the built podcast-teach")
class RealToolTests(unittest.TestCase):
    def test_the_real_tool_fits_a_toy_folder(self):
        folder = toy_folder(self, 8)
        code, said = run(folder, "--min-episodes", "3", "--fit-tool", os.environ["TEACH_FIT_TOOL"])
        self.assertEqual(code, 0, said)
        model = folder.read("ad-model.json")
        self.assertEqual(refusals(model), [])
        self.assertEqual(model["trained"]["fitter"], "lbfgs")


if __name__ == "__main__":
    unittest.main()
