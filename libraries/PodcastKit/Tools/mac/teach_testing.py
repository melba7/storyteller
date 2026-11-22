"""Helpers the tests of the teaching tools share: feeds, fake answers from a server, full episode
entries, fake `claude` runs and a temporary teaching folder. Not a test itself.

Run the tests: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import io
import json
import os
import shutil
import subprocess
import tempfile
from types import SimpleNamespace

import teach_store as store

ITUNES = 'xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd"'


# MARK: Feeds and servers

def feed(*items):
    """A feed with items given as dicts: title, date, address, guid, duration, length, type."""
    body = ""
    for item in items:
        body += "<item><title>%s</title>" % item.get("title", "")
        if item.get("guid"):
            body += "<guid>%s</guid>" % item["guid"]
        if item.get("date"):
            body += "<pubDate>%s</pubDate>" % item["date"]
        if item.get("duration"):
            body += "<itunes:duration>%s</itunes:duration>" % item["duration"]
        if item.get("address"):
            body += '<enclosure url="%s" type="%s" length="%s"/>' % (
                item["address"], item.get("type", "audio/mpeg"), item.get("length", ""))
        body += "</item>"
    return '<?xml version="1.0"?><rss %s><channel><title>Show</title>%s</channel></rss>' % (ITUNES, body)


def dated(title, day, address, **more):
    return dict(title=title, date="Mon, %02d Jan 2024 10:00:00 +0000" % day, address=address, **more)


class FakeResponse(io.BytesIO):
    """What urlopen gives back: a body, headers, the final address."""

    def __init__(self, data, content_type="audio/mpeg", url="https://cdn.example.com/a.mp3", **headers):
        super().__init__(data)
        self.headers = {"Content-Type": content_type}
        self.headers.update(headers)
        self._url = url

    def geturl(self):
        return self._url


class ShortResponse(FakeResponse):
    """A server that promises `promised` bytes and closes early: reads give what there is, then
    nothing, without an error."""

    def __init__(self, data, promised, **more):
        super().__init__(data, **{"Content-Length": str(promised)}, **more)


def opener(data, **more):
    """An open_url that answers every request with `data` and remembers the request."""
    seen = {}

    def open_url(request, timeout=None):
        seen["request"] = request
        seen["timeout"] = timeout
        return FakeResponse(data, **more)
    open_url.seen = seen
    return open_url


# MARK: Episodes and folders

def entry(number, audio=False, **more):
    """A full, valid entry of episodes.json."""
    identifier = "%012x" % number
    value = {"id": identifier, "feed": "https://feed/%d" % number, "show": "Show",
             "guid": "", "title": "Episode %d" % number, "published": None, "seconds": None,
             "address": "https://a/%d.mp3" % number, "size": None,
             "file": "audio/%s.mp3" % identifier if audio else None, "bytes": 1000 if audio else 0,
             "sha256": None, "host": None, "error": None}
    value.update(more)
    return value


class Folder:
    """A temporary teaching folder that goes when the test ends."""

    def __init__(self, test):
        self.dir = tempfile.mkdtemp()
        test.addCleanup(lambda: shutil.rmtree(self.dir, ignore_errors=True))

    def write_manifest(self, entries):
        store.save_manifest(self.dir, entries)

    def path(self, *names):
        return os.path.join(self.dir, *names)


# MARK: Claude

def printed(result="ok", cost=0.25, is_error=False):
    return json.dumps({"type": "result", "is_error": is_error, "result": result,
                       "total_cost_usd": cost})


class FakeRunner:
    """Stands in for subprocess.run: records each call and returns the given output."""

    def __init__(self, stdout="", stderr="", returncode=0, raises=None):
        self.stdout, self.stderr, self.returncode, self.raises = stdout, stderr, returncode, raises
        self.calls = []
        self.folder_was_empty = None

    def __call__(self, args, **kwargs):
        self.calls.append((args, kwargs))
        self.folder_was_empty = os.listdir(kwargs["cwd"]) == []
        if self.raises:
            raise self.raises
        return SimpleNamespace(returncode=self.returncode, stdout=self.stdout, stderr=self.stderr)


def answer(*spans, sort="sponsor", who="Acme"):
    """Claude's answer text for (first, last) spans."""
    return json.dumps({"segments": [
        {"first": a, "last": b, "sort": sort, "who": who, "delivery": "host",
         "confidence": "high", "why": "x"} for a, b in spans]})


def transcript(count, start=0.0):
    return "".join("[00:%02d:%04.1f] line %d\n" % ((start + n) // 60, (start + n) % 60, n + 1)
                   for n in range(count))


class Teaching(Folder):
    """A teaching folder with `count` episodes that each have a transcript."""

    def __init__(self, test, count, with_transcripts=None):
        super().__init__(test)
        self.entries = [entry(n) for n in range(1, count + 1)]
        self.write_manifest(self.entries)
        os.makedirs(self.path("transcripts"))
        for item in self.entries:
            self.write_transcript(item, transcript(10) if with_transcripts is None else with_transcripts)

    def write_transcript(self, item, text):
        with open(self.path("transcripts", item["id"] + ".txt"), "w") as f:
            f.write(text)

    def label_path(self, item, labels="labels"):
        return self.path(labels, item["id"] + ".json")

    def labels(self, labels="labels"):
        folder = self.path(labels)
        return sorted(os.listdir(folder)) if os.path.isdir(folder) else []

    def failures(self):
        with open(self.path("failures.json"), encoding="utf-8") as f:
            return json.load(f)


def timeout(command=("claude",), seconds=900):
    return subprocess.TimeoutExpired(list(command), seconds)
