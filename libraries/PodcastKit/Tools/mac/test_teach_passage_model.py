"""Tests for teach_passage_model.py: the windows of five lines, the softmax regression that is trained
on them (class weights, L2, the check that keeps the best pass) and its probabilities. Random
numbers only, no sentence model. Needs numpy.
Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import unittest
from unittest import mock

import numpy as np

import teach_passage_model as model

SIGNS = np.eye(5, dtype=np.float32) * 3


def episode(rng, classes, noise=0.3, shift=0):
    """Vectors for lines whose class is `classes`: a line's vector points at the class it has
    `shift` lines before it, plus noise, so shift 0 asks for the line itself and 1 for its
    neighbour."""
    n = len(classes)
    vectors = rng.normal(0, noise, (n, 8)).astype(np.float32)
    for i in range(n):
        seen = classes[i - shift] if 0 <= i - shift < n else 0
        vectors[i, :5] += SIGNS[seen]
    return vectors, list(classes)


def runs(rng, count=30, length=60):
    """`count` episodes with ad runs of 5 to 10 lines of a class from 1 to 4 among plain talk."""
    found = []
    for _ in range(count):
        classes = [0] * length
        at = 5
        while at < length - 12:
            size = int(rng.integers(5, 11))
            kind = int(rng.integers(1, 5))
            classes[at:at + size] = [kind] * size
            at += size + int(rng.integers(8, 14))
        found.append(classes)
    return found


class WindowTests(unittest.TestCase):
    def test_a_window_is_two_lines_before_the_line_and_two_after(self):
        vectors = np.arange(1, 7, dtype=np.float32).reshape(6, 1)
        made = model.windows(vectors)
        self.assertEqual(made.shape, (6, 5))
        self.assertEqual(made[2].tolist(), [1, 2, 3, 4, 5])
        self.assertEqual(made[3].tolist(), [2, 3, 4, 5, 6])

    def test_the_edges_of_an_episode_are_padded_with_zeros(self):
        made = model.windows(np.arange(1, 5, dtype=np.float32).reshape(4, 1))
        self.assertEqual(made[0].tolist(), [0, 0, 1, 2, 3])
        self.assertEqual(made[3].tolist(), [2, 3, 4, 0, 0])

    def test_an_episode_shorter_than_a_window_still_has_a_window_for_each_line(self):
        made = model.windows(np.ones((2, 3), dtype=np.float32))
        self.assertEqual(made.shape, (2, 15))
        self.assertEqual(made[0].tolist(), [0.0] * 6 + [1.0] * 6 + [0.0] * 3)

    def test_the_window_keeps_the_dimension_of_each_line_together(self):
        vectors = np.array([[1, 2], [3, 4], [5, 6]], dtype=np.float32)
        self.assertEqual(model.windows(vectors)[1].tolist(), [0, 0, 1, 2, 3, 4, 5, 6, 0, 0])


class TrainingTests(unittest.TestCase):
    def setUp(self):
        # A few hundred lines make a handful of steps a pass, so the steps are made larger than the
        # real run needs (it makes about a thousand steps a pass).
        patch = mock.patch.object(model, "RATE", 0.03)
        patch.start()
        self.addCleanup(patch.stop)

    def sets(self, shift, seed=1):
        rng = np.random.default_rng(seed)
        every = [episode(rng, classes, shift=shift) for classes in runs(rng, 36)]
        return every[:24], every[24:30], every[30:]

    def accuracy(self, fit, held):
        right = total = 0
        for vectors, classes in held:
            guesses = fit.probabilities(vectors).argmax(axis=1)
            for guess, wanted in zip(guesses, classes):
                total += 1
                right += guess == wanted
        return right / total

    def test_it_learns_a_line_from_its_own_vector(self):
        train, check, held = self.sets(shift=0)
        fit = model.train(train, check, l2=1e-3, epochs=20, seed=1, say=lambda _: None)
        self.assertGreater(self.accuracy(fit, held), 0.95)

    def test_it_learns_from_the_neighbours_because_the_window_holds_them(self):
        # The vector of a line says what the line before it was, so only the window can know.
        train, check, held = self.sets(shift=1)
        fit = model.train(train, check, l2=1e-3, epochs=20, seed=1, say=lambda _: None)
        self.assertGreater(self.accuracy(fit, held), 0.95)

    def test_the_probabilities_are_five_per_line_and_add_up_to_one(self):
        train, check, held = self.sets(shift=0)
        fit = model.train(train, check, l2=1e-3, epochs=2, seed=1, say=lambda _: None)
        rows = fit.probabilities(held[0][0])
        self.assertEqual(rows.shape, (len(held[0][0]), 5))
        self.assertTrue(np.allclose(rows.sum(axis=1), 1.0, atol=1e-5))
        self.assertTrue((rows >= 0).all())

    def test_the_same_seed_gives_the_same_probabilities(self):
        train, check, held = self.sets(shift=0)
        first = model.train(train, check, l2=1e-3, epochs=3, seed=7, say=lambda _: None)
        second = model.train(train, check, l2=1e-3, epochs=3, seed=7, say=lambda _: None)
        self.assertTrue(np.array_equal(first.probabilities(held[0][0]), second.probabilities(held[0][0])))

    def test_a_line_with_no_class_is_context_only(self):
        # Lines of a class None (the labels are unsure of them) are never trained on, but they are
        # still in the window of the lines around them.
        rng = np.random.default_rng(3)
        train = []
        for classes in runs(rng, 24):
            vectors, _ = episode(rng, classes)
            train.append((vectors, [None if i % 7 == 3 else c for i, c in enumerate(classes)]))
        check = [train.pop() for _ in range(4)]
        fit = model.train(train, check, l2=1e-3, epochs=3, seed=1, say=lambda _: None)
        self.assertEqual(fit.probabilities(train[0][0]).shape[0], len(train[0][0]))

    def test_stronger_regularisation_gives_smaller_weights(self):
        train, check, _ = self.sets(shift=0)
        weak = model.train(train, check, l2=1e-5, epochs=4, seed=1, say=lambda _: None)
        strong = model.train(train, check, l2=1e-1, epochs=4, seed=1, say=lambda _: None)
        self.assertLess(np.abs(strong.weights).sum(), np.abs(weak.weights).sum())

    def test_the_class_weights_are_the_word_model_trainers(self):
        # none counts 1; a rarer class counts min(5, none / class), so ads are not drowned by talk.
        counts = [1000, 400, 100, 10, 0]
        self.assertEqual(model.class_weights(counts), [1.0, 2.5, 5.0, 5.0, 5.0])

    def test_the_fit_keeps_the_pass_with_the_lowest_loss_on_the_check_and_says_which(self):
        train, check, _ = self.sets(shift=0)
        said = []
        fit = model.train(train, check, l2=1e-3, epochs=8, seed=1, say=said.append)
        self.assertIsNotNone(fit.check_loss)
        self.assertGreaterEqual(fit.epochs, 1)
        self.assertLessEqual(fit.epochs, 8)
        self.assertTrue(any("Pass 1" in line for line in said), said)
        self.assertTrue(all("loss" in line for line in said if line.startswith("Pass")))

    def test_with_no_check_set_it_runs_every_pass_and_has_no_check_loss(self):
        train, _, _ = self.sets(shift=0)
        fit = model.train(train, [], l2=1e-3, epochs=3, seed=1, say=lambda _: None)
        self.assertIsNone(fit.check_loss)
        self.assertEqual(fit.epochs, 3)

    def test_it_refuses_nothing_to_learn_from(self):
        with self.assertRaises(ValueError):
            model.train([], [], l2=1e-3, epochs=1, seed=1, say=lambda _: None)
        vectors = np.zeros((4, 3), dtype=np.float32)
        with self.assertRaises(ValueError):
            model.train([(vectors, [None] * 4)], [], l2=1e-3, epochs=1, seed=1, say=lambda _: None)


if __name__ == "__main__":
    unittest.main()
