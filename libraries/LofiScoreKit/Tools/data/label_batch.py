#!/usr/bin/env python3
"""Show windows for labelling and save labels, one book at a time.

    python3 -I Tools/data/label_batch.py show WINDOWS.jsonl BOOK [--words 150]
    python3 -I Tools/data/label_batch.py save WINDOWS.jsonl BOOK LABELS.jsonl LABELLER "1 calm, 2 tense, ..."

`show` numbers the book's windows and prints the last N words of each (the
part the listener is hearing now). `save` maps those numbers back to window
ids and appends {id, bucket, labeller} lines, replacing earlier labels for the
same ids by the same labeller.
"""
import json
import sys

BUCKETS = {"calm", "cozy", "playful", "hopeful", "melancholy", "mysterious", "tense", "somber"}


def windows_for(path, book):
    rows = [json.loads(l) for l in open(path) if l.strip()]
    return [r for r in rows if r["book"] == book]


def tail(record, words):
    parts = []
    for k, chapter in enumerate(record["chapters"]):
        if k:
            parts.append("¶¶")
        parts.extend(" ".join(chapter).split())
    cut = parts[-words:]
    return ("… " if len(parts) > words else "") + " ".join(cut)


def main():
    cmd, path, book = sys.argv[1:4]
    rows = windows_for(path, book)
    if cmd == "show":
        words = int(sys.argv[sys.argv.index("--words") + 1]) if "--words" in sys.argv else 150
        for n, r in enumerate(rows, 1):
            print(f"[{n}] {tail(r, words)}\n")
    elif cmd == "save":
        out, labeller, spec = sys.argv[4], sys.argv[5], sys.argv[6]
        labels = {}
        for item in spec.replace("\n", ",").split(","):
            if not item.strip():
                continue
            n, bucket = item.split()
            if bucket not in BUCKETS:
                sys.exit(f"unknown bucket {bucket}")
            labels[rows[int(n) - 1]["id"]] = bucket
        if len(labels) != len(rows):
            missing = [n for n, r in enumerate(rows, 1) if r["id"] not in labels]
            sys.exit(f"{book}: {len(rows) - len(labels)} windows unlabelled: {missing}")
        try:
            existing = [json.loads(l) for l in open(out) if l.strip()]
        except FileNotFoundError:
            existing = []
        kept = [e for e in existing if not (e["id"] in labels and e.get("labeller") == labeller)]
        with open(out, "w") as f:
            for e in kept:
                f.write(json.dumps(e, sort_keys=True) + "\n")
            for i, b in labels.items():
                f.write(json.dumps({"id": i, "bucket": b, "labeller": labeller}, sort_keys=True) + "\n")
        print(f"{book}: saved {len(labels)} labels")


if __name__ == "__main__":
    main()
