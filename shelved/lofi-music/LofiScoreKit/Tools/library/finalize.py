"""Turn the reviewed picks into the install list and the credits.

Usage: python -I finalize.py PICKS.csv CANDIDATES.csv OUT_DIR

Writes OUT_DIR/install.csv (for install_library.py on the Mac) and OUT_DIR/CREDITS.md.
"""
import csv
import os
import re
import sys

import pandas as pd

MOODS = ["Calm", "Cozy", "Playful", "Hopeful", "Melancholy", "Mysterious",
         "Tense", "Somber", "Romantic", "Dreamy", "Adventurous"]
CC_NAMES = {
    "creativecommons.org/publicdomain/zero/1.0": "CC0 1.0",
    "creativecommons.org/licenses/by/4.0": "CC BY 4.0",
    "creativecommons.org/licenses/by/3.0": "CC BY 3.0",
    "creativecommons.org/licenses/by-sa/4.0": "CC BY-SA 4.0",
    "creativecommons.org/licenses/by-sa/3.0": "CC BY-SA 3.0",
}


def clean_title(title):
    t = re.sub(r"\.mp3$", "", str(title).strip())
    t = re.sub(r"^(fsm-team-escp-|fsm-team-|barradeen-escp-)", "", t)
    if " " not in t and "-" in t:
        t = t.replace("-", " ")
    if t == t.lower():
        t = " ".join(w[:1].upper() + w[1:] for w in t.split(" "))
    t = re.sub(r"\s*\((\s*lo-?fi\s*,?)[^)]*\)\s*", " ", t, flags=re.I)  # "( Lofi , Chill )"
    t = re.sub(r"^.*\|\s*", "", t) if "|" in t else t                     # "Lo-Fi Hip Hop | Lines"
    t = re.sub(r"\s+", " ", t).strip()
    return t


def clean_artist(artist):
    a = re.sub(r"\s*\((aka|ex\.)[^)]*\)", "", str(artist)).strip()
    a = re.sub(r"\s*f\.k\.a\..*$", "", a).strip()
    return a


def safe(name):
    name = name.replace("/", "-").replace(":", " -").replace("|", "-")
    name = re.sub(r'[\\?*<>"]', "", name)
    name = re.sub(r"(\d+)\s*bpm", r"\1 b p m", name, flags=re.I)
    return re.sub(r"\s+", " ", name).strip(" .")


def license_name(url, fallback):
    for key, name in CC_NAMES.items():
        if key in str(url):
            return name
    return str(fallback)


def main():
    picks_path, cand_path, out_dir = sys.argv[1:4]
    os.makedirs(out_dir, exist_ok=True)
    picks = pd.read_csv(picks_path)
    cand = pd.read_csv(cand_path).set_index("id")
    rows = []
    used = set()
    for p in picks.itertuples():
        c = cand.loc[p.id]
        mood = p.mood.capitalize()
        title = clean_title(c.title)
        artist = clean_artist(c.artist)
        base = safe(f"{title} - {artist}")
        file = f"{mood}/{base}.mp3"
        k = 2
        while file.lower() in used:
            file = f"{mood}/{base} ({k}).mp3"
            k += 1
        used.add(file.lower())
        lic_url = re.sub(r"/deed\.[^/]*$", "", str(c.license_url).strip()).rstrip("/") + "/"
        lname = license_name(c.license_url, c.license)
        attribution = f'"{title}" by {artist}, {c.page_url}, licensed under {lname} ({lic_url})'
        rows.append({
            "id": p.id, "mood": mood, "file": file, "title": title, "artist": artist,
            "album": "" if c.source != "fma" else c.album, "page": c.page_url, "license": lic_url,
            "license_name": lname, "attribution": attribution, "source_file": c.file_url,
            "sha256": c.sha256, "local_path": c.local_path,
        })
    fields = list(rows[0].keys())
    with open(os.path.join(out_dir, "install.csv"), "w", newline="", encoding="utf-8") as handle:
        w = csv.DictWriter(handle, fieldnames=fields)
        w.writeheader()
        w.writerows(rows)

    by = {}
    for r in rows:
        by.setdefault(r["license_name"], []).append(r)
    with open(os.path.join(out_dir, "CREDITS.md"), "w", encoding="utf-8") as out:
        out.write("# Music credits\n\n")
        out.write(f"The Storyteller Lofi music library: {len(rows)} instrumental tracks in "
                  f"{len({r['mood'] for r in rows})} mood folders. Every file is the artist's own "
                  "release, used unmodified; the app only changes its volume and tone while it plays "
                  "under the narration. Each track stays under its own license, linked below; nothing "
                  "here adds terms to it. Every license was read on the track's own page when it was "
                  "downloaded on 9 November 2026, and tracks marked non-commercial (NC) or "
                  "no-derivatives (ND) were left out.\n\n")
        n_cc0 = sum(1 for r in rows if r["license_name"].startswith("CC0"))
        out.write(f"{n_cc0} of the {len(rows)} tracks are CC0 (public domain): a starter set built "
                  "only from those needs no credits at all.\n\n")
        attrib = [r for r in rows if not r["license_name"].startswith("CC0")]
        if attrib:
            out.write("## Attribution required (Creative Commons BY and BY-SA)\n\n")
            for mood in MOODS:
                for r in [r for r in attrib if r["mood"] == mood]:
                    out.write(f"- {mood}: {r['attribution']}\n")
            out.write("\n")
        cc0 = [r for r in rows if r["license_name"].startswith("CC0")]
        if cc0:
            out.write("## Public domain (CC0), credited with thanks\n\n")
            for mood in MOODS:
                for r in [r for r in cc0 if r["mood"] == mood]:
                    out.write(f"- {mood}: \"{r['title']}\" by {r['artist']}, {r['page']}\n")
            out.write("\n")
        sa = [r for r in rows if "BY-SA" in r["license_name"]]
        if sa:
            out.write("Note on the BY-SA tracks: if the app is ever shared beyond Mo's own phone, "
                      "credit them as above and check whether the share-alike terms reach the app's "
                      "audio. They are easy to swap out: each mood has CC0 or CC BY alternates in "
                      "LofiCandidates.\n")
    counts = pd.Series([r["mood"] for r in rows]).value_counts()
    print(counts.to_string())
    print(pd.Series([r["license_name"] for r in rows]).value_counts().to_string())


if __name__ == "__main__":
    main()
