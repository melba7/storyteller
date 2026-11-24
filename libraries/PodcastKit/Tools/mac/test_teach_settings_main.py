"""Tests for the command teach_settings.py: what it reads, what it writes and says, and what it does
when something is missing or damaged. Temporary folders only, no network.
Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import contextlib
import io
import json
import os
import shutil
import tempfile
import textwrap
import unittest
from unittest import mock

import teach_settings as settings
from teach_settings_rows import SCORECARD_LIMIT
from teach_settings_testing import (
    APPLE, APPLE_ALL, FEED_A, FEED_B, JOINTS, NOW, OWN, STEADY, WORDS, bar, card, note, row, show, total)

NAME = "show-settings.json"
SWIFT_TEST = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "Tests",
                          "PodcastAdsTests", "ShowTuningMacTests.swift")


class Setup(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.root, ignore_errors=True)
        self.folder = os.path.join(self.root, "teaching")
        os.makedirs(self.folder)
        self.mac = os.path.join(self.root, "mac")
        self.cloud = os.path.join(self.root, "cloud")
        self.said = []

    def scorecard(self, body):
        with open(os.path.join(self.folder, "scorecard.json"), "w", encoding="utf-8") as f:
            f.write(body if isinstance(body, str) else json.dumps(body))

    def own_sound_is_bad_on_a(self):
        """A scorecard where the finder "own-sound" costs 30 s of wrong skips on show A and finds 900 s
        of ad on show B, so it is bad on A and not bad over all shows."""
        self.scorecard(card(
            row("Phone", show(FEED_A, "Show A", heard=40), show(FEED_B, "Show B", ad=1000, heard=900)),
            row(OWN, show(FEED_A, "Show A", heard=40, cut=30), show(FEED_B, "Show B", ad=1000, heard=0))))

    def put_notes(self, folder, notes):
        directory = os.path.join(folder, "Podcasts")
        os.makedirs(directory, exist_ok=True)
        path = os.path.join(directory, "phone-notes.jsonl")
        with open(path, "w", encoding="utf-8") as f:
            f.write("".join(json.dumps(n) + "\n" for n in notes))
        return path

    def run_main(self, *extra, now=NOW):
        return settings.main(["--folder", self.folder] + list(extra), say=self.said.append,
                             defaults=lambda: [self.mac, self.cloud], now=lambda: now)

    def path(self):
        return os.path.join(self.folder, NAME)

    def text(self):
        with open(self.path(), encoding="utf-8") as f:
            return f.read()

    def written(self):
        return json.loads(self.text())

    def said_text(self):
        return "\n".join(self.said)


class WritingTests(Setup):
    def test_the_file_has_exactly_the_keys_the_phone_reads(self):
        self.own_sound_is_bad_on_a()
        self.assertEqual(self.run_main(), 0)
        found = self.written()
        self.assertEqual(sorted(found), ["default", "shows", "version", "writtenAt"])
        self.assertEqual(found["version"], 1)
        self.assertEqual(found["writtenAt"], NOW // 1000, "whole seconds, as the written rule shows")
        self.assertEqual(sorted(found["default"]), ["ask", "finders", "joints", "steadyJoints"])
        self.assertEqual(found["default"], {
            "finders": {"own-sound": "skip", "repeat-sound": "ask", "repeat-words": "ask",
                        "meaning": "skip", "apple-model": "ask"},
            "joints": True, "steadyJoints": False, "ask": 0.35})
        self.assertEqual(found["shows"], [{"feed": FEED_A, "finders": {"own-sound": "ask"}}])

    def test_the_text_is_the_same_every_time_with_its_keys_in_order(self):
        self.own_sound_is_bad_on_a()
        self.run_main()
        first = self.text()
        self.run_main()
        self.assertEqual(self.text(), first)
        self.assertEqual(first, json.dumps(json.loads(first), indent=1, sort_keys=True, ensure_ascii=False))

    def test_the_shows_come_in_order_of_their_feed_address(self):
        base = row("Phone", show(FEED_B, heard=40), show(FEED_A, heard=40),
                   show("https://c.example/f", ad=1000, heard=900))
        bad = row(OWN, show(FEED_B, heard=40, cut=15), show(FEED_A, heard=40, cut=15),
                  show("https://c.example/f", ad=1000, heard=0))
        self.scorecard(card(base, bad))
        self.run_main()
        self.assertEqual([s["feed"] for s in self.written()["shows"]], [FEED_A, FEED_B])

    def test_one_line_says_why_for_each_show_that_changed(self):
        self.own_sound_is_bad_on_a()
        self.run_main()
        lines = [line for line in self.said if "Show A" in line]
        self.assertEqual(len(lines), 1, self.said)
        self.assertIn("own-sound", lines[0])
        self.assertNotIn("Show B", self.said_text())
        self.assertIn("1 show", self.said[-1])

    def test_a_scorecard_that_changes_nothing_still_writes_the_plain_default(self):
        self.scorecard(card(row("Phone", show(FEED_A, heard=40)), row(OWN, show(FEED_A, heard=10))))
        self.assertEqual(self.run_main(), 0)
        self.assertEqual(self.written()["shows"], [])
        self.assertIn("No show needs settings of its own", self.said_text())

    def test_only_the_settings_are_written_to_the_teaching_folder(self):
        self.own_sound_is_bad_on_a()
        self.run_main()
        self.assertEqual(sorted(os.listdir(self.folder)), ["scorecard.json", NAME])
        self.assertEqual(sorted(os.listdir(self.root)), ["teaching"], "nothing was written beside it")

    def test_a_write_that_fails_leaves_the_old_file_and_no_scrap(self):
        self.own_sound_is_bad_on_a()
        self.run_main()
        old = self.text()
        self.scorecard(card(row("Phone", show(FEED_A, heard=40)), row(OWN, show(FEED_A, heard=40))))
        with mock.patch("teach_store.os.replace", side_effect=OSError("disk full")):
            self.assertEqual(self.run_main(), 2)
        self.assertEqual(self.text(), old)
        self.assertEqual(sorted(os.listdir(self.folder)), ["scorecard.json", NAME])
        self.assertIn("disk full", self.said_text())


class SharedTextTests(Setup):
    def swift_text(self):
        """The text the Swift test reads as the Mac's file (`macText` in ShowTuningMacTests.swift)."""
        with open(SWIFT_TEST, encoding="utf-8") as f:
            source = f.read()
        opening = 'static let macText = """\n'
        start = source.index(opening) + len(opening)
        return textwrap.dedent(source[start:source.index('\n    """', start)])

    def test_the_file_is_the_text_the_phones_test_reads(self):
        a, b, c = "https://show-a.test/feed", "https://www.Show-B.test/rss/", "https://c.test/f"

        def three(a_figures, b_figures, c_figures):
            return [show(a, "Show A", **a_figures), show(b, "Show B", ad=300, **b_figures),
                    show(c, "Show C", **c_figures)]
        # Apple's rows stand on the steady row. Each show's bar: on A and B the what-if row gains too
        # little (1 break; 3 breaks but 2 more skips with no ad), on C it passes 4 more and adds 1.
        last = ({"heard": 27, "cut": 50, "bar": bar(10, 4)}, {"heard": 12, "cut": 20, "bar": bar(10, 4)},
                {"heard": 18, "cut": 20, "bar": bar(10, 4)})
        self.scorecard(card(
            row("Phone's own finders", *three({"heard": 40}, {"heard": 250}, {"heard": 40})),
            row(OWN, *three({"heard": 40, "cut": 30}, {"heard": 20}, {"heard": 20})),
            row(WORDS, *three({"heard": 40, "cut": 50}, {"heard": 20, "cut": 20}, {"heard": 20, "cut": 20})),
            row(JOINTS, *three({"heard": 30, "cut": 50}, {"heard": 10, "cut": 20}, {"heard": 21, "cut": 20})),
            row(STEADY, *three(*last)),
            row(APPLE, *three(*last)),
            row(APPLE_ALL, *three(dict(last[0], bar=bar(11, 4)), dict(last[1], bar=bar(13, 6)),
                                  dict(last[2], bar=bar(14, 5))))))
        notes = self.put_notes(self.root, [note("undone", "meaning", feed="http://show-b.test/rss")] * 2)
        self.assertEqual(self.run_main("--notes", notes), 0)
        self.assertEqual(self.text(), self.swift_text())


class ScorecardTests(Setup):
    def test_a_scorecard_without_rows_gives_the_plain_default_and_says_so(self):
        self.scorecard({"version": 1, "runs": [{"at": 1, "title": "t", "total": total()}]})
        self.assertEqual(self.run_main(), 0)
        found = self.written()
        self.assertEqual(found["shows"], [])
        self.assertEqual(found["default"]["finders"]["own-sound"], "skip")
        self.assertIn("no rows", self.said_text())

    def test_a_scorecard_with_no_runs_is_the_same(self):
        self.scorecard({"version": 1, "runs": []})
        self.assertEqual(self.run_main(), 0)
        self.assertEqual(self.written()["shows"], [])
        self.assertIn("no rows", self.said_text())

    def test_no_scorecard_means_nothing_is_written(self):
        self.assertEqual(self.run_main(), 0)
        self.assertFalse(os.path.exists(self.path()))
        self.assertIn("no scorecard", self.said_text().lower())

    def test_a_damaged_scorecard_is_a_set_up_problem_and_leaves_the_old_file(self):
        with open(self.path(), "w", encoding="utf-8") as f:
            f.write("old")
        for body in ("{nope", "[]", "7", '{"runs": 5}', '{"runs": [5]}', "", "[" * 100000):
            self.said.clear()
            self.scorecard(body)
            self.assertEqual(self.run_main(), 2, body[:20])
            self.assertEqual(self.text(), "old")
            self.assertIn("scorecard.json", self.said_text())

    def test_a_number_too_big_for_a_float_in_the_scorecard_is_not_a_crash(self):
        whole = total()
        whole["cutSeconds"] = 10 ** 400
        huge = row(OWN, show(FEED_A, heard=40), show(FEED_B, heard=40), whole=whole)
        self.scorecard(card(row("Phone", show(FEED_A, heard=40), show(FEED_B, heard=40)), huge))
        self.assertEqual(self.run_main(), 0)
        self.assertEqual(self.written()["shows"], [])

    def test_a_scorecard_over_the_limit_is_not_read(self):
        self.scorecard(" " * (SCORECARD_LIMIT + 1))
        self.assertEqual(self.run_main(), 2)
        self.assertFalse(os.path.exists(self.path()))
        self.assertIn("too big", self.said_text())

    def test_a_missing_folder_is_a_set_up_problem(self):
        self.folder = os.path.join(self.root, "none")
        self.assertEqual(self.run_main(), 2)
        self.assertFalse(os.path.exists(self.folder))
        self.assertIn(self.folder, self.said_text())

    def test_bad_arguments_exit_with_two(self):
        with contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(settings.main(["--nope"], say=self.said.append), 2)


class NotesTests(Setup):
    def undone(self, by="meaning"):
        return [note("undone", by), note("undone", by)]

    def test_notes_from_a_file_make_a_finder_ask_on_the_show(self):
        self.own_sound_is_bad_on_a()
        notes = self.put_notes(self.root, self.undone())
        self.assertEqual(self.run_main("--notes", notes), 0)
        self.assertEqual(self.written()["shows"],
                         [{"feed": FEED_A, "finders": {"meaning": "ask", "own-sound": "ask"}}])
        self.assertIn("meaning", self.said_text())

    def test_the_notes_are_found_the_way_the_other_tools_find_them(self):
        self.own_sound_is_bad_on_a()
        self.put_notes(self.cloud, self.undone())  # the iCloud copy is the last folder, read first
        self.put_notes(self.mac, [])
        self.run_main()
        self.assertEqual(self.written()["shows"][0]["finders"], {"meaning": "ask", "own-sound": "ask"})

    def test_without_notes_the_scorecard_alone_decides(self):
        self.own_sound_is_bad_on_a()
        self.assertEqual(self.run_main(), 0)
        self.assertEqual(self.written()["shows"], [{"feed": FEED_A, "finders": {"own-sound": "ask"}}])

    def test_a_notes_file_that_is_not_there_is_said_and_the_scorecard_still_decides(self):
        self.own_sound_is_bad_on_a()
        self.assertEqual(self.run_main("--notes", os.path.join(self.root, "none.jsonl")), 0)
        self.assertEqual(self.written()["shows"], [{"feed": FEED_A, "finders": {"own-sound": "ask"}}])
        self.assertIn("none.jsonl", self.said_text())

    def test_a_notes_file_that_is_too_big_is_said_and_not_used(self):
        self.own_sound_is_bad_on_a()
        path = self.put_notes(self.root, [])
        with open(path, "w", encoding="utf-8") as f:
            f.write(" " * (9 * 1024 * 1024))
        self.assertEqual(self.run_main("--notes", path), 0)
        self.assertEqual(self.written()["shows"], [{"feed": FEED_A, "finders": {"own-sound": "ask"}}])
        self.assertIn("too big", self.said_text())

    def test_a_notes_file_of_bad_lines_is_not_a_problem(self):
        self.own_sound_is_bad_on_a()
        path = os.path.join(self.root, "notes.jsonl")
        with open(path, "wb") as f:
            f.write(b"{nope\n\xff\xfe\n[]\n" + json.dumps(note("undone", "meaning")).encode() + b"\n")
        self.assertEqual(self.run_main("--notes", path), 0)
        self.assertEqual(self.written()["shows"], [{"feed": FEED_A, "finders": {"own-sound": "ask"}}])

    def test_a_notes_file_the_mac_will_not_let_us_read_is_said(self):
        self.own_sound_is_bad_on_a()
        path = self.put_notes(self.root, self.undone())
        with mock.patch("teach_feedback.read_notes", side_effect=PermissionError("no")):
            self.assertEqual(self.run_main("--notes", path), 0)
        self.assertEqual(self.written()["shows"], [{"feed": FEED_A, "finders": {"own-sound": "ask"}}])
        self.assertIn("could not be read", self.said_text())


if __name__ == "__main__":
    unittest.main()
