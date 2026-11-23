"""Tests for teach_features.py: the tokens, features, hashing and probabilities that the phone must
compute the same way. The numbers come from the shared contract. No network.
Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import unittest

import teach_features as ft

WEIGHTS = {3916: [-1.0, 0.0, 1.0, 0.0, 0.0], 14330: [-0.5, 0.5, 0.0, 0.0, 0.0],
           44798: [-0.5, 0.0, 0.5, 0.0, 0.0], 49919: [-2.0, 2.0, 0.0, 0.0, 0.0],
           122389: [-3.0, 3.0, 0.0, 0.0, 0.0], 153606: [0.2, 0.3, 0.0, 0.0, 0.0],
           161629: [-1.0, 2.0, 0.0, 0.0, 0.0], 161948: [-1.0, 1.0, 0.0, 0.0, 0.0],
           168660: [-0.5, 0.0, 0.5, 0.0, 0.0], 211303: [5.0, 0.0, 0.0, 0.0, 0.0],
           242859: [-4.0, 0.0, 3.0, 0.0, 0.0]}

LINES = [(0.0, "Welcome to the show, I'm your host."),
         (6.0, "This episode is brought to you by Example Mattress."),
         (12.0, "Go to example.com/show and use promo code SHOW for 20 percent off."),
         (20.0, "That's example.com/show, promo code SHOW."),
         (26.0, "And we're back. Today we talk about rivers."),
         (33.0, "Rivers are long."),
         (130.0, "Come see us live in Chicago, tickets are on sale now."),
         (137.0, "Get your tickets at example.org/live."),
         (144.0, "Anyway, the river.")]

EXPECTED = [[0.909083, 0.050021, 0.013632, 0.013632, 0.013632],
            [0.230597, 0.692751, 0.025551, 0.025551, 0.025551],
            [0.002226, 0.992308, 0.001822, 0.001822, 0.001822],
            [0.006006, 0.985048, 0.002982, 0.002982, 0.002982],
            [0.919043, 0.030671, 0.022722, 0.013782, 0.013782],
            [0.919043, 0.030671, 0.022722, 0.013782, 0.013782],
            [0.006478, 0.010681, 0.961478, 0.010681, 0.010681],
            [0.006478, 0.010681, 0.961478, 0.010681, 0.010681],
            [0.950893, 0.010563, 0.017416, 0.010563, 0.010563]]


class TokenTests(unittest.TestCase):
    def test_reference_sentences(self):
        self.assertEqual(ft.tokens("Use promo code SLEEPY20 at example.com/show!"),
                         "use promo code sleepy20 at example com show".split())
        self.assertEqual(ft.tokens("Don’t miss it — 'quoted' O'Brien's 2026 tour"),
                         ["don't", "miss", "it", "quoted", "o'brien's", "0", "tour"])
        self.assertEqual(ft.tokens("  ...  "), [])
        self.assertEqual(ft.tokens("Café 100% OFF"), ["caf", "0", "off"])


class BucketTests(unittest.TestCase):
    def test_reference_buckets(self):
        expected = {"#bias": 211303, "u:promo": 122389, "b:promo code": 161629,
                    "p:sponsor": 116655, "n:back": 89566, "#t0": 153606, "#t1": 154009,
                    "#end": 119647, "u:0": 51818}
        for feature, number in expected.items():
            self.assertEqual(ft.bucket(feature), number, feature)
        self.assertEqual(ft.BUCKETS, 262144)

    def test_classes_in_contract_order(self):
        self.assertEqual(ft.CLASSES, ["none", "sponsor", "network_promo", "host_ask",
                                      "intro_credits"])


class FeatureTests(unittest.TestCase):
    def test_features_of_a_line(self):
        found = ft.features(LINES, 1, 150)
        self.assertIn("u:brought", found)
        self.assertIn("b:brought to", found)
        self.assertIn("p:welcome", found)
        self.assertIn("n:promo", found)
        self.assertIn("#t0", found)
        self.assertNotIn("#end", found)
        self.assertIn("#end", ft.features(LINES, 8, 150))
        self.assertNotIn("#end", ft.features(LINES, 8, None))

    def test_precomputed_buckets_equal_the_features(self):
        for duration in (150, None):
            precomputed = ft.episode_buckets(LINES, duration)
            for i in range(len(LINES)):
                wanted = sorted({ft.bucket(f) for f in ft.features(LINES, i, duration)})
                self.assertEqual(list(precomputed[i]), wanted)


class ProbabilityTests(unittest.TestCase):
    def test_reference_probabilities(self):
        for i, expected in enumerate(EXPECTED):
            got = ft.probabilities(WEIGHTS, LINES, i, 150)
            self.assertEqual([round(x, 6) for x in got], expected, "line %d" % i)


# Version 2 (4194304 buckets): the same numbers are pinned in AdWordModelVersionTwoTests.swift.
V2 = ft.BUCKETS_V2
WEIGHTS_V2 = {3357031: [5.0, 0, 0, 0, 0], 2033433: [-2.0, 2.0, 0, 0, 0],
              2349595: [-1.0, 0, 1.0, 0, 0], 1170965: [-3.0, 3.0, 0, 0, 0],
              3728355: [-1.0, 1.0, 0, 0, 0]}
EXPECTED_V2 = [[0.242466, 0.659091, 0.032814, 0.032814, 0.032814],
               [0.659091, 0.242466, 0.032814, 0.032814, 0.032814],
               [0.006561, 0.973756, 0.006561, 0.006561, 0.006561],
               [0.098767, 0.729797, 0.098767, 0.036334, 0.036334],
               [0.905195, 0.016579, 0.045067, 0.016579, 0.016579],
               [0.905195, 0.016579, 0.045067, 0.016579, 0.016579],
               [0.973756, 0.006561, 0.006561, 0.006561, 0.006561],
               [0.973756, 0.006561, 0.006561, 0.006561, 0.006561],
               [0.973756, 0.006561, 0.006561, 0.006561, 0.006561]]


class VersionTwoTests(unittest.TestCase):
    def test_reference_buckets(self):
        expected = {"#bias": 3357031, "u:promo": 1170965, "nb:promo code": 2033433,
                    "pb:promo code": 2349595, "nb:brought to": 3728355, "pb:welcome to": 358674,
                    "#t0": 4085766, "#end": 906079}
        for feature, number in expected.items():
            self.assertEqual(ft.bucket(feature, V2), number, feature)

    def test_a_version_1_line_has_no_pairs_of_its_neighbours(self):
        self.assertFalse([f for f in ft.features(LINES, 3, 150) if f[:2] in ("pb", "nb")])

    def test_the_pairs_of_the_neighbouring_lines_never_cross_a_line_border(self):
        found = ft.features(LINES, 3, 150, 2)
        pairs = sorted(f for f in found if f[:2] in ("pb", "nb"))
        self.assertEqual(len(pairs), 30)
        self.assertIn("pb:promo code", pairs)
        self.assertIn("pb:example mattress", pairs)
        self.assertNotIn("pb:mattress go", pairs)
        self.assertIn("nb:we're back", pairs)
        self.assertNotIn("nb:today rivers", pairs)
        self.assertEqual(len(found), 74)
        # Line 3 is three lines from line 0, so it takes no pair from it.
        self.assertNotIn("pb:welcome to", found)

    def test_the_pinned_pair_buckets_of_a_line(self):
        pairs = sorted(ft.bucket(f, V2) for f in ft.features(LINES, 3, 150, 2) if f[:2] in ("pb", "nb"))
        self.assertEqual(pairs[:4], [269845, 589285, 690944, 1015682])
        self.assertEqual(pairs[-3:], [3983256, 4093510, 4150614])

    def test_precomputed_buckets_equal_the_features(self):
        for duration in (150, None):
            precomputed = ft.episode_buckets(LINES, duration, 2, V2)
            for i in range(len(LINES)):
                wanted = sorted({ft.bucket(f, V2) for f in ft.features(LINES, i, duration, 2)})
                self.assertEqual(list(precomputed[i]), wanted)

    def test_reference_probabilities(self):
        for i, expected in enumerate(EXPECTED_V2):
            got = ft.probabilities(WEIGHTS_V2, LINES, i, 150, V2, 2)
            self.assertEqual([round(x, 6) for x in got], expected, "line %d" % i)


if __name__ == "__main__":
    unittest.main()
