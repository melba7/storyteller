"""Writes ahead-ads.json: where the ads are in the episodes the nightly read-ahead marked, told in
words so that the phone can find them in its own transcript.

Standard library only. teach_ahead.py write calls it. The file goes into the teaching folder and
teach_publish.py copies it to the folders the phone reads, like the other files. The format is fixed,
because the phone's finder reads exactly this:

  {"version": 1, "writtenAt": <seconds>, "episodes": [
     {"feed": "<the phone's feed address>", "guid": "<the phone's guid>", "title": "...",
      "marked": <seconds>, "ads": [
        {"kind": "ad" | "promo" | "ownPlug", "confidence": "high" | "medium" | "low",
         "start": <seconds>, "end": <seconds>,
         "startWords": "the first up to 40 words of the ad as written in the transcript",
         "endWords": "the last up to 40 words of the ad"}],
      "copy": {"file": "prepared/<id>.<ext>", "sha256": "<64 hex>", "bytes": <int>}}]}

"copy" is there only when the Mac prepared the episode's audio (teach_prepared.py) and the file is in
the iCloud copy of the phone's folder now. Then "start" and "end" of its ads are seconds in that very
file, taken from labels-snapped/<id>.json when it exists and else from labels/, and an entry with no
ads is kept, because that says the episode has none. An entry without a copy is as it always was.

The kinds are the scorecard's (AdKind(sort:) in AdLibrary.swift): sponsor is ad, network_promo is
promo, host_ask is ownPlug. The intro and the credits are left out. Claude's confidence is passed on
as it is. Each episode is kept 14 days from the time it was marked, and older ones are dropped at
every write. Episodes of the exam and the shelf are never told. A file over the size the Mac's files
keep (teach_publish.LIMIT) loses its oldest episodes.

Run the tests: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import json
import os

import teach_exam
import teach_prepared_file
import teach_segments as seg
import teach_shelf
from teach_ahead_set import read_ahead
from teach_publish import LIMIT, write_atomically

FILE = "ahead-ads.json"
KEEP_SECONDS = 14 * 86400
WORDS = 40
KINDS = {"sponsor": "ad", "network_promo": "promo", "host_ask": "ownPlug"}


def number(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def ad_words(lines, first, last):
    """(the first up to 40 words, the last up to 40 words) of lines `first` to `last` (from 1)."""
    words = " ".join(text for _, text in lines[first - 1:last]).split()
    return " ".join(words[:WORDS]), " ".join(words[-WORDS:])


def ads_of(label, lines):
    """The ads of a label, in the fixed format, for a transcript of `lines`. A stretch that is not
    an ad, a promo or the hosts' own ask (the credits), or that does not fit the transcript, is left
    out."""
    found = []
    for item in label["segments"]:
        kind = KINDS.get(item.get("sort"))
        first, last = item.get("first"), item.get("last")
        if kind is None or not seg.whole(first) or not seg.whole(last) or not 1 <= first <= last <= len(lines):
            continue
        if not number(item.get("start")) or not number(item.get("end")) or item["end"] <= item["start"]:
            continue
        start_words, end_words = ad_words(lines, first, last)
        found.append({"kind": kind, "confidence": item["confidence"], "start": item["start"],
                      "end": item["end"], "startWords": start_words, "endWords": end_words})
    return found


def read_label(folder, identifier, labels="labels"):
    """(label, transcript lines) of an episode, the label from <folder>/<labels>. Raises OSError or
    ValueError when either is missing, damaged or has nothing in it."""
    with open(os.path.join(folder, labels, identifier + ".json"), encoding="utf-8") as f:
        label = json.load(f)
    if not isinstance(label, dict) or not isinstance(label.get("segments"), list) \
            or not number(label.get("writtenAt")):
        raise ValueError("it is not a label")
    with open(os.path.join(folder, "transcripts", identifier + ".txt"), encoding="utf-8",
              errors="replace") as f:
        lines = seg.read_transcript(f.read())
    if not lines:
        raise ValueError("its transcript has no usable lines")
    return label, lines


def read_prepared_label(folder, identifier, say):
    """(label, lines) for an episode with a copy: the snapped label when there is one that can be
    read, else the label (an unreadable snapped one is said)."""
    try:
        return read_label(folder, identifier, "labels-snapped")
    except FileNotFoundError:
        pass
    except (OSError, ValueError) as error:
        say("The snapped label of %s cannot be used (%s), so its label is used." % (identifier, error))
    return read_label(folder, identifier)


def build(folder, now, say, to=None):
    """The episodes of the file, oldest pick first: the episodes of ahead.json that have a label and
    a transcript, were marked in the last 14 days and are not in the exam or on the shelf. One that
    cannot be read is left out with one line. `to` is the iCloud copy of the phone's folder, where
    the prepared audio is looked for (None: there is none)."""
    kept = set(teach_exam.read_exam(folder)) | set(teach_shelf.read_shelf(folder))
    prepared = teach_prepared_file.copies(folder, to) if to else {}
    episodes = []
    for item in read_ahead(folder):
        if item["id"] in kept:
            continue
        try:
            label, lines = (read_prepared_label(folder, item["id"], say) if item["id"] in prepared
                            else read_label(folder, item["id"]))
        except FileNotFoundError:
            continue
        except (OSError, ValueError) as error:
            say("Left out %s: its label or transcript cannot be used (%s)." % (item["id"], error))
            continue
        marked = int(label["writtenAt"] / 1000)
        if now - marked > KEEP_SECONDS:
            continue
        found = {"feed": item["feed"], "guid": item["guid"], "title": item["title"],
                 "marked": marked, "ads": ads_of(label, lines)}
        if item["id"] in prepared:
            found["copy"] = prepared[item["id"]]
        episodes.append(found)
    return episodes


def encode(episodes, now):
    return json.dumps({"version": 1, "writtenAt": now, "episodes": episodes}, separators=(",", ":"),
                      ensure_ascii=False).encode("utf-8")


def write(folder, now, say, limit=LIMIT, to=None):
    """Writes <folder>/ahead-ads.json. Answers "written", "unchanged" (the file already says the
    same, so it keeps its time), or "nothing" (there is nothing to tell and no file). `to` is as in
    build. Raises OSError."""
    episodes = build(folder, now, say, to)
    data = encode(episodes, now)
    dropped = 0
    while len(data) > limit and episodes:
        episodes, dropped = episodes[1:], dropped + 1
        data = encode(episodes, now)
    if dropped:
        say("The list of marked episodes was too large (over %d bytes), so the %d oldest were left out."
            % (limit, dropped))
    path = os.path.join(folder, FILE)
    try:
        with open(path, encoding="utf-8") as f:
            old = json.load(f)
    except (OSError, ValueError):
        old = None
    if isinstance(old, dict) and old.get("episodes") == episodes:
        return "unchanged"
    if old is None and not episodes:
        return "nothing"
    write_atomically(path, data)
    return "written"
