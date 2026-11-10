#!/usr/bin/env python3
"""Build a pool of candidate lofi tracks (download, catalog, convert). No ranking.

Usage: python3 build_candidates.py [phase ...]
  phases: fma-purrple fma-holizna fsm-tmw fsm-cats fma-extra analysis pack   (default: these)
  piano phases, run by name:
    first pass   fsm-piano fma-piano ia-musopen
    second pass  commons-piano2 fsm-piano2 pack-piano2
    third pass   commons-dl3 commons-reg3 ia-piano3 pack-piano3
  The Commons phases read piano2_commons.json beside this script: recordings picked by hand on
  Wikimedia Commons, each with the license read from its file page. upload.wikimedia.org answered
  429 to all but two of them (it wants a contact in the User-Agent), so most are still unfetched.
Resume-safe: state in LofiCandidates/.state.json; files already present with the right size are kept.
"""
import csv, hashlib, html, json, os, re, subprocess, sys, tarfile, time, urllib.parse, urllib.request

ROOT = os.path.expanduser("~/Storyteller Lofi/LofiCandidates")
STATE = os.path.join(ROOT, ".state.json")
LOG = os.path.join(ROOT, "build.log")
UA = "StorytellerLofi-library-builder/1.0 (personal, non-commercial)"
FMA = "https://freemusicarchive.org/music/"
FSM = "https://www.free-stock-music.com/"
HOLIZNA = """public-domain-lofi lo-fi-and-chill winter-lofi lazy-summer-lofi-1 chill-out spring-at-last-lofi-tape
summer-air-lo-fi spring-woke-me-up ocean-memory-lo-fi-chill nature-spirit after-dark sad-beats kick-it-laid-back-hiphop
beats-from-the-crypt horseless-headman-halloween-beats stranger-than-fiction-halloween-sci-fi
lullabies-for-the-end-of-the-world only-in-the-milky-way-part-1 only-in-the-milky-way-part-2 only-in-the-milky-way-part-3
space-sleep-meditation an-ocean-in-outer-space a-small-town-on-pluto a-lo-fi-christmas-special waves-of-nostalgia-2
background-music busted-guitar-lofi-edit city-slacker lost everything-hurts be-happy-with-who-you-are
gamer-soundtrack-quiet-towns gamer-soundtrack-caves gamer-soundtrack-haunted-mansion the-hero-and-the-haunting
all-the-years-ive-haunted-part-1 all-the-years-ive-haunted-part-2 all-the-years-ive-haunted-part-3 war-game-commission
washed-up townies left-overs tiny-plastic-video-games-for-long-anxious-space-travel""".split()
FSM_CATS = ["lo-fi", "chill-hop", "jazz-hop"]
MIN_S, MAX_S = 90, 390
VOCAL_RE = re.compile(r"\b(feat\.?|ft\.|featuring|vocals?|vocal\s+(mix|version|edit)|with\s+lyrics|sung\s+by|singer)\b", re.I)
COLS = ["id", "source", "artist", "album", "title", "page_url", "license", "license_url", "duration_s", "genres", "tags",
        "listens", "downloads", "favorites", "bpm", "file_url", "local_path", "bytes", "sha256", "bitrate_kbps",
        "sample_rate", "channels", "analysis_file"]
SKIP_COLS = ["source", "artist", "album", "title", "page_url", "license", "license_url", "duration_s", "reason"]

_last = [0.0]
def log(*a):
    s = time.strftime("%H:%M:%S ") + " ".join(str(x) for x in a)
    print(s, flush=True)
    with open(LOG, "a") as f: f.write(s + "\n")

def fetch(url, referer=None, dest=None, tries=4):
    """One request at a time, >=1 s between request starts."""
    for i in range(tries):
        wait = 1.0 - (time.time() - _last[0])
        if wait > 0: time.sleep(wait)
        _last[0] = time.time()
        h = {"User-Agent": UA}
        if referer: h["Referer"] = referer
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers=h), timeout=90) as r:
                ctype = r.headers.get("Content-Type", "")
                clen = r.headers.get("Content-Length")
                if dest is None:
                    return r.read().decode("utf-8", "replace")
                if "text/html" in ctype: raise IOError("got HTML instead of audio (" + r.geturl() + ")")
                tmp = dest + ".part"
                with open(tmp, "wb") as f:
                    while True:
                        b = r.read(1 << 16)
                        if not b: break
                        f.write(b)
                if clen and os.path.getsize(tmp) != int(clen): raise IOError("short download")
                os.replace(tmp, dest)
                return os.path.getsize(dest)
        except Exception as e:
            code = getattr(e, "code", None)
            if code in (403, 404, 410) or i == tries - 1: raise
            time.sleep(4 * (i + 1) * (5 if code == 429 else 1))

# ---------- state ----------
def load_state():
    if os.path.exists(STATE): return json.load(open(STATE))
    return {"kept": [], "skipped": [], "seen": {}, "albums": [], "errors": [], "notes": []}
def save_state(st):
    json.dump(st, open(STATE + ".tmp", "w"), indent=0); os.replace(STATE + ".tmp", STATE)
    write_csvs(st)
def write_csvs(st):
    with open(os.path.join(ROOT, "candidates.csv"), "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=COLS, extrasaction="ignore"); w.writeheader(); w.writerows(st["kept"])
    with open(os.path.join(ROOT, "skipped.csv"), "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=SKIP_COLS, extrasaction="ignore"); w.writeheader(); w.writerows(st["skipped"])

def san(s, n=100):
    s = re.sub(r'[\\/:*?"<>|\x00-\x1f]+', "-", s).strip().strip(".").strip()
    return (s[:n].strip() or "untitled")

def norm(s): return re.sub(r"[^a-z0-9]+", "", s.lower())

def lic_short(url):
    u = url.lower()
    m = re.search(r"publicdomain/(zero|mark)/([\d.]+)", u)
    if m: return ("CC0 " if m.group(1) == "zero" else "PDM ") + m.group(2)
    m = re.search(r"licenses/([a-z-]+)/([\d.]+)", u)
    if m: return "CC " + m.group(1).upper() + " " + m.group(2)
    return ""
def lic_ok(short):
    return short.startswith("CC0") or short.startswith("PDM") or re.match(r"CC BY(-SA)? [\d.]+$", short) is not None

def mmss(s):
    p = [int(x) for x in s.split(":")]
    v = 0
    for x in p: v = v * 60 + x
    return v

FFPROBE = "/opt/homebrew/bin/ffprobe"; FFMPEG = "/opt/homebrew/bin/ffmpeg"
def afinfo(path):
    if os.path.splitext(path)[1].lower() in (".ogg", ".oga", ".opus"):
        try:
            j = json.loads(subprocess.run([FFPROBE, "-v", "error", "-print_format", "json", "-show_format", "-show_streams", path],
                                          capture_output=True, text=True).stdout or "{}")
            a = [x for x in j.get("streams", []) if x.get("codec_type") == "audio"][0]
            f = j.get("format", {})
            return {"dur": float(f.get("duration") or a.get("duration")), "kbps": round(int(f.get("bit_rate", 0)) / 1000) or "",
                    "ch": int(a.get("channels") or 0), "sr": int(a.get("sample_rate") or 0)}
        except Exception: return {"dur": None, "kbps": "", "ch": "", "sr": ""}
    out = subprocess.run(["afinfo", path], capture_output=True, text=True).stdout
    d = {}
    m = re.search(r"estimated duration: ([\d.]+)", out); d["dur"] = float(m.group(1)) if m else None
    m = re.search(r"bit rate: (\d+)", out); d["kbps"] = round(int(m.group(1)) / 1000) if m else ""
    m = re.search(r"Data format:\s+(\d+) ch,\s+(\d+) Hz", out)
    d["ch"], d["sr"] = (int(m.group(1)), int(m.group(2))) if m else ("", "")
    return d

def skip(st, rec, reason):
    r = dict(rec); r["reason"] = reason
    st["skipped"].append(r); log("  - skip", rec.get("title"), "|", reason)

def _discard(path):
    """mv instead of delete: files go to LofiCandidates/.discarded/"""
    d = os.path.join(ROOT, ".discarded"); os.makedirs(d, exist_ok=True)
    os.replace(path, os.path.join(d, time.strftime("%Y%m%d-%H%M%S-") + os.path.basename(path)))

# ---------- core: one track ----------
def process(st, rec, referer=None):
    """rec has source, artist, album, title, page_url, license, license_url, duration_s, file_url, + meta."""
    key = rec["page_url"]
    if key in st["seen"]: return
    st["seen"][key] = 1
    if not lic_ok(rec["license"]):
        return skip(st, rec, "license not allowed: " + (rec["license"] or rec.get("license_raw") or "unknown"))
    d = rec.get("duration_s")
    if d in (None, ""): return skip(st, rec, "duration not shown on page")
    mn = rec.pop("min_s", MIN_S)
    if d < mn: return skip(st, rec, "too short (<%d:%02d)" % (mn // 60, mn % 60))
    mx = rec.pop("max_s", MAX_S)
    if d > mx: return skip(st, rec, "too long (>%d:%02d)" % (mx // 60, mx % 60))
    if VOCAL_RE.search(rec["title"]): return skip(st, rec, "title says vocals/featured singer")
    if rec.get("vocal_tag"): return skip(st, rec, "page tags say vocals")
    na = (norm(rec["artist"]), norm(rec["title"]))
    for k in st["kept"]:
        if (norm(k["artist"]), norm(k["title"])) == na and k["source"] != rec["source"]:
            return skip(st, rec, "duplicate of " + k["id"] + " (same artist+title from other source)")
    if not rec.get("file_url"): return skip(st, rec, "no audio file url")
    ext = os.path.splitext(urllib.parse.urlparse(rec["file_url"]).path)[1].lower() or ".mp3"
    title = rec.pop("fname", None) or re.sub(r"\.(mp3|wav|flac)$", "", rec["title"], flags=re.I)
    rel = os.path.join(san(rec["artist"]), san(rec["album"]), san(title + " - " + rec["artist"], 150) + ext)
    path = os.path.join(ROOT, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    try:
        if not os.path.exists(path) and rec.pop("no_download", False):
            return skip(st, rec, "not downloaded: upload.wikimedia.org answered 429 (rate limit for this User-Agent); retry later")
        rec.pop("no_download", None)
        if not os.path.exists(path):
            fetch(rec["file_url"], referer=referer, dest=path)
        else:
            log("  = present", rel)
    except Exception as e:
        st["errors"].append(rec["title"] + ": download failed: " + str(e))
        return skip(st, rec, "download failed: " + str(e))
    info = afinfo(path)
    if not info["dur"]:
        _discard(path); return skip(st, rec, "file does not decode (afinfo)")
    if abs(info["dur"] - d) > 0.05 * d:
        st["errors"].append("%s: afinfo %.1fs vs page %ss" % (rec["title"], info["dur"], d))
        _discard(path); return skip(st, rec, "afinfo duration %.1fs differs >5%% from page %ss" % (info["dur"], d))
    data = open(path, "rb").read()
    sha = hashlib.sha256(data).hexdigest()
    for k in st["kept"]:
        if k["sha256"] == sha:
            if k["local_path"] != rel: _discard(path)
            return skip(st, rec, "duplicate of " + k["id"] + " (identical file)")
    rec.update(id="c%04d" % (len(st["kept"]) + 1), local_path=rel, bytes=len(data), sha256=sha,
               bitrate_kbps=info["kbps"], sample_rate=info["sr"], channels=info["ch"], analysis_file="")
    st["kept"].append(rec)
    log("  + %s %s | %s | %s | %ss" % (rec["id"], rec["artist"], rec["title"], rec["license"], d))
    if len(st["kept"]) % 5 == 0: save_state(st)

# ---------- FMA ----------
def fma_album_tracks(url):
    out, pages, seen = [], [url], set()
    while pages:
        u = pages.pop(0)
        if u in seen: continue
        seen.add(u)
        p = fetch(u)
        for a, b in re.findall(r'data-track-info=(?:"([^"]+)"|\'([^\']+)\')', p):
            try: out.append(json.loads(html.unescape(a or b)))
            except json.JSONDecodeError: pass
        base = url.split("?")[0].rstrip("/")
        for m in set(re.findall(r'href="(' + re.escape(base) + r'/?\?page=\d+)"', p)):
            if m not in seen: pages.append(html.unescape(m))
    uniq, ids = [], set()
    for t in out:
        if t.get("id") in ids: continue
        ids.add(t.get("id")); uniq.append(t)
    return uniq

def fma_track_meta(page_url):
    p = fetch(page_url)
    m = re.search(r'<a rel="license" href="([^"]+)"[^>]*>([^<]*)</a>', p)
    if m: lurl, lraw = m.group(1), m.group(2).strip()
    else:
        cc = re.findall(r'href="(https?://creativecommons\.org/(?:licenses|publicdomain)/[^"]+)"', p)
        lurl, lraw = (cc[0], "") if cc else ("", "no creativecommons link on track page")
    meta = {"license_url": lurl, "license": lic_short(lurl), "license_raw": lraw}
    def count(label):
        m = re.search(r">\s*" + label + r"\s*</span>\s*</span>\s*<span[^>]*?(?:title=\"(\d+)\")?[^>]*>\s*([\d.,KkMm]*)", p)
        if not m: return ""
        return m.group(1) or m.group(2)
    meta["listens"], meta["downloads"], meta["favorites"] = count("Plays"), count("Downloads"), count("Favorites")
    ti = p.find("Track info")
    body = p[ti:] if ti >= 0 else p
    pre = p[:ti] if ti >= 0 else p
    durs = re.findall(r">\s*(\d{1,2}:\d{2}(?::\d{2})?)\s*<", pre)
    meta["duration_s"] = mmss(durs[-1]) if durs else None
    g = re.search(r">\s*Genres\s*</span>(.*?)</span>", body, re.S)
    meta["genres"] = ";".join(html.unescape(x.strip()) for x in re.findall(r"<a[^>]*>\s*([^<]+?)\s*</a>", g.group(1))) if g else ""
    tags = []
    tg = re.search(r">\s*Tags\s*</span>(.*?)</span>", body, re.S)
    if tg: tags += [html.unescape(x.strip()) for x in re.findall(r"<a[^>]*>\s*([^<]+?)\s*</a>", tg.group(1))]
    for lab in ("Instrumental", r"AI generated\?"):
        m = re.search(r">\s*" + lab + r"\s*</span>\s*<span[^>]*>\s*([^<]+?)\s*<", body)
        if m: tags.append(lab.replace("\\?", "").lower().replace(" ", "_") + "=" + m.group(1))
    meta["tags"] = ";".join(tags)
    meta["bpm"] = ""
    return meta

def fma_album(st, url, artist_hint, piano=False):
    if url in [a["url"] for a in st["albums"] if a.get("done")]:
        log("album already done:", url); return
    try: tracks = fma_album_tracks(url)
    except Exception as e:
        st["errors"].append("album " + url + ": " + str(e)); log("  ! album", url, e); return
    title = tracks[0].get("albumTitle", "") if tracks else ""
    log("ALBUM", url, "-", len(tracks), "tracks")
    for t in tracks:
        page = t.get("url") or ""
        if not page or page in st["seen"]: continue
        rec = {"source": "fma", "artist": t.get("artistName") or artist_hint, "album": t.get("albumTitle") or title,
               "title": (t.get("title") or "untitled").strip(), "page_url": page, "file_url": t.get("fileUrl") or ""}
        try: rec.update(fma_track_meta(page))
        except Exception as e:
            st["seen"][page] = 1; st["errors"].append(page + ": " + str(e))
            skip(st, rec, "track page failed: " + str(e)); continue
        if piano:
            rec["max_s"] = PIANO_MAX_S; rec["tags"] = "phase:piano;" + rec.get("tags", "")
            why = piano_reject(rec)
            if why:
                st["seen"][page] = 1; skip(st, rec, why); continue
        process(st, rec)
    st["albums"].append({"url": url, "title": title, "tracks": len(tracks), "done": True})
    save_state(st)

def fma_artist_albums(artist):
    p = fetch(FMA + artist + "/discography")
    skipw = {"", "bio", "contact", "followers", "discography", "tracks", "videos", "following"}
    out = []
    for m in re.findall(r'href="https://freemusicarchive\.org/music/' + re.escape(artist) + r'/([^"/?#]+)/?"', p, re.I):
        if m.lower() not in skipw and m not in out: out.append(m)
    return out

# ---------- FSM ----------
def fsm_track(st, slug, deadline=None, vocal_screen=False, piano=False):
    page = FSM + slug + ".html"
    if page in st["seen"]: return
    try: p = fetch(page)
    except Exception as e:
        st["seen"][page] = 1; st["errors"].append(page + ": " + str(e)); return
    def grab(rx):
        m = re.search(rx, p, re.S); return html.unescape(m.group(1).strip()) if m else ""
    artist = grab(r"<b>Artist / Author</b>:&nbsp;\s*<a[^>]*>([^<]+)</a>")
    ft = grab(r"<title>([^<]+)</title>")
    title = ft.split(" | Royalty Free")[0]
    if artist and title.endswith(" by " + artist): title = title[: -len(" by " + artist)]
    elif " by " in title: title = title.rsplit(" by ", 1)[0]
    title = title.strip()
    lurl = grab(r"<div class='licenseLinkText'>License:\s*<a[^>]*href='([^']+)'")
    lraw = grab(r"<div class='licenseLinkText'>License:\s*<a[^>]*>([^<]+)</a>")
    dur = grab(r"<b>Duration</b>:&nbsp;\s*([\d:]+)")
    cats = re.findall(r"<a href='[^']+'>([^<]+)</a>", grab(r"<p class='trackCategories'>(.*?)</p>"))
    moods = re.findall(r"<a href='[^']+'>([^<]+)</a>", grab(r"<p class='trackMoods'>(.*?)</p>"))
    tags = re.findall(r"<span>([^<]+)</span>", grab(r"<p class='tags'>(.*?)</p>"))
    fm = re.search(r"href='(/music/[^']+/mp3/" + re.escape(slug) + r"\.mp3)'", p)
    rec = {"source": "fsm", "artist": artist or "unknown", "album": "free-stock-music.com", "title": title or slug,
           "page_url": page, "license_url": lurl, "license": lic_short(lurl) if lurl else "",
           "license_raw": lraw or "no CC license on page (buy-a-license only?)",
           "duration_s": mmss(dur) if dur else None, "genres": ";".join(html.unescape(c) for c in cats),
           "tags": ";".join(["mood:" + html.unescape(m) for m in moods] + [html.unescape(t) for t in tags]),
           "listens": "", "downloads": "", "favorites": "", "bpm": grab(r"<b>BPM</b>:&nbsp;\s*(\d+)"),
           "file_url": urllib.parse.urljoin(FSM, fm.group(1)) if fm else ""}
    if vocal_screen and any(re.search(r"\b(vocals?|singing|singer|lyrics|rap|female voice|male voice)\b", t, re.I) for t in tags):
        rec["vocal_tag"] = True
    if piano:
        rec["max_s"] = PIANO_MAX_S; rec["tags"] = "phase:piano;" + rec["tags"]
        why = piano_reject(rec)
        if why:
            st["seen"][page] = 1; return skip(st, rec, why)
    process(st, rec, referer=page)

def fsm_list_slugs(url):
    p = fetch(url)
    slugs = []
    for s in re.findall(r"data-url='([^']+)'", p):
        if s not in slugs: slugs.append(s)
    return slugs

# ---------- phases ----------
def ph_fma_purrple(st):
    albums = fma_artist_albums("purrple-cat")
    if "singles" not in albums: albums.append("singles")
    log("Purrple Cat albums:", albums)
    for a in albums: fma_album(st, FMA + "purrple-cat/" + a, "Purrple Cat")

def ph_fma_holizna(st):
    for a in HOLIZNA: fma_album(st, FMA + "holiznacc0/" + a, "HoliznaCC0")

def ph_fsm_tmw(st):
    url = FSM + "artist.tokyo-music-walker.html"
    slugs = fsm_list_slugs(url)
    log("Tokyo Music Walker:", len(slugs), "tracks")
    for s in slugs: fsm_track(st, s)
    st["albums"].append({"url": url, "title": "Tokyo Music Walker (FSM artist page)", "tracks": len(slugs), "done": True})
    save_state(st)

def ph_fsm_cats(st, minutes=15):
    deadline = time.time() + minutes * 60
    pageno = {c: 1 for c in FSM_CATS}
    done = set()
    while time.time() < deadline and len(done) < len(FSM_CATS):
        for c in FSM_CATS:
            if c in done or time.time() >= deadline: continue
            url = FSM + (c + ".html" if pageno[c] == 1 else "%s-%d.html" % (c, pageno[c]))
            try: slugs = fsm_list_slugs(url)
            except Exception as e:
                log("  ! list", url, e); done.add(c); continue
            log("FSM category page", url, len(slugs), "tracks")
            if not slugs: done.add(c); continue
            st["albums"].append({"url": url, "title": "FSM category " + c + " page " + str(pageno[c]), "tracks": len(slugs), "done": True})
            for s in slugs:
                if time.time() >= deadline: break
                if s.startswith("tokyo-music-walker"): continue
                fsm_track(st, s, vocal_screen=True)
            pageno[c] += 1
            save_state(st)
    st["notes"].append("FSM categories stopped at pages %s (time box %d min)" % (pageno, minutes))
    save_state(st)

def ph_fma_extra(st, minutes=15):
    deadline = time.time() + minutes * 60
    for artist in ("lowtone-music", "elysium-sound"):
        try: albums = fma_artist_albums(artist)
        except Exception as e:
            st["errors"].append(artist + ": " + str(e)); continue
        log(artist, "albums:", albums)
        for a in albums:
            if time.time() >= deadline:
                st["notes"].append("FMA extra artists stopped by 15-min time box at " + artist + "/" + a); save_state(st); return
            fma_album(st, FMA + artist + "/" + a, artist)

def ph_analysis(st):
    adir = os.path.join(ROOT, "analysis"); os.makedirs(adir, exist_ok=True)
    for r in st["kept"]:
        out = os.path.join(adir, r["id"] + ".m4a")
        if not (os.path.exists(out) and os.path.getsize(out) > 1000):
            src = os.path.join(ROOT, r["local_path"]); tmpwav = None
            if os.path.splitext(src)[1].lower() in (".ogg", ".oga", ".opus"):
                tmpwav = out + ".tmp.wav"
                subprocess.run([FFMPEG, "-nostdin", "-v", "error", "-y", "-i", src, "-vn", "-ac", "2", "-c:a", "pcm_s16le", tmpwav], capture_output=True)
                src = tmpwav
            res = subprocess.run(["afconvert", "-f", "m4af", "-d", "aac@22050", "-c", "1", "-b", "48000",
                                  src, out + ".tmp.m4a"], capture_output=True, text=True)
            if tmpwav and os.path.exists(tmpwav): os.replace(tmpwav, os.path.join(ROOT, ".trash-tmp.wav"))
            if res.returncode != 0:
                st["errors"].append(r["id"] + ": afconvert failed: " + res.stderr.strip()[:200]); continue
            os.replace(out + ".tmp.m4a", out)
        r["analysis_file"] = "analysis/" + r["id"] + ".m4a"
    save_state(st)

def ph_pack(st):
    for f in os.listdir(ROOT):
        if re.match(r"pack-\d+\.tar$", f): os.remove(os.path.join(ROOT, f))
    limit = 300 * 1000 * 1000 - 2 * 1000 * 1000
    files = [r["analysis_file"] for r in st["kept"] if r.get("analysis_file")]
    n, size, tf = 0, 0, None
    csvsize = os.path.getsize(os.path.join(ROOT, "candidates.csv"))
    for rel in files:
        fs = os.path.getsize(os.path.join(ROOT, rel)) + 1024
        if tf is None or size + fs > limit:
            if tf: tf.close()
            n += 1; size = 0
            tf = tarfile.open(os.path.join(ROOT, "pack-%d.tar" % n), "w", format=tarfile.USTAR_FORMAT)
            if n == 1:
                tf.add(os.path.join(ROOT, "candidates.csv"), arcname="candidates.csv"); size += csvsize + 1024
        tf.add(os.path.join(ROOT, rel), arcname=rel); size += fs
    if tf: tf.close()
    for i in range(1, n + 1):
        p = os.path.join(ROOT, "pack-%d.tar" % i); log("pack", p, os.path.getsize(p))


# ---------- piano phases ----------
PIANO_MAX_S = 420
BEAT_RE = re.compile(r"lo-?fi|hip-?hop|chill-?hop|jazz-?hop|trip-?hop|beats?\b|drum|trap|dance|edm|house|techno|dubstep|rock|pop\b|funk|reggae|r&b|corporate|synthwave|chiptune|8-?bit|rap\b|electro\b|breakbeat", re.I)
def piano_reject(rec):
    """'' if the page says piano and names no beat/drum genre, else the reason."""
    text = " ".join([rec.get("genres", ""), rec.get("tags", "").replace("phase:piano", ""), rec.get("title", ""), rec.get("album", "")])
    if not re.search(r"piano", text, re.I): return "not piano (page genres/tags do not list piano)"
    m = BEAT_RE.search(rec.get("genres", "") + " " + rec.get("tags", ""))
    if m: return "piano but page lists a beat genre/tag: " + m.group(0)
    return ""

def fsm_pages(first, nxt, minutes, st, label):
    deadline = time.time() + minutes * 60
    n, prev = 1, None
    while time.time() < deadline:
        url = FSM + (first if n == 1 else nxt % n)
        try: slugs = fsm_list_slugs(url)
        except Exception as e:
            log("  ! list", url, e); break
        if not slugs or slugs == prev: break
        prev = slugs
        log("FSM", label, "page", n, len(slugs), "tracks")
        st["albums"].append({"url": url, "title": "FSM " + label + " page " + str(n), "tracks": len(slugs), "done": True})
        for s in slugs:
            if time.time() >= deadline: break
            fsm_track(st, s, vocal_screen=True, piano=True)
        save_state(st); n += 1
    st["notes"].append("FSM %s stopped at page %d (time box %d min)" % (label, n, minutes)); save_state(st)

def ph_fsm_piano(st, minutes=8):
    t_end = time.time() + minutes * 60
    fsm_pages("piano.html", "piano-%d.html", minutes * 0.6, st, "piano")
    for mood in ("sad", "melancholic", "dark", "strange"):
        left = (t_end - time.time()) / 60
        if left <= 0.5: st["notes"].append("FSM piano moods: no time left for " + mood); break
        fsm_pages("mood.%s.html" % mood, "mood." + mood + ".page-%d.html", min(left, 2.0), st, "mood " + mood)

FMA_PIANO = [("Sergey_Cheremisinov", None), ("lee-rosevere", ["music-for-podcasts-serious", "music-for-podcasts-ambient", "singles"]),
             ("Kevin_MacLeod", ["Calming", "Classical_Sampler", "Contemporary_Sampler"]), ("Borrtex", None),
             ("holiznacc0", ["depression", "will-you-miss-me", "scores", "transformations", "music-from-the-vault", "orphaned-media", "orphaned-media-pt-2"]),
             ("Kai_Engel", None), ("Chris_Zabriskie", None)]
def ph_fma_piano(st, minutes=6):
    deadline = time.time() + minutes * 60
    for artist, albums in FMA_PIANO:
        if albums is None:
            try: albums = fma_artist_albums(artist)
            except Exception as e:
                st["errors"].append("fma " + artist + ": " + str(e)); log("  ! artist", artist, e); continue
        log(artist, "albums:", albums)
        for a in albums:
            if time.time() >= deadline:
                st["notes"].append("FMA piano stopped by %d-min time box at %s/%s" % (minutes, artist, a)); save_state(st); return
            fma_album(st, FMA + artist + "/" + a, artist.replace("_", " "), piano=True)

IA_ITEMS = [  # (identifier, composer-or-None, include regex, exclude regex)
    ("musopen-chopin-complete-works-flac", "Frédéric Chopin",
     r"nocturne|prelude|waltz|valse|mazurka|largo|berceuse|cantabile|albumleaf|funeral march|marche funebre|tristesse|lament|'cello'|andantino|lento|impromptu|barcarolle|contredanse",
     r"cello sonata|trio|concerto|song|duo|flute|variations|krakowiak|fantasia|polonaise|rondo|op\. 74|scherzo|presto|finale"),
    ("MusopenCollectionAsFlac", None,
     r"schubert-sonata|beethoven.*sonata|goldberg|chopin|satie|debussy|schumann|liszt|mozart.*sonata|grieg-lyric",
     r"symphon|quartet|overture|concerto|trio|quintet|peergynt|violin|cello|allegro|presto|scherzo|rondo|vivace|fug"),
    ("MoonlightSonatamv.1", "Ludwig van Beethoven", r".", r"presto|allegretto"),
]
def ia_len(v):
    if not v: return None
    v = str(v)
    return mmss(v) if ":" in v else int(round(float(v)))
def ph_ia_musopen(st, minutes=9):
    deadline = time.time() + minutes * 60
    for ident, composer, inc, exc in IA_ITEMS:
        try: md = json.loads(fetch("https://archive.org/metadata/" + ident))
        except Exception as e:
            st["errors"].append("ia " + ident + ": " + str(e)); log("  ! ia", ident, e); continue
        meta = md.get("metadata", {})
        lurl = meta.get("licenseurl") or ""
        lshort = lic_short(lurl)
        files = [f for f in md.get("files", []) if f.get("name", "").lower().endswith(".mp3")]
        log("IA", ident, lshort or lurl or "no licenseurl", len(files), "mp3")
        st["albums"].append({"url": "https://archive.org/details/" + ident, "title": "archive.org " + (meta.get("title") or ident), "tracks": len(files), "done": True})
        for f in files:
            if time.time() >= deadline:
                st["notes"].append("archive.org Musopen stopped by %d-min time box in %s" % (minutes, ident)); save_state(st); return
            name = f["name"]
            q = urllib.parse.quote(name)
            base = os.path.splitext(os.path.basename(name))[0]
            comp = composer
            if not comp:
                comp = re.sub(r"(?<=[a-z])(?=[A-Z])", " ", base.split("-")[0]) if "-" in base else (meta.get("creator") or "unknown")
                if isinstance(comp, list): comp = comp[0]
            title = base
            perf = f.get("creator") or f.get("artist") or ""
            rec = {"source": "archive.org", "artist": comp, "album": "Musopen - " + (meta.get("title") or ident)[:80], "title": title,
                   "page_url": "https://archive.org/details/" + ident + "/" + q, "file_url": "https://archive.org/download/" + ident + "/" + q,
                   "license_url": lurl, "license": lshort, "license_raw": lurl or "item has no licenseurl",
                   "duration_s": ia_len(f.get("length")), "genres": "Classical;Piano",
                   "tags": ";".join(x for x in ["phase:piano", "musopen", "archive:" + ident, ("performer:" + perf) if perf else ""] if x),
                   "listens": "", "downloads": str(meta.get("downloads", "") or ""), "favorites": "", "bpm": "", "max_s": PIANO_MAX_S}
            key = rec["page_url"]
            if key in st["seen"]: continue
            if not re.search(inc, name, re.I) or re.search(exc, name, re.I):
                st["seen"][key] = 1; rec.pop("max_s"); skip(st, rec, "not a quiet solo-piano piece (title filter)"); continue
            process(st, rec)
        save_state(st)

PHASES = {"fma-purrple": ph_fma_purrple, "fma-holizna": ph_fma_holizna, "fsm-tmw": ph_fsm_tmw,
          "fsm-cats": ph_fsm_cats, "fma-extra": ph_fma_extra, "analysis": ph_analysis, "pack": ph_pack,
          "fsm-piano": ph_fsm_piano, "fma-piano": ph_fma_piano, "ia-musopen": ph_ia_musopen}

# ---------- piano pass 2 (mysterious) ----------
P2_JSON = os.path.join(os.path.dirname(os.path.abspath(__file__)), "piano2_commons.json")
def ph_commons_piano2(st, gap=12):
    retry = {r["page_url"] for r in st["skipped"] if r.get("source") == "commons" and r.get("reason", "").startswith("download failed")}
    st["skipped"] = [r for r in st["skipped"] if r["page_url"] not in retry]
    for u in retry: st["seen"].pop(u, None)
    for e in json.load(open(P2_JSON)):
        if e["page"] in st["seen"]: continue
        if not os.environ.get("P2_NODL"): time.sleep(gap)
        lurl = e["license_url"] or e["commons_license_url"] or ""
        lic = e["license"] or lic_short(lurl) or e["commons_license"]
        tags = ["phase:piano", "phase:piano2", "commons"] + (["performer:" + e["performer"]] if e["performer"] else [])
        if e["note"]: tags.append("note:" + e["note"].replace(";", ","))
        rec = {"source": "commons", "artist": e["composer"], "album": "Wikimedia Commons", "title": e["title"],
               "page_url": e["page"], "file_url": e["url"], "license": lic, "license_url": lurl,
               "license_raw": e["commons_license"], "duration_s": int(round(e["duration"])), "genres": "Classical;Piano",
               "tags": ";".join(tags), "listens": "", "downloads": "", "favorites": "", "bpm": "",
               "min_s": 60, "max_s": 480, "no_download": bool(os.environ.get("P2_NODL")), "fname": e["title"] + (" - " + e["performer"] if e["performer"] else "")}
        process(st, rec)
    save_state(st)

def ph_fsm_piano2(st, minutes=6):
    t_end = time.time() + minutes * 60
    for mood in ("melancholic", "dark", "strange", "mysterious", "mystical"):
        left = (t_end - time.time()) / 60
        if left <= 0.3: st["notes"].append("FSM piano2 moods: no time left for " + mood); break
        before = len(st["kept"])
        fsm_pages("mood.%s.html" % mood, "mood." + mood + ".page-%d.html", min(left, 1.6), st, "mood " + mood)
        for r in st["kept"][before:]:
            if "phase:piano2" not in r["tags"]: r["tags"] = r["tags"].replace("phase:piano;", "phase:piano;phase:piano2;", 1)
    save_state(st)

def ph_pack_piano2(st):
    rows = [r for r in st["kept"] if "phase:piano2" in r.get("tags", "") and r.get("analysis_file")]
    out = os.path.join(ROOT, "piano-pack-2.tar")
    args = ["tar", "-cf", out + ".tmp", "-C", ROOT, "candidates.csv"] + [r["analysis_file"] for r in rows]
    subprocess.run(args, check=True, env=dict(os.environ, COPYFILE_DISABLE="1"))
    os.replace(out + ".tmp", out)
    log("pack", out, os.path.getsize(out), len(rows), "analysis files")

PHASES.update({"commons-piano2": ph_commons_piano2, "fsm-piano2": ph_fsm_piano2, "pack-piano2": ph_pack_piano2})

# ---------- piano pass 3 ----------
WM_UA = "PianoLibraryBuilder/0.3 (personal one-time download of about 45 freely licensed piano recordings)"
# piano2_commons.json indices, most wanted first
P3_ORDER = [3, 2, 5, 6, 7, 18, 20, 19, 15, 16, 17, 27, 28, 30, 26, 29, 23, 24, 25,
            36, 37, 42, 43, 34, 35, 38, 39, 40, 41, 44, 22, 33, 21, 8, 9, 10, 11, 12, 1, 13, 14, 31, 32]
P3_LOG = os.path.join(ROOT, "commons3-dl.json")
def p3_path(e):
    fname = e["title"] + (" - " + e["performer"] if e["performer"] else "")
    ext = os.path.splitext(urllib.parse.urlparse(e["url"]).path)[1].lower()
    return os.path.join(ROOT, san(e["composer"]), san("Wikimedia Commons"), san(fname + " - " + e["composer"], 150) + ext)
def wm_get(url, dest):
    """one request, Wikimedia UA; returns (status, retry_after, info)"""
    try:
        with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": WM_UA}), timeout=120) as r:
            if "text/html" in r.headers.get("Content-Type", ""): return (r.status, None, "html instead of audio")
            clen = r.headers.get("Content-Length")
            with open(dest + ".part", "wb") as f:
                while True:
                    b = r.read(1 << 16)
                    if not b: break
                    f.write(b)
            if clen and os.path.getsize(dest + ".part") != int(clen): return (r.status, None, "short download")
            os.replace(dest + ".part", dest)
            return (r.status, None, "ok %d bytes" % os.path.getsize(dest))
    except urllib.error.HTTPError as e:
        return (e.code, e.headers.get("Retry-After"), e.read(300).decode("utf-8", "replace"))
    except Exception as e:
        return (None, None, repr(e))
def ph_commons_dl3(st):
    """Download only (no state writes). 30 s between files; on 429 wait Retry-After (300 s if none), retry once;
    stop for good after two files in a row still fail."""
    entries = json.load(open(P2_JSON))
    res = json.load(open(P3_LOG)) if os.path.exists(P3_LOG) else []
    first_wait = int(os.environ.get("P3_FIRST_WAIT", "0"))
    if first_wait: log("commons3: waiting %ds first (earlier Retry-After)" % first_wait); time.sleep(first_wait)
    fails, first = 0, True
    for i in P3_ORDER:
        e = entries[i]; dest = p3_path(e)
        if os.path.exists(dest): continue
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        if not first: time.sleep(30)
        first = False
        tries = []
        for attempt in (1, 2):
            code, ra, info = wm_get(e["url"], dest)
            tries.append({"t": time.strftime("%H:%M:%S"), "status": code, "retry_after": ra, "info": info[:300]})
            log("commons3", i, e["title"], e["performer"], "->", code, ra, info[:80].replace("\n", " "))
            if code == 429 and attempt == 1:
                w = int(ra) if (ra or "").isdigit() else 300
                log("commons3: 429, waiting", w, "s"); time.sleep(w); continue
            break
        ok = os.path.exists(dest)
        res.append({"idx": i, "title": e["title"], "performer": e["performer"], "ok": ok, "tries": tries})
        json.dump(res, open(P3_LOG, "w"), indent=1)
        fails = 0 if ok else fails + 1
        if fails >= 2:
            log("commons3: two files in a row failed; stopping Commons for good"); break
def ph_commons_reg3(st):
    entries = json.load(open(P2_JSON))
    for i in P3_ORDER:
        e = entries[i]
        if not os.path.exists(p3_path(e)) or any(k["page_url"] == e["page"] for k in st["kept"]): continue
        st["skipped"] = [r for r in st["skipped"] if r["page_url"] != e["page"]]
        st["seen"].pop(e["page"], None)
        lurl = e["license_url"] or e["commons_license_url"] or ""
        lic = e["license"] or lic_short(lurl) or e["commons_license"]
        tags = ["phase:piano", "phase:piano3", "phase:piano2", "commons"] + (["performer:" + e["performer"]] if e["performer"] else [])
        if e["note"]: tags.append("note:" + e["note"].replace(";", ","))
        rec = {"source": "commons", "artist": e["composer"], "album": "Wikimedia Commons", "title": e["title"],
               "page_url": e["page"], "file_url": e["url"], "license": lic, "license_url": lurl,
               "license_raw": e["commons_license"], "duration_s": int(round(e["duration"])), "genres": "Classical;Piano",
               "tags": ";".join(tags), "listens": "", "downloads": "", "favorites": "", "bpm": "",
               "min_s": 60, "max_s": 480, "fname": e["title"] + (" - " + e["performer"] if e["performer"] else "")}
        process(st, rec)
    save_state(st)
# archive.org piano3: (identifier, file name, composer, title, performer). Licenses read from each item's metadata.
WTC = "bach-well-tempered-clavier-book-1"
def _wtc(n, kind, key, bwv):
    return (WTC, "Kimiko Ishizaka - Bach- Well-Tempered Clavier, Book 1 - %02d %s No. %s, BWV %s.mp3" % (n, kind, key, bwv),
            "Johann Sebastian Bach", None, "Kimiko Ishizaka")
IA3 = [_wtc(15, "Prelude", "8 in E-flat minor", 853), _wtc(16, "Fugue", "8 in D-sharp minor", 853),
       _wtc(43, "Prelude", "22 in B-flat minor", 867), _wtc(44, "Fugue", "22 in B-flat minor", 867),
       _wtc(7, "Prelude", "4 in C-sharp minor", 849), _wtc(8, "Fugue", "4 in C-sharp minor", 849),
       _wtc(23, "Prelude", "12 in F minor", 857), _wtc(24, "Fugue", "12 in F minor", 857),
       _wtc(31, "Prelude", "16 in G minor", 861), _wtc(32, "Fugue", "16 in G minor", 861),
       _wtc(47, "Prelude", "24 in B minor", 869),
       ("satie-gnossienne-gymnopedie", "Satie Gnossienne 3.mp3", "Erik Satie", "Gnossienne No. 3 (Gregory Tait)", "Gregory Tait"),
       ("satie-gnossienne-gymnopedie", "Satie Gnossienne 1.mp3", "Erik Satie", "Gnossienne No. 1 (Gregory Tait)", "Gregory Tait"),
       ("satie-gnossienne-gymnopedie", "Satie Gymnopedie 1.mp3", "Erik Satie", "Gymnopédie No. 1 (Gregory Tait)", "Gregory Tait"),
       ("satie-gnossienne-gymnopedie", "Satie Gymnopedie 3.mp3", "Erik Satie", "Gymnopédie No. 3 (Gregory Tait)", "Gregory Tait"),
       ("a-02-gnossienne", "A02_Gnossienne.mp3", "Erik Satie", "Gnossienne No. 1 (Gregor Horvath, live)", "Gregor Horvath"),
       ("satie_gymnopedieI_20251213", "satie_gymnopedieI_20251213.mp3", "Erik Satie", "Gymnopédie No. 1 (Gregor Horvath)", "Gregor Horvath"),
       ("ThreeGnossiennesErikSatie", "Satie.mp3", "Erik Satie", "Gymnopédie No. 1 (Rafi Simcha)", "Rafi Simcha")]
def ph_ia_piano3(st):
    p2 = json.load(open(P2_JSON))
    meta = {}
    for ident, name, comp, title, perf in IA3:
        if ident not in meta:
            meta[ident] = json.loads(fetch("https://archive.org/metadata/" + ident))
            m = meta[ident]["metadata"]
            log("IA3", ident, "| licenseurl", m.get("licenseurl"), "| rights", m.get("rights"), "| date", m.get("date"))
        md = meta[ident]; m = md["metadata"]
        f = [x for x in md["files"] if x["name"] == name][0]
        lurl = m.get("licenseurl") or ""; lic = lic_short(lurl); raw = lurl
        tags = ["phase:piano", "phase:piano3", "performer:" + perf, "archive:" + ident]
        if ident == WTC:
            # item: licenseurl PDM 1.0, rights field 'Released under CC0 1.0 Universal'
            if "CC0" in (m.get("rights") or ""): lic, lurl = "CC0 1.0", "https://creativecommons.org/publicdomain/zero/1.0/"
            tags.append("note:item licenseurl PDM 1.0, rights CC0 1.0")
            bwv = re.search(r"BWV (\d+)", name).group(1); kind = "Prelude" if "Prelude" in name else "Fugue"
            title = [e["title"] for e in p2 if e["performer"] == "Kimiko Ishizaka" and bwv in e["title"] and kind in e["title"]][0]
        q = urllib.parse.quote(name)
        rec = {"source": "archive.org", "artist": comp, "album": "archive.org - " + re.sub(r"[​]", "", m.get("title") or ident)[:80], "title": title,
               "page_url": "https://archive.org/details/" + ident + "/" + q, "file_url": "https://archive.org/download/" + ident + "/" + q,
               "license": lic, "license_url": lurl, "license_raw": raw, "duration_s": ia_len(f.get("length")), "genres": "Classical;Piano",
               "tags": ";".join(tags), "listens": "", "downloads": str(m.get("downloads", "") or ""), "favorites": "", "bpm": "",
               "min_s": 60, "max_s": 480, "fname": title if ident != WTC else title + " - " + perf}
        if int(f.get("size", 0)) > 40e6: skip(st, rec, "file over 40 MB"); continue
        process(st, rec)
    save_state(st)
def ph_pack_piano3(st):
    rows = [r for r in st["kept"] if int(r["id"][1:]) >= 962 and r.get("analysis_file")]
    out = os.path.join(ROOT, "piano-pack-3.tar")
    args = ["tar", "-cf", out + ".tmp", "-C", ROOT, "candidates.csv"] + [r["analysis_file"] for r in rows]
    if os.path.exists(os.path.join(ROOT, "piano3-measure.csv")): args.append("piano3-measure.csv")
    subprocess.run(args, check=True, env=dict(os.environ, COPYFILE_DISABLE="1"))
    os.replace(out + ".tmp", out)
    log("pack", out, os.path.getsize(out), len(rows), "analysis files")
PHASES.update({"ia-piano3": ph_ia_piano3, "pack-piano3": ph_pack_piano3})
PHASES.update({"commons-dl3": ph_commons_dl3, "commons-reg3": ph_commons_reg3})
def main():
    os.makedirs(ROOT, exist_ok=True)
    phases = sys.argv[1:] or ["fma-purrple", "fma-holizna", "fsm-tmw", "fsm-cats", "fma-extra", "analysis", "pack"]
    st = load_state()
    for ph in phases:
        log("=== phase", ph)
        t0 = time.time()
        try: PHASES[ph](st)
        except Exception as e:
            st["errors"].append("phase " + ph + ": " + repr(e)); log("  ! phase", ph, repr(e))
        save_state(st)
        log("=== phase", ph, "done in %.0fs; kept %d skipped %d" % (time.time() - t0, len(st["kept"]), len(st["skipped"])))

main()
