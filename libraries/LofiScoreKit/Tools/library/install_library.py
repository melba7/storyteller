"""Build the new LofiMusic library from the picked candidates.

Usage:
  python3 install_library.py PICKS.csv CANDIDATES_DIR NEW_LIBRARY_DIR
                             [--moods Somber,Melancholy] [--no-measure] [--measure-only]

PICKS.csv columns (header row): id, mood, file, title, artist, album, page, license,
license_name, attribution, source_file, sha256, local_path, and optionally process, changes.
  - file        path inside the new library, e.g. "Calm/Calm Waters - Purrple Cat.mp3"
  - local_path  path of the original inside CANDIDATES_DIR
  - process     empty: the original is copied as it is.
                "trim": silence is cut from the start and end.
                "even": the same, and loud and quiet passages are brought closer together.

Copies each original (never moves or deletes anything), checks its sha256, measures
integrated loudness and true peak with ffmpeg's ebur128 filter, and writes library.json
(the same shape lofi-import writes) and SOURCES.csv into NEW_LIBRARY_DIR. Refuses to copy
over a file that already exists with different content.

Why "trim" and "even" exist: solo piano recordings. The player starts a track from its
first sample, so two seconds of room silence is a late start. And a classical recording
can swing 20 LU between its quietest and loudest passage, where a lofi track swings 6;
under a voice the quiet half vanishes and the loud half pokes out. Evening out rides the
gain slowly (ffmpeg dynaudnorm, 7.5 s window, at most +10 dB), so notes keep their own
shape and only whole passages move. Measured on 12 recordings: the spread between 10 s
stretches fell from 10-16 dB to 4-10 dB, and the gain never moved faster than 4 dB a second.

Silence at the ends is what lies 45 dB under the recording's peak. A recording with an
audible room (a home recording, an old tape) never gets that quiet, so its hiss would pass
for music and a late start would stay. For those the room is taken to be the quietest
200 ms of the file, and the music starts at the first 100 ms that stay 10 dB above it.
On the 23 processed piano picks this moved three starts by 1.0 to 1.2 s and cut two tails.

Both steps can take a while. --moods limits the copy step to some folders so a run fits
in a short time slot; run it once per group with --no-measure, then once with
--measure-only. A run that is cut off can simply be repeated.
"""
import array
import csv
import hashlib
import json
import math
import os
import re
import shutil
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

MOODS = ["Calm", "Cozy", "Playful", "Hopeful", "Melancholy", "Mysterious",
         "Tense", "Somber", "Romantic", "Dreamy", "Adventurous"]

EVEN_MAX_BOOST_DB = 10.0      # how far a quiet passage may be raised
EVEN_WINDOW_FRAMES = 15       # x 0.5 s: the gain follows the loudest moment within 7.5 s
SILENCE_BELOW_PEAK_DB = 45.0  # what counts as silence at the ends
KEEP_LEAD_S = 0.05            # silence left before the first note
KEEP_TAIL_S = 1.5             # of the fading last note, kept and faded out
ROOM_WITHIN_PEAK_DB = 60.0    # a room this loud never counts as silence by the test above
ABOVE_ROOM_DB = 10.0          # ... so there a note is what rises this far above the room
ROOM_LEAD_S = 0.2             # and this much more is kept before it, for a soft attack


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def ffmpeg_log(args):
    cmd = ["ffmpeg", "-nostdin", "-hide_banner", "-nostats"] + args + ["-f", "null", "-"]
    return subprocess.run(cmd, capture_output=True, text=True, timeout=300).stderr


def duration_of(path):
    probe = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration",
                            "-of", "default=nw=1:nk=1", path], capture_output=True, text=True, timeout=60)
    return float(probe.stdout.strip()) if probe.stdout.strip() else None


def measure(path):
    err = ffmpeg_log(["-i", path, "-filter_complex", "ebur128=peak=true"])
    summary = err[err.rfind("Summary:"):]
    loud = re.search(r"I:\s+(-?[\d.]+) LUFS", summary)
    peak = re.search(r"True peak:\s+Peak:\s+(-?[\d.]+|-inf) dBFS", summary)
    lra = re.search(r"LRA:\s+([\d.]+) LU", summary)
    duration = duration_of(path)
    return {
        "loudness": round(float(loud.group(1)), 2) if loud else None,
        "truePeak": round(float(peak.group(1)), 2) if peak and peak.group(1) != "-inf" else None,
        "duration": round(duration, 3) if duration else None,
        "lra": float(lra.group(1)) if lra else None,
    }


def frame_levels(path, rate=4000, frame_s=0.05):
    """The level in dB of every 50 ms of a file. Plain Python, so it runs anywhere ffmpeg does."""
    cmd = ["ffmpeg", "-nostdin", "-v", "error", "-i", path, "-ac", "1", "-ar", str(rate), "-f", "s16le", "-"]
    raw = subprocess.run(cmd, capture_output=True, timeout=300).stdout
    samples = array.array("h")
    samples.frombytes(raw[: len(raw) // 2 * 2])
    if sys.byteorder == "big":
        samples.byteswap()
    n = int(rate * frame_s)
    levels = []
    for i in range(0, len(samples) - n + 1, n):
        chunk = samples[i:i + n]
        power = sum(x * x for x in chunk) / n
        levels.append(10 * math.log10(max(power, 1.0) / 32768.0 ** 2))
    return levels, frame_s


def room_span(path, peak):
    """(start, end) of the music in a recording whose room noise is too loud to count as silence.

    Returns None when the recording is quiet enough for the ordinary test. The room is taken
    to be the quietest 200 ms of the file; a note is 100 ms that stay ABOVE_ROOM_DB over it.
    """
    levels, step = frame_levels(path)
    if len(levels) < 40:
        return None
    room = min(sum(levels[i:i + 4]) / 4 for i in range(len(levels) - 3))
    if room < peak - ROOM_WITHIN_PEAK_DB:
        return None
    loud = [v > room + ABOVE_ROOM_DB for v in levels]
    notes = [i for i in range(len(loud) - 1) if loud[i] and loud[i + 1]]
    if not notes:
        return None
    return max(0.0, notes[0] * step - ROOM_LEAD_S), (notes[-1] + 2) * step


def sounding_span(path):
    """(peak dB, start, end, duration): where the music starts and where its last note has faded."""
    duration = duration_of(path)
    peak = float(re.search(r"max_volume: (-?[\d.]+) dB", ffmpeg_log(["-i", path, "-af", "volumedetect"])).group(1))
    err = ffmpeg_log(["-i", path, "-af", f"silencedetect=noise={peak - SILENCE_BELOW_PEAK_DB:.1f}dB:d=0.15"])
    starts = [float(x) for x in re.findall(r"silence_start: (-?[\d.]+)", err)]
    ends = [float(x) for x in re.findall(r"silence_end: (-?[\d.]+)", err)]
    start, end = 0.0, duration
    if starts and starts[0] <= 0.05 and ends:
        start = ends[0]                               # the file opens with silence
    if starts and (len(ends) < len(starts) or ends[-1] >= duration - 0.1) and starts[-1] > start:
        end = starts[-1]                              # and closes with it
    if start <= 0.0 or end >= duration:
        # No silence found at one end. Either the music fills the file, or the room is
        # audible (a home recording, an old tape) and its hiss passes for sound.
        room = room_span(path, peak)
        if room:
            if start <= 0.0 and room[0] > 0.3:
                start = room[0]
            if end >= duration and room[1] < duration - 0.3 and room[1] > start:
                end = room[1]
    return peak, max(0.0, start), min(duration, end), duration


def process(src, dst, mode, row, work_dir):
    """Write a trimmed (and for mode "even" an evened-out) MP3 of src to dst."""
    peak, first, last, duration = sounding_span(src)
    start = max(0.0, first - KEEP_LEAD_S)
    had_tail = last < duration - 0.05
    end = min(duration, last + KEEP_TAIL_S) if had_tail else duration
    length = end - start
    fade = min(KEEP_TAIL_S, length / 4) if had_tail else 0.3
    chain = [f"atrim=start={start:.3f}:end={end:.3f}", "asetpts=PTS-STARTPTS"]
    if mode == "even":
        boost = 10 ** (EVEN_MAX_BOOST_DB / 20)
        chain += [f"volume={-1.0 - peak:.2f}dB",
                  f"dynaudnorm=f=500:g={EVEN_WINDOW_FRAMES}:p=0.89:m={boost:.2f}"]
    chain += ["afade=t=in:d=0.03", f"afade=t=out:st={length - fade:.3f}:d={fade:.3f}"]
    os.makedirs(work_dir, exist_ok=True)
    part = os.path.join(work_dir, row["id"] + ".mp3")
    cmd = ["ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error", "-y", "-i", src,
           "-map", "0:a:0", "-af", ",".join(chain), "-c:a", "libmp3lame", "-q:a", "0",
           "-map_metadata", "-1", "-id3v2_version", "3",
           "-metadata", f"title={row['title']}", "-metadata", f"artist={row['artist']}",
           "-metadata", f"comment={row.get('changes') or mode}; source {row['page']}", part]
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
    if result.returncode != 0 or not os.path.exists(part) or os.path.getsize(part) < 20000:
        return f"ffmpeg failed: {result.stderr[-300:]}"
    os.replace(part, dst)       # only a finished file ever appears in the library
    return f"cut {start:.2f}s from the start and {duration - end:.2f}s from the end"


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    picks_path, cand_dir, lib_dir = args[:3]
    measure_only = "--measure-only" in sys.argv
    no_measure = "--no-measure" in sys.argv
    only = None
    if "--moods" in sys.argv:
        only = set(sys.argv[sys.argv.index("--moods") + 1].split(","))
    rows = list(csv.DictReader(open(picks_path, encoding="utf-8")))
    for mood in MOODS:
        os.makedirs(os.path.join(lib_dir, mood), exist_ok=True)
    work_dir = lib_dir.rstrip("/") + "-work"

    problems = []

    def place(r):
        src = os.path.join(cand_dir, r["local_path"])
        dst = os.path.join(lib_dir, r["file"])
        mode = (r.get("process") or "").strip()
        if os.path.exists(dst):
            if mode or sha256(dst) == r["sha256"]:
                return None
            return f"{r['file']}: exists with other content, left alone"
        if not os.path.exists(src):
            return f"{r['id']}: original missing at {src}"
        if sha256(src) != r["sha256"]:
            return f"{r['id']}: sha256 differs from the download record"
        if mode:
            note = process(src, dst, mode, r, work_dir)
            print(f"  {mode:<4} {r['file']}: {note}", flush=True)
            return None if os.path.exists(dst) else f"{r['id']}: {note}"
        shutil.copy2(src, dst)
        return None

    if not measure_only:
        todo = [r for r in rows if only is None or r["mood"] in only]
        with ThreadPoolExecutor(max_workers=4) as pool:
            problems += [p for p in pool.map(place, todo) if p]
        print(f"placed {len(todo) - len(problems)} of {len(todo)} files", flush=True)
    if no_measure:
        for p in problems:
            print("PROBLEM:", p)
        return

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
        if (r.get("process") or "").strip():
            print(f"  {r['process']:<4} {r['file']}: {m['duration']:.0f} s, {m['loudness']} LUFS, "
                  f"loudness range {m['lra']} LU")
    tracks.sort(key=lambda t: (MOODS.index(t["file"].split("/")[0]), t["file"].lower()))
    manifest = {"tracks": tracks, "version": 1}
    with open(os.path.join(lib_dir, "library.json"), "w", encoding="utf-8") as handle:
        handle.write(json.dumps(manifest, indent=2, sort_keys=True, ensure_ascii=False,
                                separators=(",", " : ")) + "\n")

    fields = ["mood", "file", "title", "artist", "album", "page", "license", "license_name",
              "attribution", "source_file", "sha256", "changes"]
    with open(os.path.join(lib_dir, "SOURCES.csv"), "w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, extrasaction="ignore", restval="")
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
