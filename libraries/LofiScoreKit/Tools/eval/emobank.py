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
    # every sentence with its genre and ratings, for `lofi-train people`,
    # which learns from the non-fiction ones only
    python3 -I Tools/eval/emobank.py people DIR > Tools/data/work/emobank-people.jsonl

Scores, on the sentences every given engine read: Spearman correlation of
each engine's valence and arousal with the people's; and on the sentences
people clearly rated (valence at most 2.4 or at least 3.6), how many get a
mood on the right side (pleasant: cozy, playful, hopeful, romantic, dreamy,
adventurous; unpleasant: melancholy, tense, somber; calm and mysterious take
no side and count as misses), how many get a side at all, and how often a
side is right when one is taken. The last flatters an engine that rarely
takes a side, so compare engines on the first. 95% intervals resample whole
stories; with several files, each is also compared with the first, paired.
Standard library only.
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


def people(folder: str) -> None:
    meta = {r["id"]: r for r in csv.DictReader(open(f"{folder}/meta.tsv", encoding="utf-8"), delimiter="\t")}
    for r in csv.DictReader(open(f"{folder}/emobank.csv", encoding="utf-8")):
        m = meta.get(r["id"])
        if not m or not r["text"].strip():
            continue
        print(json.dumps({"id": r["id"], "doc": m.get("document") or r["id"], "category": m.get("category") or "",
                          "v": float(r["V"]), "a": float(r["A"]), "text": r["text"].strip()}))


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
    readings: list[tuple[str, dict[str, dict]]] = []
    for path in files:
        engine, rows = path, {}
        for line in open(path, encoding="utf-8"):
            r = json.loads(line)
            if r.get("id") in gold and r.get("bucket") is not None:
                engine = r.get("engine", engine)
                rows[r["id"]] = r
        readings.append((engine, rows))
    # Score every engine on the sentences all of them read, so differences are paired.
    common = set(gold)
    for _, rows in readings:
        common &= set(rows)
    by_doc = {d: sorted(i for i in common if gold[i][0] == d) for d in docs}
    rng = random.Random(7)
    samples = [[rng.choice(docs) for _ in docs] for _ in range(boot)]

    def side(bucket: str) -> int:
        return 1 if bucket in PLEASANT else -1 if bucket in UNPLEASANT else 0

    def stats(rows: dict[str, dict], sample: list[str]) -> tuple[float, float, float, float, float]:
        ids = [i for d in sample for i in by_doc[d]]
        v = spearman([gold[i][1]["V"] for i in ids], [rows[i].get("valence") or 0.0 for i in ids])
        a = spearman([gold[i][1]["A"] for i in ids], [rows[i].get("arousal") or 0.0 for i in ids])
        clear = [i for i in ids if gold[i][1]["V"] <= 2.4 or gold[i][1]["V"] >= 3.6]
        want = {i: 1 if gold[i][1]["V"] >= 3.6 else -1 for i in clear}
        sided = [i for i in clear if side(rows[i]["bucket"]) != 0]
        right = sum(1 for i in sided if side(rows[i]["bucket"]) == want[i])
        n = max(1, len(clear))
        return v, a, right / n, len(sided) / n, (right / len(sided) if sided else float("nan"))

    names = ["valence rho", "arousal rho", "clear sentences on the right side", "clear sentences given a side", "right when it takes a side"]
    percent = [False, False, True, True, True]

    def fmt(k: int, x: float) -> str:
        return f"{x:.1%}" if percent[k] else f"{x:.2f}"

    def interval(values: list[float], k: int, signed: bool = False) -> str:
        vals = sorted(x for x in values if x == x)
        if not vals:
            return "n/a"
        lo, hi = vals[int(0.025 * len(vals))], vals[int(0.975 * len(vals)) - 1]
        if signed:
            return (f"{lo * 100:+.1f} to {hi * 100:+.1f} points" if percent[k] else f"{lo:+.2f} to {hi:+.2f}")
        return f"{fmt(k, lo)} to {fmt(k, hi)}"

    clear_n = sum(1 for i in common if gold[i][1]["V"] <= 2.4 or gold[i][1]["V"] >= 3.6)
    print(f"# EmoBank fiction: {len(common)} sentences all engines read, in {len(docs)} stories ({clear_n} clearly pleasant or unpleasant to people)")
    print(f"# intervals: 95%, {boot} story resamples. Pleasant moods: {', '.join(sorted(PLEASANT))}; unpleasant: {', '.join(sorted(UNPLEASANT))}; calm and mysterious take no side.")
    boots = []
    for engine, rows in readings:
        point = stats(rows, docs)
        bs = [stats(rows, smp) for smp in samples]
        boots.append((engine, point, bs))
        print(f"  {engine}")
        for k, name in enumerate(names):
            print(f"    {name}: {fmt(k, point[k])} ({interval([b[k] for b in bs], k)})")
    if len(boots) > 1:
        base, bpoint, bbs = boots[0]
        print(f"\n## Paired differences from {base}")
        for engine, point, bs in boots[1:]:
            parts = []
            for k in (0, 1, 2):
                d = point[k] - bpoint[k]
                diffs = [x[k] - y[k] for x, y in zip(bs, bbs)]
                shown = f"{d * 100:+.1f} points" if percent[k] else f"{d:+.2f}"
                parts.append(f"{names[k]} {shown} ({interval(diffs, k, signed=True)})")
            print(f"  {engine}: " + ";  ".join(parts))
        print("  (an interval that includes 0 means the difference could be luck)")


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
    p = sub.add_parser("people")
    p.add_argument("folder")
    args = ap.parse_args()
    if args.cmd == "windows":
        windows(args.folder, args.context_words)
    elif args.cmd == "people":
        people(args.folder)
    else:
        score(args.folder, args.readings, args.boot)


if __name__ == "__main__":
    sys.exit(main())
