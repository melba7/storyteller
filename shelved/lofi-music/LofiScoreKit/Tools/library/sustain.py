"""Tell a piano on its own from a piano with strings or pads behind it.

Usage: python -I sustain.py OUT.csv --list FILE_WITH_PATHS

A piano note starts at once and then only fades. Bowed strings, pads and organs can
swell (get louder slowly) and can hold a level. For narrow frequency bands this measures:
  swell   of all the moments a band got clearly louder over half a second, the share
          where it did so without any sudden jump (no key was struck)
  steady  the share of sounding band-time where the level held within 3 dB for 1.5 s
  swell_e, steady_e  the same, weighted by energy
YAMNet cannot be trusted here: on soft, reverberant modern piano it reports little more
than "Music". Appends one row per file and skips files already in OUT.csv.
"""
import csv
import os
import re
import subprocess
import sys
from concurrent.futures import ProcessPoolExecutor

import numpy as np

SR = 22050
N_FFT, HOP = 4096, 512


def decode(path):
    cmd = ["ffmpeg", "-v", "error", "-nostdin", "-i", path, "-ac", "1", "-ar", str(SR), "-f", "f32le", "-"]
    out = subprocess.run(cmd, capture_output=True, check=True, timeout=300).stdout
    return np.frombuffer(out, dtype=np.float32).astype(np.float64)


def measure(path):
    from scipy.ndimage import maximum_filter1d, minimum_filter1d
    try:
        y = decode(path)
        win = np.hanning(N_FFT + 1)[:-1]
        n = 1 + (len(y) - N_FFT) // HOP
        freqs = np.fft.rfftfreq(N_FFT, 1 / SR)
        edges = 65.0 * 2 ** (np.arange(0, 36 * 5.75 + 1) / 36)   # third-of-a-semitone bands, 65 Hz to 3.5 kHz
        lo = np.searchsorted(freqs, edges[:-1])
        hi = np.maximum(np.searchsorted(freqs, edges[1:]), lo + 1)
        bands = np.empty((len(lo), n))
        for start in range(0, n, 1500):
            stop = min(n, start + 1500)
            idx = np.arange(N_FFT)[None, :] + HOP * np.arange(start, stop)[:, None]
            p = np.abs(np.fft.rfft(y[idx] * win, axis=1)) ** 2
            c = np.concatenate([np.zeros((stop - start, 1)), np.cumsum(p, axis=1)], axis=1)
            bands[:, start:stop] = (c[:, hi] - c[:, lo]).T
        db = 10 * np.log10(bands + 1e-12)
        ref = np.percentile(db, 99.5)
        active = db > ref - 45
        power = bands / (bands.sum() + 1e-12)
        hop_s = HOP / SR
        k3, k05, k15 = 3, int(round(0.5 / hop_s)), int(round(1.5 / hop_s))
        jump = np.zeros_like(db)
        jump[:, k3:] = db[:, k3:] - db[:, :-k3]                      # rise over 70 ms
        sharpest = maximum_filter1d(jump, size=k05 + k3, axis=1, origin=(k05 + k3) // 2 - 1)  # looking back 0.5 s
        rise = np.zeros_like(db)
        rise[:, k05:] = db[:, k05:] - db[:, :-k05]                   # rise over 0.5 s
        rising = (rise >= 4.0) & active
        slow = rising & (sharpest < 2.0)
        span = maximum_filter1d(db, size=k15, axis=1) - minimum_filter1d(db, size=k15, axis=1)
        steady = (span < 3.0) & active
        return {
            "path": path,
            "swell": round(float(slow.sum() / max(rising.sum(), 1)), 4),
            "swell_e": round(float(power[slow].sum() / max(power[rising].sum(), 1e-12)), 4),
            "swell_share": round(float(slow.sum() / max(active.sum(), 1)), 5),
            "steady": round(float(steady.sum() / max(active.sum(), 1)), 4),
            "steady_e": round(float(power[steady].sum() / max(power[active].sum(), 1e-12)), 4),
        }
    except Exception as error:
        return {"path": path, "error": f"{type(error).__name__}: {error}"[:150]}


def main():
    out_path = sys.argv[1]
    files = [line.strip() for line in open(sys.argv[3]) if line.strip()]
    done = set()
    if os.path.exists(out_path):
        done = {r["path"] for r in csv.DictReader(open(out_path))}
    todo = [f for f in files if f not in done]
    print(f"{len(todo)} to do", flush=True)
    fields = ["path", "error", "swell", "swell_e", "swell_share", "steady", "steady_e"]
    new = not os.path.exists(out_path)
    with open(out_path, "a", newline="") as handle, ProcessPoolExecutor(max_workers=4) as pool:
        w = csv.DictWriter(handle, fieldnames=fields)
        if new:
            w.writeheader()
        for n, row in enumerate(pool.map(measure, todo), 1):
            w.writerow(row)
            handle.flush()
            if n % 20 == 0 or n == len(todo):
                print(f"{n}/{len(todo)}", flush=True)


if __name__ == "__main__":
    main()
