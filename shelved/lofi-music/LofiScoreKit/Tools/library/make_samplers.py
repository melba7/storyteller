"""One short listening sampler per mood: an excerpt of every track, crossfaded.

Usage: python3 make_samplers.py LIBRARY_DIR OUT_DIR [SECONDS_PER_TRACK] [CROSSFADE]

Reads LIBRARY_DIR/library.json, takes SECONDS_PER_TRACK (default 16) from 40% into each
track, levels every excerpt to -16 LUFS from its measured loudness, crossfades them and
writes OUT_DIR/<Mood>.m4a plus OUT_DIR/<Mood>.txt with what plays when.
"""
import json
import os
import subprocess
import sys

MOODS = ["Calm", "Cozy", "Playful", "Hopeful", "Melancholy", "Mysterious",
         "Tense", "Somber", "Romantic", "Dreamy", "Adventurous"]


def main():
    lib, out = sys.argv[1], sys.argv[2]
    seconds = float(sys.argv[3]) if len(sys.argv) > 3 else 16.0
    fade = float(sys.argv[4]) if len(sys.argv) > 4 else 2.5
    only = set(sys.argv[5].split(",")) if len(sys.argv) > 5 else None
    os.makedirs(out, exist_ok=True)
    manifest = json.load(open(os.path.join(lib, "library.json"), encoding="utf-8"))
    for mood in MOODS:
        if only and mood not in only:
            continue
        tracks = [t for t in manifest["tracks"] if t["file"].startswith(mood + "/")]
        if not tracks:
            continue
        cmd = ["ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error", "-y"]
        filters = []
        lines = []
        t0 = 0.0
        for n, t in enumerate(tracks):
            duration = t.get("duration") or 180
            start = max(10.0, 0.4 * duration)
            cmd += ["-ss", f"{start:.2f}", "-t", f"{seconds + fade:.2f}", "-i", os.path.join(lib, t["file"])]
            gain = -16.0 - (t.get("loudness") if t.get("loudness") is not None else -16.0)
            filters.append(f"[{n}:a]aresample=44100,aformat=channel_layouts=stereo,volume={gain:.2f}dB[a{n}]")
            name = os.path.splitext(os.path.basename(t["file"]))[0]
            lines.append(f"{int(t0 // 60)}:{int(t0 % 60):02d}  {name}  (from {int(start // 60)}:{int(start % 60):02d})")
            t0 += seconds
        chain = "[a0]"
        for n in range(1, len(tracks)):
            label = f"[x{n}]"
            filters.append(f"{chain}[a{n}]acrossfade=d={fade}:c1=tri:c2=tri{label}")
            chain = label
        last = len(tracks) - 1
        filters.append(f"{chain}afade=t=in:d=1,areverse,afade=t=in:d=2,areverse[out]" if last >= 0 else "")
        cmd += ["-filter_complex", ";".join(f for f in filters if f), "-map", "[out]",
                "-c:a", "aac", "-b:a", "192k", os.path.join(out, f"{mood}.m4a")]
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=170)
        if result.returncode != 0:
            print(mood, "FAILED:", result.stderr[-500:])
            continue
        with open(os.path.join(out, f"{mood}.txt"), "w", encoding="utf-8") as handle:
            handle.write(f"{mood}: {len(tracks)} tracks, {seconds:.0f} s of each, levelled to -16 LUFS\n\n")
            handle.write("\n".join(lines) + "\n")
        print(f"{mood}: {len(tracks)} excerpts")


if __name__ == "__main__":
    main()
