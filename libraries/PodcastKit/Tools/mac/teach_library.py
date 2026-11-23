#!/usr/bin/env python3
"""Builds the library of ads and promos from the labels of the teaching run, so that the phone can
recognise a repeated ad at once by its words.

Standard library only. It reads <folder>/episodes.json, every <folder>/<labels>/<id>.json that
teach_label.py wrote and the matching <folder>/transcripts/<id>.txt, and writes
<folder>/ad-library.json (publish it to the phone with teach_publish.py) and
<folder>/ad-library-score.json.

  teach_library.py [--folder F] [--labels labels] [--most 1500]

How it works:
- A candidate is a segment with confidence "high" whose words (transcript lines first to last)
  number at least 25 and whose length is from 8 to 300 seconds. A word is a piece of text between
  spaces that has at least one letter or digit.
- Two candidates are the same ad when at least 60% of the 3-word runs of the one with fewer runs
  are also in the other. The runs are made from the first 150 words, lower-cased with everything
  but letters and digits removed.
- Candidates are grouped in the order of episodes.json, then segment order. A candidate joins the
  first group whose first member it is the same as, otherwise it starts a group. Each group is one
  entry of the library: the more episodes it was met in, the earlier it comes.
- Every group is kept, also an ad that was met in one episode only: the phone should know the
  newest ads.
- ad-library.json is built from all marked episodes. ad-library-score.json has the same shape but is
  built only from the episodes that are not on the shelf (shelf.json), so the scorecard's "plus the
  library" row does not know the shelf ads' own words. It is not published.
- Episodes of the sealed exam (exam.json, see teach_exam.py) are left out of both files.
- The file stays under 4.5 MB (the phone refuses files over 5 MB): entries are dropped from the end.

Exit code: 0 it worked (also when there are no labels yet), 2 a set-up problem.

Run the tests: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import argparse
import json
import os
import re
import statistics
import sys
import time

import teach_store
import teach_segments as seg
from teach_exam import read_exam
from teach_shelf import read_shelf

DEFAULT_MOST = 1500
MAX_BYTES = 4500000
WORD_LIMIT = 150
MIN_WORDS = 25
MIN_SECONDS = 8
MAX_SECONDS = 300
SAME_PERCENT = 60
LISTED = 10
NOT_ALNUM = re.compile(r"[\W_]+")


# MARK: Words

def normalise(word):
    """The word in lower case with everything but letters and digits removed."""
    return NOT_ALNUM.sub("", word.lower())


def words_of(text):
    """The first 150 words of the text as transcribed (case and punctuation kept). Pieces of
    text with no letter or digit are not words."""
    found = [word for word in text.split() if normalise(word)]
    return found[:WORD_LIMIT]


def runs(normalised, size=3):
    """The set of `size`-word runs (3 by default) of a list of normalised words."""
    return {tuple(normalised[i:i + size]) for i in range(len(normalised) - size + 1)}


def same_ad(one, other):
    """True when at least 60% of the runs of the one with fewer runs are also in the other."""
    smaller, larger = (one, other) if len(one) <= len(other) else (other, one)
    if not smaller:
        return False
    return len(smaller & larger) * 100 >= SAME_PERCENT * len(smaller)


# MARK: Candidates

def usable(item, lines):
    """True when a segment of a label can be used: high confidence and a place in the transcript."""
    if not isinstance(item, dict) or item.get("confidence") != "high":
        return False
    first, last = item.get("first"), item.get("last")
    if not seg.whole(first) or not seg.whole(last) or not 1 <= first <= last <= len(lines):
        return False
    return all(isinstance(item.get(k), (int, float)) and not isinstance(item.get(k), bool)
               for k in ("start", "end")) and isinstance(item.get("sort"), str)


def read_json(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def episode_candidates(entry, folder, labels, say):
    """(candidates, True) for one episode, or ([], False) when it has no label, and ([], False)
    with one line when its label or transcript cannot be read."""
    name = entry["id"]
    try:
        one = read_json(os.path.join(folder, labels, name + ".json"))
    except FileNotFoundError:
        return [], False
    except (OSError, ValueError):
        one = None
    if not isinstance(one, dict) or not isinstance(one.get("segments"), list):
        say("Skipping %s/%s.json: it is not a valid label." % (labels, name))
        return [], False
    segments = [s for s in one["segments"] if isinstance(s, dict) and s.get("confidence") == "high"]
    if not segments:
        return [], True
    try:
        with open(os.path.join(folder, "transcripts", name + ".txt"), encoding="utf-8",
                  errors="replace") as f:
            lines = seg.read_transcript(f.read())
    except OSError:
        say("Skipping %s: its transcript cannot be read." % name)
        return [], False
    found = []
    for item in segments:
        if not usable(item, lines):
            continue
        words = words_of(" ".join(text for _, text in lines[item["first"] - 1:item["last"]]))
        length = item["end"] - item["start"]
        if len(words) >= MIN_WORDS and MIN_SECONDS <= length <= MAX_SECONDS:
            who = item.get("who")
            found.append({"episode": name, "feed": entry["feed"], "sort": item["sort"],
                          "who": who if isinstance(who, str) else "", "length": length,
                          "words": words, "runs": runs([normalise(w) for w in words])})
    return found, True


def read_candidates(folder, labels, say):
    """([candidate], how many labels were read) in the order of episodes.json, then segment
    order. The episodes of the sealed exam (exam.json) are left out."""
    found, read = [], 0
    sealed = set(read_exam(folder))
    for entry in teach_store.load_manifest(folder):
        if entry["id"] in sealed:
            continue
        more, ok = episode_candidates(entry, folder, labels, say)
        found += more
        read += 1 if ok else 0
    return found, read


# MARK: Library

def group(candidates):
    """The groups of candidates that are the same ad, in the order the groups started."""
    groups = []
    for item in candidates:
        for members in groups:
            if same_ad(members[0]["runs"], item["runs"]):
                members.append(item)
                break
        else:
            groups.append([item])
    return groups


def commonest(values):
    """The most common value; a tie goes to the one that came first."""
    return max(dict.fromkeys(values), key=values.count)


def make_entry(members):
    """The library entry of one group."""
    named = [m["who"] for m in members if m["who"]]
    return {"feed": members[0]["feed"],
            "scope": "all" if len({m["feed"] for m in members}) > 1 else "show",
            "sort": commonest([m["sort"] for m in members]),
            "who": commonest(named) if named else "",
            "text": " ".join(members[0]["words"]),
            "length": round(statistics.median(m["length"] for m in members), 1),
            "seen": len({m["episode"] for m in members})}


def document(ads, written):
    """The bytes of ad-library.json, exactly as teach_store.write_json writes them."""
    value = {"version": 1, "writtenAt": written, "ads": ads}
    return json.dumps(value, indent=1, ensure_ascii=False).encode("utf-8")


def entries_of(groups, most, max_bytes, written=0):
    """The entries, most seen first, at most `most`, and as many as fit in `max_bytes`."""
    ads = sorted((make_entry(members) for members in groups), key=lambda e: -e["seen"])[:most]
    low, high = 0, len(ads)
    while low < high:
        middle = (low + high + 1) // 2
        if len(document(ads[:middle], written)) <= max_bytes:
            low = middle
        else:
            high = middle - 1
    return ads[:low]


# MARK: Command line

def positive_whole(text):
    value = int(text)
    if value < 1:
        raise ValueError(text)
    return value


def main(argv, say=print, now=time.time, max_bytes=MAX_BYTES):
    parser = argparse.ArgumentParser(prog="teach_library.py")
    parser.add_argument("--folder", default=teach_store.FOLDER)
    parser.add_argument("--labels", default="labels")
    parser.add_argument("--most", type=positive_whole, default=DEFAULT_MOST)
    try:
        options = parser.parse_args(argv)
    except SystemExit:
        return 2
    folder = os.path.expanduser(options.folder)
    try:
        candidates, labels = read_candidates(folder, options.labels, say)
    except (teach_store.Problem, teach_store.ManifestError) as error:
        say(str(error))
        return 2
    if labels == 0:
        say("No labels yet. Run \"Mark ads in the teaching episodes\" first.")
        return 0
    try:
        shelf = set(read_shelf(folder))
    except teach_store.Problem as error:
        say(str(error))
        return 2
    written = int(now() * 1000)
    ads = entries_of(group(candidates), options.most, max_bytes, written)
    unshelved = [item for item in candidates if item["episode"] not in shelf]
    scored = entries_of(group(unshelved), options.most, max_bytes, written)
    teach_store.write_json(os.path.join(folder, "ad-library.json"),
                           {"version": 1, "writtenAt": written, "ads": ads})
    teach_store.write_json(os.path.join(folder, "ad-library-score.json"),
                           {"version": 1, "writtenAt": written, "ads": scored})
    several = sum(1 for e in ads if e["scope"] == "all")
    say("Looked at %d stretches in %d labelled episodes. Kept %d different ads, %d of them in "
        "more than one show." % (len(candidates), labels, len(ads), several))
    for e in ads[:LISTED]:
        say("  %s (%s): seen in %d episodes" % (e["who"] or "no name", e["sort"], e["seen"]))
    say("Saved ad-library.json, and ad-library-score.json without the %d shelf episode%s' ads for "
        "the scorecard." % (len(shelf), "" if len(shelf) == 1 else "s"))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
