#!/usr/bin/env python3
"""Check engines against human ratings: EmoBank's fiction sentences.

EmoBank (Buechel & Hahn 2017, CC-BY-SA 4.0, github.com/JULIELab/EmoBank) has
about 10,000 English sentences, each rated by several people for valence
(unpleasant 1 to pleasant 5) and arousal (calm 1 to excited 5). Its 2,753
fiction sentences come from seven stories, in order, so each can be read the
way the app reads a book: the rated sentence last, after the sentences
before it. This is an outside check that does not rest on Claude's labels.

    # 1. windows (keep the data out of git: it lives in Tools/data/work)
    python3 -I Tools/eval/emobank.py windows DIR_WITH_emobank.csv_AND_meta.tsv > Tools/data/work/emobank-windows.jsonl
    # 2. readings, with any engine
    .build/release/lofi-eval run --engine embed:Models/LofiMood-embed-word-7.json --in Tools/data/work/emobank-windows.jsonl --out R.jsonl
    # 3. scores
    python3 -I Tools/eval/emobank.py score DIR READINGS.jsonl [READINGS2.jsonl ...]

Scores: Spearman correlation of each engine's valence and arousal with the
people's, with 95% intervals from resampling whole stories; and, on the
sentences people clearly rated (valence at most 2.4 or at least 3.6),
whether the engine's mood falls on the same side (pleasant moods: cozy,
playful, hopeful, romantic, dreamy, adventurous; unpleasant: melancholy,
tense, somber). Standard library only.
"""
from __future__ import annotations

import argparse
import csv
import json
import random
import sys

PLEASANT = {"cozy", "playful", "hopeful", "romantic", "dreamy", "adventurous"}
UNPLEASANT = {"melancholy", "tense", "somber"}


def fiction(folder: str) -> dict[str, list[dict]]:
    meta = {r["id"]: r for r in csv.DictReader(open(f"{folder}/meta.tsv", encoding="utf-8"), delimiter="\t")}
    docs: dict[str, list[dict]] = {}
    for r in csv.DictReader(open(f"{folder}/emobank.csv", encoding="utf-8")):
        m = meta.get(r["id"])
        if not m or m.get("category") != "fiction":
            continue
        parts = r["id"].rsplit("_", 2)
        start = int(parts[1]) if len(parts) == 3 and parts[1].isdigit() else 0
        docs.setdefault(m["document"], []).append({"id": r["id"], "start": start, "text": r["text"].strip(),
                                                   "V": float(r["V"]), "A": float(r["A"])})
    for rows in docs.values():
        rows.sort(key=lambda x: x["start"])
    return docs


def windows(folder: str, context_words: int) -> None:
    for doc, rows in sorted(fiction(folder).items()):
        for i, row in enumerate(rows):
            lines = [row["text"]]
            words = len(row["text"].split())
            j = i - 1
            while j >= 0 and words < context_words:
                lines.insert(0, rows[j]["text"])
                words += len(rows[j]["text"].split())
                j -= 1
            print(json.dumps({
                "id": "emobank:" + row["id"], "book": "emobank-" + doc, "chapter": 0, "sentence": i, "global": i,
                "book_fraction": i / max(1, len(rows) - 1), "trigger": "sample", "words": words, "truncated": j >= 0,
                "chapters": [lines], "text": " ".join(lines),
            }))


def ranks(values: list[float]) -> list[float]:
    order = sorted(range(len(values)), key=lambda i: values[i])
    out = [0.0] * len(values)
    i = 0
    while i < len(order):
        j = i
        while j + 1 < len(order) and values[order[j + 1]] == values[order[i]]:
            j += 1
        for k in range(i, j + 1):
            out[order[k]] = (i + j) / 2
        i = j + 1
    return out


def pearson(x: list[float], y: list[float]) -> float:
    n = len(x)
    if n < 3:
        return float("nan")
    mx, my = sum(x) / n, sum(y) / n
    sxy = sum((a - mx) * (b - my) for a, b in zip(x, y))
    sxx = sum((a - mx) ** 2 for a in x)
    syy = sum((b - my) ** 2 for b in y)
    return sxy / (sxx * syy) ** 0.5 if sxx > 0 and syy > 0 else float("nan")


def spearman(x: list[float], y: list[float]) -> float:
    return pearson(ranks(x), ranks(y))


def score(folder: str, files: list[str], boot: int) -> None:
    gold = {"emobank:" + r["id"]: (doc, r) for doc, rows in fiction(folder).items() for r in rows}
    docs = sorted({d for d, _ in gold.values()})
    rng = random.Random(7)
    samples = [[rng.choice(docs) for _ in docs] for _ in range(boot)]
    print(f"# EmoBank fiction: {len(gold)} sentences in {len(docs)} stories; intervals: 95%, {boot} story resamples")
    for path in files:
        by_doc: dict[str, list[tuple[float, float, float, float, str]]] = {d: [] for d in docs}
        engine = path
        for line in open(path, encoding="utf-8"):
            r = json.loads(line)
            if r.get("id") not in gold or r.get("bucket") is None:
                continue
            engine = r.get("engine", engine)
            doc, g = gold[r["id"]]
            by_doc[doc].append((g["V"], g["A"], r.get("valence") or 0.0, r.get("arousal") or 0.0, r["bucket"]))

        def stats(sample: list[str]) -> tuple[float, float, float]:
            rows = [x for d in sample for x in by_doc[d]]
            v = spearman([x[0] for x in rows], [x[2] for x in rows])
            a = spearman([x[1] for x in rows], [x[3] for x in rows])
            clear = [x for x in rows if (x[0] <= 2.4 or x[0] >= 3.6) and (x[4] in PLEASANT or x[4] in UNPLEASANT)]
            side = sum(1 for x in clear if (x[0] >= 3.6) == (x[4] in PLEASANT)) / len(clear) if clear else float("nan")
            return v, a, side

        point = stats(docs)
        bs = [stats(s) for s in samples]

        def iv(k: int) -> str:
            vals = sorted(b[k] for b in bs if b[k] == b[k])
            if not vals:
                return "n/a"
            lo, hi = vals[int(0.025 * len(vals))], vals[int(0.975 * len(vals)) - 1]
            return f"{lo:.1%} to {hi:.1%}" if k == 2 else f"{lo:.2f} to {hi:.2f}"

        n = sum(len(v) for v in by_doc.values())
        clear_n = sum(1 for v in by_doc.values() for x in v if (x[0] <= 2.4 or x[0] >= 3.6))
        print(f"  {engine}: {n} readings")
        print(f"    valence vs people: Spearman {point[0]:.2f} ({iv(0)})")
        print(f"    arousal vs people: Spearman {point[1]:.2f} ({iv(1)})")
        print(f"    clearly pleasant or unpleasant sentences ({clear_n}), mood on the same side when it takes one: {point[2]:.1%} ({iv(2)})")


def main() -> None:
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    w = sub.add_parser("windows")
    w.add_argument("folder")
    w.add_argument("--context-words", type=int, default=120)
    s = sub.add_parser("score")
    s.add_argument("folder")
    s.add_argument("readings", nargs="+")
    s.add_argument("--boot", type=int, default=1000)
    args = ap.parse_args()
    if args.cmd == "windows":
        windows(args.folder, args.context_words)
    else:
        score(args.folder, args.readings, args.boot)


if __name__ == "__main__":
    sys.exit(main())
