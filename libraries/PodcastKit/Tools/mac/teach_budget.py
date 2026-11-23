"""A spending budget that lasts across marking runs.

Standard library only. teach_label.py --budget NAME --cap DOLLARS keeps what the marking has cost
under that name in <folder>/marking-spend.json:

  {"version": 1, "budgets": {"<name>": {"dollars": 12.34, "episodes": 65}}}

With a budget, --cap is the total for all the runs together, so a double-click that finds the
budget spent marks nothing. The file is written atomically after every marked episode (and after an
episode that failed but still cost something). A damaged file is a set-up problem and is never
replaced by a fresh start, because that would hand out the money a second time.

Run the tests: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import json
import math
import os
import re

from teach_store import Problem, write_json

FILE = "marking-spend.json"
VERSION = 1
NAME = re.compile(r"^[A-Za-z0-9_-]{1,40}$")


class CapReached(Exception):
    """The cap (or the budget) does not allow another call."""


def number(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def read_all(folder):
    """The "budgets" object of the file, {} when there is no file. Raises Problem when the file
    is damaged."""
    path = os.path.join(folder, FILE)
    if not os.path.exists(path):
        return {}
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, ValueError):
        data = None
    budgets = data.get("budgets") if isinstance(data, dict) and data.get("version") == VERSION else None
    if not isinstance(budgets, dict) or not all(
            isinstance(spent, dict) and number(spent.get("dollars")) and spent["dollars"] >= 0
            and isinstance(spent.get("episodes"), int) and not isinstance(spent["episodes"], bool)
            and spent["episodes"] >= 0 for spent in budgets.values()):
        raise Problem("%s is damaged, so what was spent is not known and nothing is marked. Fix it "
                      "or move it away, and run again." % path)
    return budgets


class Budget:
    """One named budget of a teaching folder."""

    def __init__(self, folder, name, cap):
        if not NAME.match(name or ""):
            raise Problem("The budget name must be 1 to 40 letters, digits, - or _.")
        self.folder, self.name, self.cap = folder, name, cap
        self.budgets = read_all(folder)
        found = self.budgets.get(name, {"dollars": 0.0, "episodes": 0})
        self.dollars, self.episodes = float(found["dollars"]), found["episodes"]

    def left(self):
        return max(self.cap - self.dollars, 0)

    def add(self, dollars, episodes):
        """Adds what an episode cost (and 1 episode when it was marked) and saves the file."""
        self.dollars += dollars
        self.episodes += episodes
        self.budgets[self.name] = {"dollars": round(self.dollars, 6), "episodes": self.episodes}
        write_json(os.path.join(self.folder, FILE), {"version": VERSION, "budgets": self.budgets})

    def line(self):
        return ("Budget \"%s\": $%.2f of $%.2f spent so far on %d episode%s, $%.2f left."
                % (self.name, self.dollars, self.cap, self.episodes,
                   "" if self.episodes == 1 else "s", self.left()))
