"""Second YAMNet pass for the solo-piano check: which instruments sound, and when.

Usage: python -I instruments.py OUT.jsonl YAMNET_DIR --list FILE_WITH_PATHS

analyze.py keeps only track-wide averages of the instrument classes. A string pad that
enters for the last minute, or a soft beat under half the track, hardly moves an average,
so this pass keeps, for each group of instruments, the mean score, the 95th percentile,
the share of the track where the group is clearly present, and a coarse curve over time
(the highest score in every 10 seconds). Appends one JSON line per file and skips files
already in OUT.jsonl.
"""
import json
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import analyze  # noqa: E402  (decode, Yamnet)

GROUPS = {
    "piano": ["Piano", "Keyboard (musical)"],
    "epiano": ["Electric piano"],
    "drums": ["Drum kit", "Drum", "Snare drum", "Bass drum", "Hi-hat", "Cymbal", "Drum machine", "Rimshot",
              "Drum roll", "Percussion", "Tabla", "Wood block", "Tambourine", "Maraca", "Timpani",
              "Finger snapping", "Clapping"],
    "strings": ["Bowed string instrument", "String section", "Violin, fiddle", "Cello", "Double bass",
                "Pizzicato", "Orchestra"],
    "synth": ["Synthesizer", "Sampler", "Theremin", "Electronic music", "Drone"],
    "ambient": ["Ambient music", "New-age music"],
    "guitar": ["Guitar", "Acoustic guitar", "Electric guitar", "Bass guitar", "Plucked string instrument",
               "Harp", "Mandolin", "Zither", "Ukulele", "Banjo", "Sitar"],
    "winds": ["Flute", "Saxophone", "Clarinet", "Trumpet", "Trombone", "French horn", "Brass instrument",
              "Wind instrument, woodwind instrument", "Harmonica", "Accordion", "Bagpipes", "Didgeridoo"],
    "otherkeys": ["Organ", "Electronic organ", "Hammond organ", "Harpsichord", "Mallet percussion",
                  "Marimba, xylophone", "Glockenspiel", "Vibraphone", "Steelpan", "Music box"],
    "bells": ["Bell", "Chime", "Wind chime", "Tubular bells", "Church bell", "Jingle bell", "Singing bowl"],
    "voice": analyze.VOCAL_SPEECH + analyze.VOCAL_SINGING,
    "nature": ["Rain", "Rain on surface", "Raindrop", "Wind", "Bird", "Bird vocalization, bird call, bird song",
               "Water", "Stream", "Ocean", "Waves, surf", "Thunder", "Thunderstorm", "Fire", "Crackle",
               "Rustling leaves", "Cricket", "Insect"],
    "noise": ["White noise", "Pink noise", "Static", "Hum", "Environmental noise", "Noise", "Hiss"],
    "applause": ["Applause", "Cheering", "Crowd", "Cough", "Throat clearing"],
}


def main():
    out_path, yamnet_dir = sys.argv[1], sys.argv[2]
    files = [line.strip() for line in open(sys.argv[4]) if line.strip()]
    done = set()
    if os.path.exists(out_path):
        done = {json.loads(line)["path"] for line in open(out_path) if line.strip()}
    todo = [f for f in files if f not in done]
    print(f"{len(todo)} to do ({len(done)} done before)", flush=True)
    yam = analyze.Yamnet(yamnet_dir)
    missing = sorted({n for names in GROUPS.values() for n in names if n not in yam.index})
    if missing:
        print("not in the class map:", ", ".join(missing), flush=True)
    hop = yam.params.patch_hop_seconds
    step = max(1, int(round(10 / hop)))
    with open(out_path, "a") as out:
        for n, f in enumerate(todo, 1):
            try:
                y = analyze.decode(f, 16000)
                scores = yam.model(y)[0].numpy()
            except Exception as error:
                out.write(json.dumps({"path": f, "error": str(error)[:200]}) + "\n")
                continue
            row = {"path": f, "frames": int(len(scores))}
            for g, names in GROUPS.items():
                idx = yam.idx(names)
                s = scores[:, idx].max(axis=1)
                best = int(np.argmax(scores[:, idx].mean(axis=0)))
                row[g] = {
                    "mean": round(float(s.mean()), 4),
                    "p95": round(float(np.percentile(s, 95)), 4),
                    "f15": round(float((s > 0.15).mean()), 4),
                    "f30": round(float((s > 0.30).mean()), 4),
                    "top": yam.names[idx[best]],
                    "curve": [round(float(s[i:i + step].max()), 2) for i in range(0, len(s), step)],
                }
            mean = scores.mean(axis=0)
            row["top"] = [(yam.names[i], round(float(mean[i]), 3)) for i in np.argsort(-mean)[:10]]
            out.write(json.dumps(row) + "\n")
            out.flush()
            if n % 20 == 0 or n == len(todo):
                print(f"{n}/{len(todo)}", flush=True)


if __name__ == "__main__":
    main()
