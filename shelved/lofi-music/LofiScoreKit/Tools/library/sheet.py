"""Contact sheet of mel spectrograms, one row per track, with the YAMNet vocal curve.

Usage: python -I sheet.py OUT.png YAMNET_JSON_DIR TITLE "label|path" ["label|path" ...]
"""
import hashlib
import json
import os
import subprocess
import sys

import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402

SR = 11025


def decode(path):
    cmd = ["ffmpeg", "-v", "error", "-nostdin", "-i", path, "-ac", "1", "-ar", str(SR), "-f", "f32le", "-"]
    out = subprocess.run(cmd, capture_output=True, check=True, timeout=300).stdout
    return np.frombuffer(out, dtype=np.float32).copy()


def main():
    import librosa
    out, yam_dir, title = sys.argv[1], sys.argv[2], sys.argv[3]
    items = [arg.split("|", 1) for arg in sys.argv[4:]]
    rows = len(items)
    fig, axes = plt.subplots(rows, 1, figsize=(14, 1.15 * rows + 0.6), squeeze=False)
    for ax, (label, path) in zip(axes[:, 0], items):
        try:
            y = decode(path)
            mel = librosa.feature.melspectrogram(y=y, sr=SR, n_fft=1024, hop_length=512, n_mels=64, fmax=5000)
            db = librosa.power_to_db(mel, ref=np.max)
            ax.imshow(db, origin="lower", aspect="auto", cmap="magma", vmin=-70, vmax=0,
                      extent=[0, len(y) / SR, 0, 64])
            key = hashlib.sha1(path.encode()).hexdigest()[:16]
            jpath = os.path.join(yam_dir, key + ".json")
            if os.path.exists(jpath):
                with open(jpath) as handle:
                    curve = json.load(handle)["vocal_curve"]
                xs = np.linspace(0, len(y) / SR, num=len(curve))
                ax.plot(xs, np.array(curve) * 60 + 2, color="cyan", linewidth=0.8)
                ax.axhline(0.35 * 60 + 2, color="cyan", linewidth=0.3, linestyle=":")
        except Exception as error:
            ax.text(0.01, 0.5, f"error: {error}", transform=ax.transAxes, color="red")
        ax.set_yticks([])
        ax.set_ylabel(label, rotation=0, ha="right", va="center", fontsize=7)
        ax.tick_params(axis="x", labelsize=6)
    fig.suptitle(title, fontsize=10)
    fig.tight_layout()
    fig.savefig(out, dpi=80)


if __name__ == "__main__":
    main()
