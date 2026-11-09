#!/usr/bin/env python3
"""Fetch free recordings for the atmosphere sounds, with their credits.

Runs on Mo's Mac (it needs the network, python3 and ffmpeg). For each of the 26
atmosphere sounds it searches for steady recordings, keeps only CC0, CC BY and
CC BY-SA ones (read from each recording's own record, never assumed), cuts a
seamless loop from the steadiest part, measures its loudness, and writes:

    ~/Storyteller Lofi/Atmosphere/
        Rain/rain-fs123456.m4a ...   one folder per sound
        sounds.json                  loudness, duration, title, author, source, licence
        SOURCES.csv                  the same, one row per recording
        CREDITS.md                   the attribution CC BY and BY-SA ask for

Copy that Atmosphere folder into the music folder (next to Calm/, Cozy/, ...)
before importing the music folder in the app. Sounds with no recording keep the
app's synthesised stand-ins.

Sources:
  freesound  Freesound's API, when ~/Storyteller Lofi/.freesound-key holds an API
             key (free: https://freesound.org/apiv2/apply). Best choice.
  commons    Wikimedia Commons, no key needed. Fewer and rougher recordings.

    python3 -I fetch_ambience.py [--source freesound|commons] [--per-sound 2]
                                 [--sound rain] [--out DIR] [--dry-run]

Audio is never committed: the fork is public. Run with python3 -I and keep the
downloads folder away from this script.
"""

import argparse
import csv
import json
import re
import shutil
import subprocess
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path.home() / "Storyteller Lofi"
USER_AGENT = "StorytellerLofi-atmosphere/1.0 (personal app; python urllib)"

# What to search for, per sound (folder name as the app expects it). Steady beds
# only: the narrator must stay easy to follow, so nothing with words, music or
# sudden one-off events.
QUERIES = {
    "Rain": ["light rain ambience", "gentle rain"],
    "HeavyRain": ["heavy rain downpour", "heavy rain ambience"],
    "RainIndoors": ["rain on window", "rain on roof interior"],
    "Thunder": ["distant thunderstorm rain", "thunder rumble rain ambience"],
    "Wind": ["gentle wind ambience", "soft wind"],
    "StrongWind": ["strong wind howling", "storm wind gusts"],
    "Snow": ["winter wind snow ambience", "snowy quiet winter ambience"],
    "Fireplace": ["fireplace crackling", "fireplace fire crackle"],
    "Campfire": ["campfire crackling outdoors", "campfire night"],
    "SeaShore": ["waves beach ambience", "ocean waves shore"],
    "OpenSea": ["open sea waves boat", "ocean swell"],
    "River": ["river stream ambience", "babbling brook"],
    "Dripping": ["cave dripping water", "water drips cave ambience"],
    "Forest": ["forest ambience day", "woodland ambience birds wind"],
    "Birdsong": ["birdsong morning", "dawn chorus birds"],
    "NightInsects": ["crickets night", "night insects ambience"],
    "NightForest": ["night forest ambience", "forest at night owl"],
    "Swamp": ["swamp frogs night", "marsh frogs ambience"],
    "Crowd": ["crowd murmur indoor", "walla crowd indistinct", "school hallway ambience"],
    "City": ["city street ambience", "city traffic distant ambience"],
    "OldTown": ["medieval town ambience", "market square ambience horses"],
    "Horses": ["horse carriage hooves cobblestones", "horse drawn carriage"],
    "Train": ["train interior ambience", "steam train journey"],
    "Ship": ["ship creaking wood", "sailing ship ambience"],
    "Machinery": ["factory machinery ambience", "engine room ambience"],
    "Clock": ["clock ticking", "grandfather clock ticking"],
}

# Words in a title or tags that mean the recording would fight the narrator.
AVOID = re.compile(
    r"\b(music|song|melody|singing|voice ?over|speech|talking|dialogue|narrat|announcement|"
    r"radio|tv|television|scream|explosion|gunshot|siren|alarm|horror|scary|"
    r"synth|drone music|meditation music|asmr)\b",
    re.I,
)
SPEECH_OK = {"Crowd"}

ALLOWED = {
    "cc0": "CC0 1.0",
    "by": "CC BY",
    "by-sa": "CC BY-SA",
}

LOOP_SECONDS = 60
CROSSFADE = 3.0


def note(text):
    print(text, file=sys.stderr, flush=True)


def fetch_json(url, params=None):
    if params:
        url = url + "?" + urllib.parse.urlencode(params)
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=60) as response:
        return json.load(response)


def download(url, path):
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=300) as response, open(path, "wb") as out:
        shutil.copyfileobj(response, out)


def licence_kind(text):
    """'cc0', 'by' or 'by-sa' for licences we may use, else None (NC, ND, unknown)."""
    t = (text or "").lower()
    if "publicdomain/zero" in t or re.search(r"\bcc0\b|creative commons 0", t):
        return "cc0"
    if "nc" in re.split(r"[^a-z]+", t) or "noncommercial" in t or "non-commercial" in t:
        return None
    if "/nd" in t or "-nd" in t or "noderiv" in t or re.search(r"\bnd\b", t):
        return None
    if "licenses/by-sa" in t or re.search(r"\bby-sa\b|attribution-sharealike|cc by-sa", t):
        return "by-sa"
    if "licenses/by/" in t or re.search(r"^cc by\b|\bcc by \d|^attribution$|attribution \d", t):
        return "by"
    return None


# MARK: - Sources


class Freesound:
    name = "freesound"

    def __init__(self, key):
        self.key = key

    def search(self, query):
        data = fetch_json(
            "https://freesound.org/apiv2/search/text/",
            {
                "query": query,
                "filter": 'duration:[45 TO 1200] license:("Creative Commons 0" OR "Attribution")',
                "sort": "rating_desc",
                "page_size": 30,
                "fields": "id,name,username,license,duration,url,previews,avg_rating,num_ratings,num_downloads,tags,channels,samplerate",
                "token": self.key,
            },
        )
        time.sleep(1)
        for item in data.get("results", []):
            yield {
                "key": f"fs{item['id']}",
                "title": item.get("name", ""),
                "author": item.get("username", ""),
                "licence_text": item.get("license", ""),
                "page": item.get("url", ""),
                "duration": float(item.get("duration") or 0),
                "tags": " ".join(item.get("tags") or []),
                "score": (item.get("avg_rating") or 0) * min(1, (item.get("num_ratings") or 0) / 5)
                + min(2, (item.get("num_downloads") or 0) / 2000),
                "audio": (item.get("previews") or {}).get("preview-hq-ogg")
                or (item.get("previews") or {}).get("preview-hq-mp3"),
            }

    def confirm(self, candidate):
        """Re-reads the sound's own record and returns its licence kind."""
        sound_id = candidate["key"][2:]
        data = fetch_json(f"https://freesound.org/apiv2/sounds/{sound_id}/", {"fields": "license,username,name", "token": self.key})
        time.sleep(1)
        candidate["licence_text"] = data.get("license", candidate["licence_text"])
        return licence_kind(candidate["licence_text"])


class Commons:
    name = "commons"

    def search(self, query):
        data = fetch_json(
            "https://commons.wikimedia.org/w/api.php",
            {
                "action": "query",
                "format": "json",
                "generator": "search",
                "gsrsearch": f"{query} filetype:audio",
                "gsrnamespace": 6,
                "gsrlimit": 30,
                "prop": "imageinfo",
                "iiprop": "url|extmetadata|size",
            },
        )
        time.sleep(1)
        pages = (data.get("query") or {}).get("pages") or {}
        for page in pages.values():
            info = (page.get("imageinfo") or [{}])[0]
            meta = info.get("extmetadata") or {}
            value = lambda k: re.sub(r"<[^>]+>", "", (meta.get(k) or {}).get("value", "")).strip()
            yield {
                "key": f"wc{page.get('pageid')}",
                "title": page.get("title", "").removeprefix("File:"),
                "author": value("Artist") or "unknown",
                "licence_text": value("LicenseShortName") + " " + value("LicenseUrl"),
                "page": info.get("descriptionurl", ""),
                "duration": 0.0,
                "tags": value("ImageDescription"),
                "score": 0.0,
                "audio": info.get("url"),
            }

    def confirm(self, candidate):
        return licence_kind(candidate["licence_text"])


# MARK: - Audio


def probe_duration(path):
    out = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", str(path)],
        capture_output=True, text=True,
    )
    try:
        return float(out.stdout.strip())
    except ValueError:
        return 0.0


def steadiest_start(path, duration, length):
    """Start time of the `length`-second stretch with the least change in loudness."""
    if duration <= length + CROSSFADE + 2:
        return 0.0
    out = subprocess.run(
        ["ffmpeg", "-hide_banner", "-nostats", "-i", str(path), "-af",
         "astats=metadata=1:reset=1,ametadata=print:key=lavfi.astats.Overall.RMS_level", "-f", "null", "-"],
        capture_output=True, text=True,
    )
    levels = [float(v) for v in re.findall(r"RMS_level=(-?[0-9.]+)", out.stdout + out.stderr) if v not in ("-inf",)]
    if len(levels) < 10:
        return min(10.0, max(0.0, duration - length - CROSSFADE))
    step = duration / len(levels)
    window = max(1, int(length / step))
    best, best_start = None, 0.0
    for i in range(0, max(1, len(levels) - window - int(CROSSFADE / step)), max(1, window // 10)):
        part = levels[i:i + window]
        mean = sum(part) / len(part)
        spread = (sum((x - mean) ** 2 for x in part) / len(part)) ** 0.5
        # Steady, and not near-silent.
        cost = spread + max(0, -50 - mean)
        if best is None or cost < best:
            best, best_start = cost, i * step
    return best_start


def make_loop(source, target, start, length):
    """A seamless loop: the stretch's own continuation crossfades into its start."""
    x = CROSSFADE
    # The file is opened twice (one input per stretch): amix stalls on two trims of one stream.
    graph = (
        "[0:a]aformat=sample_rates=44100:channel_layouts=stereo,asetpts=PTS-STARTPTS,"
        f"afade=t=in:d={x}:curve=qsin[a];"
        "[1:a]aformat=sample_rates=44100:channel_layouts=stereo,asetpts=PTS-STARTPTS,"
        f"afade=t=out:d={x}:curve=qsin[b];"
        "[a][b]amix=inputs=2:duration=first:normalize=0[out]"
    )
    wav = target.with_suffix(".loop.wav")
    subprocess.run(
        ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
         "-ss", f"{start:.3f}", "-t", f"{length:.3f}", "-i", str(source),
         "-ss", f"{start + length:.3f}", "-t", f"{x:.3f}", "-i", str(source),
         "-filter_complex", graph, "-map", "[out]", "-c:a", "pcm_s16le", str(wav)],
        check=True,
    )
    try:
        if shutil.which("afconvert"):
            # Apple's AAC encoder records its priming and padding, so the phone loops the
            # file without a tick; ffmpeg's AAC can leave a few milliseconds at the seam.
            subprocess.run(["afconvert", "-f", "m4af", "-d", "aac", "-b", "160000", str(wav), str(target)], check=True)
        else:
            subprocess.run(
                ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", str(wav), "-c:a", "aac", "-b:a", "160k", str(target)],
                check=True,
            )
    finally:
        wav.unlink(missing_ok=True)


def loudness(path):
    out = subprocess.run(
        ["ffmpeg", "-hide_banner", "-nostats", "-i", str(path), "-af", "ebur128=framelog=quiet", "-f", "null", "-"],
        capture_output=True, text=True,
    )
    found = re.findall(r"I:\s+(-?[0-9.]+) LUFS", out.stderr)
    return float(found[-1]) if found else None


# MARK: - Main


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--source", choices=["freesound", "commons"])
    parser.add_argument("--per-sound", type=int, default=2)
    parser.add_argument("--sound", action="append", help="only these sounds (folder names), repeatable")
    parser.add_argument("--out", type=Path, default=ROOT / "Atmosphere")
    parser.add_argument("--downloads", type=Path, default=ROOT / "AtmosphereDownloads")
    parser.add_argument("--dry-run", action="store_true", help="list what would be fetched")
    args = parser.parse_args()

    for tool in ("ffmpeg", "ffprobe"):
        if not shutil.which(tool):
            sys.exit(f"{tool} is needed (brew install ffmpeg)")
    key_file = ROOT / ".freesound-key"
    source_name = args.source or ("freesound" if key_file.is_file() else "commons")
    if source_name == "freesound":
        if not key_file.is_file():
            sys.exit("no Freesound key at ~/Storyteller Lofi/.freesound-key (get one at https://freesound.org/apiv2/apply)")
        source = Freesound(key_file.read_text().strip())
    else:
        source = Commons()
    note(f"source: {source.name}")

    wanted = {name: QUERIES[name] for name in QUERIES if not args.sound or name.lower() in {s.lower() for s in args.sound}}
    args.out.mkdir(parents=True, exist_ok=True)
    args.downloads.mkdir(parents=True, exist_ok=True)
    manifest_path = args.out / "sounds.json"
    manifest = json.loads(manifest_path.read_text()) if manifest_path.is_file() else {"version": 1, "sounds": []}
    have = {entry["id"] for entry in manifest["sounds"]}
    skipped = []

    for folder, queries in wanted.items():
        sound = folder[0].lower() + folder[1:]
        existing = [e for e in manifest["sounds"] if e["sound"] == sound]
        need = args.per_sound - len(existing)
        if need <= 0:
            note(f"{folder}: already has {len(existing)}")
            continue
        seen, candidates = set(), []
        for query in queries:
            try:
                for c in source.search(query):
                    if c["key"] in seen or not c["audio"]:
                        continue
                    seen.add(c["key"])
                    text = f"{c['title']} {c['tags']}"
                    if folder not in SPEECH_OK and AVOID.search(text):
                        skipped.append((folder, c, "title or tags suggest music, speech or sudden events"))
                        continue
                    if licence_kind(c["licence_text"]) is None:
                        skipped.append((folder, c, f"licence {c['licence_text'].strip() or 'unknown'}"))
                        continue
                    candidates.append(c)
            except Exception as error:  # noqa: BLE001
                note(f"{folder}: search '{query}' failed: {error}")
        candidates.sort(key=lambda c: -c["score"])
        taken = 0
        for c in candidates:
            if taken >= need:
                break
            rid = f"{sound}/{c['key']}"
            if rid in have:
                continue
            if args.dry_run:
                note(f"{folder}: would fetch {c['title']} by {c['author']} ({c['licence_text'].strip()}) {c['page']}")
                taken += 1
                continue
            kind = source.confirm(c)
            if kind is None:
                skipped.append((folder, c, f"licence on its own record: {c['licence_text']}"))
                continue
            raw = args.downloads / f"{c['key']}{Path(urllib.parse.urlparse(c['audio']).path).suffix or '.audio'}"
            try:
                if not raw.is_file():
                    download(c["audio"], raw)
                    time.sleep(1)
                duration = probe_duration(raw)
                if duration < 30:
                    skipped.append((folder, c, f"only {duration:.0f} s long"))
                    continue
                length = min(LOOP_SECONDS, duration - CROSSFADE - 0.5)
                start = steadiest_start(raw, duration, length)
                file = f"{folder}/{sound}-{c['key']}.m4a"
                target = args.out / file
                target.parent.mkdir(parents=True, exist_ok=True)
                make_loop(raw, target, start, length)
                level = loudness(target)
            except Exception as error:  # noqa: BLE001
                skipped.append((folder, c, f"could not process: {error}"))
                continue
            manifest["sounds"].append({
                "id": rid,
                "file": file,
                "sound": sound,
                "loudness": round(level, 1) if level is not None else None,
                "duration": round(length, 2),
                "title": c["title"],
                "author": c["author"],
                "source": c["page"],
                "license": ALLOWED[kind] + (f" ({c['licence_text'].strip()})" if kind != "cc0" else ""),
            })
            have.add(rid)
            taken += 1
            note(f"{folder}: {c['title']} by {c['author']}, {ALLOWED[kind]}, {level} LUFS")
        if taken < need:
            note(f"{folder}: found {taken} of {need}; the app uses its stand-in for the rest")

    if args.dry_run:
        return
    manifest["sounds"].sort(key=lambda e: e["file"])
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    with open(args.out / "SOURCES.csv", "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["file", "sound", "title", "author", "license", "source", "loudness_lufs"])
        for e in manifest["sounds"]:
            writer.writerow([e["file"], e["sound"], e["title"], e["author"], e["license"], e["source"], e["loudness"]])
    lines = ["# Atmosphere sound credits", "",
             "Recordings used under Creative Commons licences. CC BY and CC BY-SA recordings are",
             "credited as their licences ask; CC0 ones are listed with thanks.", ""]
    for e in manifest["sounds"]:
        lines.append(f"- {e['title']} by {e['author']}, {e['license']}: {e['source']}")
    (args.out / "CREDITS.md").write_text("\n".join(lines) + "\n")
    with open(args.out / "skipped.csv", "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["sound", "title", "author", "source", "why"])
        for folder, c, why in skipped:
            writer.writerow([folder, c["title"], c["author"], c["page"], why])
    counts = {}
    for e in manifest["sounds"]:
        counts[e["sound"]] = counts.get(e["sound"], 0) + 1
    note(f"{len(manifest['sounds'])} recordings for {len(counts)} of {len(QUERIES)} sounds in {args.out}")
    note("Copy this Atmosphere folder into the music folder, then import the music folder in the app.")


if __name__ == "__main__":
    main()
