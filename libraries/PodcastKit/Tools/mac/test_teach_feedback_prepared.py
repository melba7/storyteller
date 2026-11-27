"""Tests for the summary of prepared episodes that teach_feedback.py prints from the phone's notes:
ads skipped by the Mac's marks, skips taken back, and taps on Skip ad, each counted by a note that
says by "prepared"; nothing is said when there are no such notes.
Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import json
import os

import teach_ahead_set as ahead
import teach_prepared_file as pfile
import teach_store as store
from teach_testing import entry
from test_teach_feedback import Setup, note

FEED = "https://a.example/feed%d"


class PreparedSetup(Setup):
    def prepared(self, number, show="Show A", published=True, removed=None, guid=None):
        """Episode `number` of feed FEED % number, listed in episodes.json, ahead.json and prepared.json."""
        item = entry(number, feed=FEED % number, show=show, guid="g%d" % number,
                     address="https://a.example/%d.mp3" % number)
        found = store.load_manifest(self.teaching) if os.path.exists(
            os.path.join(self.teaching, "episodes.json")) else []
        store.save_manifest(self.teaching, found + [item])
        ahead.add_ahead(self.teaching, [{"id": item["id"], "feed": FEED % number, "guid": "g%d" % number,
                                         "title": "T", "picked": 1}])
        listed = pfile.read_prepared(self.teaching)
        if published:
            listed.append({"id": item["id"], "file": "prepared/%s.mp3" % item["id"], "sha256": "a" * 64,
                           "bytes": 5, "published": 100, "removed": removed})
        else:
            listed.append({"id": item["id"], "file": None, "sha256": None, "bytes": 0, "published": None,
                           "picked": 100, "removed": None})
        pfile.write_prepared(self.teaching, listed)
        return item

    def notes_for(self, number, *whats, by="prepared", **more):
        return [note(what, feed=FEED % number, guid="g%d" % number, by=by, **more) for what in whats]

    def lines(self, notes):
        self.put(self.cloud, notes)
        self.run_main()
        return [line for line in self.said if "repared" in line or "Skip ad" in line or "Show" in line]

    def summary(self):
        return [line for line in self.said if line.startswith("Prepared episodes") or line.startswith("  ")
                or line.startswith("Per show")]


class CountTests(PreparedSetup):
    def test_skips_undos_and_misses_in_prepared_episodes_are_counted(self):
        self.prepared(1)
        self.prepared(2, show="Show B")
        notes = (self.notes_for(1, "skipped", "skipped", "skipped", "undone")
                 + self.notes_for(2, "skipped", "missed", "missed"))
        self.lines(notes)
        text = self.text()
        self.assertIn("the phone skipped 4 ads by the Mac's marks", text)
        self.assertIn("you took back 1 of those skips", text)
        self.assertIn("you pressed Skip ad 2 times on the Mac's copy where its marks had no ad", text)

    def test_a_third_line_gives_the_same_per_show(self):
        self.prepared(1)
        self.prepared(2, show="Show B")
        self.lines(self.notes_for(1, "skipped", "skipped", "undone") + self.notes_for(2, "skipped", "missed"))
        show_line = [line for line in self.said if line.startswith("Per show")][0]
        self.assertIn("Show A: 2 skipped, 1 taken back, 0 pressed", show_line)
        self.assertIn("Show B: 1 skipped, 0 taken back, 1 pressed", show_line)

    def test_at_most_three_lines_are_added_and_the_percentage_is_plain(self):
        self.prepared(1)
        self.lines(self.notes_for(1, "skipped", "skipped", "skipped", "skipped", "undone"))
        added = [line for line in self.said if line.startswith(("Prepared episodes", "Per show", "That is"))]
        self.assertEqual(len(added), 3)
        self.assertIn("That is 1 skip taken back in 4 (25%)", self.text())

    def test_only_notes_by_prepared_count_as_skips_undos_and_misses(self):
        self.prepared(1)
        notes = (self.notes_for(1, "skipped", "undone", "missed", by="ahead")
                 + self.notes_for(1, "skipped", "missed", by="") + self.notes_for(1, "skipped", "missed"))
        self.lines(notes)
        self.assertIn("the phone skipped 1 ad by the Mac's marks", self.text())
        self.assertIn("you took back 0 of those skips", self.text())
        self.assertIn("you pressed Skip ad 1 time on the Mac's copy where its marks had no ad", self.text())

    def test_a_miss_counts_by_its_note_and_not_by_the_episode_being_listed_in_prepared_json(self):
        self.prepared(1)
        self.prepared(2, published=False)
        elsewhere = [note("missed", feed="https://other.example/f", guid="x", by="prepared")]
        self.lines(self.notes_for(1, "missed", by="") + self.notes_for(2, "missed") + elsewhere)
        self.assertIn("you pressed Skip ad 2 times on the Mac's copy", self.text())

    def test_a_miss_in_a_published_episode_with_no_by_is_not_counted(self):
        self.prepared(1)
        self.lines(self.notes_for(1, "missed", by=""))
        self.assertFalse(any("Prepared" in line for line in self.said))

    def test_a_show_is_named_from_episodes_json_or_by_its_feed(self):
        self.prepared(1, show="Show A")
        other = note("skipped", feed="https://zzz.example/f", guid="q", by="prepared")
        self.lines(self.notes_for(1, "skipped") + [other])
        line = [line for line in self.said if line.startswith("Per show")][0]
        self.assertIn("Show A: 1 skipped", line)
        self.assertIn("zzz.example/f: 1 skipped", line)

    def test_nothing_is_said_when_there_are_no_such_notes(self):
        self.prepared(1)
        self.lines([note("missed", feed="https://other.example/f", guid="x"), note("skipped", by="ahead")])
        self.assertEqual(self.summary(), [])
        self.assertFalse(any("Prepared" in line for line in self.said))

    def test_nothing_is_said_with_no_prepared_json_and_no_prepared_notes(self):
        self.lines([note("skipped"), note("missed")])
        self.assertFalse(any("Prepared" in line for line in self.said))

    def test_prepared_notes_count_with_no_prepared_json_at_all(self):
        self.lines(self.notes_for(1, "skipped", "missed"))
        self.assertIn("the phone skipped 1 ad by the Mac's marks", self.text())
        self.assertIn("you pressed Skip ad 1 time", self.text())

    def test_the_summary_comes_after_the_table_and_before_the_closing_sentence(self):
        self.prepared(1)
        self.lines(self.notes_for(1, "skipped"))
        words = [i for i, line in enumerate(self.said) if line.startswith("Prepared episodes")][0]
        self.assertLess([i for i, line in enumerate(self.said) if line.startswith("Show")][0], words)
        self.assertLess(words, len(self.said) - 1)
        self.assertTrue(self.said[-1].startswith(("No episodes", "1 episode", "2 episode")) or
                        "next gather" in self.said[-1])
