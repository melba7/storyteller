"""What the paid teaching tools that are not the big marking run share (teach_second_look.py and
teach_playbook.py): one place that asks Claude through the same `claude -p` set-up as
teach_label.py, checks the cap before every request and writes what it cost into the named budget
(marking-spend.json, see teach_budget.py) as soon as the answer is back.

Standard library only. It never prints or logs a key: ANTHROPIC_API_KEY is removed from the
environment of every run (teach_claude.py), so a run uses the Claude plan this Mac is signed in to.

Run the tests: python3 -m pytest test_teach_second_look.py test_teach_playbook.py -q"""
import subprocess

from teach_budget import CapReached
from teach_claude import ask_claude, find_claude

NOT_CONFIRMED = 4
CAP_REACHED = 5
FAILED_IN_A_ROW = 6
USAGE_STOP = 3
IN_A_ROW = 3


class Spender:
    """Wraps `ask(prompt)` (which returns {"text", "cost"}). Before a request it raises CapReached
    when what is spent plus `reserve` (what one request is expected to cost) reaches `cap`, the
    budget's total with what it held before this run. After a request it writes the cost in the
    budget at once, also for a request that failed. A request whose cost is not known counts as
    `reserve`, so it cannot pass the cap unseen. `spent` is what this run has spent."""

    def __init__(self, ask, budget, cap, reserve=0.0):
        self.ask, self.budget, self.cap, self.reserve = ask, budget, cap, reserve
        self.before = budget.dollars
        self.spent = 0.0

    def __call__(self, prompt):
        if self.before + self.spent + self.reserve >= self.cap:
            raise CapReached()
        try:
            reply = self.ask(prompt)
        except Exception as error:  # a failed request still cost what it cost
            self.charge(getattr(error, "cost", 0.0), getattr(error, "cost_unknown", False))
            raise
        paid = self.charge(reply["cost"], reply.get("cost_unknown", False))
        return dict(reply, paid=paid)

    def charge(self, paid, unknown):
        if unknown:
            paid = max(paid, self.reserve)
        self.spent += paid
        if paid > 0:
            self.budget.add(paid, 0)
        return paid


def claude_asker(system, model, environment, extra_folders, runner=subprocess.run):
    """`ask(prompt)` that runs Claude with `system`, or None when Claude Code is not installed."""
    claude = find_claude(environment, extra_folders) if extra_folders is not None \
        else find_claude(environment)
    if claude is None:
        return None

    def ask(prompt):
        return ask_claude(system, prompt, model, claude, runner=runner, environment=environment)
    return ask
