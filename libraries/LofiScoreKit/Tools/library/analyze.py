"""Measure candidate lofi tracks so they can be vetted without listening.

Usage: python -I analyze.py OUT_DIR YAMNET_DIR AUDIO_FILE [AUDIO_FILE ...]
       python -I analyze.py OUT_DIR YAMNET_DIR --list FILE_WITH_PATHS

Writes OUT_DIR/features.csv (one row per file, appended; files already listed are
skipped) and OUT_DIR/yamnet/<sha1 of path>.json with the frame-level vocal curve
and the track's top AudioSet classes. Audio is decoded with ffmpeg into memory;
nothing in the audio files is executed or imported.
"""
import csv
import hashlib
import json
import math
import os
import subprocess
import sys
import multiprocessing
from concurrent.futures import ProcessPoolExecutor

import numpy as np

SR = 22050

VOCAL_SPEECH = [
    "Speech", "Child speech, kid speaking", "Conversation", "Narration, monologue",
    "Babbling", "Speech synthesizer", "Shout", "Whispering", "Laughter",
]
VOCAL_SINGING = [
    "Singing", "Choir", "Yodeling", "Chant", "Mantra", "Male singing", "Female singing",
    "Child singing", "Synthetic singing", "Rapping", "Humming", "Vocal music", "A capella",
]
MOOD_CLASSES = [
    "Happy music", "Funny music", "Sad music", "Tender music", "Exciting music",
    "Angry music", "Scary music",
]
STYLE_CLASSES = [
    "Hip hop music", "Jazz", "Ambient music", "Electronic music", "Piano", "Electric piano",
    "Guitar", "Acoustic guitar", "Synthesizer", "Drum machine", "Drum", "Bass guitar",
    "Rain", "Rain on surface", "Vinyl", "Christmas music", "Lullaby", "Video game music",
    "Soundtrack music", "Background music", "New-age music", "Music",
    "Orchestra", "String section", "Bell", "Chime", "Wind chime", "Whistling", "Saxophone",
    "Trumpet", "Flute", "Harp", "Glockenspiel", "Theremin",
]

MAJOR = np.array([6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88])
MINOR = np.array([6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17])
NOTES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]


def decode(path, sr):
    cmd = ["ffmpeg", "-v", "error", "-nostdin", "-i", path, "-ac", "1", "-ar", str(sr), "-f", "f32le", "-"]
    out = subprocess.run(cmd, capture_output=True, check=True, timeout=300).stdout
    return np.frombuffer(out, dtype=np.float32).copy()


def key_of(chroma_mean):
    best = None
    for shift in range(12):
        rolled = np.roll(chroma_mean, -shift)
        for mode, profile in (("major", MAJOR), ("minor", MINOR)):
            r = np.corrcoef(rolled, profile)[0, 1]
            if best is None or r > best[0]:
                best = (r, NOTES[shift], mode)
    # Mode clarity: best major vs best minor correlation.
    majors = [np.corrcoef(np.roll(chroma_mean, -s), MAJOR)[0, 1] for s in range(12)]
    minors = [np.corrcoef(np.roll(chroma_mean, -s), MINOR)[0, 1] for s in range(12)]
    return best[1], best[2], float(best[0]), float(max(majors) - max(minors))


def librosa_features(path):
    import librosa
    import pyloudnorm

    y = decode(path, SR)
    duration = len(y) / SR
    if duration < 20:
        return {"path": path, "error": f"too short ({duration:.1f} s)"}
    meter = pyloudnorm.Meter(SR)
    try:
        lufs = float(meter.integrated_loudness(y.astype(np.float64)))
    except Exception:
        lufs = float("nan")
    # Short-term loudness spread (3 s windows) as a rough loudness range.
    win = 3 * SR
    st = []
    for start in range(0, len(y) - win, SR):
        seg = y[start:start + win].astype(np.float64)
        ms = np.mean(seg * seg)
        if ms > 1e-10:
            st.append(10 * math.log10(ms))
    st = np.array(st) if st else np.array([0.0])
    lra = float(np.percentile(st, 95) - np.percentile(st, 10))

    # Analyse at most the middle 150 s for speed.
    mid = len(y) // 2
    half = min(len(y) // 2, 75 * SR)
    seg = y[mid - half: mid + half]
    onset_env = librosa.onset.onset_strength(y=seg, sr=SR)
    tempo = float(np.atleast_1d(librosa.feature.tempo(onset_envelope=onset_env, sr=SR))[0])
    onsets = librosa.onset.onset_detect(onset_envelope=onset_env, sr=SR)
    onset_rate = len(onsets) / (len(seg) / SR)
    harmonic, percussive = librosa.effects.hpss(seg)
    eh = float(np.sum(harmonic.astype(np.float64) ** 2))
    ep = float(np.sum(percussive.astype(np.float64) ** 2))
    perc_ratio = ep / (eh + ep + 1e-12)
    # tuning=0 skips librosa's tuning estimate, whose numba peak finder crashes here.
    chroma = librosa.feature.chroma_cqt(y=harmonic, sr=SR, tuning=0.0)
    key, mode, key_r, mode_clarity = key_of(chroma.mean(axis=1))
    centroid = float(np.mean(librosa.feature.spectral_centroid(y=seg, sr=SR)))
    rolloff = float(np.mean(librosa.feature.spectral_rolloff(y=seg, sr=SR, roll_percent=0.85)))
    flatness = float(np.mean(librosa.feature.spectral_flatness(y=seg)))
    spec = np.abs(librosa.stft(seg, n_fft=2048, hop_length=1024)) ** 2
    freqs = librosa.fft_frequencies(sr=SR, n_fft=2048)
    total = spec.sum() + 1e-12
    bass = float(spec[freqs < 150].sum() / total)
    presence = float(spec[(freqs >= 1500) & (freqs < 4000)].sum() / total)
    rms = librosa.feature.rms(y=seg)[0]
    rms_db = 20 * np.log10(rms + 1e-6)
    dyn = float(np.std(rms_db))
    return {
        "path": path,
        "duration": round(duration, 1),
        "lufs": round(lufs, 1),
        "lra": round(lra, 1),
        "tempo": round(tempo, 1),
        "onset_rate": round(onset_rate, 2),
        "perc_ratio": round(perc_ratio, 3),
        "key": key,
        "mode": mode,
        "key_r": round(key_r, 3),
        "mode_clarity": round(mode_clarity, 3),
        "centroid": round(centroid),
        "rolloff": round(rolloff),
        "flatness": round(flatness, 4),
        "bass": round(bass, 3),
        "presence": round(presence, 4),
        "dyn": round(dyn, 2),
    }


class Yamnet:
    def __init__(self, folder):
        sys.path.insert(0, folder)
        import params as yamnet_params  # noqa: E402  (official tensorflow/models code)
        import yamnet as yamnet_model  # noqa: E402
        self.params = yamnet_params.Params()
        self.model = yamnet_model.yamnet_frames_model(self.params)
        self.model.load_weights(os.path.join(folder, "yamnet.h5"))
        self.names = list(yamnet_model.class_names(os.path.join(folder, "yamnet_class_map.csv")))
        self.index = {name: i for i, name in enumerate(self.names)}

    def idx(self, names):
        return [self.index[n] for n in names if n in self.index]

    def run(self, path):
        y = decode(path, 16000)
        scores, _, _ = self.model(y)
        s = scores.numpy()
        speech = s[:, self.idx(VOCAL_SPEECH)].max(axis=1)
        singing = s[:, self.idx(VOCAL_SINGING)].max(axis=1)
        vocal = np.maximum(speech, singing)
        mean = s.mean(axis=0)
        top = np.argsort(-mean)[:12]
        hop = self.params.patch_hop_seconds
        # Seconds with clear vocals, and the longest run of them.
        clear = vocal > 0.35
        runs, run = [], 0
        for flag in clear:
            run = run + 1 if flag else 0
            runs.append(run)
        return {
            "speech_frac": float(np.mean(speech > 0.35)),
            "singing_frac": float(np.mean(singing > 0.3)),
            "vocal_frac": float(np.mean(clear)),
            "vocal_max": float(vocal.max()),
            "vocal_longest_s": round(max(runs) * hop if runs else 0, 1),
            "speech_mean": float(speech.mean()),
            "singing_mean": float(singing.mean()),
            "moods": {n: round(float(mean[self.index[n]]), 4) for n in MOOD_CLASSES if n in self.index},
            "styles": {n: round(float(mean[self.index[n]]), 4) for n in STYLE_CLASSES if n in self.index},
            "top": [(self.names[i], round(float(mean[i]), 4)) for i in top],
            "vocal_curve": [round(float(v), 2) for v in vocal[:: max(1, int(round(2 / hop)))]],
        }


def main():
    out_dir, yamnet_dir = sys.argv[1], sys.argv[2]
    args = sys.argv[3:]
    if args and args[0] == "--list":
        with open(args[1]) as handle:
            files = [line.rstrip("\n") for line in handle if line.strip()]
    else:
        files = args
    os.makedirs(os.path.join(out_dir, "yamnet"), exist_ok=True)
    table = os.path.join(out_dir, "features.csv")
    done = set()
    if os.path.exists(table):
        with open(table) as handle:
            done = {row["path"] for row in csv.DictReader(handle)}
    todo = [f for f in files if f not in done]
    print(f"{len(todo)} to analyse ({len(done)} done before)", flush=True)
    if not todo:
        return

    fields = None
    # Spawned workers never inherit TensorFlow's state from this process.
    with ProcessPoolExecutor(max_workers=3, mp_context=multiprocessing.get_context("spawn")) as pool:
        futures = {f: pool.submit(librosa_features, f) for f in todo}
        yam = Yamnet(yamnet_dir)
        for n, f in enumerate(todo, 1):
            try:
                row = futures[f].result()
            except Exception as error:  # a broken file: note it and go on
                row = {"path": f, "error": f"{type(error).__name__}: {error}"[:200]}
            if "error" not in row:
                try:
                    v = yam.run(f)
                    key = hashlib.sha1(f.encode()).hexdigest()[:16]
                    with open(os.path.join(out_dir, "yamnet", key + ".json"), "w") as handle:
                        json.dump({"path": f, **v}, handle)
                    row.update({
                        "speech_frac": round(v["speech_frac"], 3),
                        "singing_frac": round(v["singing_frac"], 3),
                        "vocal_frac": round(v["vocal_frac"], 3),
                        "vocal_max": round(v["vocal_max"], 3),
                        "vocal_longest_s": v["vocal_longest_s"],
                        **{"m_" + k.split()[0].lower(): val for k, val in v["moods"].items()},
                        "top3": "; ".join(f"{name} {score:.2f}" for name, score in v["top"][:5]),
                    })
                except Exception as error:
                    row["error"] = f"yamnet {type(error).__name__}: {error}"[:200]
            if fields is None:
                fields = [
                    "path", "error", "duration", "lufs", "lra", "tempo", "onset_rate", "perc_ratio",
                    "key", "mode", "key_r", "mode_clarity", "centroid", "rolloff", "flatness", "bass",
                    "presence", "dyn", "speech_frac", "singing_frac", "vocal_frac", "vocal_max",
                    "vocal_longest_s", "m_happy", "m_funny", "m_sad", "m_tender", "m_exciting",
                    "m_angry", "m_scary", "top3",
                ]
            new = not os.path.exists(table)
            with open(table, "a", newline="") as handle:
                writer = csv.DictWriter(handle, fieldnames=fields, extrasaction="ignore")
                if new:
                    writer.writeheader()
                writer.writerow(row)
            if n % 10 == 0 or n == len(todo):
                print(f"{n}/{len(todo)}", flush=True)


if __name__ == "__main__":
    main()
