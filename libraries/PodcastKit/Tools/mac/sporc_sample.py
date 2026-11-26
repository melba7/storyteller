#!/usr/bin/env python3
"""Takes a small sample of the SPoRC public podcast transcripts (Hugging Face blitt/SPoRC, released
for research and educational use only) and writes it as a teaching folder, so Claude can mark its
ads with `teach_label.py --folder` and the word model can learn from many more shows than the ones
you follow.

It needs pyarrow and huggingface_hub (the launcher "Fetch a sample of public transcripts.command"
installs them in its own folder) and a Hugging Face login that has accepted the dataset's terms.
It downloads two files: the episode catalog (metadata/episode_catalog.parquet) and one part of the
turn texts (turns/text/part-*.parquet, --part N counts from 0). From the English episodes of that
part it picks --count episodes of 20 minutes to 2.5 hours, spread over as many shows as it can
(at most 2 from a show), and writes into --out: episodes.json, transcripts/<id>.txt (lines of
"[hh:mm:ss.s] sentence", times worked out from each turn's start and end), SOURCE.txt and
SAMPLE-REPORT.txt. The data is only turn-level text: no audio, no word times. Nothing is committed
or sent anywhere. Calling it again adds to what is there.

  sporc_sample.py --out FOLDER [--count 500] [--part 0]

Run the tests: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import argparse
import hashlib
import os
import re
import sys

import probe_transcripts
import teach_feed
import teach_store as store

REPO = "blitt/SPoRC"
CATALOG = "metadata/episode_catalog.parquet"
TURNS = re.compile(r"^turns/text/part-.*\.parquet$")
LINK = "https://huggingface.co/datasets/blitt/SPoRC"
MIN_SECONDS = 20 * 60
MAX_SECONDS = 150 * 60
CATALOG_COLUMNS = ["episode_id", "podcast_id", "ep_title", "mp3_url", "duration_seconds", "language",
                   "category1", "episode_date"]
TURN_COLUMNS = ["episode_id", "turn_count", "turn_text", "start_time", "end_time"]
SENTENCE_END = re.compile(r"(?<=[.!?])\s+")
SOURCE_NOTE = """These transcripts come from SPoRC (Structured Podcast Research Corpus, {link}),
which is released for research and educational use only.

Keep these files on this Mac. Never commit them (the repository is public), never share them, and
keep anything learned from them out of a build that is published to other people.

Cite: Litterer, Jurgens and Card, "Mapping the Podcast Ecosystem with the Structured Podcast
Research Corpus", ACL 2025.
"""


# MARK: Choosing

def _digest(text):
    return hashlib.md5(str(text).encode("utf-8")).hexdigest()


def choose_episodes(rows, available, count, per_podcast=2, min_seconds=MIN_SECONDS,
                    max_seconds=MAX_SECONDS):
    """Up to `count` of the catalog `rows` (dicts) that are English, have turns (their id is in
    `available`) and last min_seconds to max_seconds, spread over shows: every show gives one
    episode before any gives a second, at most per_podcast each. The same input gives the same
    choice, whatever the order of the rows."""
    by_show = {}
    for item in rows:
        seconds = item.get("duration_seconds")
        if item["episode_id"] not in available or not (item.get("language") or "").lower().startswith("en"):
            continue
        if not isinstance(seconds, (int, float)) or not min_seconds <= seconds <= max_seconds:
            continue
        by_show.setdefault(item["podcast_id"], []).append(item)
    shows = sorted(by_show, key=_digest)
    for show in shows:
        by_show[show].sort(key=lambda item: _digest(item["episode_id"]))
    chosen = []
    for place in range(per_podcast):
        for show in shows:
            if place < len(by_show[show]) and len(chosen) < count:
                chosen.append(by_show[show][place])
    return chosen


# MARK: Text

def _stamp(seconds):
    tenths = int(round(seconds * 10))
    return "[%02d:%02d:%02d.%d]" % (tenths // 36000, tenths // 600 % 60, tenths % 600 // 10, tenths % 10)


def lines_from_turns(turns):
    """Transcript lines "[hh:mm:ss.s] sentence" from turns (dicts with turn_count, turn_text,
    start_time, end_time). A turn is cut into sentences and each sentence starts at the time its
    share of the turn's characters has reached. A turn without a usable time starts where the last
    one ended."""
    lines = []
    last = 0.0
    for turn in sorted(turns, key=lambda turn: turn.get("turn_count") or 0):
        text = (turn.get("turn_text") or "").strip()
        if not text:
            continue
        start, end = turn.get("start_time"), turn.get("end_time")
        if not isinstance(start, (int, float)) or not isinstance(end, (int, float)) or end < start:
            start = end = last
        sentences = [part.strip() for part in SENTENCE_END.split(text) if part.strip()]
        total = sum(len(part) for part in sentences)
        done = 0
        for part in sentences:
            lines.append("%s %s" % (_stamp(start + (end - start) * done / total), part))
            done += len(part)
        last = end
    return lines


# MARK: The folder

def _entry(item):
    address = item.get("mp3_url") or ""
    if not address.startswith(("http://", "https://")):
        address = "https://sporc.invalid/episode/" + item["episode_id"]
    feed = "https://sporc.invalid/podcast/" + str(item["podcast_id"])
    date = item.get("episode_date")
    try:
        published = int(int(date) / 1000)
    except (TypeError, ValueError):
        published = None
    seconds = item.get("duration_seconds")
    return {"id": teach_feed.episode_id(feed, item["episode_id"], address), "feed": feed,
            "show": "SPoRC " + str(item["podcast_id"]), "guid": item["episode_id"],
            "title": item.get("ep_title") or item["episode_id"], "published": published,
            "seconds": seconds if isinstance(seconds, (int, float)) else None, "address": address,
            "size": None, "file": None, "bytes": 0, "sha256": None, "host": "sporc", "error": None}


def _read(path):
    try:
        with open(path, encoding="utf-8") as handle:
            return handle.read()
    except OSError:
        return None


def write_folder(folder, rows, turns):
    """Writes transcripts/<id>.txt for every row whose id has lines in `turns` ({episode id:
    [lines]}), adds the entries to episodes.json (what was there stays) and writes SOURCE.txt.
    A transcript that is already there with the same text is left alone, so a bigger sample
    adds episodes without touching the ones a marking or a test may be reading.
    Returns the rows that were written."""
    try:
        entries = {entry["id"]: entry for entry in store.load_manifest(folder)}
    except (FileNotFoundError, store.ManifestError):
        entries = {}
    os.makedirs(os.path.join(folder, "transcripts"), exist_ok=True)
    written = []
    for item in rows:
        lines = turns.get(item["episode_id"]) or []
        if not lines:
            continue
        entry = _entry(item)
        path = os.path.join(folder, "transcripts", entry["id"] + ".txt")
        text = "\n".join(lines) + "\n"
        if _read(path) != text:
            with open(path, "w", encoding="utf-8") as out:
                out.write(text)
        entries[entry["id"]] = entry
        written.append(item)
    store.save_manifest(folder, list(entries.values()))
    with open(os.path.join(folder, "SOURCE.txt"), "w", encoding="utf-8") as out:
        out.write(SOURCE_NOTE.format(link=LINK))
    return written


def build_report(rows, turns):
    """A few plain lines about the sample: episodes, hours, shows and how many hold ad phrases."""
    hours = sum(item["duration_seconds"] for item in rows) / 3600
    shows = len({item["podcast_id"] for item in rows})
    holding = sum(1 for item in rows if probe_transcripts.AD_PHRASES.search(" ".join(turns[item["episode_id"]])))
    words = sum(len(" ".join(turns[item["episode_id"]]).split()) for item in rows)
    return ("SPoRC sample: %d episodes, %.1f hours, %d shows, about %d words.\n"
            "%d of %d episodes hold a spoken ad phrase (so the ads are still in the text).\n"
            % (len(rows), hours, shows, words, holding, len(rows)))


# MARK: Parquet

def _compute():
    import pyarrow.compute as pc
    import pyarrow.parquet as pq
    return pc, pq


def read_turn_ids(path):
    """The episode ids that have turns in one turns file."""
    _, pq = _compute()
    return set(pq.read_table(path, columns=["episode_id"])["episode_id"].unique().to_pylist())


def read_catalog(path, ids=None):
    """The English episodes of the catalog (limited to `ids` when given) as dicts."""
    pc, pq = _compute()
    names = pq.read_schema(path).names
    table = pq.read_table(path, columns=[name for name in CATALOG_COLUMNS if name in names])
    mask = pc.starts_with(pc.utf8_lower(pc.fill_null(table["language"], "")), "en")
    if ids is not None:
        import pyarrow as pa
        mask = pc.and_(mask, pc.is_in(table["episode_id"], value_set=pa.array(sorted(ids), pa.string())))
    return table.filter(mask).to_pylist()


def read_turns(path, ids):
    """{episode id: [turn dicts]} for the episodes in `ids`."""
    _, pq = _compute()
    table = pq.read_table(path, columns=TURN_COLUMNS, filters=[("episode_id", "in", sorted(ids))])
    turns = {}
    for turn in table.to_pylist():
        turns.setdefault(turn["episode_id"], []).append(turn)
    return turns


# MARK: Running

def _gated(error):
    text = ("%s %s" % (type(error).__name__, error)).lower()
    return any(word in text for word in ("gated", "403", "401", "restricted", "accept the conditions"))


def _hub_listing():
    from huggingface_hub import HfApi
    return HfApi().list_repo_files(REPO, repo_type="dataset")


def _hub_fetch(name):
    from huggingface_hub import hf_hub_download
    return hf_hub_download(REPO, name, repo_type="dataset")


def run(out, count=500, part=0, fetch=None, listing=None, say=print):
    """Makes the sample folder `out`. 0 when it did, 2 when it could not (the message says why)."""
    try:
        names = (listing or _hub_listing)()
    except ImportError:
        say("pyarrow or huggingface_hub is missing. Double-click the launcher, which installs them.")
        return 2
    except Exception as error:
        say(_gated_message(error) if _gated(error) else "Could not list the dataset: %s" % error)
        return 2
    parts = sorted(name for name in names if TURNS.match(name))
    if CATALOG not in names or part >= len(parts):
        say("The dataset does not have the files this expects (%s and %d turn parts). Its layout "
            "may have changed." % (CATALOG, len(parts)))
        return 2
    try:
        say("Downloading the episode catalog (this can take a few minutes the first time)...")
        catalog = (fetch or _hub_fetch)(CATALOG)
        say("Downloading one part of the transcripts: %s ..." % parts[part])
        turns_file = (fetch or _hub_fetch)(parts[part])
    except Exception as error:
        say(_gated_message(error) if _gated(error) else "The download did not work: %s" % error)
        return 2
    ids = read_turn_ids(turns_file)
    chosen = choose_episodes(read_catalog(catalog, ids), ids, count)
    if not chosen:
        say("No English episode of 20 minutes to 2.5 hours was found in this part. Try --part 1.")
        return 2
    turns = {key: lines_from_turns(value)
             for key, value in read_turns(turns_file, {item["episode_id"] for item in chosen}).items()}
    written = write_folder(out, chosen, turns)
    report = build_report(written, turns)
    with open(os.path.join(out, "SAMPLE-REPORT.txt"), "w", encoding="utf-8") as handle:
        handle.write(report)
    say(report.rstrip())
    return 0


def _gated_message(error):
    return ("Hugging Face did not let this login read the dataset (%s). Open %s while signed in, "
            "click Agree on its terms, and double-click the launcher again." % (type(error).__name__, LINK))


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--out", required=True)
    parser.add_argument("--count", type=int, default=500)
    parser.add_argument("--part", type=int, default=0)
    args = parser.parse_args(argv[1:])
    if args.count < 1 or args.part < 0:
        parser.error("--count must be at least 1 and --part at least 0")
    return run(os.path.expanduser(args.out), args.count, args.part)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
