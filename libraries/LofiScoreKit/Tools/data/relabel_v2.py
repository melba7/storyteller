#!/usr/bin/env python3
"""Carry labels over to guidelines v2 (11 moods), re-judging only some windows.

    python3 -I Tools/data/relabel_v2.py OLD_LABELS.jsonl[,MORE.jsonl] OVERRIDES.json OUT.jsonl [--books a,b,...] [--exclude-books a,b,...]

Guidelines v2 only carve three new moods (romantic, dreamy, adventurous) out
of the old eight; every other definition is unchanged. So a v1 label stays
right under v2 unless the window belongs to a new mood. The windows that
might were picked by keyword (the new moods' lexicon cues in the last 80
words) or by a v1 label of hopeful (which lost "love declared"), re-read under
v2, and changed where a new mood clearly fits. OVERRIDES maps window id to
its v2 bucket for those changes. Every output line has labeller "claude-g2".
Several label files can be given, comma-separated; they are read in order.
"""
import json
import sys

BUCKETS = {"calm", "cozy", "playful", "hopeful", "melancholy", "mysterious", "tense", "somber",
           "romantic", "dreamy", "adventurous"}


def main():
    old_path, overrides_path, out_path = sys.argv[1:4]
    books = exclude = None
    if "--books" in sys.argv:
        books = set(sys.argv[sys.argv.index("--books") + 1].split(","))
    if "--exclude-books" in sys.argv:
        exclude = set(sys.argv[sys.argv.index("--exclude-books") + 1].split(","))
    overrides = json.load(open(overrides_path))
    bad = {k: v for k, v in overrides.items() if v not in BUCKETS}
    if bad:
        sys.exit(f"unknown buckets: {bad}")
    out, used = [], set()
    lines = [line for path in old_path.split(",") for line in open(path)]
    for line in lines:
        if not line.strip():
            continue
        row = json.loads(line)
        if row["id"] in used:
            sys.exit(f"window {row['id']} is labelled twice")
        book = row["id"].split(":")[0]
        if books is not None and book not in books:
            continue
        if exclude is not None and book in exclude:
            continue
        bucket = overrides.get(row["id"], row["bucket"])
        used.add(row["id"])
        out.append({"id": row["id"], "bucket": bucket, "labeller": "claude-g2"})
    missing = set(overrides) - used
    if missing:
        sys.exit(f"overrides for windows not in the input: {sorted(missing)[:5]}")
    with open(out_path, "w") as f:
        for row in out:
            f.write(json.dumps(row, sort_keys=True) + "\n")
    changed = sum(1 for row in out if row["id"] in overrides)
    print(f"{out_path}: {len(out)} labels, {changed} changed to a v2 mood")


if __name__ == "__main__":
    main()
