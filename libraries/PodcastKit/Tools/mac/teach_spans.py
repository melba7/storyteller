"""Turns line probabilities into ad spans exactly as the phone does, and scores them in seconds.

Standard library only. This is a line-for-line port of AdWordModel+Spans.swift in PodcastAds: smooth
the ad probability over the neighbouring lines (a quarter, a half, a quarter), open a span where it
reaches `start`, keep it open while it stays at `stay` (bridging one weak line), and drop spans
shorter than 8 seconds unless their score is at least 0.9. The sort of a span is the class with the
most probability over its lines. Change nothing here without changing it there.

The check on the held-out shelf uses it, so its precision is about what the phone would cut:
a cut second is right only when the line's true sort is one the phone skips under its default
switches (sponsor ads, hosts' plugs and promos on, credits off). A span of a sort the phone does not
skip is not cut. A line the labels are unsure of counts as not an ad.

Run the tests: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
from teach_features import CLASSES

THRESHOLDS = {"start": 0.6, "stay": 0.4, "sure": 0.85}
MIN_SECONDS = 8
CERTAIN_SCORE = 0.9
SKIPPED_SORTS = ("sponsor", "network_promo", "host_ask")


def decode(rows, starts, ends, thresholds=THRESHOLDS):
    """The spans as (first index, last index, sort, score) for the per-line probability rows (five
    numbers each, "none" first) and the start and end second of every line."""
    n = len(rows)
    p = [1 - row[0] for row in rows]
    s = []
    for i in range(n):
        before = p[i - 1] if i > 0 else p[i]
        after = p[i + 1] if i + 1 < n else p[i]
        s.append(before / 4 + p[i] / 2 + after / 4)
    found = []
    i = 0
    while i < n:
        if s[i] < thresholds["start"]:
            i += 1
            continue
        j = i
        while True:
            if j + 1 < n and s[j + 1] >= thresholds["stay"]:
                j += 1
            elif j + 2 < n and s[j + 2] >= thresholds["stay"]:
                j += 2
            else:
                break
        best, best_sum = 1, float("-inf")
        for c in range(1, len(CLASSES)):
            total = 0.0
            for row in rows[i:j + 1]:
                total += row[c]
            if total > best_sum:
                best, best_sum = c, total
        score = sum(s[i:j + 1]) / (j - i + 1)
        if ends[j] - starts[i] >= MIN_SECONDS or score >= CERTAIN_SCORE:
            found.append((i, j, CLASSES[best], score))
        i = j + 1
    return found


def span_scores(rows, classes, starts, ends, thresholds=THRESHOLDS):
    """The seconds the phone would cut, the seconds of those that are really ads, and the seconds
    of real ads, as (cut, right, real). classes holds the true class index of every line, or None
    where the labels are unsure."""
    cut = right = 0.0
    for first, last, sort, _ in decode(rows, starts, ends, thresholds):
        if sort not in SKIPPED_SORTS:
            continue
        for k in range(first, last + 1):
            seconds = ends[k] - starts[k]
            cut += seconds
            if classes[k] is not None and CLASSES[classes[k]] in SKIPPED_SORTS:
                right += seconds
    real = sum(ends[k] - starts[k] for k, c in enumerate(classes)
               if c is not None and CLASSES[c] in SKIPPED_SORTS)
    return cut, right, real
