#!/usr/bin/env python3
"""Fine-tune a small language model to read the mood of a passage.

The shipped Fast engine is a softmax head on Apple's word embeddings. This
tries the next step up: a small pretrained transformer (by default
sentence-transformers/all-MiniLM-L6-v2, 22.7M parameters, Apache-2.0) whose
every layer is tuned on the labelled windows, with the same input as the
Fast engine (the newest 160 words of a window, and optionally the 160 before
them at a lower weight). It runs on Mo's Mac (Apple GPU through PyTorch's
"mps" device) inside a virtual environment in "~/Storyteller Lofi"; see
Tools/mac/finetune.sh, which runs every step below.

    # out-of-fold predictions on every labelled book, in lofi-train oof's format
    python finetune_mood.py oof --data Tools/data/work/train --sets SETS.jsonl ... --out oof-lm.jsonl
    # one model on every labelled book
    python finetune_mood.py final --data Tools/data/work/train --sets SETS.jsonl ... --variant soft --out MODEL_DIR
    # readings for lofi-eval-style windows (e.g. EmoBank's), for emobank.py score
    python finetune_mood.py read --model MODEL_DIR --in windows.jsonl --out readings.jsonl

Variants: "hard" learns the one best mood; "soft" lets the other moods that
would also suit a window (the `accept` lists in --sets files) share 30% of
its target, like the soft-0.3 recipe. Each OOF variant is written twice:
"lm-VARIANT" reads the newest words only, "lm-VARIANT-e0.2" also mixes in the
reading of the words before them at weight 0.2 (the shipped recipe's
setting). Folds are whole books, as in `lofi-train oof`, so rows compare
window by window with its recipes (Tools/eval/oof_compare.py).

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


def build(base: str, texts_for_tiny: list[str], work: str):
    torch, nn = torch_modules()
    from transformers import AutoModel, AutoTokenizer, BertConfig, BertModel

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

    class MoodNet(nn.Module):
        """Mean-pooled encoder (as sentence-transformers trains it) and a linear head."""

        def __init__(self, encoder):
            super().__init__()
            self.encoder = encoder
            self.drop = nn.Dropout(0.1)
            self.head = nn.Linear(encoder.config.hidden_size, len(MOODS))

        def forward(self, input_ids, attention_mask):
            hidden = self.encoder(input_ids=input_ids, attention_mask=attention_mask).last_hidden_state
            m = attention_mask.unsqueeze(-1).to(hidden.dtype)
            pooled = (hidden * m).sum(1) / m.sum(1).clamp(min=1e-6)
            return self.head(self.drop(pooled))

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


def train(make_model, tok, ids: list[list[int]], targets: list[list[float]], args, seed: int):
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
    rng = random.Random(seed)
    step = 0
    started = time.time()
    for epoch in range(args.epochs):
        order = list(range(len(ids)))
        rng.shuffle(order)
        running = 0.0
        for k, (idx, x, mask) in enumerate(batches(torch, ids, order, args.batch, tok.pad_token_id, device)):
            logits = model(x, mask)
            y = y_all[idx].to(device)
            loss = -(y * torch.log_softmax(logits, dim=-1)).sum(-1).mean()
            opt.zero_grad()
            loss.backward()
            torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0)
            opt.step()
            sched.step()
            running += loss.item()
            step += 1
            if step >= total:
                break
        note(f"    epoch {epoch + 1}: loss {running / max(1, k + 1):.3f} ({time.time() - started:.0f} s)")
        if step >= total:
            break
    model.eval()
    return model


def predict(model, tok, ids: list[list[int]], batch: int) -> list[list[float]]:
    torch, _ = torch_modules()
    device = next(model.parameters()).device
    out: list[list[float]] = [None] * len(ids)  # type: ignore[list-item]
    order = sorted(range(len(ids)), key=lambda i: len(ids[i]))
    with torch.no_grad():
        for idx, x, mask in batches(torch, ids, order, batch, tok.pad_token_id, device):
            p = torch.softmax(model(x, mask).float(), dim=-1).cpu().tolist()
            for i, row in zip(idx, p):
                out[i] = row
    return out


def mix(recent: list[float], earlier: list[float] | None, weight: float) -> list[float]:
    if earlier is None or weight <= 0:
        return recent
    return [(1 - weight) * a + weight * b for a, b in zip(recent, earlier)]


def predict_windows(model, tok, recent_texts: list[str], earlier_texts: list[str], args) -> tuple[list, list]:
    """Probabilities from the newest words, and from the words before them
    (None where there are fewer than 40)."""
    p_recent = predict(model, tok, encode(tok, recent_texts, args.max_len), args.batch * 2)
    has = [i for i, t in enumerate(earlier_texts) if len(words(t)) >= MIN_EARLIER_WORDS]
    p_earlier: list = [None] * len(recent_texts)
    if has:
        got = predict(model, tok, encode(tok, [earlier_texts[i] for i in has], args.max_len), args.batch * 2)
        for i, p in zip(has, got):
            p_earlier[i] = p
    return p_recent, p_earlier


def argmax_mood(p: list[float]) -> str:
    return MOODS[max(range(len(p)), key=lambda k: p[k])]


# ---------------------------------------------------------------- commands

def cmd_oof(args) -> None:
    examples, earlier = load_examples(args.data)
    accept = load_accept(args.sets)
    variants = [v for v in args.variants.split(",") if v]
    note(f"{len(examples)} windows from {len({e['book'] for e in examples})} books; "
         f"{sum(1 for e in examples if len([m for m in accept.get(e['id'], []) if m != e['label']]))} with other moods that also fit")
    tok, make_model = build(args.base, [e["text"] for e in examples], os.path.dirname(os.path.abspath(args.out)))
    ids = encode(tok, [e["text"] for e in examples], args.max_len)
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
            name = f"lm-{v}"
            if (name, f) in done:
                note(f"fold {f + 1}/{args.folds} {name}: already done")
                continue
            note(f"fold {f + 1}/{args.folds} {name}: training on {len(train_idx)} windows, holding out {len(held_idx)}")
            model = train(make_model, tok, [ids[i] for i in train_idx],
                          [target(examples[i]["label"], accept.get(examples[i]["id"]), v) for i in train_idx],
                          args, seed=args.seed + 101 * f)
            p_recent, p_earlier = predict_windows(model, tok, [examples[i]["text"] for i in held_idx],
                                                  [earlier_texts[i] for i in held_idx], args)
            rows = []
            for k, i in enumerate(held_idx):
                e = examples[i]
                for recipe, p in ((name, p_recent[k]), (f"{name}-e0.2", mix(p_recent[k], p_earlier[k], 0.2))):
                    rows.append({"book": e["book"], "gold": e["label"], "id": e["id"], "predicted": argmax_mood(p),
                                 "recipe": recipe, "repeatIndex": 0})
            exact = sum(r["gold"] == r["predicted"] for r in rows if r["recipe"] == name) / max(1, len(held_idx))
            with open(args.out, "a") as out:
                for r in rows:
                    out.write(json.dumps(r, sort_keys=True, separators=(",", ":")) + "\n")
            note(f"fold {f + 1}/{args.folds} {name}: exact {exact:.1%} on {len(held_idx)} held-out windows "
                 f"({(time.time() - started) / 60:.1f} min so far)")
            del model
            release_memory()


def release_memory() -> None:
    torch, _ = torch_modules()
    if torch.backends.mps.is_available():
        torch.mps.empty_cache()


def cmd_final(args) -> None:
    torch, _ = torch_modules()
    examples, _ = load_examples(args.data)
    accept = load_accept(args.sets)
    os.makedirs(args.out, exist_ok=True)
    tok, make_model = build(args.base, [e["text"] for e in examples], args.out)
    ids = encode(tok, [e["text"] for e in examples], args.max_len)
    note(f"final {args.variant}: training on all {len(examples)} windows from {len({e['book'] for e in examples})} books")
    model = train(make_model, tok, ids, [target(e["label"], accept.get(e["id"]), args.variant) for e in examples],
                  args, seed=args.seed)
    model = model.to("cpu")
    model.encoder.save_pretrained(os.path.join(args.out, "encoder"))
    tok.save_pretrained(os.path.join(args.out, "encoder"))
    torch.save(model.head.state_dict(), os.path.join(args.out, "head.pt"))
    params = sum(p.numel() for p in model.parameters())
    meta = {"base": args.base, "variant": args.variant, "moods": MOODS, "max_len": args.max_len,
            "chunk_words": CHUNK_WORDS, "earlier_weight": 0.2, "windows": len(examples),
            "books": len({e["book"] for e in examples}), "parameters": params,
            "fp16_megabytes": round(params * 2 / 1e6, 1), "epochs": args.epochs, "lr": args.lr}
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
    encoder = AutoModel.from_pretrained(os.path.join(folder, "encoder"), **extra)

    class MoodNet(nn.Module):
        def __init__(self):
            super().__init__()
            self.encoder = encoder
            self.drop = nn.Dropout(0.1)
            self.head = nn.Linear(encoder.config.hidden_size, len(MOODS))

        def forward(self, input_ids, attention_mask):
            hidden = self.encoder(input_ids=input_ids, attention_mask=attention_mask).last_hidden_state
            m = attention_mask.unsqueeze(-1).to(hidden.dtype)
            return self.head((hidden * m).sum(1) / m.sum(1).clamp(min=1e-6))

    model = MoodNet()
    model.head.load_state_dict(torch.load(os.path.join(folder, "head.pt"), map_location="cpu"))
    model.eval()
    return model.to(pick_device(torch)), tok, meta


def cmd_read(args) -> None:
    model, tok, meta = load_final(args.model)
    windows = []
    with open(args.inp, encoding="utf-8") as f:
        for line in f:
            if line.strip():
                windows.append(json.loads(line))
    args.max_len = meta.get("max_len", args.max_len)
    weight = meta.get("earlier_weight", 0.2) if args.earlier_weight is None else args.earlier_weight
    started = time.time()
    p_recent, p_earlier = predict_windows(model, tok, [recent_chunk(w["text"]) for w in windows],
                                          [earlier_chunk(w["text"]) for w in windows], args)
    per_window_ms = (time.time() - started) * 1000 / max(1, len(windows))
    engine = args.engine or f"lm:{os.path.basename(os.path.normpath(args.model))}"
    with open(args.out, "w") as out:
        for w, pr, pe in zip(windows, p_recent, p_earlier):
            p = mix(pr, pe, weight)
            scores = {m: round(q, 3) for m, q in zip(MOODS, p)}
            best = argmax_mood(p)
            out.write(json.dumps({
                "id": w["id"], "engine": engine, "bucket": best,
                "valence": round(sum(q * ANCHORS[m][0] for m, q in zip(MOODS, p)), 3),
                "arousal": round(sum(q * ANCHORS[m][1] for m, q in zip(MOODS, p)), 3),
                "confidence": round(max(p), 3), "scores": scores, "latencyMs": round(per_window_ms, 1),
            }, sort_keys=True) + "\n")
    note(f"read {len(windows)} windows -> {args.out} (earlier weight {weight}, {per_window_ms:.1f} ms a window in batches)")


def cmd_coreml(args) -> None:
    """Core ML for the app: an ML program (16-bit) taking input_ids and
    attention_mask of a fixed length and giving the mood probabilities, plus
    a JSON file with the WordPiece vocabulary and settings the app's
    tokenizer needs. On macOS it also checks the Core ML model against
    PyTorch on windows from --check."""
    import numpy as np
    import coremltools as ct
    torch, nn = torch_modules()
    model, tok, meta = load_final(args.model, eager=True)
    model = model.to("cpu").float().eval()
    length = meta.get("max_len", 256)

    class Probabilities(nn.Module):
        def __init__(self, inner):
            super().__init__()
            self.inner = inner

        def forward(self, input_ids, attention_mask):
            # The additive 4-D mask is built here, so the encoder skips
            # transformers' own mask code (which Core ML cannot convert).
            extended = (1.0 - attention_mask[:, None, None, :].to(torch.float32)) * -10000.0
            hidden = self.inner.encoder(input_ids=input_ids, attention_mask=extended).last_hidden_state
            m = attention_mask.unsqueeze(-1).to(hidden.dtype)
            pooled = (hidden * m).sum(1) / m.sum(1).clamp(min=1e-6)
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
    ml.license = "Model weights: Apache-2.0 base (see CREDITS). Mood labels: LofiScoreKit."
    name = args.name
    os.makedirs(args.out, exist_ok=True)
    package = os.path.join(args.out, f"{name}.mlpackage")
    ml.save(package)
    vocab = [t for t, _ in sorted(tok.get_vocab().items(), key=lambda kv: kv[1])]
    config = {
        "format": 1, "kind": "wordpiece-transformer", "model": f"{name}.mlmodelc", "moods": MOODS,
        "maxTokens": length, "lowercase": bool(getattr(tok, "do_lower_case", True)),
        "chunkWords": meta.get("chunk_words", CHUNK_WORDS), "earlierWeight": meta.get("earlier_weight", 0.2),
        "base": meta["base"], "variant": meta.get("variant"),
        "special": {"cls": tok.cls_token, "sep": tok.sep_token, "pad": tok.pad_token, "unk": tok.unk_token},
        "vocab": vocab,
    }
    with open(os.path.join(args.out, f"{name}.json"), "w", encoding="utf-8") as f:
        json.dump(config, f, ensure_ascii=False, separators=(",", ":"))
    size = sum(os.path.getsize(os.path.join(d, x)) for d, _, xs in os.walk(package) for x in xs)
    note(f"wrote {package} ({size / 1e6:.1f} MB) and {name}.json ({len(vocab)} word pieces)")

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
            p.add_argument("--base", default=DEFAULT_BASE)
            p.add_argument("--epochs", type=int, default=3)
            p.add_argument("--lr", type=float, default=5e-5)
            p.add_argument("--seed", type=int, default=2026)
            p.add_argument("--max-steps", type=int, default=0, help="stop early (for smoke tests)")

    p = sub.add_parser("oof")
    common(p, True)
    p.add_argument("--variants", default="hard,soft")
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
    p.add_argument("--out", required=True)
    p.add_argument("--engine", default=None)
    p.add_argument("--earlier-weight", type=float, default=None)
    p = sub.add_parser("coreml")
    p.add_argument("--model", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--name", default="LofiMood-lm")
    p.add_argument("--check", default=None, help="windows .jsonl to compare Core ML with PyTorch on (macOS)")
    p.add_argument("--check-count", type=int, default=200)
    args = ap.parse_args()
    {"oof": cmd_oof, "final": cmd_final, "read": cmd_read, "coreml": cmd_coreml}[args.cmd](args)


if __name__ == "__main__":
    main()
