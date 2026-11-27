"""The summary of prepared episodes that teach_feedback.py prints from the phone's notes.

Standard library only. When the phone plays the Mac's own copy of an episode (see teach_prepared.py),
a skip the Mac's marks made and the listener's Undo of it are notes with `by: "prepared"`. This counts,
over all prepared episodes and per show:

- skipped: notes "skipped" with by "prepared": ads the phone skipped by itself, by the Mac's marks;
- undone: notes "undone" with by "prepared": those skips the listener took back;
- missed: notes "missed" (taps on Skip ad, where the phone knew no ad) in an episode that
  prepared.json lists as published (with a file, whether or not that copy is still there).

An episode is matched to a note by the feed's key and the guid (or, with no guid, the audio
address), the same way the phone matches: the pairs come from ahead.json (the phone's own spelling
of the feed and the guid) and from episodes.json (the Mac's). Note that the notes do not say whether
the listener was playing the Mac's copy or the publisher's own file when they pressed Skip ad, so
a miss in a published episode may have been on the other file (a missed tap on the stream, or a copy
the phone had not taken yet). That needs one more field from the phone; see teach_feedback.py.

Run the tests: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import teach_store
from teach_ahead_set import read_ahead
from teach_feed import feed_key
from teach_prepared_file import read_prepared

BY = "prepared"
SHOWS_LINE = 5  # the most shows named on the last line


def plural(count, one, many):
    return "%d %s" % (count, one if count == 1 else many)


def episode_keys(folder):
    """({(feed key, guid or address): show}, {feed key: show}) of the episodes prepared.json lists as
    published. Raises teach_store.Problem or ManifestError when a file is damaged."""
    manifest = {e["id"]: e for e in teach_store.load_manifest(folder)}
    names = {feed_key(e["feed"]): e["show"] for e in manifest.values()}
    published = {one["id"] for one in read_prepared(folder) if one["file"] is not None}
    keys = {}
    for item in read_ahead(folder):
        if item["id"] not in published:
            continue
        mac = manifest.get(item["id"])
        show = mac["show"] if mac else feed_key(item["feed"])
        keys[(feed_key(item["feed"]), item["guid"])] = show
        if mac:
            for value in (mac["guid"], mac["address"]):
                if value:
                    keys[(feed_key(mac["feed"]), value)] = show
    return keys, names


def counts(notes, keys, names):
    """(total, per show): the counts as {"skipped", "undone", "missed"}."""
    total = {"skipped": 0, "undone": 0, "missed": 0}
    shows = {}
    for one in notes:
        key = feed_key(one["feed"])
        found = keys.get((key, one["guid"])) or keys.get((key, one["address"]))
        if one["what"] in ("skipped", "undone") and one.get("by") == BY:
            kind = one["what"]
        elif one["what"] == "missed" and found:
            kind = "missed"
        else:
            continue
        name = found or names.get(key, key)
        total[kind] += 1
        shows.setdefault(name, {"skipped": 0, "undone": 0, "missed": 0})[kind] += 1
    return total, shows


def summary(notes, folder):
    """Up to three plain lines about the prepared episodes, [] when there is nothing to say."""
    try:
        keys, names = episode_keys(folder)
    except (teach_store.Problem, teach_store.ManifestError, OSError) as error:
        if any(one.get("by") == BY for one in notes):
            return ["Prepared episodes could not be summed up (%s)." % error]
        return []
    total, shows = counts(notes, keys, names)
    if not any(total.values()):
        return []
    lines = ["Prepared episodes: the phone skipped %s by the Mac's marks, you took back %d of those "
             "skips, and you pressed Skip ad %s where the Mac's marks had no ad."
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
