#!/usr/bin/env python3
"""Picks one recent episode from each of several shows you follow, for the "Test my shows" choice
of "Compare two downloads of an episode.command", and turns the probe results into one report.

Standard library only. It reads ~/Storyteller Lofi/LofiMusic/Podcasts/apple-podcasts.json (written
by the Apple Podcasts sync), downloads each feed once (at most 30 feeds, a few seconds each, with
a pause between them), takes the newest item's audio address and groups the shows by its host.
It picks up to 8 shows from different hosts, ad-inserting hosts first. It downloads no audio;
the probe does that (3 MB twice per show). Nothing is sent anywhere but the feeds' own hosts.

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


def find_candidates(shows, fetch=fetch_feed, pause=PAUSE, say=print):
    candidates = []
    for index, show in enumerate(shows[:MAX_FEEDS]):
        if index:
            time.sleep(pause)
        try:
            address = newest_enclosure(fetch(show["feed"]))
        except Exception as error:  # a dead feed must not stop the others
            say("  skipped %s: %s" % (show["title"], error))
            continue
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
    candidates = find_candidates(shows)
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
