"""Tests for teach_spans.py. The cases mirror AdWordModelTests.swift in PodcastAdsTests, so the Mac
and the phone agree on the same inputs. No network.
Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import unittest

import teach_spans as spans
from teach_features import bucket, softmax_of

# The probabilities the Swift reference test expects for its nine lines, and their times.
REFERENCE_ROWS = [
    [0.909083, 0.050021, 0.013632, 0.013632, 0.013632],
    [0.230597, 0.692751, 0.025551, 0.025551, 0.025551],
    [0.002226, 0.992308, 0.001822, 0.001822, 0.001822],
    [0.006006, 0.985048, 0.002982, 0.002982, 0.002982],
    [0.919043, 0.030671, 0.022722, 0.013782, 0.013782],
    [0.919043, 0.030671, 0.022722, 0.013782, 0.013782],
    [0.006478, 0.010681, 0.961478, 0.010681, 0.010681],
    [0.006478, 0.010681, 0.961478, 0.010681, 0.010681],
    [0.950893, 0.010563, 0.017416, 0.010563, 0.010563],
]
REFERENCE_STARTS = [0.0, 6.0, 12.0, 20.0, 26.0, 33.0, 130.0, 137.0, 144.0]
REFERENCE_ENDS = [5.5, 11.5, 19.5, 25.5, 32.5, 36.0, 136.5, 143.5, 147.0]

# "hi" lines are surely an ad, "mid" lines are about 0.55 and any other line is about 0.03.
LEVELS = {bucket("#bias"): [5.0, 0, 0, 0, 0], bucket("u:hi"): [-7.0, 7.0, 0, 0, 0],
          bucket("u:mid"): [-2.5, 2.5, 0, 0, 0]}


def rows_of(words):
    return [softmax_of([bucket("#bias"), bucket("u:" + w)], LEVELS) for w in words]


def decoded(words, step=6.0, length=5.0, thresholds=spans.THRESHOLDS):
    starts = [i * step for i in range(len(words))]
    ends = [t + length for t in starts]
    return spans.decode(rows_of(words), starts, ends, thresholds)


def numbers(found):
    return [[first + 1, last + 1] for first, last, _, _ in found]


class DecodeTests(unittest.TestCase):
    def test_spans_follow_the_reference(self):
        found = spans.decode(REFERENCE_ROWS, REFERENCE_STARTS, REFERENCE_ENDS)
        self.assertEqual(numbers(found), [[2, 4], [7, 8]])
        self.assertEqual([f[2] for f in found], ["sponsor", "network_promo"])
        self.assertAlmostEqual(found[0][3], 0.787764, places=5)
        self.assertAlmostEqual(found[1][3], 0.761399, places=5)

    def test_one_weak_line_is_bridged_but_not_two(self):
        self.assertEqual(numbers(decoded(["lo", "hi", "mid", "lo", "mid", "hi", "lo"])), [[2, 6]])
        self.assertEqual(numbers(decoded(["lo", "hi", "mid", "lo", "lo", "mid", "hi", "lo"])),
                         [[2, 3]])

    def test_a_short_span_is_dropped_unless_its_score_is_at_least_point_nine(self):
        self.assertEqual(decoded(["lo", "hi", "hi", "lo"], step=3, length=2), [])
        strong = decoded(["lo", "hi", "hi", "hi", "hi", "hi", "lo"], step=1, length=1)
        self.assertEqual(len(strong), 1)
        self.assertAlmostEqual(strong[0][3], 0.902514, places=5)

    def test_ten_seconds_is_kept(self):
        self.assertEqual(len(decoded(["lo", "hi", "hi", "hi", "hi", "hi", "lo"], step=2, length=2)), 1)

    def test_the_thresholds_are_used(self):
        words = ["lo", "hi", "hi", "lo"]
        self.assertEqual(len(decoded(words)), 1)
        strict = {"start": 0.99, "stay": 0.5, "sure": 0.5}
        self.assertEqual(decoded(words, thresholds=strict), [])

    def test_empty_input(self):
        self.assertEqual(spans.decode([], [], []), [])

    def test_equal_probabilities_make_one_span_and_the_earliest_class_wins_the_tie(self):
        rows = [[0.2] * 5 for _ in range(9)]
        found = spans.decode(rows, REFERENCE_STARTS, REFERENCE_ENDS)
        self.assertEqual(numbers(found), [[1, 9]])
        self.assertEqual(found[0][2], "sponsor")
        self.assertAlmostEqual(found[0][3], 0.8, places=12)


# The model of AdModelSplitTests.swift: "theme" lines are intro or credits, "acme" lines a sponsor,
# "plug" lines a host ask, and any other line is plain talk.
SPLIT_LEVELS = {bucket("#bias"): [4.0, 0, 0, 0, 0], bucket("u:theme"): [-4.0, 0, 0, 0, 6.0],
                bucket("u:acme"): [-4.0, 6.0, 0, 0, 0], bucket("u:plug"): [-4.0, 0, 0, 6.0, 0]}
THEME_THEN_SPONSOR = ["plain"] * 2 + ["theme"] * 3 + ["acme"] * 4 + ["plain"] * 2


def split_decoded(words):
    rows = [softmax_of([bucket("#bias"), bucket("u:" + w)], SPLIT_LEVELS) for w in words]
    starts = [10.0 * i for i in range(len(words))]
    return spans.decode(rows, starts, [t + 9.0 for t in starts])


class SplitTests(unittest.TestCase):
    def test_a_span_is_cut_where_the_top_class_changes(self):
        found = split_decoded(THEME_THEN_SPONSOR)
        self.assertEqual([f[2] for f in found], ["intro_credits", "sponsor"])
        self.assertEqual(numbers(found), [[3, 5], [6, 9]])

    def test_a_bridged_weak_line_joins_the_class_before_it(self):
        found = split_decoded(["plain"] + ["acme"] * 3 + ["plain"] + ["acme"] * 3 + ["plain"])
        self.assertEqual([f[2] for f in found], ["sponsor"])
        self.assertEqual(numbers(found), [[2, 8]])

    def test_each_piece_has_its_own_score(self):
        found = split_decoded(THEME_THEN_SPONSOR)
        self.assertNotAlmostEqual(found[0][3], found[1][3], places=3)
        self.assertGreater(found[0][3], 0.6)

    def test_the_minimum_applies_to_the_whole_span_not_to_a_piece(self):
        # Two lines of each class are 4 seconds each, but the whole span is long enough.
        rows = [softmax_of([bucket("#bias"), bucket("u:" + w)], SPLIT_LEVELS)
                for w in ["plain", "theme", "theme", "acme", "acme", "plain"]]
        starts = [3.0 * i for i in range(6)]
        found = spans.decode(rows, starts, [t + 2.9 for t in starts])
        self.assertEqual([f[2] for f in found], ["intro_credits", "sponsor"])

    def test_the_cut_seconds_follow_the_pieces(self):
        # Credits then a sponsor: only the sponsor piece is cut, whatever the whole span was.
        words = THEME_THEN_SPONSOR
        rows = [softmax_of([bucket("#bias"), bucket("u:" + w)], SPLIT_LEVELS) for w in words]
        starts = [10.0 * i for i in range(len(words))]
        classes = [0, 0, 4, 4, 4, 1, 1, 1, 1, 0, 0]
        self.assertEqual(spans.span_scores(rows, classes, starts, [t + 10.0 for t in starts]),
                         (40.0, 40.0, 40.0))


class ScoreTests(unittest.TestCase):
    AD = [0.02, 0.92, 0.02, 0.02, 0.02]
    NONE = [0.9, 0.025, 0.025, 0.025, 0.025]
    ROWS = [NONE] * 2 + [AD] * 4 + [NONE] * 2
    STARTS = [10.0 * i for i in range(8)]
    ENDS = [10.0 * (i + 1) for i in range(8)]

    def test_seconds_cut_right_and_real(self):
        classes = [0, 0, 1, 1, 0, 0, 0, 0]
        # Lines 3 to 6 (40 s) are cut; 20 s of them are ads; 20 s are real ads.
        self.assertEqual(spans.span_scores(self.ROWS, classes, self.STARTS, self.ENDS),
                         (40.0, 20.0, 20.0))

    def test_a_sponsor_span_over_credits_is_wrong(self):
        classes = [0, 0, 4, 4, 4, 4, 0, 0]
        self.assertEqual(spans.span_scores(self.ROWS, classes, self.STARTS, self.ENDS),
                         (40.0, 0.0, 0.0))

    def test_a_span_of_a_sort_the_phone_does_not_skip_is_not_cut(self):
        rows = [[0.02, 0.02, 0.02, 0.02, 0.92]] * 8
        self.assertEqual(spans.span_scores(rows, [4] * 8, self.STARTS, self.ENDS), (0.0, 0.0, 0.0))

    def test_unsure_lines_count_as_not_an_ad(self):
        classes = [0, 0, 1, None, 1, 1, 0, 0]
        self.assertEqual(spans.span_scores(self.ROWS, classes, self.STARTS, self.ENDS),
                         (40.0, 30.0, 30.0))


if __name__ == "__main__":
    unittest.main()
