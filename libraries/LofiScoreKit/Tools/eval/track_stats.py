#!/usr/bin/env python3
"""How often would the music change with this mood track, and what settling it would do.

A mood track has a reading every ~250 words plus the probes that pin changes
down. The director follows every turn of a track (at most one change per
45 s), so a track whose readings flip between moods that both suit a scene
makes the music restless. This script measures that, and tries rules that
settle the readings into scene-length moods before the director sees them:

    python3 -I Tools/eval/track_stats.py TRACK.json [--sim SIM.jsonl] [--dwell 45] [--dump]
                                         [--settle N[:A]] [--settled-out FILE]

SIM comes from `lofi-eval simulate BOOK --engine lexicon --cadence sentence
--track TRACK.json --out SIM.jsonl`; only its clock is used (when each
sentence is narrated). Without it a sentence is taken as 6.5 seconds.

For each rule: music changes per hour and the median time a mood is held,
after the director's dwell; then how the music sits against the track's own
readings, by narrated time: "best" (the reading's mood), "fits" (its mood or
one of the others it said would also suit, prompt v3's `also`), and "far"
(does not fit and is far away on the valence/arousal map).

Rules:
  raw              the track as it is
  keep K/D         causal. Keep the playing mood while a reading still lists
                   it (best or also). When it stops fitting, change once that
                   has lasted K seconds (at once for a big jump). When it only
                   also-fits and one other mood has been best for D seconds,
                   move to that mood.
  scenes L/A       looks ahead. The cheapest way to cut the book into scenes,
                   where a second of music costs 0 on the reading's mood, A
                   on an also-fits mood and 1 otherwise (less when the moods
                   are close), and every change costs L seconds. A scene may
                   only start on a reading whose own mood it is, so the music
                   never turns to a mood before the narrated text reads as
                   that mood; what looking ahead decides is which turns are
                   worth following.
  app N/A          what playback does (MoodSettling in Swift): the scenes
                   rule counted in sentences instead of seconds, so a track
                   settles the same way whatever the narrator's pace. N is
                   the cost of a change in sentences (--settle, default 9,
                   about a minute) and A the also-fits cost (default 0.25).

--settled-out writes one line per entry (sentence, its own mood, the mood
the app rule plays), the same lines as `lofi-eval settle TRACK --out FILE`,
so the two can be compared. --dump prints the track as "seconds
mood[+also...]" tokens with no text, to study elsewhere. Standard library
only.
"""
from __future__ import annotations

import argparse
import json
import math
import sys

ANCHORS = {
    "calm": (0.25, 0.15), "cozy": (0.55, 0.30), "playful": (0.60, 0.62), "hopeful": (0.70, 0.82),
    "melancholy": (-0.50, 0.20), "mysterious": (-0.10, 0.50), "tense": (-0.55, 0.85), "somber": (-0.70, 0.45),
    "romantic": (0.75, 0.40), "dreamy": (0.45, 0.45), "adventurous": (0.35, 0.78),
}
MOODS = list(ANCHORS)
BIG_JUMP = 1.0  # DirectorConfig.bigJumpDistance
ALSO_SHARE = 0.4  # MoodSettling.alsoShare
TAIL_SENTENCES = 15.0  # MoodSettling.tailSentences


def distance(a: str, b: str) -> float:
    (va, aa), (vb, ab) = ANCHORS[a], ANCHORS[b]
    return math.sqrt((va - vb) ** 2 + ((aa - ab) * 2) ** 2)


def load(track_path: str, sim_path: str | None, seconds_per_sentence: float) -> tuple[list[dict], float, dict]:
    track = json.load(open(track_path, encoding="utf-8"))
    clock: dict[int, float] = {}
    end = 0.0
    if sim_path:
        for line in open(sim_path, encoding="utf-8"):
            if line.strip():
                r = json.loads(line)
                clock[r["global"]] = r["seconds"]
                end = max(end, r["seconds"])
    known = sorted(clock)

    def seconds(g: int) -> float:
        if not clock:
            return g * seconds_per_sentence
        if g in clock:
            return clock[g]
        # The clock has every narrated sentence; an index it lacks takes the one before it.
        lo, hi = 0, len(known)
        while lo < hi:
            mid = (lo + hi) // 2
            if known[mid] <= g:
                lo = mid + 1
            else:
                hi = mid
        return clock[known[lo - 1]] if lo else 0.0

    entries = []
    for e in sorted(track["entries"], key=lambda e: e["globalIndex"]):
        r = e["reading"]
        mood = r["bucket"]
        if mood not in ANCHORS:
            continue
        # Also fitting: scored at least ALSO_SHARE of the best mood (Claude's
        # `also` moods get half of it; a classifier's long tail does not count).
        scores = {m: v for m, v in (r.get("scores") or {}).items() if m in ANCHORS and isinstance(v, (int, float))}
        top = scores.get(mood) or max(scores.values(), default=0.0)
        also = [m for m, v in scores.items() if m != mood and v > 0 and top > 0 and v >= ALSO_SHARE * top]
        entries.append({"g": e["globalIndex"], "t": seconds(e["globalIndex"]), "mood": mood, "also": also,
                        "conf": r.get("confidence", 0.0)})
    if not entries:
        sys.exit("the track has no entries")
    last = entries[-1]["t"]
    end = max(end + seconds_per_sentence, last + seconds_per_sentence) if clock else last + 250 / 150 * 60
    for a, b in zip(entries, entries[1:]):
        a["d"] = max(0.0, b["t"] - a["t"])
    entries[-1]["d"] = max(0.0, end - last)
    return entries, end, track


# Rules: each returns the mood the track would report from every entry on.

def raw(entries: list[dict]) -> list[str]:
    return [e["mood"] for e in entries]


def keep(entries: list[dict], confirm: float, drift: float) -> list[str]:
    out = []
    playing = entries[0]["mood"]
    miss_since = drift_since = None
    drift_mood = None
    for e in entries:
        best, fits = e["mood"], {e["mood"], *e["also"]}
        if best == playing:
            miss_since = drift_since = drift_mood = None
        elif playing in fits:
            miss_since = None
            if drift_mood != best:
                drift_mood, drift_since = best, e["t"]
            if e["t"] - drift_since >= drift:
                playing = best
                drift_since = drift_mood = None
        else:
            drift_since = drift_mood = None
            if miss_since is None:
                miss_since = e["t"]
            if distance(playing, best) >= BIG_JUMP or e["t"] - miss_since >= confirm:
                playing = best
                miss_since = None
        out.append(playing)
    return out


def scenes(entries: list[dict], change: float, also_cost: float, start: str = "best") -> list[str]:
    def cost(mood: str, e: dict) -> float:
        if mood == e["mood"]:
            return 0.0
        if mood in e["also"]:
            return also_cost
        return 0.6 + 0.4 * min(1.0, distance(mood, e["mood"]))

    def may_start(mood: str, e: dict) -> bool:
        return mood == e["mood"] or (start == "fits" and mood in e["also"])

    inf = float("inf")
    n = len(entries)
    best = [{m: inf for m in MOODS} for _ in range(n)]
    back: list[dict[str, str | None]] = [{m: None for m in MOODS} for _ in range(n)]
    for m in MOODS:
        if may_start(m, entries[0]):
            best[0][m] = entries[0]["d"] * cost(m, entries[0])
    for i in range(1, n):
        e = entries[i]
        cheapest = min(MOODS, key=lambda m: best[i - 1][m])
        for m in MOODS:
            stay = best[i - 1][m]
            turn = best[i - 1][cheapest] + change if may_start(m, e) and cheapest != m else inf
            if turn < stay:
                best[i][m], back[i][m] = turn, cheapest
            else:
                best[i][m], back[i][m] = stay, m
            best[i][m] += e["d"] * cost(m, e)
    mood = min(MOODS, key=lambda m: best[n - 1][m])
    out = [mood]
    for i in range(n - 1, 0, -1):
        mood = back[i][mood] or mood
        out.append(mood)
    return out[::-1]


def app(entries: list[dict], change: float = 9.0, also_cost: float = 0.25) -> list[str]:
    """MoodSettling.moods(for:) in Swift: scenes, with sentences for seconds."""
    counted = [dict(a, d=float(max(0, b["g"] - a["g"]))) for a, b in zip(entries, entries[1:])]
    counted.append(dict(entries[-1], d=TAIL_SENTENCES))
    return scenes(counted, change, also_cost)


def director(entries: list[dict], wanted: list[str], dwell: float) -> list[tuple[float, float, str, int]]:
    """Pieces (start, end, playing mood, entry index) after the director's rule for
    track readings: follow a turn at once, but not within `dwell` of the last change;
    a turn that comes sooner goes ahead when the dwell is up if the track still says so."""
    pieces = []
    playing = wanted[0]
    last_change = -1e9
    for i, e in enumerate(entries):
        start, end = e["t"], e["t"] + e["d"]
        if wanted[i] != playing:
            at = max(start, last_change + dwell)
            if at < end:
                if at > start:
                    pieces.append((start, at, playing, i))
                playing, last_change, start = wanted[i], at, at
        if end > start:
            pieces.append((start, end, playing, i))
    return pieces


def measure(entries: list[dict], wanted: list[str], dwell: float) -> dict:
    pieces = director(entries, wanted, dwell)
    total = sum(b - a for a, b, _, _ in pieces) or 1e-9
    holds, changes = [], 0
    run_start, run_mood = pieces[0][0], pieces[0][2]
    for a, b, mood, _ in pieces[1:]:
        if mood != run_mood:
            holds.append(a - run_start)
            run_start, run_mood = a, mood
            changes += 1
    holds.append(pieces[-1][1] - run_start)
    holds.sort()
    on_best = fits = far = 0.0
    for a, b, mood, i in pieces:
        e = entries[i]
        if mood == e["mood"]:
            on_best += b - a
        if mood == e["mood"] or mood in e["also"]:
            fits += b - a
        elif distance(mood, e["mood"]) >= 0.8:
            far += b - a
    return {"changes": changes, "per_hour": changes / (total / 3600), "median_hold": holds[len(holds) // 2],
            "short_holds": sum(1 for h in holds if h < 120) / len(holds),
            "best": on_best / total, "fits": fits / total, "far": far / total}


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("track")
    ap.add_argument("--sim")
    ap.add_argument("--seconds-per-sentence", type=float, default=6.5)
    ap.add_argument("--dwell", type=float, default=45)
    ap.add_argument("--dump", action="store_true")
    ap.add_argument("--settle", default="9:0.25", help="the app rule: SENTENCES[:ALSO]")
    ap.add_argument("--settled-out")
    args = ap.parse_args()
    settle = [float(x) for x in args.settle.split(":")]
    app_change, app_also = settle[0], settle[1] if len(settle) > 1 else 0.25
    entries, end, track = load(args.track, args.sim, args.seconds_per_sentence)
    hours = (end - entries[0]["t"]) / 3600

    if args.dump:
        counts: dict[str, int] = {}
        for e in entries:
            counts[e["mood"]] = counts.get(e["mood"], 0) + 1
        print(f"# {len(entries)} entries, {hours:.2f} h; " + " ".join(f"{m}={c}" for m, c in sorted(counts.items())))
        print(" ".join(f"{e['t']:.0f}:{e['mood'][:3]}" + "".join("+" + a[:3] for a in e["also"]) for e in entries))
        return

    moods = raw(entries)
    turns = sum(1 for a, b in zip(moods, moods[1:]) if a != b)
    blips = sum(1 for a, b, c in zip(moods, moods[1:], moods[2:]) if a == c != b)
    soft = sum(1 for a, b in zip(entries, entries[1:]) if a["mood"] != b["mood"] and a["mood"] in b["also"])
    with_also = sum(1 for e in entries if e["also"])
    by_time: dict[str, float] = {}
    for e in entries:
        by_time[e["mood"]] = by_time.get(e["mood"], 0.0) + e["d"]
    print(f"# {track.get('engineID', '?')}: {len(entries)} entries over {hours:.1f} h of narration"
          f" ({'simulated clock' if args.sim else 'estimated clock'}); {with_also} list other moods that also fit")
    print("  time by mood: " + ", ".join(f"{m} {s / (hours * 36):.0f}%" for m, s in sorted(by_time.items(), key=lambda x: -x[1])))
    print(f"  the readings turn {turns} times ({turns / hours:.1f} per hour); {blips} are there-and-back (A B A);"
          f" in {soft} the old mood is still listed as also fitting")
    gaps = sorted(e["d"] for e in entries[:-1])
    print(f"  seconds between entries: median {gaps[len(gaps) // 2]:.0f}, 10% under {gaps[len(gaps) // 10]:.0f}, 10% over {gaps[len(gaps) * 9 // 10]:.0f}")
    print()
    print(f"## After the director (one change per {args.dwell:.0f} s at most)")
    print(f"  {'rule':<22}{'changes/h':>10}{'median hold':>13}{'holds <2 min':>14}{'best':>8}{'fits':>8}{'far':>7}")
    rules: list[tuple[str, list[str]]] = [("raw", moods)]
    for confirm, drift in [(0, 600), (90, 600), (90, 300), (150, 300), (150, 1e9)]:
        name = f"keep {confirm:.0f}/{'-' if drift > 1e8 else f'{drift:.0f}'}"
        rules.append((name, keep(entries, confirm, drift)))
    for change in (60, 120, 180, 300, 480):
        for also_cost in (0.25, 0.5):
            rules.append((f"scenes {change}/{also_cost}", scenes(entries, change, also_cost)))
    rules.append(("scenes 180/0.25 fits", scenes(entries, 180, 0.25, start="fits")))
    played = app(entries, app_change, app_also)
    rules.append((f"app {app_change:g}/{app_also:g}", played))
    if args.settled_out:
        with open(args.settled_out, "w", encoding="utf-8") as f:
            for e, mood in zip(entries, played):
                f.write(f"{e['g']}\t{e['mood']}\t{mood}\n")
    for name, wanted in rules:
        m = measure(entries, wanted, args.dwell)
        print(f"  {name:<22}{m['per_hour']:>10.1f}{m['median_hold'] / 60:>9.1f} min{m['short_holds']:>13.0%}"
              f"{m['best']:>8.0%}{m['fits']:>8.0%}{m['far']:>7.1%}")
    print("  (best/fits/far: share of narrated time the music is on the reading's mood, on a mood it lists, or far from it)")


if __name__ == "__main__":
    main()
