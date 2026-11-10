#!/usr/bin/env python3
"""How a book's ambience behaves over the whole book, from its atmosphere track.

A passage test says whether one answer is right. This says what a listener
gets when thousands of answers are played in order: how often the sound
changes, whether it flickers there and back, whether a place sounds the same
when the story returns to it, and how late a change can come.

    python3 -I Tools/eval/atmosphere_stats.py BOOK.atmosphere.json [more tracks ...]
        [--seconds-per-sentence 6.5] [--dwell 20] [--min-confidence 0.35] [--max-lag 80]
        [--resolution 3] [--names] [--skeleton OUT.json] [--settle N] [--settled-out FILE]

It reads only the track (a .atmosphere.json or a skeleton written by this
script), never the book, and prints numbers, sound ids and place ids like
"p12". Place names and state notes are the scorer's own words about the
book, so they are printed only with --names; the words quoted for one-off
sounds are never printed.

--skeleton writes the track with everything but its structure removed:
sentence numbers, place ids, sounds, levels, confidence, moments, transition
ids, the sentence number each answer says its scene began on, and one-off
sound ids. Each state note becomes a number ("s4"), and of the place names
only the pairs of ids whose names match are kept. So the numbers can be
studied on another machine without any of the book or of the scorer's words
about it.

"Changes of sound" and how closely they are pinned follow SceneChangeFinder
in LofiAtmosphere, which the track builder uses to decide where to score
next: a change is heard only at an entry sure enough to be played whose
place or sounds differ from what was playing; it is pinned when the entry
before it is within --resolution sentences (one sentence for a swell, a
hush, or a change that plays a door or an engine), or when the entry's own
answer says its scene begins on its own sentence.

"After the director" follows AtmosphereDirector: the newest entry at or
before the sentence whose confidence is at least --min-confidence and that
is at most --max-lag sentences back; a scene that sounds the same (same
place, same sounds, same levels) changes nothing; anything else changes the
sound, but not within --dwell seconds of the last change unless the entry
is a swell or hush on its own sentence. A change from one place without
sound to another is not counted: nobody hears it.

The last table tries settling: instead of following every entry, cut the
book into scenes, the cheapest way to give every entry a sound, where a
sentence costs nothing on the entry's own sound, up to 1 the more the sound
playing differs from it (other sounds, other levels, another place), and
every change of sound costs N sentences. A scene may only start on an entry
whose own sound it is, so nothing is ever heard before its own sentence;
looking ahead only decides which changes last long enough to follow. For
each N: changes an hour and holds after the director, and how the sound
played sits against what the track asked for, by narrated time: "exact"
(same place, sounds and levels), "same sounds" (levels may differ) and
"off" (the average difference, 0 to 1). --settle picks the N written by
--settled-out (one line per entry: sentence, the sound scored, the sound
played), to compare with the Swift.

Standard library only; works with the Python 3.9 that macOS ships.
"""
from __future__ import annotations

import argparse
import json
import sys

WEATHER = {"rain", "heavyRain", "rainIndoors", "thunder", "wind", "strongWind", "snow"}
SKIP_WORDS = {"the", "a", "an", "of", "in", "at", "on"}
LEVEL_WEIGHT = {"faint": 1.0, "soft": 2.0, "full": 3.0, "loud": 4.0}
PLACE_COST = 0.2  # another place with the very same sounds: other recordings, little else
TAIL_SENTENCES = 15  # how long the last entry is taken to last
VOICES = {"crowd", "murmur"}  # AmbientSound.isVoices


def name_words(name):
    """PlaceMemory.nameKey in Swift, as a set of words."""
    words, word = [], ""
    for ch in (name or "").lower():
        if ch.isalnum():
            word += ch
        elif word:
            words.append(word)
            word = ""
    if word:
        words.append(word)
    return frozenset(w for w in words if w not in SKIP_WORDS)


class Entry:
    __slots__ = ("g", "place", "layers", "keys", "conf", "moment", "transition", "state", "name", "words", "setting", "start")

    def __init__(self, raw):
        scene = raw.get("scene") or {}
        self.g = int(raw["globalIndex"])
        self.place = scene.get("placeID")
        layers = []
        for layer in scene.get("layers") or []:
            key = layer["sound"] + ("." + layer["variant"] if layer.get("variant") else "")
            layers.append((key, layer.get("level", "soft")))
        self.layers = tuple(sorted(layers))
        self.keys = frozenset(k for k, _ in layers)
        self.conf = float(scene.get("confidence", 1.0))
        self.moment = scene.get("moment")
        self.transition = scene.get("transition")
        self.setting = scene.get("setting", "unclear")
        # A skeleton holds a number for each state note; a full track holds the words.
        state = scene.get("stateID") or (scene.get("state") or "").strip().lower()
        self.state = state or None
        self.name = scene.get("placeName")
        self.words = name_words(self.name)
        # Where the entry's own answer says its scene began (a sentence number), if it said.
        self.start = raw.get("sceneStart")

    @property
    def ident(self):
        """What the listener would call the same scene: the place and its sounds. Without
        any sound one place is like another."""
        return (self.place, self.keys) if self.layers else (None, self.keys)

    @property
    def sound(self):
        """Exactly what plays: StoryScene.soundsLike compares this."""
        return (self.place, self.layers)

    @property
    def silent(self):
        return not self.layers

    def text(self):
        return (self.place or "-") + "|" + ",".join(f"{k}:{level}" for k, level in self.layers)


SILENT = Entry({"globalIndex": -1, "scene": {"placeID": None, "layers": [], "confidence": 1.0}})


def load(path):
    track = json.load(open(path, encoding="utf-8"))
    entries = sorted((Entry(e) for e in track.get("entries") or []), key=lambda e: e.g)
    if not entries:
        sys.exit(f"{path}: the track has no entries")
    return track, entries


def name_twins(track, entries):
    """Pairs of place ids whose names match as PlaceMemory.namesMatch does: maybe one
    place under two ids. A skeleton carries the pairs it was written with."""
    if track.get("skeleton"):
        return [tuple(pair) for pair in track.get("nameTwins") or []], track.get("namedPlaces", 0)
    names = {}
    for e in entries:
        if e.place and e.words:
            names.setdefault(e.place, e.words)
    ids = sorted(names, key=lambda p: (len(p), p))
    return [(a, b) for i, a in enumerate(ids) for b in ids[i + 1:] if names[a] <= names[b] or names[b] <= names[a]], len(ids)


def skeleton(track, entries):
    """The track's structure with none of its words."""
    twins, named = name_twins(track, entries)
    out = {
        "format": track.get("format", 1), "skeleton": True, "engineID": track.get("engineID", "?"), "bookID": "book",
        "wordsBetweenEntries": track.get("wordsBetweenEntries", 250), "chapterStarts": track.get("chapterStarts") or [],
        "variants": [{"id": v.get("id"), "of": v.get("of"), "firstIndex": v.get("firstIndex")} for v in track.get("variants") or []],
        "cues": [{"globalIndex": c["globalIndex"], "sound": c["sound"]} for c in track.get("cues") or []],
        "nameTwins": [list(pair) for pair in twins], "namedPlaces": named,
        "entries": [],
    }
    states = {}
    for e in entries:
        scene = {
            "placeID": e.place, "setting": e.setting, "confidence": round(e.conf, 3),
            "layers": [dict(sound=k.split(".")[0], level=level, **({"variant": k.split(".", 1)[1]} if "." in k else {})) for k, level in e.layers],
        }
        if e.moment:
            scene["moment"] = e.moment
        if e.transition:
            scene["transition"] = e.transition
        if e.state:
            scene["stateID"] = states.setdefault(e.state, f"s{len(states) + 1}")
        out["entries"].append(dict(globalIndex=e.g, scene=scene, **({"sceneStart": e.start} if e.start is not None else {})))
    return out


def median(values):
    values = sorted(values)
    return values[len(values) // 2] if values else 0


def pct(part, whole):
    return f"{100 * part / whole:.0f}%" if whole else "n/a"


# ---- how different two sounds are, and settling

def _weights(entry, family):
    out = {}
    for key, level in entry.layers:
        k = key.split(".")[0] if family else key
        out[k] = max(out.get(k, 0.0), LEVEL_WEIGHT.get(level, 2.0))
    return out


def _jaccard(a, b):
    keys = sorted(set(a) | set(b))
    top = sum(max(a.get(k, 0.0), b.get(k, 0.0)) for k in keys)
    return sum(min(a.get(k, 0.0), b.get(k, 0.0)) for k in keys) / top if top else 1.0


def difference(playing, entry):
    """How wrong `playing`'s sound is for `entry`, 0 (the same) to 1 (nothing shared).
    Half by exact sounds and half by their families, each weighted by level, so a
    café for a crowd, or the same sounds a step louder, is a small difference."""
    if playing.sound == entry.sound or (playing.silent and entry.silent):
        return 0.0
    same = 0.5 * _jaccard(_weights(playing, False), _weights(entry, False)) + 0.5 * _jaccard(_weights(playing, True), _weights(entry, True))
    place = 0.0 if playing.place == entry.place else PLACE_COST
    return min(1.0, place + (1.0 - place) * (1.0 - same))


def settle(entries, change, min_conf, moment_discount=0.5):
    """The entry whose sound plays from each entry on (None before the first
    confident entry). Entries under `min_conf` have no say, as in the director.
    A change onto a swell or hush costs `moment_discount` of the usual."""
    voting = [i for i, e in enumerate(entries) if e.conf >= min_conf]
    played = [None] * len(entries)
    if not voting:
        return played
    # One state per distinct sound, in order of first appearance.
    state_of, reps = {}, []
    for i in voting:
        if entries[i].sound not in state_of:
            state_of[entries[i].sound] = len(reps)
            reps.append(entries[i])
    count = len(reps)
    inf = float("inf")
    best = [inf] * count
    back = []
    for n, i in enumerate(voting):
        e = entries[i]
        length = float((entries[voting[n + 1]].g - e.g) if n + 1 < len(voting) else TAIL_SENTENCES)
        own = state_of[e.sound]
        row = list(range(count))
        if n == 0:
            best[own] = 0.0
        else:
            # The first of the cheapest, so ties always go the same way.
            cheapest = min(range(count), key=lambda m: best[m])
            turn = best[cheapest] + change * (moment_discount if e.moment else 1.0)
            if cheapest != own and turn < best[own]:
                best[own] = turn
                row[own] = cheapest
        for m in range(count):
            if best[m] < inf:
                best[m] += length * difference(reps[m], e)
        back.append(row)
    m = min(range(count), key=lambda k: best[k])
    states = []
    for n in range(len(voting) - 1, -1, -1):
        states.append(m)
        m = back[n][m]
    states.reverse()
    by_voting = dict(zip(voting, states))
    current = None
    for i in range(len(entries)):
        if i in by_voting:
            current = reps[by_voting[i]]
        played[i] = current
    return played


def infers_transition(old, new):
    """SceneTransition.inferred in Swift, as yes or no: the player gives this change of
    place a door, an engine or a crowd left behind."""
    if not old.place or old.place == new.place or old.silent or new.silent:
        return False

    def voices(e):
        return any(k.split(".")[0] in VOICES and LEVEL_WEIGHT.get(level, 2.0) >= 2.0 for k, level in e.layers)

    a, b = old.setting, new.setting
    if a == "vehicle" or b == "vehicle":
        return not (a == "vehicle" and b == "vehicle")
    if {a, b} == {"indoors", "outdoors"}:
        return True
    if a == b and a in ("indoors", "outdoors"):
        return voices(old) or voices(new)
    return False


def changes(entries, min_conf, max_lag, resolution):
    """SceneChangeFinder.changes in Swift: the changes of sound the listener hears, each
    with the entry before it, how different the sounds are, and the sentence to score
    next (None when pinned)."""
    out = []
    playing = None  # the newest entry sure enough to be played
    for i, e in enumerate(entries):
        if e.conf < min_conf:
            continue
        if i > 0:
            previous = entries[i - 1]
            before = playing if playing is not None and e.g - 1 - playing.g <= max_lag else SILENT
            if not (before.silent and e.silent) and (before.place != e.place or before.keys != e.keys):
                gap = e.g - previous.g
                needed = 1 if e.moment or e.transition or infers_transition(before, e) else resolution
                own = e.start == e.g
                probe, hinted = None, False
                if not own and gap > needed:
                    if e.start is not None and previous.g < e.start < e.g:
                        probe, hinted = e.start, True
                    else:
                        probe = previous.g + gap // 2
                out.append({"from": previous.g, "at": e.g, "gap": gap, "needed": needed, "difference": difference(before, e),
                            "probe": probe, "hinted": hinted, "own": own})
        playing = e
    return out


# ---- the director

def targets(entries, end, min_conf, max_lag, played=None):
    """What the director is asked to play: pieces (from sentence, to sentence, the sound,
    whether it is a swell or hush on its own sentence, the confident entry behind it)."""
    pieces = []
    good = None
    for i, e in enumerate(entries):
        stop = entries[i + 1].g if i + 1 < len(entries) else end
        if e.conf >= min_conf:
            good = i
        if good is None:
            pieces.append((e.g, stop, SILENT, False, None))
            continue
        source = entries[good]
        want = source if played is None else (played[good] or SILENT)
        moment = bool(good == i and source.moment and want.sound == source.sound)
        fade = source.g + max_lag + 1  # the first sentence the entry is too old for
        if fade <= e.g:
            pieces.append((e.g, stop, SILENT, False, None))
        elif fade < stop:
            pieces.append((e.g, fade, want, moment, source))
            pieces.append((fade, stop, SILENT, False, None))
        else:
            pieces.append((e.g, stop, want, moment, source))
    return pieces


def director(pieces, sps, dwell):
    """What plays: segments [from seconds, to seconds, the entry whose sound plays,
    "scene" or "level" when it starts with a change, the entry behind a change that
    began on its own sentence], and the changes the dwell delayed or dropped."""
    heard = []
    playing, last_change = SILENT, -1e18
    delayed = dropped = 0
    for start_g, stop_g, want, moment, source in pieces:
        start, stop = start_g * sps, stop_g * sps
        if want.sound != playing.sound:
            at = start if moment else max(start, last_change + dwell)
            if at < stop:
                if at > start:
                    delayed += 1
                    heard.append([start, at, playing, None, None])
                # Between two scenes without sound the director changes, and nobody hears it.
                kind = None if want.silent and playing.silent else ("scene" if want.ident != playing.ident else "level")
                playing, last_change = want, at
                own = source if source is not None and source.g == start_g else None
                heard.append([at, stop, playing, kind, own])
                continue
            dropped += 1
        heard.append([start, stop, playing, None, None])
    return [h for h in heard if h[1] > h[0]], delayed, dropped


def listen(entries, end, args, played=None):
    """Everything measured about what the listener hears."""
    sps = args.seconds_per_sentence
    own = targets(entries, end, args.min_confidence, args.max_lag)
    pieces = own if played is None else targets(entries, end, args.min_confidence, args.max_lag, played)
    heard, delayed, dropped = director(pieces, sps, args.dwell)
    total = sum(h[1] - h[0] for h in heard) or 1e-9
    hours = total / 3600
    changes = [h for h in heard if h[3]]
    scene_changes = [h for h in changes if h[3] == "scene"]
    # Scenes: stretches with the same place and sounds (levels may move inside one).
    scenes = []
    for start, stop, e, kind, _ in heard:
        if scenes and scenes[-1][2].ident == e.ident:
            scenes[-1][1] = stop
        else:
            scenes.append([start, stop, e])
    holds = [stop - start for start, stop, _ in scenes]
    # Against what the track asked for, by time.
    exact = same_sounds = off = 0.0
    j = 0
    for start_g, stop_g, want, _, _ in own:
        a, b = start_g * sps, stop_g * sps
        while j < len(heard) and heard[j][1] <= a:
            j += 1
        k = j
        while k < len(heard) and heard[k][0] < b:
            lo, hi = max(a, heard[k][0]), min(b, heard[k][1])
            if hi > lo:
                playing = heard[k][2]
                exact += (hi - lo) * (playing.sound == want.sound or (playing.silent and want.silent))
                same_sounds += (hi - lo) * (playing.ident == want.ident)
                off += (hi - lo) * difference(playing, want)
            k += 1
    index = {e.g: i for i, e in enumerate(entries)}
    late = [0 if h[4].start == h[4].g else h[4].g - entries[index[h[4].g] - 1].g
            for h in scene_changes if h[4] is not None and index[h[4].g] > 0]
    flips = {"to silence": [], "to another place": [], "same place, other sounds": []}
    for a, b, c in zip(scenes, scenes[1:], scenes[2:]):
        if a[2].ident == c[2].ident:
            kind = "to silence" if b[2].silent else ("to another place" if b[2].place != a[2].place else "same place, other sounds")
            flips[kind].append(b[1] - b[0])
    return {
        "heard": heard, "scenes": scenes, "total": total, "hours": hours, "delayed": delayed, "dropped": dropped,
        "changes": len(changes), "scene_changes": len(scene_changes), "holds": holds, "flips": flips,
        "exact": exact / total, "same_sounds": same_sounds / total, "off": off / total, "late": late,
        "silent": sum(h[1] - h[0] for h in heard if h[2].silent) / total,
    }


def report(path, args):
    track, entries = load(path)
    if args.skeleton:
        json.dump(skeleton(track, entries), open(args.skeleton, "w", encoding="utf-8"), separators=(",", ":"))
        print(f"wrote {args.skeleton}: the structure of {len(entries)} entries, none of their words")
    sps = args.seconds_per_sentence
    gaps = [b.g - a.g for a, b in zip(entries, entries[1:])]
    end = entries[-1].g + TAIL_SENTENCES
    cues = track.get("cues") or []
    m = listen(entries, end, args)
    hours, total = m["hours"], m["total"]

    print(f"# {track.get('bookID', '?') if args.names else 'a book'} by {track.get('engineID', '?')}: {len(entries)} entries over "
          f"{hours:.1f} h (at {sps:g} s a sentence), {len({e.place for e in entries if e.place})} places, "
          f"{len(track.get('variants') or [])} specific sounds in the track, {len(cues)} one-off sounds")

    # ---- as scored
    print("## Scenes as scored")
    confident = [e for e in entries if e.conf >= args.min_confidence]
    print(f"  confident enough to play (>= {args.min_confidence:g}): {len(confident)} of {len(entries)} ({pct(len(confident), len(entries))});"
          f" no place: {sum(1 for e in entries if not e.place)}; no sound: {sum(1 for e in entries if e.silent)};"
          f" confident with no sound: {sum(1 for e in confident if e.silent)}")
    with_sound = [e for e in entries if not e.silent]
    layer_count = sum(len(e.layers) for e in with_sound)
    specific = sum(1 for e in with_sound for k, _ in e.layers if "." in k)
    print(f"  sounds per scene: {layer_count / max(1, len(with_sound)):.1f}; a specific kind (family.kind) in "
          f"{pct(sum(1 for e in with_sound if any('.' in k for k in e.keys)), len(with_sound))} of scenes, {pct(specific, layer_count)} of sounds")
    levels = {}
    for e in with_sound:
        for _, level in e.layers:
            levels[level] = levels.get(level, 0) + 1
    print("  levels: " + ", ".join(f"{k} {pct(v, layer_count)}" for k, v in sorted(levels.items(), key=lambda x: -x[1])))
    place_turn = sound_turn = level_turn = 0
    for a, b in zip(entries, entries[1:]):
        if a.place != b.place:
            place_turn += 1
        elif a.keys != b.keys:
            sound_turn += 1
        elif a.layers != b.layers:
            level_turn += 1
    turns = place_turn + sound_turn + level_turn
    print(f"  neighbouring entries differ {turns} times ({turns / hours:.1f} an hour): another place {place_turn},"
          f" same place other sounds {sound_turn}, same place only levels {level_turn}")
    ordered = sorted(gaps)
    print(f"  sentences between entries: median {median(gaps)}, 10% under {ordered[len(gaps) // 10] if gaps else 0}, 10% over {ordered[len(gaps) * 9 // 10] if gaps else 0}")

    # ---- after the director
    holds = m["holds"]
    print(f"## What the listener hears (after the director: at most one change per {args.dwell:g} s)")
    print(f"  changes an hour: {m['changes'] / hours:.1f} ({m['scene_changes'] / hours:.1f} of place or sounds, {(m['changes'] - m['scene_changes']) / hours:.1f} of level only)")
    print(f"  a scene (one place, one set of sounds) is held for a median of {median(holds) / 60:.1f} min; under 30 s: {pct(sum(1 for h in holds if h < 30), len(holds))},"
          f" under 1 min: {pct(sum(1 for h in holds if h < 60), len(holds))}, under 2 min: {pct(sum(1 for h in holds if h < 120), len(holds))}")
    quiet = sorted((stop - start for start, stop, e in m["scenes"] if e.silent), reverse=True)
    print(f"  no sound at all: {m['silent']:.0%} of the time, in {len(quiet)} stretches (the longest {quiet[0] / 60:.0f} min, the middle one {median(quiet) / 60:.1f} min);"
          f" changes the dwell delayed: {m['delayed']}, dropped: {m['dropped']}" if quiet else
          f"  no sound at all: 0% of the time; changes the dwell delayed: {m['delayed']}, dropped: {m['dropped']}")
    by_main = {}
    order = {"loud": 3, "full": 2, "soft": 1, "faint": 0}
    for start, stop, e, *_ in m["heard"]:
        if e.layers:
            main = max(e.layers, key=lambda kl: (order.get(kl[1], 1), kl[0]))[0]
            by_main[main] = by_main.get(main, 0.0) + stop - start
    print("  time by main sound: " + ", ".join(f"{k} {pct(v, total)}" for k, v in sorted(by_main.items(), key=lambda x: -x[1])[:12]))

    # ---- flicker
    scenes, flips = m["scenes"], m["flips"]
    count = sum(len(v) for v in flips.values())
    print("## Flicker")
    print(f"  there and back (A B A): {count} of the {max(0, len(scenes) - 1)} changes of place or sounds go to a B that the sound then leaves for A again"
          + "".join(f"; {k}: {len(v)} (B lasts a median of {median(v):.0f} s)" for k, v in flips.items() if v))
    print(f"  B lasts under a minute in {sum(1 for v in flips.values() for d in v if d < 60)} of them; each costs the listener two changes of sound")

    # ---- places
    visits = []  # [place, first entry, last entry, seconds, end, entries heard]
    for start, stop, e, *_ in m["heard"]:
        if not e.place:
            continue
        if visits and visits[-1][0] == e.place and visits[-1][4] == start:
            visits[-1][2] = e
            visits[-1][3] += stop - start
            visits[-1][4] = stop
            visits[-1][5].append(e)
        else:
            visits.append([e.place, e, e, stop - start, stop, [e]])
    by_place = {}
    for v in visits:
        by_place.setdefault(v[0], []).append(v)
    once = [p for p, vs in by_place.items() if len(vs) == 1]
    once_time = sum(by_place[p][0][3] for p in once)
    returns = same_layers = same_keys = same_place_keys = 0
    for vs in by_place.values():
        for prev, new in zip(vs, vs[1:]):
            returns += 1
            before, after = prev[2], new[1]
            same_layers += before.layers == after.layers
            same_keys += before.keys == after.keys
            same_place_keys += {k for k in before.keys if k.split(".")[0] not in WEATHER} == {k for k in after.keys if k.split(".")[0] not in WEATHER}
    print("## Places")
    print(f"  {len(by_place)} places heard; {len(once)} only once ({pct(once_time, total)} of the time, a median of {median([by_place[p][0][3] for p in once]) / 60:.1f} min each);"
          f" {len(by_place) - len(once)} returned to ({returns} returns, the most visited {max((len(v) for v in by_place.values()), default=0)} times)")
    print(f"  a return starts with the sounds the place had when the story left it: same sounds and levels {pct(same_layers, returns)},"
          f" same sounds {pct(same_keys, returns)}, same apart from the weather {pct(same_place_keys, returns)}")
    twins, named = name_twins(track, entries)
    print(f"  ids whose names match another id's (the same place twice?): {len(twins)} pairs among {named} named places"
          + (": " + ", ".join(f"{a}={b}" for a, b in twins[:12]) if twins else ""))
    seen = {}
    for vs in by_place.values():
        for n, v in enumerate(vs):
            for e in v[5]:
                if e.state:
                    seen.setdefault((e.place, e.state), {}).setdefault(n, set()).add(e.keys)
    repeated = [s for s in seen.values() if len(s) > 1]
    agree = sum(1 for s in repeated if len(set().union(*s.values())) == 1)
    print(f"  a place back in a state it had before (same note) gets the same sounds: {agree} of {len(repeated)}")
    inside = sum(1 for a, b in zip(scenes, scenes[1:]) if a[2].place and a[2].place == b[2].place)
    print(f"  the sounds change inside a place {inside} times ({inside / hours:.1f} an hour)")
    both = note_only = sound_only = 0
    for a, b in zip(confident, confident[1:]):
        if a.place and a.place == b.place:
            note, sound = a.state != b.state, a.layers != b.layers
            both += note and sound
            note_only += note and not sound
            sound_only += sound and not note
    print(f"  inside a place, between neighbouring entries: state note and sounds change together {both} times,"
          f" the note alone {note_only}, the sounds alone {sound_only}")
    if args.names:
        for place, vs in sorted(by_place.items(), key=lambda kv: -sum(v[3] for v in kv[1]))[:15]:
            name = next((e.name for e in entries if e.place == place and e.name), "?")
            print(f"    {place} {name!r}: {len(vs)} visits, {sum(v[3] for v in vs) / 60:.0f} min")

    # ---- pinning
    found = changes(entries, args.min_confidence, args.max_lag, args.resolution)
    print("## How closely the changes are pinned")
    print(f"  changes of sound the listener hears: {len(found)} ({len(found) / hours:.1f} an hour), of the {place_turn + sound_turn}"
          f" times neighbouring entries differ in place or sounds (the rest: neither has a sound, or the later one is too unsure to play)")
    if found:
        own = sum(1 for c in found if c["own"])
        near = sum(1 for c in found if c["probe"] is None and not c["own"])
        still = [c for c in found if c["probe"] is not None]
        print(f"  pinned: {own + near} ({pct(own + near, len(found))}): {own} by an answer that says its scene begins on its own sentence,"
              f" {near} with the entry before within {args.resolution} sentences (1 where a door or engine plays)")
        if still:
            requests = 0
            for c in still:
                gap = c["gap"]
                if c["hinted"]:
                    requests += 1
                    continue
                while gap > c["needed"]:
                    gap = (gap + 1) // 2
                    requests += 1
            widths = [c["gap"] for c in still]
            print(f"  not pinned: {len(still)}; the middle one may be up to {median(widths)} sentences (about {median(widths) * sps:.0f} s) late, the widest {max(widths)};"
                  f" {sum(1 for c in still if c['hinted'])} have a sentence named by their answer to score next;"
                  f" pinning them all takes about {requests} more requests")
        strong = sum(1 for c in found if c["difference"] >= 0.8)
        mild = sum(1 for c in found if c["difference"] < 0.4)
        print(f"  how different the two sounds are: nearly everything {strong}, in between {len(found) - strong - mild}, a little {mild}")

    # ---- moments and one-offs
    swells = sum(1 for e in entries if e.moment == "swell")
    hushes = sum(1 for e in entries if e.moment == "hush")
    by_cue = {}
    for c in cues:
        by_cue[c["sound"]] = by_cue.get(c["sound"], 0) + 1
    print("## Moments and one-off sounds")
    print(f"  swells {swells}, hushes {hushes} ({(swells + hushes) / hours:.1f} an hour); one-off sounds {len(cues)} ({len(cues) / hours:.1f} an hour)"
          + (": " + ", ".join(f"{k} {v}" for k, v in sorted(by_cue.items(), key=lambda x: -x[1])[:8]) if by_cue else ""))

    # ---- settling
    print("## Settling (a change of sound costs N sentences; after the director)")
    print(f"  {'rule':<12}{'changes/h':>10}{'of scene':>10}{'median hold':>13}{'under 1 min':>13}{'flips':>7}{'exact':>8}{'same sounds':>13}{'off':>7}{'pinned':>9}")

    def row(name, r):
        pinned = pct(sum(1 for d in r["late"] if d <= args.resolution), len(r["late"]))
        print(f"  {name:<12}{r['changes'] / hours:>10.1f}{r['scene_changes'] / hours:>10.1f}{median(r['holds']) / 60:>9.1f} min"
              f"{pct(sum(1 for h in r['holds'] if h < 60), len(r['holds'])):>13}{sum(len(v) for v in r['flips'].values()):>7}"
              f"{r['exact']:>8.0%}{r['same_sounds']:>13.0%}{r['off']:>7.3f}{pinned:>9}")

    row("as scored", m)
    costs = [1, 2, 3, 4, 6, 9]
    if args.settle is not None and args.settle not in costs:
        costs = sorted(costs + [args.settle])
    for cost in costs:
        played = settle(entries, cost, args.min_confidence)
        row(f"settle {cost:g}", listen(entries, end, args, played))
        if args.settled_out and args.settle == cost:
            with open(args.settled_out, "w", encoding="utf-8") as f:
                for e, p in zip(entries, played):
                    f.write(f"{e.g}\t{e.text()}\t{p.text() if p is not None else '-'}\n")
    print("  (exact / same sounds / off: share of narrated time on exactly what the track asked for, on its place and sounds, and the average difference)")
    print()


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("tracks", nargs="+")
    ap.add_argument("--seconds-per-sentence", type=float, default=6.5)
    ap.add_argument("--dwell", type=float, default=20)
    ap.add_argument("--min-confidence", type=float, default=0.35)
    ap.add_argument("--max-lag", type=int, default=80)
    ap.add_argument("--resolution", type=int, default=3)
    ap.add_argument("--names", action="store_true", help="also print place names (the scorer's words about the book)")
    ap.add_argument("--skeleton", help="write the track's structure, with none of its words, to this file")
    ap.add_argument("--settle", type=float, help="the settling cost that --settled-out writes")
    ap.add_argument("--settled-out", help="write one line per entry: sentence, sound scored, sound played")
    args = ap.parse_args()
    if (args.skeleton or args.settled_out) and len(args.tracks) > 1:
        sys.exit("--skeleton and --settled-out take one track at a time")
    if args.settled_out and args.settle is None:
        args.settle = 3
    for path in args.tracks:
        report(path, args)


if __name__ == "__main__":
    main()
