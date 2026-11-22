"""Finds training episodes that are really a held-out shelf episode again, so the shelf stays a fair
test.

Standard library only. The same episode can reach the folder twice (under two feed addresses, or two
ids). An episode is left out of training when it shares, with an episode on the shelf, the feed key
and guid, or the audio's SHA-256, or more than half of its 5-word runs (teach_library has the
word-run code).

Run the tests: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import os

import teach_library as library
import teach_segments as seg
from teach_feed import feed_key

RUN = 5


def word_runs(folder, identifier):
    """The set of 5-word runs of an episode's transcript (empty when it cannot be read)."""
    try:
        with open(os.path.join(folder, "transcripts", identifier + ".txt"), encoding="utf-8",
                  errors="replace") as f:
            lines = seg.read_transcript(f.read())
    except OSError:
        return set()
    words = [w for w in (library.normalise(w) for _, text in lines for w in text.split()) if w]
    return library.runs(words, RUN)


def same_episode_ids(folder, entries, shelf_ids, candidate_ids):
    """The ids among `candidate_ids` that repeat an episode on the shelf. `entries` maps an id to
    its episodes.json entry."""
    keys, hashes, shelf_runs = set(), set(), set()
    for identifier in shelf_ids:
        one = entries[identifier]
        if one.get("guid"):
            keys.add((feed_key(one["feed"]), one["guid"]))
        if one.get("sha256"):
            hashes.add(one["sha256"])
        shelf_runs |= word_runs(folder, identifier)
    found = []
    for identifier in candidate_ids:
        one = entries[identifier]
        if (one.get("guid") and (feed_key(one["feed"]), one["guid"]) in keys) \
                or (one.get("sha256") and one["sha256"] in hashes):
            found.append(identifier)
            continue
        mine = word_runs(folder, identifier)
        if mine and len(mine & shelf_runs) * 2 > len(mine):
            found.append(identifier)
    return found
