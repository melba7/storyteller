#!/usr/bin/env python3
"""Compare training recipes on `lofi-train oof` predictions, window by window.

Every recipe was scored on the same held-out windows (all labelled books,
rotated through cross-validation folds, repeated with different shuffles), so
differences are paired. Intervals come from resampling whole books, because
windows from one book are not independent.

    python3 -I Tools/eval/oof_compare.py oof-word.jsonl [--baseline word2-settings] [--boot 1000]

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
    args = ap.parse_args()

    by_recipe_book: dict[str, dict[str, list[tuple[str, str]]]] = collections.defaultdict(lambda: collections.defaultdict(list))
    repeats = set()
    for line in open(args.oof):
        r = json.loads(line)
        by_recipe_book[r["recipe"]][r["book"]].append((r["gold"], r["predicted"]))
        repeats.add(r["repeatIndex"])
    recipes = sorted(by_recipe_book, key=lambda k: (k != args.baseline, k))
    books = sorted({b for d in by_recipe_book.values() for b in d})
    windows = sum(len(v) for v in by_recipe_book[args.baseline].values()) // len(repeats)
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

    print("\n## Predicted vs labelled mood counts (one repeat's worth)")
    gold = collections.Counter(g for b in books for g, _ in by_recipe_book[args.baseline][b])
    width = max(len(r) for r in recipes) + 1
    print("  mood        labels " + " ".join(f"{r:>{width}}" for r in recipes))
    counts = {r: collections.Counter(p for b in books for _, p in by_recipe_book[r][b]) for r in recipes}
    k = len(repeats)
    for mood in sorted(gold, key=lambda m: -gold[m]):
        print(f"  {mood:11} {gold[mood] // k:6} " + " ".join(f"{counts[r][mood] / k:{width}.0f}" for r in recipes))


if __name__ == "__main__":
    main()
