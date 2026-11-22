"""The teaching run's network code: one opener (that also follows HTTP 308), the feed fetch and the
download of a whole audio file.

Standard library only. Nothing is sent anywhere but the feeds' and audio files' own hosts. Both
ask for `Accept-Encoding: identity`, so files arrive as they are, and both open an address after
percent-quoting its path and query, so addresses with spaces or non-ASCII characters work.

Run the tests: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import hashlib
import os
import re
import time
import urllib.parse
import urllib.request
import zlib

import probe_shows as probe
from teach_feed import is_web_address

FEED_LIMIT = 64_000_000
MAX_FILE = 600_000_000
READ_TIMEOUT = 30
DOWNLOAD_SECONDS = 20 * 60
CHUNK = 65536
_opener = None


class TooLarge(ValueError):
    """The file is bigger than the limit."""


class RedirectHandler(urllib.request.HTTPRedirectHandler):
    """Python 3.9 does not follow HTTP 308 (permanent redirect, method kept); this treats it like 307."""

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        if not is_web_address(newurl):
            return None  # never follow a redirect to file:, ftp: and the like
        return super().redirect_request(req, fp, 307 if code == 308 else code, msg, headers, newurl)

    http_error_308 = urllib.request.HTTPRedirectHandler.http_error_302


def opener():
    """The one opener for feeds and downloads."""
    global _opener
    if _opener is None:
        _opener = urllib.request.build_opener(RedirectHandler)
    return _opener


def quote_address(address):
    """The address with its path and query percent-quoted (and a non-ASCII host name in its ASCII
    form), the fragment dropped. Characters that are already quoted are left as they are."""
    parts = urllib.parse.urlsplit(address.strip())
    host = parts.netloc
    if not host.isascii():
        login, at, hostport = host.rpartition("@")
        name, colon, port = hostport.partition(":")
        host = login + at + name.encode("idna").decode("ascii") + colon + port

    def quoted(text, safe):
        return urllib.parse.quote(re.sub(r"%(?![0-9A-Fa-f]{2})", "%25", text), safe=safe)

    return urllib.parse.urlunsplit((parts.scheme, host, quoted(parts.path, "/%:@!$&'()*+,;=~-._"),
                                    quoted(parts.query, "/%:@!$&'()*+,;=?~-._"), ""))


def make_request(address):
    """The request for an address. Only http and https addresses are fetched: anything else (file:,
    ftp:, data: and so on) raises ValueError."""
    if not is_web_address(address):
        raise ValueError("%s is not an http or https address, so it is not fetched" % address[:80])
    return urllib.request.Request(quote_address(address), headers={
        "User-Agent": probe.USER_AGENT, "Accept-Encoding": "identity"})


def promised_length(headers):
    """The Content-Length of an answer as a number, or None when it has none or the body is
    encoded (then the length is not the length of what is read)."""
    length = (headers.get("Content-Length") or "").strip()
    encoding = (headers.get("Content-Encoding") or "").strip().lower()
    return int(length) if length.isdigit() and length.isascii() and encoding in ("", "identity") else None


# MARK: Feeds

def gunzip(body, limit):
    unpacker = zlib.decompressobj(16 + zlib.MAX_WBITS)
    try:
        data = unpacker.decompress(body, limit + 1)
    except zlib.error as error:
        raise ValueError("the feed's gzip data is damaged (%s)" % error)
    if len(data) > limit:
        raise ValueError("the feed is bigger than %d MB" % (limit // 1_000_000))
    if not unpacker.eof:
        raise ValueError("the feed's gzip data is cut short")
    return data


def fetch_feed(address, open_url=None, limit=FEED_LIMIT):
    """The bytes of a feed. Raises ValueError when it is bigger than `limit` (or cut short by the
    server), and OSError when it cannot be read. A gzip answer (by Content-Encoding or because it
    starts with the gzip bytes) is unpacked."""
    with (open_url or opener().open)(make_request(address), timeout=probe.FEED_TIMEOUT) as response:
        body = response.read(limit + 1)
        expected = promised_length(response.headers)
        encoding = (response.headers.get("Content-Encoding") or "").strip().lower()
    if len(body) > limit:
        raise ValueError("the feed is bigger than %d MB" % (limit // 1_000_000))
    if expected is not None and len(body) < expected:
        raise OSError("the server stopped early: %d of %d bytes of the feed" % (len(body), expected))
    if encoding in ("gzip", "x-gzip") or body[:2] == b"\x1f\x8b":
        body = gunzip(body, limit)
    return body


# MARK: Download

def download(address, path, open_url=None, max_bytes=MAX_FILE, max_seconds=DOWNLOAD_SECONDS,
             clock=time.monotonic, chunk=CHUNK):
    """Saves a whole file to `path` (through `path`.part, renamed at the end) and returns
    {"bytes", "sha256", "host"}, the host being the one after redirects. Raises, with the .part
    removed: TooLarge when the file is, or says it is, bigger than `max_bytes`; ValueError when it
    is empty or an answer of type text/ (an error page); OSError when the server closed early
    (fewer bytes than its Content-Length) or the network failed; TimeoutError when it takes longer
    than `max_seconds`.

    It never resumes a half-finished file: hosts that insert ads can send a different file on
    every request, so the start of one answer must not be glued to the rest of another. A new try
    starts from zero."""
    part = path + ".part"
    deadline = clock() + max_seconds
    digest = hashlib.sha256()
    kept = 0
    try:
        with (open_url or opener().open)(make_request(address), timeout=READ_TIMEOUT) as response:
            if (response.headers.get("Content-Type") or "").strip().lower().startswith("text/"):
                raise ValueError("the server answered with a text page, not audio")
            expected = promised_length(response.headers)
            if expected is not None and expected > max_bytes:
                raise TooLarge("the file is bigger than %d MB" % (max_bytes // 1_000_000))
            host = probe.host_of(response.geturl())
            with open(part, "wb") as handle:
                while True:
                    if clock() > deadline:
                        raise TimeoutError("took more than %d minutes" % (max_seconds // 60))
                    block = response.read(chunk)
                    if not block:
                        break
                    kept += len(block)
                    if kept > max_bytes:
                        raise TooLarge("the file is bigger than %d MB" % (max_bytes // 1_000_000))
                    digest.update(block)
                    handle.write(block)
        if kept == 0:
            raise ValueError("the file is empty")
        if expected is not None and kept < expected:
            raise OSError("the server stopped early: %d of %d bytes" % (kept, expected))
        os.replace(part, path)
    except BaseException:
        if os.path.exists(part):
            os.remove(part)
        raise
    return {"bytes": kept, "sha256": digest.hexdigest(), "host": host}
