"""Fits the version 2 word model with `podcast-teach fit` (the Swift tool, which has a proper solver
where Python is too slow), and the plain-talk rule for the bias the fit gives back.

Standard library only. Used by teach_train.py.
- write_examples: the examples as a text file, `buckets <N> classes 5` and then one line for each
  training line with its class and its distinct buckets (the bias bucket is not listed).
- run_fit: writes the examples to a temporary file in the folder, runs the tool, reads its JSON
  and removes the temporary files. A tool that cannot run or fails is a set-up problem
  (teach_store.Problem), never a silent fallback.
- plain_bias: the five bias numbers, with the "none" number raised just enough when the bias alone
  would not call an empty line plain talk (the phone refuses such a file).

Run the tests: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import json
import math
import os
import subprocess
import tempfile

import teach_store

C = 0.1
MIN_COUNT = 3
CLASS_CAP = 5
ITERATIONS = 300


def write_examples(path, examples, size, bias_bucket):
    """Writes [(class index, buckets)] in the format `podcast-teach fit` reads."""
    with open(path, "w", encoding="utf-8") as f:
        f.write("buckets %d classes 5\n" % size)
        for cls, active in examples:
            f.write(" ".join([str(cls)] + [str(b) for b in active if b != bias_bucket]))
            f.write("\n")


def read_fit(path):
    """(bias, {bucket: five numbers}, iterations, objective) from the tool's JSON, or a Problem."""
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        bias, weights = data["bias"], data["weights"]
        numbers = [bias] + list(weights.values())
        ok = all(isinstance(r, list) and len(r) == 5
                 and all(isinstance(v, (int, float)) and math.isfinite(v) for v in r)
                 for r in numbers)
        if not ok:
            raise ValueError("a row is not five numbers")
        return bias, {int(b): r for b, r in weights.items()}, data["iterations"], data["objective"]
    except (OSError, ValueError, KeyError, TypeError, AttributeError) as error:
        raise teach_store.Problem("The fit tool's result could not be read: %s." % error)


def run_fit(tool, folder, examples, size, bias_bucket, say, runner=subprocess.Popen):
    """Fits the examples with the tool at `tool` and returns what read_fit returns."""
    names = []
    try:
        for suffix in (".txt", ".json"):
            handle, name = tempfile.mkstemp(dir=folder, prefix=".fit-", suffix=suffix)
            os.close(handle)
            names.append(name)
        write_examples(names[0], examples, size, bias_bucket)
        command = [tool, "fit", names[0], names[1], "--c", str(C), "--min-count", str(MIN_COUNT),
                   "--class-cap", str(CLASS_CAP), "--iterations", str(ITERATIONS)]
        last = []
        try:
            with runner(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                        text=True) as process:
                for line in process.stdout:
                    line = line.rstrip()
                    if line:
                        say(line)
                        last = (last + [line])[-3:]
                code = process.wait()
        except OSError as error:
            raise teach_store.Problem("The fit tool %s cannot be run: %s." % (tool, error))
        if code != 0:
            raise teach_store.Problem("The fit tool %s failed with exit code %s%s." % (
                tool, code, ": " + " ".join(last) if last else ""))
        return read_fit(names[1])
    except OSError as error:
        raise teach_store.Problem("The fit could not use the folder %s: %s." % (folder, error))
    finally:
        for name in names:
            if os.path.exists(name):
                os.remove(name)


def plain_probability(bias):
    top = max(bias)
    e = [math.exp(v - top) for v in bias]
    return e[0] / sum(e)


def plain_bias(bias):
    """(five rounded numbers, raised). When the plain-talk chance of the bias alone is under 0.5 the
    first number is raised, in steps of 0.0001, until it is at least 0.5."""
    row = [round(v, 4) + 0.0 for v in bias]
    raised = plain_probability(row) < 0.5
    if raised:
        top = max(row[1:])
        row[0] = math.ceil(top * 10000 + math.log(sum(math.exp(v - top) for v in row[1:])) * 10000) / 10000
        while plain_probability(row) < 0.5:
            row[0] = round(row[0] + 0.0001, 4)
    return row, raised
