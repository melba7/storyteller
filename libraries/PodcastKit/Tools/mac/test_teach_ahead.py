"""Tests for teach_ahead.py: reading the phone's list of next episodes, choosing the night's episodes
(never one that is marked, in the teaching set, in the exam or on the shelf), the weekly budget, the
episodes that get audio, and a night with nothing to do. No network, no Claude, no iCloud: the
folders are made up. Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import json
import os
import shutil
import tempfile
import unittest
from unittest import mock

import teach_ahead as night
import teach_ahead_set as ahead
import teach_budget
import teach_store as store
from teach_feed import episode_id
from teach_testing import entry

NOW = 1_800_000_000


def queued(number, **more):
    one = {"feed": "https://phone.example/feed%d.xml" % number, "guid": "guid-%d" % number,
           "title": "Episode %d" % number, "show": "Show %d" % number,
           "audio": "https://cdn.example/%d.mp3" % number, "reason": "upNext", "rank": number - 1}
    one.update(more)
    return one


class Setup(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.root, True)
        self.folder = os.path.join(self.root, "teaching")
        self.mac = os.path.join(self.root, "LofiMusic")
        self.icloud = os.path.join(self.root, "iCloud", "LofiMusic")
        for name in (self.folder, os.path.join(self.mac, "Podcasts"), os.path.join(self.icloud, "Podcasts")):
            os.makedirs(name)
        self.said = []

    def write_queue(self, episodes, where=None, **more):
        data = {"version": 1, "writtenAt": NOW}
        data.update(more)
        data["episodes"] = episodes
        with open(os.path.join(where or self.icloud, "Podcasts", "phone-queue.json"), "w") as f:
            json.dump(data, f)

    def run_command(self, *options, command="pick", shows=(), budget=True):
        extra = ["--budget", "ahead-2026-W48"] if budget and command == "pick" else []
        return night.main([command, "--folder", self.folder] + extra + list(options), say=self.said.append,
                          defaults=lambda: [self.mac, self.icloud], now=lambda: NOW,
                          load_shows=lambda path: list(shows))

    def manifest(self):
        return store.load_manifest(self.folder)

    def picked_guids(self):
        return [e["guid"] for e in ahead.read_ahead(self.folder)]


class ReadQueueTests(Setup):
    def read(self, text):
        path = os.path.join(self.root, "q.json")
        with open(path, "w") as f:
            f.write(text)
        return night.read_queue(path)

    def test_the_episodes_come_back_in_rank_order(self):
        items, bad = self.read(json.dumps({"version": 1, "writtenAt": 1, "episodes": [
            queued(3, rank=2), queued(1, rank=0), queued(2, rank=1)]}))
        self.assertEqual(([i["guid"] for i in items], bad), (["guid-1", "guid-2", "guid-3"], 0))

    def test_an_episode_that_cannot_be_fetched_is_counted_and_left_out(self):
        items, bad = self.read(json.dumps({"version": 1, "episodes": [
            queued(1), queued(2, guid=""), queued(3, audio="ftp://x/a.mp3"), queued(4, feed="local:files"),
            queued(5, title=None), "text", queued(6, rank="first")]}))
        self.assertEqual(([i["guid"] for i in items], bad), (["guid-1"], 6))

    def test_a_file_that_is_not_a_version_1_list_is_refused(self):
        for text in ("", "nope", "[]", '{"version": 2, "episodes": []}', '{"version": 1}',
                     '{"version": 1, "episodes": {}}'):
            with self.assertRaises(ValueError, msg=text):
                self.read(text)

    def test_a_file_over_a_megabyte_is_refused(self):
        with self.assertRaises(ValueError):
            self.read(json.dumps({"version": 1, "episodes": [], "pad": "x" * (1024 * 1024)}))


class PickTests(Setup):
    def test_a_night_with_no_queue_file_does_nothing(self):
        code = self.run_command()
        self.assertEqual(code, 3)
        self.assertEqual(os.listdir(self.folder), [])
        self.assertEqual(len(self.said), 1)
        self.assertIn("phone-queue.json", self.said[0])

    def test_the_icloud_copy_is_read_before_the_macs_own(self):
        self.write_queue([queued(1)], where=self.mac)
        self.write_queue([queued(2)], where=self.icloud)
        self.assertEqual(self.run_command(), 0)
        self.assertEqual(self.picked_guids(), ["guid-2"])

    def test_the_macs_own_copy_is_used_when_there_is_no_icloud_copy(self):
        self.write_queue([queued(1)], where=self.mac)
        self.assertEqual(self.run_command(), 0)
        self.assertEqual(self.picked_guids(), ["guid-1"])

    def test_an_explicit_queue_file_is_read_instead(self):
        self.write_queue([queued(1)])
        path = os.path.join(self.root, "mine.json")
        with open(path, "w") as f:
            json.dump({"version": 1, "episodes": [queued(7)]}, f)
        self.assertEqual(self.run_command("--queue", path), 0)
        self.assertEqual(self.picked_guids(), ["guid-7"])

    def test_the_night_takes_eight_in_the_phones_order(self):
        self.write_queue([queued(n) for n in range(1, 13)])
        self.assertEqual(self.run_command(), 0)
        self.assertEqual(self.picked_guids(), ["guid-%d" % n for n in range(1, 9)])
        self.assertEqual(len(self.manifest()), 8)

    def test_the_picked_episodes_join_the_teaching_set_waiting_for_a_download(self):
        self.write_queue([queued(1)])
        self.run_command()
        [one] = self.manifest()
        store.check_entry(one)
        self.assertEqual((one["show"], one["title"], one["guid"], one["address"]),
                         ("Show 1", "Episode 1", "guid-1", "https://cdn.example/1.mp3"))
        self.assertEqual((one["file"], one["bytes"], one["error"]), (None, 0, None))
        self.assertEqual(one["id"], episode_id("https://phone.example/feed1.xml", "guid-1", ""))
        [flagged] = ahead.read_ahead(self.folder)
        self.assertEqual(flagged, {"id": one["id"], "feed": "https://phone.example/feed1.xml",
                                   "guid": "guid-1", "title": "Episode 1", "picked": NOW})

    def test_the_phones_published_time_is_kept_in_the_teaching_set(self):
        # The phone writes it in seconds since 1970, the way the Mac's feed reading does.
        self.write_queue([queued(1, published=1_700_000_000), queued(2, published=1_700_086_400.0)])
        self.run_command()
        self.assertEqual([e["published"] for e in self.manifest()], [1_700_000_000, 1_700_086_400])
        self.assertTrue(all(isinstance(e["published"], int) for e in self.manifest()))

    def test_a_queue_with_no_published_time_or_a_wrong_one_keeps_none(self):
        # An older phone writes no time. Anything that is not a number is no time either.
        self.write_queue([queued(1), queued(2, published=None), queued(3, published="yesterday"),
                          queued(4, published=True), queued(5, published=float("nan"))])
        self.run_command()
        self.assertEqual([e["published"] for e in self.manifest()], [None] * 5)

    def test_the_flag_is_written_before_the_teaching_set(self):
        self.write_queue([queued(1)])
        with mock.patch.object(night.teach_store, "save_manifest", side_effect=OSError("disk")):
            self.assertEqual(self.run_command(), 2)
        self.assertEqual(self.picked_guids(), ["guid-1"])

    def test_an_episode_already_in_the_teaching_set_is_not_picked(self):
        known = entry(1, feed="https://phone.example/feed1.xml", guid="guid-1")
        store.save_manifest(self.folder, [known])
        self.write_queue([queued(1), queued(2)])
        self.assertEqual(self.run_command(), 0)
        self.assertEqual(self.picked_guids(), ["guid-2"])
        self.assertEqual(len(self.manifest()), 2)

    def test_the_same_episode_under_another_spelling_of_its_feed_is_not_picked(self):
        known = entry(1, feed="https://Example.com/feed.xml/", guid="guid-1", address="https://a/other.mp3")
        store.save_manifest(self.folder, [known])
        self.write_queue([queued(1, feed="http://www.example.com/feed.xml", audio="https://b/new.mp3")])
        self.assertEqual(self.run_command(), 3)
        self.assertEqual(self.picked_guids(), [])

    def test_an_episode_without_a_guid_in_the_set_is_known_by_its_audio_address(self):
        known = entry(1, feed="https://phone.example/feed1.xml", guid="", address="https://cdn.example/1.mp3")
        store.save_manifest(self.folder, [known])
        self.write_queue([queued(1)])
        self.assertEqual(self.run_command(), 3)
        self.assertEqual(self.picked_guids(), [])

    def test_an_exam_or_shelf_episode_is_never_picked(self):
        # Even when the teaching set no longer lists them, the exam and the shelf keep them out.
        exam = episode_id(queued(1)["feed"], "guid-1", "")
        shelf = episode_id(queued(2)["feed"], "guid-2", "")
        store.write_json(os.path.join(self.folder, "exam.json"), {"episodes": [exam]})
        store.write_json(os.path.join(self.folder, "shelf.json"), {"version": 1, "episodes": [shelf]})
        self.write_queue([queued(1), queued(2), queued(3)])
        self.assertEqual(self.run_command(), 0)
        self.assertEqual(self.picked_guids(), ["guid-3"])

    def test_an_episode_of_an_earlier_night_is_not_picked_again(self):
        self.write_queue([queued(1), queued(2)])
        self.run_command()
        self.said.clear()
        self.assertEqual(self.run_command(), 3)
        self.assertEqual(len(self.manifest()), 2)
        self.assertIn("already", " ".join(self.said))

    def test_an_episode_listed_twice_is_picked_once(self):
        self.write_queue([queued(1), queued(1, rank=5)])
        self.run_command()
        self.assertEqual(self.picked_guids(), ["guid-1"])

    def test_the_macs_own_spelling_of_a_followed_feed_gives_the_id_but_the_phones_is_kept(self):
        shows = [{"feed": "https://example.com/feed.xml", "title": "Followed"}]
        self.write_queue([queued(1, feed="http://www.example.com/feed.xml/")])
        self.assertEqual(self.run_command(shows=shows), 0)
        [one] = self.manifest()
        self.assertEqual((one["feed"], one["id"]),
                         ("https://example.com/feed.xml", episode_id("https://example.com/feed.xml", "guid-1", "")))
        self.assertEqual(ahead.read_ahead(self.folder)[0]["feed"], "http://www.example.com/feed.xml/")

    def test_a_damaged_queue_is_a_set_up_problem_and_changes_nothing(self):
        with open(os.path.join(self.icloud, "Podcasts", "phone-queue.json"), "w") as f:
            f.write("{nope")
        self.assertEqual(self.run_command(), 2)
        self.assertEqual(os.listdir(self.folder), [])
        self.assertIn("phone-queue.json", self.said[-1])

    def test_a_queue_with_nothing_in_it_does_nothing(self):
        self.write_queue([])
        self.assertEqual(self.run_command(), 3)
        self.assertEqual(os.listdir(self.folder), [])

    def test_a_damaged_teaching_set_stops_it_with_the_reason(self):
        with open(os.path.join(self.folder, "episodes.json"), "w") as f:
            f.write("{nope")
        self.write_queue([queued(1)])
        self.assertEqual(self.run_command(), 2)
        self.assertIn("episodes.json", self.said[-1])

    def test_a_macOS_permission_problem_is_said_with_what_to_do(self):
        def refused(defaults, denied=None, name=None):
            denied.append(os.path.join(self.icloud, "Podcasts", "phone-queue.json"))
        with mock.patch.object(night.teach_feedback, "find_notes", refused):
            self.assertEqual(self.run_command(), 2)
        self.assertIn("Full Disk Access", self.said[-1])

    def test_another_run_in_the_folder_means_nothing_tonight(self):
        self.write_queue([queued(1)])
        with store.run_lock(self.folder):
            self.assertEqual(self.run_command(), 3)
        self.assertEqual(self.picked_guids(), [])


class BudgetTests(Setup):
    def spend(self, dollars, episodes=1):
        teach_budget.Budget(self.folder, "ahead-2026-W48", 10).add(dollars, episodes)

    def test_the_cap_limits_how_many_are_picked(self):
        self.spend(9.5)  # $0.50 left: two episodes at about $0.19
        self.write_queue([queued(n) for n in range(1, 9)])
        self.assertEqual(self.run_command("--cap", "10"), 0)
        self.assertEqual(self.picked_guids(), ["guid-1", "guid-2"])

    def test_an_episode_that_would_reach_the_cap_exactly_is_not_picked(self):
        # Two episodes at $0.19 would make $0.38, the cap: the marking stops before a call that
        # reaches the cap, so only one is picked.
        self.spend(9.62)
        self.write_queue([queued(n) for n in range(1, 5)])
        self.assertEqual(self.run_command("--cap", "10"), 0)
        self.assertEqual(self.picked_guids(), ["guid-1"])

    def test_nothing_is_picked_when_not_even_one_episode_fits(self):
        self.spend(9.9)
        self.write_queue([queued(1)])
        self.assertEqual(self.run_command("--cap", "10"), 3)
        self.assertEqual(self.picked_guids(), [])
        self.assertEqual(self.manifest(), [])
        self.assertIn("cap", " ".join(self.said))
        self.assertIn("$10.00", " ".join(self.said))

    def test_the_cap_is_ten_dollars_and_the_estimate_nineteen_cents_unless_changed(self):
        self.assertEqual((night.CAP, night.ESTIMATE, night.MOST), (10.0, 0.19, 8))
        self.write_queue([queued(n) for n in range(1, 9)])
        self.run_command()
        self.assertEqual(len(self.picked_guids()), 8)

    def test_a_week_with_nothing_spent_has_room_for_the_whole_night(self):
        self.write_queue([queued(n) for n in range(1, 4)])
        self.assertEqual(self.run_command("--cap", "0.6"), 0)
        self.assertEqual(len(self.picked_guids()), 3)

    def test_a_damaged_budget_file_is_a_set_up_problem(self):
        with open(os.path.join(self.folder, "marking-spend.json"), "w") as f:
            f.write("nope")
        self.write_queue([queued(1)])
        self.assertEqual(self.run_command(), 2)
        self.assertEqual(self.picked_guids(), [])

    def test_the_budget_needs_a_name_and_the_cap_a_number(self):
        self.write_queue([queued(1)])
        self.assertEqual(self.run_command(budget=False), 2)
        for bad in ("abc", "0", "-3", "nan"):
            self.assertEqual(self.run_command("--cap", bad), 2, bad)
        self.assertEqual(self.picked_guids(), [])


class ReadyTests(Setup):
    def add(self, number, audio, label=False):
        item = entry(number, audio=audio)
        known = store.load_manifest(self.folder)
        store.save_manifest(self.folder, known + [item])
        ahead.add_ahead(self.folder, [{"id": item["id"], "feed": item["feed"], "guid": "g", "title": "t",
                                       "picked": NOW}])
        if audio:
            os.makedirs(os.path.join(self.folder, "audio"), exist_ok=True)
            with open(os.path.join(self.folder, item["file"]), "wb") as f:
                f.write(b"x")
        if label:
            os.makedirs(os.path.join(self.folder, "labels"), exist_ok=True)
            with open(os.path.join(self.folder, "labels", item["id"] + ".json"), "w") as f:
                f.write("{}")
        return item

    def test_an_episode_with_audio_and_no_label_is_ready(self):
        self.add(1, audio=True)
        self.assertEqual(self.run_command(command="ready"), 0)
        self.assertIn("1 episode", self.said[-1])

    def test_no_audio_means_nothing_to_write_down_or_mark_and_says_so_in_one_line(self):
        self.add(1, audio=False)
        self.assertEqual(self.run_command(command="ready"), 3)
        self.assertEqual(len(self.said), 1)
        self.assertIn("online", self.said[0])

    def test_a_marked_episode_is_not_ready_again(self):
        self.add(1, audio=True, label=True)
        self.assertEqual(self.run_command(command="ready"), 3)

    def test_an_episode_that_is_not_in_ahead_json_is_not_counted(self):
        store.save_manifest(self.folder, [entry(1, audio=True)])
        self.assertEqual(self.run_command(command="ready"), 3)


class WriteCommandTests(Setup):
    def test_with_nothing_marked_it_writes_nothing_and_succeeds(self):
        self.assertEqual(self.run_command(command="write"), 0)
        self.assertFalse(os.path.exists(os.path.join(self.folder, "ahead-ads.json")))

    def test_a_marked_episode_ends_up_in_the_file(self):
        item = entry(1, feed="https://mac/1", guid="g1")
        store.save_manifest(self.folder, [item])
        ahead.add_ahead(self.folder, [{"id": item["id"], "feed": "https://phone/1", "guid": "pg1",
                                       "title": "T", "picked": NOW}])
        os.makedirs(os.path.join(self.folder, "labels"))
        os.makedirs(os.path.join(self.folder, "transcripts"))
        with open(os.path.join(self.folder, "transcripts", item["id"] + ".txt"), "w") as f:
            f.write("[00:00:01.0] hello there\n[00:00:09.0] buy this now\n[00:00:20.0] back to the show\n")
        with open(os.path.join(self.folder, "labels", item["id"] + ".json"), "w") as f:
            json.dump({"writtenAt": (NOW - 60) * 1000, "segments": [
                {"first": 2, "last": 2, "sort": "sponsor", "confidence": "high", "start": 9.0, "end": 20.0}]}, f)
        self.assertEqual(self.run_command(command="write"), 0)
        with open(os.path.join(self.folder, "ahead-ads.json")) as f:
            found = json.load(f)
        self.assertEqual(found["episodes"][0]["ads"][0]["startWords"], "buy this now")
        self.assertIn("written", self.said[-1])

    def test_a_damaged_ahead_json_is_a_set_up_problem(self):
        with open(os.path.join(self.folder, "ahead.json"), "w") as f:
            f.write("nope")
        self.assertEqual(self.run_command(command="write"), 2)
        self.assertIn("ahead.json", self.said[-1])


if __name__ == "__main__":
    unittest.main()
