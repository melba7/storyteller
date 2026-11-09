#!/usr/bin/env python3
"""Download the curated public-domain books from the PG-19 mirror.

PG-19 (DeepMind) is a cleaned copy of Project Gutenberg books published
before 1919, served from Google Cloud Storage. Files land in
Tools/data/books/raw/<slug>.txt, which is git-ignored.

    python3 -I Tools/data/fetch_books.py            # all books in books.csv
    python3 -I Tools/data/fetch_books.py dracula    # just one
"""
import csv
import pathlib
import sys
import urllib.error
import urllib.request

HERE = pathlib.Path(__file__).resolve().parent
MIRROR = "https://storage.googleapis.com/deepmind-gutenberg"
SPLITS = ("train", "validation", "test")


def fetch(pg_id: str) -> bytes:
    for split in SPLITS:
        try:
            with urllib.request.urlopen(f"{MIRROR}/{split}/{pg_id}.txt", timeout=60) as r:
                return r.read()
        except urllib.error.HTTPError as e:
            if e.code != 404:
                raise
    raise FileNotFoundError(f"PG-19 has no book {pg_id}")


def main() -> None:
    wanted = set(sys.argv[1:])
    out = HERE / "books" / "raw"
    out.mkdir(parents=True, exist_ok=True)
    with open(HERE / "books.csv", newline="") as f:
        for row in csv.DictReader(f):
            if wanted and row["slug"] not in wanted:
                continue
            path = out / f"{row['slug']}.txt"
            if path.exists():
                continue
            try:
                path.write_bytes(fetch(row["pg_id"]))
                print(f"fetched {row['slug']} ({path.stat().st_size // 1024} KB)")
            except Exception as e:  # keep going; report at the end
                print(f"FAILED {row['slug']}: {e}", file=sys.stderr)


if __name__ == "__main__":
    main()
