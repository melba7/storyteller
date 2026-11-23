"""Helpers the tests of teach_settings.py share: a made scorecard, its rows and shows, and made
notes. Not a test itself.
Run the tests: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import teach_settings as settings
from teach_settings_rows import rows_in

NOW = 1_700_000_000_000  # milliseconds, like the notes' "at"
DAY = 24 * 3600 * 1000
FEED_A = "https://a.example/feed"
FEED_B = "https://b.example/rss"
OWN, SOUNDS, WORDS, MEANING = (
    "Plus the phone's own sounds", "Plus repeated sounds", "Plus repeated words",
    "Plus the meaning model")
JOINTS, STEADY = "Plus joints", "Plus joints (steady files too)"


def total(episodes=3, ad=100.0, heard=0.0, cut=0.0, before=0.0, after=0.0, show_seconds=3000.0):
    """A scorecard total in the shape the phone's tool writes it (more keys are there in the file)."""
    return {"episodes": episodes, "ads": 4, "caught": 2, "adSeconds": ad, "heardSeconds": heard,
            "heardBeforeSeconds": before, "heardAfterSeconds": after, "cutSeconds": cut,
            "showSeconds": show_seconds, "wrongSkips": 1, "bySort": {}}


def show(feed, name="Show", **figures):
    return {"feed": feed, "show": name, "total": total(**figures)}


SUMMED = ("episodes", "ads", "caught", "adSeconds", "heardSeconds", "heardBeforeSeconds",
          "heardAfterSeconds", "cutSeconds", "showSeconds", "wrongSkips")


def row(name, *shows, whole=None):
    """A scorecard row: the total is the shows' totals added up unless `whole` is given."""
    if whole is None:
        whole = total(0, 0.0)
        for key in SUMMED:
            whole[key] = sum(s["total"][key] for s in shows)
    return {"name": name, "total": whole, "shows": list(shows)}


def card(*rows):
    """The scorecard's newest run, as the file keeps it."""
    return {"version": 1, "runs": [{"at": 1, "title": "old", "total": total(), "rows": []},
                                   {"at": 2, "title": "new", "total": total(), "rows": list(rows)}]}


def rows_of(*rows):
    """The rows as the chooser reads them."""
    return rows_in(card(*rows))


def note(what, by, feed=FEED_A, at=NOW - DAY):
    return {"v": 1, "at": at, "what": what, "feed": feed, "guid": "g", "title": "t",
            "address": "https://a.example/1.mp3", "start": 10.0, "end": None, "kind": "ad", "by": by}


def choose(rows, notes=(), now=NOW):
    return settings.choose(rows, list(notes), now)


def entry(shows, feed):
    found = [s for s in shows if s["feed"] == feed]
    return found[0] if found else None
