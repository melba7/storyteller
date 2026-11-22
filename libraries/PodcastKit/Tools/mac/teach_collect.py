#!/usr/bin/env python3
"""Gathers recent episodes of the shows you follow into one folder, for the teaching run that
later marks ads.

Standard library only. It reads ~/Storyteller Lofi/LofiMusic/Podcasts/apple-podcasts.json (written
by the Apple Podcasts sync), reads every show's feed once (with a pause between them), takes the
newest episodes of each show and downloads each whole file into the teaching folder, one download
at a time with a pause between them. Nothing is sent anywhere but the feeds' and audio files' own
hosts. The folder (default ~/Storyteller Lofi/PodcastTeaching) holds:

  episodes.json        the list of episodes and what happened to each; only this tool writes it
  audio/<id>.<ext>     the downloaded audio; the name comes from the episode's id only
  transcripts/<id>.txt written by teach_transcribe.py

Running it again carries on: finished episodes are never downloaded again, failed ones are tried
once more, and new episodes are added at the end.

  teach_collect.py [--folder F] [--shows FILE] [--per-show 4] [--max-gb 12] [--keep-free-gb 15] [--list]

--list only reads the feeds and says what a run would download. Exit codes: 0 it ran, 2 the shows
file cannot be read, the folder cannot be written or episodes.json is damaged.

Run the tests: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import argparse
import hashlib
import json
import os
import re
import shutil
import sys
import tempfile
import time
import urllib.request
import xml.etree.ElementTree as ET
from email.utils import parsedate_to_datetime
from urllib.parse import urlparse

import probe_shows as probe

FOLDER = "~/Storyteller Lofi/PodcastTeaching"
MANIFEST = "episodes.json"
VERSION = 1
PER_SHOW = 4
MAX_GB = 12
KEEP_FREE_GB = 15
GB = 1_000_000_000
MAX_FILE = 600_000_000
READ_TIMEOUT = 30
DOWNLOAD_SECONDS = 20 * 60
CHUNK = 65536
AUDIO_EXTENSIONS = ("mp3", "m4a", "aac", "ogg", "opus", "wav")
ITUNES = "{http://www.itunes.com/dtds/podcast-1.0.dtd}"
ID_PATTERN = re.compile(r"^[0-9a-f]{12}$")
FILE_PATTERN = re.compile(r"^audio/([0-9a-f]{12})\.(%s)$" % "|".join(AUDIO_EXTENSIONS))
# The fields every entry of episodes.json has and the kinds of value each may hold.
FIELDS = {"id": (str,), "feed": (str,), "show": (str,), "guid": (str,), "title": (str,),
          "published": (int, float, type(None)), "seconds": (int, float, type(None)),
          "address": (str,), "size": (int, type(None)), "file": (str, type(None)),
          "bytes": (int,), "sha256": (str, type(None)), "host": (str, type(None)),
          "error": (str, type(None))}


class ManifestError(ValueError):
    """episodes.json exists but cannot be trusted."""


# MARK: Episodes

def episode_id(feed, guid, address):
    """The first 12 hex digits of the sha1 of the feed and the item's guid (or its address)."""
    return hashlib.sha1((feed + "\n" + (guid or address)).encode("utf-8")).hexdigest()[:12]


def parse_duration(text):
    """Seconds from itunes:duration written as H:MM:SS, MM:SS or plain seconds; None otherwise."""
    parts = (text or "").strip().split(":")
    if not 1 <= len(parts) <= 3 or not all(part.isdigit() and part.isascii() for part in parts):
        return None
    seconds = 0
    for part in parts:
        seconds = seconds * 60 + int(part)
    return seconds


def feed_episodes(xml_text, count):
    """The newest `count` items of an RSS feed that have audio, newest first, as dicts with guid,
    title, published, seconds, address and size. Items are ordered by pubDate; items without a date
    come after the dated ones, in the order of the feed (first is newest). Only http and https
    addresses, no video, each address once. Broken XML gives an empty list."""
    try:
        root = ET.fromstring(xml_text)
    except ET.ParseError:
        return []
    items = []
    for position, item in enumerate(root.iter("item")):
        enclosure = item.find("enclosure")
        url = (enclosure.get("url") or "").strip() if enclosure is not None else ""
        if not url.startswith(("http://", "https://")):
            continue
        if (enclosure.get("type") or "").strip().lower().startswith("video/"):
            continue
        published = None
        date = item.findtext("pubDate")
        if date:
            try:
                published = int(parsedate_to_datetime(date.strip()).timestamp())
            except (TypeError, ValueError):
                pass
        length = (enclosure.get("length") or "").strip()
        size = int(length) if length.isdigit() and length.isascii() and int(length) > 0 else None
        items.append(((float("-inf") if published is None else published, -position), {
            "guid": (item.findtext("guid") or "").strip(), "title": (item.findtext("title") or "").strip(),
            "published": published, "seconds": parse_duration(item.findtext(ITUNES + "duration")),
            "address": url, "size": size}))
    items.sort(key=lambda entry: entry[0], reverse=True)
    found, seen = [], set()
    for _, episode in items:
        if episode["address"] not in seen:
            seen.add(episode["address"])
            found.append(episode)
        if len(found) == count:
            break
    return found


def audio_name(identifier, address):
    """audio/<id>.<ext>; the extension comes from the address's path when it is a known audio type."""
    ext = os.path.splitext(urlparse(address).path)[1].lstrip(".").lower()
    return "audio/%s.%s" % (identifier, ext if ext in AUDIO_EXTENSIONS else "mp3")


def plan(shows, known_ids, per_show, fetch=probe.fetch_feed, pause=probe.PAUSE, sleep=time.sleep,
         say=print, stats=None):
    """The new episodes (not in `known_ids`) of every show, in round-robin order: every show's
    newest first (shows in file order), then every show's second newest, and so on, so a size cap
    still covers every show. A feed that fails is skipped with one line. `stats`, when given, gets
    "shows_read", the number of feeds that were read."""
    columns = []
    for index, show in enumerate(shows):
        if index:
            sleep(pause)
        try:
            episodes = feed_episodes(fetch(show["feed"]), per_show)
        except Exception as error:  # a dead feed must not stop the others
            say("  skipped %s: %s" % (show["title"], error))
            continue
        columns.append([{
            "id": episode_id(show["feed"], episode["guid"], episode["address"]), "feed": show["feed"],
            "show": show["title"], "guid": episode["guid"], "title": episode["title"],
            "published": episode["published"], "seconds": episode["seconds"],
            "address": episode["address"], "size": episode["size"], "file": None, "bytes": 0,
            "sha256": None, "host": None, "error": None} for episode in episodes])
    if stats is not None:
        stats["shows_read"] = len(columns)
    entries, taken = [], set(known_ids)
    for rank in range(per_show):
        for column in columns:
            if rank < len(column) and column[rank]["id"] not in taken:
                taken.add(column[rank]["id"])
                entries.append(column[rank])
    return entries


# MARK: Download

def download(address, path, open_url=urllib.request.urlopen, max_bytes=MAX_FILE,
             max_seconds=DOWNLOAD_SECONDS, clock=time.monotonic, chunk=CHUNK):
    """Saves a whole file to `path` (through `path`.part, renamed at the end) and returns
    {"bytes", "sha256", "host"}, the host being the one after redirects. Raises OSError or
    ValueError, with the .part removed, when the file is empty, bigger than `max_bytes`, an answer
    of type text/ (an error page) or takes longer than `max_seconds`.

    It never resumes a half-finished file: hosts that insert ads can send a different file on
    every request, so the start of one answer must not be glued to the rest of another. A new try
    starts from zero."""
    request = urllib.request.Request(address, headers={
        "User-Agent": probe.USER_AGENT, "Accept-Encoding": "identity"})
    part = path + ".part"
    deadline = clock() + max_seconds
    digest = hashlib.sha256()
    kept = 0
    try:
        with open_url(request, timeout=READ_TIMEOUT) as response:
            if (response.headers.get("Content-Type") or "").strip().lower().startswith("text/"):
                raise ValueError("the server answered with a text page, not audio")
            host = probe.host_of(response.geturl())
            with open(part, "wb") as handle:
                while True:
                    if clock() > deadline:
                        raise TimeoutError("took more than %d minutes" % (max_seconds // 60))
                    block = response.read(chunk)
                    if not block:
                        break
                    kept += len(block)
                    if kept > max_bytes:
                        raise ValueError("the file is bigger than %d MB" % (max_bytes // 1_000_000))
                    digest.update(block)
                    handle.write(block)
        if kept == 0:
            raise ValueError("the file is empty")
        os.replace(part, path)
    except BaseException:
        if os.path.exists(part):
            os.remove(part)
        raise
    return {"bytes": kept, "sha256": digest.hexdigest(), "host": host}


# MARK: Manifest

def check_entry(entry):
    """Raises ManifestError when an entry of episodes.json is not shaped as the contract says."""
    if not isinstance(entry, dict):
        raise ManifestError("an episode is not an object")
    for field, kinds in FIELDS.items():
        value = entry.get(field)
        if field not in entry or not isinstance(value, kinds) or isinstance(value, bool):
            raise ManifestError("an episode has a bad or missing \"%s\"" % field)
    if not ID_PATTERN.match(entry["id"]):
        raise ManifestError("an episode has an id that is not 12 hex digits")
    if not entry["address"].startswith(("http://", "https://")) or entry["bytes"] < 0:
        raise ManifestError("an episode has a bad address or size")
    if entry["file"] is not None:
        match = FILE_PATTERN.match(entry["file"])
        if not match or match.group(1) != entry["id"]:
            raise ManifestError("an episode's file name does not match its id")


def load_manifest(folder):
    """The entries of <folder>/episodes.json, or [] when there is no such file. Raises
    ManifestError when it is not valid JSON, has another version or is not shaped as expected."""
    path = os.path.join(folder, MANIFEST)
    try:
        with open(path, encoding="utf-8") as handle:
            data = json.load(handle)
    except FileNotFoundError:
        return []
    except (OSError, ValueError) as error:
        raise ManifestError("%s cannot be read: %s" % (path, error))
    if not isinstance(data, dict) or data.get("version") != VERSION or not isinstance(data.get("episodes"), list):
        raise ManifestError("%s is not a version %d episode list" % (path, VERSION))
    ids = set()
    for entry in data["episodes"]:
        check_entry(entry)
        if entry["id"] in ids:
            raise ManifestError("%s lists an episode twice" % path)
        ids.add(entry["id"])
    return data["episodes"]


def save_manifest(folder, entries):
    """Writes episodes.json through a temporary file in the same folder, so it is never half-written."""
    data = {"version": VERSION, "writtenAt": int(time.time() * 1000), "episodes": entries}
    handle, temporary = tempfile.mkstemp(prefix=MANIFEST + ".", suffix=".tmp", dir=folder)
    try:
        with os.fdopen(handle, "w", encoding="utf-8") as out:
            json.dump(data, out, indent=1, ensure_ascii=False)
        os.replace(temporary, os.path.join(folder, MANIFEST))
    except BaseException:
        if os.path.exists(temporary):
            os.remove(temporary)
        raise


# MARK: Collect

def collect(folder, shows, per_show, max_bytes, keep_free_bytes, fetch=probe.fetch_feed,
            download=download, free_space=lambda path: shutil.disk_usage(path).free,
            pause=probe.PAUSE, sleep=time.sleep, say=print):
    """Adds the new episodes to episodes.json and downloads every entry that has no file yet, in
    list order. Stops before a download that would take the audio on disk over `max_bytes`, or
    when the free disk space is under `keep_free_bytes`. episodes.json is saved after every
    episode. A failed download is recorded and the run carries on. Answers {"shows_read",
    "downloaded", "failed", "waiting", "files", "bytes", "why"}, `why` being "size", "space" or None."""
    entries = load_manifest(folder)
    os.makedirs(os.path.join(folder, "audio"), exist_ok=True)
    stats = {}
    entries.extend(plan(shows, {entry["id"] for entry in entries}, per_show, fetch, pause, sleep, say, stats))
    save_manifest(folder, entries)
    result = {"shows_read": stats["shows_read"], "downloaded": 0, "failed": 0, "waiting": 0,
              "files": 0, "bytes": 0, "why": None}
    first = True
    for position, entry in enumerate(entries):
        if entry["file"]:
            continue
        on_disk = sum(other["bytes"] for other in entries if other["file"])
        if on_disk + (entry["size"] or 0) > max_bytes:
            result["why"] = "size"
        elif free_space(folder) < keep_free_bytes:
            result["why"] = "space"
        if result["why"]:
            result["waiting"] = sum(1 for other in entries[position:] if not other["file"])
            break
        if not first:
            sleep(pause)
        first = False
        name = audio_name(entry["id"], entry["address"])
        say("  downloading %s: %s" % (entry["show"], entry["title"] or entry["address"]))
        try:
            info = download(entry["address"], os.path.join(folder, name))
        except Exception as error:  # one bad episode must not stop the rest
            entry["error"] = str(error) or error.__class__.__name__
            result["failed"] += 1
            say("    did not download: %s" % entry["error"])
        else:
            entry.update(file=name, bytes=info["bytes"], sha256=info["sha256"], host=info["host"], error=None)
            result["downloaded"] += 1
        save_manifest(folder, entries)
    result["files"] = sum(1 for entry in entries if entry["file"])
    result["bytes"] = sum(entry["bytes"] for entry in entries if entry["file"])
    return result


def list_command(folder, shows, per_show, fetch, sleep, say):
    """Says what a run would download, without writing anything."""
    entries = load_manifest(folder)
    stats = {}
    entries = [e for e in entries if not e["file"]] + plan(
        shows, {entry["id"] for entry in entries}, per_show, fetch, probe.PAUSE, sleep, say, stats)
    known = sum(entry["size"] or 0 for entry in entries)
    unknown = sum(1 for entry in entries if not entry["size"])
    say("Read %d show%s. A run would download %d episodes, %.1f GB in the sizes the feeds give; "
        "%d of them have no size." % (stats["shows_read"], "" if stats["shows_read"] == 1 else "s",
                                     len(entries), known / GB, unknown))
    return 0


def main(argv=None, fetch=probe.fetch_feed, download=download, sleep=time.sleep, say=print):
    parser = argparse.ArgumentParser(description="Gathers recent episodes of your shows for teaching.")
    parser.add_argument("--folder", default=FOLDER)
    parser.add_argument("--shows", default=probe.SHOWS_FILE)
    parser.add_argument("--per-show", type=int, default=PER_SHOW)
    parser.add_argument("--max-gb", type=float, default=MAX_GB)
    parser.add_argument("--keep-free-gb", type=float, default=KEEP_FREE_GB)
    parser.add_argument("--list", action="store_true")
    args = parser.parse_args(argv)
    folder = os.path.expanduser(args.folder)
    try:
        shows = probe.load_shows(args.shows)
    except (OSError, ValueError, AttributeError, TypeError) as error:
        say("Could not read your followed shows from %s: %s" % (args.shows, error))
        return 2
    try:
        if args.list:
            return list_command(folder, shows, args.per_show, fetch, sleep, say)
        say("Reading the feeds of %d shows..." % len(shows))
        result = collect(folder, shows, args.per_show, int(args.max_gb * GB), int(args.keep_free_gb * GB),
                         fetch=fetch, download=download, sleep=sleep, say=say)
    except ManifestError as error:
        say("%s\nNothing was changed. Fix or move that file and run this again." % error)
        return 2
    except OSError as error:
        say("Could not write to %s: %s" % (folder, error))
        return 2
    say("\nRead %d shows. %d episodes are on disk (%.1f GB). %d failed this time."
        % (result["shows_read"], result["files"], result["bytes"] / GB, result["failed"]))
    if result["waiting"]:
        why = ("the %.0f GB size limit was reached" % args.max_gb if result["why"] == "size"
               else "free disk space is under %.0f GB" % args.keep_free_gb)
        say("%d are still waiting because %s." % (result["waiting"], why))
    return 0


if __name__ == "__main__":
    sys.exit(main())
