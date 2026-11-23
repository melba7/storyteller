"""The waiting of the marking run: for the night hours to begin, and for the Claude usage allowance
to come back.

Standard library only. teach_label.py asks a Waiter before every episode. The clock and the sleep
are given in, so the tests do not wait. A window is written "23-7": local clock hours, the start
hour in and the end hour out, and it may cross midnight.

Run the tests: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import re
import time
from datetime import datetime, timedelta

STEP = 600  # the longest single sleep, in seconds, so a closed lid or a changed clock is noticed
ALLOWANCE = 1800  # how long to wait, in seconds, before trying again when the allowance is used up


def parse_window(text):
    """(start, end) hours from "23-7". Raises ValueError for anything else."""
    found = re.fullmatch(r"\s*([0-9]{1,2})-([0-9]{1,2})\s*", text or "")
    if not found:
        raise ValueError(text)
    start, end = int(found.group(1)), int(found.group(2))
    if not (0 <= start <= 23 and 0 <= end <= 24) or start == end:
        raise ValueError(text)
    return start, end


def in_window(hour, window):
    start, end = window
    return start <= hour < end if start < end else hour >= start or hour < end


def window_text(window):
    return "%02d:00 and %02d:00" % (window[0], window[1] % 24)


class Waiter:
    """Waits for the window to open and for the allowance to come back."""

    def __init__(self, window=None, wait_hours=None, clock=datetime.now, sleep=time.sleep,
                 say=print):
        self.window, self.clock, self.sleep, self.say = window, clock, sleep, say
        self.allowance_left = (wait_hours or 0) * 3600

    def seconds_until_open(self, now):
        target = now.replace(hour=self.window[0] % 24, minute=0, second=0, microsecond=0)
        if target <= now:
            target += timedelta(days=1)
        return (target - now).total_seconds()

    def for_window(self):
        """Returns when the local time is inside the window (at once without a window)."""
        told = False
        while self.window and not in_window(self.clock().hour, self.window):
            if not told:
                self.say("Waiting until %02d:00 (marking happens only between %s). Keep the Mac "
                         "plugged in." % (self.window[0], window_text(self.window)))
                told = True
            self.sleep(max(1, min(STEP, self.seconds_until_open(self.clock()))))

    def for_allowance(self):
        """Waits for the allowance (up to what is left of --wait-hours, 30 minutes at a time) and
        returns True; returns False when no waiting is left."""
        if self.allowance_left <= 0:
            return False
        nap = min(ALLOWANCE, self.allowance_left)
        more = "" if nap == ALLOWANCE else " more"
        self.say("Claude's usage allowance is used up. Waiting %d minutes%s, then trying the same "
                 "episode again." % (max(nap // 60, 1), more))
        self.allowance_left -= nap
        while nap > 0:
            step = min(STEP, nap)
            self.sleep(step)
            nap -= step
        return True
