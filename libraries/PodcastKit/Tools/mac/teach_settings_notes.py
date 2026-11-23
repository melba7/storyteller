"""The phone's notes, for teach_settings.py: finding and reading them, and what they say about each
finder on each show.

Standard library only. The notes are only read, through teach_feedback.py's reader, never changed.

Run the tests: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import os

import teach_feedback
from teach_feed import feed_key
from teach_settings_rows import number

ANSWERS = ("undone", "denied", "confirmed")
ANSWER_WINDOW = 5
BAD_ANSWERS = 2
ANSWER_LIFE_MS = 30 * 24 * 3600 * 1000


def answers(notes, now, finders):
    """{(feed key, finder): (level, why)} from the notes: of a finder's last five answers on a show
    (undone, denied or confirmed, none older than 30 days), two denied turn it off and two undone make
    it ask. This is the phone's finder guard's rule. `finders` are the names that count; `now` and
    the notes' "at" are in milliseconds."""
    given = {}
    for one in sorted((n for n in notes if number(n.get("at"))), key=lambda n: n["at"]):
        if one.get("what") in ANSWERS and one.get("by") in finders \
                and abs(now - one["at"]) <= ANSWER_LIFE_MS:
            given.setdefault((feed_key(one["feed"]), one["by"]), []).append(one["what"])
    chosen = {}
    for key, last in given.items():
        last = last[-ANSWER_WINDOW:]
        for answer, level, words in (("denied", "off", "\"not an ad\""), ("undone", "ask", "undone skips")):
            if last.count(answer) >= BAD_ANSWERS:
                chosen[key] = (level, "%d of its last %d answers on this show were %s"
                               % (last.count(answer), len(last), words))
                break
    return chosen


def read_notes(given, defaults, say):
    """The phone's notes (from `given`, or where teach_feedback.py looks), or [] with a line saying
    why there are none to use. Never raises."""
    denied = []
    path = os.path.expanduser(given) if given else teach_feedback.find_notes(defaults, denied)
    if path is None and denied:
        say("macOS did not let this read the phone's notes at %s (a permission problem), so only the "
            "scorecard was used." % denied[0])
    elif path is None:
        say("The phone has sent no notes yet, so only the scorecard was used.")
    else:
        try:
            os.stat(path)
            return teach_feedback.read_notes(path)[0]
        except FileNotFoundError:
            say("There is no notes file at %s, so only the scorecard was used." % path)
        except ValueError as error:
            say("The phone's notes were not used: %s" % error)
        except OSError as error:
            say("The notes in %s could not be read (%s), so only the scorecard was used." % (path, error))
    return []
