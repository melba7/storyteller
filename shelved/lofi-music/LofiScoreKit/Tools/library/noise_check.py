"""Hiss check: how far the quietest stretches of a recording sit under its music.

Usage: python -I noise_check.py ANALYSIS_DIR ID [ID ...]

Prints, per track: the level of the quietest 2% of 100 ms frames between the first and
last note (room noise or hiss, in dB), the median level of the louder half of frames,
and the gap between them. Also the same gap above 4 kHz, where hiss is easiest to hear
because a piano has little energy there.
"""
import subprocess, sys
import numpy as np

SR = 22050

def decode(path):
    cmd = ["ffmpeg", "-v", "error", "-nostdin", "-i", path, "-ac", "1", "-ar", str(SR), "-f", "f32le", "-"]
    return np.frombuffer(subprocess.run(cmd, capture_output=True, check=True).stdout, dtype=np.float32).astype(np.float64)

def frames_db(y, n):
    k = len(y) // n
    return 10 * np.log10((y[: k * n].reshape(k, n) ** 2).mean(axis=1) + 1e-14)

def main():
    adir, ids = sys.argv[1], sys.argv[2:]
    n = int(0.1 * SR)
    print(f"{'id':<6} {'quiet':>7} {'music':>7} {'gap':>6} {'hf quiet':>9} {'hf gap':>7}")
    for i in ids:
        y = decode(f"{adir}/{i}.m4a")
        e = frames_db(y, n)
        live = np.where(e > np.percentile(e, 99) - 45)[0]
        e = e[live[0]: live[-1] + 1]
        quiet = np.percentile(e, 2)
        music = np.median(e[e >= np.median(e)])
        # above 4 kHz: difference of adjacent samples twice is a crude high-pass; use FFT instead
        k = len(y) // n
        spec = np.abs(np.fft.rfft(y[: k * n].reshape(k, n) * np.hanning(n), axis=1)) ** 2
        f = np.fft.rfftfreq(n, 1 / SR)
        hf = 10 * np.log10(spec[:, f >= 4000].sum(axis=1) / n + 1e-14)[live[0]: live[-1] + 1]
        hq = np.percentile(hf, 2)
        print(f"{i:<6} {quiet:7.1f} {music:7.1f} {music - quiet:6.1f} {hq:9.1f} {music - hq:7.1f}")

if __name__ == "__main__":
    main()
