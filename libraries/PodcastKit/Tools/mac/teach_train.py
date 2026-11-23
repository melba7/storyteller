#!/usr/bin/env python3
"""Trains the small model that lets the phone spot ads by itself, from the ads Claude marked in the
teaching run, and writes it as ad-model.json.

Standard library only. It reads <folder>/episodes.json, <folder>/transcripts/<id>.txt and
<folder>/<labels>/<id>.json (written by teach_label.py), and writes <folder>/ad-model.json and
then <folder>/shelf.json, so an old model never sits beside a newer shelf. How a line becomes words, features and buckets is the contract with the
phone and lives in teach_features.py.

  teach_train.py [--folder F] [--labels labels] [--epochs 5] [--seed 1] [--min-episodes 20]

- Every transcript line of an episode that has a transcript and a label is one example. Its class is
  the sort of the segment covering it (confidence high or medium); other lines are "none". A line
  that only a low-confidence segment covers is left out, in training and in the check.
- The shelf is a set of held-out episodes: for each show (by feed) with at least 3 usable episodes,
  its newest one. It is never trained on, stays on the shelf in later runs, and a show with one on
  the shelf gets no second. The file shelf.json is rewritten only when it changes, and only after
  the model is written. An episode that repeats a shelf episode (same feed key and guid, same audio
  SHA-256, or more than half of its 5-word runs the same, see teach_overlap.py) is left out of
  training, and the tool says how many.
- The sealed exam (exam.json, see teach_exam.py) is invisible here: an exam episode is never trained
  on and never put on the shelf, an episode that repeats one is left out of training like one that
  repeats a shelf episode, and the tool says how many exam episodes it left out.
- Training is softmax regression on the hashed features with AdaGrad (rate 0.5), L2 of 1e-6 on the
  weights an example touches, and each example's loss weighted by min(5, none count / class count).
  The bias bucket is fixed at plain talk (teach_model.BIAS_NONE) and never trained: the many words of
  plain talk used to carry its weight, which left a bias that said "ad" and a model the phone refuses.
  It is deterministic for a given --seed.
- After training the shelf is scored and the numbers are printed and saved in the model under
  trained.heldOut: "episodes", "shows", "predictedAdSeconds" (what teach_publish.py needs before it
  publishes), "anyAd" (precision and recall in seconds of the spans the phone would cut, see
  teach_spans.py), and per line "lineAnyAd" and "classes". A ratio with nothing to divide by is null.
- The model keeps at most 40,000 buckets (those with the biggest weights) and stays under 4.5 MB.
- With fewer than --min-episodes training episodes nothing is trained or written.

Exit code: 0 it worked (also with too little data), 2 a set-up problem.

Run the tests: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import argparse
import json
import math
import os
import random
import sys
import time
from array import array

import teach_segments as seg
import teach_store
from teach_exam import read_exam
from teach_model import (BIAS_BUCKET, BIAS_NONE, MAX_BUCKETS, MAX_BYTES, THRESHOLDS,  # noqa: F401
                         build_model, ranked_buckets, write_text)
from teach_overlap import same_episode_ids
from teach_shelf import SHELF_FILE, check_lines, choose_shelf, evaluate, read_shelf
from teach_features import BUCKETS, CLASSES, episode_buckets, probabilities  # noqa: F401

MIN_EPISODES = 20
RATE = 0.5
EPSILON = 1e-8
L2 = 1e-6
MODEL_FILE = "ad-model.json"
CLASS_COUNT = len(CLASSES)


# MARK: Examples

def whole(value):
    return isinstance(value, int) and not isinstance(value, bool)


def line_classes(segments, count):
    """For each of `count` lines the class index of the segment covering it, 0 for none, or None
    when only a low-confidence segment covers it. Segments are dicts with first, last (1-based),
    sort and confidence. A segment with an unknown sort is ignored; the first strong one wins."""
    classes = [0] * count
    strong = [False] * count
    low = [False] * count
    for one in segments:
        if one["sort"] not in CLASSES[1:]:
            continue
        sure = one["confidence"] in ("high", "medium")
        for n in range(max(one["first"], 1), min(one["last"], count) + 1):
            if sure and not strong[n - 1]:
                classes[n - 1] = CLASSES.index(one["sort"])
                strong[n - 1] = True
            elif not sure:
                low[n - 1] = True
    return [None if low[i] and not strong[i] else classes[i] for i in range(count)]


def valid_label(one):
    """True when a decoded label has the shape this tool needs."""
    if not isinstance(one, dict) or not isinstance(one.get("segments"), list):
        return False
    length = one.get("length")
    if isinstance(length, bool) or not isinstance(length, (int, float)):
        return False
    return all(isinstance(s, dict) and whole(s.get("first")) and whole(s.get("last"))
               and isinstance(s.get("sort"), str) and isinstance(s.get("confidence"), str)
               for s in one["segments"])


def load_episode(folder, labels, entry, say):
    """One episode as {id, feed, published, starts, ends, classes, buckets} with the start and end
    second, a class (or None) and the buckets of every transcript line, or None when it has no transcript or label. A file that
    cannot be read is skipped with one line."""
    identifier = entry["id"]
    transcript = os.path.join(folder, "transcripts", identifier + ".txt")
    label = os.path.join(folder, labels, identifier + ".json")
    if not os.path.exists(transcript) or not os.path.exists(label):
        return None
    try:
        with open(label, encoding="utf-8") as f:
            one = json.load(f)
        if not valid_label(one):
            raise ValueError("it is not a valid label")
        with open(transcript, encoding="utf-8") as f:
            lines = seg.read_transcript(f.read())
        if not lines:
            raise ValueError("the transcript has no lines")
    except (OSError, ValueError) as error:
        say("Skipping %s: %s." % (identifier, error))
        return None
    starts = [t for t, _ in lines]
    ends = starts[1:] + [starts[-1] + seg.LAST_LINE_SECONDS]
    return {"id": identifier, "feed": entry["feed"], "published": entry["published"],
            "starts": starts, "ends": ends, "classes": line_classes(one["segments"], len(lines)),
            "buckets": episode_buckets(lines, seg.episode_length(entry, lines))}


# MARK: Training

def new_weights():
    return array("d", [0.0]) * (BUCKETS * CLASS_COUNT)


def class_weights(counts):
    """How much each class's loss counts: min(5, none count / class count), 1 for none."""
    return [1.0] + [min(5.0, counts[0] / counts[c]) if counts[c] and counts[0] else 5.0
                    for c in range(1, CLASS_COUNT)]


def train(examples, epochs, seed, say=print):
    """Softmax regression with AdaGrad. examples is [(class index, buckets)]. Returns the flat
    weights, five per bucket."""
    counts = [0] * CLASS_COUNT
    for cls, _ in examples:
        counts[cls] += 1
    cost = class_weights(counts)
    w = new_weights()
    g2 = new_weights()
    bias_k = BIAS_BUCKET * 5
    w[bias_k] = BIAS_NONE
    rng = random.Random(seed)
    order = list(range(len(examples)))
    exp, log, sqrt = math.exp, math.log, math.sqrt
    for number in range(1, epochs + 1):
        started = time.monotonic()
        rng.shuffle(order)
        total = 0.0
        for index in order:
            cls, active = examples[index]
            z0 = z1 = z2 = z3 = z4 = 0.0
            for b in active:
                k = b * 5
                z0 += w[k]
                z1 += w[k + 1]
                z2 += w[k + 2]
                z3 += w[k + 3]
                z4 += w[k + 4]
            top = max(z0, z1, z2, z3, z4)
            e = [exp(z0 - top), exp(z1 - top), exp(z2 - top), exp(z3 - top), exp(z4 - top)]
            norm = sum(e)
            weight = cost[cls]
            total += -weight * log(max(e[cls] / norm, 1e-12))
            slope = [weight * v / norm for v in e]
            slope[cls] -= weight
            for b in active:
                if b == BIAS_BUCKET:
                    continue
                k = b * 5
                for c in range(5):
                    g = slope[c] + L2 * w[k + c]
                    g2[k + c] += g * g
                    w[k + c] -= RATE * g / (sqrt(g2[k + c]) + EPSILON)
        say("Pass %d of %d: mean loss %.4f, %.1f seconds."
            % (number, epochs, total / max(len(order), 1), time.monotonic() - started))
    return w


# MARK: Run

def positive(text):
    try:
        number = int(text)
    except ValueError:
        raise argparse.ArgumentTypeError("%r is not a whole number" % text)
    if number < 1:
        raise argparse.ArgumentTypeError("%r is not 1 or more" % text)
    return number


def whole_number(text):
    try:
        return int(text)
    except ValueError:
        raise argparse.ArgumentTypeError("%r is not a whole number" % text)


def main(argv, say=print, now=None):
    parser = argparse.ArgumentParser(prog="teach_train.py")
    parser.add_argument("--folder", default=teach_store.FOLDER)
    parser.add_argument("--labels", default="labels")
    parser.add_argument("--epochs", type=positive, default=5)
    parser.add_argument("--seed", type=whole_number, default=1)
    parser.add_argument("--min-episodes", type=positive, default=MIN_EPISODES)
    try:
        options = parser.parse_args(argv)
    except SystemExit as stop:
        return stop.code if isinstance(stop.code, int) else 2
    now = now or (lambda: int(time.time() * 1000))
    folder = os.path.expanduser(options.folder)
    try:
        if not os.path.exists(os.path.join(folder, teach_store.MANIFEST)):
            raise teach_store.Problem("There is no episodes.json in %s. Run the gather step first." % folder)
        try:
            entries = teach_store.load_manifest(folder)
        except teach_store.ManifestError as error:
            raise teach_store.Problem(str(error))
        old_shelf = read_shelf(folder)
        sealed = set(read_exam(folder))
        episodes = {}
        for entry in entries:
            if entry["id"] in sealed:
                continue
            found = load_episode(folder, options.labels, entry, say)
            if found:
                episodes[entry["id"]] = found
        shelf = choose_shelf(entries, set(episodes), old_shelf)
        on_shelf = set(shelf)
        shelved = [e for i, e in episodes.items() if i in on_shelf]
        learning = [e for i, e in episodes.items() if i not in on_shelf]
        by_id = {e["id"]: e for e in entries}
        kept_apart = [e["id"] for e in shelved] + [i for i in sorted(sealed) if i in by_id]
        repeats = set(same_episode_ids(folder, by_id, kept_apart, [e["id"] for e in learning]))
        if repeats:
            learning = [e for e in learning if e["id"] not in repeats]
            say("Left %d episode%s out of training because %s the same as one on the shelf%s."
                % (len(repeats), "" if len(repeats) == 1 else "s",
                   "it is" if len(repeats) == 1 else "they are",
                   " or in the exam" if sealed else ""))
        if sealed & set(by_id):
            count = len(sealed & set(by_id))
            say("Left %d exam episode%s out of learning." % (count, "" if count == 1 else "s"))
        if len(learning) < options.min_episodes:
            say("Only %d episodes are marked and not on the shelf; at least %d are needed to train, "
                "so no model was written." % (len(learning), options.min_episodes))
            return 0
        examples = [(c, b) for e in learning for c, b in zip(e["classes"], e["buckets"])
                    if c is not None]
        say("Training on %d episodes (%d lines), with %d on the shelf."
            % (len(learning), len(examples), len(shelved)))
        flat = train(examples, options.epochs, options.seed, say)
        trained = {"writtenAt": now(), "episodes": len(learning), "lines": len(examples),
                   "shelf": len(shelved)}
        text = build_model(flat, trained, lambda kept: evaluate(kept, shelved))
        path = os.path.join(folder, MODEL_FILE)
        write_text(path, text)
        if shelf != old_shelf:
            teach_store.write_json(os.path.join(folder, SHELF_FILE), {"version": 1, "episodes": shelf})
    except teach_store.Problem as error:
        say(str(error))
        return 2
    except OSError as error:
        say("The teaching folder cannot be used: %s" % error)
        return 2
    model = json.loads(text)
    for line in check_lines(model["trained"]["heldOut"]):
        say(line)
    say("Wrote %s with %d buckets." % (path, len(model["weights"])))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
