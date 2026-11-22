"""Reads a podcast feed for the teaching run: turns its bytes into an XML tree (strictly first,
then once more after cleaning the usual mistakes) and picks the newest episodes with audio.

Standard library only. No network and no files: teach_fetch.py gets the bytes, teach_collect.py
uses the episodes.

Run the tests: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import codecs
import hashlib
import os
import re
import xml.etree.ElementTree as ET
from email.utils import parsedate_to_datetime
from urllib.parse import urlparse

from teach_store import AUDIO_EXTENSIONS

ITUNES = "{http://www.itunes.com/dtds/podcast-1.0.dtd}"
# What an enclosure's type says when its address does not show the kind of audio.
AUDIO_TYPES = {"audio/mpeg": "mp3", "audio/mp4": "m4a", "audio/x-m4a": "m4a", "audio/aac": "aac",
               "audio/ogg": "ogg", "audio/opus": "opus", "audio/wav": "wav", "audio/x-wav": "wav"}
# Characters XML 1.0 does not allow: control characters other than tab, newline and carriage return.
FORBIDDEN = re.compile("[\x00-\x08\x0b\x0c\x0e-\x1f￾￿]")
# An & that does not start one of the five named entities or a number reference.
BARE_AMPERSAND = re.compile(r"&(?!(?:amp|lt|gt|quot|apos|#[0-9]+|#x[0-9A-Fa-f]+);)")
NUMBER_REFERENCE = re.compile(r"&#(?:([0-9]+)|x([0-9A-Fa-f]+));")
DECLARED_ENCODING = re.compile(rb"^\s*<\?xml[^>]*?encoding\s*=\s*[\"']([A-Za-z0-9._-]+)[\"']")


FEED_SCHEME = re.compile(r"^(?:[a-z][a-z0-9+.-]*:)?//([^/?]*)(.*)$", re.IGNORECASE)
TRAILING_SLASHES = re.compile(r"/+(?=\?|\Z)")


def feed_key(address):
    """One key for every spelling of a feed address: no scheme, no `www.`, the host in lower case,
    no fragment and no closing slash. The path and query keep their case. It is the same key as
    `feedKey` in applePodcasts.ts and FeedKey.swift, so the phone and the Mac meet through it."""
    text = address.strip()
    if "#" in text:
        text = text[:text.index("#")]
    found = FEED_SCHEME.match(text)
    if found:
        host, rest = found.group(1), found.group(2)
    else:
        host = re.split(r"[/?]", text)[0]
        rest = text[len(host):]
    host = host.lower()
    if host.startswith("www."):
        host = host[4:]
    return host + TRAILING_SLASHES.sub("", rest, count=1)


def is_web_address(address):
    """True for an address that starts with http:// or https:// (in any case) and names a host.
    Anything else (file:, ftp:, feed:, no scheme) is not fetched."""
    found = re.match(r"^https?://([^/?#\s]+)", address, re.IGNORECASE) if isinstance(address, str) else None
    return bool(found)


class FeedError(ValueError):
    """The feed is not XML, even after cleaning."""


# MARK: Parsing

def allowed_character(number):
    return number in (9, 10, 13) or 0x20 <= number <= 0xD7FF or 0xE000 <= number <= 0xFFFD \
        or 0x10000 <= number <= 0x10FFFF


def strict_input(data):
    """The feed as text or bytes ready for the XML parser: without a byte order mark or white space
    in front (either makes the parser refuse the XML declaration). UTF-16 is turned into text."""
    if isinstance(data, str):
        return data.lstrip("﻿").lstrip()
    if data.startswith((codecs.BOM_UTF16_LE, codecs.BOM_UTF16_BE)):
        return data.decode("utf-16", errors="replace").lstrip()
    if data.startswith(codecs.BOM_UTF8):
        data = data[len(codecs.BOM_UTF8):]
    return data.lstrip()


def cleaned_text(data):
    """The feed as text with the characters and ampersands XML does not allow taken out or fixed."""
    if isinstance(data, str):
        text = data
    else:
        found = DECLARED_ENCODING.match(data[:300].lstrip(codecs.BOM_UTF8))
        encoding = "utf-8"
        if found:
            try:
                encoding = codecs.lookup(found.group(1).decode("ascii")).name
            except LookupError:
                pass
        if data.startswith((codecs.BOM_UTF16_LE, codecs.BOM_UTF16_BE)):
            encoding = "utf-16"
        text = data.decode(encoding, errors="replace")

    def reference(match):
        number = int(match.group(1)) if match.group(1) else int(match.group(2), 16)
        return match.group(0) if allowed_character(number) else ""

    text = FORBIDDEN.sub("", text.lstrip("﻿").lstrip())
    return NUMBER_REFERENCE.sub(reference, BARE_AMPERSAND.sub("&amp;", text))


def parse_feed(data):
    """The root of the feed's XML. Parses strictly first; when that fails, once more after
    removing control characters and turning every & that starts no valid entity into &amp;. Raises
    FeedError, naming the first problem, when both fail."""
    try:
        return ET.fromstring(strict_input(data))
    except ET.ParseError as first:
        try:
            return ET.fromstring(cleaned_text(data))
        except ET.ParseError:
            raise FeedError("it is not valid XML: %s" % first)


# MARK: Episodes

def episode_id(feed, guid, address):
    """The first 12 hex digits of the sha1 of the feed and the item's guid (or its address)."""
    return hashlib.sha1((feed + "\n" + (guid or address)).encode("utf-8")).hexdigest()[:12]


def parse_duration(text):
    """Seconds from itunes:duration written as H:MM:SS, MM:SS or plain seconds; None otherwise."""
    parts = (text or "").strip().split(":")
    if not 1 <= len(parts) <= 3 or not all(part.isdigit() and part.isascii() for part in parts):
        return None
    seconds = 0
    for part in parts:
        seconds = seconds * 60 + int(part)
    return seconds


def feed_episodes(data, count):
    """The newest `count` items of an RSS feed (bytes or text) that have audio, newest first, as
    dicts with guid, title, published, seconds, address, size and type (the enclosure's, in lower
    case). Items are ordered by pubDate; items without a date come after the dated ones, in the
    order of the feed (first is newest). Only http and https addresses, no video, each address
    once. Raises FeedError when the feed cannot be read as XML."""
    root = parse_feed(data)
    items = []
    for position, item in enumerate(root.iter("item")):
        enclosure = item.find("enclosure")
        url = (enclosure.get("url") or "").strip() if enclosure is not None else ""
        if not url.startswith(("http://", "https://")):
            continue
        kind = (enclosure.get("type") or "").strip().lower()
        if kind.startswith("video/"):
            continue
        published = None
        date = item.findtext("pubDate")
        if date:
            try:
                published = int(parsedate_to_datetime(date.strip()).timestamp())
            except (TypeError, ValueError):
                pass
        length = (enclosure.get("length") or "").strip()
        size = int(length) if length.isdigit() and length.isascii() and int(length) > 0 else None
        items.append(((float("-inf") if published is None else published, -position), {
            "guid": (item.findtext("guid") or "").strip(), "title": (item.findtext("title") or "").strip(),
            "published": published, "seconds": parse_duration(item.findtext(ITUNES + "duration")),
            "address": url, "size": size, "type": kind}))
    items.sort(key=lambda entry: entry[0], reverse=True)
    found, seen = [], set()
    for _, episode in items:
        if episode["address"] not in seen:
            seen.add(episode["address"])
            found.append(episode)
        if len(found) == count:
            break
    return found


def audio_name(identifier, address, kind=None):
    """audio/<id>.<ext>. The extension comes from the address's path when it is a known audio
    type, otherwise from the enclosure's type (`kind`), otherwise it is mp3."""
    ext = os.path.splitext(urlparse(address).path)[1].lstrip(".").lower()
    if ext not in AUDIO_EXTENSIONS:
        ext = AUDIO_TYPES.get((kind or "").split(";")[0].strip().lower(), "mp3")
    return "audio/%s.%s" % (identifier, ext)


def feed_title(data):
    """The title of the show a feed is for, "" when it has none. Raises FeedError when the feed
    cannot be read as XML."""
    channel = parse_feed(data).find("channel")
    return (channel.findtext("title") or "").strip() if channel is not None else ""
