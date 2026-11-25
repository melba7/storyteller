#!/usr/bin/env python3
"""Tests whether the word model finds ads better on the held-out shelf when it also learns from the
marked public transcripts (the SPoRC sample, see sporc_sample.py).

Standard library only. It makes two scratch folders of symbolic links in --work, `base` (your
teaching folder's episodes) and `with-public` (the same plus every public episode that has a
transcript and a label), copies shelf.json, exam.json and ahead.json into both so the shelf stays
the same held-out episodes and the sealed exam is never trained on, and runs teach_train.py in each
(the same settings the steps after marking use: --fit-tool and --labels). Nothing in your teaching
folder or the public folder is written: the models land in --work/base/ad-model.json and
--work/with-public/ad-model.json. It prints both models' held-out precision and recall side by side
and writes the table to --work/COMPARE.txt.

  teach_public_compare.py [--folder F] [--public P] [--work W] [--labels labels-snapped] [--fit-tool PATH]

Exit code: 0 it worked, 2 a set-up problem, no marked public episode, or a trainer that failed.

Run the tests: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import argparse
import json
import os
import shutil
import subprocess
import sys

import teach_store as store

HERE = os.path.dirname(os.path.abspath(__file__))
COPIED = ("shelf.json", "exam.json", "ahead.json")
BASE = "base"
MIXED = "with-public"
PUBLIC_LABELS = "labels"


def _link(source, target):
    if os.path.exists(source) and not os.path.lexists(target):
        os.symlink(source, target)


def usable_public(public):
    """The entries of the public folder that have both a transcript and a label."""
    found = []
    for item in store.load_manifest(public):
        transcript = os.path.join(public, "transcripts", item["id"] + ".txt")
        label = os.path.join(public, PUBLIC_LABELS, item["id"] + ".json")
        if os.path.exists(transcript) and os.path.exists(label):
            found.append(item)
    return found


def make_folders(main, public, work, labels):
    """Makes (base, with-public) fresh and returns their paths."""
    entries = store.load_manifest(main)
    extra = usable_public(public)
    made = []
    for name, added in ((BASE, []), (MIXED, extra)):
        folder = os.path.join(work, name)
        shutil.rmtree(folder, ignore_errors=True)
        for sub in ("transcripts", labels):
            os.makedirs(os.path.join(folder, sub), exist_ok=True)
        for owner, items, label_dir in ((main, entries, labels), (public, added, PUBLIC_LABELS)):
            for item in items:
                name_ = item["id"]
                _link(os.path.join(owner, "transcripts", name_ + ".txt"),
                      os.path.join(folder, "transcripts", name_ + ".txt"))
                _link(os.path.join(owner, label_dir, name_ + ".json"),
                      os.path.join(folder, labels, name_ + ".json"))
        _link(os.path.join(main, "audio"), os.path.join(folder, "audio"))
        for file in COPIED:
            if os.path.exists(os.path.join(main, file)):
                shutil.copyfile(os.path.join(main, file), os.path.join(folder, file))
        store.save_manifest(folder, entries + added)
        made.append(folder)
    return made[0], made[1]


def _percent(value):
    return "%.1f" % (value * 100) if isinstance(value, (int, float)) else "-"


def _change(before, after):
    if not isinstance(before, (int, float)) or not isinstance(after, (int, float)):
        return "-"
    return "%+.1f" % ((after - before) * 100)


def report(base, mixed):
    """The table for two model files (as read from ad-model.json)."""
    rows = []
    held = [(model.get("trained") or {}).get("heldOut") for model in (base, mixed)]
    if not all(held):
        return "One of the models has no held-out numbers, so they cannot be compared.\n"
    rows.append("%-34s %12s %12s %10s" % ("Held-out shelf (%d episodes)" % held[0].get("episodes", 0),
                                          "base", "with public", "change"))
    rows.append("%-34s %12s %12s" % ("Episodes trained on",
                                     (base["trained"] or {}).get("episodes", "-"),
                                     (mixed["trained"] or {}).get("episodes", "-")))
    for title, key in (("Any ad, seconds", "anyAd"), ("Any ad, lines", "lineAnyAd")):
        for kind in ("precision", "recall"):
            before = (held[0].get(key) or {}).get(kind)
            after = (held[1].get(key) or {}).get(kind)
            rows.append("%-34s %12s %12s %10s" % ("%s, %s (%%)" % (title, kind), _percent(before),
                                                  _percent(after), _change(before, after)))
    return "\n".join(rows) + "\n"


def _read_model(folder):
    with open(os.path.join(folder, "ad-model.json"), encoding="utf-8") as handle:
        return json.load(handle)


def _trainer(labels, fit_tool):
    def train(folder):
        command = [sys.executable, "-u", os.path.join(HERE, "teach_train.py"), "--folder", folder,
                   "--labels", labels]
        if fit_tool:
            command += ["--fit-tool", fit_tool]
        return subprocess.run(command).returncode
    return train


def run(main, public, work, labels, fit_tool, say=print, train=None):
    """Makes both folders, trains in each and prints the comparison. 0 when it did."""
    try:
        extra = usable_public(public)
        store.load_manifest(main)
    except (OSError, store.ManifestError) as error:
        say("Could not read an episode list: %s" % error)
        return 2
    if not extra:
        say('No public transcript has a label yet. Double-click "Mark the public transcripts" first.')
        return 2
    say("%d marked public episodes will be added to training." % len(extra))
    base, mixed = make_folders(main, public, work, labels)
    train = train or _trainer(labels, fit_tool)
    for name, folder in (("base", base), ("with the public marks", mixed)):
        say("Training the model: %s ..." % name)
        if train(folder) != 0:
            say("The trainer did not work for %s (see above)." % name)
            return 2
    for name, folder in (("base", base), ("with the public marks", mixed)):
        if not os.path.exists(os.path.join(folder, "ad-model.json")):
            say("The trainer wrote no model for %s (too few marked episodes, see above)." % name)
            return 2
    try:
        text = report(_read_model(base), _read_model(mixed))
    except (OSError, ValueError) as error:
        say("Could not read a model: %s" % error)
        return 2
    heading = "Word model on the held-out shelf, without and with the public marks\n\n"
    with open(os.path.join(work, "COMPARE.txt"), "w", encoding="utf-8") as handle:
        handle.write(heading + text)
    say("\n" + heading + text)
    say("The models are in %s/base and %s/with-public (ad-model.json)." % (work, work))
    return 0


def main(argv):
    base = os.path.expanduser("~/Storyteller Lofi")
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--folder", default=os.path.join(base, "PodcastTeaching"))
    parser.add_argument("--public", default=os.path.join(base, "PodcastTeachingSporc"))
    parser.add_argument("--work", default=os.path.join(base, "PodcastTeachingPublicTest"))
    parser.add_argument("--labels", default="labels-snapped")
    parser.add_argument("--fit-tool")
    args = parser.parse_args(argv[1:])
    return run(args.folder, args.public, args.work, args.labels, args.fit_tool)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
