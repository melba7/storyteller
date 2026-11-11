#!/usr/bin/env python3
"""Turn plain-text public-domain books into Storyteller-shaped readaloud EPUBs.

For every book in books/raw/<slug>.txt (see fetch_books.py) this writes

  books/json/<slug>.json   chapters -> paragraphs -> sentences (the canonical form)
  books/epub/<slug>/       an unzipped EPUB 3 directory shaped like Storyteller's
                           output: sentence spans `<chapterId>-s<n>` with
                           epub:type="storyteller:sentence-span", one SMIL media
                           overlay per chapter, and synthetic narration timing
                           (no real audio; clip times assume ~155 words a minute)

The eval and the training-data export read these through LofiScoreKit's real
EPUB path (`SpoilerGuard(epubDirectory:)`), so the books also exercise the
parser at scale.

    pip install pysbd
    python3 -I Tools/data/make_readaloud.py              # every fetched book
    python3 -I Tools/data/make_readaloud.py dracula      # one book
    python3 -I Tools/data/make_readaloud.py --report     # chapter summary only
"""
from __future__ import annotations

import csv
import html
import json
import pathlib
import re
import sys
from dataclasses import dataclass, field

import pysbd

HERE = pathlib.Path(__file__).resolve().parent
BOOKS = HERE / "books"

WORDS_PER_SECOND = 2.6  # ~155 words a minute, a typical narration pace
SENTENCE_GAP = 0.35  # seconds of silence after each sentence

# ---------------------------------------------------------------------------
# Paragraphs and headings
# ---------------------------------------------------------------------------

NUMBER_WORDS = [
    "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
    "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen",
    "eighteen", "nineteen", "twenty",
]
ORDINAL_WORDS = ["first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth", "ninth", "tenth"]

KEYWORD = re.compile(r"^(chapter|stave|book|part|letter)\b\.?\s*(?P<num>[ivxlcdm]+\b|\d+\b|[a-z\-]+)?", re.I)
ROMAN = re.compile(r"^(?P<num>[IVXLCDM]+)(?:\.(?:\s+(?P<title>\S.*))?|\s{2,}(?P<title2>\S.*)|\s+(?P<caps>[^a-z]+))?$")
ARABIC = re.compile(r"^(?P<num>\d{1,3})(?:\.(?:\s+(?P<title>\S.*))?|\s{2,}(?P<title2>\S.*)|\s(?P<title3>[A-Z][^.,;:!?]*))?$")
PAGE_NUMBER = re.compile(r"(\S.*\S)\s{3,}\d+$")
SIDENOTE = re.compile(r"^\[sidenote:\s*(?P<text>.+)\]$", re.I | re.S)
END_MARKERS = re.compile(
    r"^\s*(the end\.?|finis\.?|footnotes?:?|transcriber'?s notes?:?|end of (the )?project gutenberg.*)\s*$",
    re.I,
)


def roman_value(s: str) -> int | None:
    values = {"i": 1, "v": 5, "x": 10, "l": 50, "c": 100, "d": 500, "m": 1000}
    s = s.lower()
    if not s or any(c not in values for c in s):
        return None
    total = 0
    for i, c in enumerate(s):
        v = values[c]
        total += -v if i + 1 < len(s) and values[s[i + 1]] > v else v
    return total


def number_value(token: str | None) -> int | None:
    if not token:
        return None
    t = token.lower().strip(".")
    if t.isdigit():
        return int(t)
    if t in NUMBER_WORDS:
        return NUMBER_WORDS.index(t) + 1
    if t in ORDINAL_WORDS:
        return ORDINAL_WORDS.index(t) + 1
    return roman_value(t)


@dataclass
class Paragraph:
    lines: list[str]

    @property
    def text(self) -> str:
        return " ".join(line.strip() for line in self.lines)


@dataclass
class Heading:
    index: int  # paragraph index
    number: int | None
    label: str  # the heading line, cleaned


BRACKET_OPEN = re.compile(r"^\s*\[_?(illustration|footnote|sidenote|transcriber|note|this illustration)", re.I)


def paragraphs_of(raw: str) -> list[Paragraph]:
    paragraphs, current = [], []
    for line in raw.replace("\r\n", "\n").split("\n"):
        if line.strip():
            current.append(line.rstrip())
        elif current:
            paragraphs.append(Paragraph(current))
            current = []
    if current:
        paragraphs.append(Paragraph(current))
    # Drop illustration captions and footnotes, including ones that run over
    # several paragraphs before their closing bracket.
    kept, skipping = [], False
    for p in paragraphs:
        text = p.text.strip()
        if skipping:
            skipping = "]" not in text
            continue
        if BRACKET_OPEN.match(text):
            depth = text.count("[") - text.count("]")
            skipping = depth > 0
            rest = text[text.rfind("]") + 1:].strip() if not skipping else ""
            if rest and any(c.isalpha() for c in rest):
                kept.append(Paragraph([rest]))
            continue
        kept.append(p)
    return kept


def heading_of(p: Paragraph) -> tuple[int | None, str] | None:
    """Returns (number, label) when the paragraph looks like a chapter heading."""
    if len(p.lines) > 3 or any(len(line.strip()) > 72 for line in p.lines):
        return None
    first = p.lines[0].strip().strip("_")
    if m := KEYWORD.match(first):
        number = number_value(m.group("num"))
        bare = first.rstrip(".:").lower() == m.group(1).lower()
        if number is None and not bare:
            return None  # "Letter, Mina Murray to Lucy Westenra." is not a heading
        return number, first
    if m := ROMAN.match(first):
        title = m.group("title") or m.group("title2") or m.group("caps")
        if title and m.group("caps") and len(m.group("num")) == 1 and m.group("num") == "I":
            return None  # "I SAID IT." is prose, not "I. TITLE"
        return roman_value(m.group("num")), first
    if m := ARABIC.match(first):
        if m.group("title3") and not is_title_case(m.group("title3")):
            return None
        return int(m.group("num")), first
    return None


def is_title_case(t: str) -> bool:
    words = [w for w in re.split(r"\s+", t.strip()) if w]
    if not words or len(words) > 9:
        return False
    capitalized = sum(1 for w in words if w[:1].isupper() or not w[:1].isalpha())
    return capitalized / len(words) >= 0.6


def title_text(p: Paragraph) -> str:
    t = p.text.strip()
    if m := SIDENOTE.match(t):
        t = m.group("text")
    return t.strip().strip("_").strip()


def is_title_line(p: Paragraph) -> bool:
    if len(p.lines) != 1 and not SIDENOTE.match(p.text.strip()):
        return False
    t = title_text(p)
    if not t or len(t) > 70 or not any(c.isalpha() for c in t):
        return False
    if t.upper() == t:
        return True
    if t.endswith(('"', "'", "”", "’", "?", "!", ":", ";", ",")):
        return False
    return is_title_case(t)


# ---------------------------------------------------------------------------
# Cleaning
# ---------------------------------------------------------------------------

BRACKET_BLOCK = re.compile(r"\[_?(illustration|footnote|sidenote|transcriber|note|this illustration)[^\]]*(\]|$)", re.I | re.S)
INLINE_MARKER = re.compile(r"\[(\d{1,3}|[A-Z])\]")


def clean(text: str) -> str:
    text = BRACKET_BLOCK.sub(" ", text)
    text = INLINE_MARKER.sub("", text)
    text = re.sub(r"(?<![\w*])_(?=\S)(.+?)(?<=\S)_(?![\w*])", r"\1", text, flags=re.S)
    text = text.replace("_", " ")
    text = re.sub(r"\s*--+\s*", "—", text)
    text = re.sub(r"\s+", " ", text)
    return text.strip()


def tidy_heading(label: str) -> str:
    label = clean(label)
    label = PAGE_NUMBER.sub(r"\1", label).strip()
    if label.upper() == label:
        label = " ".join(w[:1].upper() + w[1:].lower() for w in label.split(" "))
    return label


# ---------------------------------------------------------------------------
# Chapters
# ---------------------------------------------------------------------------


@dataclass
class Chapter:
    heading: list[str]
    paragraphs: list[str] = field(default_factory=list)

    def words(self) -> int:
        return sum(len(p.split()) for p in self.paragraphs)


def body_words(paragraphs: list[Paragraph], start: int, end: int) -> int:
    return sum(len(paragraphs[i].text.split()) for i in range(start, end) if heading_of(paragraphs[i]) is None)


def chapters_of(raw: str, min_words: int = 150, min_chapter_words: int = 30, fallback_words: int = 3000) -> list[Chapter]:
    paragraphs = paragraphs_of(raw)
    # Cut end matter at the first end marker after the first third of the book.
    for i in range(len(paragraphs) // 3, len(paragraphs)):
        if len(paragraphs[i].lines) == 1 and END_MARKERS.match(paragraphs[i].lines[0]):
            paragraphs = paragraphs[:i]
            break

    headings = [Heading(i, h[0], h[1]) for i, p in enumerate(paragraphs) if (h := heading_of(p))]
    bounds = [h.index for h in headings] + [len(paragraphs)]
    long_enough = {h.index for k, h in enumerate(headings) if body_words(paragraphs, h.index + 1, bounds[k + 1]) >= min_words}

    # The story starts at the first heading numbered 1 that has a real body
    # (contents entries have none); otherwise at the first heading with a body.
    start = next((k for k, h in enumerate(headings) if h.number == 1 and h.index in long_enough), None)
    if start is None:
        start = next((k for k, h in enumerate(headings) if h.index in long_enough), None)

    if start is None or sum(1 for h in headings[start:] if h.index in long_enough) < 3:
        return fallback_chapters(paragraphs, fallback_words)

    chapters: list[Chapter] = []
    pending_heading: list[str] = []
    for k in range(start, len(headings)):
        h = headings[k]
        end = bounds[k + 1]
        i = h.index + 1
        heading = pending_heading + [tidy_heading(line) for line in paragraphs[h.index].lines]
        pending_heading = []
        # One title line after the heading (e.g. "1" then "The Old Sea-dog").
        if i < end and is_title_line(paragraphs[i]) and heading_of(paragraphs[i]) is None:
            heading.append(tidy_heading(title_text(paragraphs[i])))
            i += 1
        if body_words(paragraphs, i, end) < min_chapter_words:
            # "BOOK TWO" above "CHAPTER ONE": carry the heading into the next chapter.
            pending_heading = heading + [clean(paragraphs[j].text) for j in range(i, end) if clean(paragraphs[j].text)]
            continue
        chapter = Chapter(heading=heading)
        for j in range(i, end):
            text = clean(paragraphs[j].text)
            if any(c.isalpha() for c in text):
                chapter.paragraphs.append(text)
        chapters.append(chapter)
    if pending_heading and chapters:
        chapters[-1].paragraphs.extend(pending_heading)
    return chapters


def fallback_chapters(paragraphs: list[Paragraph], target_words: int) -> list[Chapter]:
    """No usable headings: cut the text into parts of about `target_words` words."""
    chapters: list[Chapter] = []
    current = Chapter(heading=["Part 1"])
    for p in paragraphs:
        text = clean(p.text)
        if not any(c.isalpha() for c in text):
            continue
        current.paragraphs.append(text)
        if current.words() >= target_words:
            chapters.append(current)
            current = Chapter(heading=[f"Part {len(chapters) + 1}"])
    if current.paragraphs:
        chapters.append(current)
    return chapters


# ---------------------------------------------------------------------------
# Sentences
# ---------------------------------------------------------------------------

_segmenter = pysbd.Segmenter(language="en", clean=False)


def sentences_of(paragraph: str) -> list[str]:
    out = []
    for s in _segmenter.segment(paragraph):
        s = s.strip()
        if not s:
            continue
        # pysbd sometimes leaves a lone closing quote or bracket as a sentence.
        if out and not any(c.isalnum() for c in s):
            out[-1] = out[-1] + s
        else:
            out.append(s)
    return out


# ---------------------------------------------------------------------------
# EPUB rendering
# ---------------------------------------------------------------------------


def esc(text: str) -> str:
    return html.escape(text, quote=True)


def write_epub(root: pathlib.Path, meta: dict, chapters: list[dict]) -> None:
    import shutil

    if root.exists():
        shutil.rmtree(root)
    for d in ("META-INF", "OEBPS/Text", "OEBPS/MediaOverlays", "OEBPS/Audio"):
        (root / d).mkdir(parents=True, exist_ok=True)
    (root / "mimetype").write_text("application/epub+zip")
    (root / "META-INF/container.xml").write_text(
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">\n'
        '  <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>\n'
        "</container>\n"
    )

    manifest, spine, nav_items = [], [], []
    total_seconds = 0.0
    for c in chapters:
        cid = c["id"]
        manifest.append(
            f'    <item id="{cid}" href="Text/{cid}.xhtml" media-type="application/xhtml+xml" media-overlay="{cid}_overlay"/>'
        )
        manifest.append(f'    <item id="{cid}_overlay" href="MediaOverlays/{cid}.smil" media-type="application/smil+xml"/>')
        manifest.append(f'    <item id="{cid}_audio" href="Audio/{cid}.mp4" media-type="audio/mp4"/>')
        spine.append(f'    <itemref idref="{cid}"/>')
        nav_items.append(f'<li><a href="Text/{cid}.xhtml">{esc(" ".join(c["heading"]))}</a></li>')

        body, pars, clock, n = [], [], 0.0, 0
        href = f"../Text/{cid}.xhtml"

        def span(text: str) -> str:
            nonlocal n, clock
            sid = f"{cid}-s{n}"
            n += 1
            duration = len(text.split()) / WORDS_PER_SECOND
            pars.append(
                f'<par id="{sid}" epub:type="storyteller:aligned"><text src="{href}#{sid}"/>'
                f'<audio src="../Audio/{cid}.mp4" clipBegin="{clock:.3f}s" clipEnd="{clock + duration:.3f}s"/></par>'
            )
            clock += duration + SENTENCE_GAP
            return f'<span id="{sid}" epub:type="storyteller:sentence-span">{esc(text)}</span>'

        body.append("<h2>" + " ".join(span(h) for h in c["heading"]) + "</h2>")
        for paragraph in c["paragraphs"]:
            body.append("<p>" + " ".join(span(s) for s in paragraph) + "</p>")
        total_seconds += clock

        (root / f"OEBPS/Text/{cid}.xhtml").write_text(
            '<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE html>\n'
            '<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" '
            'epub:prefix="storyteller: https://storyteller-platform.dev/docs/vocabulary">\n'
            f'<head><meta charset="utf-8"/><title>{esc(" ".join(c["heading"]))}</title></head>\n<body>\n'
            + "\n".join(body)
            + "\n</body>\n</html>\n"
        )
        (root / f"OEBPS/MediaOverlays/{cid}.smil").write_text(
            '<?xml version="1.0" encoding="UTF-8"?>\n'
            '<smil xmlns="http://www.w3.org/ns/SMIL" xmlns:epub="http://www.idpf.org/2007/ops" version="3.0">\n<body>\n'
            f'<seq id="{cid}_overlay" epub:textref="{href}" epub:type="chapter">\n'
            + "\n".join(pars)
            + "\n</seq>\n</body>\n</smil>\n"
        )

    hours, rest = divmod(int(total_seconds), 3600)
    minutes, seconds = divmod(rest, 60)
    (root / "OEBPS/nav.xhtml").write_text(
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><head><title>Contents</title></head>\n'
        '<body><nav epub:type="toc"><ol>' + "".join(nav_items) + "</ol></nav></body></html>\n"
    )
    (root / "OEBPS/content.opf").write_text(
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id" '
        'prefix="storyteller: https://storyteller-platform.dev/docs/vocabulary">\n'
        '  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">\n'
        f'    <dc:identifier id="id">urn:lofi:pg{esc(meta["pg_id"])}</dc:identifier>\n'
        f'    <dc:title>{esc(meta["title"])}</dc:title>\n'
        f'    <dc:creator>{esc(meta["author"])}</dc:creator>\n'
        "    <dc:language>en</dc:language>\n"
        f'    <meta property="media:duration">{hours:02d}:{minutes:02d}:{seconds:02d}</meta>\n'
        "  </metadata>\n  <manifest>\n"
        '    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>\n'
        + "\n".join(manifest)
        + "\n  </manifest>\n  <spine>\n"
        + "\n".join(spine)
        + "\n  </spine>\n</package>\n"
    )


# ---------------------------------------------------------------------------


def build(meta: dict, report_only: bool) -> None:
    slug = meta["slug"]
    raw = (BOOKS / "raw" / f"{slug}.txt").read_text(encoding="utf-8", errors="replace")
    chapters = chapters_of(raw)
    words = [c.words() for c in chapters]
    print(
        f"{slug:28} {len(chapters):3} chapters  {sum(words):7} words  "
        f"min {min(words) if words else 0:5}  first: {' / '.join(chapters[0].heading) if chapters else '-'}"
        f"  last: {' / '.join(chapters[-1].heading) if chapters else '-'}"
    )
    if report_only:
        return
    out = []
    for k, c in enumerate(chapters):
        out.append(
            {
                "id": f"ch{k + 1:03d}",
                "heading": [h for h in c.heading if h],
                "paragraphs": [s for s in (sentences_of(p) for p in c.paragraphs) if s],
            }
        )
    record = {**meta, "chapters": out}
    (BOOKS / "json").mkdir(parents=True, exist_ok=True)
    (BOOKS / "json" / f"{slug}.json").write_text(json.dumps(record, ensure_ascii=False))
    write_epub(BOOKS / "epub" / slug, meta, out)


def main() -> None:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    report_only = "--report" in sys.argv
    with open(HERE / "books.csv", newline="") as f:
        for meta in csv.DictReader(f):
            if args and meta["slug"] not in args:
                continue
            if not (BOOKS / "raw" / f"{meta['slug']}.txt").exists():
                print(f"{meta['slug']}: not fetched", file=sys.stderr)
                continue
            build(meta, report_only)


if __name__ == "__main__":
    main()
