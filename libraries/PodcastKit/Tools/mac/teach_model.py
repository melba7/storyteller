"""The model file of the teaching run: which buckets are kept and the text of ad-model.json.

Standard library only. Used by teach_train.py (which re-exports these names).

Version 1 files have 262144 buckets and at most 40000 rows. Version 2 files (the word pairs of the
neighbouring lines as features, see teach_features.py) have 4194304 buckets and at most 80000 rows.

Run the tests: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import json
import os
import tempfile

from teach_features import BUCKETS, CLASSES, bucket
from teach_spans import THRESHOLDS  # the cut-offs the file carries are the ones the check uses

MAX_BUCKETS = 40000
MAX_BUCKETS_V2 = 80000
MAX_BYTES = 4500000
# The bias bucket (every line has it) holds [BIAS_NONE, 0, 0, 0, 0] and training never moves it: a
# line with no known words is plain talk, and the phone refuses a model whose bias alone says
# otherwise. A word that hashes to the same bucket cannot be learned.
BIAS_BUCKET = bucket("#bias")
BIAS_NONE = 5.0


def ranked_buckets(flat, limit, size=BUCKETS):
    """[(bucket, five rounded weights)] with the biggest weights first, at most `limit`, leaving
    out buckets whose rounded weights are all zero. The bias bucket always comes first, so it is
    always kept."""
    found = []
    for b in range(size):
        k = b * 5
        if flat[k] or flat[k + 1] or flat[k + 2] or flat[k + 3] or flat[k + 4]:
            five = [round(flat[k + c], 4) + 0.0 for c in range(5)]
            if any(five):
                found.append((b, five))
    found.sort(key=lambda item: (-max(abs(v) for v in item[1]), item[0]))
    bias = bucket("#bias", size)
    found.sort(key=lambda item: item[0] != bias)
    return found[:limit]


def build_model(flat, trained, check, max_buckets=MAX_BUCKETS, max_bytes=MAX_BYTES, version=1,
                size=BUCKETS):
    """The text of ad-model.json. `check(weights)` returns the heldOut numbers for the weights that
    are kept. When the text would pass max_bytes, fewer buckets are kept."""
    ranked = ranked_buckets(flat, max_buckets, size)

    def render(count, held=None):
        kept = dict(sorted(ranked[:count]))
        data = {"version": version, "buckets": size, "classes": CLASSES, "thresholds": THRESHOLDS,
                "weights": {str(b): five for b, five in kept.items()},
                "trained": dict(trained, heldOut=check(kept) if held is None else held)}
        return json.dumps(data, separators=(",", ":"))

    def fits(text):
        return len(text.encode("utf-8")) <= max_bytes

    text = render(len(ranked))
    if fits(text):
        return text
    # The size is judged with the check of the full set (the check scores the shelf, which takes
    # a while); the numbers of the check hardly change its length.
    held = json.loads(text)["trained"]["heldOut"]
    low, high = 0, len(ranked) - 1
    while low < high:
        middle = (low + high + 1) // 2
        if fits(render(middle, held)):
            low = middle
        else:
            high = middle - 1
    text = render(low)
    while low > 0 and not fits(text):
        low -= 1
        text = render(low)
    return text


def write_text(path, text):
    """Writes the text through a temporary file in the same folder."""
    handle, temporary = tempfile.mkstemp(dir=os.path.dirname(path), prefix=".", suffix=".part")
    try:
        with os.fdopen(handle, "w", encoding="utf-8") as f:
            f.write(text)
            f.flush()
            os.fsync(f.fileno())
        os.replace(temporary, path)
    except BaseException:
        if os.path.exists(temporary):
            os.remove(temporary)
        raise
