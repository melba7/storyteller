#!/usr/bin/env python3
"""Learns the lines that open an ad and the lines that come back after one, and writes them as
ad-cues.json for the phone's two timing finders (opening lines and filled holes).

Standard library only. It reads <folder>/episodes.json, <folder>/transcripts/<id>.txt and
<folder>/<labels>/<id>.json (written by teach_label.py), and writes <folder>/ad-cues.json.

  teach_cues.py [--folder F] [--labels labels] [--min-episodes 20]

The file has "version": 1, "writtenAt", "episodes" (how many episodes it learned from), the general
lists "starts" and "returns", "shows" (each with its "feed" address and its own "starts" and
"returns", only shows that have a cue), "common" and "usual". Every list is sorted, so the same
input gives the same file. It holds words of transcripts, so it is never committed.

The rules (docs/PLAN.md, "The file ad-cues.json"):
- A cue is the first 3 to 6 words of a transcript line, made by teach_features.tokens and joined by
  one space. A line matches a list when one of its own first 3, 4, 5 or 6 words is in it.
- It learns from the episodes teach_train.py learns from: a transcript and a label, not on the shelf
  (shelf.json as it is on disk), not in the sealed exam and not a repeat of either. The ads are the
  segments of the sorts sponsor, network_promo and host_ask with confidence high or medium; segments
  within 1 second of each other are one break.
- A line "opens" when it starts within 1 second of a segment's start. It is "in an ad" from 0.3
  seconds before a break's start to 0.5 seconds before its end. It is a "return" when it is not in
  an ad and the line before it is.
- A start cue opens in 5 or more episodes and 9 in 10 or more of all the lines that begin with it
  open. A show's start cue is the same within the show, in 3 or more of its episodes. Return cues
  are the same for return lines. Only the shortest cue is written: one that begins with a written
  cue of the same list (or with a general one, in a show) matches nothing more.
- "common" is the words of 4 characters or more in more than 15 in 100 of the episodes, "usual" the
  words in more than 5 and at most 15 in 100.

With fewer than --min-episodes episodes to learn from nothing is written and an old file stays. A
label or transcript that cannot be read is skipped and counted. When the new file differs from the
old one only in "writtenAt" it is left as it is.

Exit code: 0 it worked (also with too little data or nothing to change), 2 a set-up problem.

Run the tests: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import argparse
import json
import os
import sys
import time
from bisect import bisect_right
from collections import Counter

import teach_segments as seg
import teach_store
from teach_exam import read_exam
from teach_features import tokens
from teach_overlap import same_episode_ids
from teach_shelf import read_shelf
from teach_train import valid_label

CUES_FILE = "ad-cues.json"
SORTS = ("sponsor", "network_promo", "host_ask")
CONFIDENCE = ("high", "medium")
JOIN_SECONDS = 1.0
OPEN_SECONDS = 1.0
BEFORE_SECONDS = 0.3
END_SECONDS = 0.5
SIZES = (3, 4, 5, 6)
MIN_EPISODES_GENERAL = 5
MIN_EPISODES_SHOW = 3
MIN_WORD_LETTERS = 4
MIN_EPISODES = 20
KINDS = ("starts", "returns")


# MARK: One episode

def number(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def ad_spans(label):
    """The (start, end) of each ad segment of a label that counts, sorted. Raises ValueError when a
    segment of those sorts has no usable times."""
    spans = []
    for one in label["segments"]:
        if one["sort"] not in SORTS or one["confidence"] not in CONFIDENCE:
            continue
        start, end = one.get("start"), one.get("end")
        if not number(start) or not number(end):
            raise ValueError("a segment has no start and end time")
        if end > start:
            spans.append((start, end))
    return sorted(spans)


def joined(spans):
    """The breaks: spans that lie within JOIN_SECONDS of each other (or overlap) are one."""
    breaks = []
    for start, end in spans:
        if breaks and start - breaks[-1][1] <= JOIN_SECONDS:
            breaks[-1] = (breaks[-1][0], max(breaks[-1][1], end))
        else:
            breaks.append((start, end))
    return breaks


def cues_of(words):
    """The cues a line with these words begins with (those of 3 to 6 words it has)."""
    return [" ".join(words[:size]) for size in SIZES if len(words) >= size]


def read_episode(lines, spans):
    """What one episode teaches: {"starts": Counter, "returns": Counter} of how many of its lines
    with a cue open or return, "lines": Counter of the first 6 words of each line (all lines with 3
    words or more) and "words": the set of words of 4 characters or more. `lines` is
    [(seconds, text)], `spans` the sorted (start, end) of the ads."""
    breaks = joined(spans)
    break_starts = [start - BEFORE_SECONDS for start, _ in breaks]
    segment_starts = [start for start, _ in spans]

    def in_ad(second):
        index = bisect_right(break_starts, second) - 1
        return index >= 0 and second < breaks[index][1] - END_SECONDS

    def opens(second):
        index = bisect_right(segment_starts, second + OPEN_SECONDS)
        return index > 0 and segment_starts[index - 1] >= second - OPEN_SECONDS

    found = {"starts": Counter(), "returns": Counter(), "lines": Counter(), "words": set()}
    before = False
    for second, text in lines:
        words = tokens(text)
        found["words"].update(w for w in words if len(w) >= MIN_WORD_LETTERS)
        now = in_ad(second)
        kinds = (["starts"] if opens(second) else []) + (["returns"] if before and not now else [])
        before = now
        if len(words) < SIZES[0]:
            continue
        found["lines"][" ".join(words[:SIZES[-1]])] += 1
        for kind in kinds:
            found[kind].update(cues_of(words))
    return found


# MARK: Many episodes

class Tally:
    """What a group of episodes (all of them, or one show's) taught so far."""

    def __init__(self):
        self.episodes = 0
        self.lines = Counter()
        self.opening = {kind: Counter() for kind in KINDS}  # key -> lines that open or return
        self.seen = {kind: Counter() for kind in KINDS}  # key -> episodes with such a line

    def add(self, found):
        self.episodes += 1
        self.lines.update(found["lines"])
        for kind in KINDS:
            self.opening[kind].update(found[kind])
            self.seen[kind].update(found[kind].keys())

    def totals(self, wanted):
        """How many lines begin with each cue in `wanted`."""
        totals = Counter()
        for prefix, count in self.lines.items():
            for cue in cues_of(prefix.split()):
                if cue in wanted:
                    totals[cue] += count
        return totals

    def qualifying(self, least):
        """For each kind the cues that occur in `least` episodes and where 9 in 10 of all the lines
        that begin with the cue open (or return)."""
        wanted = {key for kind in KINDS for key, n in self.seen[kind].items() if n >= least}
        totals = self.totals(wanted) if wanted else {}
        return {kind: {key for key, n in self.seen[kind].items()
                       if n >= least and self.opening[kind][key] * 10 >= totals[key] * 9}
                for kind in KINDS}


def shortest(cues, covering=()):
    """The cues that have no shorter cue in `cues` or `covering` as the first words."""
    kept = []
    for cue in cues:
        words = cue.split()
        if not any(" ".join(words[:size]) in cues or " ".join(words[:size]) in covering
                   for size in SIZES if size < len(words)) and cue not in covering:
            kept.append(cue)
    return sorted(kept)


def frequent(words, episodes, low, high):
    """The sorted words in more than `low` and at most `high` of every 100 episodes."""
    return sorted(w for w, n in words.items()
                  if n * 100 > low * episodes and (high is None or n * 100 <= high * episodes))


def build(tally, shows, words):
    """(the file's content without writtenAt, the unpruned counts). `shows` maps a feed to its
    Tally and `words` counts the episodes each word occurs in."""
    general = tally.qualifying(MIN_EPISODES_GENERAL)
    out = {"version": 1, "episodes": tally.episodes}
    unpruned = {"general": {kind: len(general[kind]) for kind in KINDS}, "shows": {k: 0 for k in KINDS}}
    for kind in KINDS:
        out[kind] = shortest(general[kind])
    listed = []
    for feed in sorted(shows):
        own = shows[feed].qualifying(MIN_EPISODES_SHOW)
        for kind in KINDS:
            unpruned["shows"][kind] += len(own[kind])
        kept = {kind: shortest(own[kind], general[kind]) for kind in KINDS}
        if any(kept.values()):
            listed.append(dict(feed=feed, **kept))
    out["shows"] = listed
    out["common"] = frequent(words, tally.episodes, 15, None)
    out["usual"] = frequent(words, tally.episodes, 5, 15)
    return out, unpruned


# MARK: Run

def teaching_episodes(folder, labels, entries, say):
    """[(entry, lines, spans)] for the episodes that teach, and the counts of what was left out as
    a dict. An episode is read as teach_train.py reads one; a file that cannot be read is skipped."""
    sealed = set(read_exam(folder))
    shelf = set(read_shelf(folder))
    by_id = {e["id"]: e for e in entries}
    left = {"unreadable": 0, "kept apart": 0, "repeats": 0}
    ready = []
    for entry in entries:
        identifier = entry["id"]
        transcript = os.path.join(folder, "transcripts", identifier + ".txt")
        label = os.path.join(folder, labels, identifier + ".json")
        if not os.path.exists(transcript) or not os.path.exists(label):
            continue
        if identifier in sealed or identifier in shelf:
            left["kept apart"] += 1
            continue
        try:
            with open(label, encoding="utf-8") as f:
                one = json.load(f)
            if not valid_label(one):
                raise ValueError("it is not a valid label")
            spans = ad_spans(one)
            with open(transcript, encoding="utf-8") as f:
                lines = seg.read_transcript(f.read())
            if not lines:
                raise ValueError("the transcript has no lines")
        except (OSError, ValueError, KeyError) as error:
            say("Skipping %s: %s." % (identifier, error))
            left["unreadable"] += 1
            continue
        ready.append((entry, lines, spans))
    apart = [i for i in sorted(shelf | sealed) if i in by_id]
    repeats = set(same_episode_ids(folder, by_id, apart, [e["id"] for e, _, _ in ready]))
    left["repeats"] = len(repeats)
    return [r for r in ready if r[0]["id"] not in repeats], left


def learn(episodes):
    """The Tally of all episodes, the Tally of each feed and the episode count of each word."""
    everything, shows, words = Tally(), {}, Counter()
    for entry, lines, spans in episodes:
        found = read_episode(lines, spans)
        everything.add(found)
        shows.setdefault(entry["feed"], Tally()).add(found)
        words.update(found["words"])
    return everything, shows, words


def same_but_time(old, new):
    return isinstance(old, dict) and {k: v for k, v in old.items() if k != "writtenAt"} == new


def plural(count, one, many):
    return "%d %s" % (count, one if count == 1 else many)


def main(argv, say=print, now=None):
    parser = argparse.ArgumentParser(prog="teach_cues.py")
    parser.add_argument("--folder", default=teach_store.FOLDER)
    parser.add_argument("--labels", default="labels")
    parser.add_argument("--min-episodes", type=int, default=MIN_EPISODES)
    try:
        options = parser.parse_args(argv)
    except SystemExit as stop:
        return stop.code if isinstance(stop.code, int) else 2
    now = now or (lambda: int(time.time() * 1000))
    folder = os.path.expanduser(options.folder)
    path = os.path.join(folder, CUES_FILE)
    try:
        entries = teach_store.require_manifest(folder)
        episodes, left = teaching_episodes(folder, options.labels, entries, say)
        if len(episodes) < options.min_episodes:
            say("Only %d episodes are marked and not on the shelf; at least %d are needed to learn "
                "opening lines, so %s was not written." % (len(episodes), options.min_episodes, CUES_FILE))
            return 0
        content, unpruned = build(*learn(episodes))
        try:
            with open(path, encoding="utf-8") as f:
                old = json.load(f)
        except (OSError, ValueError):
            old = None
        if same_but_time(old, content):
            say("%s is already up to date." % CUES_FILE)
            return 0
        teach_store.write_json(path, dict(content, writtenAt=now()))
        size = os.path.getsize(path)
    except teach_store.Problem as error:
        say(str(error))
        return 2
    except (OSError, teach_store.ManifestError) as error:
        say("The teaching folder cannot be used: %s" % error)
        return 2
    say("Learned from %s (skipped %d unreadable, %d on the shelf or in the exam, %d repeats)."
        % (plural(content["episodes"], "episode", "episodes"), left["unreadable"],
           left["kept apart"], left["repeats"]))
    say("Before keeping only the shortest cue: %d opening and %d return lines for every show, "
        "%d and %d for single shows." % (unpruned["general"]["starts"], unpruned["general"]["returns"],
                                         unpruned["shows"]["starts"], unpruned["shows"]["returns"]))
    say("Wrote %s: %d opening and %d return lines for every show, %d and %d for %s, %d common and "
        "%d usual words, %d bytes." % (
            path, len(content["starts"]), len(content["returns"]),
            sum(len(s["starts"]) for s in content["shows"]), sum(len(s["returns"]) for s in content["shows"]),
            plural(len(content["shows"]), "show", "shows"), len(content["common"]),
            len(content["usual"]), size))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
