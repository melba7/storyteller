"""Tests for teach_passage_encoder.py: the sentence model's wrapper (without torch: its batching, its
check on three probe sentences and its plain sentence when torch is missing) and the cache of line
vectors kept in the teaching folder. Needs numpy.
Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import os
import shutil
import sys
import tempfile
import unittest
from unittest import mock

import numpy as np

import teach_passage_encoder as enc
import teach_store
from teach_passage_testing import FakeEncoder


class BatchTests(unittest.TestCase):
    def test_batches_hold_lines_of_alike_length_and_cover_every_line_once(self):
        texts = ["a" * n for n in (50, 3, 20, 4, 49, 21, 2, 48)]
        batches = enc.batches_by_length(texts, 3)
        self.assertEqual(sorted(i for batch in batches for i in batch), list(range(8)))
        self.assertTrue(all(len(batch) <= 3 for batch in batches))
        lengths = [[len(texts[i]) for i in batch] for batch in batches]
        self.assertEqual(lengths, [[2, 3, 4], [20, 21, 48], [49, 50]])

    def test_no_text_gives_no_batch(self):
        self.assertEqual(enc.batches_by_length([], 8), [])


class StubModel(enc.MiniLM):
    """A MiniLM whose model is a function: the vector of a text is made from its characters."""

    def __init__(self, probes=None):
        super().__init__(say=lambda _: None)
        self.seen = []
        self.probes = probes

    def _load(self):
        pass

    def _embed(self, texts):
        self.seen.append(list(texts))
        rows = np.zeros((len(texts), enc.DIMENSION), dtype=np.float32)
        for row, text in enumerate(texts):
            if self.probes and text in self.probes:
                rows[row] = self.probes[text]
            else:
                rows[row, len(text) % enc.DIMENSION] = 1.0
        return rows


class MiniLMTests(unittest.TestCase):
    def test_vectors_come_back_in_the_order_of_the_texts_whatever_the_batches(self):
        model = StubModel()
        texts = ["x" * n for n in (30, 2, 11, 7, 25, 3)]
        out = model.encode(texts)
        self.assertEqual(out.shape, (6, enc.DIMENSION))
        self.assertEqual([int(row.argmax()) for row in out], [30, 2, 11, 7, 25, 3])

    def test_an_empty_list_gives_an_empty_array_of_the_right_width(self):
        self.assertEqual(StubModel().encode([]).shape, (0, enc.DIMENSION))

    def test_it_has_a_tag_and_a_dimension_for_the_cache(self):
        self.assertEqual(enc.MiniLM.dimension, 384)
        self.assertIn("minilm", enc.MiniLM.tag)

    def test_without_torch_it_says_in_a_sentence_where_to_run_it(self):
        with mock.patch.dict(sys.modules, {"torch": None}):
            with self.assertRaises(teach_store.Problem) as caught:
                enc.MiniLM(say=lambda _: None).encode(["hello"])
        self.assertIn("python-mood", str(caught.exception))
        self.assertIn("torch", str(caught.exception))

    def test_the_check_passes_when_a_paraphrase_is_nearer_than_an_unrelated_sentence(self):
        a, b, c = (np.zeros(enc.DIMENSION, dtype=np.float32) for _ in range(3))
        a[0], b[0], b[1], c[2] = 1.0, 0.8, 0.6, 1.0
        enc.check_probes(lambda texts: np.stack([a, b, c]))

    def test_the_check_stops_a_model_that_does_not_read_meaning(self):
        a, b, c = (np.zeros(enc.DIMENSION, dtype=np.float32) for _ in range(3))
        a[0], b[1], c[0] = 1.0, 1.0, 1.0
        with self.assertRaises(teach_store.Problem) as caught:
            enc.check_probes(lambda texts: np.stack([a, b, c]))
        self.assertIn("sentence model", str(caught.exception))

    def test_the_check_stops_vectors_that_are_not_of_length_one_or_the_wrong_size(self):
        short = np.zeros((3, 10), dtype=np.float32)
        with self.assertRaises(teach_store.Problem):
            enc.check_probes(lambda texts: short)
        long = np.zeros((3, enc.DIMENSION), dtype=np.float32)
        long[:, 0] = 2.0
        with self.assertRaises(teach_store.Problem):
            enc.check_probes(lambda texts: long)


class CacheTests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.folder, True)
        self.encoder = FakeEncoder()
        self.texts = ["brought to you by acme", "we walked along the river", "use promo code show"]

    def names(self):
        found = os.path.join(self.folder, enc.CACHE)
        return sorted(os.listdir(found)) if os.path.isdir(found) else []

    def test_the_first_time_it_embeds_and_keeps_the_vectors_the_second_time_it_reads_them(self):
        first, cached = enc.cached_vectors(self.folder, self.encoder, "e1", self.texts)
        self.assertFalse(cached)
        self.assertEqual(self.encoder.calls, 1)
        second, cached = enc.cached_vectors(self.folder, self.encoder, "e1", self.texts)
        self.assertTrue(cached)
        self.assertEqual(self.encoder.calls, 1)
        self.assertTrue(np.array_equal(first, second))
        self.assertEqual(first.dtype, np.float32)

    def test_the_file_is_named_by_episode_text_and_encoder_and_nothing_is_left_half_written(self):
        enc.cached_vectors(self.folder, self.encoder, "e1", self.texts)
        names = self.names()
        self.assertEqual(len(names), 1)
        self.assertTrue(names[0].startswith("e1."), names)
        self.assertTrue(names[0].endswith("." + self.encoder.tag + ".npy"), names)
        self.assertFalse([n for n in names if n.endswith(".part")])

    def test_other_text_is_embedded_again_and_the_old_file_goes(self):
        enc.cached_vectors(self.folder, self.encoder, "e1", self.texts)
        enc.cached_vectors(self.folder, self.encoder, "e2", self.texts)
        _, cached = enc.cached_vectors(self.folder, self.encoder, "e1", self.texts + ["one more line"])
        self.assertFalse(cached)
        names = self.names()
        self.assertEqual(len([n for n in names if n.startswith("e1.")]), 1)
        self.assertEqual(len([n for n in names if n.startswith("e2.")]), 1)

    def test_a_damaged_or_wrong_sized_file_is_embedded_again(self):
        enc.cached_vectors(self.folder, self.encoder, "e1", self.texts)
        path = os.path.join(self.folder, enc.CACHE, self.names()[0])
        with open(path, "wb") as f:
            f.write(b"not an array")
        vectors, cached = enc.cached_vectors(self.folder, self.encoder, "e1", self.texts)
        self.assertFalse(cached)
        self.assertEqual(vectors.shape, (3, self.encoder.dimension))
        with open(path, "wb") as f:
            np.save(f, np.zeros((2, self.encoder.dimension), dtype=np.float32))
        vectors, cached = enc.cached_vectors(self.folder, self.encoder, "e1", self.texts)
        self.assertFalse(cached)
        self.assertEqual(vectors.shape, (3, self.encoder.dimension))

    def test_another_encoder_does_not_read_this_ones_vectors(self):
        enc.cached_vectors(self.folder, self.encoder, "e1", self.texts)
        other = FakeEncoder(tag="other")
        _, cached = enc.cached_vectors(self.folder, other, "e1", self.texts)
        self.assertFalse(cached)

    def test_an_episode_with_no_lines_has_no_file(self):
        vectors, _ = enc.cached_vectors(self.folder, self.encoder, "e1", [])
        self.assertEqual(vectors.shape, (0, self.encoder.dimension))
        self.assertEqual(self.names(), [])

    def test_a_folder_that_cannot_be_written_still_gives_the_vectors(self):
        blocked = os.path.join(self.folder, enc.CACHE)
        with open(blocked, "w") as f:
            f.write("a file where the cache folder should be")
        vectors, cached = enc.cached_vectors(self.folder, self.encoder, "e1", self.texts)
        self.assertFalse(cached)
        self.assertEqual(vectors.shape, (3, self.encoder.dimension))


if __name__ == "__main__":
    unittest.main()
