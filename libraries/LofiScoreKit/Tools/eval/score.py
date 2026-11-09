#!/usr/bin/env python3
"""Score mood engines: agreement with labels, latency, stability and plot-knowledge drift.

Inputs are the JSON-lines files `lofi-eval` writes:

  windows   lofi-eval windows ...           (id, book, book_fraction, trigger, seconds, ...)
  readings  lofi-eval run --engine X ...    (id, engine, bucket, valence, arousal, confidence, latency_ms)
  labels    gold or Claude labels           (id, bucket[, valence, arousal, labeller])

    python3 -I Tools/eval/score.py --windows w.jsonl --labels gold.jsonl readings/*.jsonl
    python3 -I Tools/eval/score.py --windows w.jsonl --drift fm.jsonl --against fast.jsonl
    python3 -I Tools/eval/score.py --windows w.jsonl --masked-pair fm.jsonl fm.masked.jsonl
    python3 -I Tools/eval/score.py --windows playback.jsonl --director readings/*.jsonl

Standard library only, so it runs with the python3 that ships with Xcode.
"""
from __future__ import annotations

import argparse
import collections
import csv
import json
import math
import pathlib
import statistics
import sys

BUCKETS = ["calm", "cozy", "playful", "hopeful", "melancholy", "mysterious", "tense", "somber"]
# Kept in step with MoodBucket.anchor in LofiScoreCore.
ANCHORS = {
    "calm": (0.25, 0.15),
    "cozy": (0.55, 0.30),
    "playful": (0.60, 0.62),
    "hopeful": (0.70, 0.82),
    "melancholy": (-0.50, 0.20),
    "mysterious": (-0.10, 0.50),
    "tense": (-0.55, 0.85),
    "somber": (-0.70, 0.45),
}
DARK = {"melancholy", "mysterious", "tense", "somber"}
BOOKS_CSV = pathlib.Path(__file__).resolve().parent.parent / "data" / "books.csv"


def distance(a: tuple[float, float], b: tuple[float, float]) -> float:
    # Same metric as MoodPoint.distance(to:): arousal differences count double.
    return math.hypot(a[0] - b[0], 2 * (a[1] - b[1]))


def nearest(point: tuple[float, float]) -> str:
    return min(BUCKETS, key=lambda b: distance(point, ANCHORS[b]))


def load(path: str) -> list[dict]:
    with open(path) as f:
        return [json.loads(line) for line in f if line.strip()]


def by_id(rows: list[dict]) -> dict[str, dict]:
    return {r["id"]: r for r in rows}


def book_groups() -> dict[str, str]:
    if not BOOKS_CSV.exists():
        return {}
    with open(BOOKS_CSV, newline="") as f:
        return {row["slug"]: row["group"] for row in csv.DictReader(f)}


def pct(x: float) -> str:
    return f"{100 * x:5.1f}%"


def percentile(values: list[float], q: float) -> float:
    if not values:
        return float("nan")
    values = sorted(values)
    return values[min(len(values) - 1, int(q * len(values)))]


# ---------------------------------------------------------------------------
# Agreement
# ---------------------------------------------------------------------------


def agreement(labels: dict[str, dict], readings: dict[str, dict]) -> dict:
    pairs = [(labels[i]["bucket"], r["bucket"]) for i, r in readings.items() if i in labels and r.get("bucket")]
    n = len(pairs)
    if n == 0:
        return {"n": 0}
    exact = sum(1 for g, p in pairs if g == p) / n
    # "Close": the predicted anchor is within 0.45 of the gold anchor (e.g. calm/cozy, tense/somber).
    close = sum(1 for g, p in pairs if distance(ANCHORS[g], ANCHORS[p]) <= 0.45) / n
    f1s = []
    for b in BUCKETS:
        tp = sum(1 for g, p in pairs if g == b and p == b)
        fp = sum(1 for g, p in pairs if g != b and p == b)
        fn = sum(1 for g, p in pairs if g == b and p != b)
        if tp + fp + fn == 0:
            continue
        f1s.append(2 * tp / (2 * tp + fp + fn))
    gold_counts = collections.Counter(g for g, _ in pairs)
    pred_counts = collections.Counter(p for _, p in pairs)
    expected = sum(gold_counts[b] * pred_counts[b] for b in BUCKETS) / (n * n)
    kappa = (exact - expected) / (1 - expected) if expected < 1 else 1.0
    # The director picks the bucket nearest the smoothed (valence, arousal), so score that too.
    point_pairs = [
        (labels[i]["bucket"], nearest((r["valence"], r["arousal"])))
        for i, r in readings.items()
        if i in labels and r.get("valence") is not None
    ]
    by_point = sum(1 for g, p in point_pairs if g == p) / len(point_pairs) if point_pairs else float("nan")
    confusion = collections.Counter(pairs)
    return {"n": n, "exact": exact, "close": close, "macro_f1": sum(f1s) / len(f1s), "kappa": kappa,
            "by_point": by_point, "confusion": confusion}


def print_confusion(confusion: collections.Counter) -> None:
    short = [b[:5] for b in BUCKETS]
    print("      gold \\ engine " + " ".join(f"{s:>6}" for s in short))
    for g in BUCKETS:
        row = [confusion.get((g, p), 0) for p in BUCKETS]
        if sum(row):
            print(f"      {g:>17} " + " ".join(f"{c:6d}" for c in row))


# ---------------------------------------------------------------------------
# Reference director (the plan's rules; the real one lives in the audio target)
# ---------------------------------------------------------------------------


def direct(observations: list[tuple[float, str, dict]], tau: float = 60.0, dwell: float = 90.0,
           jump_confidence: float = 0.8, jump_distance: float = 0.6) -> list[tuple[float, str]]:
    """observations: (seconds, trigger, reading) in playback order.
    Returns the music changes as (seconds, bucket), the first entry being the opening track."""
    changes: list[tuple[float, str]] = []
    point = None
    playing = None
    candidate, count = None, 0
    last_t = last_change = 0.0
    for t, trigger, r in observations:
        if not r.get("bucket"):
            continue
        rp = (r["valence"], r["arousal"])
        if point is None or trigger in ("start", "seek"):
            point = rp
        else:
            alpha = 1 - math.exp(-max(0.0, t - last_t) / tau)
            point = (point[0] + alpha * (rp[0] - point[0]), point[1] + alpha * (rp[1] - point[1]))
        last_t = t
        if playing is None:
            playing, last_change = nearest(point), t
            changes.append((t, playing))
            continue
        target = nearest(point)
        if r["confidence"] >= jump_confidence and distance(rp, ANCHORS[playing]) >= jump_distance and r["bucket"] != playing:
            target, point, count, candidate = r["bucket"], rp, 2, r["bucket"]
        elif target == playing:
            candidate, count = None, 0
            continue
        elif target == candidate:
            count += 1
        else:
            candidate, count = target, 1
        exempt = trigger in ("chapterStart", "seek")
        if count >= 2 and (exempt or t - last_change >= dwell):
            playing, last_change, candidate, count = target, t, None, 0
            changes.append((t, playing))
    return changes


# ---------------------------------------------------------------------------
# Reports
# ---------------------------------------------------------------------------


def report_engines(windows: dict[str, dict], labels: dict[str, dict] | None, files: list[str], confusion: bool) -> None:
    print("\n## Engines\n")
    for path in files:
        # Only the windows named by --windows count, so a reading file that also
        # covers training windows is scored on the held-out ones alone.
        rows = [r for r in load(path) if r["id"] in windows]
        readings = by_id(rows)
        ok = [r for r in rows if r.get("bucket")]
        engine = rows[0]["engine"] if rows else path
        lat = [r["latency_ms"] for r in ok]
        dist = collections.Counter(r["bucket"] for r in ok)
        print(f"### {engine}  ({path})")
        print(f"  readings {len(ok)}/{len(rows)}  failures {len(rows) - len(ok)}  "
              f"latency p50 {percentile(lat, 0.5):.1f} ms  p95 {percentile(lat, 0.95):.1f} ms")
        print("  buckets  " + ", ".join(f"{b} {pct(dist[b] / max(1, len(ok))).strip()}" for b in BUCKETS if dist[b]))
        if labels:
            a = agreement(labels, readings)
            if a["n"]:
                print(f"  vs labels (n={a['n']}): exact {pct(a['exact'])}  close {pct(a['close'])}  "
                      f"macro-F1 {a['macro_f1']:.3f}  kappa {a['kappa']:.3f}  nearest-point {pct(a['by_point'])}")
                if confusion:
                    print_confusion(a["confusion"])
        print()


def report_pairwise(files: list[str]) -> None:
    if len(files) < 2:
        return
    print("## Pairwise agreement\n")
    loaded = [(load(p)[0]["engine"] if load(p) else p, by_id(load(p))) for p in files]
    for i in range(len(loaded)):
        for j in range(i + 1, len(loaded)):
            (na, a), (nb, b) = loaded[i], loaded[j]
            common = [k for k in a if k in b and a[k].get("bucket") and b[k].get("bucket")]
            if common:
                same = sum(1 for k in common if a[k]["bucket"] == b[k]["bucket"]) / len(common)
                print(f"  {na} vs {nb}: {pct(same)} of {len(common)}")
    print()


def report_director(windows: list[dict], files: list[str]) -> None:
    print("## Stability through the plan's director rules (bar: about 8 changes an hour or fewer)\n")
    order = [w for w in windows if w.get("seconds") is not None]
    if not order:
        print("  (windows have no playback times; export them without --sample)\n")
        return
    for path in files:
        readings = by_id(load(path))
        per_book = collections.defaultdict(list)
        for w in order:
            if w["id"] in readings:
                per_book[w["book"]].append((w["seconds"], w["trigger"], readings[w["id"]]))
        total_hours = total_changes = raw_changes = 0.0
        for book, obs in per_book.items():
            obs.sort(key=lambda o: o[0])
            hours = max(1e-9, (obs[-1][0] - obs[0][0]) / 3600)
            changes = direct(obs)
            buckets = [o[2].get("bucket") for o in obs if o[2].get("bucket")]
            raw_changes += sum(1 for x, y in zip(buckets, buckets[1:]) if x != y)
            total_changes += max(0, len(changes) - 1)
            total_hours += hours
        engine = next(iter(readings.values()))["engine"] if readings else path
        print(f"  {engine}: {total_changes / max(total_hours, 1e-9):5.1f} changes/hour after the director "
              f"({raw_changes / max(total_hours, 1e-9):5.1f} raw) over {total_hours:.1f} h in {len(per_book)} books")
    print()


def report_drift(windows: dict[str, dict], llm_path: str, against_path: str, early: float) -> None:
    """Ominous drift: does the LLM call early chapters of famous books darker than a
    plot-blind engine does, by more than it does for obscure books?"""
    groups = book_groups()
    llm, base = by_id(load(llm_path)), by_id(load(against_path))
    print(f"## Plot-knowledge drift (first {int(early * 100)}% of each book)\n")
    rows = {}
    for group in ("famous", "obscure"):
        ids = [i for i, w in windows.items()
               if w["book_fraction"] <= early and groups.get(w["book"]) == group
               and llm.get(i, {}).get("bucket") and base.get(i, {}).get("bucket")]
        if not ids:
            continue
        dark_llm = sum(1 for i in ids if llm[i]["bucket"] in DARK) / len(ids)
        dark_base = sum(1 for i in ids if base[i]["bucket"] in DARK) / len(ids)
        valence_gap = statistics.fmean(llm[i]["valence"] - base[i]["valence"] for i in ids)
        rows[group] = (dark_llm - dark_base, valence_gap)
        print(f"  {group:8} n={len(ids):4}  dark: llm {pct(dark_llm)} vs plot-blind {pct(dark_base)}  "
              f"mean valence gap {valence_gap:+.3f}")
    if len(rows) == 2:
        dd = rows["famous"][0] - rows["obscure"][0]
        dv = rows["famous"][1] - rows["obscure"][1]
        print(f"\n  excess darkness on famous books: {dd * 100:+.1f} points, valence {dv:+.3f}")
        print("  (near zero is good; a clearly positive darkness or negative valence gap suggests plot knowledge)")
    print()


def report_masked(windows: dict[str, dict], plain_path: str, masked_path: str) -> None:
    """Name-masking test: rename the characters and places and see whether the reading changes.
    A plot-blind reader should not care; a reader leaning on what it knows about
    Dracula will change its mind more on famous books than on obscure ones."""
    groups = book_groups()
    plain, masked = by_id(load(plain_path)), by_id(load(masked_path))
    print("## Name-masking test\n")
    for group in ("famous", "obscure"):
        ids = [i for i in plain if i in masked and plain[i].get("bucket") and masked[i].get("bucket")
               and groups.get(windows.get(i, {}).get("book", i.split(":")[0])) == group]
        if not ids:
            continue
        flips = sum(1 for i in ids if plain[i]["bucket"] != masked[i]["bucket"]) / len(ids)
        darker = sum(1 for i in ids if plain[i]["bucket"] in DARK and masked[i]["bucket"] not in DARK) / len(ids)
        print(f"  {group:8} n={len(ids):4}  label changes {pct(flips)}  dark only with real names {pct(darker)}")
    print()


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("readings", nargs="*", help="reading files from lofi-eval run")
    ap.add_argument("--windows", required=True)
    ap.add_argument("--labels", help="gold or Claude labels (id, bucket)")
    ap.add_argument("--confusion", action="store_true")
    ap.add_argument("--director", action="store_true", help="replay readings through the plan's director rules")
    ap.add_argument("--drift", help="LLM engine readings for the drift report")
    ap.add_argument("--against", help="plot-blind engine readings for the drift report")
    ap.add_argument("--early", type=float, default=0.15)
    ap.add_argument("--masked-pair", nargs=2, metavar=("PLAIN", "MASKED"))
    args = ap.parse_args()

    window_rows = load(args.windows)
    windows = by_id(window_rows)
    labels = by_id(load(args.labels)) if args.labels else None
    print(f"# Mood engine eval: {len(windows)} windows from {len({w['book'] for w in window_rows})} books"
          + (f", {len(labels)} labels" if labels else ""))
    if args.readings:
        report_engines(windows, labels, args.readings, args.confusion)
        report_pairwise(args.readings)
        if args.director:
            report_director(window_rows, args.readings)
    if args.drift and args.against:
        report_drift(windows, args.drift, args.against, args.early)
    if args.masked_pair:
        report_masked(windows, *args.masked_pair)


if __name__ == "__main__":
    sys.exit(main())
