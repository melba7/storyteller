"""Build the new LofiMusic library from the picked candidates.

Usage:
  python3 install_library.py PICKS.csv CANDIDATES_DIR NEW_LIBRARY_DIR [--measure-only]

PICKS.csv columns (header row): id, mood, file, title, artist, album, page, license,
license_name, attribution, source_file, sha256, local_path.
  - file        path inside the new library, e.g. "Calm/Calm Waters - Purrple Cat.mp3"
  - local_path  path of the original inside CANDIDATES_DIR

Copies each original (never moves or deletes anything), checks its sha256, measures
integrated loudness and true peak with ffmpeg's ebur128 filter, and writes library.json
(the same shape lofi-import writes) and SOURCES.csv into NEW_LIBRARY_DIR. Refuses to copy
over a file that already exists with different content.
"""
import csv
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

MOODS = ["Calm", "Cozy", "Playful", "Hopeful", "Melancholy", "Mysterious",
         "Tense", "Somber", "Romantic", "Dreamy", "Adventurous"]


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def measure(path):
    cmd = ["ffmpeg", "-nostdin", "-hide_banner", "-nostats", "-i", path,
           "-filter_complex", "ebur128=peak=true", "-f", "null", "-"]
    err = subprocess.run(cmd, capture_output=True, text=True, timeout=300).stderr
    summary = err[err.rfind("Summary:"):]
    loud = re.search(r"I:\s+(-?[\d.]+) LUFS", summary)
    peak = re.search(r"True peak:\s+Peak:\s+(-?[\d.]+|-inf) dBFS", summary)
    probe = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration",
                            "-of", "default=nw=1:nk=1", path], capture_output=True, text=True, timeout=60)
    duration = float(probe.stdout.strip()) if probe.stdout.strip() else None
    return {
        "loudness": round(float(loud.group(1)), 2) if loud else None,
        "truePeak": round(float(peak.group(1)), 2) if peak and peak.group(1) != "-inf" else None,
        "duration": round(duration, 3) if duration else None,
    }


def main():
    picks_path, cand_dir, lib_dir = sys.argv[1:4]
    measure_only = "--measure-only" in sys.argv
    rows = list(csv.DictReader(open(picks_path, encoding="utf-8")))
    for mood in MOODS:
        os.makedirs(os.path.join(lib_dir, mood), exist_ok=True)

    problems = []
    if not measure_only:
        for r in rows:
            src = os.path.join(cand_dir, r["local_path"])
            dst = os.path.join(lib_dir, r["file"])
            if os.path.exists(dst):
                if sha256(dst) == r["sha256"]:
                    continue
                problems.append(f"{r['file']}: exists with other content, left alone")
                continue
            if not os.path.exists(src):
                problems.append(f"{r['id']}: original missing at {src}")
                continue
            if sha256(src) != r["sha256"]:
                problems.append(f"{r['id']}: sha256 differs from the download record")
                continue
            shutil.copy2(src, dst)

    def one(r):
        path = os.path.join(lib_dir, r["file"])
        return r, (measure(path) if os.path.exists(path) else None)

    with ThreadPoolExecutor(max_workers=4) as pool:
        measured = list(pool.map(one, rows))

    tracks = []
    for r, m in measured:
        if m is None:
            problems.append(f"{r['file']}: not in the library, not measured")
            continue
        stem = os.path.splitext(os.path.basename(r["file"]))[0]
        track = {
            "bucket": r["mood"].lower(),
            "file": r["file"],
            "id": f"{r['mood'].lower()}/{stem}",
            "license": r["license"],
            "source": r["page"],
        }
        for key in ("duration", "loudness", "truePeak"):
            if m.get(key) is not None:
                track[key] = m[key]
        tracks.append(track)
    tracks.sort(key=lambda t: (MOODS.index(t["file"].split("/")[0]), t["file"].lower()))
    manifest = {"tracks": tracks, "version": 1}
    with open(os.path.join(lib_dir, "library.json"), "w", encoding="utf-8") as handle:
        handle.write(json.dumps(manifest, indent=2, sort_keys=True, ensure_ascii=False,
                                separators=(",", " : ")) + "\n")

    fields = ["mood", "file", "title", "artist", "album", "page", "license", "license_name",
              "attribution", "source_file", "sha256"]
    with open(os.path.join(lib_dir, "SOURCES.csv"), "w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, extrasaction="ignore")
        writer.writeheader()
        for r in sorted(rows, key=lambda r: (MOODS.index(r["mood"]), r["file"].lower())):
            writer.writerow(r)

    louds = [t["loudness"] for t in tracks if "loudness" in t]
    print(f"{len(tracks)} tracks in library.json; loudness {min(louds):.1f} to {max(louds):.1f} LUFS, "
          f"mean {sum(louds) / len(louds):.1f}" if louds else f"{len(tracks)} tracks, none measured")
    for mood in MOODS:
        n = sum(1 for t in tracks if t["file"].startswith(mood + "/"))
        print(f"  {mood:<12}{n}")
    for p in problems:
        print("PROBLEM:", p)


if __name__ == "__main__":
    main()
