"""Tests for apple_podcasts_export.py, on a small library file built here with the same table
and column names. Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import contextlib
import io
import json
import os
import sqlite3
import tempfile
import unittest

import apple_podcasts_export as export

SHOW_COLUMNS = "Z_PK INTEGER PRIMARY KEY, ZFEEDURL VARCHAR, ZUPDATEDFEEDURL VARCHAR, ZTITLE VARCHAR, ZSUBSCRIBED INTEGER"
EPISODE_COLUMNS = "Z_PK INTEGER PRIMARY KEY, ZPODCAST INTEGER, ZGUID VARCHAR, ZHASBEENPLAYED INTEGER"


# The current library: a play state, a play count and some dates, with ZHASBEENPLAYED left empty.
STATE_EPISODE_COLUMNS = (
    "Z_PK INTEGER PRIMARY KEY, ZPODCAST INTEGER, ZGUID VARCHAR, ZHASBEENPLAYED INTEGER, "
    "ZPLAYSTATE INTEGER, ZPLAYCOUNT INTEGER, ZLASTUSERMARKEDASPLAYEDDATE REAL, "
    "ZLASTDATEPLAYED REAL, ZPLAYSTATESOURCE INTEGER"
)


def load(path):
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def snapshot_of(path):
    with open(path, "rb") as handle:
        return os.stat(path).st_mtime_ns, handle.read()


def build(path, shows_sql=SHOW_COLUMNS, episodes_sql=EPISODE_COLUMNS, wal=False):
    conn = sqlite3.connect(path)
    if wal:
        conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("CREATE TABLE ZMTPODCAST (%s)" % shows_sql)
    conn.execute("CREATE TABLE ZMTEPISODE (%s)" % episodes_sql)
    conn.commit()
    return conn


def add_show(conn, key, feed, title, subscribed, updated=None):
    conn.execute(
        "INSERT INTO ZMTPODCAST (Z_PK, ZFEEDURL, ZUPDATEDFEEDURL, ZTITLE, ZSUBSCRIBED) VALUES (?, ?, ?, ?, ?)",
        (key, feed, updated, title, subscribed),
    )


def add_episode(conn, show, guid, played):
    conn.execute(
        "INSERT INTO ZMTEPISODE (ZPODCAST, ZGUID, ZHASBEENPLAYED) VALUES (?, ?, ?)",
        (show, guid, played),
    )


class LibraryTestCase(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.dir.cleanup)
        self.source = os.path.join(self.dir.name, "MTLibrary.sqlite")
        self.music = os.path.join(self.dir.name, "LofiMusic")
        os.makedirs(self.music)

    def make(self, **kwargs):
        conn = build(self.source, **kwargs)
        self.addCleanup(conn.close)
        return conn

    def read(self, conn):
        conn.commit()
        return export.export(self.source, [self.music])


class ExportTests(LibraryTestCase):
    def test_followed_shows_and_finished_episodes(self):
        conn = self.make()
        add_show(conn, 1, "https://a.example/feed", "Show A", 1)
        add_show(conn, 2, "https://b.example/feed", " Show B ", 1)
        add_episode(conn, 1, "a-1", 1)
        add_episode(conn, 1, "a-2", 0)
        add_episode(conn, 2, "b-1", 1)
        shows, finished, written = self.read(conn)
        self.assertEqual(
            shows,
            [
                {"feed": "https://a.example/feed", "title": "Show A"},
                {"feed": "https://b.example/feed", "title": "Show B"},
            ],
        )
        self.assertEqual(
            finished,
            [
                {"feed": "https://a.example/feed", "guid": "a-1"},
                {"feed": "https://b.example/feed", "guid": "b-1"},
            ],
        )
        self.assertEqual(written, [self.music])

    def test_an_unfollowed_show_and_its_episodes_are_left_out(self):
        conn = self.make()
        add_show(conn, 1, "https://a.example/feed", "Followed", 1)
        add_show(conn, 2, "https://gone.example/feed", "Unfollowed", 0)
        add_episode(conn, 1, "a-1", 1)
        add_episode(conn, 2, "gone-1", 1)
        shows, finished, _ = self.read(conn)
        self.assertEqual([s["feed"] for s in shows], ["https://a.example/feed"])
        self.assertEqual([f["guid"] for f in finished], ["a-1"])

    def test_a_moved_feed_uses_its_newest_address(self):
        conn = self.make()
        add_show(conn, 1, "https://old.example/feed", "Moved", 1, updated="https://new.example/feed")
        add_show(conn, 2, "https://same.example/feed", "Same", 1, updated="")
        shows, _, _ = self.read(conn)
        self.assertEqual(
            [s["feed"] for s in shows],
            ["https://new.example/feed", "https://same.example/feed"],
        )

    def test_empty_addresses_empty_guids_and_repeats_are_dropped(self):
        conn = self.make()
        add_show(conn, 1, "https://a.example/feed", "A", 1)
        add_show(conn, 2, "", "No feed", 1)
        add_show(conn, 3, "https://a.example/feed", "Repeat", 1)
        add_episode(conn, 1, "a-1", 1)
        add_episode(conn, 1, "a-1", 1)
        add_episode(conn, 1, "", 1)
        add_episode(conn, 1, None, 1)
        add_episode(conn, 2, "orphan", 1)
        add_episode(conn, 99, "unknown-show", 1)
        shows, finished, _ = self.read(conn)
        self.assertEqual(len(shows), 1)
        self.assertEqual(finished, [{"feed": "https://a.example/feed", "guid": "a-1"}])

    def test_a_library_with_content_still_in_the_wal_is_read(self):
        conn = self.make(wal=True)
        add_show(conn, 1, "https://a.example/feed", "A", 1)
        conn.commit()
        # The connection stays open, so the row is in the -wal file, not yet in the database.
        shows, _, _ = export.export(self.source, [self.music])
        self.assertEqual(len(shows), 1)
        conn.close()

    def test_the_source_is_not_changed(self):
        conn = self.make()
        add_show(conn, 1, "https://a.example/feed", "A", 1)
        conn.commit()
        conn.close()
        before = snapshot_of(self.source)
        export.export(self.source, [self.music])
        after = snapshot_of(self.source)
        self.assertEqual(before, after)
        self.assertEqual(sorted(os.listdir(self.dir.name)), ["LofiMusic", "MTLibrary.sqlite"])

    def test_a_missing_column_names_what_changed(self):
        conn = self.make(episodes_sql="Z_PK INTEGER PRIMARY KEY, ZPODCAST INTEGER, ZHASBEENPLAYED INTEGER")
        with self.assertRaises(export.FormatChanged) as caught:
            self.read(conn)
        self.assertIn("column ZMTEPISODE.ZGUID", str(caught.exception))
        self.assertIn("Apple Podcasts' library has changed", str(caught.exception))
        self.assertFalse(os.path.exists(os.path.join(self.music, "Podcasts")))

    def test_a_missing_table_names_what_changed(self):
        conn = sqlite3.connect(self.source)
        self.addCleanup(conn.close)
        conn.execute("CREATE TABLE ZMTPODCAST (%s)" % SHOW_COLUMNS)
        conn.commit()
        with self.assertRaises(export.FormatChanged) as caught:
            export.export(self.source, [self.music])
        self.assertIn("table ZMTEPISODE", str(caught.exception))
        conn.close()

    def test_a_missing_subscribed_column_is_reported_too(self):
        conn = self.make(shows_sql="Z_PK INTEGER PRIMARY KEY, ZFEEDURL VARCHAR, ZTITLE VARCHAR")
        with self.assertRaises(export.FormatChanged) as caught:
            self.read(conn)
        self.assertIn("ZMTPODCAST.ZSUBSCRIBED", str(caught.exception))

    def test_a_title_column_is_optional(self):
        conn = self.make(shows_sql="Z_PK INTEGER PRIMARY KEY, ZFEEDURL VARCHAR, ZSUBSCRIBED INTEGER")
        conn.execute("INSERT INTO ZMTPODCAST VALUES (1, 'https://a.example/feed', 1)")
        shows, _, _ = self.read(conn)
        self.assertEqual(shows, [{"feed": "https://a.example/feed", "title": ""}])


class PlayStateTests(LibraryTestCase):
    """Finished episodes in the current library, where ZHASBEENPLAYED is empty and the play
    state decides."""

    def add(self, conn, guid, state, count=None, marked=None, last=None, source=None):
        conn.execute(
            "INSERT INTO ZMTEPISODE (ZPODCAST, ZGUID, ZPLAYSTATE, ZPLAYCOUNT, "
            "ZLASTUSERMARKEDASPLAYEDDATE, ZLASTDATEPLAYED, ZPLAYSTATESOURCE) "
            "VALUES (1, ?, ?, ?, ?, ?, ?)",
            (guid, state, count, marked, last, source),
        )

    def finished_guids(self, conn):
        _, finished, _ = self.read(conn)
        return [f["guid"] for f in finished]

    def library(self):
        conn = self.make(episodes_sql=STATE_EPISODE_COLUMNS)
        add_show(conn, 1, "https://a.example/feed", "A", 1)
        return conn

    def test_played_to_the_end_and_marked_by_hand_are_finished(self):
        conn = self.library()
        self.add(conn, "listened", 0, count=1, last=700000000)
        self.add(conn, "marked", 0, count=0, marked=700000000)
        self.assertEqual(self.finished_guids(conn), ["listened", "marked"])

    def test_the_back_catalogue_of_a_followed_show_is_not_finished(self):
        conn = self.library()
        self.add(conn, "catalogue-dated", 0, count=0, last=700000000, source=6)
        self.add(conn, "catalogue-bare", 0, count=0)
        self.add(conn, "catalogue-null", 0)
        self.assertEqual(self.finished_guids(conn), [])

    def test_a_last_played_date_from_another_source_counts(self):
        conn = self.library()
        self.add(conn, "played", 0, count=0, last=700000000, source=2)
        self.add(conn, "played-no-source", 0, count=0, last=700000000)
        self.assertEqual(self.finished_guids(conn), ["played", "played-no-source"])

    def test_in_progress_and_unplayed_are_not_finished(self):
        conn = self.library()
        self.add(conn, "in-progress", 1, count=1, marked=700000000, last=700000000)
        self.add(conn, "unplayed", 2, count=1, marked=700000000, last=700000000)
        self.assertEqual(self.finished_guids(conn), [])

    def test_the_played_flag_is_ignored_when_the_library_has_the_play_state(self):
        # If a macOS update starts filling the flag for the back catalogue, it must not send
        # every old episode to the phone as finished.
        conn = self.library()
        conn.execute("INSERT INTO ZMTEPISODE (ZPODCAST, ZGUID, ZHASBEENPLAYED, ZPLAYSTATE) VALUES (1, 'flag', 1, 2)")
        conn.execute("INSERT INTO ZMTEPISODE (ZPODCAST, ZGUID, ZHASBEENPLAYED, ZPLAYSTATE) VALUES (1, 'flag-0', 1, 0)")
        self.assertEqual(self.finished_guids(conn), [])

    def test_an_older_library_with_only_the_flag_still_uses_it(self):
        conn = self.make(episodes_sql=EPISODE_COLUMNS)
        add_show(conn, 1, "https://a.example/feed", "A", 1)
        conn.execute("INSERT INTO ZMTEPISODE (ZPODCAST, ZGUID, ZHASBEENPLAYED) VALUES (1, 'old', 1)")
        conn.execute("INSERT INTO ZMTEPISODE (ZPODCAST, ZGUID, ZHASBEENPLAYED) VALUES (1, 'unplayed', 0)")
        self.assertEqual(self.finished_guids(conn), ["old"])

    def test_a_play_state_without_any_listened_column_counts_nothing(self):
        conn = self.make(episodes_sql="Z_PK INTEGER PRIMARY KEY, ZPODCAST INTEGER, ZGUID VARCHAR, ZPLAYSTATE INTEGER")
        add_show(conn, 1, "https://a.example/feed", "A", 1)
        conn.execute("INSERT INTO ZMTEPISODE (ZPODCAST, ZGUID, ZPLAYSTATE) VALUES (1, 'x', 0)")
        self.assertEqual(self.finished_guids(conn), [])

    def test_neither_a_play_state_nor_a_played_flag_names_what_is_missing(self):
        conn = self.make(episodes_sql="Z_PK INTEGER PRIMARY KEY, ZPODCAST INTEGER, ZGUID VARCHAR")
        with self.assertRaises(export.FormatChanged) as caught:
            self.read(conn)
        self.assertIn("ZMTEPISODE.ZPLAYSTATE or ZMTEPISODE.ZHASBEENPLAYED", str(caught.exception))
        self.assertIn("Apple Podcasts' library has changed", str(caught.exception))


class WriteTests(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.dir.cleanup)
        self.shows = [{"feed": "https://a.example/feed", "title": "A"}]
        self.finished = [{"feed": "https://a.example/feed", "guid": "g"}]

    def path(self):
        return os.path.join(self.dir.name, "Podcasts", "apple-podcasts.json")

    def test_the_file_has_a_version_a_time_and_the_lists(self):
        self.assertTrue(export.write_document(self.dir.name, self.shows, self.finished, now=1700000000))
        document = load(self.path())
        self.assertEqual(
            document,
            {"version": 1, "writtenAt": 1700000000000, "shows": self.shows, "finished": self.finished},
        )

    def test_nothing_is_rewritten_when_nothing_changed(self):
        export.write_document(self.dir.name, self.shows, self.finished, now=1)
        self.assertFalse(export.write_document(self.dir.name, self.shows, self.finished, now=2))
        self.assertEqual(load(self.path())["writtenAt"], 1000)
        self.assertTrue(export.write_document(self.dir.name, self.shows, [], now=3))
        self.assertEqual(load(self.path())["finished"], [])

    def test_no_temporary_file_is_left_behind(self):
        export.write_document(self.dir.name, self.shows, self.finished)
        self.assertEqual(os.listdir(os.path.dirname(self.path())), ["apple-podcasts.json"])

    def test_a_broken_old_file_is_replaced(self):
        os.makedirs(os.path.dirname(self.path()))
        with open(self.path(), "w") as handle:
            handle.write("{nope")
        self.assertTrue(export.write_document(self.dir.name, self.shows, self.finished))
        self.assertEqual(load(self.path())["version"], 1)

    def test_folders_that_do_not_exist_are_skipped(self):
        source = os.path.join(self.dir.name, "lib.sqlite")
        conn = build(source)
        add_show(conn, 1, "https://a.example/feed", "A", 1)
        conn.commit()
        conn.close()
        there = os.path.join(self.dir.name, "there")
        os.makedirs(there)
        _, _, written = export.export(source, [there, os.path.join(self.dir.name, "not-there")])
        self.assertEqual(written, [there])


class MainTests(unittest.TestCase):
    def test_a_refused_write_is_not_reported_as_a_refused_read(self):
        with tempfile.TemporaryDirectory() as folder:
            source = os.path.join(folder, "lib.sqlite")
            build(source).close()
            target = os.path.join(folder, "icloud")
            os.makedirs(target)
            errors = io.StringIO()
            real = export.write_document

            def refused(*args, **kwargs):
                raise PermissionError(1, "Operation not permitted")

            export.write_document = refused
            try:
                with contextlib.redirect_stderr(errors):
                    code = export.main(["--source", source, "--folder", target])
            finally:
                export.write_document = real
        self.assertEqual(code, 2)
        self.assertIn("Could not write the export", errors.getvalue())
        self.assertIn(target, errors.getvalue())
        self.assertNotIn("did not let this read Apple Podcasts' library", errors.getvalue())

    def test_a_missing_library_says_so(self):
        with tempfile.TemporaryDirectory() as folder:
            code = export.main(["--source", os.path.join(folder, "none.sqlite"), "--folder", folder])
        self.assertEqual(code, 2)

    def test_a_changed_format_stops_with_its_own_code(self):
        with tempfile.TemporaryDirectory() as folder:
            source = os.path.join(folder, "lib.sqlite")
            conn = sqlite3.connect(source)
            conn.execute("CREATE TABLE ZMTPODCAST (Z_PK INTEGER)")
            conn.commit()
            conn.close()
            self.assertEqual(export.main(["--source", source, "--folder", folder]), 3)


if __name__ == "__main__":
    unittest.main()
