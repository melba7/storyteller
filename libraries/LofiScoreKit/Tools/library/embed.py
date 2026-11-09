"""YAMNet embeddings for each candidate, for a small mood model trained on site tags.

Usage: python -I embed.py OUT.npz YAMNET_DIR --list FILE_WITH_PATHS

Saves ids (file stems), the mean and standard deviation of the 1024-d frame embeddings,
and the mean embedding of each quarter of the track.
"""
import os
import subprocess
import sys

import numpy as np


def decode(path, sr=16000):
    cmd = ["ffmpeg", "-v", "error", "-nostdin", "-i", path, "-ac", "1", "-ar", str(sr), "-f", "f32le", "-"]
    out = subprocess.run(cmd, capture_output=True, check=True, timeout=300).stdout
    return np.frombuffer(out, dtype=np.float32).copy()


def main():
    out_path, yamnet_dir = sys.argv[1], sys.argv[2]
    assert sys.argv[3] == "--list"
    with open(sys.argv[4]) as handle:
        files = [line.strip() for line in handle if line.strip()]
    sys.path.insert(0, yamnet_dir)
    import params as yamnet_params  # official tensorflow/models code
    import yamnet as yamnet_model

    params = yamnet_params.Params()
    model = yamnet_model.yamnet_frames_model(params)
    model.load_weights(os.path.join(yamnet_dir, "yamnet.h5"))

    ids, means, stds, quarters = [], [], [], []
    for n, path in enumerate(files, 1):
        y = decode(path)
        _, emb, _ = model(y)
        e = emb.numpy()
        ids.append(os.path.basename(path).split(".")[0])
        means.append(e.mean(axis=0))
        stds.append(e.std(axis=0))
        parts = np.array_split(e, 4)
        quarters.append(np.stack([p.mean(axis=0) for p in parts]))
        if n % 50 == 0 or n == len(files):
            print(f"{n}/{len(files)}", flush=True)
    np.savez_compressed(
        out_path,
        ids=np.array(ids),
        mean=np.stack(means).astype(np.float32),
        std=np.stack(stds).astype(np.float32),
        quarters=np.stack(quarters).astype(np.float32),
    )


if __name__ == "__main__":
    main()
