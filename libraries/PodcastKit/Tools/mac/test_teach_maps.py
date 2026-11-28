"""Tests for teach_maps.py: a map is written for each prepared MP3 copy that is in iCloud, with the
marks Claude was sure of, by the map tool (a stand-in here) from the Mac's own copy of that very file
into a folder outside iCloud, and then copied into iCloud; a map that is there is not made again;
the maps of copies that are gone are removed; and ahead-ads.json names the map in its entry.
Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import hashlib
import json
import os

import teach_ahead_ads as ads
import teach_maps as maps
import teach_prepared_file as pfile
import teach_store as store
from test_teach_ahead_ads import NOW, segment
from test_teach_ahead_ads_copy import CopyBase

AUDIO = b"x" * 2000
HASH = hashlib.sha256(AUDIO).hexdigest()


class MapBase(CopyBase):
    def setUp(self):
        super().setUp()
        self.calls = []
        self.fails = None

    def tool(self, command):
        """Stands in for `podcast-ads --map`: notes the call and writes a map of the named copy."""
        self.calls.append(command)
        if self.fails:
            return 1, self.fails
        value = {command[i]: command[i + 1] for i in range(3, len(command), 2)}
        with open(value["--marks"], encoding="utf-8") as f:
            marks = json.load(f)
        with open(value["--out"], "w", encoding="utf-8") as f:
            json.dump({"version": 1, "sha256": value["--sha256"], "feed": value["--feed"],
                       "guid": value["--guid"], "marks": marks, "frames": "AAAA"}, f)
        return 0, "Map written: 3 frames, %d marks, 1 KB.\n" % len(marks)

    def own_audio(self, item):
        return os.path.join(self.night.dir, "audio", item["id"] + ".mp3")

    def publish(self, item, own=AUDIO, **more):
        """Publishes the copy as CopyBase does, of the bytes AUDIO, and keeps the Mac's own copy of
        the audio, as the teaching folder does (`own` None: the Mac has no copy any more)."""
        if own is not None:
            os.makedirs(os.path.dirname(self.own_audio(item)), exist_ok=True)
            with open(self.own_audio(item), "wb") as f:
                f.write(own)
            for one in self.night.entries:
                if one["id"] == item["id"]:
                    one.update(file="audio/%s.mp3" % item["id"], bytes=len(own))
            store.save_manifest(self.night.dir, self.night.entries)
        super().publish(item, size=len(AUDIO), sha=HASH, **more)

    def go(self, *options):
        return maps.main(["publish", "--tool", "/built/podcast-ads", "--folder", self.night.dir,
                          "--to", self.to] + list(options), say=self.night.said.append, run=self.tool)

    def map_path(self, item):
        return os.path.join(self.to, "Podcasts", "maps", item["id"] + ".json")

    def written(self, item):
        with open(self.map_path(item), encoding="utf-8") as f:
            return json.load(f)


class PublishTests(MapBase):
    def test_a_prepared_copy_gets_a_map_made_of_that_file_with_the_phones_feed_and_guid(self):
        item = self.night.add(1)
        self.publish(item)
        self.assertEqual(self.go(), 0, self.night.said)
        self.assertEqual(len(self.calls), 1)
        command = self.calls[0]
        self.assertEqual(command[:3], ["/built/podcast-ads", "--map", self.own_audio(item)])
        made = self.written(item)
        self.assertEqual((made["sha256"], made["feed"], made["guid"]), (HASH, "https://phone/1", "phone-g1"))
        self.assertEqual(made["marks"], [{"start": 10.0, "end": 30.0, "kind": "ad"}])
        self.assertEqual(len(self.night.said), 1)
        self.assertIn("Map of %s" % item["id"], self.night.said[0])

    def test_only_the_marks_claude_was_sure_of_are_in_the_map_and_the_kinds_are_the_phones(self):
        item = self.night.add(1, segments=[segment(1, 1), segment(3, 3, "network_promo", "medium"),
                                           segment(5, 5, "host_ask", "low"), segment(7, 7, "intro_credits")])
        self.publish(item)
        self.assertEqual(self.go(), 0)
        self.assertEqual([(m["start"], m["kind"]) for m in self.written(item)["marks"]],
                         [(0.0, "ad"), (20.0, "promo")])

    def test_the_marks_are_the_snapped_ones_when_there_is_a_snapped_label(self):
        item = self.night.add(1)
        self.publish(item)
        self.snapped(item, [dict(segment(2, 3), start=11.25, end=29.5)])
        self.assertEqual(self.go(), 0)
        self.assertEqual(self.written(item)["marks"], [{"start": 11.25, "end": 29.5, "kind": "ad"}])

    def test_an_episode_with_no_ads_still_gets_a_map(self):
        item = self.night.add(1, segments=[])
        self.publish(item)
        self.assertEqual(self.go(), 0)
        self.assertEqual(self.written(item)["marks"], [])

    def test_a_map_that_is_there_for_this_file_is_not_made_again(self):
        self.publish(self.night.add(1))
        self.assertEqual(self.go(), 0)
        self.assertEqual(self.go(), 0)
        self.assertEqual(len(self.calls), 1)

    def test_a_map_of_another_file_is_made_again(self):
        item = self.night.add(1)
        self.publish(item)
        os.makedirs(os.path.dirname(self.map_path(item)))
        with open(self.map_path(item), "w") as f:
            json.dump({"version": 1, "sha256": "cd" * 32}, f)
        self.assertEqual(self.go(), 0)
        self.assertEqual(self.written(item)["sha256"], HASH)

    def test_an_episode_without_a_copy_in_icloud_or_whose_copy_is_not_mp3_gets_no_map(self):
        self.night.add(1)
        item = self.night.add(2)
        self.publish(item, put_file=False)
        other = self.night.add(3)
        os.makedirs(os.path.join(self.to, "Podcasts", "prepared"), exist_ok=True)
        with open(os.path.join(self.to, "Podcasts", "prepared", other["id"] + ".m4a"), "wb") as f:
            f.write(b"x" * 10)
        pfile.write_prepared(self.night.dir, pfile.read_prepared(self.night.dir) + [
            {"id": other["id"], "file": "prepared/%s.m4a" % other["id"], "sha256": HASH, "bytes": 10,
             "published": NOW, "removed": None}])
        self.assertEqual(self.go(), 0)
        self.assertEqual(self.calls, [])

    def test_a_tool_that_fails_is_said_in_one_line_and_the_other_maps_are_still_made(self):
        first, second = self.night.add(1), self.night.add(2)
        self.publish(first)
        self.publish(second)
        real = self.tool

        def flaky(command):
            if first["id"] in command[2]:
                self.calls.append(command)
                return 1, "No map: it is not an MP3 file a map can be made of.\n"
            return real(command)
        code = maps.main(["publish", "--tool", "t", "--folder", self.night.dir, "--to", self.to],
                         say=self.night.said.append, run=flaky)
        self.assertEqual(code, 1)
        self.assertFalse(os.path.exists(self.map_path(first)))
        self.assertTrue(os.path.exists(self.map_path(second)))
        self.assertEqual(len([line for line in self.night.said if line.startswith("No map of")]), 1)

    def test_a_tool_that_cannot_be_started_is_a_reason_and_not_a_crash(self):
        self.publish(self.night.add(1))

        def missing(command):
            raise FileNotFoundError("no such tool")
        code = maps.main(["publish", "--tool", "t", "--folder", self.night.dir, "--to", self.to],
                         say=self.night.said.append, run=missing)
        self.assertEqual(code, 1)
        self.assertIn("no such tool", self.night.said[0])

    def test_the_marks_file_handed_to_the_tool_is_gone_afterwards(self):
        self.publish(self.night.add(1))
        self.go()
        marks_file = self.calls[0][self.calls[0].index("--marks") + 1]
        self.assertFalse(os.path.exists(marks_file))

    def test_the_tool_reads_and_writes_nothing_in_icloud_and_its_own_files_are_gone_afterwards(self):
        # On the Mac the map tool, run by the preparing job on the copy in iCloud Drive and told to
        # write there, printed nothing for five minutes and was stopped, for every copy.
        item = self.night.add(1)
        self.publish(item)
        self.assertEqual(self.go(), 0, self.night.said)
        command = self.calls[0]
        value = {command[i]: command[i + 1] for i in range(3, len(command), 2)}
        icloud = os.path.realpath(self.to) + os.sep
        for path in (command[2], value["--out"], value["--marks"]):
            self.assertFalse(os.path.realpath(path).startswith(icloud), path)
        self.assertFalse(os.path.exists(value["--out"]))
        self.assertEqual(self.written(item)["sha256"], HASH)
        self.assertEqual(os.listdir(os.path.dirname(self.map_path(item))), [item["id"] + ".json"])

    def test_no_own_copy_or_an_own_copy_that_is_another_file_is_one_line_and_no_map(self):
        never, gone, other, fine = (self.night.add(n) for n in (1, 2, 3, 4))
        self.publish(never, own=None)
        self.publish(gone)
        os.remove(self.own_audio(gone))
        self.publish(other, own=b"y" * 2000)
        self.publish(fine)
        self.assertEqual(self.go(), 1)
        self.assertEqual([c[2] for c in self.calls], [self.own_audio(fine)])
        failed = [line for line in self.night.said if line.startswith("No map of")]
        self.assertEqual(len(failed), 3, self.night.said)
        self.assertTrue(all("own copy" in line for line in failed), failed)
        for item in (never, gone, other):
            self.assertFalse(os.path.exists(self.map_path(item)))

    def test_the_tools_own_folder_is_gone_after_it_failed_too(self):
        self.publish(self.night.add(1))
        self.fails = "No map: it is not an MP3 file a map can be made of.\n"
        self.assertEqual(self.go(), 1)
        out = self.calls[0][self.calls[0].index("--out") + 1]
        self.assertFalse(os.path.exists(os.path.dirname(out)))

    def test_a_damaged_episode_list_is_one_line_and_exit_2(self):
        self.publish(self.night.add(1))
        with open(os.path.join(self.night.dir, "episodes.json"), "w") as f:
            f.write("not json")
        self.assertEqual(self.go(), 2)
        self.assertEqual(self.calls, [])
        self.assertEqual(len(self.night.said), 1, self.night.said)

    def test_the_map_of_a_copy_that_is_gone_is_removed_and_other_files_are_left_alone(self):
        item = self.night.add(1)
        self.publish(item)
        self.go()
        folder = os.path.dirname(self.map_path(item))
        for name in ("0123456789ab.json", "notes.txt", "0123456789ab.json.keep"):
            with open(os.path.join(folder, name), "w") as f:
                f.write("{}")
        self.assertEqual(self.go(), 0)
        self.assertEqual(sorted(os.listdir(folder)),
                         sorted([item["id"] + ".json", "notes.txt", "0123456789ab.json.keep"]))

    def test_no_icloud_copy_of_the_phones_folder_is_one_line_and_exit_3(self):
        self.publish(self.night.add(1))
        self.to = os.path.join(self.to, "nowhere")
        self.assertEqual(self.go(), 3)
        self.assertEqual(self.calls, [])
        self.assertEqual(len(self.night.said), 1)


class ToldTests(MapBase):
    def test_the_entry_of_an_episode_with_a_map_names_it_after_the_copy(self):
        item = self.night.add(1)
        self.publish(item)
        self.go()
        built = self.build()[0]
        self.assertEqual(built["map"], "maps/%s.json" % item["id"])
        self.assertEqual(list(built), ["feed", "guid", "title", "marked", "ads", "copy", "map"])

    def test_an_entry_without_a_map_or_with_a_map_of_another_file_has_no_map_key(self):
        item = self.night.add(1)
        self.publish(item)
        self.assertNotIn("map", self.build()[0])
        os.makedirs(os.path.dirname(self.map_path(item)))
        with open(self.map_path(item), "w") as f:
            json.dump({"version": 1, "sha256": "cd" * 32}, f)
        self.assertNotIn("map", self.build()[0])
        with open(self.map_path(item), "w") as f:
            f.write("not json")
        self.assertNotIn("map", self.build()[0])

    def test_the_file_stays_version_1_and_writing_it_again_with_the_map_changes_it_once(self):
        item = self.night.add(1)
        self.publish(item)
        say = self.night.said.append
        self.assertEqual(ads.write(self.night.dir, NOW, say, to=self.to), "written")
        self.go()
        self.assertEqual(ads.write(self.night.dir, NOW, say, to=self.to), "written")
        self.assertEqual(ads.write(self.night.dir, NOW, say, to=self.to), "unchanged")
        with open(os.path.join(self.night.dir, ads.FILE)) as f:
            data = json.load(f)
        self.assertEqual(data["version"], 1)
        self.assertEqual(data["episodes"][0]["map"], "maps/%s.json" % item["id"])
