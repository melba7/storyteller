"""The report of the second look (teach_second_look.py): reads labels-second-look/, where each moved
label carries the edges it scored ("secondLook": exact, before and after), and writes
second-look-report.json and a plain summary. It holds numbers only, no transcript words.

Standard library only.

Run the tests: python3 -m pytest test_teach_second_look.py -q"""
import json
import os
import time

from teach_store import write_json

OUT = "labels-second-look"
REPORT = "second-look-report.json"
WITHIN = (1, 2, 5)
KEEP_GAIN = 5  # edges in 100 that must land within 5 s more for the second look to be kept


def counts(edges, key):
    """How many of the edges ({"exact", "before", "after"}) lie within 1, 2 and 5 seconds."""
    return {str(t): sum(abs(e[key] - e["exact"]) <= t + 1e-9 for e in edges) for t in WITHIN}


def table(edges):
    before, after = counts(edges, "before"), counts(edges, "after")
    return {str(t): {"before": before[str(t)], "after": after[str(t)]} for t in WITHIN}


def report(folder, say=print, now=time.time):
    """Reads labels-second-look/, writes second-look-report.json and says the summary."""
    names = sorted(n for n in os.listdir(os.path.join(folder, OUT))) \
        if os.path.isdir(os.path.join(folder, OUT)) else []
    edges, by_kind, per_episode, cost = [], {}, [], 0.0
    for name in names:
        try:
            with open(os.path.join(folder, OUT, name), encoding="utf-8") as f:
                look = json.load(f)["secondLook"]
        except (OSError, ValueError, KeyError):
            continue
        mine = []
        for record in look["edges"]:
            for key in ("start", "end"):
                if key in record:
                    mine.append(record[key])
                    by_kind.setdefault(record["sort"], []).append(record[key])
        edges += mine
        cost += look["cost"]
        per_episode.append({"id": name[:-5], "edges": len(mine), "cost": look["cost"],
                            "within5Before": counts(mine, "before")["5"],
                            "within5After": counts(mine, "after")["5"]})
    within = table(edges)
    kinds = {sort: {"edges": len(items), "within": table(items)} for sort, items in sorted(by_kind.items())}
    worse = [s for s, k in kinds.items() if k["within"]["5"]["after"] < k["within"]["5"]["before"]]
    gain = round((within["5"]["after"] - within["5"]["before"]) * 100 / len(edges), 1) if edges else 0.0
    out = {"version": 1, "writtenAt": int(now() * 1000), "episodes": len(per_episode),
           "edges": len(edges), "cost": round(cost, 6), "within": within, "byKind": kinds,
           "worseKinds": worse, "gainPer100": gain, "perEpisode": per_episode}
    if names:
        write_json(os.path.join(folder, REPORT), out)
    if not edges:
        say("Second look: nothing to report yet.")
        return out
    say("Second look on %d episodes, %d edges, cost $%.2f ($%.2f an episode)."
        % (len(per_episode), len(edges), cost, cost / len(per_episode)))
    for t in WITHIN:
        one = within[str(t)]
        say("  within %d s of the exact edge: %d of %d before, %d after." % (t, one["before"], len(edges), one["after"]))
    for sort, k in kinds.items():
        one = k["within"]["5"]
        say("  %s: %d edges, within 5 s %d before, %d after." % (sort, k["edges"], one["before"], one["after"]))
    kept = gain >= KEEP_GAIN and not worse
    say("Within 5 s changed by %+.1f in 100 edges; %s. The rule to keep it: at least %d in 100 more and no "
        "kind worse, %s." % (gain, ("kinds that got worse: " + ", ".join(worse)) if worse else "no kind got worse",
                             KEEP_GAIN, "met" if kept else "not met"))
    return out


