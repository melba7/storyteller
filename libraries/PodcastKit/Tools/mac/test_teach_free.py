"""Tests for teach_free.py: freeing disk space by deleting the audio of episodes whose lessons are
already kept. Temporary folders only; no Mac, no network, no Claude.
Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import contextlib
import io
import json
import os
import unittest

import teach_collect
import teach_free as free
import teach_store as store
from teach_testing import Folder, entry, transcript


class Setup(unittest.TestCase):
    """A teaching folder whose episodes have audio on disk."""

    def setUp(self):
        self.folder = Folder(self)
        self.dir = self.folder.dir
        self.said = []
        self.backups = []

    def episodes(self, count):
        self.entries = [entry(n, audio=True, bytes=50) for n in range(1, count + 1)]
        self.folder.write_manifest(self.entries)
        for item in self.entries:
            self.write("audio/%s.mp3" % item["id"], "x" * 50)
        return self.entries

    def write(self, name, text):
        os.makedirs(os.path.dirname(self.folder.path(name)), exist_ok=True)
        with open(self.folder.path(name), "w") as handle:
            handle.write(text)

    def learned(self, item, bank=True, truth=True):
        """Gives an episode a transcript, marks, a second-download truth and a sound bank. The bank is
        a little newer than the rest, as when the sounds step ran after the last change."""
        self.write("transcripts/%s.txt" % item["id"], transcript(5))
        self.write("labels/%s.json" % item["id"], "{}")
        if truth:
            self.write("copies/%s.truth.txt" % item["id"], "12.0 30.0\n")
        if bank:
            self.write("sound-bank/%s.json" % item["id"], json.dumps(
                {"version": 1, "episode": item["id"], "stretches": []}))
        self.touch(item, "transcripts/%s.txt", 0)
        self.touch(item, "labels/%s.json", 0)
        self.touch(item, "copies/%s.truth.txt", 0)
        self.touch(item, "sound-bank/%s.json", 10)

    def touch(self, item, pattern, seconds):
        path = self.folder.path(pattern % item["id"])
        if os.path.exists(path):
            os.utime(path, (1_700_000_000 + seconds, 1_700_000_000 + seconds))

    def listed(self, name, ids):
        self.write(name, json.dumps({"version": 1, "episodes": [
            {"id": identifier} if name == "ahead.json" else identifier for identifier in ids]}))

    def backup(self, folder, check=False, say=print):
        self.backups.append([name for name in os.listdir(os.path.join(folder, "audio"))])
        return 0

    def run_it(self, *args, backup=None):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = free.main(["--folder", self.dir] + list(args), say=self.said.append,
                             backup=backup or self.backup)
        return code

    def audio(self):
        return sorted(os.listdir(self.folder.path("audio")))

    def manifest(self):
        return {item["id"]: item for item in store.load_manifest(self.dir)}


class FreeTests(Setup):
    def test_deletes_audio_that_has_a_transcript_and_marks_and_nothing_else(self):
        first, second, third = self.episodes(3)
        self.learned(first)
        self.write("transcripts/%s.txt" % second["id"], transcript(5))  # no marks
        self.write("labels/%s.json" % third["id"], "{}")  # no transcript
        self.assertEqual(self.run_it("--delete"), 0)
        self.assertEqual(self.audio(), sorted([second["id"] + ".mp3", third["id"] + ".mp3"]))
        self.assertTrue(os.path.exists(self.folder.path("transcripts", first["id"] + ".txt")))
        self.assertTrue(os.path.exists(self.folder.path("labels", first["id"] + ".json")))

    def test_audio_stays_until_its_sound_bank_is_saved(self):
        first, second, third, fourth = self.episodes(4)
        self.learned(first)
        self.learned(second, bank=False)
        self.learned(third)
        self.write("sound-bank/%s.json" % third["id"], "{")  # damaged
        self.learned(fourth)
        self.write("sound-bank/%s.json" % fourth["id"], json.dumps(
            {"version": 1, "episode": "someone else", "stretches": []}))
        self.assertEqual(self.run_it("--delete"), 0)
        self.assertEqual(self.audio(), sorted(item["id"] + ".mp3" for item in (second, third, fourth)))
        self.assertTrue(os.path.exists(self.folder.path("sound-bank", first["id"] + ".json")))

    def test_a_bank_older_than_the_marks_or_the_second_download_is_not_enough(self):
        first, second, third, fourth = self.episodes(4)
        for item in (first, second, third, fourth):
            self.learned(item)
        self.touch(second, "labels/%s.json", 20)  # marked again after the bank was saved
        self.touch(third, "copies/%s.truth.txt", 20)  # compared after the bank was saved
        for item in (first, second, third, fourth):
            self.write("labels-snapped/%s.json" % item["id"], "{}")
            self.touch(item, "labels-snapped/%s.json", 20 if item is fourth else 0)  # fourth: after the bank
        self.run_it("--delete")
        self.assertEqual(self.audio(), sorted(item["id"] + ".mp3" for item in (second, third, fourth)))

    def test_with_snapped_labels_every_episode_needs_its_snapped_label(self):
        first, second = self.episodes(2)
        self.learned(first)
        self.learned(second)
        self.write("labels-snapped/%s.json" % first["id"], "{}")
        self.touch(first, "labels-snapped/%s.json", 0)
        self.run_it("--delete")
        self.assertEqual(self.audio(), [second["id"] + ".mp3"])

    def test_an_episode_not_compared_with_its_second_download_keeps_its_audio(self):
        first, second, third = self.episodes(3)
        self.learned(first)
        self.learned(second, truth=False)
        self.learned(third, truth=False)
        self.write("copies/failed.json", json.dumps({"version": 1, "failed": {third["id"]: 3}}))
        self.run_it("--delete")
        self.assertEqual(self.audio(), [second["id"] + ".mp3"])  # third was given up on, so it goes

    def test_without_copies_frees_those_waiting_for_a_second_download_too(self):
        first, = self.episodes(1)
        self.learned(first, truth=False)
        self.run_it("--delete", "--without-copies")
        self.assertEqual(self.audio(), [])

    def test_it_says_how_many_more_could_go_without_the_second_download(self):
        first, second = self.episodes(2)
        self.learned(first)
        self.learned(second, truth=False)
        self.run_it()
        self.assertTrue(any("1 more" in line and "gives up that comparison" in line for line in self.said))

    def test_an_episode_that_is_not_an_mp3_needs_no_bank_and_no_second_download(self):
        item = entry(1, audio=True, bytes=50, file="audio/%s.m4a" % entry(1)["id"])
        self.folder.write_manifest([item])
        self.write(item["file"], "x" * 50)
        self.learned(item, bank=False, truth=False)
        self.run_it("--delete")
        self.assertEqual(self.audio(), [])

    def test_a_freed_episode_is_written_down_so_it_is_never_downloaded_again(self):
        first, = self.episodes(1)
        self.learned(first)
        self.run_it("--delete")
        freed = self.manifest()[first["id"]]  # load_manifest also checks the entry's shape
        self.assertIsNone(freed["file"])
        self.assertEqual(freed["bytes"], 0)
        self.assertTrue(teach_collect.is_skipped(freed))
        self.assertEqual(freed["address"], first["address"])

    def test_the_shelf_the_exam_and_the_read_ahead_keep_their_audio(self):
        items = self.episodes(4)
        for item in items:
            self.learned(item)
        self.listed("shelf.json", [items[0]["id"]])
        self.listed("exam.json", [items[1]["id"]])
        self.listed("ahead.json", [items[2]["id"]])
        self.run_it("--delete")
        self.assertEqual(self.audio(), sorted(item["id"] + ".mp3" for item in items[:3]))

    def test_without_delete_nothing_is_deleted_or_backed_up(self):
        first, = self.episodes(1)
        self.learned(first)
        self.assertEqual(self.run_it(), 0)
        self.assertEqual(self.audio(), [first["id"] + ".mp3"])
        self.assertEqual(self.backups, [])
        self.assertIsNotNone(self.manifest()[first["id"]]["file"])
        self.assertTrue(any("--delete" in line for line in self.said))

    def test_the_backup_is_made_before_the_audio_goes(self):
        first, = self.episodes(1)
        self.learned(first)
        self.run_it("--delete")
        self.assertEqual(self.backups, [[first["id"] + ".mp3"]])

    def test_a_backup_that_is_not_good_stops_everything(self):
        first, = self.episodes(1)
        self.learned(first)
        code = self.run_it("--delete", backup=lambda folder, check=False, say=print: 1)
        self.assertEqual(code, 1)
        self.assertEqual(self.audio(), [first["id"] + ".mp3"])
        self.assertIsNotNone(self.manifest()[first["id"]]["file"])

    def test_it_is_refused_while_another_run_holds_the_folder(self):
        first, = self.episodes(1)
        self.learned(first)
        with store.run_lock(self.dir):
            self.assertEqual(self.run_it("--delete"), 3)
        self.assertEqual(self.audio(), [first["id"] + ".mp3"])

    def test_an_entry_whose_file_is_already_gone_is_put_right(self):
        first, = self.episodes(1)
        self.learned(first)
        os.remove(self.folder.path("audio", first["id"] + ".mp3"))
        self.run_it("--delete")
        freed = self.manifest()[first["id"]]
        self.assertIsNone(freed["file"])
        self.assertTrue(teach_collect.is_skipped(freed))

    def test_a_damaged_list_is_left_alone(self):
        self.write("episodes.json", "{")
        self.assertEqual(self.run_it("--delete"), 2)

    def test_a_damaged_exam_file_stops_before_anything_is_deleted(self):
        first, = self.episodes(1)
        self.learned(first)
        self.write("exam.json", "{")
        self.assertEqual(self.run_it("--delete"), 2)
        self.assertEqual(self.audio(), [first["id"] + ".mp3"])

    def test_nothing_to_free_is_said_and_is_not_an_error(self):
        self.episodes(2)
        self.assertEqual(self.run_it("--delete"), 0)
        self.assertEqual(self.backups, [])
        self.assertTrue(any("nothing to free" in line.lower() for line in self.said))


if __name__ == "__main__":
    unittest.main()
