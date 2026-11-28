"""Tests for teach_feedback.py: reading the phone's notes, counting per show, and writing the list
of wanted episodes. Temporary folders only, no network.
Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import json
import os
import re
import shutil
import tempfile
import unittest

import teach_feedback as feedback


def note(what="missed", at=1000, feed="https://a.example/feed", guid="g1", title="One",
         address="https://a.example/1.mp3", **more):
    value = {"v": 1, "at": at, "what": what, "feed": feed, "guid": guid, "title": title,
             "address": address, "start": 10.0, "end": None, "kind": ""}
    value.update(more)
    return value


class Setup(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.root, ignore_errors=True)
        self.teaching = os.path.join(self.root, "teaching")
        self.mac = os.path.join(self.root, "mac")
        self.cloud = os.path.join(self.root, "cloud")
        self.said = []

    def put(self, folder, notes, raw=None):
        directory = os.path.join(folder, "Podcasts")
        os.makedirs(directory, exist_ok=True)
        path = os.path.join(directory, "phone-notes.jsonl")
        with open(path, "wb") as f:
            f.write(raw if raw is not None else
                    "".join(json.dumps(n) + "\n" for n in notes).encode("utf-8"))
        return path

    def run_main(self, *extra):
        # The Mac's own copy comes first in the list, as apple_podcasts_export gives it.
        return feedback.main(["--folder", self.teaching] + list(extra), say=self.said.append,
                             defaults=lambda: [self.mac, self.cloud], now=lambda: 5000)

    def wanted(self):
        with open(os.path.join(self.teaching, "wanted.json"), encoding="utf-8") as f:
            return json.load(f)

    def text(self):
        return "\n".join(self.said)


class ReadingTests(Setup):
    def test_a_good_line_is_a_note(self):
        self.assertEqual(feedback.read_note(json.dumps(note())), note())

    def test_bad_lines_are_not_notes(self):
        bad = ["{nope", "[]", "5", json.dumps(note(v=2)), json.dumps(note(what="liked")),
               json.dumps(note(at="soon")), json.dumps(note(at=True)),
               json.dumps(note(feed="")), json.dumps(note(guid="", address="")),
               json.dumps(note(title=None)), json.dumps(note(start="x")),
               json.dumps(note(end="x")), json.dumps({"v": 1})]
        for line in bad:
            self.assertIsNone(feedback.read_note(line), line)

    def test_an_empty_guid_is_fine_when_there_is_an_address(self):
        self.assertIsNotNone(feedback.read_note(json.dumps(note(guid=""))))

    def test_the_end_may_be_null_or_a_number(self):
        self.assertIsNotNone(feedback.read_note(json.dumps(note(end=None))))
        self.assertIsNotNone(feedback.read_note(json.dumps(note(end=30))))


class WantedTests(Setup):
    def test_only_missed_and_undone_episodes_are_wanted_most_recent_first(self):
        self.put(self.cloud, [
            note("skipped", 1, guid="s"), note("missed", 10, guid="a", title="A"),
            note("undone", 30, guid="b", title="B"), note("missed", 20, guid="a", title="A"),
            note("trimmed", 99, guid="t")])
        self.assertEqual(self.run_main(), 0, self.said)
        episodes = self.wanted()["episodes"]
        self.assertEqual([e["guid"] for e in episodes], ["b", "a"])
        self.assertEqual(episodes[1], {"feed": "https://a.example/feed", "guid": "a", "title": "A",
                                       "address": "https://a.example/1.mp3", "missed": 2,
                                       "undone": 0, "last": 20})
        self.assertEqual(episodes[0]["undone"], 1)
        data = self.wanted()
        self.assertEqual((data["version"], data["writtenAt"]), (1, 5000))

    def test_an_episode_is_the_feed_and_guid_or_the_feed_and_address_without_a_guid(self):
        self.put(self.cloud, [
            note(guid="", address="https://x/1.mp3", at=1),
            note(guid="", address="https://x/1.mp3", at=2),
            note(guid="", address="https://x/2.mp3", at=3),
            note(feed="https://other", guid="", address="https://x/1.mp3", at=4)])
        self.run_main()
        found = {(e["feed"], e["address"]): e["missed"] for e in self.wanted()["episodes"]}
        self.assertEqual(found, {("https://a.example/feed", "https://x/1.mp3"): 2,
                                 ("https://a.example/feed", "https://x/2.mp3"): 1,
                                 ("https://other", "https://x/1.mp3"): 1})

    def test_at_most_40_episodes(self):
        self.put(self.cloud, [note(guid="g%d" % n, at=n) for n in range(60)])
        self.run_main()
        episodes = self.wanted()["episodes"]
        self.assertEqual(len(episodes), 40)
        self.assertEqual(episodes[0]["guid"], "g59")
        self.assertIn("40 episodes", self.said[-1])

    def test_the_title_and_address_come_from_the_newest_note_that_has_them(self):
        self.put(self.cloud, [note(at=1, title="Old", address="https://old"),
                              note(at=2, title="", address="")])
        self.run_main()
        episode = self.wanted()["episodes"][0]
        self.assertEqual((episode["title"], episode["address"]), ("Old", "https://old"))

    def test_no_episode_to_ask_for_still_writes_an_empty_list(self):
        self.put(self.cloud, [note("skipped")])
        self.assertEqual(self.run_main(), 0)
        self.assertEqual(self.wanted()["episodes"], [])
        self.assertIn("No episodes", self.said[-1])

    def test_an_old_list_is_replaced(self):
        self.put(self.cloud, [note(guid="a")])
        self.run_main()
        self.put(self.cloud, [note("skipped")])
        self.run_main()
        self.assertEqual(self.wanted()["episodes"], [])


class FindingTests(Setup):
    def test_the_cloud_copy_is_read_before_the_macs_own(self):
        self.put(self.mac, [note(guid="mac")])
        self.put(self.cloud, [note(guid="cloud")])
        self.run_main()
        self.assertEqual([e["guid"] for e in self.wanted()["episodes"]], ["cloud"])

    def test_the_macs_own_copy_is_used_when_the_cloud_has_none(self):
        self.put(self.mac, [note(guid="mac")])
        self.run_main()
        self.assertEqual([e["guid"] for e in self.wanted()["episodes"]], ["mac"])

    def test_the_notes_option_reads_that_file(self):
        path = os.path.join(self.root, "mine.jsonl")
        with open(path, "w") as f:
            f.write(json.dumps(note(guid="mine")) + "\n")
        self.put(self.cloud, [note(guid="cloud")])
        self.run_main("--notes", path)
        self.assertEqual([e["guid"] for e in self.wanted()["episodes"]], ["mine"])

    def test_no_notes_is_not_an_error_and_writes_nothing(self):
        self.assertEqual(self.run_main(), 0)
        self.assertEqual(self.said, ["The phone has sent no notes yet, so there is nothing to learn "
                                     "from. Nothing was written."])
        self.assertFalse(os.path.exists(self.teaching))

    def test_a_missing_notes_file_named_by_option_is_also_not_an_error(self):
        self.assertEqual(self.run_main("--notes", os.path.join(self.root, "nope.jsonl")), 0)
        self.assertIn("nope.jsonl", self.text())
        self.assertFalse(os.path.exists(self.teaching))


class ReportTests(Setup):
    def test_bad_lines_are_counted_and_skipped(self):
        raw = (json.dumps(note()) + "\n{broken\n\n").encode("utf-8") + b"\xff\xfe\n"
        self.put(self.cloud, None, raw=raw)
        self.assertEqual(self.run_main(), 0)
        self.assertIn("2 lines in the notes were not valid and were skipped", self.text())
        self.assertEqual(len(self.wanted()["episodes"]), 1)

    def test_a_table_per_show_counts_skipped_undone_and_missed(self):
        self.put(self.cloud, [note("skipped"), note("skipped", guid="x"), note("undone", guid="x"),
                              note("missed"), note("missed", feed="https://b.example/feed")])
        self.run_main()
        lines = [line for line in self.said if "https://a.example/feed" in line]
        self.assertEqual(len(lines), 1)
        self.assertEqual(lines[0].split()[-3:], ["2", "1", "1"])
        self.assertIn("skipped", self.said[0])
        self.assertIn("undone", self.said[0])
        self.assertIn("missed", self.said[0])

    def test_a_show_name_from_the_episode_list_is_used_when_there_is_one(self):
        os.makedirs(self.teaching)
        entry = {"id": "0123456789ab", "feed": "https://a.example/feed", "show": "Radio A",
                 "guid": "g", "title": "t", "published": None, "seconds": None,
                 "address": "https://a.example/1.mp3", "size": None, "file": None, "bytes": 0,
                 "sha256": None, "host": None, "error": None}
        with open(os.path.join(self.teaching, "episodes.json"), "w") as f:
            json.dump({"version": 1, "writtenAt": 0, "episodes": [entry]}, f)
        self.put(self.cloud, [note()])
        self.run_main()
        self.assertTrue(any("Radio A" in line for line in self.said))

    def test_the_closing_sentence_counts_the_episodes(self):
        self.put(self.cloud, [note(guid="a")])
        self.run_main()
        self.assertEqual(self.said[-1], "1 episode is on the list for the next gather.")

    def test_an_unreadable_notes_file_is_a_setup_problem(self):
        path = self.put(self.cloud, [note()])
        os.remove(path)
        os.makedirs(path)  # a folder where the file should be
        self.assertEqual(self.run_main(), 2)
        self.assertIn("could not be read", self.text())

    def test_a_teaching_folder_that_cannot_be_written_is_a_setup_problem(self):
        with open(self.teaching, "w") as f:
            f.write("a file where the folder should be")
        self.put(self.cloud, [note()])
        self.assertEqual(self.run_main(), 2)

    def test_bad_arguments_exit_2(self):
        self.assertEqual(feedback.main(["--nonsense"], say=self.said.append), 2)


# The line `MacFixtures.confirmedNote` holds in PodcastKit/Tests/PodcastAdsTests/MacFixtures.swift,
# word for word: a "confirmed" note as the notes file in the linked folder holds it (what
# `noteLine` in modules/podcasts/phoneNotes.ts writes, with the finder's name in `by`).
CONFIRMED_LINE = (
    '{"v":1,"at":1700000000000,"what":"confirmed","feed":"https://show-a.test/feed",'
    '"guid":"guid-1","title":"One","address":"https://show-a.test/one.mp3","start":125.5,'
    '"end":180,"kind":"ad","by":"repeat-words"}')

SWIFT_FIXTURES = os.path.join(os.path.dirname(os.path.abspath(__file__)), os.pardir, os.pardir,
                              "Tests", "PodcastAdsTests", "MacFixtures.swift")


class AnsweredQuestionTests(Setup):
    """The notes "confirmed" (the listener said yes to a question) and "denied" (not an ad), and
    the optional `by` (which finder made the ad)."""

    def test_the_shared_line_is_still_in_the_swift_fixture(self):
        # The Swift tests check this line against what the app writes. If either side changes it,
        # this fails, so the phone and the Mac cannot drift apart without a test saying so.
        with open(SWIFT_FIXTURES, encoding="utf-8") as handle:
            text = handle.read()
        found = re.search(r'static let confirmedNote =\s*#"(.*)"#', text)
        self.assertIsNotNone(found, "MacFixtures.swift has no `confirmedNote` line any more")
        self.assertEqual(found.group(1), CONFIRMED_LINE)

    def test_the_line_the_phone_writes_for_a_confirmed_note_is_read(self):
        one = feedback.read_note(CONFIRMED_LINE)
        self.assertEqual(one, json.loads(CONFIRMED_LINE))
        self.assertEqual((one["what"], one["by"]), ("confirmed", "repeat-words"))

    def test_a_denied_note_is_read_with_or_without_by(self):
        self.assertIsNotNone(feedback.read_note(json.dumps(note("denied"))))
        self.assertEqual(feedback.read_note(json.dumps(note("denied", by="meaning")))["by"], "meaning")

    def test_a_note_without_by_has_no_by(self):
        self.assertNotIn("by", feedback.read_note(json.dumps(note("confirmed"))))

    def test_the_old_kinds_are_still_read(self):
        for what in ("skipped", "undone", "trimmed", "missed"):
            self.assertIsNotNone(feedback.read_note(json.dumps(note(what))), what)

    def test_a_by_that_is_not_text_makes_the_line_invalid(self):
        for bad in (5, True, ["own-sound"], {"a": 1}):
            self.assertIsNone(feedback.read_note(json.dumps(note("confirmed", by=bad))), bad)

    def test_a_null_by_is_the_same_as_none(self):
        # A writer that puts `"by": null` knows no finder; the note is still a good note.
        one = feedback.read_note(json.dumps(note("confirmed", by=None)))
        self.assertIsNotNone(one)
        self.assertIsNone(one["by"])

    def test_a_confirmed_note_counts_like_missed_and_a_denied_one_like_undone(self):
        wanted = feedback.wanted_episodes([
            note("confirmed", 10, guid="a"), note("denied", 20, guid="b"),
            note("confirmed", 30, guid="a", by="meaning"), note("missed", 40, guid="a"),
            note("denied", 50, guid="a"), note("undone", 60, guid="b")])
        self.assertEqual([e["guid"] for e in wanted], ["b", "a"])
        self.assertEqual({e["guid"]: (e["missed"], e["undone"]) for e in wanted},
                         {"a": (3, 1), "b": (0, 2)})

    def test_an_episode_with_only_an_answer_note_is_wanted_most_recent_first(self):
        self.put(self.cloud, [note("confirmed", 10, guid="a"), note("denied", 30, guid="b"),
                              note("skipped", 99, guid="s")])
        self.assertEqual(self.run_main(), 0, self.said)
        self.assertEqual([e["guid"] for e in self.wanted()["episodes"]], ["b", "a"])

    def test_the_phones_own_confirmed_line_makes_its_episode_wanted(self):
        self.put(self.cloud, None, raw=(CONFIRMED_LINE + "\n").encode("utf-8"))
        self.assertEqual(self.run_main(), 0, self.said)
        episode, = self.wanted()["episodes"]
        self.assertEqual((episode["feed"], episode["guid"], episode["missed"], episode["undone"]),
                         ("https://show-a.test/feed", "guid-1", 1, 0))
        self.assertNotIn("not valid", self.text())

    def test_the_table_still_counts_only_its_three_columns(self):
        self.put(self.cloud, [note("skipped"), note("confirmed", guid="x"), note("denied", guid="y")])
        self.run_main()
        row, = [line for line in self.said if "https://a.example/feed" in line]
        self.assertEqual(row.split()[-3:], ["1", "0", "0"])


class ICloudDownloadTests(unittest.TestCase):
    """The phone's files reach the Mac as files iCloud Drive has not downloaded yet. A program's
    default on macOS is not to download one when it reads it: the read fails with EDEADLK
    ("Resource deadlock avoided"), which every preparing run said for the phone's notes and list
    of next episodes (2026-11-28). So the readers first let the process download them."""

    class FakeLibc:
        def __init__(self, answer=0):
            self.calls, self.answer = [], answer

        def setiopolicy_np(self, *values):
            self.calls.append(values)
            return self.answer

    def test_on_macos_the_process_is_let_download_dataless_files(self):
        libc = self.FakeLibc()
        self.assertTrue(feedback.allow_icloud_downloads(platform="darwin", load=lambda: libc))
        # IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_PROCESS, ..._FILES_ON (sys/resource.h)
        self.assertEqual(libc.calls, [(3, 0, 2)])

    def test_elsewhere_or_when_it_cannot_be_set_nothing_breaks(self):
        libc = self.FakeLibc()
        self.assertFalse(feedback.allow_icloud_downloads(platform="linux", load=lambda: libc))
        self.assertEqual(libc.calls, [])
        self.assertFalse(feedback.allow_icloud_downloads(platform="darwin", load=lambda: self.FakeLibc(-1)))

        def missing():
            raise OSError("no such library")
        self.assertFalse(feedback.allow_icloud_downloads(platform="darwin", load=missing))
        self.assertFalse(feedback.allow_icloud_downloads(platform="darwin", load=lambda: object()))

    def test_finding_a_phone_file_lets_the_process_download_it_first(self):
        root = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, root, ignore_errors=True)
        os.makedirs(os.path.join(root, "Podcasts"))
        with open(os.path.join(root, feedback.NOTES), "w") as f:
            f.write("")
        asked = []
        real = feedback.allow_icloud_downloads
        feedback.allow_icloud_downloads = lambda: asked.append(True) or True
        try:
            self.assertEqual(feedback.find_notes(lambda: [root]), os.path.join(root, feedback.NOTES))
        finally:
            feedback.allow_icloud_downloads = real
        self.assertEqual(asked, [True])


if __name__ == "__main__":
    unittest.main()
