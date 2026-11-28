"""Mo's bar in Python, for tools that replay a score dump (`podcast-teach score --dump`). It is
the same rule as AdBar.swift: marked stretches within 1 second of each other are one break, only
breaks of 10 seconds or more count, and a break passes when at most 5 seconds of it are heard and
the skips cut at most 5 seconds of show before it and after it. A skip that touches no marked ad
and cuts more than half a second of show is a skip with no ad.

Standard library only. Stretches are (start, end) pairs in seconds.

Run the tests: python3 -m pytest test_teach_bar.py -q"""
HEARD = 5.0
CUT = 5.0
JOIN = 1.0
SHORTEST = 10.0
NO_AD = 0.5
SLACK = 1e-9


def overlap(a, b):
    return max(0.0, min(a[1], b[1]) - max(a[0], b[0]))


def clipped(spans, duration):
    out = []
    for start, end in spans:
        start, end = max(start, 0.0), min(end, duration)
        if end > start:
            out.append((start, end))
    return out


def join(spans, gap):
    joined = []
    for start, end in sorted(spans):
        if joined and start <= joined[-1][1] + gap:
            joined[-1] = (joined[-1][0], max(joined[-1][1], end))
        else:
            joined.append((start, end))
    return joined


def outside(span, others):
    """The parts of `span` that no stretch of `others` (sorted, apart) covers."""
    parts, start = [], span[0]
    for other in others:
        if other[1] > start and other[0] < span[1]:
            if other[0] > start:
                parts.append((start, other[0]))
            start = max(start, other[1])
    if start < span[1]:
        parts.append((start, span[1]))
    return parts


def cause_of(span, skips, marked):
    """The first cause that fails the break, or None when it passes."""
    reaching = [s for s in skips if overlap(s, span) > 0]
    if not reaching:
        return "missed"
    heard = span[1] - span[0] - sum(overlap(s, span) for s in reaching)
    late = max(0.0, reaching[0][0] - span[0])
    early_stop = max(0.0, span[1] - reaching[-1][1])
    before = after = 0.0
    for skip in reaching:
        for part in outside(skip, marked):
            if part[1] <= span[0] + SLACK:
                before += part[1] - part[0]
            elif part[0] >= span[1] - SLACK:
                after += part[1] - part[0]
    if late > HEARD + SLACK:
        return "startsLate"
    if early_stop > HEARD + SLACK:
        return "stopsEarly"
    if heard > HEARD + SLACK:
        between = heard - late - early_stop
        return "gapInside" if between > SLACK else ("startsLate" if late >= early_stop else "stopsEarly")
    if before > CUT + SLACK:
        return "startsEarly"
    if after > CUT + SLACK:
        return "landsTooFar"
    return None


def score(truth, maybe, skips, duration):
    """{"breaks", "passed", "causes", "noAdSkips"} for one episode. `truth` are the counted ads,
    `maybe` the neutral stretches, `skips` what the phone would skip."""
    counted = clipped(truth, duration)
    skips = join(clipped(skips, duration), 0)
    marked = join(counted + clipped(maybe, duration), 0)
    total = {"breaks": 0, "passed": 0, "causes": {}, "noAdSkips": 0}
    for span in join(counted, JOIN):
        if span[1] - span[0] < SHORTEST - SLACK:
            continue
        total["breaks"] += 1
        cause = cause_of(span, skips, marked)
        if cause is None:
            total["passed"] += 1
        else:
            total["causes"][cause] = total["causes"].get(cause, 0) + 1
    for skip in skips:
        if not any(overlap(c, skip) > 0 for c in counted):
            if sum(b - a for a, b in outside(skip, marked)) > NO_AD:
                total["noAdSkips"] += 1
    return total
