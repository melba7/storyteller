"""Close-up spectrograms to tell a piano on its own from a piano with pads or strings.

Usage: python -I zoom_sheet.py OUT.png CANDIDATES.csv ANALYSIS_DIR ID [ID ...]

For each track draws two 30 s windows (at 35% and 70% of the track), 60 Hz to 5 kHz on
a log axis. A piano note is a sharp vertical edge whose partials fade; a pad or bowed
string is a level line with no edge, often with a slow start.
"""
import subprocess, sys
import numpy as np
import pandas as pd
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

SR = 16000
out, cand_path, adir, ids = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4:]
cand = pd.read_csv(cand_path).set_index("id")

def decode(path):
    cmd = ["ffmpeg", "-v", "error", "-nostdin", "-i", path, "-ac", "1", "-ar", str(SR), "-f", "f32le", "-"]
    return np.frombuffer(subprocess.run(cmd, capture_output=True, check=True).stdout, dtype=np.float32)

fig, axes = plt.subplots(len(ids), 2, figsize=(17, 2.1 * len(ids)), squeeze=False)
N, H = 2048, 256
win = np.hanning(N)
for row, cid in enumerate(ids):
    y = decode(f"{adir}/{cid}.m4a")
    dur = len(y) / SR
    for col, frac in enumerate((0.35, 0.70)):
        a = int(max(0, min(dur - 30, frac * dur)) * SR)
        seg = y[a:a + 30 * SR]
        n = 1 + (len(seg) - N) // H
        idx = np.arange(N)[None, :] + H * np.arange(n)[:, None]
        S = np.abs(np.fft.rfft(seg[idx] * win, axis=1)).T
        db = 20 * np.log10(S + 1e-6)
        db -= db.max()
        f = np.fft.rfftfreq(N, 1 / SR)
        keep = (f >= 60) & (f <= 5000)
        ax = axes[row, col]
        ax.pcolormesh(a / SR + np.arange(n) * H / SR, f[keep], db[keep], vmin=-70, vmax=0, cmap="magma", shading="auto")
        ax.set_yscale("log")
        ax.set_yticks([100, 300, 1000, 3000]); ax.set_yticklabels(["100", "300", "1k", "3k"], fontsize=6)
        ax.tick_params(axis="x", labelsize=6)
        if col == 0:
            r = cand.loc[cid]
            ax.set_title(f"{cid}  {str(r.artist)[:28]} | {str(r.title)[:60]}", fontsize=8, loc="left")
plt.tight_layout()
plt.savefig(out, dpi=75)
