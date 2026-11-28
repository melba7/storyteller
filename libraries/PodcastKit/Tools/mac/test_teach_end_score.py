"""Tests for teach_end_score.py: Claude's own label edges against the stretches where two downloads of an
episode differ, with a label's end taken from the next line (before) and from its last word (after).
Made-up transcripts, labels and truth files only. Run: python3 -m unittest discover -s
libraries/PodcastKit/Tools/mac"""
import json
import os
import unittest

import teach_end_score as score
import teach_testing as testing


def transcript_of_five_second_lines(count=120):
    """Line n (from 1) starts at (n - 1) * 5 seconds."""
    return "".join("[%02d:%02d:%02d.0] line %d\n" % (n * 5 // 3600, n * 5 // 60 % 60, n * 5 % 60, n + 1)
                   for n in range(count))


def label(first, last, start, end):
    return {"first": first, "last": last, "sort": "sponsor", "who": "Acme", "delivery": "host",
            "confidence": "high", "why": "x", "start": start, "end": end}


class Base(unittest.TestCase):
    def setUp(self):
        self.teaching = testing.Folder(self)
        os.makedirs(self.teaching.path("labels"))
        os.makedirs(self.teaching.path("transcripts"))
        os.makedirs(self.teaching.path("copies"))
        self.said = []

    def episode(self, number, segments, truth, ends=None, lines=transcript_of_five_second_lines()):
        """Writes the label, the truth and the transcript of episode `number`; `ends` is {line number:
        exact end} for a side file."""
        identifier = "%012x" % number
        with open(self.teaching.path("transcripts", identifier + ".txt"), "w") as handle:
            handle.write(lines)
        with open(self.teaching.path("labels", identifier + ".json"), "w") as handle:
            json.dump({"version": 1, "episode": identifier, "segments": segments}, handle)
        with open(self.teaching.path("copies", identifier + ".truth.txt"), "w") as handle:
            handle.write("# made up\n" + "".join("%s %s\n" % pair for pair in truth))
        if ends is not None:
            count = len(lines.splitlines())
            pairs = [[n * 5.0, ends.get(n + 1, n * 5.0 + 4.0)] for n in range(count)]
            with open(self.teaching.path("transcripts", identifier + ".words.json"), "w") as handle:
                json.dump({"version": 1, "duration": 600.0, "lines": pairs, "words": []}, handle)
        return identifier

    def run_score(self, **options):
        return score.score(self.teaching.dir, **options)


class ScoreTests(Base):
    def test_a_label_end_from_the_last_word_is_closer_than_one_from_the_next_line(self):
        # Lines 3 and 4 are marked: 10.0 to 20.0 by the next line. The ad really ends at 17.4.
        self.episode(1, [label(3, 4, 10.0, 20.0)], [("0:10.000", "0:17.400")], ends={4: 17.3})
        report = self.run_score()
        self.assertEqual(report["stretches"]["marked"], 1)
        self.assertEqual(report["starts"]["within1"], 1)
        self.assertEqual((report["endsBefore"]["within1"], report["endsBefore"]["within2"],
                          report["endsBefore"]["within5"]), (0, 0, 1))
        self.assertEqual((report["endsAfter"]["within1"], report["endsAfter"]["within2"],
                          report["endsAfter"]["within5"]), (1, 1, 1))
        self.assertEqual(report["endsAfter"]["share1"], 1.0)
        self.assertEqual(report["episodes"]["withWordTimes"], 1)

    def test_an_episode_without_word_times_is_scored_as_before_for_both(self):
        self.episode(1, [label(3, 4, 10.0, 20.0)], [("0:10.000", "0:17.400")])
        report = self.run_score()
        self.assertEqual(report["endsAfter"], report["endsBefore"])
        self.assertEqual(report["episodes"]["withWordTimes"], 0)
        self.assertEqual(report["withWordTimes"]["marked"], 0)

    def test_the_subset_with_word_times_is_reported_alone(self):
        self.episode(1, [label(3, 4, 10.0, 20.0)], [("0:10.000", "0:17.400")], ends={4: 17.3})
        self.episode(2, [label(3, 4, 10.0, 20.0)], [("0:10.000", "0:17.400")])
        report = self.run_score()
        self.assertEqual(report["stretches"]["marked"], 2)
        self.assertEqual(report["withWordTimes"]["marked"], 1)
        self.assertEqual(report["withWordTimes"]["endsAfter"]["within1"], 1)
        self.assertEqual(report["endsAfter"]["within1"], 1)

    def test_several_labels_in_one_stretch_use_the_first_start_and_the_last_end(self):
        self.episode(1, [label(3, 4, 10.0, 20.0), label(5, 6, 20.0, 30.0)], [("0:10.000", "0:27.000")],
                     ends={6: 27.2})
        report = self.run_score()
        self.assertEqual(report["stretches"]["marked"], 1)
        self.assertEqual((report["starts"]["within1"], report["endsAfter"]["within1"],
                          report["endsBefore"]["within2"]), (1, 1, 0))

    def test_a_stretch_no_label_covers_is_counted_and_not_scored(self):
        self.episode(1, [label(3, 4, 10.0, 20.0)], [("0:10.000", "0:17.400"), ("5:00.000", "5:30.000")])
        report = self.run_score()
        self.assertEqual((report["stretches"]["differing"], report["stretches"]["marked"],
                          report["stretches"]["notMarked"]), (2, 1, 1))

    def test_a_stretch_over_300_seconds_is_left_out(self):
        self.episode(1, [label(3, 4, 10.0, 20.0)], [("0:10.000", "0:17.400"), ("1:00.000", "7:00.000")])
        report = self.run_score()
        self.assertEqual((report["stretches"]["tooLong"], report["stretches"]["differing"]), (1, 1))

    def test_an_episode_whose_downloads_agreed_has_nothing_to_score(self):
        self.episode(1, [label(3, 4, 10.0, 20.0)], [])
        report = self.run_score()
        self.assertEqual((report["stretches"]["differing"], report["stretches"]["marked"]), (0, 0))
        self.assertEqual(report["episodes"]["withTruth"], 1)
        self.assertIsNone(report["endsAfter"]["share5"])

    def test_an_episode_with_no_truth_file_or_no_transcript_is_counted_and_left_out(self):
        identifier = self.episode(1, [label(3, 4, 10.0, 20.0)], [("0:10.000", "0:17.400")])
        os.remove(self.teaching.path("copies", identifier + ".truth.txt"))
        other = self.episode(2, [label(3, 4, 10.0, 20.0)], [("0:10.000", "0:17.400")])
        os.remove(self.teaching.path("transcripts", other + ".txt"))
        report = self.run_score()
        self.assertEqual((report["episodes"]["withTruth"], report["episodes"]["noTranscript"],
                          report["episodes"]["labelled"]), (1, 1, 2))

    def test_the_sealed_exam_is_not_scored(self):
        identifier = self.episode(1, [label(3, 4, 10.0, 20.0)], [("0:10.000", "0:17.400")])
        with open(self.teaching.path("exam.json"), "w") as handle:
            json.dump({"version": 1, "episodes": [identifier]}, handle)
        report = self.run_score()
        self.assertEqual((report["episodes"]["exam"], report["stretches"]["marked"]), (1, 0))

    def test_the_bar_is_95_in_100_of_the_ends_within_5_seconds_after(self):
        for number in range(1, 21):
            end = "0:17.400" if number > 1 else "0:40.000"
            self.episode(number, [label(3, 4, 10.0, 20.0)], [("0:10.000", end)], ends={4: 17.3})
        report = self.run_score()
        self.assertEqual(report["endsAfter"]["within5"], 19)
        self.assertEqual((report["bar"]["share"], report["bar"]["needed"], report["bar"]["met"]),
                         (0.95, 0.95, True))
        self.episode(21, [label(3, 4, 10.0, 20.0)], [("0:10.000", "0:40.000")], ends={4: 17.3})
        self.assertFalse(self.run_score()["bar"]["met"])

    def test_a_damaged_label_or_truth_file_is_left_out_with_a_word_said(self):
        identifier = self.episode(1, [label(3, 4, 10.0, 20.0)], [("0:10.000", "0:17.400")])
        with open(self.teaching.path("copies", identifier + ".truth.txt"), "w") as handle:
            handle.write("not times\n")
        other = self.episode(2, [label(3, 4, 10.0, 20.0)], [("0:10.000", "0:17.400")])
        with open(self.teaching.path("labels", other + ".json"), "w") as handle:
            handle.write("{")
        report = self.run_score(say=self.said.append)
        self.assertEqual(report["stretches"]["marked"], 0)
        self.assertEqual(len(self.said), 2)


class SwitchTests(Base):
    def good(self, count=20):
        for number in range(1, count + 1):
            self.episode(number, [label(3, 4, 10.0, 20.0)], [("0:10.000", "0:17.400")], ends={4: 17.3})

    def switch(self):
        return self.teaching.path("word-ends-on")

    def test_the_report_has_a_plain_line_and_no_switch_without_the_flag(self):
        self.good()
        self.assertEqual(score.main(["--folder", self.teaching.dir], say=self.said.append), 0)
        self.assertTrue(any(line.startswith("The word ends passed the bar") for line in self.said), self.said)
        self.assertFalse(os.path.exists(self.switch()))

    def test_the_flag_writes_the_switch_when_the_bar_passes_and_no_kind_got_worse(self):
        self.good()
        score.main(["--folder", self.teaching.dir, "--switch-on-pass"], say=self.said.append)
        self.assertTrue(os.path.exists(self.switch()))
        self.assertTrue(any("switched on" in line for line in self.said))

    def test_the_flag_writes_nothing_when_the_bar_fails(self):
        self.good()
        self.episode(21, [label(3, 4, 10.0, 20.0)], [("0:10.000", "0:40.000")], ends={4: 17.3})
        self.episode(22, [label(3, 4, 10.0, 20.0)], [("0:10.000", "0:40.000")], ends={4: 17.3})
        score.main(["--folder", self.teaching.dir, "--switch-on-pass"], say=self.said.append)
        self.assertFalse(os.path.exists(self.switch()))
        self.assertTrue(any("did not pass the bar" in line for line in self.said))

    def test_the_flag_writes_nothing_when_one_kind_of_break_got_worse(self):
        self.good()
        # A host ask whose ad ends before the next line, so the last word end is further away.
        self.episode(30, [dict(label(3, 4, 10.0, 20.0), sort="host_ask")], [("0:10.000", "0:19.000")],
                     ends={4: 12.0})
        report = score.score(self.teaching.dir)
        self.assertTrue(report["bar"]["met"])
        self.assertFalse(report["bar"]["noKindWorse"])
        score.main(["--folder", self.teaching.dir, "--switch-on-pass"], say=self.said.append)
        self.assertFalse(os.path.exists(self.switch()))

    def test_before_and_after_are_reported_whether_or_not_the_switch_exists(self):
        self.good(1)
        for _ in range(2):
            report = score.score(self.teaching.dir)
            self.assertEqual(report["endsBefore"]["within5"], 1)
            self.assertEqual(report["endsAfter"]["within1"], 1)
            with open(self.switch(), "w") as handle:
                handle.write("on\n")


class MainTests(Base):
    def test_writes_the_report_and_says_the_numbers(self):
        self.episode(1, [label(3, 4, 10.0, 20.0)], [("0:10.000", "0:17.400")], ends={4: 17.3})
        code = score.main(["--folder", self.teaching.dir], say=self.said.append)
        self.assertEqual(code, 0)
        with open(self.teaching.path("end-edges.json")) as handle:
            written = json.load(handle)
        self.assertEqual(written["endsAfter"]["within1"], 1)
        text = "\n".join(self.said)
        self.assertIn("within 1 s", text)
        self.assertIn("100%", text)

    def test_the_report_goes_where_asked(self):
        self.episode(1, [label(3, 4, 10.0, 20.0)], [("0:10.000", "0:17.400")])
        out = self.teaching.path("mine.json")
        self.assertEqual(score.main(["--folder", self.teaching.dir, "--out", out], say=self.said.append), 0)
        self.assertTrue(os.path.exists(out))

    def test_no_labels_folder_is_a_set_up_problem(self):
        folder = testing.Folder(self)
        self.assertEqual(score.main(["--folder", folder.dir], say=self.said.append), 2)
        self.assertIn("labels", self.said[0])


if __name__ == "__main__":
    unittest.main()
