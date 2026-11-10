"""Turn the reviewed picks into the install list and the credits.

Usage: python -I finalize.py PICKS.csv CANDIDATES.csv OUT_DIR

Writes OUT_DIR/install.csv (for install_library.py on the Mac) and OUT_DIR/CREDITS.md.
PICKS.csv needs the columns mood and id. An optional column process ("even" or "trim")
is passed on to install_library.py and written into the credits, since a licence that
asks for credit also asks that changes are said.
"""
import csv
import os
import re
import sys
import unicodedata

import pandas as pd

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import piano_pieces  # noqa: E402  (readable titles for classical recordings)

MOODS = ["Calm", "Cozy", "Playful", "Hopeful", "Melancholy", "Mysterious",
         "Tense", "Somber", "Romantic", "Dreamy", "Adventurous"]
CC_NAMES = {
    "creativecommons.org/publicdomain/zero/1.0": "CC0 1.0",
    "creativecommons.org/publicdomain/mark/1.0": "Public Domain Mark 1.0",
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
    # Plain ASCII: accented letters come in two encodings, and a file name that changes
    # encoding between the Mac, iCloud and the phone no longer matches library.json.
    name = unicodedata.normalize("NFKD", name).encode("ascii", "ignore").decode()
    name = name.replace("/", "-").replace(":", " -").replace("|", "-")
    name = re.sub(r'[\\?*<>"]', "", name)
    name = re.sub(r"(\d+)\s*bpm", r"\1 b p m", name, flags=re.I)
    return re.sub(r"\s+", " ", name).strip(" .")


def free_of_terms(name):
    """CC0 and public-domain recordings need no credit."""
    return name.startswith("CC0") or name.startswith("Public Domain")


def license_name(url, fallback):
    for key, name in CC_NAMES.items():
        if key in str(url):
            return name
    return str(fallback)


CHANGES = {
    "even": "loud and quiet passages evened out and silence trimmed from the ends",
    "trim": "silence trimmed from the ends",
}


def performer_of(tags):
    """Musopen names the pianist in the item's file list; the download step kept it as a tag."""
    m = re.search(r"performer:([^;]+)", str(tags))
    if not m:
        return ""
    return m.group(1).strip().replace("OIga", "Olga")   # typo on archive.org (capital i for l)


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
        musopen = c.source == "archive.org" and "musopen" in str(c.album).lower()
        classical = piano_pieces.is_classical(c)
        title = piano_pieces.display_title(c.title) if classical else clean_title(c.title)
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
        credit = artist
        if classical:
            # The licence belongs to the recording, so the credit names who played it.
            performer = performer_of(c.tags)
            credit = f"{artist}, played by {performer}" if performer and performer != artist else artist
            if musopen:
                credit += " (Musopen recording)"
        process = str(getattr(p, "process", "") or "")
        process = process if process in CHANGES else ""
        attribution = f'"{title}" by {credit}, {c.page_url}, licensed under {lname} ({lic_url})'
        if process:
            attribution += f"; changes: {CHANGES[process]}"
        rows.append({
            "id": p.id, "mood": mood, "file": file, "title": title, "artist": artist, "credit": credit,
            "album": "" if c.source != "fma" else c.album, "page": c.page_url, "license": lic_url,
            "license_name": lname, "attribution": attribution, "source_file": c.file_url,
            "sha256": c.sha256, "local_path": c.local_path, "process": process,
            "changes": CHANGES.get(process, ""),
        })
    fields = [k for k in rows[0].keys() if k != "credit"]
    with open(os.path.join(out_dir, "install.csv"), "w", newline="", encoding="utf-8") as handle:
        w = csv.DictWriter(handle, fieldnames=fields, extrasaction="ignore")
        w.writeheader()
        w.writerows(rows)

    by = {}
    for r in rows:
        by.setdefault(r["license_name"], []).append(r)
    with open(os.path.join(out_dir, "CREDITS.md"), "w", encoding="utf-8") as out:
        out.write("# Music credits\n\n")
        out.write(f"The Storyteller Lofi music library: {len(rows)} instrumental tracks in "
                  f"{len({r['mood'] for r in rows})} mood folders. ")
        changed = [r for r in rows if r["process"]]
        if changed:
            out.write(f"{len(rows) - len(changed)} files are the artist's own release, unmodified. "
                      f"The {len(changed)} solo piano recordings marked below were changed so they sit "
                      "under a voice: silence was trimmed from the ends, and where marked the loud and "
                      "quiet passages were brought closer together. Nothing else was altered. ")
        else:
            out.write("Every file is the artist's own release, used unmodified. ")
        out.write("The app only changes a track's volume and tone while it plays "
                  "under the narration. Each track stays under its own license, linked below; nothing "
                  "here adds terms to it. Every license was read on the track's own page when it was "
                  "downloaded on 9 and 10 November 2026, and tracks marked non-commercial (NC) or "
                  "no-derivatives (ND) were left out.\n\n")
        n_cc0 = sum(1 for r in rows if free_of_terms(r["license_name"]))
        out.write(f"{n_cc0} of the {len(rows)} tracks are CC0 or public domain: a starter set built "
                  "only from those needs no credits at all.\n\n")
        attrib = [r for r in rows if not free_of_terms(r["license_name"])]
        if attrib:
            out.write("## Attribution required (Creative Commons BY and BY-SA)\n\n")
            for mood in MOODS:
                for r in [r for r in attrib if r["mood"] == mood]:
                    out.write(f"- {mood}: {r['attribution']}\n")
            out.write("\n")
        cc0 = [r for r in rows if free_of_terms(r["license_name"])]
        if cc0:
            out.write("## Public domain (CC0 and public-domain recordings), credited with thanks\n\n")
            for mood in MOODS:
                for r in [r for r in cc0 if r["mood"] == mood]:
                    note = f" ({r['changes']})" if r["changes"] else ""
                    out.write(f"- {mood}: \"{r['title']}\" by {r['credit']}, {r['page']}{note}\n")
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
