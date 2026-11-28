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
  failures.json        which episodes failed in the later steps (teach_failures.py)
  .lock                keeps two runs from working in the folder at once

Running it again carries on: finished episodes are never downloaded again, failed ones are tried
once more (with the address the feed gives now), and new episodes are added at the end. An episode
that is bigger than the file limit is marked "skipped: ..." and not tried again.

  teach_collect.py [--folder F] [--shows FILE] [--per-show 4] [--wanted 20] [--max-gb 12]
                   [--keep-free-gb 15] [--exam] [--exam-most 60] [--list]

When the folder has a wanted.json (teach_feedback.py writes it from the phone's notes), the episodes
in it are planned before the newest episodes of each show, whatever --per-show says, at most
--wanted of them in one run. A wanted episode is matched to a followed show by its feed key (see teach_feed.feed_key), so the
phone's spelling of a feed finds the show, and is planned under the show's own feed address and id.
It is looked up in the show's feed by guid (or by audio address when it has no guid). One whose
feed is not followed, whose address is not http or https, that is no longer in its feed, or that is
already gathered, is left out and counted. A damaged wanted.json is ignored.

--exam gathers a sealed exam instead (see teach_exam.py): wanted.json is ignored for the run, of the new
episodes only those whose published time is later than the newest of every episode of the same feed
already in episodes.json are kept (one with no published time is not), at most --exam-most (default
60, the exam episodes already in exam.json counting) in the planner's round-robin order. Their ids go
into exam.json before episodes.json is saved and before any download, so a run that stops half way
cannot leak them into training. The exam's episodes are downloaded first (those of an earlier exam
gather that are still waiting too), the other waiting ones after them if the size limit allows. With --list it says how many exam episodes a run would take.

--max-gb is the limit for all the audio kept in the folder, not for one run, and audio is never
deleted, so once the folder is full nothing more is downloaded, the wanted episodes included.

--own-gb N (only with --only-ahead; the hourly episode preparing uses it, teach_prepare.py) is the
most GB of audio that the episodes of ahead.json may keep on this Mac. Only their audio is counted,
and the --max-gb check on the whole folder is not made, so the audio of earlier big runs does not stop
the hour. The free disk check stays as it is.

--only-ahead is for the nightly read-ahead (teach_ahead.py): it reads no feed and downloads only the
episodes in ahead.json that have no file yet, with the same size and disk limits. Nothing else in
episodes.json is touched.

--list only reads the feeds and says what a run would download. Exit codes: 0 it ran, 2 the shows
file cannot be read, the folder cannot be written, episodes.json is damaged or another run is
working in the folder, 3 it ran but the size limit stopped downloads that were waiting.

Run the tests: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import argparse
import os
import shutil
import sys
import time

import probe_shows as probe
import teach_fetch as fetching
import teach_exam
import teach_store
import teach_wanted
from teach_ahead_set import ahead_ids
from teach_wanted import wanted_entries
from teach_feed import audio_name, episode_id, feed_episodes
from teach_store import (FIELDS, FOLDER, MANIFEST, Busy, ManifestError, check_entry,  # noqa: F401
                         load_manifest, run_lock, save_manifest)

PER_SHOW = 4
WANTED = teach_wanted.MOST
MAX_GB = 12
KEEP_FREE_GB = 15
GB = 1_000_000_000
SIZE_LIMIT = 3  # the exit code when the size limit on kept audio stopped the downloads
SKIPPED = "skipped:"
ALL = 1_000_000


# MARK: Episodes

def new_entry(title, feed, episode):
    """A full entry of episodes.json for an episode of a feed, not downloaded yet."""
    return {"id": episode_id(feed, episode["guid"], episode["address"]), "feed": feed, "show": title,
            "guid": episode["guid"], "title": episode["title"], "published": episode["published"],
            "seconds": episode["seconds"], "address": episode["address"], "size": episode["size"],
            "file": None, "bytes": 0, "sha256": None, "host": None, "error": None}


def plan(shows, known_ids, per_show, fetch=fetching.fetch_feed, pause=probe.PAUSE, sleep=time.sleep,
         say=print, stats=None, wanted=(), wanted_most=WANTED):
    """The new episodes (not in `known_ids`) to download. First the wanted ones (see teach_wanted.py,
    at most `wanted_most`, whatever `per_show` says), then those of every show in round-robin
    order: every show's newest first (shows in file order), then every show's second newest, and so
    on, so a size cap still covers every show. A feed that cannot be fetched or read is skipped
    with one line and does not count as read. A wanted episode is matched to a followed show by feed key
    and planned under that show's own spelling and id; one whose feed is not followed is left out. `stats`, when given, gets "shows_read", the number of followed feeds that
    were read, and "listed", {id: {"address", "size", "type"}} for every episode the feeds list now
    (known or new)."""
    columns, listed, lookups = [], {}, {}

    def make(title, feed, episode):
        entry = new_entry(title, feed, episode)
        listed[entry["id"]] = {key: episode[key] for key in ("address", "size", "type")}
        return entry

    wanted = teach_wanted.followed_only(wanted, shows, say)
    wanted_feeds = {item["feed"] for item in wanted}
    for index, show in enumerate(shows):
        if index:
            sleep(pause)
        try:
            data = fetch(show["feed"])
            episodes = feed_episodes(data, per_show)
            if show["feed"] in wanted_feeds:
                lookups[show["feed"]] = (show["title"], feed_episodes(data, ALL))
        except Exception as error:  # a dead feed must not stop the others
            say("Skipped %s: its feed could not be read (%s)"
                % (show["title"], str(error) or error.__class__.__name__))
            continue
        column = []
        for episode in episodes:
            column.append(make(show["title"], show["feed"], episode))
        columns.append(column)
    first = wanted_entries(wanted, lookups, known_ids, wanted_most, say, make)
    if stats is not None:
        stats.update(shows_read=len(columns), listed=listed)
    entries, taken = list(first), set(known_ids) | {entry["id"] for entry in first}
    for rank in range(per_show):
        for column in columns:
            if rank < len(column) and column[rank]["id"] not in taken:
                taken.add(column[rank]["id"])
                entries.append(column[rank])
    return entries


def positive(text):
    try:
        number = int(text)
    except ValueError:
        raise argparse.ArgumentTypeError("%r is not a whole number" % text)
    if number < 1:
        raise argparse.ArgumentTypeError("%r is not 1 or more" % text)
    return number


def gigabytes(text):
    try:
        value = float(text)
    except ValueError:
        value = 0.0
    if not 0 < value < float("inf"):
        raise argparse.ArgumentTypeError("%r is not a number above zero" % text)
    return value


def is_skipped(entry):
    return (entry["error"] or "").startswith(SKIPPED)


def refresh(entries, listed):
    """Gives the episodes that are known but have no file yet the address and size the feed lists
    now (signed addresses expire). Skipped episodes are left as they are."""
    for entry in entries:
        fresh = listed.get(entry["id"])
        if fresh and not entry["file"] and not is_skipped(entry):
            entry["address"], entry["size"] = fresh["address"], fresh["size"]


# MARK: Collect

def collect(folder, shows, per_show, max_bytes, keep_free_bytes, fetch=fetching.fetch_feed,
            download=fetching.download, free_space=lambda path: shutil.disk_usage(path).free,
            pause=probe.PAUSE, sleep=time.sleep, say=print, max_file=fetching.MAX_FILE,
            wanted=(), wanted_most=WANTED, exam=False, exam_most=teach_exam.MOST, only=None,
            own_bytes=None):
    """Adds the new episodes to episodes.json and downloads every entry that has no file yet, in
    list order (with `exam`, the exam's episodes first). Stops before a download that would take the audio on disk over `max_bytes`, or
    when the free disk space, less the file about to come (the feed's size, when known), is under
    `keep_free_bytes`. An episode bigger than `max_file` (by the feed's size or the server's) is
    recorded as "skipped: ..." and never tried again. episodes.json is saved after every episode.
    A failed download is recorded and the run carries on. Answers {"shows_read", "downloaded",
    "failed", "skipped", "waiting", "files", "bytes", "why"}, `why` being "size", "space" or None.
    With `exam`, the wanted list is ignored and only the episodes that teach_exam.pick_new takes are
    added; their ids go into exam.json before episodes.json is saved and before any download, and
    the downloads start with the exam's episodes. With `only` (a set of ids) only those episodes are
    downloaded, and `shows` is normally empty so no feed is read. With `own_bytes` (only with `only`)
    the size check counts just the audio of the ids in `only` and is made against `own_bytes`, not
    against `max_bytes`, so other audio kept in the folder does not stop these downloads."""
    entries = load_manifest(folder)
    os.makedirs(os.path.join(folder, "audio"), exist_ok=True)
    stats = {}
    new = plan(shows, {entry["id"] for entry in entries}, per_show, fetch, pause, sleep, say, stats,
               () if exam else wanted, wanted_most)
    if exam:
        new = teach_exam.pick_new(entries, new, teach_exam.read_exam(folder), exam_most,
                                  ahead_ids(folder))
        joined = teach_exam.add_to_exam(folder, [entry["id"] for entry in new])
        say("%d new episodes were put in the exam (%d in all)." % (len(new), len(joined)))
    refresh(entries, stats["listed"])
    entries.extend(new)
    save_manifest(folder, entries)
    result = {"shows_read": stats["shows_read"], "downloaded": 0, "failed": 0, "skipped": 0,
              "waiting": 0, "files": 0, "bytes": 0, "why": None}
    too_big = "%s larger than %d MB" % (SKIPPED, max_file // 1_000_000)
    first = True
    # An exam run downloads the exam's own episodes first, so the size allowance goes to them and
    # not to episodes that were still waiting from an earlier run.
    exam_ids = set(teach_exam.read_exam(folder)) if exam else set()
    order = [e for e in entries if e["id"] in exam_ids] + [e for e in entries if e["id"] not in exam_ids]
    if only is not None:
        order = [e for e in order if e["id"] in only]
    for position, entry in enumerate(order):
        if entry["file"] or is_skipped(entry):
            continue
        if (entry["size"] or 0) > max_file:
            entry["error"] = too_big
            result["skipped"] += 1
            save_manifest(folder, entries)
            continue
        if own_bytes is None:
            on_disk, limit = sum(other["bytes"] for other in entries if other["file"]), max_bytes
        else:
            on_disk = sum(other["bytes"] for other in entries if other["file"] and other["id"] in only)
            limit = own_bytes
        if on_disk + (entry["size"] or 0) > limit:
            result["why"] = "size"
        elif free_space(folder) - (entry["size"] or 0) < keep_free_bytes:
            result["why"] = "space"
        if result["why"]:
            result["waiting"] = sum(1 for other in order[position:]
                                    if not other["file"] and not is_skipped(other))
            break
        if not first:
            sleep(pause)
        first = False
        kind = stats["listed"].get(entry["id"], {}).get("type")
        name = audio_name(entry["id"], entry["address"], kind)
        say("  downloading %s: %s" % (entry["show"], entry["title"] or entry["address"]))
        try:
            info = download(entry["address"], os.path.join(folder, name), max_bytes=max_file)
        except fetching.TooLarge:
            entry["error"] = too_big
            result["skipped"] += 1
            say("    skipped: the file is bigger than %d MB" % (max_file // 1_000_000))
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


def list_command(folder, shows, per_show, fetch, sleep, say, wanted_most=WANTED, exam=False,
                 exam_most=teach_exam.MOST):
    """Says what a run would download, without writing anything."""
    entries = load_manifest(folder)
    stats = {}
    new = plan(shows, {entry["id"] for entry in entries}, per_show, fetch, probe.PAUSE, sleep, say,
               stats, () if exam else teach_wanted.load_wanted(folder, say), wanted_most)
    if exam:
        new = teach_exam.pick_new(entries, new, teach_exam.read_exam(folder), exam_most,
                                  ahead_ids(folder))
    entries = [e for e in entries if not e["file"] and not is_skipped(e)] + new
    known = sum(entry["size"] or 0 for entry in entries)
    unknown = sum(1 for entry in entries if not entry["size"])
    if exam:
        say("A run would take %d exam episodes." % len(new))
    say("Read %d show%s. A run would download %d episodes, %.1f GB in the sizes the feeds give; "
        "%d of them have no size." % (stats["shows_read"], "" if stats["shows_read"] == 1 else "s",
                                     len(entries), known / GB, unknown))
    return 0


def main(argv=None, fetch=fetching.fetch_feed, download=fetching.download, sleep=time.sleep, say=print):
    parser = argparse.ArgumentParser(description="Gathers recent episodes of your shows for teaching.")
    parser.add_argument("--folder", default=FOLDER)
    parser.add_argument("--shows", default=probe.SHOWS_FILE)
    parser.add_argument("--per-show", type=int, default=PER_SHOW)
    parser.add_argument("--max-gb", type=float, default=MAX_GB)
    parser.add_argument("--keep-free-gb", type=float, default=KEEP_FREE_GB)
    parser.add_argument("--wanted", type=int, default=WANTED)
    parser.add_argument("--exam", action="store_true")
    parser.add_argument("--exam-most", type=positive, default=teach_exam.MOST)
    parser.add_argument("--only-ahead", action="store_true")
    parser.add_argument("--own-gb", type=gigabytes)
    parser.add_argument("--list", action="store_true")
    args = parser.parse_args(argv)
    folder = os.path.expanduser(args.folder)
    if args.own_gb is not None and not args.only_ahead:
        say("--own-gb limits the audio of the episodes of ahead.json, so it needs --only-ahead.")
        return 2
    try:
        shows = [] if args.only_ahead else probe.load_shows(args.shows)
    except (OSError, ValueError, AttributeError, TypeError) as error:
        say("Could not read your followed shows from %s: %s" % (args.shows, error))
        return 2
    try:
        if args.list:
            return list_command(folder, shows, args.per_show, fetch, sleep, say, args.wanted,
                                args.exam, args.exam_most)
        with run_lock(folder):
            say("Downloading tonight's episodes..." if args.only_ahead
                else "Reading the feeds of %d shows..." % len(shows))
            result = collect(folder, shows, args.per_show, int(args.max_gb * GB),
                             int(args.keep_free_gb * GB), fetch=fetch, download=download,
                             sleep=sleep, say=say,
                             wanted=() if args.exam or args.only_ahead
                             else teach_wanted.load_wanted(folder, say),
                             wanted_most=args.wanted, exam=args.exam, exam_most=args.exam_most,
                             only=ahead_ids(folder) if args.only_ahead else None,
                             own_bytes=None if args.own_gb is None else int(args.own_gb * GB))
    except (Busy, teach_store.Problem) as error:
        say(str(error))
        return 2
    except ManifestError as error:
        say("%s\nNothing was changed. Fix or move that file and run this again." % error)
        return 2
    except OSError as error:
        say("Could not write to %s: %s" % (folder, error))
        return 2
    say("\nRead %d shows. %d episodes are on disk (%.1f GB). %d failed this time."
        % (result["shows_read"], result["files"], result["bytes"] / GB, result["failed"]))
    if result["skipped"]:
        say("%d were left out for good because the file is too big." % result["skipped"])
    if result["waiting"]:
        why = ("the %.0f GB size limit on all kept audio was reached" % args.max_gb
               if result["why"] == "size" and args.own_gb is None
               else "the %g GB limit on the job's own audio was reached" % args.own_gb
               if result["why"] == "size" else "free disk space is under %.0f GB" % args.keep_free_gb)
        say("%d are still waiting because %s." % (result["waiting"], why))
    return SIZE_LIMIT if result["why"] == "size" else 0


if __name__ == "__main__":
    sys.exit(main())
