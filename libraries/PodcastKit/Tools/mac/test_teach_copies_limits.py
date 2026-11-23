"""Tests for teach_copies.py, the second half: the limits, the exit codes of a set-up that is not
right, that nothing is sent but the episode's own address, and a real program on the command line.
The stand-ins are those of test_teach_copies.py.
Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import contextlib
import io
import json
import os
import re
import stat
import subprocess
import unittest

import probe_shows as probe
import teach_copies as tc
import teach_fetch as fetching
import teach_second
import teach_store as store
import teach_testing
import teach_truth
from test_teach_copies import ADDRESS, STRETCH, Base, sha


class LimitTests(Base):
    def test_max_stops_the_run_after_that_many_episodes_with_exit_3(self):
        for number in range(1, 6):
            self.add(number)
        self.assertEqual(self.go("--max", "2"), 3)
        self.assertEqual([c["address"] for c in self.net.calls], [ADDRESS % 1, ADDRESS % 2])
        self.assertIn("limit of 2 episodes", self.text())
        self.assertIn("3 are still waiting", self.text())

    def test_a_run_that_just_reaches_the_limit_with_nothing_waiting_is_exit_0(self):
        self.add(1)
        self.add(2)
        self.assertEqual(self.go("--max", "2"), 0)

    def test_a_failed_episode_counts_towards_max(self):
        for number in range(1, 5):
            self.add(number)
        self.net.fail = {ADDRESS % 1}
        self.assertEqual(self.go("--max", "2"), 3)
        self.assertEqual(len(self.net.calls), 2)

    def test_the_next_run_carries_on_where_the_limit_stopped_it(self):
        for number in range(1, 5):
            self.add(number)
        self.go("--max", "2")
        self.net.calls.clear()
        self.assertEqual(self.go("--max", "2"), 0)
        self.assertEqual([c["address"] for c in self.net.calls], [ADDRESS % 3, ADDRESS % 4])

    def test_max_gb_stops_before_a_download_that_would_go_over_it_with_exit_3(self):
        for number in range(1, 5):
            self.add(number)  # each is 1000 bytes
        self.assertEqual(self.go("--max-gb", "0.0000025"), 3)  # 2500 bytes
        self.assertEqual(len(self.net.calls), 2)
        self.assertEqual(self.net.calls[0]["max_bytes"], 2500)
        self.assertEqual(self.net.calls[1]["max_bytes"], 1500)
        self.assertIn("GB limit", self.text())
        self.assertIn("2 are still waiting", self.text())

    def test_a_file_that_would_go_over_the_budget_stops_the_run_and_is_not_a_failure(self):
        self.add(1)
        self.add(2)
        self.net.raises = {1: fetching.TooLarge("the file is bigger than 0 MB")}
        self.assertEqual(self.go("--max-gb", "0.0000025"), 3)
        self.assertEqual(len(self.net.calls), 1)
        self.assertNotIn("failed.json", self.names("copies"))

    def test_a_file_over_the_file_limit_with_a_big_budget_is_a_failure_of_that_episode(self):
        self.add(1)
        self.add(2)
        self.net.raises = {1: fetching.TooLarge("the file is bigger than 600 MB")}
        self.assertEqual(self.go(), 0)
        self.assertEqual(len(self.net.calls), 2)
        self.assertIn("1 failed", self.text())

    def test_the_defaults_are_40_episodes_and_3_gb(self):
        self.assertEqual((tc.MAX_EPISODES, tc.MAX_GB), (40, 3))
        for number in range(1, 43):
            self.add(number)
        self.assertEqual(self.go(), 3)
        self.assertEqual(len(self.net.calls), 40)
        self.assertEqual(self.net.calls[0]["max_bytes"], fetching.MAX_FILE)

    def test_the_run_pauses_between_downloads_but_not_before_the_first(self):
        for number in range(1, 4):
            self.add(number)
        self.go()
        self.assertEqual(self.pauses, [probe.PAUSE, probe.PAUSE])

    def test_bad_numbers_are_refused_before_anything_happens(self):
        self.add(1)
        for flag, value in (("--max", "0"), ("--max", "-1"), ("--max", "x"), ("--max-gb", "0"),
                            ("--max-gb", "-2"), ("--max-gb", "nan"), ("--max-gb", "inf"), ("--max-gb", "x")):
            with self.assertRaises(SystemExit) as caught, contextlib.redirect_stderr(io.StringIO()):
                self.go(flag, value)
            self.assertEqual(caught.exception.code, 2, flag + value)
        self.assertEqual(self.net.calls, [])


class FailureMemoryTests(Base):
    def failed(self):
        with open(self.folder.path("copies", "failed.json"), encoding="utf-8") as handle:
            return json.load(handle)["failed"]

    def test_three_episodes_in_a_row_that_never_failed_before_stop_the_run_with_exit_1(self):
        for number in range(1, 6):
            self.add(number)
        self.net.fail = {ADDRESS % n for n in range(1, 6)}
        self.assertEqual(self.go(), 1)
        self.assertEqual(len(self.net.calls), 3)
        self.assertIn("Stopping: 3 episodes in a row failed", self.text())

    def test_an_episode_that_failed_three_times_is_left_out_unless_asked_for(self):
        self.add(1)
        self.add(2)
        self.net.fail = {ADDRESS % 1}
        for _ in range(3):
            self.go()
        self.assertEqual(self.failed(), {"%012x" % 1: 3})
        self.net.calls.clear()
        self.said.clear()
        self.assertEqual(self.go(), 0)
        self.assertEqual(self.net.calls, [])
        self.assertIn("given up on after failing 3 times", self.text())
        self.assertEqual(self.go("--retry-failed"), 0)
        self.assertEqual([c["address"] for c in self.net.calls], [ADDRESS % 1])

    def test_episodes_that_never_failed_come_before_those_that_did(self):
        self.add(1)
        self.add(2)
        self.net.fail = {ADDRESS % 1}
        self.go("--max", "1")
        self.net.calls.clear()
        self.go("--max", "1")
        self.assertEqual([c["address"] for c in self.net.calls], [ADDRESS % 2])

    def test_a_success_clears_the_episodes_failures(self):
        self.add(1)
        self.net.fail = {ADDRESS % 1}
        self.go()
        self.net.fail = set()
        self.go()
        self.assertEqual(self.failed(), {})

    def test_a_damaged_failure_memory_is_ignored(self):
        self.add(1)
        os.makedirs(self.folder.path("copies"))
        with open(self.folder.path("copies", "failed.json"), "w") as handle:
            handle.write("{broken")
        self.assertEqual(self.go(), 0)
        self.assertEqual(self.truth(1), STRETCH)


class SetupTests(Base):
    def test_another_run_in_the_folder_is_refused_with_exit_2_and_nothing_is_fetched(self):
        self.add(1)
        with store.run_lock(self.folder.dir):
            self.assertEqual(self.go(), 2)
        self.assertEqual(self.net.calls, [])
        self.assertIn("Another teaching run is already working", self.text())

    def test_a_missing_or_unrunnable_tool_gives_2(self):
        self.add(1)
        self.tool_path = self.folder.path("nowhere")
        self.assertEqual(self.go(), 2)
        self.assertIn("missing or cannot be run", self.text())
        self.tool_path = self.folder.path("plain")
        with open(self.tool_path, "w") as handle:
            handle.write("x")
        os.chmod(self.tool_path, stat.S_IRUSR | stat.S_IWUSR)
        self.assertEqual(self.go(), 2)
        self.assertEqual(self.net.calls, [])

    def test_no_episode_list_gives_2_and_says_to_gather_first(self):
        self.assertEqual(self.go(), 2)
        self.assertIn("Gather the episodes first", self.text())

    def test_a_damaged_episode_list_gives_2_and_is_left_alone(self):
        with open(self.folder.path("episodes.json"), "w") as handle:
            handle.write("{broken")
        self.assertEqual(self.go(), 2)
        with open(self.folder.path("episodes.json")) as handle:
            self.assertEqual(handle.read(), "{broken")

    def test_a_folder_that_cannot_be_written_gives_2(self):
        self.add(1)
        with open(self.folder.path("copies"), "w") as handle:
            handle.write("a file where the folder should be")
        self.assertEqual(self.go(), 2)
        self.assertIn("Could not write", self.text())


class SendsNothingElseTests(Base):
    def test_only_the_episodes_own_address_is_asked_for_with_no_secret_header(self):
        self.add(1)
        seen = []

        def open_url(request, timeout=None):
            seen.append(request)
            return teach_testing.FakeResponse(b"different bytes " * 20)
        self.assertEqual(self.go(download=fetching.download, open_url=open_url), 0)
        self.assertEqual([r.full_url for r in seen], [ADDRESS % 1])
        self.assertEqual({k.lower() for k in seen[0].headers}, {"user-agent", "accept-encoding"})
        agent = seen[0].get_header("User-agent")
        self.assertEqual(agent, teach_second.SECOND_AGENT)
        self.assertNotEqual(agent, probe.USER_AGENT)

    def test_a_download_is_only_ever_of_a_listed_episodes_address(self):
        for number in (1, 2, 3):
            self.add(number)
        self.go()
        self.assertEqual({c["address"] for c in self.net.calls}, {e["address"] for e in self.entries})


class StandInProgramTests(Base):
    """A real program on the command line, built like podcast-ads --truth-from-copies: it reads the
    two paths, writes the truth lines to its standard output and its own file beside the first path
    (and refuses when that file is there), and fails the way the Swift tool does."""
    PROGRAM = """#!/bin/bash
[ "$1" = "--truth-from-copies" ] || { echo "usage" >&2; exit 2; }
if cmp -s "$2" "$3"; then echo "These are the same file twice. Choose two different files." >&2; exit 1; fi
echo "# Ads marked from the differences between two downloads of one episode."
if grep -q "differs" "$3"; then
  [ -e "$2.truth.txt" ] && { echo "$2.truth.txt is already there." >&2; exit 1; }
  echo "0:33.480 1:02.120"
  echo "0:33.480 1:02.120" > "$2.truth.txt"
  exit 0
fi
echo "# The two files have no frame in common, so they are not two downloads of one episode"
echo "No stretch was marked, so no file was written." >&2
exit 1
"""

    def setUp(self):
        super().setUp()
        with open(self.tool_path, "w") as handle:
            handle.write(self.PROGRAM)

    def fetch(self, address, path, **more):
        number = int(re.search(r"/(\d+)\.mp3", address).group(1))
        data = b"second differs %d" % number if number != 3 else b"unrelated"
        with open(path, "wb") as handle:
            handle.write(data)
        return {"bytes": len(data), "sha256": sha(data), "host": "h"}

    def test_the_real_command_line_gives_a_truth_file_and_litters_nothing(self):
        for number in (1, 2, 3):
            self.add(number)
        self.assertEqual(self.go(download=self.fetch, runner=subprocess.run), 0, self.text())
        self.assertEqual(teach_truth.read_truth(self.truth(1)), [(33.48, 62.12)])
        self.assertEqual(teach_truth.read_truth(self.truth(3)), [])
        self.assertEqual(self.names("copies"), ["%012x.truth.txt" % n for n in (1, 2, 3)])
        self.assertEqual(self.names("audio"), ["%012x.mp3" % n for n in (1, 2, 3)])

    def test_it_runs_again_without_the_tools_own_file_getting_in_the_way(self):
        self.add(1)
        self.go(download=self.fetch, runner=subprocess.run)
        os.remove(self.folder.path("copies", "%012x.truth.txt" % 1))
        self.assertEqual(self.go(download=self.fetch, runner=subprocess.run), 0)
        self.assertEqual(teach_truth.read_truth(self.truth(1)), [(33.48, 62.12)])


if __name__ == "__main__":
    unittest.main()
