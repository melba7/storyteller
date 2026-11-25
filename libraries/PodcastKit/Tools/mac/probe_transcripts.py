#!/usr/bin/env python3
"""Counts which of the shows you follow carry a publisher's transcript (podcast:transcript) in their
feed, and checks one sample file of each, for "Count publisher transcripts in my shows.command".

Standard library only. It reads ~/Storyteller Lofi/LofiMusic/Podcasts/apple-podcasts.json (written by
the Apple Podcasts sync), downloads each feed once (all of them, a few seconds each, with a pause
between them) and, for each feed that carries a transcript, the newest transcript file once (at
most 300 KB). It downloads no audio and sends nothing but the requests to the feeds' own hosts. It
writes one plain report. Nothing is kept except that report.

  probe_transcripts.py <report file>

Run the tests: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import re
import sys
import time
import urllib.request
import xml.etree.ElementTree as ET

import probe_shows

SAMPLE_LIMIT = 300_000
# What a spoken ad read usually says. A publisher's transcript that has these keeps the host-read
# ads, so comparing words with it finds only the ads stitched in later.
AD_PHRASES = re.compile(r"brought to you by|sponsored by|promo code|use code|our sponsor", re.I)


def scan_feed(xml_text):
    """{"items", "with", "types", "sample"} for the newest items of a feed: how many were looked at,
    how many carry a transcript tag, the types, and the address of the newest transcript file (http or
    https only). All empty when the feed is not XML."""
    result = {"items": 0, "with": 0, "types": [], "sample": None}
    try:
        root = ET.fromstring(xml_text)
    except ET.ParseError:
        return result
    for item in list(root.iter("item"))[:probe_shows.TRANSCRIPT_ITEMS]:
        result["items"] += 1
        tags = [element for element in item.iter() if _is_transcript(element)]
        if not tags:
            continue
        result["with"] += 1
        for element in tags:
            if result["sample"] is None:
                address = (element.get("url") or "").strip()
                if address.startswith(("http://", "https://")):
                    result["sample"] = address
    result["types"] = probe_shows.transcript_types(xml_text)
    return result


def _is_transcript(element):
    tag = element.tag if isinstance(element.tag, str) else ""
    namespace, _, name = tag[1:].partition("}") if tag.startswith("{") else ("", "", "")
    return name == "transcript" and "podcast" in namespace.lower()


def check_sample(text):
    """{"words", "ad_phrases"} of a transcript file: its words (timing lines included, so a rough
    count) and how many spoken-ad phrases it holds."""
    return {"words": len(text.split()), "ad_phrases": len(AD_PHRASES.findall(text))}


def build_report(rows):
    """The report text for the rows run() makes: a summary and a line for each show."""
    read = [row for row in rows if not row["error"]]
    if not read:
        return "Publisher transcripts: No feed was read.\n"
    carrying = [row for row in read if row["with"]]
    failed = len(rows) - len(read)
    lines = ["Storyteller Lofi: publisher transcripts in the shows you follow",
             "Made %s. A feed counts when a transcript tag is in its newest %d items.\n"
             % (time.strftime("%Y-%m-%d %H:%M"), probe_shows.TRANSCRIPT_ITEMS),
             "%d of %d shows read carry a publisher's transcript." % (len(carrying), len(read))]
    if failed:
        lines.append("%d feed%s could not be read." % (failed, "" if failed == 1 else "s"))
    checked = [row for row in carrying if "words" in row]
    holding = [row for row in checked if row["ad_phrases"]]
    if checked:
        if holding:
            lines.append("%d of the %d samples that were read hold spoken ad reads (so host-read ads "
                         "are in the publisher's text)." % (len(holding), len(checked)))
        else:
            lines.append("None of the samples that were read holds a spoken ad read: those "
                         "transcripts look like the show without its ads.")
    lines.append("")
    lines.append("%-34s %-10s %-26s %s" % ("Show", "Items", "Types", "Sample (words, ad phrases)"))
    for row in rows:
        if row["error"]:
            lines.append("%-34s FAILED: %s" % (row["title"][:34], row["error"]))
            continue
        sample = "-"
        if "words" in row:
            sample = "%d words, %d ad phrases" % (row["words"], row["ad_phrases"])
        elif row["with"]:
            sample = "not read"
        lines.append("%-34s %-10s %-26s %s" % (
            row["title"][:34], "%d of %d" % (row["with"], row["items"]),
            ", ".join(row["types"])[:26] or "none", sample))
    return "\n".join(lines) + "\n"


def fetch_sample(address):
    request = urllib.request.Request(address, headers={"User-Agent": probe_shows.USER_AGENT})
    with urllib.request.urlopen(request, timeout=probe_shows.FEED_TIMEOUT) as response:
        return response.read(SAMPLE_LIMIT)


def _text(data):
    return data.decode("utf-8", errors="replace") if isinstance(data, bytes) else data


def run(shows_path, report_path, fetch=None, pause=probe_shows.PAUSE, say=print):
    """Reads every show's feed and one transcript sample of each feed that has one, writes the
    report to `report_path`. 0 when it wrote the report, 2 when the show list cannot be read."""
    try:
        shows = probe_shows.load_shows(shows_path)
    except FileNotFoundError:
        say('Your followed shows are not saved on this Mac yet. Double-click "Sync Apple Podcasts '
            'now.command" first.')
        return 2
    except (OSError, ValueError) as error:
        say("Could not read %s: %s" % (shows_path, error))
        return 2
    fetch_feed = fetch or probe_shows.fetch_feed
    fetch_file = fetch or fetch_sample
    say("Reading the feeds of %d shows..." % len(shows))
    rows = []
    for index, show in enumerate(shows):
        if index:
            time.sleep(pause)
        row = {"title": show["title"], "error": None, "items": 0, "with": 0, "types": [],
               "sample": None}
        try:
            row.update(scan_feed(_text(fetch_feed(show["feed"]))))
        except Exception as error:  # a dead feed must not stop the others
            row["error"] = str(error) or error.__class__.__name__
        if row["sample"]:
            try:
                row.update(check_sample(_text(fetch_file(row["sample"]))))
            except Exception:
                pass  # the count stays; the line says the sample was not read
        say("  %s: %s" % (row["title"], row["error"] or "%d of %d items" % (row["with"], row["items"])))
        rows.append(row)
    with open(report_path, "w", encoding="utf-8") as handle:
        handle.write(build_report(rows))
    return 0


def main(argv):
    if len(argv) != 2:
        print(__doc__)
        return 64
    return run(probe_shows.SHOWS_FILE, argv[1])


if __name__ == "__main__":
    sys.exit(main(sys.argv))
