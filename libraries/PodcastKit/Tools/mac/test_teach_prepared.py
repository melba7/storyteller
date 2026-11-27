"""Tests for teach_prepared.py publish: the audio of each marked episode is copied (a clone first,
a plain copy when that fails) into the iCloud copy of the phone's folder as <id>.<ext>.part and
renamed, hashed, and noted in prepared.json; the three stops for low space. The command runner and
the disk reading are stand-ins, so nothing is really copied through iCloud and no Mac is needed.
Cleaning is in test_teach_prepared_clean.py. Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import hashlib
import json
import os
import shutil
import tempfile
import unittest

import teach_ahead_set as ahead
import teach_prepared as prepared
import teach_store as store
import teach_testing

NOW = 1_800_000_000
DAY = 86400
GB = 1_000_000_000
QUOTA = "%d bytes of quota remaining in paid account"


class Base(unittest.TestCase):
    def setUp(self):
        self.folder = teach_testing.Folder(self)
        self.dest = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.dest, True)
        self.said, self.commands, self.entries = [], [], []
        self.free = 100 * GB
        self.quota = QUOTA % (50 * GB)  # a string, or an exception to raise
        self.clone_fails = False
        self.copy_fails = set()
        self.seen = []

    def prepared_folder(self):
        return os.path.join(self.dest, "Podcasts", "prepared")

    def episode(self, number, size=1000, label=True, audio=True, ahead_too=True, extension="mp3"):
        item = teach_testing.entry(number, audio=audio)
        if audio:
            item["file"] = "audio/%s.%s" % (item["id"], extension)
            item["bytes"] = size
            os.makedirs(self.folder.path("audio"), exist_ok=True)
            with open(self.folder.path(item["file"]), "wb") as f:
                f.write((b"audio %d " % number * (size // 8 + 1))[:size])
        if label:
            os.makedirs(self.folder.path("labels"), exist_ok=True)
            with open(self.folder.path("labels", item["id"] + ".json"), "w") as f:
                json.dump({"version": 1, "episode": item["id"], "writtenAt": NOW * 1000, "segments": []}, f)
        self.entries.append(item)
        self.folder.write_manifest(self.entries)
        if ahead_too:
            ahead.add_ahead(self.folder.dir, [{"id": item["id"], "feed": "https://phone/%d" % number,
                                               "guid": "g%d" % number, "title": "T%d" % number,
                                               "picked": NOW}])
        return item

    def runner(self, command):
        """Stands in for running a program: brctl answers with self.quota, cp copies the file."""
        self.commands.append(list(command))
        if command[0] == "brctl":
            if isinstance(self.quota, Exception):
                raise self.quota
            return 0, self.quota
        clone = command[1] == "-c"
        source, target = command[-2], command[-1]
        self.seen.append((os.path.basename(target), sorted(os.listdir(os.path.dirname(target)))
                          if os.path.isdir(os.path.dirname(target)) else None))
        if (clone and self.clone_fails) or os.path.basename(source) in self.copy_fails:
            return 1, "cp: failed"
        os.makedirs(os.path.dirname(target), exist_ok=True)
        shutil.copyfile(source, target)
        return 0, ""

    def go(self, command="publish", *extra):
        return prepared.main([command, "--folder", self.folder.dir, "--to", self.dest] + list(extra),
                             say=self.said.append, now=lambda: NOW, run=self.runner,
                             free=lambda path: self.free)

    def listed(self):
        return prepared.read_prepared(self.folder.dir)

    def on_dest(self):
        folder = self.prepared_folder()
        return sorted(os.listdir(folder)) if os.path.isdir(folder) else []

    def cps(self):
        return [c for c in self.commands if c[0] == "cp"]


class PublishTests(Base):
    def test_the_audio_is_cloned_to_a_part_file_and_renamed(self):
        item = self.episode(1)
        self.assertEqual(self.go(), 0, self.said)
        self.assertEqual(self.on_dest(), [item["id"] + ".mp3"])
        clone = self.cps()[0]
        self.assertEqual(clone[:2], ["cp", "-c"])
        self.assertEqual(clone[2], self.folder.path(item["file"]))
        self.assertEqual(clone[3], os.path.join(self.prepared_folder(), item["id"] + ".mp3.part"))
        # While it was written the final name did not exist yet, and no .part is left.
        self.assertEqual(self.seen[0][1], [])
        self.assertFalse([n for n in self.on_dest() if n.endswith(".part")])

    def test_a_plain_copy_is_the_fallback_when_the_clone_fails(self):
        item = self.episode(1)
        self.clone_fails = True
        self.assertEqual(self.go(), 0, self.said)
        self.assertEqual([c[:2] for c in self.cps()], [["cp", "-c"], ["cp", self.folder.path(item["file"])]])
        self.assertEqual(self.cps()[1][2], os.path.join(self.prepared_folder(), item["id"] + ".mp3.part"))
        self.assertEqual(self.on_dest(), [item["id"] + ".mp3"])

    def test_a_runner_that_cannot_start_cp_is_a_failed_clone_too(self):
        item = self.episode(1)
        real = self.runner

        def run(command):
            if command[:2] == ["cp", "-c"]:
                raise OSError("no such program")
            return real(command)
        self.runner = run
        self.assertEqual(self.go(), 0, self.said)
        self.assertEqual(self.on_dest(), [item["id"] + ".mp3"])

    def test_prepared_json_lists_id_file_hash_bytes_when_and_not_removed(self):
        item = self.episode(1, size=2_500_000)
        self.go()
        with open(self.folder.path(item["file"]), "rb") as f:
            digest = hashlib.sha256(f.read()).hexdigest()
        with open(self.folder.path("prepared.json")) as f:
            data = json.load(f)
        self.assertEqual(data, {"version": 1, "episodes": [{
            "id": item["id"], "file": "prepared/%s.mp3" % item["id"], "sha256": digest,
            "bytes": 2_500_000, "published": NOW, "removed": None}]})

    def test_the_hash_is_read_in_chunks_and_is_the_same(self):
        item = self.episode(1, size=3000)
        old = prepared.CHUNK
        prepared.CHUNK = 7
        self.addCleanup(setattr, prepared, "CHUNK", old)
        self.go()
        with open(self.folder.path(item["file"]), "rb") as f:
            self.assertEqual(self.listed()[0]["sha256"], hashlib.sha256(f.read()).hexdigest())

    def test_an_episode_is_published_once(self):
        self.episode(1)
        self.go()
        self.commands.clear()
        self.assertEqual(self.go(), 0)
        self.assertEqual(self.cps(), [])
        self.assertEqual(len(self.listed()), 1)

    def test_a_published_episode_whose_file_has_gone_from_icloud_is_published_again(self):
        item = self.episode(1)
        self.go()
        os.remove(os.path.join(self.prepared_folder(), item["id"] + ".mp3"))
        self.go()
        self.assertEqual(self.on_dest(), [item["id"] + ".mp3"])
        self.assertEqual(len(self.listed()), 1)

    def test_other_audio_kinds_keep_their_extension(self):
        item = self.episode(1, extension="m4a")
        self.go()
        self.assertEqual(self.on_dest(), [item["id"] + ".m4a"])

    def test_only_marked_episodes_of_ahead_json_with_audio_are_published(self):
        good = self.episode(1)
        self.episode(2, label=False)
        self.episode(3, audio=False)
        self.episode(4, ahead_too=False)
        exam = self.episode(5)
        with open(self.folder.path("exam.json"), "w") as f:
            json.dump({"version": 1, "episodes": [exam["id"]]}, f)
        shelf = self.episode(6)
        with open(self.folder.path("shelf.json"), "w") as f:
            json.dump({"version": 1, "episodes": [shelf["id"]]}, f)
        self.go()
        self.assertEqual(self.on_dest(), [good["id"] + ".mp3"])

    def test_one_episode_that_cannot_be_copied_does_not_keep_the_others(self):
        first, second = self.episode(1), self.episode(2)
        self.copy_fails = {os.path.basename(first["file"])}
        self.assertEqual(self.go(), 1)
        self.assertEqual(self.on_dest(), [second["id"] + ".mp3"])
        self.assertEqual([e["id"] for e in self.listed()], [second["id"]])
        self.assertTrue(any(first["id"] in line and "could not be copied" in line for line in self.said))

    def test_a_copy_of_the_wrong_size_is_not_kept(self):
        item = self.episode(1)
        real = self.runner

        def short(command):
            code, text = real(command)
            if command[0] == "cp":
                with open(command[-1], "ab") as f:
                    f.write(b"more")
            return code, text
        self.runner = short
        self.assertEqual(self.go(), 1)
        self.assertEqual(self.on_dest(), [])
        self.assertEqual(self.listed(), [])
        self.assertTrue(any("not the size" in line for line in self.said))
        self.assertTrue(item)

    def test_a_damaged_prepared_json_is_a_set_up_problem_and_nothing_is_copied(self):
        self.episode(1)
        with open(self.folder.path("prepared.json"), "w") as f:
            f.write("nope")
        self.assertEqual(self.go(), 2)
        self.assertEqual(self.cps(), [])
        self.assertIn("prepared.json", self.said[-1])

    def test_it_is_refused_while_another_run_holds_the_folder(self):
        self.episode(1)
        with store.run_lock(self.folder.dir):
            self.assertEqual(self.go(), 3)
        self.assertIn("Another teaching run", self.said[-1])
        self.assertEqual(self.cps(), [])


class StopTests(Base):
    def test_no_icloud_folder_stops_it_in_one_line(self):
        self.episode(1)
        shutil.rmtree(self.dest)
        self.assertEqual(self.go(), 3)
        self.assertEqual(len(self.said), 1)
        self.assertIn("iCloud", self.said[0])
        self.assertEqual(self.commands, [])

    def test_under_15_gb_free_on_the_mac_stops_it_in_one_line(self):
        self.episode(1)
        self.free = 15 * GB - 1
        self.assertEqual(self.go(), 3)
        self.assertEqual(len(self.said), 1)
        self.assertIn("15 GB", self.said[0])
        self.assertEqual(self.cps(), [])
        self.assertEqual(self.on_dest(), [])

    def test_exactly_15_gb_free_is_enough_and_the_limit_can_be_changed(self):
        self.episode(1)
        self.free = 15 * GB
        self.assertEqual(self.go(), 0)
        self.free = 4 * GB
        self.episode(2)
        self.assertEqual(self.go("publish", "--keep-free-gb", "5"), 3)
        self.assertEqual(self.go("publish", "--keep-free-gb", "3"), 0)
        self.assertEqual(len(self.on_dest()), 2)

    def test_icloud_with_under_2_gb_plus_the_file_left_stops_it_in_one_line(self):
        item = self.episode(1, size=5000)
        self.quota = QUOTA % (2 * GB + 4999)
        self.assertEqual(self.go(), 3)
        self.assertEqual(len(self.said), 1)
        self.assertIn("iCloud", self.said[0])
        self.assertIn("2 GB", self.said[0])
        self.assertEqual(self.cps(), [])
        self.quota = QUOTA % (2 * GB + 5000)
        self.assertEqual(self.go(), 0)
        self.assertEqual(self.on_dest(), [item["id"] + ".mp3"])

    def test_a_missing_brctl_or_words_it_does_not_understand_do_not_stop_it(self):
        self.episode(1)
        for answer in (FileNotFoundError("brctl"), "something else entirely", "", "unlimited quota"):
            self.quota = answer
            self.assertEqual(self.go(), 0, answer)
            shutil.rmtree(self.prepared_folder())
            os.remove(self.folder.path("prepared.json"))
        self.assertFalse([line for line in self.said if line.startswith("Not published")])

    def test_brctl_is_asked_with_quota_and_a_failing_brctl_does_not_stop_it(self):
        self.episode(1)
        self.go()
        self.assertEqual(self.commands[0], ["brctl", "quota"])

        def failing(command):
            return (1, "error") if command[0] == "brctl" else self.runner_cp(command)
        self.runner_cp, self.runner = self.runner, failing
        shutil.rmtree(self.prepared_folder())
        os.remove(self.folder.path("prepared.json"))
        self.assertEqual(self.go(), 0)

    def test_the_numbers_may_have_commas_and_text_around_them(self):
        self.episode(1, size=1000)
        self.quota = "Quota: 2,000,000,500 bytes of quota remaining in paid account (of 5 TB)"
        self.assertEqual(self.go(), 3)
        self.quota = "Quota: 2,000,001,000 bytes of quota remaining in paid account"
        self.assertEqual(self.go(), 0)

    def test_a_stop_for_space_leaves_what_was_published_before_it(self):
        self.episode(1)
        self.go()
        self.episode(2)
        self.free = 1 * GB
        self.assertEqual(self.go(), 3)
        self.assertEqual(len(self.listed()), 1)


if __name__ == "__main__":
    unittest.main()
