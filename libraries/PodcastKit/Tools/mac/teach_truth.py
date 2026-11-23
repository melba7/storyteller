"""What teach_copies.py and teach_snap.py share: the folder names, reading a truth file, saving
bytes without leaving half a file, and which transcript lines a stretch of the audio covers.

Standard library only. A truth file is what `podcast-ads --truth-from-copies` prints for two
downloads of one episode: one stretch to a line as two times such as 0:33.480 1:02.120, and notes
that start with "#". teach_copies.py keeps it as <folder>/copies/<id>.truth.txt.

Run the tests: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import math
import os
import re
import tempfile

import teach_segments as seg

LABELS = "labels"
SNAPPED = "labels-snapped"
COPIES = "copies"
TIME_PART = re.compile(r"^[0-9]+(\.[0-9]+)?$", re.ASCII)
WHOLE_PART = re.compile(r"^[0-9]+$", re.ASCII)


def truth_path(folder, identifier):
    """Where teach_copies.py keeps what it found for an episode."""
    return os.path.join(folder, COPIES, identifier + ".truth.txt")


def clock_seconds(text):
    """Seconds in "12:30", "1:02:03" or "12:30.5", or None for anything else. Only the first part
    may be 60 or more."""
    parts = text.split(":")
    if not 2 <= len(parts) <= 3:
        return None
    total = 0.0
    for index, part in enumerate(parts):
        if not (TIME_PART if index == len(parts) - 1 else WHOLE_PART).match(part):
            return None
        value = float(part)
        if not math.isfinite(value) or (index > 0 and value >= 60):
            return None
        total = total * 60 + value
    return total if math.isfinite(total) else None


def read_truth(text):
    """The stretches of a truth file, [(start, end)] in order, in seconds. Blank lines and lines
    that start with "#" are left out. Raises ValueError, naming the line, for a line that is not
    two times with the second after the first."""
    found = []
    for number, row in enumerate(text.splitlines(), 1):
        line = row.strip()
        if not line or line.startswith("#"):
            continue
        times = [word for word in line.split() if word not in ("-", "–", "to")]
        start = clock_seconds(times[0]) if len(times) == 2 else None
        end = clock_seconds(times[1]) if len(times) == 2 else None
        if start is None or end is None or end <= start:
            raise ValueError("Line %d is not two times such as 12:30 13:45: %s" % (number, line[:80]))
        found.append((start, end))
    return sorted(found)


def save_bytes(path, data):
    """Writes the bytes through a temporary file in the same folder, so the file is never
    half-written."""
    handle, temporary = tempfile.mkstemp(dir=os.path.dirname(path), prefix=".", suffix=".part")
    try:
        with os.fdopen(handle, "wb") as out:
            out.write(data)
            out.flush()
            os.fsync(out.fileno())
        os.replace(temporary, path)
    except BaseException:
        if os.path.exists(temporary):
            os.remove(temporary)
        raise


def overlap(first_start, first_end, second_start, second_end):
    """How many seconds two stretches share (0 when they do not meet)."""
    return max(0.0, min(first_end, second_end) - max(first_start, second_start))


def covered(lines, start, end):
    """(first, last), the numbers (from 1) of the transcript lines that the stretch covers by half
    or more of their length, or only the one line it covers most when no line is half covered.
    None when it touches no line. A line lasts until the next one starts, the last one 5 s."""
    first = last = best = None
    most = 0.0
    for number, (begin, _) in enumerate(lines, 1):
        finish = lines[number][0] if number < len(lines) else begin + seg.LAST_LINE_SECONDS
        shared = overlap(begin, finish, start, end)
        if shared <= 0:
            continue
        if shared * 2 >= finish - begin:
            first = first or number
            last = number
        if shared > most:
            most, best = shared, number
    if first is not None:
        return first, last
    return (best, best) if best else None
