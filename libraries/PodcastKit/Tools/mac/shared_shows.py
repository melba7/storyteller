#!/usr/bin/env python3
"""Gets the start of two episodes of each of up to 3 shows you follow, for the "Compare my shows"
choice of "Compare two episodes of a show.command", and turns the results of `podcast-ads
--shared` into one report with a table at the end.

Standard library only. It reads ~/Storyteller Lofi/LofiMusic/Podcasts/apple-podcasts.json (written
by the Apple Podcasts sync), downloads each feed once (at most 30 feeds, with a pause between
them), takes the two newest episodes of each show and picks up to 3 shows from different hosts,
ad-inserting hosts first (the way probe_shows.py picks). It then downloads only the first 20 MB of
each of those episodes with a Range request (the first minutes are where pre-roll ads sit), one
download at a time with a pause between them: 6 downloads, at most 120 MB. Nothing is sent
anywhere but the feeds' own hosts.

  shared_shows.py prepare <work folder>        reads the feeds, downloads the starts into the work
                                               folder, writes shows.json and pairs.tsv there
  shared_shows.py report <work folder> <file>  joins the --shared outputs (1.txt, 2.txt ...) in
                                               the work folder into one report

Run the tests: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import json
import os
import re
import sys
import time
import urllib.request
import xml.etree.ElementTree as ET
from email.utils import parsedate_to_datetime

import probe_shows as probe

HEAD_BYTES = 20_000_000
MAX_SHOWS = 3
EPISODES = 2
DOWNLOAD_TIMEOUT = 30
DOWNLOAD_SECONDS = 300
CHUNK = 65536
TABLE_HEADING = "All shows at a glance"


# MARK: Episodes

def newest_enclosures(xml_text, count=EPISODES):
    """The audio addresses of the newest `count` items of an RSS feed, newest first, each address
    once. Items are ordered by pubDate; items without a date come after the dated ones, in the
    order of the feed (first is newest). Items without an audio address are left out."""
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
        stamp = float("-inf")
        date = item.findtext("pubDate")
        if date:
            try:
                stamp = parsedate_to_datetime(date.strip()).timestamp()
            except (TypeError, ValueError):
                pass
        items.append(((stamp, -position), url))
    items.sort(key=lambda entry: entry[0], reverse=True)
    found = []
    for _, url in items:
        if url not in found:
            found.append(url)
        if len(found) == count:
            break
    return found


def find_candidates(shows, fetch=probe.fetch_feed, pause=probe.PAUSE, say=print):
    """[{"title", "address", "addresses"}] for the shows whose feed has two episodes with audio.
    `address` is the newest episode's, which the choice by host looks at."""
    candidates = []
    for index, show in enumerate(shows[:probe.MAX_FEEDS]):
        if index:
            time.sleep(pause)
        try:
            addresses = newest_enclosures(fetch(show["feed"]))
        except Exception as error:  # a dead feed must not stop the others
            say("  skipped %s: %s" % (show["title"], error))
            continue
        if len(addresses) < EPISODES:
            say("  skipped %s: fewer than %d episodes with audio" % (show["title"], EPISODES))
            continue
        candidates.append({"title": show["title"], "address": addresses[0], "addresses": addresses})
    return candidates


def choose_shows(candidates):
    """At most MAX_SHOWS shows, one per host, ad-inserting hosts first."""
    return probe.choose(candidates, limit=MAX_SHOWS)


# MARK: Downloads

def download_head(address, path, limit=HEAD_BYTES, timeout=DOWNLOAD_TIMEOUT,
                  open_url=urllib.request.urlopen):
    """Saves the first `limit` bytes of an address to `path` and stops reading there, so a server
    that ignores the Range request does not send the whole episode. Raises OSError when the
    download fails. Returns {"bytes", "status", "total", "note", "host"}: how much was kept, the
    answer code (206 means the range was honoured), the size of the whole file if the server
    said, a note when the server ignored the range, and the host after redirects."""
    request = urllib.request.Request(address, headers={
        "User-Agent": probe.USER_AGENT, "Range": "bytes=0-%d" % (limit - 1),
        "Accept-Encoding": "identity"})
    deadline = time.monotonic() + DOWNLOAD_SECONDS
    kept = 0
    with open_url(request, timeout=timeout) as response:
        status = response.status
        host = probe.host_of(response.geturl())
        match = re.search(r"/(\d+)\s*$", response.headers.get("Content-Range") or "")
        length = response.headers.get("Content-Length")
        total = int(match.group(1)) if match else (int(length) if length and length.isdigit() else None)
        with open(path, "wb") as handle:
            while kept < limit:
                if time.monotonic() > deadline:
                    raise TimeoutError("took more than %d minutes" % (DOWNLOAD_SECONDS // 60))
                chunk = response.read(min(CHUNK, limit - kept))
                if not chunk:
                    break
                handle.write(chunk)
                kept += len(chunk)
    note = ""
    if status == 200 and kept >= limit and (total is None or total > limit):
        note = "the server ignored the Range request; the download was stopped after the first bytes"
    return {"bytes": kept, "status": status, "total": total, "note": note, "host": host}


def prepare(work, shows, fetch=probe.fetch_feed, download=download_head, pause=probe.PAUSE,
            sleep=time.sleep, say=print):
    """Finds the shows' episodes, downloads the start of each into `work` as <show>-<n>.mp3 and
    writes shows.json (for the report) and pairs.tsv ("number<TAB>first<TAB>second" for each show
    whose two downloads worked). Answers how many shows are ready to compare."""
    picks = choose_shows(find_candidates(shows, fetch=fetch, pause=pause, say=say))
    entries = []
    first = True
    for number, pick in enumerate(picks, 1):
        say("[%d] %s" % (number, pick["title"]))
        entry = {"number": number, "title": pick["title"], "host": probe.host_of(pick["address"]),
                 "ready": True, "episodes": []}
        for which, address in enumerate(pick["addresses"], 1):
            episode = {"address": address, "file": None, "bytes": 0, "status": None, "total": None,
                       "note": "", "error": None}
            entry["episodes"].append(episode)
            if not entry["ready"]:
                episode["error"] = "not downloaded, because the first episode failed"
                continue
            if not first:
                sleep(pause)
            first = False
            path = os.path.join(work, "%d-%d.mp3" % (number, which))
            try:
                info = download(address, path)
            except Exception as error:
                entry["ready"] = False
                episode["error"] = str(error) or error.__class__.__name__
                if os.path.exists(path):
                    os.remove(path)
                say("    episode %d did not download: %s" % (which, episode["error"]))
                continue
            episode.update(file=path, bytes=info["bytes"], status=info["status"],
                           total=info["total"], note=info["note"])
            if which == 1 and info.get("host"):
                entry["host"] = info["host"]
            say("    episode %d: %.1f MB" % (which, info["bytes"] / 1e6))
        entries.append(entry)
    with open(os.path.join(work, "shows.json"), "w", encoding="utf-8") as handle:
        json.dump(entries, handle, indent=1)
    ready = [entry for entry in entries if entry["ready"]]
    with open(os.path.join(work, "pairs.tsv"), "w", encoding="utf-8") as handle:
        for entry in ready:
            handle.write("%d\t%s\t%s\n" % (entry["number"], entry["episodes"][0]["file"],
                                           entry["episodes"][1]["file"]))
    return len(ready)


def prepare_command(work):
    try:
        shows = probe.load_shows(probe.SHOWS_FILE)
    except FileNotFoundError:
        print('Your followed shows are not saved on this Mac yet. Double-click "Sync Apple '
              'Podcasts now.command" first.')
        return 2
    except (OSError, ValueError) as error:
        print("Could not read %s: %s" % (probe.SHOWS_FILE, error))
        return 2
    print("Reading the feeds of %d shows (at most %d)..." % (len(shows), probe.MAX_FEEDS))
    ready = prepare(work, shows)
    if ready == 0:
        print("No show could be compared: none had two episodes that downloaded.")
        return 1
    print("\n%d show%s ready to compare." % (ready, "" if ready == 1 else "s"))
    return 0


# MARK: Report

def parse_shared(text):
    """Reads the output of `podcast-ads --shared` into {"error", "runs", "longest", "both_ends"}:
    why it failed (or None), how many runs, the longest one in seconds, and how many runs have a
    reservoir reset or a change of encoding at both ends, in the first and in the second episode."""
    info = {"error": None, "runs": 0, "longest": 0.0, "both_ends": [0, 0]}
    if "Frames that are the same bytes in two episodes" not in text:
        lines = [line.strip() for line in text.splitlines() if line.strip()]
        info["error"] = lines[0][:90] if lines else "no result"
        return info
    for block in re.split(r"^(?=Run \d+: )", text, flags=re.M)[1:]:
        match = re.match(r"Run \d+: ([\d.]+) s", block)
        info["runs"] += 1
        info["longest"] = max(info["longest"], float(match.group(1)))
        side = None
        marked = {}  # (side, "start" or "end") -> whether the bytes say something there
        for line in block.splitlines():
            if line.startswith("  In the first episode"):
                side = 0
            elif line.startswith("  In the second episode"):
                side = 1
            elif side is not None and re.match(r"\s+(start|end): ", line):
                marked[(side, line.split(":")[0].strip())] = "nothing within" not in line
        for number in (0, 1):
            if marked.get((number, "start")) and marked.get((number, "end")):
                info["both_ends"][number] += 1
    return info


def table_line(title, host, info):
    """One line for the table: show, host, runs, the longest run, runs marked at both ends."""
    if info["error"]:
        rest = "FAILED: " + info["error"]
    elif info["runs"] == 0:
        rest = "%-5s %-9s %s" % (0, "none", "-")
    else:
        rest = "%-5d %-9s %d / %d" % (info["runs"], "%.1f s" % info["longest"],
                                      info["both_ends"][0], info["both_ends"][1])
    return "%-30s %-30s %s" % (title[:30], (host or "?")[:30], rest)


def megabytes(count):
    return "%.1f MB" % (count / 1e6)


def episode_lines(number, episode):
    label = "newest" if number == 1 else "the one before"
    lines = ["  Episode %d (%s): %s" % (number, label, episode["address"])]
    if episode["error"]:
        lines.append("    did not download: %s" % episode["error"])
        return lines
    size = megabytes(episode["bytes"])
    if episode["total"]:
        size += " of " + megabytes(episode["total"])
    lines.append("    kept the first %s (answer %s)" % (size, episode["status"]))
    if episode["note"]:
        lines.append("    " + episode["note"])
    return lines


def build_report(work):
    """Joins <work>/shows.json with the outputs <work>/1.txt, 2.txt ... into one text that ends
    with a table."""
    with open(os.path.join(work, "shows.json"), encoding="utf-8") as handle:
        shows = json.load(handle)
    parts = [
        "Storyteller Lofi: are the ads that come back in a show's episodes the same bytes?",
        "Made %s.\n" % time.strftime("%Y-%m-%d %H:%M"),
        "For each show you follow (up to 3, from different hosts) the two newest episodes were "
        "compared. Only the first 20 MB of each episode was downloaded (a Range request, about "
        "the first 20 minutes of a typical 128 kbps file), because the start of an episode is "
        "where a pre-roll ad sits. Ads later in an episode are not looked at. The downloads were "
        "kept in a temporary folder and deleted afterwards.\n"]
    rows = []
    for show in shows:
        parts.append("=" * 72 + "\n%s\n" % show["title"])
        parts.append("Host after redirects: %s" % show["host"])
        for number, episode in enumerate(show["episodes"], 1):
            parts.extend(episode_lines(number, episode))
        if show["ready"]:
            try:
                with open(os.path.join(work, "%d.txt" % show["number"]), encoding="utf-8") as handle:
                    text = handle.read()
            except OSError:
                text = ""
            parts.append("\n" + text)
            info = parse_shared(text)
        else:
            failed = next(episode["error"] for episode in show["episodes"] if episode["error"])
            parts.append("")
            info = {"error": "did not download: " + failed}
        rows.append(table_line(show["title"], show["host"], info))
    parts.append("=" * 72 + "\n" + TABLE_HEADING + "\n")
    parts.append("Runs: stretches of 3 s or more that are the same bytes in both episodes. Both ends "
                 "marked: runs whose start and end each have a bit reservoir reset or a change of "
                 "encoding within 2 frames, in the first and in the second episode. Resets also "
                 "happen inside ordinary audio, so listen at the times of the long runs to see "
                 "whether they are ads.\n")
    parts.append("%-30s %-30s %-5s %-9s %s" % (
        "Show", "Host after redirects", "Runs", "Longest", "Both ends marked (1st / 2nd)"))
    parts.extend(rows)
    return "\n".join(parts) + "\n"


def main(argv):
    if len(argv) == 3 and argv[1] == "prepare":
        return prepare_command(argv[2])
    if len(argv) == 4 and argv[1] == "report":
        with open(argv[3], "w", encoding="utf-8") as handle:
            handle.write(build_report(argv[2]))
        return 0
    print(__doc__)
    return 64


if __name__ == "__main__":
    sys.exit(main(sys.argv))
