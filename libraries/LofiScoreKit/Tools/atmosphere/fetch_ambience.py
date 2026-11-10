#!/usr/bin/env python3
"""Fetch recordings for the atmosphere sounds, with their credits.

Runs on Mo's Mac (it needs the network, python3 and ffmpeg). For every sound
it searches for steady recordings whose title (or Freesound tags) names the
sound, reads each recording's licence from its own record (never assumed), cuts
a seamless loop from the steadiest part, measures its loudness, and writes:

    ~/Storyteller Lofi/Atmosphere/
        Rain/rain-fs123456.m4a ...        one folder per sound
        OldTown.ChurchBells/...           one per more specific sound (variant)
        sounds.json                       loudness, duration, title, author, source, licence, use
        variants.json                     the more specific sounds and the books that asked for them
        OneShots/DoorKnock/...            one-off sounds (a knock, a clap of thunder),
        OneShots/sounds.json              played once on their sentence when the app's setting is on
        SOURCES.csv  CREDITS.md  skipped.csv

Copy that Atmosphere folder into the music folder (next to Calm/, Cozy/, ...)
before importing the music folder in the app. Sounds with no recording keep
the app's synthesised stand-ins; a variant with none plays its plain sound.

What it fetches:
  - the 26 built-in sounds (Rain, Fireplace, Crowd, ...), --per-sound each;
  - the more specific sounds (variants), --per-variant each: a starter set
    (STARTER_VARIANTS below) plus every variant a book's atmosphere track
    asked for (~/Storyteller Lofi/tracks/*.atmosphere.json and *.score.json);
  - the 15 one-off sounds (ONE_SHOTS below), --per-one-shot each: short single
    sounds, trimmed of silence, not looped.
Runs add what is missing, so run it again after scoring new books. One run at a
time writes a folder; a second one waits for it.

Two editions:
  personal (default)  For Mo's own app. Searches Freesound (needs
                      ~/Storyteller Lofi/.freesound-key) and keeps the best
                      steady recordings under CC0, CC BY or CC BY-NC. Every
                      Freesound recording is marked "use": "personal": the
                      Freesound API is free for non-commercial use only, and
                      CC BY-NC allows nothing else. Wikimedia Commons fills in
                      when Freesound has too few. Writes ~/Storyteller Lofi/Atmosphere.
  publish             For an App Store build. Wikimedia Commons only, CC0,
                      CC BY and CC BY-SA only, nothing personal. Writes
                      ~/Storyteller Lofi/AtmospherePublish.
A published app build also refuses any recording marked personal
(LOFI_SOUND_EDITION=publish in the app's build), whatever folder it is given.

    python3 -I fetch_ambience.py [--edition personal|publish] [--per-sound 4]
                                 [--per-variant 2] [--per-one-shot 2] [--sound Rain]
                                 [--no-variants] [--no-one-shots] [--out DIR] [--dry-run]

Audio is never committed: the fork is public. Run with python3 -I and keep the
downloads folder away from this script.
"""

import argparse
import csv
import fcntl
import json
import re
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path.home() / "Storyteller Lofi"
USER_AGENT = "StorytellerLofi-atmosphere/2.0 (personal app; python urllib)"

# What to search for, per built-in sound (folder name as the app expects it).
# Steady beds only: the narrator must stay easy to follow, so nothing with words,
# music or sudden one-off events.
QUERIES = {
    "Rain": ["light rain ambience", "gentle rain", "steady rain"],
    "HeavyRain": ["heavy rain downpour", "heavy rain ambience", "torrential rain"],
    "RainIndoors": ["rain on window", "rain on roof interior", "rain inside house"],
    "Thunder": ["distant thunderstorm rain", "thunder rumble rain ambience"],
    "Wind": ["gentle wind ambience", "soft wind", "wind field"],
    "StrongWind": ["strong wind howling", "storm wind gusts", "gale wind"],
    "Snow": ["winter wind snow ambience", "snowy quiet winter ambience", "snow forest winter"],
    "Fireplace": ["fireplace crackling", "fireplace fire crackle", "wood stove crackle"],
    "Campfire": ["campfire crackling outdoors", "campfire night"],
    "SeaShore": ["waves beach ambience", "ocean waves shore", "waves rocks"],
    "OpenSea": ["open sea waves boat", "ocean swell", "boat hull water"],
    "River": ["river stream ambience", "babbling brook", "creek water flowing"],
    "Dripping": ["cave dripping water", "water drips cave ambience"],
    "Forest": ["forest ambience day", "woodland ambience birds wind"],
    "Birdsong": ["birdsong morning", "dawn chorus birds", "garden birds"],
    "NightInsects": ["crickets night", "night insects ambience"],
    "NightForest": ["night forest ambience", "forest at night owl"],
    "Swamp": ["swamp frogs night", "marsh frogs ambience"],
    "Crowd": ["crowd murmur indoor", "walla crowd indistinct", "school hallway ambience"],
    "City": ["city street ambience", "city traffic distant ambience"],
    "OldTown": ["medieval town ambience", "market square ambience horses", "village square ambience"],
    "Horses": ["horse carriage hooves cobblestones", "horse drawn carriage"],
    "Train": ["train interior ambience", "steam train journey"],
    "Ship": ["ship creaking wood", "sailing ship ambience"],
    "Machinery": ["factory machinery ambience", "engine room ambience"],
    "Clock": ["clock ticking", "grandfather clock ticking"],
}

# More specific kinds of the built-in sounds, fetched up front so Claude can use
# them in any book (it can also ask for new ones while scoring). Each plays its
# `of` sound until a recording is imported. id: camelCase, never a built-in name.
STARTER_VARIANTS = [
    ("drizzle", "rain", "a light drizzle, barely there", "light drizzle rain"),
    ("rainOnLeaves", "rain", "rain falling through a forest canopy", "rain forest leaves"),
    ("tentRain", "rainIndoors", "rain drumming on a tent", "rain on tent"),
    ("blizzard", "strongWind", "a blizzard of driving snow and wind", "blizzard wind snow"),
    ("desertWind", "wind", "wind blowing over sand in a desert", "desert wind"),
    ("mountainWind", "wind", "wind on a high mountain ridge", "mountain wind"),
    ("windChimes", "wind", "a breeze with wind chimes on a porch", "wind chimes breeze"),
    ("bonfire", "campfire", "a big roaring bonfire", "bonfire roaring"),
    ("waterfall", "river", "a waterfall close by", "waterfall"),
    ("fountain", "river", "a fountain splashing in a courtyard", "fountain courtyard"),
    ("lakeShore", "seaShore", "small waves lapping a lake shore", "lake shore lapping water"),
    ("harbour", "seaShore", "a harbour: water against the quay, gulls, rigging", "harbour ambience gulls"),
    ("underwater", "openSea", "under water, muffled and deep", "underwater ambience"),
    ("rowingBoat", "openSea", "a small rowing boat on calm water", "rowing boat oars water"),
    ("shipStorm", "ship", "a ship in a storm: groaning timbers, heavy seas", "ship storm creaking waves"),
    ("jungle", "forest", "a tropical jungle: insects, birds, humid air", "jungle ambience"),
    ("summerMeadow", "birdsong", "a summer meadow: bees, grasshoppers, birds", "summer meadow insects"),
    ("cafe", "crowd", "a cafe: low chatter, cups and saucers", "cafe ambience"),
    ("tavern", "crowd", "a busy tavern or pub: murmur, mugs, laughter", "tavern pub ambience"),
    ("marketplace", "crowd", "an open-air market: stalls, chatter, footsteps", "market ambience"),
    ("schoolCorridor", "crowd", "a busy school corridor between lessons", "school hallway ambience"),
    ("feastHall", "crowd", "a great hall at a feast: many voices, cutlery", "banquet hall crowd"),
    ("trainStation", "crowd", "a railway station concourse", "train station ambience"),
    ("churchBells", "oldTown", "church bells ringing across a town", "church bells distant"),
    ("cityNight", "city", "a city at night: distant traffic, quiet streets", "city night ambience"),
    ("library", "clock", "a hushed library: pages turning, soft footsteps", "library ambience quiet"),
    ("office", "machinery", "a quiet office: air conditioning, distant keyboards", "office ambience"),
    ("carInterior", "machinery", "inside a moving car", "car interior driving"),
    ("airplaneCabin", "machinery", "inside an airliner in flight", "airplane cabin ambience"),
    ("spaceship", "machinery", "the hum inside a spaceship", "spaceship interior hum"),
    ("subway", "train", "inside an underground train", "subway train interior"),
    ("steamTrain", "train", "a steam train on the move", "steam train"),
]

BUILTINS = [name[0].lower() + name[1:] for name in QUERIES]

# One-off sounds (the app's OneShotSound), folder name: (queries, longest kept in seconds).
# Played once, on the sentence that says they happen, when the listener turns them on.
ONE_SHOTS = {
    "ThunderClap": (["thunder clap", "thunder crack", "single thunder strike"], 8),
    "DoorKnock": (["knocking on door", "door knock"], 4),
    "DoorSlam": (["door slam", "door slamming shut"], 3),
    "DoorCreak": (["door creak", "creaky door opening"], 4),
    "Doorbell": (["doorbell ding dong", "doorbell"], 4),
    "PhoneRing": (["old telephone ring", "telephone ringing bell"], 6),
    "BellToll": (["church bell toll single", "bell toll"], 8),
    "ClockChime": (["clock chime hour", "grandfather clock chime"], 12),
    "GlassBreak": (["glass break", "glass shatter"], 3),
    "DogBark": (["dog bark", "dog barking"], 4),
    "OwlHoot": (["owl hoot", "tawny owl call"], 4),
    "WolfHowl": (["wolf howl"], 7),
    "HorseNeigh": (["horse neigh", "horse whinny"], 4),
    "TrainWhistle": (["steam train whistle", "train whistle"], 6),
    "ShipHorn": (["ship horn", "foghorn"], 7),
}
ONE_SHOT_FOLDER = "OneShots"

# Words in a title or tags that mean the recording would fight the narrator.
AVOID = re.compile(
    r"\b(music|song|melody|singing|voice ?over|speech|talking|dialogue|narrat|announcement|"
    r"radio|tv|television|scream|explosion|gunshot|siren|alarm|horror|scary|"
    r"synth|drone music|meditation music|asmr)\b",
    re.I,
)
SPEECH_OK = {"crowd"}
# For one-off sounds: no words or music, and single events rather than long beds.
ONE_SHOT_AVOID = re.compile(
    r"\b(music|song|melody|singing|voice ?over|speech|talking|dialogue|narrat|announcement|"
    r"radio|tv|television|scream|synth|ambience|ambient|soundscape|loop|compilation|collection)\b",
    re.I,
)

# Words too general to show that a recording is of the sound being searched for.
GENERIC = {
    "a", "an", "and", "at", "by", "in", "of", "on", "the", "with",
    "ambience", "ambiance", "ambient", "atmosphere", "sound", "sounds", "sfx", "effect", "recording",
    "field", "loop", "room", "call", "single", "light", "gentle", "steady", "soft", "strong", "heavy",
    "distant", "quiet", "indistinct", "interior", "inside", "indoor", "indoors", "outdoors", "open",
    "old", "day", "night", "morning", "drawn", "journey", "busy", "small", "big",
}


def stem(word):
    """Enough of a word to match its other forms: "crackling" and "crackle", "bells" and "bell"."""
    word = word.lower()
    if len(word) > 5:
        return word[:5]
    return word[:-1] if len(word) > 3 and word.endswith("s") else word


def keywords(folder, queries):
    """Stems of the words that name a target: its own name (a variant's own part only) and its queries."""
    own = re.split(r"[./]", folder)[-1]
    words = re.findall(r"[A-Z]?[a-z]+", own) + [w for q in queries for w in re.findall(r"[a-z]+", q.lower())]
    return {stem(w) for w in words if w.lower() not in GENERIC}


def names_the_sound(candidate, keys):
    """Whether the recording's own name (and Freesound's tags) says it is the sound searched for.

    Search engines also match long descriptions, so a pier's creaks recorded on a rainy day
    turns up under rain. The title has to name it."""
    if not keys:
        return True
    return any(w.startswith(k) for w in re.findall(r"[a-z]+", candidate["match"].lower()) for k in keys)


LABELS = {
    "cc0": "CC0 1.0",
    "by": "CC BY",
    "by-sa": "CC BY-SA",
    "by-nc": "CC BY-NC",
    "by-nc-sa": "CC BY-NC-SA",
}
COMMERCIAL = {"cc0", "by", "by-sa"}
VIA_FREESOUND = "found through Freesound's API, which is free for non-commercial use only"

LOOP_SECONDS = 60
CROSSFADE = 3.0
BITRATE = 128000


def note(text):
    print(text, file=sys.stderr, flush=True)


# Statuses that mean "slow down" or "busy, try again": waited out instead of giving up.
RETRY_STATUSES = {429, 502, 503, 504}
RETRIES = 6


def retry_after(error):
    """The server's Retry-After in seconds, if it sent a number (capped at 5 minutes)."""
    value = (error.headers or {}).get("Retry-After", "")
    return min(300.0, float(value)) if value.strip().isdigit() else None


def open_url(url, timeout):
    """urlopen that waits out rate limits: Wikimedia answers 429 when asked too often."""
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    for attempt in range(RETRIES):
        try:
            return urllib.request.urlopen(request, timeout=timeout)
        except urllib.error.HTTPError as error:
            if error.code not in RETRY_STATUSES or attempt == RETRIES - 1:
                raise
            wait = retry_after(error) or min(120.0, 5.0 * 2 ** attempt)
            note(f"  {urllib.parse.urlparse(url).netloc} answered {error.code}; waiting {wait:.0f} s")
            time.sleep(wait)


def fetch_json(url, params=None):
    if params:
        url = url + "?" + urllib.parse.urlencode(params)
    with open_url(url, timeout=60) as response:
        return json.load(response)


def download(url, path):
    """Downloads through a .part file, so a stopped download is never taken for a whole one."""
    part = path.with_name(path.name + ".part")
    with open_url(url, timeout=300) as response, open(part, "wb") as out:
        shutil.copyfileobj(response, out)
    part.replace(path)


def licence_kind(text):
    """'cc0', 'by', 'by-sa', 'by-nc' or 'by-nc-sa', else None (no-derivatives, Sampling+, unknown)."""
    t = (text or "").lower()
    words = set(re.split(r"[^a-z+]+", t))
    if "publicdomain/zero" in t or re.search(r"\bcc0\b|creative commons 0", t):
        return "cc0"
    if "/nd" in t or "-nd" in t or "noderiv" in t or "nd" in words or "sampling+" in t:
        return None
    noncommercial = "nc" in words or "noncommercial" in t or "non-commercial" in t
    sharealike = "licenses/by-sa" in t or "-sa/" in t or "sa" in words or "sharealike" in t
    attribution = "licenses/by" in t or re.search(r"^cc by\b|\bcc by[- ]|^cc-by\b|^attribution\b|attribution \d", t)
    if not attribution:
        return None
    if noncommercial:
        return "by-nc-sa" if sharealike else "by-nc"
    return "by-sa" if sharealike else "by"


def normalized_id(text):
    """The app's variant id rules (SoundVariant.normalizedID): camelCase letters and
    digits, at most 32, starting with a letter, never a built-in sound's name."""
    words = [w for w in re.split(r"[^0-9A-Za-z]+", text or "") if w]
    if not words:
        return None
    vid = words[0][0].lower() + words[0][1:] + "".join(w[0].upper() + w[1:] for w in words[1:])
    if len(vid) > 32 or not vid[0].isalpha() or not vid.isascii() or not vid.isalnum():
        return None
    letters = re.sub(r"[^a-z]", "", vid.lower())
    if any(letters == b.lower() for b in BUILTINS):
        return None
    return vid


def folder_name(sound, variant=None):
    base = sound[0].upper() + sound[1:]
    return base if not variant else f"{base}.{variant[0].upper()}{variant[1:]}"


# MARK: - Sources


class Freesound:
    name = "freesound"

    def __init__(self, key, personal):
        self.key = key
        self.personal = personal

    def search(self, query, one_shot=False):
        licences = '"Creative Commons 0" OR "Attribution"' + (' OR "Attribution NonCommercial"' if self.personal else "")
        durations = "[0.3 TO 20]" if one_shot else "[45 TO 1200]"
        data = fetch_json(
            "https://freesound.org/apiv2/search/text/",
            {
                "query": query,
                "filter": f"duration:{durations} license:({licences})",
                "sort": "rating_desc",
                "page_size": 30,
                "fields": "id,name,username,license,duration,url,previews,avg_rating,num_ratings,num_downloads,tags",
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
                "match": f"{item.get('name', '')} {' '.join(item.get('tags') or [])}",
                "score": (item.get("avg_rating") or 0) * min(1, (item.get("num_ratings") or 0) / 5)
                + min(2, (item.get("num_downloads") or 0) / 2000),
                "audio": (item.get("previews") or {}).get("preview-hq-ogg")
                or (item.get("previews") or {}).get("preview-hq-mp3"),
                "via": self.name,
            }

    def confirm(self, candidate):
        """Re-reads the sound's own record and returns its licence kind."""
        sound_id = candidate["key"][2:]
        data = fetch_json(f"https://freesound.org/apiv2/sounds/{sound_id}/", {"fields": "license,username,name", "token": self.key})
        time.sleep(1)
        candidate["licence_text"] = data.get("license", candidate["licence_text"])
        return licence_kind(candidate["licence_text"])


COMMONS_PAUSE = 3.0


class Commons:
    name = "commons"

    def search(self, query, one_shot=False):
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
        # Wikimedia rate-limits clients that search quickly; open_url waits out any 429.
        time.sleep(COMMONS_PAUSE)
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
                # Commons descriptions are long and mention anything nearby: judge by the title.
                "match": re.sub(r"\.[a-z0-9]+$", "", page.get("title", "").removeprefix("File:"), flags=re.I),
                "score": 0.0,
                "audio": info.get("url"),
                "via": self.name,
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
            subprocess.run(["afconvert", "-f", "m4af", "-d", "aac", "-b", str(BITRATE), str(wav), str(target)], check=True)
        else:
            subprocess.run(
                ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", str(wav), "-c:a", "aac", "-b:a", f"{BITRATE // 1000}k", str(target)],
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


def make_one_shot(source, target, longest):
    """A one-off sound: silence trimmed from both ends, at most `longest` seconds,
    faded out at its end so it never stops on a click."""
    graph = (
        "aformat=sample_rates=44100:channel_layouts=stereo,"
        "silenceremove=start_periods=1:start_threshold=-45dB,"
        f"atrim=0:{longest},asetpts=PTS-STARTPTS,"
        "areverse,silenceremove=start_periods=1:start_threshold=-55dB,afade=t=in:d=0.25,areverse"
    )
    wav = target.with_suffix(".once.wav")
    subprocess.run(
        ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", str(source), "-af", graph, "-c:a", "pcm_s16le", str(wav)],
        check=True,
    )
    try:
        if probe_duration(wav) < 0.2:
            raise ValueError("nothing left after trimming silence")
        if shutil.which("afconvert"):
            subprocess.run(["afconvert", "-f", "m4af", "-d", "aac", "-b", str(BITRATE), str(wav), str(target)], check=True)
        else:
            subprocess.run(
                ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", str(wav), "-c:a", "aac", "-b:a", f"{BITRATE // 1000}k", str(target)],
                check=True,
            )
    finally:
        wav.unlink(missing_ok=True)


# MARK: - Variants


def track_variants(tracks_dir):
    """(variant, book) pairs from every atmosphere track and book score in the folder."""
    found = []
    for path in sorted(tracks_dir.glob("*.json")) if tracks_dir.is_dir() else []:
        if not (path.name.endswith(".atmosphere.json") or path.name.endswith(".score.json")):
            continue
        try:
            data = json.loads(path.read_text())
        except (OSError, ValueError):
            continue
        track = data.get("atmosphere") if path.name.endswith(".score.json") else data
        if not isinstance(track, dict):
            continue
        for v in track.get("variants") or []:
            found.append((v, track.get("bookID") or path.name))
    return found


def merge_catalog(catalog, starter, from_tracks):
    """The variants catalog with the starter set and the tracks' variants added."""
    by_id = {}
    for entry in catalog.get("variants", []):
        vid = normalized_id(entry.get("id", ""))
        if vid and entry.get("of") in BUILTINS:
            entry["id"] = vid
            entry["books"] = sorted(set(entry.get("books") or []))
            by_id[vid] = entry
    for vid, of, about, search in starter:
        # Offered to every book, even one that asked for it too.
        by_id.setdefault(vid, {"id": vid, "of": of, "about": about, "search": search, "books": []})["starter"] = True
    for v, book in from_tracks:
        vid = normalized_id(v.get("id", ""))
        of = v.get("of")
        if not vid or of not in BUILTINS:
            continue
        entry = by_id.setdefault(vid, {
            "id": vid, "of": of,
            "about": str(v.get("about") or "")[:120],
            "search": str(v.get("search") or v.get("about") or vid)[:80],
            "books": [],
        })
        if book not in entry["books"]:
            entry["books"] = sorted(entry["books"] + [book])
    return {"version": 1, "variants": sorted(by_id.values(), key=lambda e: (e["of"], e["id"]))}


# MARK: - Main


def personal_reason(kind, via):
    if kind not in COMMERCIAL:
        return f"{LABELS[kind]} licence: non-commercial use only"
    if via == Freesound.name:
        return VIA_FREESOUND
    return None


def mark_freesound_personal(manifest):
    """Recordings from earlier runs that came through Freesound's API are personal use."""
    for entry in manifest["sounds"]:
        if entry.get("use") is None and "/fs" in entry.get("id", ""):
            entry["use"] = "personal"
            entry["personalReason"] = VIA_FREESOUND


def write_companions(out, manifest, skipped, edition, one_shots=None):
    manifest["sounds"].sort(key=lambda e: e["file"])
    (out / "sounds.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    if one_shots is not None:
        one_shots["sounds"].sort(key=lambda e: e["file"])
        (out / ONE_SHOT_FOLDER).mkdir(parents=True, exist_ok=True)
        (out / ONE_SHOT_FOLDER / "sounds.json").write_text(json.dumps(one_shots, indent=2, sort_keys=True) + "\n")
    # Every recording, one-off sounds with their folder, for the credits.
    everything = manifest["sounds"] + [
        dict(e, file=f"{ONE_SHOT_FOLDER}/{e['file']}") for e in (one_shots or {"sounds": []})["sounds"]
    ]
    with open(out / "SOURCES.csv", "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["file", "sound", "variant", "title", "author", "license", "use", "source", "loudness_lufs"])
        for e in everything:
            writer.writerow([e["file"], e["sound"], e.get("variant") or "", e["title"], e["author"], e["license"],
                             e.get("use") or "any", e["source"], e["loudness"]])
    lines = ["# Atmosphere sound credits", "",
             "Recordings used under Creative Commons licences, credited as their licences ask;",
             "CC0 ones are listed with thanks."]
    if edition == "personal":
        lines += ["", "Recordings marked (personal use) are for this personal app only: they are under a",
                  "non-commercial licence or came through Freesound's API, and a published build leaves them out."]
    lines.append("")
    for e in everything:
        mark = " (personal use)" if e.get("use") == "personal" else ""
        lines.append(f"- {e['title']} by {e['author']}, {e['license']}{mark}: {e['source']}")
    (out / "CREDITS.md").write_text("\n".join(lines) + "\n")
    with open(out / "skipped.csv", "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["sound", "title", "author", "source", "why"])
        for folder, c, why in skipped:
            writer.writerow([folder, c["title"], c["author"], c["page"], why])


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--edition", choices=["personal", "publish"], default="personal")
    parser.add_argument("--per-sound", type=int, default=4, help="recordings per built-in sound")
    parser.add_argument("--per-variant", type=int, default=2, help="recordings per more specific sound")
    parser.add_argument("--per-one-shot", type=int, default=2, help="recordings per one-off sound")
    parser.add_argument("--sound", action="append", help="only these sounds (folder names, e.g. Rain or OldTown.ChurchBells), repeatable")
    parser.add_argument("--no-variants", action="store_true", help="no more specific sounds")
    parser.add_argument("--no-one-shots", action="store_true", help="no one-off sounds")
    parser.add_argument("--tracks", type=Path, default=ROOT / "tracks", help="where the atmosphere tracks are")
    parser.add_argument("--out", type=Path)
    parser.add_argument("--downloads", type=Path, default=ROOT / "AtmosphereDownloads")
    parser.add_argument("--dry-run", action="store_true", help="list what would be fetched")
    args = parser.parse_args()

    for tool in ("ffmpeg", "ffprobe"):
        if not shutil.which(tool):
            sys.exit(f"{tool} is needed (brew install ffmpeg)")
    personal = args.edition == "personal"
    out = args.out or ROOT / ("Atmosphere" if personal else "AtmospherePublish")
    key_file = ROOT / ".freesound-key"
    sources = []
    if personal:
        if key_file.is_file():
            sources.append(Freesound(key_file.read_text().strip(), personal=True))
        else:
            note("no Freesound key at ~/Storyteller Lofi/.freesound-key: Wikimedia Commons only")
    sources.append(Commons())
    note(f"{args.edition} edition, sources: {', '.join(s.name for s in sources)}, writing {out}")

    out.mkdir(parents=True, exist_ok=True)
    args.downloads.mkdir(parents=True, exist_ok=True)
    # One run at a time per folder: two writing the same sounds.json would lose recordings.
    # The lock lives with the downloads, so it never gets copied into the music folder.
    lock = open(args.downloads / f".{out.name}.lock", "w")
    if not args.dry_run:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            note(f"another fetch is writing {out}; waiting for it to finish")
            fcntl.flock(lock, fcntl.LOCK_EX)
    manifest_path = out / "sounds.json"
    manifest = json.loads(manifest_path.read_text()) if manifest_path.is_file() else {"version": 1, "sounds": []}
    mark_freesound_personal(manifest)
    one_shot_path = out / ONE_SHOT_FOLDER / "sounds.json"
    one_shots = json.loads(one_shot_path.read_text()) if one_shot_path.is_file() else {"version": 1, "sounds": []}
    catalog_path = out / "variants.json"
    catalog = json.loads(catalog_path.read_text()) if catalog_path.is_file() else {"version": 1, "variants": []}
    catalog = merge_catalog(catalog, STARTER_VARIANTS, track_variants(args.tracks))
    if not args.dry_run:
        catalog_path.write_text(json.dumps(catalog, indent=2, sort_keys=True) + "\n")

    # What to fetch: (folder, sound, variant, queries, how many, longest one-off in seconds or None).
    targets = [(folder, folder[0].lower() + folder[1:], None, queries, args.per_sound, None) for folder, queries in QUERIES.items()]
    if not args.no_variants:
        for v in catalog["variants"]:
            queries = list(dict.fromkeys([v["search"], f"{v['search']} ambience"]))
            targets.append((folder_name(v["of"], v["id"]), v["of"], v["id"], queries, args.per_variant, None))
    if not args.no_one_shots:
        for folder, (queries, longest) in ONE_SHOTS.items():
            targets.append((f"{ONE_SHOT_FOLDER}/{folder}", folder[0].lower() + folder[1:], None, queries, args.per_one_shot, longest))
    if args.sound:
        wanted = {s.lower() for s in args.sound}
        targets = [t for t in targets if t[0].lower() in wanted or t[0].lower().removeprefix(ONE_SHOT_FOLDER.lower() + "/") in wanted]

    have = {entry["id"] for entry in manifest["sounds"]} | {f"once.{entry['id']}" for entry in one_shots["sounds"]}
    skipped = []
    fetched = 0
    for folder, sound, variant, queries, count, longest in targets:
        one_shot = longest is not None
        listing = one_shots["sounds"] if one_shot else manifest["sounds"]
        existing = [e for e in listing if e["sound"] == sound and e.get("variant") == variant]
        need = count - len(existing)
        if need <= 0:
            note(f"{folder}: already has {len(existing)}")
            continue
        keys = keywords(folder, queries)
        taken = 0
        for source in sources:
            if taken >= need:
                break
            seen, candidates = set(), []
            for query in queries:
                try:
                    for c in source.search(query, one_shot=one_shot):
                        if c["key"] in seen or not c["audio"]:
                            continue
                        seen.add(c["key"])
                        text = f"{c['title']} {c['tags']}"
                        if one_shot and ONE_SHOT_AVOID.search(text):
                            skipped.append((folder, c, "title or tags suggest music, speech or a long recording"))
                            continue
                        if not one_shot and sound not in SPEECH_OK and AVOID.search(text):
                            skipped.append((folder, c, "title or tags suggest music, speech or sudden events"))
                            continue
                        if not names_the_sound(c, keys):
                            skipped.append((folder, c, "its title does not name the sound"))
                            continue
                        kind = licence_kind(c["licence_text"])
                        if kind is None or (not personal and kind not in COMMERCIAL):
                            skipped.append((folder, c, f"licence {c['licence_text'].strip() or 'unknown'}"))
                            continue
                        candidates.append(c)
                except Exception as error:  # noqa: BLE001
                    note(f"{folder}: {source.name} search '{query}' failed: {error}")
            # The best fit first, whatever its licence: in the personal edition a
            # non-commercial recording that fits better wins.
            # A one-off sound close to the length it is kept at needs the least cutting.
            if one_shot:
                for c in candidates:
                    if c["duration"] and c["duration"] > longest * 2:
                        c["score"] -= 1
            candidates.sort(key=lambda c: -c["score"])
            for c in candidates:
                if taken >= need:
                    break
                rid = f"{sound}{'.' + variant if variant else ''}/{c['key']}"
                if (f"once.{rid}" if one_shot else rid) in have:
                    continue
                if args.dry_run:
                    note(f"{folder}: would fetch {c['title']} by {c['author']} ({c['licence_text'].strip()}) {c['page']}")
                    taken += 1
                    continue
                kind = source.confirm(c)
                if kind is None or (not personal and kind not in COMMERCIAL):
                    skipped.append((folder, c, f"licence on its own record: {c['licence_text']}"))
                    continue
                raw = args.downloads / f"{c['key']}{Path(urllib.parse.urlparse(c['audio']).path).suffix or '.audio'}"
                try:
                    if not raw.is_file():
                        download(c["audio"], raw)
                        time.sleep(1)
                    duration = probe_duration(raw)
                    if one_shot:
                        if duration < 0.3 or duration > 60:
                            skipped.append((folder, c, f"{duration:.1f} s long"))
                            continue
                        file = f"{folder.removeprefix(ONE_SHOT_FOLDER + '/')}/{sound}-{c['key']}.m4a"
                        target = out / ONE_SHOT_FOLDER / file
                        target.parent.mkdir(parents=True, exist_ok=True)
                        make_one_shot(raw, target, longest)
                        length = probe_duration(target)
                    else:
                        if duration < 30:
                            skipped.append((folder, c, f"only {duration:.0f} s long"))
                            continue
                        length = min(LOOP_SECONDS, duration - CROSSFADE - 0.5)
                        start = steadiest_start(raw, duration, length)
                        file = f"{folder}/{variant or sound}-{c['key']}.m4a"
                        target = out / file
                        target.parent.mkdir(parents=True, exist_ok=True)
                        make_loop(raw, target, start, length)
                    level = loudness(target)
                except Exception as error:  # noqa: BLE001
                    skipped.append((folder, c, f"could not process: {error}"))
                    continue
                entry = {
                    "id": rid,
                    "file": file,
                    "sound": sound,
                    "loudness": round(level, 1) if level is not None else None,
                    "duration": round(length, 2),
                    "title": c["title"],
                    "author": c["author"],
                    "source": c["page"],
                    "license": LABELS[kind] + (f" ({c['licence_text'].strip()})" if kind != "cc0" else ""),
                }
                if variant:
                    entry["variant"] = variant
                reason = personal_reason(kind, source.name)
                if reason:
                    entry["use"] = "personal"
                    entry["personalReason"] = reason
                listing.append(entry)
                have.add(f"once.{rid}" if one_shot else rid)
                taken += 1
                fetched += 1
                note(f"{folder}: {c['title']} by {c['author']}, {LABELS[kind]}{' (personal use)' if reason else ''}, {level} LUFS")
            # Save as we go, so a stopped run keeps what it fetched.
            if not args.dry_run and taken:
                write_companions(out, manifest, skipped, args.edition, one_shots)
        if taken < need:
            fallback = "its stand-in, or nothing" if one_shot else ("its plain sound" if variant else "its stand-in")
            note(f"{folder}: found {taken} of {need}; the app uses {fallback} for the rest")

    if args.dry_run:
        return
    write_companions(out, manifest, skipped, args.edition, one_shots)
    plain = {e["sound"] for e in manifest["sounds"] if not e.get("variant")}
    variants = {(e["sound"], e["variant"]) for e in manifest["sounds"] if e.get("variant")}
    singles = {e["sound"] for e in one_shots["sounds"]}
    personal_count = sum(1 for e in manifest["sounds"] + one_shots["sounds"] if e.get("use") == "personal")
    note(f"{fetched} new; {len(manifest['sounds']) + len(one_shots['sounds'])} recordings ({personal_count} personal use) for "
         f"{len(plain)} of {len(QUERIES)} sounds, {len(variants)} of {len(catalog['variants'])} specific sounds "
         f"and {len(singles)} of {len(ONE_SHOTS)} one-off sounds in {out}")
    listed = {e["file"] for e in manifest["sounds"]} | {f"{ONE_SHOT_FOLDER}/{e['file']}" for e in one_shots["sounds"]}
    extra = sorted(
        str(f.relative_to(out)) for f in out.rglob("*")
        if f.is_file() and f.suffix.lower() in {".m4a", ".aac", ".mp3", ".wav", ".aif", ".aiff", ".caf", ".flac"}
        and str(f.relative_to(out)) not in listed
    )
    if extra:
        note(f"{len(extra)} audio file(s) in {out} are not in sounds.json (a stopped run, or added by hand); "
             f"the app plays them too, without credits. Move them out if they are not yours: {', '.join(extra[:10])}"
             + (" ..." if len(extra) > 10 else ""))
    note("Copy this Atmosphere folder into the music folder, then import the music folder in the app.")


if __name__ == "__main__":
    main()
