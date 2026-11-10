"""Try gain-riding settings on a few tracks and report loudness spread before and after.

Usage: python -I even_test.py AUDIO_FILE [AUDIO_FILE ...]

For each file: peak, loudness range and loudness, then the spread between 3 s and 10 s
stretches (95th minus 10th percentile, and loudest minus median). The same again for
five dynaudnorm settings (maximum boost 6, 9 or 12 dB; window 31 or 15 frames of 0.5 s).
This is how install_library.py's "even" settings were chosen: the 15-frame window with
a boost between the 9 and 12 dB tried here (+10 dB) narrowed the spread the most. The
gain was then measured never to move faster than 4 dB a second.
"""
import subprocess, sys, re, os
import numpy as np

SR = 22050

def decode(path, flt=None):
    cmd = ["ffmpeg", "-v", "error", "-nostdin", "-i", path]
    if flt:
        cmd += ["-af", flt]
    cmd += ["-ac", "1", "-ar", str(SR), "-f", "f32le", "-"]
    return np.frombuffer(subprocess.run(cmd, capture_output=True, check=True).stdout, dtype=np.float32)

def peak_db(path):
    err = subprocess.run(["ffmpeg", "-nostdin", "-hide_banner", "-i", path, "-af", "volumedetect", "-f", "null", "-"],
                         capture_output=True, text=True).stderr
    return float(re.search(r"max_volume: (-?[\d.]+) dB", err).group(1))

def windows(y, sec):
    n = int(sec * SR)
    k = len(y) // n
    e = (y[: k * n].reshape(k, n).astype(np.float64) ** 2).mean(axis=1)
    return 10 * np.log10(e + 1e-12)

def spread(y):
    out = {}
    for sec in (3, 10):
        w = windows(y, sec)
        w = w[w > w.max() - 40]            # ignore silence
        out[sec] = (np.percentile(w, 95) - np.percentile(w, 10), w.max() - np.median(w))
    return out

def lra(path, flt=None):
    f = (flt + "," if flt else "") + "ebur128"
    err = subprocess.run(["ffmpeg", "-nostdin", "-hide_banner", "-nostats", "-i", path, "-af", f, "-f", "null", "-"],
                         capture_output=True, text=True).stderr
    s = err[err.rfind("Summary:"):]
    return float(re.search(r"LRA:\s+([\d.]+)", s).group(1)), float(re.search(r"I:\s+(-?[\d.]+)", s).group(1))

for path in sys.argv[1:]:
    pk = peak_db(path)
    base = spread(decode(path))
    l0 = lra(path)
    print(f"{os.path.basename(path)} peak {pk:.1f} dB  LRA {l0[0]:.1f}  I {l0[1]:.1f} | 3s spread {base[3][0]:.1f} (max-med {base[3][1]:.1f}) | 10s spread {base[10][0]:.1f} (max-med {base[10][1]:.1f})")
    for m_db, g in ((6, 31), (9, 31), (12, 31), (9, 15), (12, 15)):
        m = 10 ** (m_db / 20)
        flt = f"volume={-1 - pk:.2f}dB,dynaudnorm=f=500:g={g}:p=0.89:m={m:.2f}"
        s = spread(decode(path, flt))
        l1 = lra(path, flt)
        print(f"   +{m_db:>2} dB g={g:<2}: LRA {l1[0]:.1f}  I {l1[1]:.1f} | 3s {s[3][0]:.1f} ({s[3][1]:.1f}) | 10s {s[10][0]:.1f} ({s[10][1]:.1f})")
