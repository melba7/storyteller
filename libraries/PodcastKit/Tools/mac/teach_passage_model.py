"""The classifier of the passage model: windows of five lines and a softmax regression over them.

Needs numpy only (the Mac's python-mood environment has it, so has the cloud; scikit-learn and torch
are not used here). A line is a vector from the sentence model (teach_passage_encoder.py). Its window
is the vectors of the two lines before it, the line itself and the two lines after it, side by side;
beyond an episode's edge the window holds zeros. The classifier says, for each line, how likely each
of the five classes of the word model is (teach_features.CLASSES, "none" first).

Training is mini-batch Adam on the softmax loss with an L2 penalty on the weights (not the bias),
every example's loss weighted as the word-model trainer weights it (teach_train.class_weights). After
each pass the loss on a check set of other episodes is measured, and the fit keeps the pass with the
lowest one. Lines with a class of None (the labels are unsure of them) are context only. The vectors
are standardised first, with the mean and spread of the training lines.

Run the tests: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import time

import numpy as np

from teach_train import class_weights  # noqa: F401  (the same balancing as the word model's)

CLASS_COUNT = 5
BEFORE = AFTER = 2
GROUP = 8        # episodes whose windows are built together
BATCH = 512      # lines in one step
RATE = 0.002
BETAS = (0.9, 0.999)
EPSILON = 1e-8
PATIENCE = 2     # passes without a better check loss before the fit stops


def windows(vectors):
    """For each line of an episode, its vector and those of the two lines either side, side by
    side: an array of shape (lines, 5 * dimension). Beyond the episode's edges there are zeros."""
    count, dimension = vectors.shape
    padded = np.zeros((count + BEFORE + AFTER, dimension), dtype=vectors.dtype)
    padded[BEFORE:BEFORE + count] = vectors
    return np.concatenate([padded[k:k + count] for k in range(BEFORE + AFTER + 1)], axis=1)


def softmax(scores):
    scores = scores - scores.max(axis=1, keepdims=True)
    exps = np.exp(scores)
    return exps / exps.sum(axis=1, keepdims=True)


class Fit:
    """The weights of one trained classifier and what its training said."""

    def __init__(self, mean, spread, weights, bias, check_loss, epochs, l2):
        self.mean, self.spread, self.weights, self.bias = mean, spread, weights, bias
        self.check_loss, self.epochs, self.l2 = check_loss, epochs, l2

    def probabilities(self, vectors):
        """An array of shape (lines, 5): the class probabilities of every line of an episode."""
        scores = windows(((vectors - self.mean) / self.spread).astype(np.float32)) @ self.weights
        return softmax((scores + self.bias).astype(np.float64))


def labelled(episodes):
    """The training lines among `episodes` (vectors, classes): those with a class."""
    return sum(1 for _, classes in episodes for c in classes if c is not None)


def standardiser(episodes):
    """The mean and spread of every dimension over all lines of the episodes."""
    total = squares = 0.0
    count = 0
    for vectors, _ in episodes:
        values = vectors.astype(np.float64)
        total = total + values.sum(axis=0)
        squares = squares + (values * values).sum(axis=0)
        count += len(values)
    mean = total / count
    spread = np.sqrt(np.maximum(squares / count - mean * mean, 0.0)) + 1e-6
    return mean.astype(np.float32), spread.astype(np.float32)


def examples(episodes, mean, spread):
    """The windows of the lines that have a class, and those classes, for some episodes."""
    parts, wanted = [], []
    for vectors, classes in episodes:
        keep = [i for i, c in enumerate(classes) if c is not None]
        if not keep:
            continue
        made = windows(((vectors - mean) / spread).astype(np.float32))
        parts.append(made[keep])
        wanted.append(np.array([classes[i] for i in keep], dtype=np.int64))
    if not parts:
        return np.zeros((0, 0), dtype=np.float32), np.zeros(0, dtype=np.int64)
    return np.concatenate(parts), np.concatenate(wanted)


def weighted_loss(fit, episodes, cost):
    """The mean loss per labelled line of the episodes, every line counting as much as its class
    weighs. None when there is no line to judge."""
    total = 0.0
    count = 0
    for vectors, classes in episodes:
        rows = fit.probabilities(vectors)
        for i, c in enumerate(classes):
            if c is not None:
                total += -cost[c] * np.log(max(rows[i, c], 1e-12))
                count += 1
    return total / count if count else None


def train(training, checking, l2, epochs, seed, say=print):
    """Trains on `training` and judges each pass on `checking`; both are lists of (vectors, classes)
    with vectors of shape (lines, dimension) and a class index or None for every line. Returns the
    Fit of the best pass (the last one when there is no check set). Raises ValueError when no
    training line has a class."""
    if not training or labelled(training) == 0:
        raise ValueError("There is no marked line to learn from.")
    mean, spread = standardiser(training)
    dimension = training[0][0].shape[1]
    counts = [0] * CLASS_COUNT
    for _, classes in training:
        for c in classes:
            if c is not None:
                counts[c] += 1
    cost = np.array(class_weights(counts), dtype=np.float32)
    rng = np.random.default_rng(seed)
    weights = np.zeros(((BEFORE + AFTER + 1) * dimension, CLASS_COUNT), dtype=np.float32)
    bias = np.zeros(CLASS_COUNT, dtype=np.float32)
    first = [np.zeros_like(weights), np.zeros_like(bias)]
    second = [np.zeros_like(weights), np.zeros_like(bias)]
    step = 0
    best = None
    stale = 0
    for number in range(1, epochs + 1):
        started = time.monotonic()
        total = 0.0
        seen = 0
        order = rng.permutation(len(training))
        for begin in range(0, len(order), GROUP):
            x, y = examples([training[i] for i in order[begin:begin + GROUP]], mean, spread)
            for batch in np.array_split(rng.permutation(len(y)), max(1, len(y) // BATCH)):
                if not len(batch):
                    continue
                rows = softmax(x[batch] @ weights + bias)
                heavy = cost[y[batch]]
                total += float((-heavy * np.log(np.maximum(rows[np.arange(len(batch)), y[batch]], 1e-12))).sum())
                seen += len(batch)
                rows[np.arange(len(batch)), y[batch]] -= 1
                rows *= (heavy / len(batch))[:, None]
                gradients = [x[batch].T @ rows + l2 * weights, rows.sum(axis=0)]
                step += 1
                for parameter, gradient, m, v in zip((weights, bias), gradients, first, second):
                    m *= BETAS[0]
                    m += (1 - BETAS[0]) * gradient
                    v *= BETAS[1]
                    v += (1 - BETAS[1]) * gradient * gradient
                    parameter -= RATE * (m / (1 - BETAS[0] ** step)) / (
                        np.sqrt(v / (1 - BETAS[1] ** step)) + EPSILON)
        current = Fit(mean, spread, weights.copy(), bias.copy(), None, number, l2)
        current.check_loss = weighted_loss(current, checking, cost) if checking else None
        say("Pass %d of %d (L2 %g): loss %.4f on the training lines%s, %.1f seconds."
            % (number, epochs, l2, total / max(seen, 1),
               "" if current.check_loss is None else ", %.4f on the check episodes" % current.check_loss,
               time.monotonic() - started))
        if current.check_loss is None:
            best = current
        elif best is None or current.check_loss < best.check_loss:
            best, stale = current, 0
        else:
            stale += 1
            if stale >= PATIENCE:
                break
    return best
