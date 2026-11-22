"""Tests for teach_phone_rule.py and the way teach_publish.py uses it: one failing case for each
rule of `init?(data:)` in AdWordModel.swift, and a good model that passes. No network.
Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import copy
import json
import unittest

import teach_phone_rule as rule
import teach_publish as publish
from teach_features import CLASSES, bucket

BIAS = bucket("#bias", 262144)


def good():
    return {"version": 1, "buckets": 262144, "classes": list(CLASSES),
            "weights": {str(BIAS): [4.0, 0, 0, 0, 0], "122389": [-3.0, 3.0, 0, 0, 0]}}


def changed(**fields):
    value = good()
    value.update(fields)
    return value


class RefusalTests(unittest.TestCase):
    def refused(self, value, text):
        found = rule.refusals(value)
        self.assertTrue(any(text in reason for reason in found), (text, found))

    def test_a_good_model_is_taken(self):
        self.assertEqual(rule.refusals(good()), [])

    def test_a_good_model_with_thresholds_is_taken(self):
        self.assertEqual(rule.refusals(changed(thresholds={"start": 0.5, "stay": 0.5, "sure": 1})),
                         [])

    def test_not_an_object(self):
        self.refused([], "not an object")

    def test_the_version_must_be_1(self):
        self.refused(changed(version=2), "version")
        self.refused(changed(version=True), "version")
        self.refused(changed(version="1"), "version")

    def test_the_buckets_must_be_in_range(self):
        for value in (1023, 4194305, "262144", None, True, 2048.5, float("nan")):
            self.refused(changed(buckets=value), "bucket count")
        self.assertEqual(rule.refusals(changed(buckets=1024, weights={"0": [4, 0, 0, 0, 0],
                         str(bucket("#bias", 1024)): [4, 0, 0, 0, 0]})), [])

    def test_the_classes_must_be_the_five_in_order(self):
        self.refused(changed(classes=list(reversed(CLASSES))), "classes")
        self.refused(changed(classes=CLASSES[:4]), "classes")
        self.refused(changed(classes="none"), "classes")

    def test_the_weights_must_not_be_empty(self):
        self.refused(changed(weights={}), "no weights")
        self.refused(changed(weights=[]), "no weights")

    def test_a_threshold_must_be_a_finite_number_from_0_to_1(self):
        for name in ("start", "stay", "sure"):
            for value in (-0.1, 1.5, "0.6", True, None, float("nan"), float("inf")):
                self.refused(changed(thresholds={name: value}), "threshold " + name)
        self.refused(changed(thresholds="high"), "thresholds")

    def test_an_unknown_threshold_is_checked_too(self):
        self.refused(changed(thresholds={"other": 7}), "threshold other")

    def test_start_must_be_at_least_one_half(self):
        self.refused(changed(thresholds={"start": 0.49, "stay": 0.3}), "below 0.5")

    def test_stay_must_not_be_above_start(self):
        self.refused(changed(thresholds={"start": 0.6, "stay": 0.7}), "stay threshold is above")

    def test_a_missing_threshold_takes_the_default(self):
        self.assertEqual(rule.refusals(changed(thresholds={"start": 0.55})), [])
        self.assertEqual(rule.refusals(changed(thresholds={"start": 0.5})), [])
        self.refused(changed(thresholds={"stay": 0.7}), "stay threshold is above")

    def test_a_weights_key_must_be_digits_below_the_buckets(self):
        for key in ("", "-5", "1e3", "12a", " 7", "262144", "٣"):
            weights = good()["weights"]
            weights[key] = [0] * 5
            self.refused(changed(weights=weights), "weights key")

    def test_a_row_must_be_five_finite_numbers_within_a_million(self):
        for row in ([0] * 4, [0] * 6, [0, 0, 0, 0, "1"], [0, 0, 0, 0, True], [0, 0, 0, 0, None],
                    [0, 0, 0, 0, float("nan")], [0, 0, 0, 0, float("inf")], [0, 0, 0, 0, 1000001],
                    [0, 0, 0, 0, -1000001], [0, 0, 0, 0, 10 ** 400], "abcde", None, {}):
            weights = good()["weights"]
            weights["5"] = row
            self.refused(changed(weights=weights), "weights row")

    def test_a_row_at_a_million_is_fine(self):
        weights = good()["weights"]
        weights["5"] = [-1000000, 1000000, 0, 0, 0]
        self.assertEqual(rule.refusals(changed(weights=weights)), [])

    def test_a_bias_that_does_not_call_a_line_plain_is_refused(self):
        weights = good()["weights"]
        weights[str(BIAS)] = [0.0, 1.0, 0, 0, 0]
        self.refused(changed(weights=weights), "bias")

    def test_a_missing_bias_row_counts_as_zeros_and_is_refused(self):
        self.refused(changed(weights={"122389": [-3.0, 3.0, 0, 0, 0]}), "bias")

    def test_a_bias_of_exactly_one_half_is_taken(self):
        weights = good()["weights"]
        weights[str(BIAS)] = [-1e6, 0, 0, 0, 0]
        self.refused(changed(weights=weights), "bias")
        weights[str(BIAS)] = [1.0, 1.0, -1e6, -1e6, -1e6]
        self.assertEqual(rule.refusals(changed(weights=weights)), [])

    def test_every_reason_is_listed(self):
        value = changed(version=2, classes=[], weights={})
        self.assertGreaterEqual(len(rule.refusals(value)), 3)

    def test_the_input_is_not_changed(self):
        value = good()
        before = copy.deepcopy(value)
        rule.refusals(value)
        self.assertEqual(value, before)


def strong(value):
    held = {"episodes": 6, "shows": 4, "predictedAdSeconds": 900,
            "anyAd": {"precision": 0.9, "recall": 0.5}}
    value["trained"] = {"heldOut": held}
    return json.dumps(value).encode("utf-8")


class PublishGateTests(unittest.TestCase):
    def test_a_good_strong_model_passes_the_gate(self):
        self.assertIsNone(publish.weak_model(strong(good()), 0.85))

    def test_a_model_the_phone_would_refuse_is_not_published_and_says_why(self):
        said = publish.weak_model(strong(changed(buckets=10)), 0.85)
        self.assertIn("the phone would refuse the file", said)
        self.assertIn("bucket count", said)

    def test_the_reasons_come_with_the_old_ones(self):
        said = publish.weak_model(json.dumps(changed(version=3)).encode("utf-8"), 0.85)
        self.assertIn("version is not 1", said)
        self.assertIn("no precision", said)

    def test_odd_json_values_never_crash_the_gate(self):
        for text in (b'{"version": 1, "buckets": NaN, "weights": {"1": [NaN, 1, 1, 1, 1]}}',
                     b'{"version": 1, "thresholds": {"start": "x"}, "weights": 5}',
                     b'{"version": 1, "classes": null, "weights": {"1": true}}',
                     b'[1, 2]', b'null', b'{"version": 1, "weights": {"1": [1e999, 0, 0, 0, 0]}}'):
            self.assertIn("refuse", publish.weak_model(text, 0.85) or "", text)


if __name__ == "__main__":
    unittest.main()
