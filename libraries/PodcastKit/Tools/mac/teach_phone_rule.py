"""Says why the phone would refuse a model file, by the same rules as `init?(data:)` in
AdWordModel.swift (PodcastAds). Versions 1 and 2 are taken. Standard library only. Change nothing here without changing it there.

The teaching run must never publish a model the phone silently drops, so teach_publish.py asks
`refusals` before it copies ad-model.json. JSON can hold odd values (a string where a number
belongs, NaN, a boolean); they are refused with a reason, never a crash.

Run the tests: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import math

from teach_features import CLASSES, bucket, softmax_of

MIN_BUCKETS = 1024
MAX_BUCKETS = 4194304
MAX_WEIGHT = 1000000
DEFAULTS = {"start": 0.6, "stay": 0.4, "sure": 0.85}


def is_int(value):
    return isinstance(value, int) and not isinstance(value, bool)


def is_number(value):
    """A finite JSON number (a boolean or a string is not one)."""
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return False
    try:
        return math.isfinite(value)
    except OverflowError:
        return False


def threshold_reasons(file):
    given = file.get("thresholds")
    if given is None:
        given = {}
    if not isinstance(given, dict):
        return ["its thresholds are not a list of named numbers"]
    reasons = []
    cutoffs = dict(DEFAULTS)
    for name, value in given.items():
        if not is_number(value) or not 0 <= value <= 1:
            reasons.append("its threshold %s is not a number from 0 to 1" % name)
        elif name in cutoffs:
            cutoffs[name] = value
    if reasons:
        return reasons
    if cutoffs["start"] < 0.5:
        reasons.append("its start threshold is below 0.5")
    if cutoffs["stay"] > cutoffs["start"]:
        reasons.append("its stay threshold is above its start threshold")
    return reasons


def weight_reasons(file, size):
    """The reasons the weights are refused, and the table (bucket number to row) when there are
    none."""
    weights = file.get("weights")
    if not isinstance(weights, dict) or not weights:
        return ["it has no weights"], None
    table = {}
    for key, row in weights.items():
        digits = bool(key) and all("0" <= c <= "9" for c in key)
        if not digits or int(key) >= size:
            return ["a weights key (%.30s) is not a bucket number below %d" % (key, size)], None
        if not isinstance(row, list) or len(row) != len(CLASSES) \
                or not all(is_number(v) and abs(v) <= MAX_WEIGHT for v in row):
            return ["the weights row for bucket %s is not five numbers within plus or minus %d"
                    % (key, MAX_WEIGHT)], None
        table[int(key)] = row
    return [], table


def refusals(value):
    """The plain reasons the phone would refuse this parsed model file; an empty list when it
    would take it."""
    if not isinstance(value, dict):
        return ["it is not an object"]
    reasons = []
    if not is_int(value.get("version")) or value["version"] not in (1, 2):
        reasons.append("its version is not 1 or 2")
    size = value.get("buckets")
    sized = is_int(size) and MIN_BUCKETS <= size <= MAX_BUCKETS
    if not sized:
        reasons.append("its bucket count is not a whole number from %d to %d"
                       % (MIN_BUCKETS, MAX_BUCKETS))
    if value.get("classes") != CLASSES:
        reasons.append("its classes are not %s in that order" % ", ".join(CLASSES))
    reasons += threshold_reasons(value)
    if not sized:
        return reasons
    problems, table = weight_reasons(value, size)
    reasons += problems
    if table is not None:
        plain = softmax_of([bucket("#bias", size)], table)[0]
        if plain < 0.5:
            reasons.append("its bias alone does not call a line plain talk (%.0f%% plain, at "
                           "least 50%% is needed)" % (plain * 100))
    return reasons
