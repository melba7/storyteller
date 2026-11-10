#!/usr/bin/env python3
"""Compare training recipes on `lofi-train oof` predictions, window by window.

Every recipe was scored on the same held-out windows (all labelled books,
rotated through cross-validation folds, repeated with different shuffles), so
differences are paired. Intervals come from resampling whole books, because
windows from one book are not independent.

    python3 -I Tools/eval/oof_compare.py oof-word.jsonl [--baseline word2-settings] [--boot 1000] [--sets SETS.jsonl]

With --sets (label files with an `accept` list, such as
claude-g2-test-sets.jsonl), it also reports "fits" (the prediction is one of
the moods that would suit the window) on the windows those files cover.

Standard library only.
"""
from __future__ import annotations

import argparse
import collections
import json
import random


def scores(pairs: list[tuple[str, str]]) -> tuple[float, float, float]:
    n = len(pairs)
    if n == 0:
        return 0.0, 0.0, 0.0
    exact = sum(g == p for g, p in pairs) / n
    gold = collections.Counter(g for g, _ in pairs)
    pred = collections.Counter(p for _, p in pairs)
    pe = sum(gold[c] * pred[c] for c in gold) / (n * n)
    kappa = (exact - pe) / (1 - pe) if pe < 1 else 0.0
    f1s = []
    for c in gold:
        tp = sum(1 for g, p in pairs if g == c and p == c)
        fp = pred[c] - tp
        fn = gold[c] - tp
        f1s.append(2 * tp / (2 * tp + fp + fn) if tp else 0.0)
    return exact, sum(f1s) / len(f1s), kappa


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("oof")
    ap.add_argument("--baseline", default="word2-settings")
    ap.add_argument("--boot", type=int, default=1000)
    ap.add_argument("--seed", type=int, default=7)
    ap.add_argument("--sets", action="append", default=[])
    args = ap.parse_args()
    accept: dict[str, set[str]] = {}
    for path in args.sets:
        for line in open(path):
            if line.strip():
                r = json.loads(line)
                accept[r["id"]] = set(r.get("accept") or []) | {r["bucket"]}
    fits_by: dict[str, dict[str, list[bool]]] = collections.defaultdict(lambda: collections.defaultdict(list))

    by_recipe_book: dict[str, dict[str, list[tuple[str, str]]]] = collections.defaultdict(lambda: collections.defaultdict(list))
    repeats = set()
    repeats_of: dict[str, set] = collections.defaultdict(set)
    for line in open(args.oof):
        r = json.loads(line)
        by_recipe_book[r["recipe"]][r["book"]].append((r["gold"], r["predicted"]))
        repeats.add(r["repeatIndex"])
        repeats_of[r["recipe"]].add(r["repeatIndex"])
        if r["id"] in accept:
            fits_by[r["recipe"]][r["book"]].append(r["predicted"] in accept[r["id"]])
    recipes = sorted(by_recipe_book, key=lambda k: (k != args.baseline, k))
    books = sorted({b for d in by_recipe_book.values() for b in d})
    windows = sum(len(v) for v in by_recipe_book[args.baseline].values()) // len(repeats_of[args.baseline])
    print(f"# {len(books)} books, {windows} windows, {len(repeats)} repeats; intervals: 95%, {args.boot} book resamples")

    def stat(recipe: str, sample: list[str]) -> tuple[float, float, float]:
        pairs = [p for b in sample for p in by_recipe_book[recipe][b]]
        return scores(pairs)

    rng = random.Random(args.seed)
    samples = [[rng.choice(books) for _ in books] for _ in range(args.boot)]
    boot = {r: [stat(r, s) for s in samples] for r in recipes}

    def interval(values: list[float]) -> tuple[float, float]:
        v = sorted(values)
        return v[int(0.025 * len(v))], v[int(0.975 * len(v)) - 1]

    names = ["exact", "macro-F1", "kappa"]
    print("\n## Each recipe (out-of-fold, all books)")
    for r in recipes:
        point = stat(r, books)
        parts = []
        for i, name in enumerate(names):
            lo, hi = interval([b[i] for b in boot[r]])
            if i == 0:
                parts.append(f"{name} {point[i] * 100:5.1f}% ({lo * 100:.1f} to {hi * 100:.1f})")
            else:
                parts.append(f"{name} {point[i]:.3f} ({lo:.3f} to {hi:.3f})")
        print(f"  {r:22} " + "   ".join(parts))

    print(f"\n## Paired differences from {args.baseline}")
    base_point = stat(args.baseline, books)
    for r in recipes:
        if r == args.baseline:
            continue
        point = stat(r, books)
        parts = []
        for i, name in enumerate(names):
            diffs = [a[i] - b[i] for a, b in zip(boot[r], boot[args.baseline])]
            lo, hi = interval(diffs)
            share = sum(d > 0 for d in diffs) / len(diffs)
            scale = 100 if i == 0 else 1
            unit = " pts" if i == 0 else ""
            fmt = "{:+.1f}" if i == 0 else "{:+.3f}"
            parts.append(f"{name} {fmt.format((point[i] - base_point[i]) * scale)}{unit} ({fmt.format(lo * scale)} to {fmt.format(hi * scale)}, better in {share:.0%} of resamples)")
        print(f"  {r}:\n      " + "\n      ".join(parts))
    print("  (an interval that excludes 0 is a real difference at the 95% level)")

    if fits_by:
        set_books = sorted({b for d in fits_by.values() for b in d})
        n_sets = sum(len(v) for v in fits_by[args.baseline].values()) // len(repeats_of[args.baseline])
        print(f"\n## Fits on the plausible sets ({n_sets} windows from {len(set_books)} books, held out in every fold)")
        set_samples = [[rng.choice(set_books) for _ in set_books] for _ in range(args.boot)]

        def fits(recipe: str, sample: list[str]) -> float:
            v = [x for b in sample for x in fits_by[recipe][b]]
            return sum(v) / len(v) if v else 0.0

        base_boot = [fits(args.baseline, s) for s in set_samples]
        for r in recipes:
            point = fits(r, set_books)
            vals = [fits(r, s) for s in set_samples]
            lo, hi = interval(vals)
            line = f"  {r:22} fits {point * 100:5.1f}% ({lo * 100:.1f} to {hi * 100:.1f})"
            if r != args.baseline:
                d = [a - b for a, b in zip(vals, base_boot)]
                dlo, dhi = interval(d)
                line += f"   vs {args.baseline}: {(point - fits(args.baseline, set_books)) * 100:+.1f} pts ({dlo * 100:+.1f} to {dhi * 100:+.1f})"
            print(line)

    print("\n## Predicted vs labelled mood counts (one repeat's worth)")
    gold = collections.Counter(g for b in books for g, _ in by_recipe_book[args.baseline][b])
    width = max(len(r) for r in recipes) + 1
    print("  mood        labels " + " ".join(f"{r:>{width}}" for r in recipes))
    counts = {r: collections.Counter(p for b in books for _, p in by_recipe_book[r][b]) for r in recipes}
    k = len(repeats_of[args.baseline])
    # Each recipe divided by its own number of repeats (a fine-tuned model
    # may have run once where the word recipes ran three times).
    for mood in sorted(gold, key=lambda m: -gold[m]):
        print(f"  {mood:11} {gold[mood] // k:6} " + " ".join(f"{counts[r][mood] / len(repeats_of[r]):{width}.0f}" for r in recipes))


if __name__ == "__main__":
    main()
