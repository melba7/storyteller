"""The summary of prepared episodes that teach_feedback.py prints from the phone's notes.

Standard library only. When the phone plays the Mac's own copy of an episode (see teach_prepared.py),
what happens on that copy is noted with `by: "prepared"`: a skip the Mac's marks made, the listener's
Undo of it, and a tap on Skip ad where the phone knew no ad (a "missed" note). This counts those
three, over all prepared episodes and per show, each exactly when the note says by "prepared". The
notes are not matched to prepared.json: the phone says itself which file it was playing. A show is
named from episodes.json by its feed's key, or by the key when it is not there.

Run the tests: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import teach_store
from teach_feed import feed_key

BY = "prepared"
KINDS = ("skipped", "undone", "missed")
SHOWS_LINE = 5  # the most shows named on the last line


def plural(count, one, many):
    return "%d %s" % (count, one if count == 1 else many)


def show_names(folder):
    """{feed key: show name} from episodes.json, {} when it is missing or cannot be used."""
    try:
        return {feed_key(e["feed"]): e["show"] for e in teach_store.load_manifest(folder)}
    except (teach_store.ManifestError, OSError):
        return {}


def counts(notes, names):
    """(total, per show): the counts as {"skipped", "undone", "missed"}, of the notes by prepared."""
    total = dict.fromkeys(KINDS, 0)
    shows = {}
    for one in notes:
        if one.get("by") != BY or one["what"] not in KINDS:
            continue
        key = feed_key(one["feed"])
        total[one["what"]] += 1
        shows.setdefault(names.get(key, key), dict.fromkeys(KINDS, 0))[one["what"]] += 1
    return total, shows


def summary(notes, folder):
    """Up to three plain lines about the prepared episodes, [] when there is nothing to say."""
    total, shows = counts(notes, show_names(folder))
    if not any(total.values()):
        return []
    lines = ["Prepared episodes: the phone skipped %s by the Mac's marks, you took back %d of those "
             "skips, and you pressed Skip ad %s on the Mac's copy where its marks had no ad."
             % (plural(total["skipped"], "ad", "ads"), total["undone"],
                plural(total["missed"], "time", "times"))]
    if total["skipped"]:
        lines.append("That is %s taken back in %d (%d%%)." % (
            plural(total["undone"], "skip", "skips"), total["skipped"],
            round(100 * total["undone"] / total["skipped"])))
    ranked = sorted(shows.items(), key=lambda row: (-sum(row[1].values()), row[0].lower()))
    lines.append("Per show: " + "; ".join(
        "%s: %d skipped, %d taken back, %d pressed" % (name, row["skipped"], row["undone"], row["missed"])
        for name, row in ranked[:SHOWS_LINE]) + ("; and %d more" % (len(ranked) - SHOWS_LINE)
                                                   if len(ranked) > SHOWS_LINE else "") + ".")
    return lines
