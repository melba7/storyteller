"""Tests for teach_copies.py: which episodes get a second download, the truth file it keeps, and the
second copy being gone afterwards (also after a failure or a stop). A stand-in download and a
stand-in podcast-ads are used, so no network and no Swift. The limits, the set-up and what is sent
are in test_teach_copies_limits.py. Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import hashlib
import json
import os
import re
import subprocess
import unittest
from types import SimpleNamespace

import teach_copies as tc
import teach_fetch as fetching
import teach_testing
import teach_truth

HEADER = "# Ads marked from the differences between two downloads of one episode.\n"
STRETCH = HEADER + "0:33.480 1:02.120\n"
NO_FRAME = HEADER + "# The two files have no frame in common, so they are not two downloads of one episode\n"
ADDRESS = "https://a/%d.mp3"


def sha(data):
    return hashlib.sha256(data).hexdigest()


class Net:
    """Stands in for teach_fetch.download: writes the bytes for an address, or fails for it."""

    def __init__(self, copies, same=(), fail=(), raises=None):
        self.copies, self.same, self.fail, self.raises = copies, set(same), set(fail), raises
        self.calls, self.saw = [], []

    def __call__(self, address, path, open_url=None, max_bytes=None, **more):
        self.calls.append({"address": address, "path": path, "max_bytes": max_bytes, "open_url": open_url})
        self.saw.append(sorted(os.listdir(self.copies)))
        number = int(re.search(r"/(\d+)\.mp3", address).group(1))
        if address in self.fail:
            raise OSError("the server stopped early")
        if isinstance(self.raises, dict) and number in self.raises:
            raise self.raises[number]
        data = b"first %d" % number if address in self.same else (b"second %d " % number).ljust(1000, b"x")
        with open(path, "wb") as handle:
            handle.write(data)
        return {"bytes": len(data), "sha256": sha(data), "host": "cdn.example.com"}


class Tool:
    """Stands in for subprocess.run on podcast-ads: answers by episode number."""

    def __init__(self, answers=None, raises=None):
        self.answers, self.raises, self.calls, self.options, self.saw = answers or {}, raises, [], [], []

    def __call__(self, command, **options):
        self.calls.append(command)
        self.options.append(options)
        first, second = command[2], command[3]
        self.saw.append({"link": os.path.islink(first), "second": os.path.exists(second),
                         "beside_first": sorted(os.listdir(os.path.dirname(first)))})
        if self.raises:
            raise self.raises
        number = int(os.path.basename(first)[:12], 16)
        text, code, error = self.answers.get(number, (STRETCH, 0, ""))
        return SimpleNamespace(returncode=code, stdout=text, stderr=error)


class Base(unittest.TestCase):
    def setUp(self):
        self.folder = teach_testing.Folder(self)
        self.entries = []
        self.said = []
        self.tool_path = self.folder.path("podcast-ads")
        with open(self.tool_path, "w") as handle:
            handle.write("#!/bin/bash\nexit 0\n")
        os.chmod(self.tool_path, 0o755)
        self.net = Net(self.folder.path("copies"))
        self.tool = Tool()
        self.pauses = []

    def add(self, number, label=True, audio=True, extension="mp3", on_disk=True):
        item = teach_testing.entry(number, audio=audio, address=ADDRESS % number)
        if audio:
            item["file"] = "audio/%s.%s" % (item["id"], extension)
            item["sha256"] = sha(b"first %d" % number)
            if on_disk:
                os.makedirs(self.folder.path("audio"), exist_ok=True)
                with open(self.folder.path(item["file"]), "wb") as handle:
                    handle.write(b"first %d" % number)
        if label:
            os.makedirs(self.folder.path("labels"), exist_ok=True)
            with open(self.folder.path("labels", item["id"] + ".json"), "w") as handle:
                json.dump({"segments": []}, handle)
        self.entries.append(item)
        self.folder.write_manifest(self.entries)
        return item

    def go(self, *extra, **more):
        more.setdefault("download", self.net)
        more.setdefault("runner", self.tool)
        return tc.main(["--folder", self.folder.dir, "--tool", self.tool_path] + list(extra),
                       sleep=self.pauses.append, say=self.said.append, **more)

    def text(self):
        return "\n".join(self.said)

    def names(self, *parts):
        path = self.folder.path(*parts)
        return sorted(os.listdir(path)) if os.path.isdir(path) else []

    def truth(self, number):
        with open(self.folder.path("copies", "%012x.truth.txt" % number), encoding="utf-8") as handle:
            return handle.read()


class ComparingTests(Base):
    def test_a_marked_episode_gets_a_truth_file_and_loses_its_second_copy(self):
        self.add(1)
        self.assertEqual(self.go(), 0, self.text())
        self.assertEqual(self.truth(1), STRETCH)
        self.assertEqual(self.names("copies"), ["%012x.truth.txt" % 1])
        self.assertEqual(self.net.saw, [[]])  # the copy folder was empty when the download began
        self.assertTrue(self.tool.saw[0]["second"])
        self.assertIn("1 episode", self.text())

    def test_the_tool_gets_a_link_to_the_audio_so_nothing_is_written_beside_the_audio(self):
        item = self.add(1)
        self.go()
        tool, mode, first, second = self.tool.calls[0]
        self.assertEqual((tool, mode), (self.tool_path, "--truth-from-copies"))
        self.assertTrue(self.tool.saw[0]["link"])
        self.assertEqual(os.path.dirname(first), self.folder.path("copies"))
        self.assertEqual(second, self.net.calls[0]["path"])
        self.assertEqual(self.names("audio"), [os.path.basename(item["file"])])
        with open(self.folder.path(item["file"]), "rb") as handle:
            self.assertEqual(handle.read(), b"first 1")

    def test_the_tool_is_run_with_no_environment_of_its_own_and_a_time_limit(self):
        self.add(1)
        self.go()
        self.assertEqual(sorted(self.tool.options[0]), ["stderr", "stdout", "text", "timeout"])
        self.assertGreater(self.tool.options[0]["timeout"], 0)

    def test_only_marked_episodes_with_mp3_audio_on_disk_are_fetched(self):
        self.add(1)
        self.add(2, label=False)
        self.add(3, audio=False)
        self.add(4, on_disk=False)
        self.add(5, extension="m4a")
        self.assertEqual(self.go(), 0)
        self.assertEqual([c["address"] for c in self.net.calls], [ADDRESS % 1])
        self.assertIn("1 is not an MP3", self.text())

    def test_an_episode_that_was_compared_is_not_fetched_again(self):
        self.add(1)
        self.go()
        self.said.clear()
        self.assertEqual(self.go(), 0)
        self.assertEqual(len(self.net.calls), 1)
        self.assertIn("Nothing to do", self.text())
        self.assertIn("1 episode was compared before", self.text())

    def test_no_marked_episode_is_nothing_to_do_and_exit_0(self):
        self.add(1, label=False)
        self.assertEqual(self.go(), 0)
        self.assertEqual(self.net.calls, [])
        self.assertIn("No marked episode", self.text())

    def test_the_same_file_twice_runs_no_tool_and_says_nothing_is_learned(self):
        self.add(1)
        self.net.same = {ADDRESS % 1}
        self.assertEqual(self.go(), 0)
        self.assertEqual(self.tool.calls, [])
        self.assertEqual(teach_truth.read_truth(self.truth(1)), [])
        self.assertIn("same file", self.text())
        self.assertIn("nothing is learned", self.text())
        self.assertEqual(self.names("copies"), ["%012x.truth.txt" % 1])

    def test_two_downloads_with_no_differing_stretch_are_not_a_failure(self):
        self.add(1)
        self.tool.answers = {1: (HEADER, 1, "No stretch was marked, so no file was written.\n")}
        self.assertEqual(self.go(), 0)
        self.assertEqual(teach_truth.read_truth(self.truth(1)), [])
        self.assertIn("same ads", self.text())
        self.assertIn("nothing is learned", self.text())
        self.assertNotIn("failed.json", self.names("copies"))
        self.assertIn("1 got the same ads", self.text())

    def test_a_host_that_makes_a_new_file_every_time_is_said(self):
        self.add(1)
        self.tool.answers = {1: (NO_FRAME, 1, "")}
        self.go()
        self.assertIn("no frame in common", self.text())

    def test_the_figures_at_the_end(self):
        for number in (1, 2, 3):
            self.add(number)
        self.tool.answers = {2: (HEADER, 1, "")}
        self.go()
        self.assertIn("3 episodes compared: 2 with differing stretches (2 in all), 1 got the same ads", self.text())

    def test_the_truth_file_is_kept_as_the_tool_printed_it_and_can_be_read_by_snap(self):
        self.add(1)
        self.tool.answers = {1: (STRETCH + "# Left out: 0:10.000 to 0:10.500 differs but is under 1 s long.\n", 0, "")}
        self.go()
        self.assertEqual(teach_truth.read_truth(self.truth(1)), [(33.48, 62.12)])


class FailureTests(Base):
    def failed(self):
        with open(self.folder.path("copies", "failed.json"), encoding="utf-8") as handle:
            return json.load(handle)["failed"]

    def gone(self):
        self.assertEqual([n for n in self.names("copies") if "second" in n or "first" in n or n.endswith(".part")], [])

    def test_a_tool_that_fails_leaves_no_truth_file_and_the_failure_is_counted(self):
        self.add(1)
        self.tool.answers = {1: ("", 1, "No MP3 frames in %012x.second.mp3\n" % 1)}
        self.assertEqual(self.go(), 0)
        self.assertNotIn("%012x.truth.txt" % 1, self.names("copies"))
        self.assertEqual(self.failed(), {"%012x" % 1: 1})
        self.assertIn("No MP3 frames", self.text())
        self.assertIn("1 failed", self.text())
        self.gone()

    def test_a_tool_that_cannot_be_started_is_a_failure_and_leaves_nothing(self):
        self.add(1)
        self.tool.raises = OSError("not allowed")
        self.assertEqual(self.go(), 0)
        self.assertIn("not allowed", self.text())
        self.gone()

    def test_a_tool_that_runs_too_long_is_a_failure_and_leaves_nothing(self):
        self.add(1)
        self.tool.raises = subprocess.TimeoutExpired("podcast-ads", 600)
        self.assertEqual(self.go(), 0)
        self.assertIn("took more than", self.text())
        self.gone()

    def test_an_answer_that_is_not_a_truth_file_is_a_failure(self):
        self.add(1)
        self.tool.answers = {1: ("hello there\n", 0, "")}
        self.go()
        self.assertNotIn("%012x.truth.txt" % 1, self.names("copies"))
        self.assertEqual(self.failed(), {"%012x" % 1: 1})
        self.gone()

    def test_a_download_that_fails_is_a_failure_and_leaves_nothing(self):
        self.add(1)
        self.net.fail = {ADDRESS % 1}
        self.assertEqual(self.go(), 0)
        self.assertEqual(self.tool.calls, [])
        self.assertIn("did not download", self.text())
        self.assertEqual(self.failed(), {"%012x" % 1: 1})
        self.gone()

    def test_a_download_the_server_cuts_short_leaves_no_part_file(self):
        self.add(1)
        cut = lambda request, timeout=None: teach_testing.ShortResponse(b"abc", 100)
        self.assertEqual(self.go(download=fetching.download, open_url=cut), 0)
        self.assertEqual(self.names("copies"), ["failed.json"])

    def test_a_stop_by_the_user_deletes_the_second_copy_and_keeps_what_was_done(self):
        self.add(1)
        self.add(2)
        self.net.raises = {2: KeyboardInterrupt()}
        self.assertEqual(self.go(), 130)
        self.assertEqual(self.names("copies"), ["%012x.truth.txt" % 1])
        self.assertIn("Stopped", self.text())

    def test_a_stop_while_the_tool_runs_deletes_both_files(self):
        self.add(1)
        self.tool.raises = KeyboardInterrupt()
        self.assertEqual(self.go(), 130)
        self.assertEqual(self.names("copies"), [])

    def test_a_stop_is_not_counted_as_a_failure(self):
        self.add(1)
        self.net.raises = {1: KeyboardInterrupt()}
        self.go()
        self.assertNotIn("failed.json", self.names("copies"))

    def test_what_a_killed_run_left_behind_is_removed_at_the_start(self):
        os.makedirs(self.folder.path("copies"))
        for name in ("%012x.second.mp3" % 9, "%012x.second.mp3.part" % 9, "%012x.first.mp3.truth.txt" % 9):
            with open(self.folder.path("copies", name), "w") as handle:
                handle.write("x")
        os.symlink(self.folder.path("nowhere"), self.folder.path("copies", "%012x.first.mp3" % 9))
        with open(self.folder.path("copies", "%012x.truth.txt" % 9), "w") as handle:
            handle.write(HEADER)
        self.add(1)
        self.go()
        self.assertEqual(self.names("copies"), ["%012x.truth.txt" % 1, "%012x.truth.txt" % 9])


if __name__ == "__main__":
    unittest.main()
