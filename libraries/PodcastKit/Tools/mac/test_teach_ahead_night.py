"""A whole night of the read-ahead, end to end, with fakes in place of the network, the transcriber
and Claude: the phone's list, the pick, the download, the writing down, the marking under a weekly
budget, ahead-ads.json and its copy to two folders. It shows that an episode already marked is not
marked twice, that the weekly cap stops the marking before the call that would pass it, and that the
published file has the format the phone reads. Nothing is sent anywhere and nothing costs money.
Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import json
import os
import shutil
import tempfile
import time
import unittest

import teach_ahead as night
import teach_collect as collect
import teach_label as label
import teach_publish as publish
import teach_transcribe as transcribe
from teach_testing import FakeRunner, answer, printed

BUDGET = "ahead-2026-W48"
TRANSCRIPT = "".join("[00:%02d:00.0] line %d of the show goes here\n" % (n, n) for n in range(1, 7))


def queued(number):
    return {"feed": "https://phone.example/feed%d.xml" % number, "guid": "guid-%d" % number,
            "title": "Episode %d" % number, "show": "Show %d" % number,
            "audio": "https://cdn.example/%d.mp3" % number, "reason": "upNext", "rank": number - 1}


class NightTests(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.root, True)
        self.folder = os.path.join(self.root, "teaching")
        self.mac = os.path.join(self.root, "LofiMusic")
        self.icloud = os.path.join(self.root, "iCloud", "LofiMusic")
        for name in (self.mac, self.icloud, os.path.join(self.icloud, "Podcasts")):
            os.makedirs(name, exist_ok=True)
        bin_folder = os.path.join(self.root, "bin")
        os.makedirs(bin_folder)
        for name in ("claude", "podcast-transcribe"):
            with open(os.path.join(bin_folder, name), "w") as f:
                f.write("#!/bin/sh\n")
            os.chmod(os.path.join(bin_folder, name), 0o755)
        self.transcriber = os.path.join(bin_folder, "podcast-transcribe")
        self.environment = {"HOME": self.root, "PATH": bin_folder}
        self.said, self.downloads, self.claude = [], [], FakeRunner(stdout=printed(answer((2, 3)), cost=0.25))
        self.now = int(time.time())  # the labels are stamped with the real time

    def queue(self, numbers):
        with open(os.path.join(self.icloud, "Podcasts", "phone-queue.json"), "w") as f:
            json.dump({"version": 1, "writtenAt": 1, "episodes": [queued(n) for n in numbers]}, f)

    def download(self, address, path, **more):
        self.downloads.append(address)
        with open(path, "wb") as f:
            f.write(b"x" * 50)
        return {"bytes": 50, "sha256": "ab" * 32, "host": "cdn.example"}

    def write_down(self, command, **more):
        def runner(args, **options):
            options["stdout"].write(TRANSCRIPT)
            return type("Done", (), {"returncode": 0, "stderr": ""})()
        return transcribe.main(command, runner=runner, say=self.said.append)

    def night(self, numbers, cap="10", estimate="0.19"):
        """One night: every step in the order of teach-ahead.sh. Returns the exit codes."""
        self.queue(numbers)
        codes = {}
        codes["pick"] = night.main(["pick", "--folder", self.folder, "--budget", BUDGET, "--cap", cap,
                                    "--estimate", estimate], say=self.said.append,
                                   defaults=lambda: [self.mac, self.icloud], now=lambda: 1_800_000_000,
                                   load_shows=lambda path: [])
        if codes["pick"] != 0:
            return codes
        codes["download"] = collect.main(["--folder", self.folder, "--only-ahead", "--keep-free-gb", "0"],
                                         download=self.download, sleep=lambda s: None, say=self.said.append)
        codes["write down"] = self.write_down(["--folder", self.folder, "--tool", self.transcriber,
                                               "--only-ahead"])
        codes["mark"] = label.main(["--folder", self.folder, "--yes", "--only-ahead", "--limit", "8",
                                    "--budget", BUDGET, "--cap", cap, "--reserve", estimate],
                                   runner=self.claude, environment=self.environment, say=self.said.append,
                                   extra_folders=())
        codes["write"] = night.main(["write", "--folder", self.folder], say=self.said.append,
                                    now=lambda: self.now + 100)
        codes["publish"] = publish.main(["--folder", self.folder, "--to", self.mac, "--to", self.icloud],
                                        say=self.said.append)
        return codes

    def published(self, folder):
        with open(os.path.join(folder, "Podcasts", "ahead-ads.json"), encoding="utf-8") as f:
            return json.load(f)

    def test_a_night_ends_with_the_marks_in_both_folders_in_the_agreed_format(self):
        codes = self.night([1, 2, 3])
        self.assertEqual(set(codes.values()), {0}, (codes, self.said))
        self.assertEqual(self.downloads, ["https://cdn.example/%d.mp3" % n for n in (1, 2, 3)])
        self.assertEqual(len(self.claude.calls), 3)
        for folder in (self.mac, self.icloud):
            found = self.published(folder)
            self.assertEqual(list(found), ["version", "writtenAt", "episodes"])
            self.assertEqual((found["version"], found["writtenAt"]), (1, self.now + 100))
            self.assertEqual([e["guid"] for e in found["episodes"]], ["guid-1", "guid-2", "guid-3"])
            first = found["episodes"][0]
            self.assertEqual(list(first), ["feed", "guid", "title", "marked", "ads"])
            self.assertEqual(first["feed"], "https://phone.example/feed1.xml")
            self.assertEqual(first["ads"], [{
                "kind": "ad", "confidence": "high", "start": 120.0, "end": 240.0,
                "startWords": "line 2 of the show goes here line 3 of the show goes here",
                "endWords": "line 2 of the show goes here line 3 of the show goes here"}])
        with open(os.path.join(self.icloud, "Podcasts", "teaching.json")) as f:
            self.assertIn("ahead-ads.json", json.load(f)["files"])

    def test_the_marked_episodes_join_the_teaching_set_with_their_labels_and_stay_off_the_shelf(self):
        self.night([1, 2])
        with open(os.path.join(self.folder, "episodes.json")) as f:
            entries = json.load(f)["episodes"]
        self.assertEqual(len(entries), 2)
        for one in entries:
            self.assertTrue(one["file"] and os.path.exists(os.path.join(self.folder, one["file"])))
            self.assertTrue(os.path.exists(os.path.join(self.folder, "labels", one["id"] + ".json")))
            self.assertTrue(os.path.exists(os.path.join(self.folder, "transcripts", one["id"] + ".txt")))
        with open(os.path.join(self.folder, "ahead.json")) as f:
            self.assertEqual({e["id"] for e in json.load(f)["episodes"]}, {e["id"] for e in entries})

    def test_a_second_night_with_the_same_list_marks_and_downloads_nothing_again(self):
        self.night([1, 2, 3])
        calls, downloads = len(self.claude.calls), len(self.downloads)
        codes = self.night([1, 2, 3])
        self.assertEqual(codes, {"pick": 3})
        self.assertEqual((len(self.claude.calls), len(self.downloads)), (calls, downloads))

    def test_a_new_episode_on_the_second_night_is_the_only_one_marked(self):
        self.night([1, 2])
        self.night([1, 2, 3])
        self.assertEqual(len(self.claude.calls), 3)
        self.assertEqual([e["guid"] for e in self.published(self.icloud)["episodes"]],
                         ["guid-1", "guid-2", "guid-3"])

    def test_the_weekly_cap_stops_before_the_call_that_would_pass_it(self):
        # $0.90 a week and $0.19 expected: four episodes fit by the estimate, but each call really
        # costs $0.25, so after three ($0.75) the next call is expected to make $0.94 and does not run.
        codes = self.night([1, 2, 3, 4, 5, 6], cap="0.9", estimate="0.19")
        self.assertEqual(codes["pick"], 0)
        self.assertEqual(len(self.claude.calls), 3)
        with open(os.path.join(self.folder, "marking-spend.json")) as f:
            spent = json.load(f)["budgets"][BUDGET]
        self.assertEqual(spent, {"dollars": 0.75, "episodes": 3})
        self.assertEqual(codes["mark"], label.CAP_REACHED)
        self.assertIn("would pass the cap", "\n".join(self.said))
        self.assertEqual(len(self.published(self.icloud)["episodes"]), 3)

    def test_the_cap_is_for_the_week_so_the_next_night_has_no_room(self):
        self.night([1, 2, 3, 4, 5, 6], cap="0.9", estimate="0.19")
        calls = len(self.claude.calls)
        codes = self.night([1, 2, 3, 4, 5, 6, 7, 8], cap="0.9", estimate="0.19")
        self.assertEqual(codes, {"pick": 3})  # $0.75 spent: not even one more episode fits
        self.assertEqual(len(self.claude.calls), calls)

    def test_an_episode_that_cannot_be_downloaded_is_skipped_and_the_night_goes_on(self):
        original = self.download

        def flaky(address, path, **more):
            if address.endswith("/2.mp3"):
                raise OSError("no route to host")
            return original(address, path, **more)
        self.download = flaky
        codes = self.night([1, 2, 3])
        self.assertEqual(set(codes.values()), {0}, (codes, self.said))
        self.assertEqual([e["guid"] for e in self.published(self.icloud)["episodes"]], ["guid-1", "guid-3"])
        self.assertTrue(any("did not download" in line for line in self.said))

    def test_an_episode_that_fails_to_mark_is_skipped_and_the_night_goes_on(self):
        good = FakeRunner(stdout=printed(answer((2, 3)), cost=0.25))
        calls = []

        def runner(args, **options):
            calls.append(args)
            if "Episode: Episode 1\n" in options["input"]:
                return FakeRunner(stdout="junk", returncode=1)(args, **options)
            return good(args, **options)
        runner.calls = calls
        self.claude = runner
        codes = self.night([1, 2])
        self.assertEqual(codes["mark"], 0)
        self.assertEqual([e["guid"] for e in self.published(self.icloud)["episodes"]], ["guid-2"])

    def test_no_audio_means_nothing_is_ready(self):
        self.queue([1])
        night.main(["pick", "--folder", self.folder, "--budget", BUDGET], say=self.said.append,
                   defaults=lambda: [self.mac, self.icloud], now=lambda: 5, load_shows=lambda path: [])
        self.said.clear()
        self.assertEqual(night.main(["ready", "--folder", self.folder], say=self.said.append), 3)

    def test_a_night_with_no_list_from_the_phone_does_nothing_at_all(self):
        codes = night.main(["pick", "--folder", self.folder, "--budget", BUDGET], say=self.said.append,
                           defaults=lambda: [self.mac, self.icloud], now=lambda: 5, load_shows=lambda path: [])
        self.assertEqual(codes, 3)
        self.assertEqual((os.listdir(self.folder) if os.path.isdir(self.folder) else []), [])
        self.assertEqual((self.downloads, self.claude.calls), ([], []))


if __name__ == "__main__":
    unittest.main()
