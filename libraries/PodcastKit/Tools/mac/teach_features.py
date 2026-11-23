"""The contract shared with the phone: how a transcript line becomes words, features, hashed
buckets and five class probabilities. The phone's Swift code does exactly the same, so change
nothing here without changing it there.

Standard library only. Used by teach_train.py.
- tokens: lower-case letters a-z, digits and apostrophes, with U+2019 read as an apostrophe,
  apostrophes trimmed from both ends, and every all-digit word turned into "0".
- features of line i: "#bias"; "u:" + word; "b:" + word pair; "p:" + each word of the two lines
  before; "n:" + each word of the two lines after; "#t0" (starts before 120 s) or "#t1" (before
  300 s); "#end" (fewer than 120 s before the end, when the length is known).
- Version 2 files (BUCKETS_V2 buckets) add "pb:" + a + " " + b for every pair of neighbouring words
  a, b of each of the two lines before, and "nb:" + a + " " + b for each of the two lines after.
  A pair never crosses a line border.
- A feature's bucket is the FNV-1a 32-bit hash of its UTF-8 bytes modulo 262144. A line's scores
  are the sums of the weights of its distinct buckets, and the probabilities are their softmax.

Run the tests: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import math
from array import array

CLASSES = ["none", "sponsor", "network_promo", "host_ask", "intro_credits"]
BUCKETS = 262144
BUCKETS_V2 = 4194304


def tokens(text):
    """The words of a line, as described above."""
    words, current = [], []
    for ch in text:
        if ch == "’":
            ch = "'"
        o = ord(ch)
        if 65 <= o <= 90:
            o += 32
            ch = chr(o)
        if 97 <= o <= 122 or 48 <= o <= 57 or ch == "'":
            current.append(ch)
        elif current:
            words.append("".join(current))
            current = []
    if current:
        words.append("".join(current))
    cleaned = []
    for word in words:
        word = word.strip("'")
        if not word:
            continue
        if all("0" <= c <= "9" for c in word):
            word = "0"
        cleaned.append(word)
    return cleaned


def fnv1a32(data):
    """The 32-bit FNV-1a hash of some bytes."""
    h = 2166136261
    for b in data:
        h ^= b
        h = (h * 16777619) & 0xFFFFFFFF
    return h


def bucket(feature, buckets=BUCKETS):
    return fnv1a32(feature.encode("utf-8")) % buckets


def features(lines, i, duration, version=1):
    """The set of feature strings of line i. lines is [(start_seconds, text)]."""
    found = {"#bias"}
    words = tokens(lines[i][1])
    for w in words:
        found.add("u:" + w)
    for a, b in zip(words, words[1:]):
        found.add("b:" + a + " " + b)
    for j in (i - 2, i - 1):
        if j >= 0:
            words_before = tokens(lines[j][1])
            for w in words_before:
                found.add("p:" + w)
            if version >= 2:
                for a, b in zip(words_before, words_before[1:]):
                    found.add("pb:" + a + " " + b)
    for j in (i + 1, i + 2):
        if j < len(lines):
            words_after = tokens(lines[j][1])
            for w in words_after:
                found.add("n:" + w)
            if version >= 2:
                for a, b in zip(words_after, words_after[1:]):
                    found.add("nb:" + a + " " + b)
    t = lines[i][0]
    if t < 120:
        found.add("#t0")
    elif t < 300:
        found.add("#t1")
    if duration is not None and duration - t < 120:
        found.add("#end")
    return found


def episode_buckets(lines, duration, version=1, size=BUCKETS):
    """For every line the sorted distinct buckets of its features, as array('i'). Same result as
    hashing features(), but each line's words are hashed once and reused by its neighbours."""
    own, before, after = [], [], []
    for _, text in lines:
        words = tokens(text)
        own.append({bucket("u:" + w, size) for w in words}
                   | {bucket("b:" + a + " " + b, size) for a, b in zip(words, words[1:])})
        near_before = {bucket("p:" + w, size) for w in words}
        near_after = {bucket("n:" + w, size) for w in words}
        if version >= 2:
            near_before |= {bucket("pb:" + a + " " + b, size) for a, b in zip(words, words[1:])}
            near_after |= {bucket("nb:" + a + " " + b, size) for a, b in zip(words, words[1:])}
        before.append(near_before)
        after.append(near_after)
    bias, t0, t1, end = (bucket(name, size) for name in ("#bias", "#t0", "#t1", "#end"))
    result = []
    for i, (t, _) in enumerate(lines):
        found = {bias} | own[i]
        for j in (i - 2, i - 1):
            if j >= 0:
                found |= before[j]
        for j in (i + 1, i + 2):
            if j < len(lines):
                found |= after[j]
        if t < 120:
            found.add(t0)
        elif t < 300:
            found.add(t1)
        if duration is not None and duration - t < 120:
            found.add(end)
        result.append(array("i", sorted(found)))
    return result


def softmax_of(line_buckets, weights):
    """The five probabilities for a line's buckets. weights maps a bucket to five numbers."""
    z = [0.0] * len(CLASSES)
    for b in line_buckets:
        w = weights.get(b)
        if w:
            for c in range(len(CLASSES)):
                z[c] += w[c]
    top = max(z)
    e = [math.exp(v - top) for v in z]
    total = sum(e)
    return [v / total for v in e]


def probabilities(weights, lines, i, duration, buckets=BUCKETS, version=1):
    """The five class probabilities of line i. lines is [(start_seconds, text)]."""
    found = features(lines, i, duration, version)
    return softmax_of(sorted({bucket(f, buckets) for f in found}), weights)
