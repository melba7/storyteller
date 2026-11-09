#!/usr/bin/env python3
"""Rename the characters and places in window records, for the name-masking test.

A reader that judges only the passage gives the same mood whether the count is
called Dracula or Varno. A reader leaning on what it remembers about the book
changes its mind more on famous books than on obscure ones; score.py
--masked-pair measures exactly that.

Proper nouns are found per book: capitalised words that appear mid-sentence at
least three times and never in lower case. Each gets a stable invented name.

    python3 -I Tools/eval/mask_names.py windows.jsonl > windows.masked.jsonl
"""
from __future__ import annotations

import collections
import hashlib
import json
import re
import sys

KEEP = {
    "I", "I'm", "I'll", "I've", "I'd", "Mr", "Mrs", "Miss", "Dr", "Sir", "Lady", "Lord", "Madam", "Madame", "God",
    "Heaven", "Christ", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday", "January",
    "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December",
    "English", "England", "London", "French", "Christmas", "O", "Oh", "Professor", "Captain", "Colonel", "Uncle",
    "Aunt", "Mother", "Father", "Count", "King", "Queen", "Prince", "Princess",
}
SYLLABLES = ["va", "ro", "mel", "tor", "an", "is", "bre", "dun", "ka", "sel", "wyn", "or", "the", "lo", "mar", "ith"]
WORD = re.compile(r"\b[A-Z][a-z]+(?:'s)?\b")


def invented(name: str, book: str) -> str:
    h = hashlib.sha256(f"{book}:{name}".encode()).digest()
    parts = [SYLLABLES[h[i] % len(SYLLABLES)] for i in range(2 + h[5] % 2)]
    return "".join(parts).capitalize()


def proper_nouns(texts: list[str]) -> set[str]:
    capital, lower = collections.Counter(), set()
    for text in texts:
        for sentence in re.split(r"(?<=[.!?”\"])\s+", text):
            words = sentence.split()
            for k, w in enumerate(words):
                core = w.strip(".,;:!?\"'()“”‘’—-")
                if core.endswith("'s"):
                    core = core[:-2]
                if not core.isalpha():
                    continue
                if core[0].islower():
                    lower.add(core.lower())
                elif k > 0 and core[0].isupper() and not core.isupper():
                    capital[core] += 1
    return {w for w, c in capital.items() if c >= 3 and w.lower() not in lower and w not in KEEP}


def main() -> None:
    rows = [json.loads(line) for line in open(sys.argv[1]) if line.strip()]
    by_book = collections.defaultdict(list)
    for r in rows:
        by_book[r["book"]].append(r)
    for book, records in by_book.items():
        names = proper_nouns([r["text"] for r in records])
        mapping = {n: invented(n, book) for n in names}

        def swap(text: str) -> str:
            return WORD.sub(lambda m: mapping.get(m.group(0).removesuffix("'s"), m.group(0).removesuffix("'s"))
                            + ("'s" if m.group(0).endswith("'s") else ""), text)

        for r in records:
            r["chapters"] = [[swap(s) for s in chapter] for chapter in r["chapters"]]
            r["text"] = swap(r["text"])
            r["masked"] = True
        print(f"{book}: masked {len(mapping)} names", file=sys.stderr)
    for r in rows:
        print(json.dumps(r, ensure_ascii=False, sort_keys=True))


if __name__ == "__main__":
    main()
