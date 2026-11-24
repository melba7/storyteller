"""The sentence model of the passage model, and the cache of the vectors it gives.

Needs numpy; MiniLM also needs torch and transformers, which the Mac's python-mood environment has
(libraries/LofiScoreKit/Tools/mac/finetune.sh makes it). The mood work loads the same model the same
way (Tools/eval/finetune_mood.py): sentence-transformers/all-MiniLM-L6-v2 through AutoTokenizer and
AutoModel, its Hugging Face files kept in ~/Storyteller Lofi/.cache/huggingface (the launcher sets
HF_HOME there). A line becomes 384 numbers: the mean of the model's token vectors, scaled to length 1,
which is what sentence-transformers gives for this model.

An encoder is any object with `tag` (a short name that goes into cache file names), `dimension` and
`encode(texts)`, which returns a float32 array of shape (len(texts), dimension). The tests use a fake
one (teach_passage_testing.py), so nothing else in the passage model needs torch.

The cache keeps one file for each episode in <teaching folder>/passage-cache/, named by the episode,
a fingerprint of its lines' text and the encoder's tag, so changed text or another encoder is never
read from an old file. It is only a speed-up: a file that is damaged or of the wrong size is made
again, and a folder that cannot be written does not stop the run.

Run the tests: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import hashlib
import os
import re
import tempfile

import numpy as np

import teach_store

MODEL = "sentence-transformers/all-MiniLM-L6-v2"
TAG = "minilm-l6-v2"
DIMENSION = 384
MAX_TOKENS = 256
BATCH = 128
CACHE = "passage-cache"
# Two sentences that mean nearly the same (an ad read two ways) and one that does not.
PROBES = ("This episode is brought to you by Acme. Use promo code SHOW for twenty percent off.",
          "Today's show is sponsored by Acme, so visit acme dot com and enter the code SHOW.",
          "We walked along the river this morning and the weather was calm.")
PROBE_MARGIN = 0.1


def batches_by_length(texts, size):
    """Lists of at most `size` indexes of `texts`, the shortest texts first, so that a batch holds
    texts of alike length and little of it is padding. Every index is in exactly one batch."""
    order = sorted(range(len(texts)), key=lambda i: len(texts[i]))
    return [order[start:start + size] for start in range(0, len(order), size)]


def check_probes(embed):
    """Raises teach_store.Problem unless `embed` (a function from a list of texts to an array)
    gives vectors of length 1 and the right size, and the two ad sentences are nearer to each
    other than to the sentence about the river. A model that is not the one it should be, or that
    is used the wrong way, would read every line wrongly without any other sign."""
    rows = np.asarray(embed(list(PROBES)))
    if rows.shape != (len(PROBES), DIMENSION) \
            or not np.allclose(np.linalg.norm(rows, axis=1), 1.0, atol=0.01):
        raise teach_store.Problem(
            "The sentence model does not give %d numbers of length 1 for a line (it gave an array "
            "of shape %s), so it is not the model this run was made for." % (DIMENSION, rows.shape))
    if rows[0] @ rows[1] < rows[0] @ rows[2] + PROBE_MARGIN:
        raise teach_store.Problem(
            "The sentence model does not put two ways of reading the same ad nearer to each other "
            "than to a sentence about a river, so it does not read meaning as expected.")


class MiniLM:
    """sentence-transformers/all-MiniLM-L6-v2 with torch. It is loaded on the first line it is
    asked to read, so a run that finds every vector in the cache does not need torch at all."""

    tag = TAG
    dimension = DIMENSION

    def __init__(self, say=print):
        self.say = say
        self.model = None

    def _load(self):
        if self.model is not None:
            return
        try:
            import torch
            from transformers import AutoModel, AutoTokenizer
        except ImportError as error:
            raise teach_store.Problem(
                "The sentence model needs torch and transformers. Run this with the python "
                "of the python-mood environment in ~/Storyteller Lofi (finetune.sh makes it): %s"
                % error)
        self.say("Loading the sentence model %s." % MODEL)
        try:
            self.tokenizer = AutoTokenizer.from_pretrained(MODEL)
            self.model = AutoModel.from_pretrained(MODEL).eval()
        except (OSError, ValueError) as error:
            raise teach_store.Problem(
                "The sentence model %s could not be loaded: %s. The first run downloads it once "
                "(about 90 MB) unless the mood work already did." % (MODEL, error))
        self.torch = torch
        self.device = torch.device("mps" if torch.backends.mps.is_available()
                                   else "cuda" if torch.cuda.is_available() else "cpu")
        self.model.to(self.device)
        try:
            check_probes(self._embed)
        except teach_store.Problem:
            self.model = None  # the next line asked is checked again, not trusted
            raise
        self.say("The sentence model is ready (on %s)." % self.device)

    def _embed(self, texts):
        """One batch: the mean of the token vectors, scaled to length 1, as float32 numpy."""
        with self.torch.inference_mode():
            batch = self.tokenizer(texts, padding=True, truncation=True, max_length=MAX_TOKENS,
                                   return_tensors="pt").to(self.device)
            hidden = self.model(**batch).last_hidden_state
            mask = batch["attention_mask"].unsqueeze(-1).to(hidden.dtype)
            pooled = (hidden * mask).sum(1) / mask.sum(1).clamp(min=1e-6)
            pooled = self.torch.nn.functional.normalize(pooled, dim=1)
        return pooled.cpu().numpy().astype(np.float32)

    def encode(self, texts):
        out = np.zeros((len(texts), DIMENSION), dtype=np.float32)
        if not texts:
            return out
        self._load()
        for batch in batches_by_length(texts, BATCH):
            out[batch] = self._embed([texts[i] for i in batch])
        return out


def fingerprint(texts):
    """A short hash of the lines' text, so the cache notices a changed transcript."""
    digest = hashlib.sha256()
    for text in texts:
        digest.update(text.encode("utf-8"))
        digest.update(b"\n")
    return digest.hexdigest()[:16]


def cached_vectors(folder, encoder, identifier, texts):
    """(vectors, from_cache) for the lines of one episode: read from the cache when it holds them,
    otherwise made by the encoder and kept. The older file of the episode goes once the new one is
    written."""
    if not texts:
        return np.zeros((0, encoder.dimension), dtype=np.float32), False
    directory = os.path.join(folder, CACHE)
    name = "%s.%s.%s.npy" % (identifier, fingerprint(texts), encoder.tag)
    try:
        found = np.load(os.path.join(directory, name), allow_pickle=False)
        if found.dtype == np.float32 and found.shape == (len(texts), encoder.dimension):
            return found, True
    except (OSError, ValueError, EOFError):
        pass
    vectors = np.asarray(encoder.encode(texts), dtype=np.float32)
    try:
        os.makedirs(directory, exist_ok=True)
        handle, temporary = tempfile.mkstemp(dir=directory, prefix=".", suffix=".part")
        try:
            with os.fdopen(handle, "wb") as out:
                np.save(out, vectors)
            os.replace(temporary, os.path.join(directory, name))
        except BaseException:
            if os.path.exists(temporary):
                os.remove(temporary)
            raise
        older = re.compile(r"^%s\.[0-9a-f]{16}\..+\.npy$" % re.escape(identifier))
        for other in os.listdir(directory):
            if other != name and older.match(other):
                os.remove(os.path.join(directory, other))
    except OSError:
        pass
    return vectors, False
