"""The work on one episode for teach_copies.py: asking for the second copy, running the Swift tool
on the two files, reading what it says, and the memory of which episodes failed.

Standard library only. Nothing is sent anywhere but the episode's own audio address, and what is
sent is what teach_fetch sends (a User-Agent and Accept-Encoding) with the second listener's name
as the User-Agent.

Run the tests: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import json
import os
import subprocess

import teach_fetch as fetching
from teach_store import write_json
from teach_truth import COPIES, read_truth

SECOND_AGENT = "StorytellerLofi-probe/1.0 (second listener)"
TIMEOUT = 10 * 60
TAIL_LINES = 5
SAME_FILE = ("# Ads marked from the differences between two downloads of one episode.\n"
             "# Both downloads were the same file, so no stretch differs and nothing can be learned.\n")


class Failures:
    """copies/failed.json: how many times each episode's second copy failed."""

    def __init__(self, copies):
        self.path = os.path.join(copies, "failed.json")
        self.counts = {}
        try:
            with open(self.path, encoding="utf-8") as handle:
                found = json.load(handle)
        except (OSError, ValueError):
            return  # no file, or a damaged one: start with an empty memory
        if isinstance(found, dict) and isinstance(found.get("failed"), dict):
            self.counts = {key: value for key, value in found["failed"].items()
                           if isinstance(value, int) and not isinstance(value, bool) and value > 0}

    def count(self, identifier):
        return self.counts.get(identifier, 0)

    def failed(self, identifier):
        self.counts[identifier] = self.count(identifier) + 1
        write_json(self.path, {"version": 1, "failed": self.counts})

    def succeeded(self, identifier):
        if self.counts.pop(identifier, None) is not None:
            write_json(self.path, {"version": 1, "failed": self.counts})


def plural(number, one, many):
    return "%d %s" % (number, one if number == 1 else many)


def as_second_listener(open_url=None):
    """An `open_url` for teach_fetch.download that asks with the second listener's name and nothing
    else added: the request keeps the two headers teach_fetch gives it."""
    def open_second(request, timeout=None):
        request.add_header("User-Agent", SECOND_AGENT)
        return (open_url or fetching.opener().open)(request, timeout=timeout)
    return open_second


def read_answer(done):
    """What the tool's run means: {"kind", "text", "stretches"} with kind "found" (stretches
    differ), "agree" (none do) or "no_frame" (the files share no frame, so the host makes a new
    file for every download). Raises RuntimeError, with the last lines the tool said, when the run
    failed. The Swift tool exits with 1 and prints only notes when no stretch differs."""
    text = done.stdout or ""
    try:
        stretches = read_truth(text)
    except ValueError as error:
        raise RuntimeError("the tool printed something that is not a list of stretches (%s)" % error)
    if stretches and done.returncode == 0:
        return {"kind": "found", "text": text, "stretches": stretches}
    if not stretches and done.returncode in (0, 1) and text.strip():
        return {"kind": "no_frame" if "no frame in common" in text else "agree", "text": text,
                "stretches": []}
    said = (done.stderr or "").replace("\r", "\n").splitlines()
    tail = " / ".join([line.strip() for line in said if line.strip()][-TAIL_LINES:])
    raise RuntimeError("%s%s" % ("the tool stopped with code %d" % done.returncode if done.returncode
                                 else "the tool printed no stretch", ": " + tail if tail else ""))


def compare(entry, folder, tool, download, open_url, runner, max_bytes):
    """Downloads the second copy of an episode and runs the tool on the two files. Returns what
    read_answer gives (kind "same" when both downloads were the same file, which needs no tool) and
    "bytes", what was downloaded. The second copy, the link to the audio and the tool's own file
    are gone when this ends, however it ends."""
    copies = os.path.join(folder, COPIES)
    second = os.path.join(copies, entry["id"] + ".second.mp3")
    link = os.path.join(copies, entry["id"] + ".first.mp3")
    try:
        try:
            info = download(entry["address"], second, open_url=as_second_listener(open_url),
                            max_bytes=max_bytes)
        except fetching.TooLarge:
            raise
        except Exception as error:
            raise RuntimeError("did not download: %s" % (str(error) or error.__class__.__name__))
        if entry["sha256"] and info["sha256"] == entry["sha256"]:
            return {"kind": "same", "text": SAME_FILE, "stretches": [], "bytes": info["bytes"]}
        os.symlink(os.path.abspath(os.path.join(folder, entry["file"])), link)
        try:
            done = runner([tool, "--truth-from-copies", link, second], stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, text=True, timeout=TIMEOUT)
        except subprocess.TimeoutExpired:
            raise RuntimeError("the tool took more than %d minutes" % (TIMEOUT // 60))
        except OSError as error:
            raise RuntimeError("could not run %s: %s" % (tool, error))
        return dict(read_answer(done), bytes=info["bytes"])
    finally:
        for path in (second, second + ".part", link, link + ".truth.txt"):
            try:
                os.remove(path)
            except OSError:
                pass


def tell(outcome, say):
    kind = outcome["kind"]
    if kind == "found":
        seconds = sum(end - start for start, end in outcome["stretches"])
        say("  %s differ, %.0f s in all." % (plural(len(outcome["stretches"]), "stretch", "stretches"), seconds))
    elif kind == "same":
        say("  both downloads were the same file, so nothing is learned from this episode.")
    elif kind == "no_frame":
        say("  the two downloads have no frame in common (the host makes a new file for every "
            "download), so nothing can be compared.")
    else:
        say("  both downloads got the same ads, so nothing is learned from this episode.")
