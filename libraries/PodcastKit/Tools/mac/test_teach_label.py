"""Tests for teach_label.py: marking one episode, the whole run (the cost cap, the memory of failures)
with a fake claude. No network, no real claude, no sleeping.
Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import json
import os
import unittest

import teach_claude as claude
import teach_label as label
import teach_segments as seg
from teach_testing import Teaching, answer, entry, transcript


# MARK: label_episode

class LabelEpisodeTests(unittest.TestCase):
    def lines(self, count):
        return seg.read_transcript(transcript(count))

    def test_the_length_is_the_episode_seconds_when_known(self):
        ask = lambda prompt: {"text": answer((2, 4)), "cost": 0.1}
        known = dict(entry(1), seconds=600)
        self.assertEqual(label.label_episode(known, self.lines(10), "m", ask)["length"], 600)
        for seconds in (None, 0, -1):
            odd = dict(entry(1), seconds=seconds)
            self.assertEqual(label.label_episode(odd, self.lines(10), "m", ask)["length"], 9.0)

    def test_one_part(self):
        asked = []

        def ask(prompt):
            asked.append(prompt)
            return {"text": answer((2, 4)), "cost": 0.1}

        result = label.label_episode(entry(1), self.lines(10), "m1", ask, now=lambda: 5.0)
        self.assertEqual(len(asked), 1)
        self.assertEqual((result["version"], result["prompt"], result["model"]), (1, "t1", "m1"))
        self.assertEqual((result["episode"], result["feed"], result["show"]),
                         ("000000000001", "https://feed/1", "Show"))
        self.assertEqual((result["lines"], result["length"]), (10, 9.0))
        self.assertEqual(result["segments"][0]["start"], 1.0)
        self.assertEqual(result["segments"][0]["end"], 4.0)
        self.assertEqual((result["dropped"], result["cost"], result["writtenAt"]), (0, 0.1, 5000))

    def test_two_parts_join_a_stretch_split_at_the_boundary(self):
        # Each line's text is 6 to 7 characters, so a limit of 20 gives about three lines a part.
        lines = self.lines(6)
        ranges = seg.parts(lines, 20)
        self.assertEqual(len(ranges), 2)
        first_part, second_part = ranges
        replies = [answer((first_part[1] - 1, first_part[1])),
                   answer((second_part[0], second_part[0] + 1))]
        prompts = []

        def ask(prompt):
            prompts.append(prompt)
            return {"text": replies[len(prompts) - 1], "cost": 0.2}

        result = label.label_episode(entry(1), lines, "m", ask, limit=20)
        self.assertEqual(len(prompts), 2)
        self.assertIn("lines %d to %d of 6" % second_part, prompts[1])
        self.assertEqual(len(result["segments"]), 1)
        self.assertEqual((result["segments"][0]["first"], result["segments"][0]["last"]),
                         (first_part[1] - 1, second_part[0] + 1))
        self.assertAlmostEqual(result["cost"], 0.4)

    def test_a_bad_answer_is_asked_for_once_more(self):
        replies = ["no json at all", answer((1, 2))]
        asked = []

        def ask(prompt):
            asked.append(prompt)
            return {"text": replies[len(asked) - 1], "cost": 0.1}

        result = label.label_episode(entry(1), self.lines(5), "m", ask)
        self.assertEqual(len(asked), 2)
        self.assertEqual(len(result["segments"]), 1)
        self.assertAlmostEqual(result["cost"], 0.2)

    def test_two_bad_answers_raise(self):
        with self.assertRaises(ValueError):
            label.label_episode(entry(1), self.lines(5), "m",
                                lambda prompt: {"text": "nope", "cost": 0.0})


# MARK: run

class RunHelpers:
    """What the tests of a run share: a fake ask and a way to go through run()."""

    def fake_ask(self, cost=0.1, text=None, log=None):
        def ask(prompt):
            if log is not None:
                log.append(prompt)
            return {"text": text or answer((1, 2)), "cost": cost}
        return ask

    def go(self, teaching, ask, **options):
        said = []
        settings = {"labels": "labels", "model": "m", "limit": None, "cap": None}
        settings.update(options)
        result = label.run(teaching.dir, settings["labels"], settings["model"], settings["limit"],
                           settings["cap"], ask, say=said.append,
                           retry_failed=settings.get("retry_failed", False))
        return result, said


class RunTests(RunHelpers, unittest.TestCase):
    def test_writes_a_label_per_episode_and_reports(self):
        teaching = Teaching(self, 2)
        result, said = self.go(teaching, self.fake_ask())
        self.assertEqual(teaching.labels(), [e["id"] + ".json" for e in teaching.entries])
        with open(teaching.label_path(teaching.entries[0])) as f:
            self.assertEqual(json.load(f)["episode"], teaching.entries[0]["id"])
        self.assertEqual(result["done"], 2)
        self.assertIsNone(result["stop"])
        self.assertIn("1 of 2", said[0])
        self.assertIn("Episode 1", said[0])
        self.assertIn("1 sponsor", said[0])
        self.assertIn("$0.10", said[0])
        self.assertIn("$0.20", said[1])

    def test_no_temporary_files_are_left(self):
        teaching = Teaching(self, 1)
        self.go(teaching, self.fake_ask())
        self.assertTrue(all(name.endswith(".json") for name in teaching.labels()))

    def test_resumes_without_asking_again(self):
        teaching = Teaching(self, 3)
        self.go(teaching, self.fake_ask(), limit=2)
        log = []
        result, _ = self.go(teaching, self.fake_ask(log=log))
        self.assertEqual((len(log), result["done"]), (1, 1))
        self.assertEqual(len(teaching.labels()), 3)

    def test_a_second_labels_folder_is_independent(self):
        teaching = Teaching(self, 1)
        self.go(teaching, self.fake_ask())
        log = []
        self.go(teaching, self.fake_ask(log=log), labels="other")
        self.assertEqual(len(log), 1)
        self.assertEqual(len(teaching.labels("other")), 1)

    def test_episodes_without_a_transcript_are_not_waiting(self):
        teaching = Teaching(self, 2)
        os.remove(os.path.join(teaching.dir, "transcripts", teaching.entries[0]["id"] + ".txt"))
        log = []
        self.go(teaching, self.fake_ask(log=log))
        self.assertEqual(len(log), 1)

    def test_a_transcript_without_lines_is_skipped_with_one_line(self):
        teaching = Teaching(self, 2)
        teaching.write_transcript(teaching.entries[0], "nothing usable\n")
        result, said = self.go(teaching, self.fake_ask())
        self.assertEqual(result["done"], 1)
        self.assertEqual(len([s for s in said if "no usable lines" in s]), 1)

    def test_limit(self):
        teaching = Teaching(self, 3)
        result, _ = self.go(teaching, self.fake_ask(), limit=2)
        self.assertEqual((result["done"], result["stop"]), (2, "limit"))
        self.assertEqual(len(teaching.labels()), 2)

    def test_cap(self):
        teaching = Teaching(self, 4)
        result, said = self.go(teaching, self.fake_ask(cost=0.5), cap=1.0)
        self.assertEqual((result["done"], result["stop"]), (2, "cap"))
        self.assertIn("$1.00", said[-1])

    def test_usage_limit_stops_at_once_and_keeps_the_work(self):
        teaching = Teaching(self, 4)
        calls = []

        def ask(prompt):
            calls.append(prompt)
            if len(calls) == 3:
                raise claude.UsageLimit("usage limit reached")
            return {"text": answer((1, 2)), "cost": 0.1}

        result, said = self.go(teaching, ask)
        self.assertEqual((result["done"], result["stop"]), (2, "usage"))
        self.assertEqual(len(calls), 3)
        self.assertEqual(len(teaching.labels()), 2)

    def test_three_failures_in_a_row_stop(self):
        teaching = Teaching(self, 6)

        def ask(prompt):
            raise RuntimeError("broken")

        result, _ = self.go(teaching, ask)
        self.assertEqual((result["done"], result["failed"], result["stop"]), (0, 3, "failures"))

    def test_a_success_resets_the_failure_count(self):
        teaching = Teaching(self, 6)
        calls = []

        def ask(prompt):
            calls.append(prompt)
            if len(calls) in (1, 2, 4, 5):
                raise RuntimeError("broken")
            return {"text": answer((1, 2)), "cost": 0.0}

        result, _ = self.go(teaching, ask)
        self.assertEqual((result["done"], result["failed"], result["stop"]), (2, 4, None))


if __name__ == "__main__":
    unittest.main()
