#!/usr/bin/env python3
"""Fine-tune a small language model to read the mood of a passage.

The shipped Fast engine is a softmax head on Apple's word embeddings. This
tries the next step up: a small pretrained transformer (by default
sentence-transformers/all-MiniLM-L6-v2, 22.7M parameters, Apache-2.0) whose
every layer is tuned on the labelled windows, with the same input as the
Fast engine (the newest 160 words of a window, and the 160 before them at
weight 0.2). It runs on Mo's Mac (Apple GPU through PyTorch's "mps" device)
inside a virtual environment in "~/Storyteller Lofi"; see
Tools/mac/finetune.sh, which runs every step below.

    # out-of-fold predictions on every labelled book, in lofi-train oof's format
    python finetune_mood.py oof --data Tools/data/work/train --sets SETS.jsonl ... --people P.jsonl --out oof-lm.jsonl
    # one model on every labelled book
    python finetune_mood.py final --data Tools/data/work/train --sets SETS.jsonl ... --people P.jsonl --variant soft --out MODEL_DIR
    # readings for lofi-eval-style windows (e.g. EmoBank's), one file per lean
    python finetune_mood.py read --model MODEL_DIR --in windows.jsonl --out PREFIX [--leans 1:0:0.3,...]
    # Core ML for the app, with one lean folded into the head
    python finetune_mood.py coreml --model MODEL_DIR --lean 1:0:0.3 --out DIR --name LofiMood-lm-soft

Variants: "hard" learns the one best mood; "soft" lets the other moods that
would also suit a window (the `accept` lists in --sets files) share 30% of
its target. "-mtX" (e.g. "soft-mt1") also teaches the encoder people's
ratings while it learns the moods: every step adds X times the squared error
of a small side head predicting how pleasant and how energetic readers rated
a batch of EmoBank's NON-fiction sentences (--people, from `emobank.py
people`; its fiction sentences stay the test and never train anything).

Leans ("V:A:P"), applied after training and folded into the mood head, so
the exported model is unchanged in shape: like the word recipes' people
lean, each mood's logit gains V × the mood's standardised valence anchor ×
the standardised predicted pleasantness of the text (A likewise for energy),
where the prediction is a ridge regression from the encoder's pooled
features to EmoBank's non-fiction ratings; and like the prior shift, each
mood's bias loses P × the log of its share of the training labels, which
lifts the rare moods. OOF rows are named "lm-VARIANT[-vV][-aA][-pP]-e0.2",
read with the earlier words at weight 0.2. Folds are whole books, as in
`lofi-train oof`, so rows compare window by window with its recipes
(Tools/eval/oof_compare.py).

--base test-tiny builds a tiny random model and vocabulary from the data,
for checking the pipeline without downloads; its numbers mean nothing.
"""
from __future__ import annotations

import argparse
import collections
import json
import math
import os
import random
import sys
import time

MOODS = ["calm", "cozy", "playful", "hopeful", "melancholy", "mysterious", "tense", "somber", "romantic", "dreamy", "adventurous"]
ANCHORS = {  # MoodBucket.anchor (valence, arousal)
    "calm": (0.25, 0.15), "cozy": (0.55, 0.30), "playful": (0.60, 0.62), "hopeful": (0.70, 0.82),
    "melancholy": (-0.50, 0.20), "mysterious": (-0.10, 0.50), "tense": (-0.55, 0.85), "somber": (-0.70, 0.45),
    "romantic": (0.75, 0.40), "dreamy": (0.45, 0.45), "adventurous": (0.35, 0.78),
}
CHUNK_WORDS = 160          # ClassifierInput.defaultChunkWords
MIN_EARLIER_WORDS = 40     # ClassifierInput.minimumEarlierWords
DEFAULT_BASE = "sentence-transformers/all-MiniLM-L6-v2"


def note(msg: str) -> None:
    print(f"[{time.strftime('%H:%M:%S')}] {msg}", file=sys.stderr, flush=True)


# ---------------------------------------------------------------- data

def read_json_list(path: str) -> list:
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def load_examples(data_dir: str) -> tuple[list[dict], dict[str, str]]:
    """Every distinct labelled window of a `lofi-train export` folder (train,
    valid and test; balancing copies dropped), plus the earlier words."""
    seen: set[str] = set()
    out: list[dict] = []
    for name in ("train.json", "valid.json", "test.json"):
        path = os.path.join(data_dir, name)
        if not os.path.exists(path):
            continue
        for e in read_json_list(path):
            if e["id"] in seen:
                continue
            seen.add(e["id"])
            if e["label"] not in MOODS:
                continue
            out.append({"id": e["id"], "book": e["book"], "text": e["text"], "label": e["label"]})
    earlier_path = os.path.join(data_dir, "earlier.json")
    earlier = {}
    if os.path.exists(earlier_path):
        with open(earlier_path, encoding="utf-8") as f:
            earlier = json.load(f)
    return out, earlier


def load_accept(paths: list[str]) -> dict[str, list[str]]:
    accept: dict[str, list[str]] = {}
    for path in paths:
        with open(path, encoding="utf-8") as f:
            for line in f:
                if line.strip():
                    r = json.loads(line)
                    if r.get("accept"):
                        accept[r["id"]] = [m for m in r["accept"] if m in MOODS]
    return accept


def target(label: str, accept: list[str] | None, variant: str, share: float = 0.3) -> list[float]:
    t = [0.0] * len(MOODS)
    others = [m for m in (accept or []) if m != label]
    if variant == "soft" and others:
        t[MOODS.index(label)] = 1 - share
        for m in others:
            t[MOODS.index(m)] += share / len(others)
    else:
        t[MOODS.index(label)] = 1.0
    return t


def words(text: str) -> list[str]:
    return text.split()


def recent_chunk(text: str) -> str:
    return " ".join(words(text)[-CHUNK_WORDS:])


def earlier_chunk(text: str) -> str:
    w = words(text)
    return " ".join(w[:-CHUNK_WORDS][-CHUNK_WORDS:]) if len(w) > CHUNK_WORDS else ""



DEFAULT_LEANS = "0:0:0,0:0:0.3,0:0:0.6,0.5:0:0.3,1:0:0.3,2:0:0.3,1:0:0.6,2:0:0.6,1:0.5:0.3"


def load_people(path: str | None) -> list[dict]:
    """EmoBank sentences that may train (`emobank.py people`): non-fiction only."""
    if not path:
        return []
    rows = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            if line.strip():
                r = json.loads(line)
                if r.get("category") != "fiction" and r.get("text"):
                    rows.append(r)
    return rows


def parse_variant(v: str) -> tuple[str, float]:
    """"soft-mt1" -> ("soft", 1.0)."""
    if "-mt" in v:
        base, mt = v.split("-mt", 1)
        return base, float(mt)
    return v, 0.0


def parse_leans(spec: str) -> list[tuple[float, float, float]]:
    out = []
    for part in spec.split(","):
        if part.strip():
            v, a, p = (float(x) for x in part.split(":"))
            out.append((v, a, p))
    return out


def lean_suffix(lean: tuple[float, float, float]) -> str:
    v, a, p = lean
    return (f"-v{v:g}" if v else "") + (f"-a{a:g}" if a else "") + (f"-p{p:g}" if p else "")


# ---------------------------------------------------------------- model

def torch_modules():
    import torch  # noqa: F401  (imported lazily so --help works without it)
    from torch import nn
    return torch, nn


def pick_device(torch):
    if torch.backends.mps.is_available():
        return torch.device("mps")
    if torch.cuda.is_available():
        return torch.device("cuda")
    return torch.device("cpu")


def tiny_tokenizer(texts: list[str], folder: str):
    """A small WordPiece vocabulary from the data (test-tiny only)."""
    from transformers import BertTokenizerFast
    counts = collections.Counter(w.strip(".,;:!?\"'()[]-").lower() for t in texts for w in t.split())
    vocab = ["[PAD]", "[UNK]", "[CLS]", "[SEP]", "[MASK]"] + [w for w, _ in counts.most_common(4000) if w]
    os.makedirs(folder, exist_ok=True)
    path = os.path.join(folder, "vocab.txt")
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(dict.fromkeys(vocab)) + "\n")
    # from_pretrained on the folder works in transformers 4 and 5 alike.
    return BertTokenizerFast.from_pretrained(folder, do_lower_case=True)


def mood_net_class():
    torch, nn = torch_modules()

    class MoodNet(nn.Module):
        """Mean-pooled encoder (as sentence-transformers trains it), a linear
        mood head, and a side head for people's ratings (-mt variants)."""

        def __init__(self, encoder):
            super().__init__()
            self.encoder = encoder
            self.drop = nn.Dropout(0.1)
            self.head = nn.Linear(encoder.config.hidden_size, len(MOODS))
            self.people = nn.Linear(encoder.config.hidden_size, 2)

        def pooled(self, input_ids, attention_mask, extended=None):
            mask = attention_mask if extended is None else extended
            hidden = self.encoder(input_ids=input_ids, attention_mask=mask).last_hidden_state
            m = attention_mask.unsqueeze(-1).to(hidden.dtype)
            return (hidden * m).sum(1) / m.sum(1).clamp(min=1e-6)

        def forward(self, input_ids, attention_mask):
            return self.head(self.drop(self.pooled(input_ids, attention_mask)))

    return MoodNet


def build(base: str, texts_for_tiny: list[str], work: str):
    from transformers import AutoModel, AutoTokenizer, BertConfig, BertModel
    MoodNet = mood_net_class()
    if base == "test-tiny":
        tok = tiny_tokenizer(texts_for_tiny, os.path.join(work, "test-tiny-vocab"))

        def make_encoder():
            return BertModel(BertConfig(vocab_size=tok.vocab_size, hidden_size=32, num_hidden_layers=2,
                                        num_attention_heads=2, intermediate_size=64, max_position_embeddings=512))
    else:
        tok = AutoTokenizer.from_pretrained(base)

        def make_encoder():
            return AutoModel.from_pretrained(base)
    tok.truncation_side = "left"  # keep the newest words
    return tok, (lambda: MoodNet(make_encoder()))


def encode(tok, texts: list[str], max_len: int) -> list[list[int]]:
    return tok(texts, truncation=True, max_length=max_len)["input_ids"]


def batches(torch, ids: list[list[int]], order: list[int], size: int, pad: int, device):
    for start in range(0, len(order), size):
        idx = order[start:start + size]
        n = max(len(ids[i]) for i in idx)
        x = torch.full((len(idx), n), pad, dtype=torch.long)
        mask = torch.zeros((len(idx), n), dtype=torch.long)
        for row, i in enumerate(idx):
            x[row, :len(ids[i])] = torch.tensor(ids[i], dtype=torch.long)
            mask[row, :len(ids[i])] = 1
        yield idx, x.to(device), mask.to(device)


def train(make_model, tok, ids: list[list[int]], targets: list[list[float]], args, seed: int,
          people_ids: list[list[int]] | None = None, people_y: list[list[float]] | None = None, mt: float = 0.0):
    torch, nn = torch_modules()
    torch.manual_seed(seed)
    random.seed(seed)
    device = pick_device(torch)
    model = make_model().to(device)
    model.train()
    opt = torch.optim.AdamW(model.parameters(), lr=args.lr, weight_decay=0.01)
    steps_per_epoch = math.ceil(len(ids) / args.batch)
    total = steps_per_epoch * args.epochs
    if args.max_steps:
        total = min(total, args.max_steps)
    warm = max(1, int(0.06 * total))
    sched = torch.optim.lr_scheduler.LambdaLR(
        opt, lambda s: min((s + 1) / warm, max(0.0, (total - s) / max(1, total - warm))))
    y_all = torch.tensor(targets, dtype=torch.float32)
    use_people = mt > 0 and people_ids
    if use_people:
        py_all = torch.tensor(people_y, dtype=torch.float32)
        people_order: list[int] = []
    rng = random.Random(seed)
    step = 0
    started = time.time()
    for epoch in range(args.epochs):
        order = list(range(len(ids)))
        rng.shuffle(order)
        running, running_people, k = 0.0, 0.0, 0
        for k, (idx, x, mask) in enumerate(batches(torch, ids, order, args.batch, tok.pad_token_id, device)):
            logits = model(x, mask)
            y = y_all[idx].to(device)
            loss = -(y * torch.log_softmax(logits, dim=-1)).sum(-1).mean()
            running += loss.item()
            if use_people:
                if len(people_order) < args.batch:
                    fresh = list(range(len(people_ids)))
                    rng.shuffle(fresh)
                    people_order += fresh
                pidx, people_order = people_order[:args.batch], people_order[args.batch:]
                _, px, pmask = next(batches(torch, people_ids, pidx, len(pidx), tok.pad_token_id, device))
                pred = model.people(model.drop(model.pooled(px, pmask)))
                people_loss = ((pred - py_all[pidx].to(device)) ** 2).mean()
                loss = loss + mt * people_loss
                running_people += people_loss.item()
            opt.zero_grad()
            loss.backward()
            torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0)
            opt.step()
            sched.step()
            step += 1
            if step >= total:
                break
        extra = f", people {running_people / max(1, k + 1):.3f}" if use_people else ""
        note(f"    epoch {epoch + 1}: loss {running / max(1, k + 1):.3f}{extra} ({time.time() - started:.0f} s)")
        if step >= total:
            break
    model.eval()
    return model


def infer(model, tok, ids: list[list[int]], batch: int):
    """Mood logits and pooled features, as numpy arrays in input order."""
    import numpy as np
    torch, _ = torch_modules()
    device = next(model.parameters()).device
    logits = np.zeros((len(ids), len(MOODS)), dtype=np.float64)
    pooled = None
    order = sorted(range(len(ids)), key=lambda i: len(ids[i]))
    with torch.no_grad():
        for idx, x, mask in batches(torch, ids, order, batch, tok.pad_token_id, device):
            p = model.pooled(x, mask)
            lg = model.head(p)
            p = p.float().cpu().numpy()
            if pooled is None:
                pooled = np.zeros((len(ids), p.shape[1]), dtype=np.float64)
            pooled[idx] = p
            logits[idx] = lg.float().cpu().numpy()
    return logits, pooled


# ---------------------------------------------------------------- leans

def ridge(x, y, l2: float):
    """Ridge on standardised features; weights mapped back to raw features."""
    import numpy as np
    mean = x.mean(0)
    scale = np.maximum(x.std(0), 1e-8)
    z = (x - mean) / scale
    n, d = z.shape
    w = np.linalg.solve(z.T @ z / n + l2 * np.eye(d), z.T @ (y - y.mean()) / n)
    raw = w / scale
    return raw, float(y.mean() - raw @ mean)


def fit_people(pooled, rows: list[dict]) -> dict:
    """Valence and arousal from pooled features, the penalty chosen by 5-fold
    cross-validation over EmoBank documents (as `lofi-train people` does)."""
    import numpy as np
    docs = sorted({r["doc"] for r in rows})
    rng = random.Random(11)
    rng.shuffle(docs)
    fold = np.array([{d: i % 5 for i, d in enumerate(docs)}[r["doc"]] for r in rows])
    out = {}
    for key in ("v", "a"):
        y = np.array([float(r[key]) for r in rows])
        best = (None, -2.0)
        for l2 in (0.01, 0.1, 1.0, 10.0):
            pred = np.zeros(len(rows))
            for f in range(5):
                tr, te = fold != f, fold == f
                w, b = ridge(pooled[tr], y[tr], l2)
                pred[te] = pooled[te] @ w + b
            r = float(np.corrcoef(pred, y)[0, 1])
            if r > best[1]:
                best = (l2, r)
        w, b = ridge(pooled, y, best[0])
        out[key] = {"w": w.tolist(), "b": b, "l2": best[0], "r_heldout_documents": round(best[1], 3)}
    return out


def lean_parts(people: dict, train_pooled, train_labels: list[str]) -> dict:
    """Everything a lean needs besides its strengths: the ratings' spread over
    the training windows, the moods' standardised anchors and log shares."""
    import numpy as np
    parts = {"people": people}
    for key, axis in (("v", 0), ("a", 1)):
        s = train_pooled @ np.array(people[key]["w"]) + people[key]["b"]
        parts[f"mu_{key}"] = float(s.mean())
        parts[f"sd_{key}"] = float(max(s.std(), 1e-8))
        anchors = np.array([ANCHORS[m][axis] for m in MOODS])
        parts[f"za_{key}"] = ((anchors - anchors.mean()) / max(anchors.std(), 1e-12)).tolist()
    counts = collections.Counter(train_labels)
    n = max(1, len(train_labels))
    parts["log_share"] = [math.log(max(counts[m], 0.5) / n) for m in MOODS]
    return parts


def lean_head(weight, bias, parts: dict, lean: tuple[float, float, float]):
    """The mood head (weight [moods, features], bias [moods]) with a lean folded in."""
    import numpy as np
    sv, sa, sp = lean
    w = np.array(weight, dtype=np.float64).copy()
    b = np.array(bias, dtype=np.float64).copy()
    for key, s in (("v", sv), ("a", sa)):
        if s:
            za = np.array(parts[f"za_{key}"])
            pw = np.array(parts["people"][key]["w"]) / parts[f"sd_{key}"]
            pb = (parts["people"][key]["b"] - parts[f"mu_{key}"]) / parts[f"sd_{key}"]
            w += s * np.outer(za, pw)
            b += s * za * pb
    if sp:
        b -= sp * np.array(parts["log_share"])
    return w, b


def softmax_rows(z):
    import numpy as np
    z = z - z.max(1, keepdims=True)
    e = np.exp(z)
    return e / e.sum(1, keepdims=True)


def probabilities(pooled, weight, bias):
    return softmax_rows(pooled @ weight.T + bias)


def read_windows(model, tok, recent: list[str], earlier: list[str], args):
    """Pooled features of the newest words and of the words before them
    (None where there are fewer than 40 earlier words)."""
    _, p_recent = infer(model, tok, encode(tok, recent, args.max_len), args.batch * 2)
    has = [i for i, t in enumerate(earlier) if len(words(t)) >= MIN_EARLIER_WORDS]
    p_earlier = None
    if has:
        _, got = infer(model, tok, encode(tok, [earlier[i] for i in has], args.max_len), args.batch * 2)
        p_earlier = (has, got)
    return p_recent, p_earlier


def mixed_probabilities(p_recent, p_earlier, weight, bias, earlier_weight: float = 0.2):
    out = probabilities(p_recent, weight, bias)
    if p_earlier and earlier_weight > 0:
        has, got = p_earlier
        older = probabilities(got, weight, bias)
        out[has] = (1 - earlier_weight) * out[has] + earlier_weight * older
    return out


def head_arrays(model):
    return (model.head.weight.detach().float().cpu().numpy().astype("float64"),
            model.head.bias.detach().float().cpu().numpy().astype("float64"))


def people_features(model, tok, people: list[dict], args):
    _, pooled = infer(model, tok, encode(tok, [r["text"] for r in people], 128), args.batch * 4)
    return pooled


def people_targets(people: list[dict]) -> list[list[float]]:
    v = [float(r["v"]) for r in people]
    a = [float(r["a"]) for r in people]
    mv, ma = sum(v) / len(v), sum(a) / len(a)
    sv = max(1e-8, (sum((x - mv) ** 2 for x in v) / len(v)) ** 0.5)
    sa = max(1e-8, (sum((x - ma) ** 2 for x in a) / len(a)) ** 0.5)
    return [[(x - mv) / sv, (y - ma) / sa] for x, y in zip(v, a)]


def argmax_mood(p) -> str:
    return MOODS[max(range(len(p)), key=lambda k: p[k])]


def release_memory() -> None:
    torch, _ = torch_modules()
    if torch.backends.mps.is_available():
        torch.mps.empty_cache()


# ---------------------------------------------------------------- commands

def cmd_oof(args) -> None:
    examples, earlier = load_examples(args.data)
    accept = load_accept(args.sets)
    people = load_people(args.people)
    variants = [v for v in args.variants.split(",") if v]
    leans = parse_leans(args.leans) if people else [(0.0, 0.0, p) for p in sorted({p for _, _, p in parse_leans(args.leans)})]
    note(f"{len(examples)} windows from {len({e['book'] for e in examples})} books; "
         f"{sum(1 for e in examples if len([m for m in accept.get(e['id'], []) if m != e['label']]))} with other moods that also fit; "
         f"{len(people)} people-rated non-fiction sentences; leans {', '.join(lean_suffix(l) or 'none' for l in leans)}")
    tok, make_model = build(args.base, [e["text"] for e in examples], os.path.dirname(os.path.abspath(args.out)))
    ids = encode(tok, [e["text"] for e in examples], args.max_len)
    people_ids = encode(tok, [r["text"] for r in people], 128) if people else None
    people_y = people_targets(people) if people else None
    earlier_texts = [earlier.get(e["id"], "") for e in examples]
    books = sorted({e["book"] for e in examples})
    rng = random.Random(args.seed)
    rng.shuffle(books)
    fold_of = {b: i % args.folds for i, b in enumerate(books)}
    done: set[tuple[str, int]] = set()
    if os.path.exists(args.out):  # resume: skip folds already written
        with open(args.out) as f:
            for line in f:
                r = json.loads(line)
                done.add((r["recipe"], fold_of.get(r["book"], -1)))
    folds = range(args.folds) if args.only_folds is None else [int(x) for x in args.only_folds.split(",")]
    started = time.time()
    for f in folds:
        train_idx = [i for i, e in enumerate(examples) if fold_of[e["book"]] != f]
        held_idx = [i for i, e in enumerate(examples) if fold_of[e["book"]] == f]
        for v in variants:
            base_variant, mt = parse_variant(v)
            name = f"lm-{v}"
            if (f"{name}-e0.2", f) in done:
                note(f"fold {f + 1}/{args.folds} {name}: already done")
                continue
            note(f"fold {f + 1}/{args.folds} {name}: training on {len(train_idx)} windows, holding out {len(held_idx)}")
            model = train(make_model, tok, [ids[i] for i in train_idx],
                          [target(examples[i]["label"], accept.get(examples[i]["id"]), base_variant) for i in train_idx],
                          args, seed=args.seed + 101 * f, people_ids=people_ids, people_y=people_y, mt=mt)
            weight, bias = head_arrays(model)
            sample = random.Random(f).sample(train_idx, min(1500, len(train_idx)))
            _, train_pooled = infer(model, tok, [ids[i] for i in sample], args.batch * 2)
            parts = lean_parts(fit_people(people_features(model, tok, people, args), people) if people else
                               {"v": {"w": [0.0] * train_pooled.shape[1], "b": 0.0}, "a": {"w": [0.0] * train_pooled.shape[1], "b": 0.0}},
                               train_pooled, [examples[i]["label"] for i in train_idx])
            p_recent, p_earlier = read_windows(model, tok, [examples[i]["text"] for i in held_idx],
                                               [earlier_texts[i] for i in held_idx], args)
            rows, summary = [], []
            for lean in leans:
                w, b = lean_head(weight, bias, parts, lean)
                probs = mixed_probabilities(p_recent, p_earlier, w, b)
                recipe = f"{name}{lean_suffix(lean)}-e0.2"
                hits = 0
                for k, i in enumerate(held_idx):
                    e = examples[i]
                    predicted = argmax_mood(probs[k])
                    hits += predicted == e["label"]
                    rows.append({"book": e["book"], "gold": e["label"], "id": e["id"], "predicted": predicted,
                                 "recipe": recipe, "repeatIndex": 0})
                summary.append(f"{lean_suffix(lean) or 'plain'} {hits / max(1, len(held_idx)):.1%}")
            with open(args.out, "a") as out:
                for r in rows:
                    out.write(json.dumps(r, sort_keys=True, separators=(",", ":")) + "\n")
            people_r = (f"; people r {parts['people']['v'].get('r_heldout_documents')}/{parts['people']['a'].get('r_heldout_documents')}"
                        if people else "")
            note(f"fold {f + 1}/{args.folds} {name}: exact {', '.join(summary)} on {len(held_idx)} held-out windows{people_r} "
                 f"({(time.time() - started) / 60:.1f} min so far)")
            del model
            release_memory()


def cmd_final(args) -> None:
    torch, _ = torch_modules()
    examples, _ = load_examples(args.data)
    accept = load_accept(args.sets)
    people = load_people(args.people)
    base_variant, mt = parse_variant(args.variant)
    os.makedirs(args.out, exist_ok=True)
    tok, make_model = build(args.base, [e["text"] for e in examples], args.out)
    ids = encode(tok, [e["text"] for e in examples], args.max_len)
    note(f"final {args.variant}: training on all {len(examples)} windows from {len({e['book'] for e in examples})} books")
    model = train(make_model, tok, ids, [target(e["label"], accept.get(e["id"]), base_variant) for e in examples],
                  args, seed=args.seed,
                  people_ids=encode(tok, [r["text"] for r in people], 128) if people else None,
                  people_y=people_targets(people) if people else None, mt=mt)
    if people:
        sample = random.Random(0).sample(range(len(ids)), min(3000, len(ids)))
        _, train_pooled = infer(model, tok, [ids[i] for i in sample], args.batch * 2)
        parts = lean_parts(fit_people(people_features(model, tok, people, args), people), train_pooled,
                           [e["label"] for e in examples])
        with open(os.path.join(args.out, "lean.json"), "w") as f:
            json.dump(parts, f)
        note(f"people's ratings from pooled features: r {parts['people']['v']['r_heldout_documents']} (pleasant), "
             f"{parts['people']['a']['r_heldout_documents']} (energetic) on held-out non-fiction documents")
    model = model.to("cpu")
    model.encoder.save_pretrained(os.path.join(args.out, "encoder"))
    tok.save_pretrained(os.path.join(args.out, "encoder"))
    torch.save(model.head.state_dict(), os.path.join(args.out, "head.pt"))
    params = sum(p.numel() for n, p in model.named_parameters() if not n.startswith("people."))
    meta = {"base": args.base, "variant": args.variant, "moods": MOODS, "max_len": args.max_len,
            "chunk_words": CHUNK_WORDS, "earlier_weight": 0.2, "windows": len(examples),
            "books": len({e["book"] for e in examples}), "parameters": params,
            "fp16_megabytes": round(params * 2 / 1e6, 1), "epochs": args.epochs, "lr": args.lr,
            "people_sentences": len(people)}
    with open(os.path.join(args.out, "meta.json"), "w") as f:
        json.dump(meta, f, indent=1, sort_keys=True)
    note(f"wrote {args.out} ({params / 1e6:.1f}M parameters, about {params * 2 / 1e6:.0f} MB in 16-bit)")


def load_final(folder: str, eager: bool = False):
    torch, nn = torch_modules()
    from transformers import AutoModel, AutoTokenizer
    with open(os.path.join(folder, "meta.json")) as f:
        meta = json.load(f)
    tok = AutoTokenizer.from_pretrained(os.path.join(folder, "encoder"))
    tok.truncation_side = "left"
    extra = {"attn_implementation": "eager"} if eager else {}
    model = mood_net_class()(AutoModel.from_pretrained(os.path.join(folder, "encoder"), **extra))
    model.head.load_state_dict(torch.load(os.path.join(folder, "head.pt"), map_location="cpu"))
    model.eval()
    parts = None
    if os.path.exists(os.path.join(folder, "lean.json")):
        with open(os.path.join(folder, "lean.json")) as f:
            parts = json.load(f)
    return model.to(pick_device(torch)), tok, meta, parts


def cmd_read(args) -> None:
    model, tok, meta, parts = load_final(args.model)
    windows = []
    with open(args.inp, encoding="utf-8") as f:
        for line in f:
            if line.strip():
                windows.append(json.loads(line))
    args.max_len = meta.get("max_len", args.max_len)
    leans = parse_leans(args.leans)
    if parts is None:
        note(f"{args.model} has no lean.json (trained without --people): reading it plain")
        leans = [(0.0, 0.0, 0.0)]
    started = time.time()
    p_recent, p_earlier = read_windows(model, tok, [recent_chunk(w["text"]) for w in windows],
                                       [earlier_chunk(w["text"]) for w in windows], args)
    per_window_ms = (time.time() - started) * 1000 / max(1, len(windows))
    weight, bias = head_arrays(model)
    name = args.engine or os.path.basename(os.path.normpath(args.model))
    for lean in leans:
        w, b = lean_head(weight, bias, parts, lean) if parts else (weight, bias)
        probs = mixed_probabilities(p_recent, p_earlier, w, b, meta.get("earlier_weight", 0.2))
        path = f"{args.out}{lean_suffix(lean) or '-plain'}.jsonl"
        with open(path, "w") as out:
            for wdw, p in zip(windows, probs):
                p = [float(q) for q in p]
                out.write(json.dumps({
                    "id": wdw["id"], "engine": f"{name}{lean_suffix(lean)}", "bucket": argmax_mood(p),
                    "valence": round(sum(q * ANCHORS[m][0] for m, q in zip(MOODS, p)), 3),
                    "arousal": round(sum(q * ANCHORS[m][1] for m, q in zip(MOODS, p)), 3),
                    "confidence": round(max(p), 3), "scores": {m: round(q, 3) for m, q in zip(MOODS, p)},
                    "latencyMs": round(per_window_ms, 1),
                }, sort_keys=True) + "\n")
        print(path)
    note(f"read {len(windows)} windows with {len(leans)} leans ({per_window_ms:.1f} ms a window in batches)")


def cmd_coreml(args) -> None:
    """Core ML for the app: an ML program (16-bit) taking input_ids and
    attention_mask of a fixed length and giving the mood probabilities, with
    --lean folded into the head, plus a JSON file with the WordPiece
    vocabulary and settings the app's tokenizer needs. On macOS it also
    checks the Core ML model against PyTorch on windows from --check."""
    import numpy as np
    import coremltools as ct
    torch, nn = torch_modules()
    model, tok, meta, parts = load_final(args.model, eager=True)
    model = model.to("cpu").float().eval()
    length = meta.get("max_len", 256)
    lean = parse_leans(args.lean)[0] if args.lean else (0.0, 0.0, 0.0)
    if any(lean):
        if parts is None:
            raise SystemExit(f"{args.model} has no lean.json: cannot apply lean {args.lean}")
        weight, bias = head_arrays(model)
        w, b = lean_head(weight, bias, parts, lean)
        with torch.no_grad():
            model.head.weight.copy_(torch.tensor(w, dtype=torch.float32))
            model.head.bias.copy_(torch.tensor(b, dtype=torch.float32))

    class Probabilities(nn.Module):
        def __init__(self, inner):
            super().__init__()
            self.inner = inner

        def forward(self, input_ids, attention_mask):
            # The additive 4-D mask is built here, so the encoder skips
            # transformers' own mask code (which Core ML cannot convert).
            extended = (1.0 - attention_mask[:, None, None, :].to(torch.float32)) * -10000.0
            pooled = self.inner.pooled(input_ids, attention_mask, extended=extended)
            return torch.softmax(self.inner.head(pooled), dim=-1)

    wrapped = Probabilities(model).eval()
    sample = tok(["It was a quiet evening by the fire."], padding="max_length", truncation=True,
                 max_length=length, return_tensors="pt")
    with torch.no_grad():
        same = torch.allclose(wrapped(sample["input_ids"], sample["attention_mask"]),
                              torch.softmax(model(sample["input_ids"], sample["attention_mask"]), dim=-1), atol=1e-4)
    if not same:
        raise SystemExit("the 4-D mask path does not match the model; not converting")
    # torch.export copes with newer transformers' mask code, which TorchScript
    # tracing turns into ops Core ML cannot convert; fall back to tracing.
    try:
        program = torch.export.export(wrapped, (sample["input_ids"], sample["attention_mask"]))
        source = program.run_decompositions({})
    except Exception as e:  # older torch
        note(f"torch.export failed ({type(e).__name__}: {e}); tracing instead")
        with torch.no_grad():
            source = torch.jit.trace(wrapped, (sample["input_ids"], sample["attention_mask"]), strict=False)
    ml = ct.convert(
        source,
        inputs=[ct.TensorType(name="input_ids", shape=(1, length), dtype=np.int32),
                ct.TensorType(name="attention_mask", shape=(1, length), dtype=np.int32)],
        outputs=[ct.TensorType(name="probabilities")],
        convert_to="mlprogram", compute_precision=ct.precision.FLOAT16,
        minimum_deployment_target=ct.target.iOS17,
    )
    ml.short_description = f"Mood of a passage ({', '.join(MOODS)}), fine-tuned from {meta['base']}"
    ml.license = "Base model Apache-2.0; see CREDITS.md (a people's-ratings lean comes from EmoBank, CC BY-SA 4.0)."
    name = args.name
    os.makedirs(args.out, exist_ok=True)
    package = os.path.join(args.out, f"{name}.mlpackage")
    ml.save(package)
    vocab = [t for t, _ in sorted(tok.get_vocab().items(), key=lambda kv: kv[1])]
    config = {
        "format": 1, "kind": "wordpiece-transformer", "model": f"{name}.mlmodelc", "moods": MOODS,
        "maxTokens": length, "lowercase": bool(getattr(tok, "do_lower_case", True)),
        "chunkWords": meta.get("chunk_words", CHUNK_WORDS), "earlierWeight": meta.get("earlier_weight", 0.2),
        "base": meta["base"], "variant": f"{meta.get('variant')}{lean_suffix(lean)}",
        "special": {"cls": tok.cls_token, "sep": tok.sep_token, "pad": tok.pad_token, "unk": tok.unk_token},
        "vocab": vocab,
    }
    with open(os.path.join(args.out, f"{name}.json"), "w", encoding="utf-8") as f:
        json.dump(config, f, ensure_ascii=False, separators=(",", ":"))
    size = sum(os.path.getsize(os.path.join(d, x)) for d, _, xs in os.walk(package) for x in xs)
    note(f"wrote {package} ({size / 1e6:.1f} MB) and {name}.json ({len(vocab)} word pieces; lean {lean_suffix(lean) or 'none'})")

    if args.check and sys.platform == "darwin":
        windows = [json.loads(line) for line in open(args.check, encoding="utf-8") if line.strip()][:args.check_count]
        agree, worst = 0, 0.0
        for w in windows:
            enc = tok([recent_chunk(w["text"])], padding="max_length", truncation=True, max_length=length, return_tensors="pt")
            with torch.no_grad():
                p_torch = wrapped(enc["input_ids"], enc["attention_mask"])[0].tolist()
            out = ml.predict({"input_ids": enc["input_ids"].numpy().astype(np.int32),
                              "attention_mask": enc["attention_mask"].numpy().astype(np.int32)})
            p_ml = [float(x) for x in np.asarray(out["probabilities"]).reshape(-1)]
            agree += argmax_mood(p_torch) == argmax_mood(p_ml)
            worst = max(worst, max(abs(a - b) for a, b in zip(p_torch, p_ml)))
        note(f"Core ML vs PyTorch on {len(windows)} windows: same mood {agree}/{len(windows)}, "
             f"largest probability difference {worst:.4f}")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)

    def common(p, training: bool) -> None:
        p.add_argument("--max-len", type=int, default=256)
        p.add_argument("--batch", type=int, default=32)
        if training:
            p.add_argument("--data", default="Tools/data/work/train")
            p.add_argument("--sets", action="append", default=[])
            p.add_argument("--people", default=None, help="emobank.py people output (non-fiction rows train the lean)")
            p.add_argument("--base", default=DEFAULT_BASE)
            p.add_argument("--epochs", type=int, default=3)
            p.add_argument("--lr", type=float, default=5e-5)
            p.add_argument("--seed", type=int, default=2026)
            p.add_argument("--max-steps", type=int, default=0, help="stop early (for smoke tests)")

    p = sub.add_parser("oof")
    common(p, True)
    p.add_argument("--variants", default="soft,soft-mt1")
    p.add_argument("--leans", default=DEFAULT_LEANS)
    p.add_argument("--folds", type=int, default=10)
    p.add_argument("--only-folds", default=None)
    p.add_argument("--out", required=True)
    p = sub.add_parser("final")
    common(p, True)
    p.add_argument("--variant", default="soft")
    p.add_argument("--out", required=True)
    p = sub.add_parser("read")
    common(p, False)
    p.add_argument("--model", required=True)
    p.add_argument("--in", dest="inp", required=True)
    p.add_argument("--out", required=True, help="prefix: writes PREFIX[-vV][-aA][-pP].jsonl per lean")
    p.add_argument("--engine", default=None)
    p.add_argument("--leans", default="0:0:0")
    p = sub.add_parser("coreml")
    p.add_argument("--model", required=True)
    p.add_argument("--lean", default=None, help="V:A:P folded into the head")
    p.add_argument("--out", required=True)
    p.add_argument("--name", default="LofiMood-lm")
    p.add_argument("--check", default=None, help="windows .jsonl to compare Core ML with PyTorch on (macOS)")
    p.add_argument("--check-count", type=int, default=200)
    args = ap.parse_args()
    {"oof": cmd_oof, "final": cmd_final, "read": cmd_read, "coreml": cmd_coreml}[args.cmd](args)


if __name__ == "__main__":
    main()
