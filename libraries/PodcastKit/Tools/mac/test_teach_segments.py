"""Tests for teach_segments.py: reading a transcript, cutting it into parts, the prompt, checking
the answer, joining split stretches and adding times. No network.
Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import json
import unittest

import teach_segments as seg


def line(number, **fields):
    """A segment dict with defaults, for the tests."""
    base = {"first": number, "last": number, "sort": "sponsor", "who": "Acme",
            "delivery": "host", "confidence": "high", "why": "x"}
    base.update(fields)
    return base


class ReadTranscriptTests(unittest.TestCase):
    def test_reads_times_and_text(self):
        text = "[00:00:00.0] hello\n[00:12:30.5] and we're back\n[01:00:01] no tenths\n"
        self.assertEqual(seg.read_transcript(text),
                         [(0.0, "hello"), (750.5, "and we're back"), (3601.0, "no tenths")])

    def test_skips_bad_and_empty_lines(self):
        text = "garbage\n[00:00:01.0] \n[00:00:02.0] fine\n\n[0:1] bad time\n"
        self.assertEqual(seg.read_transcript(text), [(2.0, "fine")])


class PartsTests(unittest.TestCase):
    def test_one_part_when_it_fits(self):
        self.assertEqual(seg.parts([(0.0, "abc")] * 5), [(1, 5)])

    def test_splits_within_limit_and_covers_every_line_once(self):
        lines = [(0.0, "x" * 10)] * 7
        self.assertEqual(seg.parts(lines, limit=30), [(1, 3), (4, 6), (7, 7)])

    def test_huge_line_is_a_part_by_itself(self):
        lines = [(0.0, "a"), (1.0, "b" * 100), (2.0, "c")]
        self.assertEqual(seg.parts(lines, limit=10), [(1, 1), (2, 2), (3, 3)])

    def test_empty_transcript(self):
        self.assertEqual(seg.parts([]), [])


class PromptTests(unittest.TestCase):
    LINES = [(0.0, "hello"), (7.4, "world"), (3725.0, "late")]

    def test_whole_transcript(self):
        text = seg.prompt("Show", "Title", self.LINES, 1, 3)
        self.assertEqual(text, "Show: Show\nEpisode: Title\n\nTranscript:\n"
                               "1 [0:00:00] hello\n2 [0:00:07] world\n3 [1:02:05] late")

    def test_part_uses_real_numbers_and_says_so(self):
        text = seg.prompt("Show", "Title", self.LINES, 2, 3)
        self.assertIn("lines 2 to 3 of 3", text)
        self.assertIn("may have begun before them or carry on after them", text)
        self.assertTrue(text.endswith("Transcript:\n2 [0:00:07] world\n3 [1:02:05] late"))
        self.assertNotIn("1 [0:00:00]", text)


class ParseTests(unittest.TestCase):
    def answer(self, *items):
        return json.dumps({"segments": list(items)})

    def test_good_segment(self):
        segments, dropped = seg.parse(self.answer(line(2, last=4)), 1, 10)
        self.assertEqual(dropped, 0)
        self.assertEqual(segments, [line(2, last=4)])

    def test_code_fence_and_words_around(self):
        text = "Here you go:\n```json\n" + self.answer(line(1)) + "\n```\nDone."
        self.assertEqual(len(seg.parse(text, 1, 5)[0]), 1)

    def test_no_json_raises(self):
        with self.assertRaises(ValueError):
            seg.parse("nothing here", 1, 5)

    def test_segments_not_a_list_raises(self):
        with self.assertRaises(ValueError):
            seg.parse('{"segments": "no"}', 1, 5)
        with self.assertRaises(ValueError):
            seg.parse('{"other": []}', 1, 5)

    def test_empty_list(self):
        self.assertEqual(seg.parse('{"segments": []}', 1, 5), ([], 0))

    def test_drops_bad_numbers_and_sorts(self):
        items = [line(3, first=True), line(3, last=2.5), line(3, first=0), line(3, last=99),
                 line(5, last=4), line(3, sort="other"), line(3, first="3"), "text", line(3)]
        segments, dropped = seg.parse(self.answer(*items), 1, 10)
        self.assertEqual(dropped, 8)
        self.assertEqual([s["first"] for s in segments], [3])

    def test_range_is_the_parts_range(self):
        segments, dropped = seg.parse(self.answer(line(5, last=6), line(2)), 5, 8)
        self.assertEqual((len(segments), dropped), (1, 1))

    def test_defaults_and_cuts(self):
        item = {"first": 1, "last": 2, "sort": "host_ask", "who": "w" * 100, "why": "y" * 300,
                "confidence": "certain", "delivery": "robot"}
        segments, _ = seg.parse(self.answer(item), 1, 5)
        self.assertEqual(segments[0]["confidence"], "low")
        self.assertEqual(segments[0]["delivery"], "unsure")
        self.assertEqual((len(segments[0]["who"]), len(segments[0]["why"])), (80, 200))
        bare = {"first": 1, "last": 2, "sort": "sponsor", "who": 5, "why": None}
        segments, _ = seg.parse(self.answer(bare), 1, 5)
        self.assertEqual((segments[0]["who"], segments[0]["why"]), ("", ""))
        self.assertEqual((segments[0]["confidence"], segments[0]["delivery"]), ("low", "unsure"))

    def test_orders_and_cuts_overlaps(self):
        items = [line(8, last=10), line(1, last=5), line(4, last=6, who="B"), line(2, last=3, who="C")]
        segments, dropped = seg.parse(self.answer(*items), 1, 10)
        self.assertEqual([(s["first"], s["last"]) for s in segments], [(1, 5), (6, 6), (8, 10)])
        self.assertEqual(dropped, 1)


class MergeTests(unittest.TestCase):
    def test_joins_neighbours_with_lowest_confidence(self):
        joined = seg.merge([line(1, last=3, who="Acme", confidence="high", why="first"),
                            line(4, last=6, who="ACME", confidence="low")])
        self.assertEqual(len(joined), 1)
        self.assertEqual((joined[0]["first"], joined[0]["last"]), (1, 6))
        self.assertEqual((joined[0]["confidence"], joined[0]["why"], joined[0]["who"]),
                         ("low", "first", "Acme"))

    def test_keeps_apart_when_gap_sort_or_who_differ(self):
        self.assertEqual(len(seg.merge([line(1, last=3), line(5, last=6)])), 2)
        self.assertEqual(len(seg.merge([line(1, last=3), line(4, sort="host_ask")])), 2)
        self.assertEqual(len(seg.merge([line(1, last=3), line(4, who="Other")])), 2)

    def test_does_not_change_its_input(self):
        original = [line(1, last=3), line(4, last=5)]
        seg.merge(original)
        self.assertEqual(original[0]["last"], 3)


class WithTimesTests(unittest.TestCase):
    LINES = [(0.0, "a"), (10.04, "b"), (20.0, "c"), (31.26, "d")]

    def test_start_and_end_from_next_line(self):
        out = seg.with_times([line(2, last=3)], self.LINES)
        self.assertEqual((out[0]["start"], out[0]["end"]), (10.0, 31.3))

    def test_last_line_ends_five_seconds_later(self):
        out = seg.with_times([line(3, last=4)], self.LINES)
        self.assertEqual((out[0]["start"], out[0]["end"]), (20.0, 36.3))


if __name__ == "__main__":
    unittest.main()
