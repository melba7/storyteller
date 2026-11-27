#!/usr/bin/env python3
"""Copies the results of the teaching run to the folders the phone reads.

Standard library only. For each destination folder it writes, into the same Podcasts subfolder
that apple_podcasts_export.py uses (<folder>/Podcasts):

  ad-model.json    from <folder>/ad-model.json    (teach_train.py)
  ad-library.json  from <folder>/ad-library.json  (teach_library.py)
  show-habits.json from <folder>/habits.json      (teach_habits.py)
  ad-sounds.json   from <folder>/ad-sounds.json   (podcast-teach sounds)
  ad-meaning.json  from <folder>/ad-meaning.json  (podcast-teach meaning), see the gate below
  show-settings.json from <folder>/show-settings.json (teach_settings.py)
  ahead-ads.json   from <folder>/ahead-ads.json   (teach_ahead.py write, the nightly read-ahead:
                   where the ads are in the episodes it marked, told in words). It has no gate: it
                   has to be a version 1 file with a list of episodes, within the size limit.
  ad-cues.json     from <folder>/ad-cues.json     (teach_cues.py: the lines that open an ad and the
                   lines that come back after one, in words of transcripts). It has no gate: it has
                   to be a version 1 file with the lists starts, returns, shows, common and usual,
                   within the size limit. Like ahead-ads.json it is listed in teaching.json, and
                   its absence is quiet.
  teaching.json    a small list of the files above that are in the Podcasts folder now,
                   each with its sha256 and size, so the phone fetches a big file only when its
                   hash changed. It is rewritten only when that list changes.

  teach_publish.py [--folder F] [--to FOLDER ...] [--min-precision 0.85]

A model the phone would refuse (see teach_phone_rule.py) is not published either. A weak model is
not published: ad-model.json is copied only when its check on the held-out shelf
rests on at least 5 episodes from at least 3 shows and 600 seconds of predicted ads, and
trained.heldOut.anyAd.precision (in seconds of the spans the phone would cut) is at least
--min-precision. Otherwise the tool says which bar was missed and with what numbers, leaves a model
that is already at the destination alone and still publishes the other files (this is not a
failure).

ad-meaning.json passes that same check on held-out episodes AND a second one on scorecard.json
(teach_publish_gates.py): the row "Plus the meaning model" must add right seconds for host_ask or
network_promo over the row before it, with a precision of at least --min-precision, in a scorecard
that is not older than the model. With no scorecard or no such row it is not published. The reason is
said in one line and a copy already at the destination is left alone. show-settings.json has no gate:
it only has to be a version 1 file with a list of shows, as the phone needs.

Without --to the destinations are the ones apple_podcasts_export.py writes to: the LofiMusic
folder under ~/Storyteller Lofi and its copy in iCloud Drive. A source that does not exist is
skipped. A source is checked before it is copied: it must be JSON, an object with "version": 1
(the word model, ad-model.json, may also be "version": 2) and at
most 4.5 MB (the phone refuses files over 5 MB). A file is written through a temporary file in
the same folder, and only when its content differs from what is there. A destination folder that
does not exist or cannot be written is reported and the others are still tried.

Exit code: 0 every existing source reached every destination folder that exists (also when there
was nothing to publish), 2 a source reached no folder or not the first one, or the arguments are
wrong, 3 the first folder was written but a later folder that exists (the iCloud copy, which is the
one the phone reads) could not be written. The last lines then say which copy failed.

Run the tests: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import argparse
import hashlib
import json
import os
import sys
import tempfile
import time

import teach_store
from teach_phone_rule import refusals
from teach_publish_gates import ahead_shape, cues_shape, percent, scorecard_reason, settings_shape
from apple_podcasts_export import default_folders

LIMIT = 4500000
SUBFOLDER = "Podcasts"
FILES = (("ad-model.json", "ad-model.json"), ("ad-library.json", "ad-library.json"),
         ("habits.json", "show-habits.json"), ("ad-sounds.json", "ad-sounds.json"),
         ("ad-meaning.json", "ad-meaning.json"), ("show-settings.json", "show-settings.json"))
# The nightly read-ahead's file. It goes where the others go and into teaching.json, but it exists
# only when the nightly read-ahead is on, so it is kept apart from FILES: its absence is quiet.
AHEAD = ("ahead-ads.json", "ahead-ads.json")
# The opening and return lines. Same treatment: kept apart, quiet when it is not there yet.
CUES = ("ad-cues.json", "ad-cues.json")
OPTIONAL = (AHEAD, CUES)
MODEL = "ad-model.json"
MEANING = "ad-meaning.json"
SETTINGS = "show-settings.json"
LIST = "teaching.json"
MIN_PRECISION = 0.85
ICLOUD_FAILED = 3
MIN_EPISODES = 5
MIN_SHOWS = 3
MIN_AD_SECONDS = 600


def checked(path, limit=LIMIT, versions=(1,)):
    """The bytes of a source that is fit to publish. Raises ValueError (with the reason in plain
    words) when it is too large, not JSON or not an object of one of `versions` (the word model may
    be version 1 or 2, every other file is version 1), and OSError when it cannot be read."""
    size = os.path.getsize(path)
    if size > limit:
        raise ValueError("it is too large (%d bytes, the most is %d)" % (size, limit))
    with open(path, "rb") as f:
        data = f.read()
    try:
        value = json.loads(data)
    except ValueError:
        raise ValueError("it is not JSON")
    if not isinstance(value, dict) or type(value.get("version")) is not int \
            or value["version"] not in versions:
        raise ValueError("it is not an object with \"version\": %s"
                         % " or ".join(str(v) for v in versions))
    return data


def held_out(data, *keys):
    """The value at trained.heldOut.<keys> in a model's JSON bytes, or None when it is missing."""
    value = json.loads(data)
    for key in ("trained", "heldOut") + keys:
        value = value.get(key) if isinstance(value, dict) else None
    return value


def number_of(value):
    return value if isinstance(value, (int, float)) and not isinstance(value, bool) else None


def precision_of(data):
    """The number at trained.heldOut.anyAd.precision in a model's JSON bytes, or None when it is
    missing, null or not a number."""
    return number_of(held_out(data, "anyAd", "precision"))


def check_reasons(data, minimum):
    """The reasons the check on held-out episodes in a model's JSON bytes is not good enough, as a
    list (empty when it is). It must rest on enough held-out episodes, shows and predicted ad
    seconds, and its precision (in seconds of the spans the phone would cut) must reach `minimum`."""
    reasons = []
    episodes = number_of(held_out(data, "episodes")) or 0
    shows = number_of(held_out(data, "shows")) or 0
    seconds = number_of(held_out(data, "predictedAdSeconds")) or 0
    if episodes < MIN_EPISODES or shows < MIN_SHOWS:
        reasons.append("its check needs %d held-out episodes from %d shows and has %d from %d"
                       % (MIN_EPISODES, MIN_SHOWS, episodes, shows))
    if seconds < MIN_AD_SECONDS:
        reasons.append("its check needs %d seconds of predicted ads and has %d"
                       % (MIN_AD_SECONDS, seconds))
    precision = precision_of(data)
    if precision is None:
        reasons.append("it has no precision number from the check on held-out episodes (%s is "
                       "needed)" % percent(minimum))
    elif precision < minimum:
        reasons.append("it found ads with a precision of %s, and %s is needed"
                       % (percent(precision), percent(minimum)))
    return reasons


def weak_model(data, minimum):
    """A sentence saying why the model is not good enough to publish, or None when it is: the phone
    would refuse the file, or its check on held-out episodes is not good enough."""
    reasons = []
    try:
        refused = refusals(json.loads(data))
    except ValueError:
        refused = ["it is not JSON"]
    if refused:
        reasons.append("the phone would refuse the file, because " + "; and ".join(refused))
    return "; ".join(reasons + check_reasons(data, minimum)) or None


def weak_meaning(data, folder, minimum):
    """The same for the meaning model: the check on held-out episodes of the word model's gate, and
    what the scorecard in `folder` says (teach_publish_gates.py). Both reasons are said at once."""
    reasons = check_reasons(data, minimum)
    reason = scorecard_reason(folder, data, minimum)
    return "; ".join(reasons + ([reason] if reason else [])) or None


def write_atomically(path, data):
    """Writes `data` to `path` through a temporary file in the same folder, forced to disk before it
    replaces the old file."""
    handle, temporary = tempfile.mkstemp(dir=os.path.dirname(path), prefix=".", suffix=".tmp")
    try:
        with os.fdopen(handle, "wb") as f:
            f.write(data)
            f.flush()
            os.fsync(f.fileno())
        os.replace(temporary, path)
    except BaseException:
        if os.path.exists(temporary):
            os.remove(temporary)
        raise


def put(folder, name, data, writer):
    """Puts `data` at <folder>/Podcasts/<name>: "written" or "unchanged". Raises OSError."""
    if not os.path.isdir(folder):
        raise OSError("the folder does not exist")
    directory = os.path.join(folder, SUBFOLDER)
    path = os.path.join(directory, name)
    try:
        with open(path, "rb") as f:
            if f.read() == data:
                return "unchanged"
    except OSError:
        pass
    os.makedirs(directory, exist_ok=True)
    writer(path, data)
    return "written"


def share(value):
    try:
        number = float(value)
    except ValueError:
        raise argparse.ArgumentTypeError("%r is not a number" % value)
    if not 0 <= number <= 1:
        raise argparse.ArgumentTypeError("%r is not between 0 and 1" % value)
    return number


def update_list(destination, writer, now):
    """Writes <destination>/Podcasts/teaching.json for the teaching files that are in that folder
    now, hashed as they are on disk: "written", "unchanged", or None when the destination has no
    Podcasts folder yet. Raises OSError."""
    directory = os.path.join(destination, SUBFOLDER)
    if not os.path.isdir(directory):
        return None
    files = {}
    for _, target in FILES + OPTIONAL:
        try:
            with open(os.path.join(directory, target), "rb") as f:
                data = f.read()
        except FileNotFoundError:
            continue
        files[target] = {"sha256": hashlib.sha256(data).hexdigest(), "bytes": len(data)}
    try:
        with open(os.path.join(directory, LIST), "rb") as f:
            if json.loads(f.read()).get("files") == files:
                return "unchanged"
    except (OSError, ValueError, AttributeError):
        pass
    text = json.dumps({"version": 1, "writtenAt": now(), "files": files}, indent=1)
    writer(os.path.join(directory, LIST), text.encode("utf-8"))
    return "written"


def main(argv, say=print, writer=write_atomically, limit=LIMIT, defaults=default_folders,
         now=lambda: int(time.time() * 1000)):
    parser = argparse.ArgumentParser(prog="teach_publish.py")
    parser.add_argument("--folder", default=teach_store.FOLDER)
    parser.add_argument("--to", action="append", metavar="FOLDER")
    parser.add_argument("--min-precision", type=share, default=MIN_PRECISION)
    try:
        options = parser.parse_args(argv)
    except SystemExit:
        return 2
    folder = os.path.expanduser(options.folder)
    destinations = [os.path.expanduser(f) for f in options.to] if options.to else defaults()
    exit_code = 0
    broken = []  # the destinations an existing folder could not be written to, in order

    def failed(number, destination):
        """Notes a failed write: the first folder is a set-up problem (2), a later folder that exists
        (the iCloud copy the phone reads) has its own code (3)."""
        nonlocal exit_code
        if number == 0:
            exit_code = 2
        elif os.path.isdir(destination):
            exit_code = exit_code or ICLOUD_FAILED
        else:
            return
        if destination not in broken:
            broken.append(destination)

    for source, target in FILES + OPTIONAL:
        try:
            data = checked(os.path.join(folder, source), limit, (1, 2) if target == MODEL else (1,))
            if target == SETTINGS:
                settings_shape(data)
            if target == AHEAD[1]:
                ahead_shape(data)
            if target == CUES[1]:
                cues_shape(data)
        except FileNotFoundError:
            # ahead-ads.json exists only when the nightly read-ahead is on and ad-cues.json only
            # after the Mac has learned from enough episodes, so their absence is quiet.
            if (source, target) not in OPTIONAL:
                say("%s: skipped, there is no %s in %s." % (target, source, folder))
            continue
        except (OSError, ValueError) as error:
            say("%s: not copied, %s is not fit to publish: %s." % (target, source, error))
            exit_code = 2
            continue
        if target == MODEL:
            reason = weak_model(data, options.min_precision)
            if reason:
                say("%s: The small model was not published: %s. A model already in the phone's "
                    "folder is left as it is." % (target, reason))
                continue
        if target == MEANING:
            reason = weak_meaning(data, folder, options.min_precision)
            if reason:
                say("%s: The meaning model was not published: %s. A meaning model already in the "
                    "phone's folder is left as it is." % (target, reason))
                continue
        for number, destination in enumerate(destinations):
            try:
                outcome = put(destination, target, data, writer)
            except OSError as error:
                say("%s in %s: failed (%s)." % (target, destination, error))
                outcome = None
            else:
                say("%s in %s: %s." % (target, destination, outcome))
            if outcome is None:
                failed(number, destination)
    for number, destination in enumerate(destinations):
        try:
            outcome = update_list(destination, writer, now)
        except OSError as error:
            say("%s in %s: failed (%s)." % (LIST, destination, error))
            failed(number, destination)
        else:
            if outcome:
                say("%s in %s: %s." % (LIST, destination, outcome))
    for destination in broken:
        say("The copy into %s did not work, so that folder does not have the new files%s."
            % (destination, " (the phone reads this one)" if destination != destinations[0] else ""))
    return exit_code


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
