"""Learns from what you tapped: per-show lines for Claude, made from the phone's notes.

Standard library only. The phone writes Podcasts/phone-notes.jsonl into its linked folder
(teach_feedback.py describes the notes). The notes of a prepared episode say by "prepared". This reads
the new ones and turns three kinds into one short line each:

  undone   you took back a skip (Undo): the line gives the first and the last words of the skip.
  trimmed  you went back into a skip: it went too far, and the line says where.
  missed   you pressed Skip ad where nothing was marked: the line gives the words there.

The words come from the episode's transcript on this Mac. A tap moves no skip by itself: the lines
only go into the prompt when Claude marks that show's next episodes (teach_label.py --only-ahead,
through guidance()). At most 20 lines are kept per show, the newest.

  teach_taps.py learn [--folder F]

The lines are kept in <folder>/show-taps.json, with the time of the newest note already read:

  {"version": 1, "readThrough": <ms>, "shows": {"<feed key>": {"show": "...", "lines": [{"at": <ms>, "text": "..."}]}}}

They hold words from transcripts, so the file stays on this Mac and is listed in .gitignore. A notes
file that cannot be read (for instance an iCloud file that is not downloaded yet) is said in one line
and the run goes on. The run's log says how many notes were read.

Run the tests: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import argparse
import json
import os
import sys

import teach_feedback
import teach_segments as seg
import teach_store
from apple_podcasts_export import default_folders
from teach_feedback_prepared import plural
from teach_feed import feed_key

FILE = "show-taps.json"
MOST_LINES = 20
KINDS = ("undone", "trimmed", "missed")
BY = "prepared"
WORDS = 20  # the most words of one quoted stretch
QUOTED = 2  # the most transcript lines quoted from one place


def clock(seconds):
    """Seconds as H:MM:SS, or M:SS below an hour."""
    whole = int(seconds)
    if whole >= 3600:
        return "%d:%02d:%02d" % (whole // 3600, whole % 3600 // 60, whole % 60)
    return "%d:%02d" % (whole // 60, whole % 60)


def words_at(lines, seconds, last=False):
    """The words said at `seconds` (or just before it when `last`): up to QUOTED transcript lines,
    cut to WORDS words, in quotation marks. "" when the transcript is empty."""
    if not lines:
        return ""
    index = max((i for i, (start, _) in enumerate(lines) if start <= seconds), default=0)
    chosen = lines[max(0, index - QUOTED + 1):index + 1] if last else lines[index:index + QUOTED]
    words = " ".join(text for _, text in chosen).split()
    return '"%s"' % " ".join(words[-WORDS:] if last else words[:WORDS])


def line_for(note, lines):
    """The short line a note becomes, or None when it is not of a kind that teaches (or has no
    place in the transcript). `lines` is the episode's transcript as [(seconds, text)]."""
    kind, start, end = note["what"], note["start"], note["end"]
    if kind not in KINDS or not lines:
        return None
    if kind == "missed":
        return ("Skip ad pressed at %s where nothing was marked, so a break may start here. The words "
                "there were: %s." % (clock(start), words_at(lines, start)))
    if end is None or end <= start:
        end = start
    span = "%s to %s" % (clock(start), clock(end))
    if kind == "undone":
        return ("Undo of a skip from %s: the break may have started later or ended earlier than "
                "marked, or was none. It began with %s and ended with %s."
                % (span, words_at(lines, start), words_at(lines, end, last=True)))
    return ("A skip from %s went too far: you went back into it, so the break ended earlier than "
            "marked. It began with %s and the words just before its end were %s."
            % (span, words_at(lines, start), words_at(lines, end, last=True)))


def read_taps(folder):
    """(readThrough, {feed key: {"show", "lines"}}) from show-taps.json, (0, {}) when there is none
    or it cannot be used."""
    try:
        with open(os.path.join(folder, FILE), encoding="utf-8") as f:
            data = json.load(f)
        shows = data["shows"]
        through = data["readThrough"]
        if data["version"] != 1 or not isinstance(shows, dict) or not teach_feedback.number(through):
            raise ValueError("not the file")
        for one in shows.values():
            if not isinstance(one["lines"], list) or not all(
                    isinstance(x["text"], str) and teach_feedback.number(x["at"]) for x in one["lines"]):
                raise ValueError("not the file")
        return through, shows
    except (OSError, ValueError, KeyError, TypeError, AttributeError):
        return 0, {}


def episode_lookup(folder):
    """{(feed key, guid or audio address): (id, show)} of episodes.json, {} when it cannot be read."""
    try:
        entries = teach_store.load_manifest(folder)
    except (teach_store.ManifestError, OSError):
        return {}
    found = {}
    for one in entries:
        for name in (one["guid"], one["address"]):
            if name:
                found[(feed_key(one["feed"]), name)] = (one["id"], one["show"])
    return found


def transcript_of(folder, identifier):
    try:
        with open(os.path.join(folder, "transcripts", identifier + ".txt"), encoding="utf-8",
                  errors="replace") as f:
            return seg.read_transcript(f.read())
    except OSError:
        return []


def learn(folder, say, defaults=default_folders):
    """Reads the notes that are new since the last time and adds their lines. Returns 0, or 2 when
    show-taps.json cannot be written. A notes file that cannot be read is said and is not an error."""
    denied = []
    path = teach_feedback.find_notes(defaults, denied)
    if path is None:
        say("Taps: no phone notes to read yet%s." % (" (macOS did not let this read %s)" % denied[0]
                                                      if denied else ""))
        return 0
    try:
        notes, bad = teach_feedback.read_notes(path)
    except (OSError, ValueError) as error:
        say("Taps: the notes in %s could not be read (%s), so they are skipped this time. If the file "
            "is in iCloud and not downloaded yet, opening it once on this Mac downloads it." % (path, error))
        return 0
    through, shows = read_taps(folder)
    fresh = [one for one in notes if one["at"] > through]
    lookup = episode_lookup(folder)
    cache, made, no_words = {}, 0, 0
    for one in sorted(fresh, key=lambda note: note["at"]):
        if one.get("by") != BY or one["what"] not in KINDS:
            continue
        found = lookup.get((feed_key(one["feed"]), one["guid"] or one["address"]))
        if found is None:
            no_words += 1
            continue
        if found[0] not in cache:
            cache[found[0]] = transcript_of(folder, found[0])
        text = line_for(one, cache[found[0]])
        if text is None:
            no_words += 1
            continue
        entry = shows.setdefault(feed_key(one["feed"]), {"show": found[1], "lines": []})
        entry["lines"] = (entry["lines"] + [{"at": one["at"], "text": text}])[-MOST_LINES:]
        made += 1
    newest = max([one["at"] for one in fresh], default=through)
    try:
        teach_store.write_json(os.path.join(folder, FILE),
                               {"version": 1, "readThrough": newest, "shows": shows})
    except OSError as error:
        say("Taps: %s could not be written (%s)." % (FILE, error))
        return 2
    say("Taps: read %s from the phone (%s new, %d of those by prepared episodes); %s made, %d left "
        "out (no transcript on this Mac or no place in it)%s."
        % (plural(len(notes), "note", "notes"), len(fresh), sum(1 for o in fresh if o.get("by") == BY),
           plural(made, "line", "lines"), no_words, "; %s were not valid notes" % bad if bad else ""))
    return 0


def guidance(folder):
    """{feed key: [the show's lines, oldest first]} for the prompt of the marking."""
    return {key: [x["text"] for x in one["lines"]] for key, one in read_taps(folder)[1].items()
            if one["lines"]}


def main(argv, say=print, defaults=default_folders):
    parser = argparse.ArgumentParser(prog="teach_taps.py")
    parser.add_argument("command", choices=("learn",))
    parser.add_argument("--folder", default=teach_store.FOLDER)
    try:
        options = parser.parse_args(argv)
    except SystemExit as stop:
        return stop.code if isinstance(stop.code, int) else 2
    return learn(os.path.expanduser(options.folder), say, defaults)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
