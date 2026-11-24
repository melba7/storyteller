#!/usr/bin/env python3
"""Tries a small language model on the ad finding: reads five transcript lines at a time with a
sentence model and says, for each line, how likely it is to be an ad. This is a trial (milestone W5
of docs/PLAN.md); nothing here reaches the phone.

Needs numpy, and torch and transformers for the real sentence model, so run it with the python of
the python-mood environment in ~/Storyteller Lofi (the launcher "Teach the passage model.command"
does). It reads <folder>/episodes.json, <folder>/transcripts/<id>.txt, <folder>/<labels>/<id>.json,
shelf.json and exam.json, and writes <folder>/passage-cache/ and then <folder>/passage-model.json.

  teach_passage.py [--folder F] [--labels labels] [--epochs 8] [--seed 1] [--min-episodes 20]

- Every transcript line of the marked episodes that are not on the shelf (shelf.json, chosen by
  teach_train.py) and not in the sealed exam (exam.json), and that do not repeat a shelf or exam
  episode, is a lesson. Its class is the sort of the segment covering it, as in teach_train.py; a
  line that only a low-confidence segment covers is context only. Every tenth of those episodes (by
  id) is not learned from: it is the check that picks the pass and the L2 strength with the lowest
  loss. The shelf and the exam are never learned from, nor judged on while learning.
- Each line is embedded with MiniLM (teach_passage_encoder.py). Its window is the vectors of two
  lines before, the line and two lines after; a softmax regression over the windows (numpy only,
  teach_passage_model.py) says how likely each of the word model's five classes is.
- The answers go to passage-model.json for the shelf episodes only, as five probabilities for every
  line and no words: {"version": 1, "model", "decoder": 2, "classes", "thresholds", "trained",
  "episodes": {"<id>": {"lines": N, "rows": [[five numbers], ...]}}}. `podcast-teach score` decodes
  them with the word model's decoder (version 2, teach_spans.py) and adds the row "Plus the passage
  model". Without the file the row is left out.
- The vectors of every episode are kept in passage-cache/, so a stopped run carries on where it was
  and a second run takes minutes. The answers are written at the end, whole, through a temporary file.

Exit code: 0 it worked (also with too little data), 2 a set-up problem.

Run the tests: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import argparse
import json
import os
import sys
import time

import teach_passage_encoder as encoders
import teach_passage_model as classifier
import teach_segments as seg
import teach_store
from teach_exam import read_exam
from teach_features import CLASSES
from teach_model import write_text
from teach_overlap import same_episode_ids
from teach_passage_report import held_out, report_lines
from teach_shelf import read_shelf
from teach_spans import THRESHOLDS
from teach_train import MIN_EPISODES, line_classes, positive, valid_label, whole_number

ANSWERS_FILE = "passage-model.json"
VERSION = 1
DECODER = 2  # the word model's version 2 decoder (AdWordModel+SpansTwo.swift, teach_spans.decode_two)
DEFAULT_EPOCHS = 8
CHECK_EVERY = 10
L2_CHOICES = (1e-5, 1e-4, 1e-3)


# MARK: Episodes

def load_episode(folder, labels, entry, say):
    """One episode as {id, feed, texts, starts, ends, classes} with the text, the start and end second
    and the class (or None) of every transcript line, or None when it has no transcript or label. A
    file that cannot be read is skipped with one line."""
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
    return {"id": identifier, "feed": entry["feed"], "texts": [text for _, text in lines],
            "starts": starts, "ends": starts[1:] + [starts[-1] + seg.LAST_LINE_SECONDS],
            "classes": line_classes(one["segments"], len(lines))}


def sorted_out(entries, episodes, shelf, sealed, folder, say):
    """(learning, shelved): the episodes to learn from and the shelf episodes to answer for, in
    order. An episode that repeats a shelf or exam episode is left out of learning."""
    on_shelf = set(shelf)
    shelved = [episodes[i] for i in shelf if i in episodes]
    learning = [e for i, e in episodes.items() if i not in on_shelf]
    by_id = {e["id"]: e for e in entries}
    kept_apart = [e["id"] for e in shelved] + [i for i in sorted(sealed) if i in by_id]
    repeats = set(same_episode_ids(folder, by_id, kept_apart, [e["id"] for e in learning]))
    if repeats:
        learning = [e for e in learning if e["id"] not in repeats]
        say("Left %d episode%s out of training because %s the same as one on the shelf%s."
            % (len(repeats), "" if len(repeats) == 1 else "s", "it is" if len(repeats) == 1 else "they are",
               " or in the exam" if sealed else ""))
    if sealed & set(by_id):
        count = len(sealed & set(by_id))
        say("Left %d exam episode%s out of learning." % (count, "" if count == 1 else "s"))
    return learning, shelved


# MARK: Vectors

def how_long(seconds):
    if seconds < 60:
        return "under a minute"
    minutes = round(seconds / 60)
    return "%d minutes" % minutes if minutes < 90 else "%.1f hours" % (minutes / 60)


def embed_all(folder, encoder, episodes, say):
    """The line vectors of every episode by id, from the cache or from the encoder, with a line
    for each episode that had to be embedded."""
    vectors = {}
    total = sum(len(e["texts"]) for e in episodes)
    done = fresh_lines = kept = 0
    fresh_seconds = 0.0
    for number, episode in enumerate(episodes, 1):
        began = time.monotonic()
        vectors[episode["id"]], cached = encoders.cached_vectors(
            folder, encoder, episode["id"], episode["texts"])
        count = len(episode["texts"])
        done += count
        if cached:
            kept += 1
            continue
        spent = time.monotonic() - began
        fresh_lines += count
        fresh_seconds += spent
        left = (total - done) * fresh_seconds / max(fresh_lines, 1)
        say("Embedded %d of %d episodes: %d lines in %.1f seconds, about %s to go (if none of the "
            "rest is kept from before)." % (number, len(episodes), count, spent, how_long(left)))
    if kept:
        say("%d of %d episodes were kept from an earlier run (%s)." % (kept, len(episodes), encoders.CACHE))
    return vectors


# MARK: Learning

def best_fit(vectors, training, checking, options, say):
    """The fit with the lowest loss on the check episodes among the L2 strengths tried."""
    def pairs(group):
        return [(vectors[e["id"]], e["classes"]) for e in group]
    try:
        fits = [classifier.train(pairs(training), pairs(checking), l2, options.epochs, options.seed, say)
                for l2 in L2_CHOICES]
    except ValueError as error:
        raise teach_store.Problem(str(error))
    return min(fits, key=lambda one: float("inf") if one.check_loss is None else one.check_loss)


def answers_file(encoder, options, fit, training, checking, shelved, rows, held, now):
    """The text of passage-model.json: the shelf's rows, what the fit was made from and its check."""
    trained = {"writtenAt": now(), "labels": options.labels, "encoder": encoder.tag,
               "episodes": len(training), "checkEpisodes": len(checking),
               "lines": sum(1 for e in training for c in e["classes"] if c is not None),
               "shelf": len(shelved), "l2": fit.l2, "passes": fit.epochs,
               "checkLoss": None if fit.check_loss is None else round(float(fit.check_loss), 4),
               "heldOut": held}
    return json.dumps({
        "version": VERSION, "model": "%s, five lines, softmax regression" % encoder.tag,
        "decoder": DECODER, "classes": CLASSES, "thresholds": THRESHOLDS, "trained": trained,
        "episodes": {e["id"]: {"lines": len(e["texts"]), "rows": rows[e["id"]]} for e in shelved}},
        separators=(",", ":"))


def learn(folder, options, encoder, say, now):
    """The whole run. Returns the exit code, or raises teach_store.Problem."""
    entries = teach_store.require_manifest(folder)
    sealed = set(read_exam(folder))
    shelf = read_shelf(folder)
    episodes = {}
    for entry in entries:
        found = None if entry["id"] in sealed else load_episode(folder, options.labels, entry, say)
        if found:
            episodes[entry["id"]] = found
    learning, shelved = sorted_out(entries, episodes, shelf, sealed, folder, say)
    if len(learning) < options.min_episodes:
        say("Only %d episodes are marked and not on the shelf; at least %d are needed to learn, "
            "so no answers were written." % (len(learning), options.min_episodes))
        return 0
    if not shelf:
        raise teach_store.Problem(
            "There is no shelf.json in %s. The shelf is chosen when the word model is trained: "
            "double-click \"Teach the phone again\" first." % folder)
    if not shelved:
        raise teach_store.Problem(
            "No episode on the shelf has both a transcript and a label in \"%s\", so there is "
            "nothing to answer for." % options.labels)
    say("Learning from %d episodes, answering for the %d on the shelf." % (len(learning), len(shelved)))
    vectors = embed_all(folder, encoder, shelved + learning, say)

    learning.sort(key=lambda e: e["id"])
    checking = learning[::CHECK_EVERY]
    checked = {e["id"] for e in checking}
    training = [e for e in learning if e["id"] not in checked]
    say("Training on %d episodes; %d others pick the pass and the L2 strength."
        % (len(training), len(checking)))
    fit = best_fit(vectors, training, checking, options, say)
    rows = {e["id"]: fit.probabilities(vectors[e["id"]]).round(4).tolist() for e in shelved}
    held = held_out(shelved, rows)
    path = os.path.join(folder, ANSWERS_FILE)
    write_text(path, answers_file(encoder, options, fit, training, checking, shelved, rows, held, now))
    say("Chose L2 %g, kept pass %d of at most %d." % (fit.l2, fit.epochs, options.epochs))
    for line in report_lines(held):
        say(line)
    say("Wrote %s with the answers for %d shelf episodes." % (path, len(shelved)))
    return 0


def main(argv, say=print, encoder=None, now=None):
    parser = argparse.ArgumentParser(prog="teach_passage.py")
    parser.add_argument("--folder", default=teach_store.FOLDER)
    parser.add_argument("--labels", default="labels")
    parser.add_argument("--epochs", type=positive, default=DEFAULT_EPOCHS)
    parser.add_argument("--seed", type=whole_number, default=1)
    parser.add_argument("--min-episodes", type=positive, default=MIN_EPISODES)
    try:
        options = parser.parse_args(argv)
    except SystemExit as stop:
        return stop.code if isinstance(stop.code, int) else 2
    try:
        return learn(os.path.expanduser(options.folder), options, encoder or encoders.MiniLM(say), say,
                     now or (lambda: int(time.time() * 1000)))
    except teach_store.Problem as error:
        say(str(error))
        return 2
    except OSError as error:
        say("The teaching folder cannot be used: %s" % error)
        return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
