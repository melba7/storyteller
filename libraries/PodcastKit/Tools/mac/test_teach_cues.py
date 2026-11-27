"""Tests for teach_cues.py: when a line opens, is in an ad or returns, the 5-episode and 9-in-10
rule, the per-show 3-episode rule, keeping only the shortest cue, the common and usual words, the
shelf and the exam being left out, and damaged input. Made-up transcripts only. No network.
Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import json
import os
import unittest
from collections import Counter

import teach_cues as cues
from teach_testing import Folder, entry

AD = (60.0, 90.0)


def stamp(seconds):
    return "[%02d:%02d:%04.1f]" % (seconds // 3600, seconds % 3600 // 60, seconds % 60)


def lines_of(number, opener="This episode is brought to you by Foo.", back="And we are back with more.",
             extra=()):
    """One made-up episode: talk, an opening line at 60 s, a line in the ad, the return at 90 s,
    more talk. The talk has words only this episode has, so no episode repeats another."""
    own = " ".join("w%dx%d" % (number, j) for j in range(40))
    return [(0.0, "Hello and " + own), (30.0, "Talk " + own[::-1]), (AD[0], opener),
            (70.0, "Use the code foo today."), (AD[1], back),
            (120.0, "Then " + own.upper())] + list(extra)


def segment(start, end, sort="sponsor", confidence="high"):
    return {"first": 1, "last": 2, "sort": sort, "confidence": confidence, "start": start, "end": end}


class Setup(unittest.TestCase):
    def setUp(self):
        self.folder = Folder(self)
        self.said = []
        self.entries = []

    def episode(self, number, feed="https://show/a", lines=None, spans=(AD,), segments=None,
                labels="labels", **more):
        item = entry(number, feed=feed, **more)
        self.entries.append(item)
        lines = lines_of(number) if lines is None else lines
        os.makedirs(self.folder.path("transcripts"), exist_ok=True)
        with open(self.folder.path("transcripts", item["id"] + ".txt"), "w", encoding="utf-8") as f:
            f.write("\n".join("%s %s" % (stamp(t), text) for t, text in lines) + "\n")
        found = segments if segments is not None else [segment(a, b) for a, b in spans]
        self.label(item["id"], {"version": 1, "segments": found, "length": 200}, labels)
        return item["id"]

    def label(self, identifier, value, labels="labels"):
        os.makedirs(self.folder.path(labels), exist_ok=True)
        with open(self.folder.path(labels, identifier + ".json"), "w", encoding="utf-8") as f:
            json.dump(value, f)

    def run_it(self, *more, minimum="1"):
        self.folder.write_manifest(self.entries)
        code = cues.main(["--folder", self.folder.dir, "--min-episodes", minimum] + list(more),
                         say=self.said.append, now=lambda: 1700000000)
        return code

    def written(self):
        with open(self.folder.path("ad-cues.json"), encoding="utf-8") as f:
            return json.load(f)


class LineRuleTests(unittest.TestCase):
    def read(self, lines, spans):
        return cues.read_episode(lines, spans)

    def test_a_line_opens_within_one_second_of_a_segment_start(self):
        for start, opens in ((59.0, True), (61.0, True), (58.9, False), (61.1, False)):
            found = self.read([(start, "one two three four")], [(60.0, 80.0)])
            self.assertEqual(bool(found["starts"]), opens, start)

    def test_a_line_in_an_ad_neither_opens_nor_returns(self):
        found = self.read([(65.0, "one two three"), (70.0, "four five six")], [(60.0, 90.0)])
        self.assertEqual((found["starts"], found["returns"]), (Counter(), Counter()))

    def test_the_first_line_after_the_ad_returns(self):
        lines = [(60.0, "open now here"), (80.0, "still in it"), (89.6, "back after break"),
                 (95.0, "later talk goes on")]
        found = self.read(lines, [(60.0, 90.0)])
        self.assertEqual(set(found["returns"]), {"back after break"})

    def test_the_ad_ends_half_a_second_early_and_starts_a_third_early(self):
        lines = [(59.6, "early line here"), (59.8, "second early line"), (89.4, "late in ad"),
                 (89.6, "just after it")]
        found = self.read(lines, [(60.0, 90.0)])
        self.assertEqual(set(found["returns"]), {"just after it"})

    def test_spans_within_a_second_are_one_break_and_far_ones_are_two(self):
        self.assertEqual(cues.joined([(10, 20), (20.9, 30), (35, 40)]), [(10, 30), (35, 40)])
        self.assertEqual(cues.joined([(10, 50), (20, 30)]), [(10, 50)])

    def test_a_line_with_fewer_than_three_words_has_no_cue(self):
        found = self.read([(60.0, "hello there")], [(60.0, 80.0)])
        self.assertEqual(found["starts"], Counter())
        found = self.read([(60.0, "one two three four five six seven")], [(60.0, 80.0)])
        self.assertEqual(set(found["starts"]), {"one two three", "one two three four",
                                                "one two three four five", "one two three four five six"})

    def test_the_words_are_those_of_four_letters_or_more(self):
        found = self.read([(0.0, "The quick fox 12 jumps")], [])
        self.assertEqual(found["words"], {"quick", "jumps"})


class RuleTests(Setup):
    def many(self, count, **more):
        for number in range(1, count + 1):
            self.episode(number, **more)

    def test_a_cue_in_five_episodes_is_written_and_in_four_it_is_not(self):
        self.many(4)
        self.assertEqual(self.run_it(), 0)
        self.assertEqual(self.written()["starts"], [])
        self.episode(5)
        self.assertEqual(self.run_it(), 0)
        self.assertEqual(self.written()["starts"], ["this episode is"])
        self.assertEqual(self.written()["returns"], ["and we are"])

    def test_only_the_shortest_cue_is_written(self):
        self.many(6)
        self.run_it()
        for cue in self.written()["starts"] + self.written()["returns"]:
            self.assertEqual(len(cue.split()), 3, cue)

    def test_nine_in_ten_of_the_lines_must_open(self):
        self.many(9)
        self.episode(10, lines=lines_of(10, extra=[(150.0, "This episode is about cats.")]))
        self.run_it()
        self.assertEqual(self.written()["starts"], ["this episode is"])  # 9 of 10 lines
        self.episode(11, lines=lines_of(11, extra=[(150.0, "This episode is about dogs.")]))
        self.run_it()
        self.assertEqual(self.written()["starts"], ["this episode is brought"])  # 9 of 11, so longer

    def test_a_show_needs_three_episodes_and_its_cue_is_listed_by_feed(self):
        for number in range(1, 4):
            self.episode(number, feed="https://show/a", lines=lines_of(number, opener="Mine alone opens here."))
        self.episode(4, feed="https://show/b", lines=lines_of(4, opener="Other words open this."))
        self.episode(5, feed="https://show/b", lines=lines_of(5, opener="Other words open this."))
        self.run_it()
        data = self.written()
        self.assertEqual(data["starts"], [])
        self.assertEqual([s["feed"] for s in data["shows"]], ["https://show/a"])
        self.assertEqual(data["shows"][0]["starts"], ["mine alone opens"])

    def test_a_show_does_not_repeat_a_general_cue_or_one_that_begins_with_it(self):
        self.many(5, feed="https://show/a")
        self.run_it()
        self.assertEqual(self.written()["shows"], [])
        self.assertEqual(self.written()["starts"], ["this episode is"])

    def test_a_show_with_a_longer_cue_than_the_general_one_has_none_of_its_own(self):
        for number in range(1, 6):
            self.episode(number, feed="https://show/%d" % number)
        self.run_it()
        self.assertEqual(self.written()["shows"], [])

    def test_the_file_is_sorted_and_says_what_it_learned_from(self):
        self.many(6)
        self.run_it()
        data = self.written()
        self.assertEqual((data["version"], data["writtenAt"], data["episodes"]), (1, 1700000000, 6))
        for name in ("starts", "returns", "common", "usual"):
            self.assertEqual(data[name], sorted(data[name]))
        self.assertIn("episode", " ".join(self.said))

    def test_only_high_and_medium_ads_of_the_three_sorts_teach(self):
        for number in range(1, 7):
            self.episode(number, segments=[segment(60, 90, "intro_credits"),
                                           segment(60, 90, confidence="low")])
        self.run_it()
        self.assertEqual(self.written()["starts"], [])


class FrequencyTests(unittest.TestCase):
    def test_common_is_more_than_fifteen_in_a_hundred_and_usual_up_to_that(self):
        words = Counter({"often": 16, "edge": 15, "some": 6, "five": 5, "rare": 1})
        self.assertEqual(cues.frequent(words, 100, 15, None), ["often"])
        self.assertEqual(cues.frequent(words, 100, 5, 15), ["edge", "some"])


class LeftOutTests(Setup):
    def test_the_shelf_the_exam_and_their_repeats_do_not_teach(self):
        for number in range(1, 7):
            self.episode(number)
        shelved = self.episode(7, lines=lines_of(7, opener="Shelf opener words go here."))
        sealed = self.episode(8, lines=lines_of(8, opener="Exam opener words go here."))
        same = lines_of(9, opener="Repeat opener words go here.")
        self.episode(9, lines=same)
        self.episode(10, lines=same)
        self.folder.write_manifest(self.entries)
        with open(self.folder.path("shelf.json"), "w") as f:
            json.dump({"version": 1, "episodes": [shelved, self.entries[8]["id"]]}, f)
        with open(self.folder.path("exam.json"), "w") as f:
            json.dump({"episodes": [sealed]}, f)
        self.assertEqual(self.run_it(), 0)
        data = self.written()
        self.assertEqual(data["episodes"], 6)
        self.assertEqual(data["starts"], ["this episode is"])
        self.assertNotIn("shelf", " ".join(data["common"] + data["usual"]))

    def test_the_shelf_is_read_as_it_is_and_never_chosen(self):
        for number in range(1, 7):
            self.episode(number)
        self.run_it()
        self.assertFalse(os.path.exists(self.folder.path("shelf.json")))


class BadInputTests(Setup):
    def test_a_bad_label_or_transcript_is_skipped_and_counted(self):
        for number in range(1, 7):
            self.episode(number)
        self.label(self.entries[0]["id"], {"segments": "no"})
        self.episode(7, segments=[{"first": 1, "last": 2, "sort": "sponsor", "confidence": "high"}])
        with open(self.folder.path("transcripts", self.entries[2]["id"] + ".txt"), "wb") as f:
            f.write(b"\xff\xfe\x00bad")
        with open(self.folder.path("labels", self.entries[3]["id"] + ".json"), "w") as f:
            f.write("{not json")
        self.assertEqual(self.run_it(), 0)
        self.assertEqual(self.written()["episodes"], 3)
        self.assertEqual(sum(1 for m in self.said if m.startswith("Skipping")), 4)
        self.assertIn("4 unreadable", " ".join(self.said))

    def test_too_few_episodes_say_so_and_leave_an_old_file_alone(self):
        for number in range(1, 4):
            self.episode(number)
        with open(self.folder.path("ad-cues.json"), "w") as f:
            f.write("old")
        self.assertEqual(self.run_it(minimum="20"), 0)
        with open(self.folder.path("ad-cues.json")) as f:
            self.assertEqual(f.read(), "old")
        self.assertIn("at least 20", " ".join(self.said))

    def test_a_file_that_would_be_the_same_is_not_written_again(self):
        for number in range(1, 7):
            self.episode(number)
        self.run_it()
        before = os.stat(self.folder.path("ad-cues.json")).st_mtime_ns
        self.said.clear()
        self.assertEqual(cues.main(["--folder", self.folder.dir, "--min-episodes", "1"],
                                   say=self.said.append, now=lambda: 1800000000), 0)
        self.assertEqual(os.stat(self.folder.path("ad-cues.json")).st_mtime_ns, before)
        self.assertEqual(self.written()["writtenAt"], 1700000000)
        self.assertIn("up to date", " ".join(self.said))

    def test_no_episode_list_is_a_set_up_problem(self):
        self.assertEqual(cues.main(["--folder", self.folder.dir], say=self.said.append), 2)
        self.assertIn("episodes.json", self.said[0])

    def test_a_damaged_shelf_is_a_set_up_problem(self):
        self.episode(1)
        self.folder.write_manifest(self.entries)
        with open(self.folder.path("shelf.json"), "w") as f:
            f.write("[]")
        self.assertEqual(cues.main(["--folder", self.folder.dir], say=self.said.append), 2)

    def test_the_labels_folder_can_be_chosen(self):
        for number in range(1, 7):
            self.episode(number, labels="labels-snapped")
        self.assertEqual(self.run_it("--labels", "labels-snapped"), 0)
        self.assertEqual(self.written()["starts"], ["this episode is"])


if __name__ == "__main__":
    unittest.main()
