"""Pick solo piano tracks for the darker moods: somber, melancholy and mysterious.

Usage: python -I pick_piano.py CANDIDATES.csv FEATURES.csv YAMNET_JSON_DIR INSTRUMENTS.jsonl SUSTAIN.csv OUT_DIR [OVERRIDES.csv]

Mo listened to the lofi picks for these moods and asked for piano on its own. Only
candidates tagged phase:piano are considered, and a track must really be piano alone:
no drums or beat, no strings, pads, guitar or winds for any real stretch, no voice.
INSTRUMENTS.jsonl comes from instruments.py, which keeps how long each kind of
instrument sounds, not only a track-wide average. SUSTAIN.csv comes from sustain.py,
which looks for notes that swell or hold, which a piano cannot do.

The classical recordings (Musopen) are known to be one piano. Modern "piano" tracks from
stock sites often have a pad or strings behind the piano, and YAMNet hears most of them
as plain "Music", so they get a stricter test whose limits were set from what the
classical recordings reach. Check modern picks on a spectrogram sheet as well.

OVERRIDES.csv (id,mood,weight) works as in pick.py: -9 on "*" drops a track, a small
weight nudges it, and a weight of 5 or more pins it to that mood ahead of the scores
(it must still pass the filters).

Evidence for each mood comes from the site's mood tags, the title, what is known about
classical pieces (piano_pieces.py), YAMNet's mood classes and the sound (mode, register,
density, how clear the key is). Ten moods compete, so a bright or dreamy piece is not
pushed into melancholy just because it is piano. Writes picks.csv, scored.csv and
review.txt like pick.py.
"""
import hashlib
import json
import os
import re
import subprocess
import sys

import numpy as np
import pandas as pd

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pick as base  # noqa: E402  (tag map, helpers)
import piano_pieces as pieces  # noqa: E402

MOODS = ["calm", "dreamy", "romantic", "hopeful", "playful", "adventurous", "melancholy", "somber",
         "mysterious", "tense"]
TARGETS = {"somber": 8, "melancholy": 8, "mysterious": 8}

# Title words for modern pieces. Matched on the lower-cased title.
LEX = [
    (r"\bsad\b|sadness|sorrow(?!ful)|lonel|\balone\b|solitude|\btears?\b|\bcry|memor|nostalg|remember|"
     r"forgot|\bautumn|\bfall\b|\brain\b|rainy|farewell|goodbye|longing|\blost\b|\bgone\b|\bempty|fading|"
     r"yesterday|regret|distant|missing|melanchol|wistful|\bblue\b|homesick|letters?\b|"
     r"\bthe past\b|october|solitary|wanderer|grey sky|gray sky|undertow|\bleap\b|remains of the day",
     {"melancholy": 1.0}),
    (r"grief|mourn|funeral|requiem|elegy|lament|dirge|\bdeath\b|dying|\bgrave\b|\btomb|sorrowful|"
     r"darkness|\bheavy|solemn|despair|tragedy|tragic|ashes|in memoriam|\bthe end\b|\bloss\b|\bcold\b|"
     r"desolat|filaments|keep us here", {"somber": 1.0}),
    (r"myster|secret|shadow|unknown|enigma|\bmist|\bfog|phantom|ghost|haunt|nocturnal|labyrinth|"
     r"riddle|hidden|whisper|strange|curious|cryptic|\bveil|\bomen|\bcandle|\bmidnight|nightwalk|"
     r"nightfall|\bdusk|\bdark\b|silhouette|uncanny|twilight|\bthe deep\b|\bcave|underground|\bspell|"
     r"uncertain|in the walls|out of reach", {"mysterious": 1.0}),
    (r"\bcalm|\bpeace|\bquiet|\bstill\b|seren|tranquil|\bgentle|\brest\b|\bsoft\b|meditat|\bbreath|"
     r"relax", {"calm": 1.0}),
    (r"\bdream|reverie|\bsleep|lullab|cloud|\bstars?\b|starlight|\bmoon|\bfloat|\bwonder|\bsky\b|"
     r"snowfall|\bsnow\b|ethereal|hazy", {"dreamy": 1.0}),
    (r"\blove|romanc|romantic|\bheart|\bkiss|\btender|darling|\bwith you\b|embrace|serenade|wedding|"
     r"valentine|only you|ceremony", {"romantic": 1.0}),
    (r"\bhope|sunrise|\bdawn|\bmorning|\bspring\b|new beginning|\blight\b|lights\b|\bbright|\brise\b|"
     r"\bsun|uplift|inspir|alive|freedom|summit|awaken", {"hopeful": 1.0}),
    (r"\bhappy|\bdance|\bjoy|\bplay|\bfun\b|children|childhood|butterfl|jolly|christmas|yuletide", {"playful": 1.0}),
    (r"tension|danger|chase|\bstorm|fury|panic|\bfear|\bbattle|\bwar\b|horror|decisive", {"tense": 1.0}),
    (r"\bepic|heroes|journey|adventure|reaching the sky|traveling|follow the river", {"adventurous": 1.0}),
]

# YAMNet mood classes -> moods (z-scored within the eligible pool).
YAM = {
    "melancholy": {"m_sad": 0.6, "m_tender": 0.3},
    "somber": {"m_sad": 0.6, "m_scary": 0.3},
    "mysterious": {"m_scary": 0.6, "m_sad": 0.2},
    "calm": {"m_tender": 0.4, "m_exciting": -0.3},
    "dreamy": {"m_tender": 0.4},
    "romantic": {"m_tender": 0.6},
    "hopeful": {"m_happy": 0.6},
    "playful": {"m_happy": 0.5, "m_funny": 0.4},
    "adventurous": {"m_exciting": 0.7},
    "tense": {"m_scary": 0.4, "m_angry": 0.4, "m_exciting": 0.4},
}
W = {"tags": 1.0, "title": 1.0, "classical": 1.2, "sound": 0.7, "yam": 0.35}

# The solo-piano test. Limits were set from the classical recordings in the pool, which are
# known to be one piano and nothing else: each limit sits a little above what those reach.
SOLO_LIMITS = {
    "drums": ("f15", 0.03), "strings": ("f30", 0.04), "synth": ("f30", 0.04), "guitar": ("f30", 0.06),
    "winds": ("f30", 0.03), "otherkeys": ("f30", 0.08), "bells": ("f30", 0.06), "nature": ("f30", 0.03),
    "applause": ("f30", 0.02),
}
# Extra limits for modern tracks, which are not known to be solo. On the classical set:
# ambient and synth are never heard, strings_f15 stays under 0.024, drums_f15 under 0.017,
# perc_ratio under 0.11 (0.08 without the fast waltzes), swell_e under 0.005.
EVEN_ABOVE = 9.5   # loudness range (LU) above which a pick is evened out at install
MODERN_LIMITS = {"ambient_f30": 0.02, "synth_f15": 0.01, "strings_f15": 0.025, "drums_f15": 0.02,
                 "perc_ratio": 0.09, "swell_e": 0.005, "steady_e": 0.012}


def evidence_tags(tags):
    out = {}
    for t in str(tags).split(";"):
        if t.startswith("mood:"):
            base.add(out, base.TAGMAP.get(t[5:], {}), 1.0)
    return {m: min(v, 1.5) for m, v in out.items()}


def evidence_title(text):
    out = {}
    for pattern, mapping in LEX:
        if re.search(pattern, text):
            base.add(out, mapping, 1.0)
    return {m: min(v, 1.5) for m, v in out.items()}


def edges(path, sr=22050):
    """Seconds of near-silence (45 dB under the loud parts) at the start and end of a file."""
    cmd = ["ffmpeg", "-v", "error", "-nostdin", "-i", path, "-ac", "1", "-ar", str(sr), "-f", "f32le", "-"]
    y = np.frombuffer(subprocess.run(cmd, capture_output=True, check=True, timeout=300).stdout, dtype=np.float32)
    n = int(0.05 * sr)
    k = len(y) // n
    e = 10 * np.log10((y[: k * n].reshape(k, n).astype(np.float64) ** 2).mean(axis=1) + 1e-12)
    live = np.where(e > np.percentile(e, 99) - 45)[0]
    return round(live[0] * 0.05, 2), round((k - 1 - live[-1]) * 0.05, 2)


def main():
    cand_path, feat_path, yam_dir, inst_path, sustain_path, out_dir = sys.argv[1:7]
    override_path = sys.argv[7] if len(sys.argv) > 7 else None
    os.makedirs(out_dir, exist_ok=True)
    cand = pd.read_csv(cand_path)
    cand = cand[cand.tags.fillna("").str.contains("phase:piano")].copy()
    feat = pd.read_csv(feat_path)
    feat["id"] = feat.path.str.extract(r"/(c\d{4})\.m4a$")[0]
    feat = feat.drop_duplicates("id", keep="last")
    d = cand.merge(feat, on="id", how="left", suffixes=("", "_f")).reset_index(drop=True)
    d["text"] = (d.title.fillna("") + " | " + d.album.fillna("") + " | " + d.artist.fillna("")).str.lower()
    d["composer"] = [pieces.composer_of(t) for t in d.text]
    d["title_clean"] = [pieces.display_title(t) if c else base.nice_title(t, a)
                        for t, a, c in zip(d.title, d.artist, d.composer)]
    d["fav"] = d.favorites.map(base.num)
    d["tempo_n"] = pd.to_numeric(d.tempo, errors="coerce")

    # First YAMNet pass: voice measures and mood classes.
    rows = []
    for p in d.path.fillna(""):
        row = {"speech_mean": 0.0, "singing_mean": 0.0, "vocal_share20": 0.0}
        jp = os.path.join(yam_dir, hashlib.sha1(p.encode()).hexdigest()[:16] + ".json") if p else ""
        if jp and os.path.exists(jp):
            j = json.load(open(jp))
            row["speech_mean"] = j.get("speech_mean", 0.0)
            row["singing_mean"] = j.get("singing_mean", 0.0)
            row["vocal_share20"] = float((np.array(j.get("vocal_curve", [0.0])) > 0.2).mean())
        rows.append(row)
    ex = pd.DataFrame(rows)
    for c in ex.columns:
        d[c] = ex[c].values
    # Second pass: instruments over time.
    inst = {}
    if os.path.exists(inst_path):
        for line in open(inst_path):
            if line.strip():
                j = json.loads(line)
                inst[j["path"]] = j
    groups = ["piano", "epiano", "drums", "strings", "synth", "ambient", "guitar", "winds", "otherkeys",
              "bells", "voice", "nature", "noise", "applause"]
    for g in groups:
        for stat in ("mean", "p95", "f15", "f30"):
            d[f"{g}_{stat}"] = [inst.get(p, {}).get(g, {}).get(stat, np.nan) for p in d.path.fillna("")]
    d["has_inst"] = [p in inst and "error" not in inst[p] for p in d.path.fillna("")]
    sus = pd.read_csv(sustain_path).drop_duplicates("path", keep="last").set_index("path")
    for c in ("swell_e", "steady_e"):
        d[c] = [sus[c].get(p, np.nan) for p in d.path.fillna("")]
    d["known_solo"] = (d.composer != "") & d.source.isin(pieces.SOLO_SOURCES)

    # --- filters -----------------------------------------------------------------------
    reasons, soft = {}, {}

    def flag(i, why):
        reasons.setdefault(i, []).append(why)

    for i, r in d.iterrows():
        if pd.isna(r.get("duration")) or (isinstance(r.get("error"), str) and r.get("error")) or not r.has_inst:
            flag(i, "not analysed")
            continue
        if base.EXCLUDE_TITLE.search(str(r.title)) or re.search(r"christmas|xmas|yuletide|auld lang|wedding|bridal",
                                                               str(r.title) + " " + str(r.genres), re.I):
            flag(i, "holiday or occasion music")
        if r.speech_frac > 0.02 or r.singing_frac > 0.02 or r.vocal_longest_s >= 2.5:
            flag(i, f"vocals (speech {r.speech_frac:.2f}, singing {r.singing_frac:.2f})")
        elif r.singing_mean > 0.02 or r.speech_mean > 0.015 or r.vocal_share20 > 0.05:
            flag(i, "vocal-like throughout")
        elif r.vocal_max > 0.35:
            if r.known_solo and r.vocal_longest_s <= 1.0:
                # One half-second frame in a recording known to be one piano: a false alarm
                # on a singing melody line, or at worst a breath.
                soft[i] = f"one voice-like frame (peak {r.vocal_max:.2f})"
            else:
                flag(i, f"brief vocal sample (peak {r.vocal_max:.2f})")
        if r.duration < 75 or r.duration > 420:
            flag(i, f"length {r.duration:.0f}s")
        # Piano swings far more than lofi. Up to EVEN_ABOVE the track is used as it is;
        # above it install_library.py evens it out (slow gain riding), which copes with
        # about 22 LU.
        if r.lra > (22 if r.known_solo else 16):
            flag(i, f"wide dynamics (loudness range {r.lra:.0f} LU)")
        if r.lufs < -34:
            flag(i, f"recorded very quietly ({r.lufs:.0f} LUFS)")
        # On the Musopen recordings YAMNet hears a piano at least 29% of the time.
        if r.piano_f15 < (0.25 if r.known_solo else 0.05):
            flag(i, f"piano not recognised ({r.piano_f15:.0%} of the time)")
        others = []
        for g, (stat, limit) in SOLO_LIMITS.items():
            v = r[f"{g}_{stat}"]
            if v > limit:
                others.append(f"{g} {v:.0%}")
        if not r.known_solo:
            for col, limit in MODERN_LIMITS.items():
                v = r[col]
                if pd.isna(v) or v > limit:
                    others.append(f"{col} {v:.3f}")
        if others:
            flag(i, "not piano alone: " + ", ".join(others))
        if not r.known_solo and r.piano_f15 < 0.1:
            soft[i] = f"piano barely recognised ({r.piano_f15:.0%})"
    d["excluded"] = [" ; ".join(reasons.get(i, [])) for i in d.index]
    d["note"] = [soft.get(i, "") for i in d.index]

    # --- evidence ----------------------------------------------------------------------
    pool_mask = d.excluded == ""
    zz = lambda col: base.z(d[col].where(pool_mask)).fillna(0)  # noqa: E731  z within the eligible pool
    minor = np.where(d["mode"] == "minor", 1.0, -1.0) * (0.5 + d.mode_clarity.abs().fillna(0.1).clip(0, 0.5))
    dark = -zz("centroid")
    slow = -zz("onset_rate")
    low = zz("bass")
    vague = -zz("key_r")
    sound = {
        "somber": 0.4 * minor + 0.35 * dark + 0.3 * slow + 0.15 * low,
        "melancholy": 0.55 * minor + 0.1 * dark + 0.1 * slow,
        "mysterious": 0.25 * minor + 0.4 * vague + 0.2 * slow + 0.2 * dark,
        "calm": -0.4 * minor + 0.35 * slow,
        "dreamy": -0.3 * minor - 0.3 * dark + 0.15 * slow,
        "romantic": -0.45 * minor + 0.05 * slow,
        "hopeful": -0.5 * minor - 0.3 * slow,
        "playful": -0.45 * minor - 0.5 * slow,
        "adventurous": -0.2 * minor - 0.6 * slow - 0.2 * dark,
        "tense": 0.35 * minor - 0.5 * slow + 0.15 * dark,
    }
    ev = {k: {m: np.zeros(len(d)) for m in MOODS} for k in W}
    forms, storms = [], []
    for n, r in d.iterrows():
        form, storm = "", 0
        if r.composer:
            form, moods = pieces.classical(r.text, r.composer)
            storm = moods.pop("storm", 0)
            for m, v in moods.items():
                if m in ev["classical"]:
                    ev["classical"][m][n] = v
        else:
            for k, e in (("tags", evidence_tags(r.tags)), ("title", evidence_title(str(r.title).lower()))):
                for m, v in e.items():
                    if m in ev[k]:
                        ev[k][m][n] = v
        forms.append(form)
        storms.append(storm)
    d["form"], d["storm"] = forms, storms
    for m in MOODS:
        ev["sound"][m] = np.clip(np.asarray(sound[m], dtype=float), -1.2, 1.2)
        ev["yam"][m] = np.clip(sum(w * zz(c).values for c, w in YAM[m].items() if c in d), -1.2, 1.2)
    total = pd.DataFrame({m: sum(ev[k][m] * w for k, w in W.items()) for m in MOODS})
    for m in MOODS:
        d["s_" + m] = total[m].round(2)
        d["sem_" + m] = (ev["tags"][m] * W["tags"] + ev["title"][m] * W["title"]
                         + ev["classical"][m] * W["classical"]).round(2)
        parts = {k: ev[k][m] * w for k, w in W.items()}
        d["why_" + m] = [" ".join(f"{k}{parts[k][n]:+.1f}" for k in W if abs(parts[k][n]) >= 0.15)
                         for n in range(len(d))]
    pins = {}
    if override_path and os.path.exists(override_path):
        ov = pd.read_csv(override_path, comment="#", skipinitialspace=True)
        for r in ov.itertuples():
            if r.weight >= 5 and r.mood in TARGETS:
                pins[r.id] = r.mood          # chosen by ear or by eye: goes in whatever the scores say
                continue
            for i in d.index[d.id == r.id]:
                for m in (MOODS if r.mood == "*" else [r.mood]):
                    if "s_" + m in d:
                        d.loc[i, "s_" + m] += r.weight
                        d.loc[i, "sem_" + m] += max(r.weight, 0)
    d["best"] = d[[f"s_{m}" for m in MOODS]].idxmax(axis=1).str[2:]

    # How well a track sits under a voice: even loudness, few notes, soft tone, no dance step.
    # Evening out takes most of the sting out of a wide loudness range, so count only part of it.
    d["lra_eff"] = np.where(d.lra > EVEN_ABOVE, EVEN_ABOVE + 0.3 * (d.lra - EVEN_ABOVE), d.lra)
    d["even"] = np.where(d.lra > EVEN_ABOVE, "yes", "")
    d["subtle"] = (-0.35 * zz("lra_eff") - 0.25 * zz("onset_rate") - 0.2 * zz("dyn") - 0.2 * zz("centroid")
                   - 0.5 * d.storm - np.where(d.form.isin(pieces.DANCES), 0.25, 0.0)).round(2)
    br = pd.to_numeric(d.bitrate_kbps, errors="coerce").fillna(256)
    # Solo piano needs few bits, so a variable-rate file of it averages well under 160 kbps.
    low = np.where(d.known_solo, 100, 160)
    d["quality"] = (np.where(br < low, -0.8, np.where(br >= 256, 0.15, 0.0))
                    + np.where(d.duration.between(100, 400), 0.15, 0.0)
                    + np.where(d.lra > 17, -0.2, 0.0)
                    + np.where(d.lufs < -30, -0.2, 0.0)
                    - 0.6 * d.noise_f30.fillna(0).clip(0, 0.5)
                    - np.where(d.note != "", 0.2, 0.0)).round(2)

    # --- selection ---------------------------------------------------------------------
    pool = d[d.excluded == ""].copy()
    picks, taken = [], set()
    supply = {m: int(((pool["s_" + m] >= pool[[f"s_{x}" for x in MOODS]].max(axis=1) - 0.3)
                      & (pool["s_" + m] > 0.6)).sum()) for m in TARGETS}
    for m in sorted(TARGETS, key=lambda x: supply[x]):
        other = pool[[f"s_{x}" for x in MOODS if x != m]].max(axis=1)
        fit = pool["s_" + m] - 0.5 * (other - pool["s_" + m]).clip(lower=0)
        rank = fit + 0.4 * pool.subtle + 0.35 * pool.quality
        cands = pool.assign(fit=fit.round(2), rank=rank.round(2), other=other).sort_values("rank", ascending=False)
        chosen = []
        for _, r in cands.iterrows():
            if pins.get(r.id) == m and len(chosen) < TARGETS[m]:
                r = r.copy()
                r["pass"] = "pinned"
                chosen.append(r)
                taken.add(r.id)
        for strict in (True, False):
            for _, r in cands.iterrows():
                if len(chosen) >= TARGETS[m]:
                    break
                if r.id in taken or r.id in pins:
                    continue
                if strict and (r["s_" + m] < 1.0 or r["s_" + m] < r.other - 0.2 or r["sem_" + m] < 0.4):
                    continue
                if not strict and (r["s_" + m] < 0.7 or r["s_" + m] < r.other - 0.4):
                    continue
                if r.known_solo and r["sem_" + m] < 0.4:
                    continue   # the sound alone is not enough to call a classical piece dark
                if not r.composer and sum(1 for c in chosen if c.artist == r.artist) >= 2:
                    continue
                if r.composer and sum(1 for c in chosen if c.composer == r.composer) >= (5 if r.composer == "chopin" else 2):
                    continue
                if r.form and sum(1 for c in chosen if c.form == r.form) >= (2 if r.form in pieces.DANCES else 3):
                    continue
                r = r.copy()
                r["pass"] = "strict" if strict else "relaxed"
                chosen.append(r)
                taken.add(r.id)
        for n, r in enumerate(chosen, 1):
            picks.append({"mood": m, "n": n, **r.to_dict()})
    pk = pd.DataFrame(picks)
    # What install_library.py should do to each pick: "even" (even out and trim), "trim"
    # (only cut silence off the ends; music starts from the top of a track, so a silent
    # lead-in is a late start) or nothing. A changed track stays under its own licence,
    # which for share-alike is what that licence asks, and the credits say what changed.
    # The library holds MP3s, so a pick in another format is at least trimmed (re-encoded).
    if len(pk):
        lead_trail = [edges(p) for p in pk.path]
        pk["lead_s"] = [a for a, _ in lead_trail]
        pk["trail_s"] = [b for _, b in lead_trail]
        not_mp3 = ~pk.local_path.fillna("").str.lower().str.endswith(".mp3")
        pk["process"] = np.where(pk.even == "yes", "even",
                                 np.where((pk.lead_s > 0.3) | (pk.trail_s > 2.0) | not_mp3, "trim", ""))
    cols = ["mood", "n", "id", "pass", "source", "artist", "album", "title_clean", "license", "fit", "rank",
            "subtle", "quality", "tempo_n", "key", "mode", "lufs", "lra", "duration", "bitrate_kbps", "best",
            "piano_f15", "piano_f30", "drums_f15", "strings_f15", "synth_f15", "ambient_f30", "swell_e", "steady_e",
            "perc_ratio", "known_solo", "composer", "form", "storm", "process", "lead_s", "trail_s", "note",
            "page_url", "local_path"]
    pk.reindex(columns=cols).to_csv(os.path.join(out_dir, "picks.csv"), index=False)
    d.to_csv(os.path.join(out_dir, "scored.csv"), index=False)
    with open(os.path.join(out_dir, "review.txt"), "w") as out:
        out.write(f"piano pool {len(d)}, eligible {len(pool)}, excluded {len(d) - len(pool)}\n")
        out.write("supply: " + ", ".join(f"{m} {supply[m]}" for m in TARGETS) + "\n")
        out.write("best mood of eligible tracks: " + ", ".join(
            f"{m} {n}" for m, n in pool.best.value_counts().items()) + "\n\n")
        for m in TARGETS:
            sel = pk[pk.mood == m] if len(pk) else pk
            out.write(f"== {m.upper()} ({len(sel)})\n")
            for r in sel.to_dict("records"):
                out.write(f"  {r['id']} {r['fit']:5.2f} {r['pass'][:3]} sub{r['subtle']:+.2f} q{r['quality']:+.2f} "
                          f"{r['tempo_n']:4.0f}bpm {r['key']}{'m' if r['mode'] == 'minor' else ''} "
                          f"{r['lufs']:5.1f}LUFS lra{r['lra']:4.1f} {r['duration']:4.0f}s on{r['onset_rate']:.1f} "
                          f"{r['license']} | {r['artist']} | {r['title_clean']} {'| even out ' if r['even'] else ''}{('| ' + r['note']) if r['note'] else ''}\n"
                          f"        [{r['why_' + m]}]\n")
            alt = pool[~pool.id.isin(taken)].assign(f=pool["s_" + m]).sort_values("f", ascending=False).head(12)
            for r in alt.itertuples():
                out.write(f"    alt {r.id} {r.f:5.2f} best={r.best} sub{r.subtle:+.2f} lra{r.lra:4.1f} | {r.artist} | {r.title_clean}\n")
            out.write("\n")
        out.write(f"== EXCLUDED ({len(d) - len(pool)})\n")
        for r in d[d.excluded != ""].itertuples():
            out.write(f"  {r.id} {r.artist} | {r.title_clean} | {r.excluded}\n")
    print(open(os.path.join(out_dir, "review.txt")).read()[:400])


if __name__ == "__main__":
    main()
