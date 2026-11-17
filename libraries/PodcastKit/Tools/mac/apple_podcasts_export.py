#!/usr/bin/env python3
"""Reads the shows you follow and the episodes you finished in Apple Podcasts on this Mac and
writes them to Podcasts/apple-podcasts.json, for the Storyteller Lofi phone app.

One way only: Apple's files are opened read-only and copied with SQLite's backup, so nothing
is ever written to them. Standard library only (macOS's own python3 is enough).

Apple's library is a Core Data file with no documentation, so the table and column names
below are what other people's tools found by reading it; they are all in this one place. If
Apple renames one, the run stops and says which.
"""
import argparse
import json
import os
import shutil
import sqlite3
import sys
import tempfile
import time
from urllib.parse import quote

# MARK: Apple's names (the only place they appear)

LIBRARY = os.path.join(
    "~",
    "Library",
    "Group Containers",
    "243LU875E5.groups.com.apple.podcasts",
    "Documents",
    "MTLibrary.sqlite",
)

SHOWS = "ZMTPODCAST"
EPISODES = "ZMTEPISODE"
# What each table must have. A missing one means Apple changed its format.
REQUIRED = {
    # The key episodes point at, the feed address and 1 for a show you follow.
    SHOWS: ["Z_PK", "ZFEEDURL", "ZSUBSCRIBED"],
    # The show it belongs to (a Z_PK of ZMTPODCAST), the feed's own id, and 1 once played.
    EPISODES: ["ZPODCAST", "ZGUID", "ZHASBEENPLAYED"],
}
# Used when present: the show's newest feed address (a feed that moved) and its name.
SHOW_UPDATED_FEED = "ZUPDATEDFEEDURL"
SHOW_TITLE = "ZTITLE"

VERSION = 1


class FormatChanged(Exception):
    """Apple's library does not look the way this script expects."""


# MARK: Reading

def snapshot(source, destination):
    """Copies the library into `destination` (a new file) without writing to the original.

    It opens the original read-only and uses SQLite's backup, which gives one consistent
    copy that includes whatever is still in the write-ahead log. If a read-only open is not
    possible (no -shm file to read), the files are copied as they are and read from the copy.
    """
    try:
        src = sqlite3.connect("file:%s?mode=ro" % quote(source), uri=True)
        try:
            dst = sqlite3.connect(destination)
            try:
                src.backup(dst)
            finally:
                dst.close()
        finally:
            src.close()
        return
    except sqlite3.OperationalError:
        if not os.path.exists(source):
            raise
    # Copy the database with its log files, then let SQLite read the copy.
    copy_dir = tempfile.mkdtemp(prefix="apple-podcasts-copy-")
    try:
        target = os.path.join(copy_dir, "library.sqlite")
        shutil.copyfile(source, target)
        for suffix in ("-wal", "-shm"):
            if os.path.exists(source + suffix):
                shutil.copyfile(source + suffix, target + suffix)
        src = sqlite3.connect(target)
        try:
            dst = sqlite3.connect(destination)
            try:
                src.backup(dst)
            finally:
                dst.close()
        finally:
            src.close()
    finally:
        shutil.rmtree(copy_dir, ignore_errors=True)


def _columns(conn, table):
    rows = conn.execute('PRAGMA table_info("%s")' % table).fetchall()
    return {row[1] for row in rows}


def check_format(conn):
    """Raises FormatChanged naming what is missing."""
    missing = []
    for table, wanted in REQUIRED.items():
        have = _columns(conn, table)
        if not have:
            missing.append("table %s" % table)
            continue
        for column in wanted:
            if column not in have:
                missing.append("column %s.%s" % (table, column))
    if missing:
        raise FormatChanged(
            "Apple Podcasts' library has changed: missing %s. "
            "The export needs updating (names are in apple_podcasts_export.py)."
            % ", ".join(missing)
        )


def _clean(value):
    return value.strip() if isinstance(value, str) else ""


def read_library(conn):
    """The followed shows and the finished episodes, as plain lists.

    shows: [{"feed": address, "title": name}] for shows with ZSUBSCRIBED = 1.
    finished: [{"feed": the show's address, "guid": the episode's id}] for episodes of those
    shows with ZHASBEENPLAYED = 1. A show you unfollowed is left out with its episodes.
    """
    check_format(conn)
    have = _columns(conn, SHOWS)
    feed_sql = "p.ZFEEDURL"
    if SHOW_UPDATED_FEED in have:
        feed_sql = "COALESCE(NULLIF(TRIM(p.%s), ''), p.ZFEEDURL)" % SHOW_UPDATED_FEED
    title_sql = "p.%s" % SHOW_TITLE if SHOW_TITLE in have else "''"
    show_rows = conn.execute(
        "SELECT p.Z_PK, %s, %s FROM %s p WHERE p.ZSUBSCRIBED = 1 ORDER BY p.Z_PK"
        % (feed_sql, title_sql, SHOWS)
    ).fetchall()

    shows = []
    feed_of = {}
    seen = set()
    for key, feed, title in show_rows:
        feed = _clean(feed)
        if feed == "" or feed in seen:
            continue
        seen.add(feed)
        feed_of[key] = feed
        shows.append({"feed": feed, "title": _clean(title)})

    finished = []
    done = set()
    episode_rows = conn.execute(
        "SELECT e.ZPODCAST, e.ZGUID FROM %s e WHERE e.ZHASBEENPLAYED = 1 ORDER BY e.rowid"
        % EPISODES
    ).fetchall()
    for show_key, guid in episode_rows:
        feed = feed_of.get(show_key)
        guid = _clean(guid)
        if feed is None or guid == "" or (feed, guid) in done:
            continue
        done.add((feed, guid))
        finished.append({"feed": feed, "guid": guid})
    return shows, finished


def export(source, folders, now=None):
    """Reads the library at `source` and writes Podcasts/apple-podcasts.json into each folder
    (a folder that does not exist is skipped). Returns (shows, finished, written folders)."""
    work = tempfile.mkdtemp(prefix="apple-podcasts-")
    try:
        copy = os.path.join(work, "library.sqlite")
        snapshot(source, copy)
        conn = sqlite3.connect(copy)
        try:
            shows, finished = read_library(conn)
        finally:
            conn.close()
    finally:
        shutil.rmtree(work, ignore_errors=True)

    written = []
    for folder in folders:
        if not os.path.isdir(folder):
            continue
        if write_document(folder, shows, finished, now):
            written.append(folder)
    return shows, finished, written


# MARK: Writing

def write_document(folder, shows, finished, now=None):
    """Writes <folder>/Podcasts/apple-podcasts.json atomically. Returns False (and writes
    nothing) when the shows and finished episodes are the same as in the file already, so
    iCloud has nothing to upload."""
    directory = os.path.join(folder, "Podcasts")
    path = os.path.join(directory, "apple-podcasts.json")
    try:
        with open(path, encoding="utf-8") as handle:
            old = json.load(handle)
        if old.get("version") == VERSION and old.get("shows") == shows and old.get("finished") == finished:
            return False
    except (OSError, ValueError, AttributeError):
        pass
    os.makedirs(directory, exist_ok=True)
    document = {
        "version": VERSION,
        "writtenAt": int((time.time() if now is None else now) * 1000),
        "shows": shows,
        "finished": finished,
    }
    handle, temporary = tempfile.mkstemp(dir=directory, prefix=".apple-podcasts-", suffix=".tmp")
    try:
        with os.fdopen(handle, "w", encoding="utf-8") as out:
            json.dump(document, out, ensure_ascii=False, indent=1)
            out.write("\n")
        os.replace(temporary, path)
    except BaseException:
        try:
            os.unlink(temporary)
        except OSError:
            pass
        raise
    return True


# MARK: Running

def default_folders():
    root = os.path.expanduser("~/Storyteller Lofi")
    return [
        os.path.join(root, "LofiMusic"),
        os.path.expanduser(
            "~/Library/Mobile Documents/com~apple~CloudDocs/Storyteller Lofi/LofiMusic"
        ),
    ]


ACCESS_HELP = (
    "macOS did not let this read Apple Podcasts' library. Allow it when macOS asks, or give "
    "the program that runs this Full Disk Access: System Settings > Privacy & Security > "
    "Full Disk Access > +, press Cmd-Shift-G, type /bin/bash, add it and switch it on."
)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--source", default=os.path.expanduser(LIBRARY))
    parser.add_argument(
        "--folder",
        action="append",
        help="a LofiMusic folder to write into (default: the local one and its iCloud copy)",
    )
    args = parser.parse_args(argv)
    folders = args.folder or default_folders()
    try:
        shows, finished, written = export(args.source, folders)
    except FormatChanged as error:
        print(str(error), file=sys.stderr)
        return 3
    except (PermissionError, sqlite3.OperationalError) as error:
        if not os.path.exists(args.source):
            print("Apple Podcasts' library is not at %s (is Apple Podcasts set up on this Mac?)" % args.source, file=sys.stderr)
        else:
            print("%s (%s)" % (ACCESS_HELP, error), file=sys.stderr)
        return 2
    except OSError as error:
        print("Could not write the export: %s. If it is the iCloud copy: %s" % (error, ACCESS_HELP), file=sys.stderr)
        return 2
    print(
        "%d followed shows, %d finished episodes; %s"
        % (
            len(shows),
            len(finished),
            ("updated " + ", ".join(written)) if written else "nothing changed",
        )
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
