"""Tests that teach_ahead_ads.py gives an entry the "copy" block of a prepared file: the block and
its hash, an entry with a copy and no ads that is kept, the times taken from labels-snapped when
there is a snapped label, and an entry without a copy that is exactly as it was.
Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import json
import os
import shutil
import tempfile
import unittest

import teach_ahead_ads as ads
import teach_prepared_file as pfile
from test_teach_ahead_ads import NOW, Night, segment

HASH = "ab" * 32


class CopyBase(unittest.TestCase):
    def setUp(self):
        self.night = Night(self)
        self.to = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.to, True)

    def publish(self, item, size=2000, days_ago=1, removed=None, put_file=True, sha=HASH):
        name = "prepared/%s.mp3" % item["id"]
        if put_file:
            os.makedirs(os.path.join(self.to, "Podcasts", "prepared"), exist_ok=True)
            with open(os.path.join(self.to, "Podcasts", name), "wb") as f:
                f.write(b"x" * size)
        found = pfile.read_prepared(self.night.dir)
        found.append({"id": item["id"], "file": name, "sha256": sha, "bytes": size,
                      "published": NOW - days_ago * 86400, "removed": removed})
        pfile.write_prepared(self.night.dir, found)

    def snapped(self, item, segments):
        os.makedirs(os.path.join(self.night.dir, "labels-snapped"), exist_ok=True)
        with open(os.path.join(self.night.dir, "labels-snapped", item["id"] + ".json"), "w") as f:
            json.dump({"version": 1, "episode": item["id"], "writtenAt": NOW * 1000, "segments": segments}, f)

    def build(self):
        return ads.build(self.night.dir, NOW, self.night.said.append, self.to)


class CopyTests(CopyBase):
    def test_a_published_file_gives_the_entry_a_copy_block(self):
        item = self.night.add(1)
        self.publish(item, size=2000)
        built = self.build()[0]
        self.assertEqual(built["copy"], {"file": "prepared/%s.mp3" % item["id"], "sha256": HASH, "bytes": 2000})
        self.assertEqual(list(built), ["feed", "guid", "title", "marked", "ads", "copy"])
        self.assertEqual(list(built["copy"]), ["file", "sha256", "bytes"])

    def test_the_copy_block_is_written_into_the_file_the_phone_reads(self):
        item = self.night.add(1)
        self.publish(item)
        self.assertEqual(ads.write(self.night.dir, NOW, self.night.said.append, to=self.to), "written")
        with open(os.path.join(self.night.dir, ads.FILE)) as f:
            data = json.load(f)
        self.assertEqual(data["version"], 1)
        self.assertEqual(data["episodes"][0]["copy"]["sha256"], HASH)

    def test_an_entry_with_a_copy_and_no_ads_is_kept_with_its_empty_list(self):
        item = self.night.add(1, segments=[])
        self.publish(item)
        built = self.build()[0]
        self.assertEqual((built["ads"], built["copy"]["bytes"]), ([], 2000))

    def test_without_a_copy_the_entry_is_exactly_as_before(self):
        self.night.add(1)
        self.assertEqual(list(self.build()[0]), ["feed", "guid", "title", "marked", "ads"])

    def test_no_copy_when_the_file_is_not_there_has_another_size_was_removed_or_the_hash_is_bad(self):
        cases = (dict(put_file=False), dict(size=1999), dict(removed=NOW - 5), dict(sha="short"))
        for number, more in enumerate(cases, 1):
            item = self.night.add(number)
            self.publish(item, **dict({"size": 2000}, **more))
            if more.get("size") == 1999:  # the file on disk is 1999 bytes, the list says 2000
                with open(os.path.join(self.to, "Podcasts", "prepared", item["id"] + ".mp3"), "wb") as f:
                    f.write(b"x" * 1999)
                pfile.write_prepared(self.night.dir, [dict(e, bytes=2000) for e in pfile.read_prepared(self.night.dir)])
        for built in self.build():
            self.assertNotIn("copy", built)

    def test_no_copy_without_an_icloud_folder_to_look_in(self):
        item = self.night.add(1)
        self.publish(item)
        self.assertNotIn("copy", ads.build(self.night.dir, NOW, self.night.said.append, None)[0])

    def test_a_name_that_is_not_of_the_form_is_not_told(self):
        item = self.night.add(1)
        self.publish(item)
        found = pfile.read_prepared(self.night.dir)
        found[0]["file"] = "prepared/../ad-model.json"
        pfile.write_prepared(self.night.dir, found)
        self.assertNotIn("copy", self.build()[0])


class CommandTests(CopyBase):
    def write(self, *options, defaults=None):
        import teach_ahead
        return teach_ahead.main(["write", "--folder", self.night.dir] + list(options),
                                say=self.night.said.append, now=lambda: NOW,
                                defaults=defaults or (lambda: ["/nowhere/mac", "/nowhere/icloud"]))

    def told(self):
        with open(os.path.join(self.night.dir, ads.FILE)) as f:
            return json.load(f)["episodes"][0]

    def test_write_looks_for_the_audio_in_the_icloud_copy_the_publisher_writes_last(self):
        self.publish(self.night.add(1))
        self.assertEqual(self.write(defaults=lambda: ["/nowhere/mac", self.to]), 0)
        self.assertIn("copy", self.told())

    def test_write_can_be_pointed_at_another_folder(self):
        self.publish(self.night.add(1))
        self.assertEqual(self.write("--prepared-to", self.to), 0)
        self.assertIn("copy", self.told())

    def test_write_with_no_icloud_folder_tells_words_only(self):
        self.publish(self.night.add(1))
        self.write()
        self.assertNotIn("copy", self.told())


class SnappedTests(CopyBase):
    def test_the_times_of_a_copy_come_from_the_snapped_label_when_there_is_one(self):
        item = self.night.add(1, segments=[segment(2, 3)])
        self.publish(item)
        moved = dict(segment(2, 3), start=10.48, end=30.12)
        self.snapped(item, [moved])
        found = self.build()[0]["ads"][0]
        self.assertEqual((found["start"], found["end"]), (10.48, 30.12))

    def test_the_times_come_from_labels_when_there_is_no_snapped_label(self):
        item = self.night.add(1, segments=[segment(2, 3)])
        self.publish(item)
        found = self.build()[0]["ads"][0]
        self.assertEqual((found["start"], found["end"]), (10.0, 30.0))

    def test_a_snapped_label_that_cannot_be_read_falls_back_to_labels_and_says_so(self):
        item = self.night.add(1, segments=[segment(2, 3)])
        self.publish(item)
        os.makedirs(os.path.join(self.night.dir, "labels-snapped"))
        with open(os.path.join(self.night.dir, "labels-snapped", item["id"] + ".json"), "w") as f:
            f.write("nope")
        self.assertEqual(self.build()[0]["ads"][0]["start"], 10.0)
        self.assertTrue(any("snapped" in line for line in self.night.said))

    def test_an_added_stretch_of_the_snapped_label_is_told_with_its_own_words(self):
        item = self.night.add(1, segments=[])
        self.publish(item)
        self.snapped(item, [dict(segment(5, 6, confidence="medium"), start=40.0, end=60.0)])
        found = self.build()[0]["ads"]
        self.assertEqual([(a["start"], a["end"], a["confidence"]) for a in found], [(40.0, 60.0, "medium")])
        self.assertIn("word5a", found[0]["startWords"])

    def test_without_a_copy_the_snapped_label_is_not_used(self):
        item = self.night.add(1, segments=[segment(2, 3)])
        self.snapped(item, [dict(segment(2, 3), start=11.0, end=29.0)])
        self.assertEqual(self.build()[0]["ads"][0]["start"], 10.0)


if __name__ == "__main__":
    unittest.main()
