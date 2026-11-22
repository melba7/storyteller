"""The pure parts of the teaching run's ad marking: reading a transcript, cutting a long one into
parts, writing the question for Claude, checking its answer and adding times to the stretches
it found. Nothing here touches files, the network or a program. teach_label.py uses it.

A transcript is a list of (seconds, text) lines. Line numbers start at 1. A segment is a dict with
first, last, sort, who, delivery, confidence and why (and, after with_times, start and end).

Run the tests: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import json
import re

SORTS = ("sponsor", "network_promo", "host_ask", "intro_credits")
CONFIDENCE = ("high", "medium", "low")
DELIVERY = ("host", "spot", "unsure")
PROMPT_VERSION = "t1"
PART_CHARS = 240000
WHO_CHARS = 80
WHY_CHARS = 200
LAST_LINE_SECONDS = 5

SYSTEM = """You mark the parts of a podcast episode that are not the episode itself, so that a player can skip them.

You get the show's name, the episode's title and the transcript. Every transcript line starts with its number and the time it begins. A speech recogniser wrote the transcript: names can be misspelt, punctuation can be wrong and nothing says who is speaking.

Mark every stretch that is one of these four sorts:

- "sponsor": a paid advertisement for a product, a service or a company. It can be a produced spot or the host reading it. Typical signs: "brought to you by", "support for this show comes from", a web address or promo code, an offer, a list of a product's benefits, a disclaimer read fast.
- "network_promo": the show, its host, its network or its publisher advertising something of their own that is not this episode: another podcast or its trailer, a live show or tour, tickets, a book, a newsletter, an app, a paid subscription or membership, a conference, merchandise.
- "host_ask": the host asking the listener to do the show a favour: follow, subscribe for free, rate, review, share, send in questions or voicemail, donate, join the Patreon.
- "intro_credits": the standing opening that is the same in every episode (theme, tagline, standard welcome) and the closing credits (who produced, edited, mixed, fact-checked, composed the music).

Do not mark:
- the episode's own content, also when a guest talks about their own book, film or company in an interview;
- a preview of what is coming later in this same episode;
- reporting about a company or a product.

Rules:
- A stretch runs from its first line to its last line. Include the lines that lead into it ("we'll be right back", "first, a word from our sponsors") and out of it ("and we're back", "welcome back").
- Advertisements for different advertisers that follow each other are separate stretches.
- If you are unsure whether a stretch is one of the four sorts or part of the episode, mark it and give it "low" confidence. Leaving out a real advertisement is worse than marking a doubtful one as low.
- "first" and "last" are line numbers taken from the transcript you were given. Stretches must not overlap.
- "who" is the advertiser or the thing promoted, in a few words, spelt as it should be if you recognise it. Use "" when there is none (credits, for example).
- "delivery" is "host" when a host of the show reads it in their own voice and words, "spot" when it is a produced advertisement or a different voice, "unsure" when the text does not tell.
- "why" is one short sentence saying what gave it away.

Answer with one JSON object and nothing else, in this shape:
{"segments": [{"first": 12, "last": 19, "sort": "sponsor", "who": "Example Mattress", "delivery": "host", "confidence": "high", "why": "Promo code and web address."}]}
List the stretches in the order they occur. If there are none, answer {"segments": []}."""

LINE = re.compile(r"^\[(\d+):(\d{2}):(\d{2}(?:\.\d+)?)\]\s*(.*)$")


# MARK: Transcript

def read_transcript(text):
    """[(seconds, text)] from lines shaped `[HH:MM:SS.t] text`. Lines that do not match, or whose
    text is empty, are skipped."""
    lines = []
    for raw in text.splitlines():
        found = LINE.match(raw.strip())
        if not found or not found.group(4).strip():
            continue
        seconds = int(found.group(1)) * 3600 + int(found.group(2)) * 60 + float(found.group(3))
        lines.append((seconds, found.group(4).strip()))
    return lines


def parts(lines, limit=PART_CHARS):
    """[(first, last)] line-number ranges that cover every line once, in order, each with at most
    `limit` characters of text. A line longer than the limit is a part by itself."""
    ranges = []
    start = 1
    size = 0
    for number, (_, text) in enumerate(lines, 1):
        if number > start and size + len(text) > limit:
            ranges.append((start, number - 1))
            start, size = number, 0
        size += len(text)
    if lines:
        ranges.append((start, len(lines)))
    return ranges


def clock(seconds):
    """Seconds as H:MM:SS."""
    whole = int(seconds)
    return "%d:%02d:%02d" % (whole // 3600, whole % 3600 // 60, whole % 60)


def prompt(show, title, lines, first, last):
    """The user message for lines `first` to `last` (numbers start at 1)."""
    head = "Show: %s\nEpisode: %s\n\n" % (show, title)
    if first != 1 or last != len(lines):
        head += ("These are lines %d to %d of %d. A stretch may have begun before them or carry "
                 "on after them.\n\n" % (first, last, len(lines)))
    body = "\n".join("%d [%s] %s" % (number, clock(lines[number - 1][0]), lines[number - 1][1])
                     for number in range(first, last + 1))
    return head + "Transcript:\n" + body


# MARK: Answer

def find_object(text):
    """The first JSON object in `text` that decodes, or None."""
    decoder = json.JSONDecoder()
    position = text.find("{")
    while position != -1:
        try:
            value, _ = decoder.raw_decode(text, position)
            if isinstance(value, dict):
                return value
        except ValueError:
            pass
        position = text.find("{", position + 1)
    return None


def whole(value):
    """True for an integer that is not a boolean."""
    return isinstance(value, int) and not isinstance(value, bool)


def text_of(value, limit):
    return value[:limit] if isinstance(value, str) else ""


def checked(item, first, last):
    """A clean copy of one answered segment, or None when it cannot be used."""
    if not isinstance(item, dict):
        return None
    start, end = item.get("first"), item.get("last")
    if not whole(start) or not whole(end) or start > end or start < first or end > last:
        return None
    if item.get("sort") not in SORTS:
        return None
    confidence = item.get("confidence")
    delivery = item.get("delivery")
    return {"first": start, "last": end, "sort": item["sort"],
            "who": text_of(item.get("who"), WHO_CHARS),
            "delivery": delivery if delivery in DELIVERY else "unsure",
            "confidence": confidence if confidence in CONFIDENCE else "low",
            "why": text_of(item.get("why"), WHY_CHARS)}


def parse(answer_text, first, last):
    """(segments, dropped) from Claude's answer for lines `first` to `last`. Raises ValueError when
    the answer holds no JSON object or its "segments" is not a list."""
    found = find_object(answer_text)
    if found is None:
        raise ValueError("the answer holds no JSON object")
    items = found.get("segments")
    if not isinstance(items, list):
        raise ValueError('"segments" is not a list')
    good = []
    dropped = 0
    for item in items:
        clean = checked(item, first, last)
        if clean is None:
            dropped += 1
        else:
            good.append(clean)
    good.sort(key=lambda s: s["first"])
    segments = []
    for item in good:
        if segments and item["first"] <= segments[-1]["last"]:
            item["first"] = segments[-1]["last"] + 1
            if item["first"] > item["last"]:
                dropped += 1
                continue
        segments.append(item)
    return segments, dropped


def merge(segments):
    """Joins a segment to the one before it when it starts on the next line and has the same sort
    and the same `who` (ignoring case): a stretch that was split at a part boundary. The joined
    segment keeps the earlier one's fields and the lower confidence."""
    joined = []
    for item in segments:
        item = dict(item)
        before = joined[-1] if joined else None
        if (before and item["first"] == before["last"] + 1 and item["sort"] == before["sort"]
                and item["who"].lower() == before["who"].lower()):
            before["last"] = item["last"]
            before["confidence"] = max(before["confidence"], item["confidence"],
                                       key=CONFIDENCE.index)
        else:
            joined.append(item)
    return joined


def with_times(segments, lines):
    """Copies of the segments with `start` and `end` in seconds (one decimal). The end is the time
    of the line after the segment, or 5 seconds after the last line when it ends the transcript."""
    timed = []
    for item in segments:
        item = dict(item)
        item["start"] = round(lines[item["first"] - 1][0], 1)
        if item["last"] < len(lines):
            item["end"] = round(lines[item["last"]][0], 1)
        else:
            item["end"] = round(lines[-1][0] + LAST_LINE_SECONDS, 1)
        timed.append(item)
    return timed
