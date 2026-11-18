#!/usr/bin/env python3
"""Picks one recent episode from each of several shows you follow, for the "Test my shows" choice
of "Compare two downloads of an episode.command", and turns the probe results into one report.

Standard library only. It reads ~/Storyteller Lofi/LofiMusic/Podcasts/apple-podcasts.json (written
by the Apple Podcasts sync), downloads each feed once (at most 30 feeds, a few seconds each, with
a pause between them), takes the newest item's audio address and groups the shows by its host.
It picks up to 8 shows from different hosts, ad-inserting hosts first. It downloads no audio;
the probe does that (3 MB twice per show). Nothing is sent anywhere but the feeds' own hosts.
While it reads the feeds it also counts the shows whose feed carries a publisher's transcript
(podcast:transcript) and saves that count next to the picks, for the report.

  probe_shows.py pick <picks file>        prints the chosen shows, writes "title<TAB>address" lines
  probe_shows.py report <folder> <file>   joins the probe outputs in <folder> into one report

Run the tests: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import json
import os
import re
import sys
import time
import urllib.request
import xml.etree.ElementTree as ET
from urllib.parse import urlparse

USER_AGENT = "StorytellerLofi/1.0 podcast client"
SHOWS_FILE = "~/Storyteller Lofi/LofiMusic/Podcasts/apple-podcasts.json"
MAX_FEEDS = 30
MAX_PICKS = 8
FEED_TIMEOUT = 15
FEED_LIMIT = 5_000_000
PAUSE = 1.0
# How many of a feed's newest items are looked at for a publisher's transcript, the file the
# report keeps the count in, and how many shows make the idea worth building.
TRANSCRIPT_ITEMS = 10
TRANSCRIPTS_FILE = "transcripts.txt"
TRANSCRIPT_MIN_SHOWS = 3

# Hosts that insert ads per download, in the order they are preferred. A host matches when its
# name contains one of these words.
AD_HOSTS = [
    "megaphone", "art19", "acast", "simplecast", "omny", "anchor", "spotify",
    "podtrac", "chartable", "chrt.fm", "pscrb",
]


def newest_enclosure(xml_text):
    """The audio address of the newest item in an RSS feed, or None. The newest item is the one
    with the latest pubDate; items without a date count by their place in the feed (first is
    newest)."""
    try:
        root = ET.fromstring(xml_text)
    except ET.ParseError:
        return None
    best = None
    best_key = None
    for position, item in enumerate(root.iter("item")):
        enclosure = item.find("enclosure")
        url = (enclosure.get("url") or "").strip() if enclosure is not None else ""
        if not url.startswith(("http://", "https://")):
            continue
        stamp = None
        date = item.findtext("pubDate")
        if date:
            try:
                from email.utils import parsedate_to_datetime
                stamp = parsedate_to_datetime(date.strip()).timestamp()
            except (TypeError, ValueError):
                stamp = None
        key = (stamp if stamp is not None else float("-inf"), -position)
        if best_key is None or key > best_key:
            best, best_key = url, key
    return best


def host_of(address):
    return (urlparse(address).hostname or "").lower()


def ad_rank(host):
    """0 for the most preferred ad-inserting host, len(AD_HOSTS) for any other host."""
    for rank, word in enumerate(AD_HOSTS):
        if word in host:
            return rank
    return len(AD_HOSTS)


def choose(candidates, limit=MAX_PICKS):
    """candidates: [{"title", "address"}]. At most one show per host, ad-inserting hosts first,
    then the others in the order given. Returns the chosen candidates."""
    first_of_host = {}
    for candidate in candidates:
        host = host_of(candidate["address"])
        if host and host not in first_of_host:
            first_of_host[host] = candidate
    order = sorted(first_of_host, key=lambda host: ad_rank(host))  # stable: ties keep feed order
    return [first_of_host[host] for host in order[:limit]]


def parse_probe(text):
    """Reads one probe's output into {"host", "same", "ranges", "matched", "percent", "error"}.
    Fields it cannot find are None."""
    result = {"host": None, "same": False, "ranges": None, "matched": None, "percent": None,
              "error": None}
    match = re.search(r"host after redirects: (\S+)", text)
    if match:
        result["host"] = match.group(1)
    if "byte for byte the same" in text:
        result["same"] = True
        return result
    match = re.search(r"byte-identical in both copies, in the same order: (\d+) \((\d+) %", text)
    if match:
        result["matched"] = int(match.group(1))
        result["percent"] = int(match.group(2))
    if "Ranges that differ and then join again: none" in text:
        result["ranges"] = 0
    else:
        result["ranges"] = len(re.findall(r"^\s+copy A .+, copy B ", text, re.M)) if (
            "Ranges that differ and then join again (candidate" in text) else None
    if result["matched"] is None:
        if "No MP3 frames" in text:
            result["error"] = "no MP3 frames"
        elif "did not download" in text:
            result["error"] = "did not download"
        elif result["host"] is None:
            result["error"] = "no result"
    return result


def summary_line(title, info):
    """One line for the table: show, host, same bytes or differing ranges, shared frames."""
    if info["error"]:
        copies = "FAILED: " + info["error"]
        frames = "-"
    elif info["same"]:
        copies = "same bytes"
        frames = "all (same file)"
    else:
        count = info["ranges"]
        copies = "differ in %d range%s" % (count, "" if count == 1 else "s") if count is not None \
            else "differ, no joined range"
        if info["matched"] == 0:
            frames = "share no frames (re-encoded)"
        elif info["matched"] is None:
            frames = "unknown"
        else:
            frames = "share %d frames (%d %%)" % (info["matched"], info["percent"])
    return "%-32s %-34s %-24s %s" % (title[:32], (info["host"] or "?")[:34], copies, frames)


# MARK: Publisher transcripts

def transcript_types(xml_text):
    """The MIME types of the podcast:transcript files in the newest items of a feed, each once,
    sorted. Empty when there are none or the feed is not XML. Either namespace of the podcast
    tags counts; a tag with no type is "unknown"."""
    try:
        root = ET.fromstring(xml_text)
    except ET.ParseError:
        return []
    types = set()
    for item in list(root.iter("item"))[:TRANSCRIPT_ITEMS]:
        for element in item.iter():
            tag = element.tag if isinstance(element.tag, str) else ""
            namespace, _, name = tag[1:].partition("}") if tag.startswith("{") else ("", "", "")
            if name == "transcript" and "podcast" in namespace.lower():
                types.add((element.get("type") or "unknown").strip().lower())
    return sorted(types)


def transcript_summary(found):
    """found: {show title: [types]} for each feed that was read. A few plain lines: how many
    shows carry a publisher's transcript, in which types, and whether that is enough to build the
    comparison of the app's words with it."""
    if not found:
        return "Publisher transcripts: No feed was read."
    carrying = [title for title, types in found.items() if types]
    counts = {}
    for types in found.values():
        for kind in types:
            counts[kind] = counts.get(kind, 0) + 1
    by_count = sorted(counts.items(), key=lambda pair: (-pair[1], pair[0]))
    kinds = ": " + ", ".join("%s %d" % pair for pair in by_count) if by_count else ""
    lines = ["Publisher transcripts (a podcast:transcript tag in a feed's newest %d items)"
             % TRANSCRIPT_ITEMS,
             "  %d of %d shows read have one%s" % (len(carrying), len(found), kinds)]
    if carrying:
        more = " and more" if len(carrying) > 12 else ""
        lines.append("  Shows: " + ", ".join(carrying[:12]) + more)
    if len(carrying) >= TRANSCRIPT_MIN_SHOWS:
        lines.append("  The app could find inserted ads by comparing its words with these "
                     "files. That is enough shows to build it.")
    else:
        lines.append("  That is fewer than %d shows, so comparing the app's words with a "
                     "publisher's transcript is not worth building yet." % TRANSCRIPT_MIN_SHOWS)
    return "\n".join(lines)


# MARK: Feeds

def load_shows(path):
    """[{"feed", "title"}] from the sync's file. Raises OSError or ValueError."""
    with open(os.path.expanduser(path), encoding="utf-8") as handle:
        data = json.load(handle)
    shows = []
    for show in data.get("shows", []):
        feed = (show.get("feed") or "").strip()
        if feed.startswith(("http://", "https://")):
            shows.append({"feed": feed, "title": (show.get("title") or feed).strip()})
    return shows


def fetch_feed(feed):
    request = urllib.request.Request(feed, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=FEED_TIMEOUT) as response:
        return response.read(FEED_LIMIT)


def find_candidates(shows, fetch=fetch_feed, pause=PAUSE, say=print, transcripts=None):
    """With `transcripts` (a dict), it also gets {title: types} for each feed that was read."""
    candidates = []
    for index, show in enumerate(shows[:MAX_FEEDS]):
        if index:
            time.sleep(pause)
        try:
            xml_text = fetch(show["feed"])
            address = newest_enclosure(xml_text)
        except Exception as error:  # a dead feed must not stop the others
            say("  skipped %s: %s" % (show["title"], error))
            continue
        if transcripts is not None:
            transcripts[show["title"]] = transcript_types(xml_text)
        if address:
            candidates.append({"title": show["title"], "address": address})
        else:
            say("  skipped %s: no episode with audio" % show["title"])
    return candidates


def pick_command(picks_path):
    try:
        shows = load_shows(SHOWS_FILE)
    except FileNotFoundError:
        print('Your followed shows are not saved on this Mac yet. Double-click "Sync Apple '
              'Podcasts now.command" first.')
        return 2
    except (OSError, ValueError) as error:
        print("Could not read %s: %s" % (SHOWS_FILE, error))
        return 2
    print("Reading the feeds of %d shows (at most %d)..." % (len(shows), MAX_FEEDS))
    found = {}
    candidates = find_candidates(shows, transcripts=found)
    summary = transcript_summary(found)
    print("\n" + summary)
    with open(os.path.join(os.path.dirname(picks_path), TRANSCRIPTS_FILE), "w",
              encoding="utf-8") as handle:
        handle.write(summary + "\n")
    picks = choose(candidates)
    if not picks:
        print("No show with an audio address was found.")
        return 1
    print("\nChosen, one per host:")
    with open(picks_path, "w", encoding="utf-8") as handle:
        for pick in picks:
            print("  %-32s %s" % (pick["title"][:32], host_of(pick["address"])))
            handle.write("%s\t%s\n" % (pick["title"].replace("\t", " "), pick["address"]))
    return 0


# MARK: Report

def build_report(folder):
    """Joins <folder>/picks.tsv with the probe outputs <folder>/1.txt, 2.txt ... into one text."""
    with open(os.path.join(folder, "picks.tsv"), encoding="utf-8") as handle:
        picks = [line.rstrip("\n").split("\t") for line in handle if line.strip()]
    parts = ["Storyteller Lofi: second quick download of each show's start",
             "Made %s. One probe per show, 3 MB downloaded twice each.\n" % time.strftime("%Y-%m-%d %H:%M")]
    lines = []
    for number, (title, address) in enumerate(picks, 1):
        try:
            with open(os.path.join(folder, "%d.txt" % number), encoding="utf-8") as handle:
                text = handle.read()
        except OSError:
            text = ""
        parts.append("=" * 72 + "\n%s\n%s\n" % (title, address) + text)
        lines.append(summary_line(title, parse_probe(text)))
    parts.append("=" * 72 + "\nSummary\n")
    parts.append("%-32s %-34s %-24s %s" % ("Show", "Host after redirects", "Copies", "Frames"))
    parts.extend(lines)
    try:
        with open(os.path.join(folder, TRANSCRIPTS_FILE), encoding="utf-8") as handle:
            parts.append("\n" + handle.read().rstrip())
    except OSError:
        pass  # the pick did not save a count
    return "\n".join(parts) + "\n"


def main(argv):
    if len(argv) == 3 and argv[1] == "pick":
        return pick_command(argv[2])
    if len(argv) == 4 and argv[1] == "report":
        with open(argv[3], "w", encoding="utf-8") as handle:
            handle.write(build_report(argv[2]))
        return 0
    print(__doc__)
    return 64


if __name__ == "__main__":
    sys.exit(main(sys.argv))
