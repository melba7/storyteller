"""A stand-in for the sentence model that the tests of the passage model share. Not a test itself.

Run the tests: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import re
import zlib

import numpy as np


class FakeEncoder:
    """The same interface as teach_passage_encoder.MiniLM, with no torch: a line becomes the
    hashed counts of its words, scaled to length 1. Two lines that share words are near each other
    and the same text always gives the same vector, which is all a test needs. `calls` counts the
    times it was asked, `lines` how many lines it embedded."""

    def __init__(self, tag="fake-hash", dimension=32):
        self.tag = tag
        self.dimension = dimension
        self.calls = 0
        self.lines = 0
        self.fail_on_call = None

    def encode(self, texts):
        self.calls += 1
        if self.fail_on_call == self.calls:
            raise RuntimeError("the fake encoder was stopped")
        self.lines += len(texts)
        out = np.zeros((len(texts), self.dimension), dtype=np.float32)
        for row, text in enumerate(texts):
            for word in re.findall(r"[a-z0-9']+", text.lower()):
                out[row, zlib.crc32(word.encode()) % self.dimension] += 1.0
            norm = float(np.sqrt((out[row] ** 2).sum()))
            if norm:
                out[row] /= norm
        return out
