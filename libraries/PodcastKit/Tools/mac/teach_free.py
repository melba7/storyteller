"""Frees disk space by deleting the audio of episodes whose lessons are already kept.

Standard library only. The audio is the big part of the teaching folder (about 60 MB an episode).
Three things still learn from an episode's audio after it has been written down and marked: the
ad sounds (the Swift `podcast-teach sounds` step), the comparison with a second download of the
same episode, and the exam. So an MP3 episode's audio goes only when all of its learning is kept:
its sound bank (sound-bank/<id>.json, written by `podcast-teach sounds` after the last change to its
marks and second download, so the library is rebuilt whole without the audio) and its second-download truth (copies/<id>.truth.txt, or the episode was
given up on after three failures). teach_backup.py leaves the audio out of its backups on purpose
and puts the sound bank in.

  python3 teach_free.py [--folder F]            says what it would free; nothing is deleted
  python3 teach_free.py [--folder F] --delete   makes and checks a backup of the marks, then deletes
  --without-copies                              also frees episodes still waiting for a second
                                                download: that comparison is given up for them

An episode's audio goes only when its transcript and its marks both exist, it has its sound bank
and its second-download truth (an episode that is not an MP3 needs neither), and it is not on the
shelf (shelf.json), in the exam (exam.json) or waiting in the nightly read-ahead (ahead.json): those
keep theirs. The transcripts, the marks, the sound banks, the models and every other small file stay.
The episode stays in episodes.json with file null, bytes 0 and the error "skipped: audio deleted
...", so the gathering never downloads it again and never counts it against the size limit. An
entry whose file is already gone from the disk is put right the same way. The shelf is chosen
from transcripts and marks, not from audio, so a show that has no shelf episode yet can later get
a freed one; the score rows that need audio then skip it, and it is better to let a run train
(which fills the shelf) before freeing.

It takes the folder's lock like every teaching tool, so it is refused while a gather, a writing
down or a marking run is working. Exit codes: 0 well (also when there is nothing to free), 1 the
backup was not good so nothing was deleted, 2 something to set right first, 3 another run is
working in the folder, 4 some audio could not be deleted (the rest was).

Run the tests: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import argparse
import json
import os
import shutil
import sys

import teach_backup
import teach_exam
import teach_store
from teach_failures import GIVE_UP_AFTER
from teach_second import Failures
from teach_shelf import read_shelf
from teach_store import FOLDER, Busy, ManifestError, run_lock, save_manifest

GB = 1_000_000_000
FREED = "skipped: audio deleted to free disk space; its transcript and marks are kept"
SAVE_EVERY = 25  # entries between saves of episodes.json while deleting


def read_ahead_ids(folder):
    """The ids in ahead.json (the nightly read-ahead), empty when there is no file. This reads the
    file itself, as teach_ahead_set.py does, so this tool needs nothing from the read-ahead."""
    path = os.path.join(folder, "ahead.json")
    if not os.path.exists(path):
        return set()
    try:
        with open(path, encoding="utf-8") as handle:
            data = json.load(handle)
        return {item["id"] for item in data["episodes"]}
    except (OSError, ValueError, KeyError, TypeError):
        raise teach_store.Problem("%s is damaged. Fix or remove it, and run again." % path)


def protected_ids(folder):
    """The ids whose audio is never deleted: the shelf, the exam and the read-ahead."""
    return set(read_shelf(folder)) | set(teach_exam.read_exam(folder)) | read_ahead_ids(folder)


def has_text(path):
    try:
        return os.path.getsize(path) > 0
    except OSError:
        return False


def modified(path):
    try:
        return os.path.getmtime(path)
    except OSError:
        return None


def bank_is_saved(folder, identifier):
    """True when sound-bank/<id>.json is that episode's bank and is at least as new as the marks the
    sounds step cut it from (labels/, labels-snapped/) and the second-download truth that snapping
    uses, so the bank holds the borders the library would get from the audio. Swift writes the bank
    and reads it again in full; this only checks whose it is, which labels it was cut from and when
    it was saved."""
    path = os.path.join(folder, "sound-bank", identifier + ".json")
    try:
        with open(path, encoding="utf-8") as handle:
            data = json.load(handle)
        if not (data["version"] == 1 and data["episode"] == identifier and isinstance(data["stretches"], list)):
            return False
    except (OSError, ValueError, KeyError, TypeError):
        return False
    saved = modified(path)
    newest = [modified(os.path.join(folder, "labels", identifier + ".json")),
              modified(os.path.join(folder, "copies", identifier + ".truth.txt"))]
    snapping = os.path.isdir(os.path.join(folder, "labels-snapped"))
    # teach-finish.sh gives the steps labels-snapped when that folder is there (and the snapping
    # worked), else Claude's own labels. The bank must come from the labels the audio would be cut by.
    if data.get("labels") != ("labels-snapped" if snapping else "labels"):
        return False
    if snapping:
        snapped = modified(os.path.join(folder, "labels-snapped", identifier + ".json"))
        if snapped is None:
            return False  # the snapping has not reached this episode yet
        newest.append(snapped)
    return saved is not None and all(when is None or when <= saved for when in newest)


def second_download_settled(folder, identifier, failures):
    """True when the episode was compared with its second download, or given up on."""
    return (os.path.exists(os.path.join(folder, "copies", identifier + ".truth.txt"))
            or failures.count(identifier) >= GIVE_UP_AFTER)


def candidates(folder, entries, keep, with_copies=True):
    """(to free, left): the entries whose audio may go, and how many entries with audio were left
    out and why. `with_copies` False also frees those waiting for a second download."""
    left = {"protected": 0, "no_transcript": 0, "no_marks": 0, "no_bank": 0, "no_copies": 0}
    failures = Failures(os.path.join(folder, "copies"))
    found = []
    for item in entries:
        if not item["file"]:
            continue
        identifier = item["id"]
        is_mp3 = item["file"].lower().endswith(".mp3")
        if identifier in keep:
            left["protected"] += 1
        elif not has_text(os.path.join(folder, "transcripts", identifier + ".txt")):
            left["no_transcript"] += 1
        elif not os.path.exists(os.path.join(folder, "labels", identifier + ".json")):
            left["no_marks"] += 1
        elif is_mp3 and not bank_is_saved(folder, identifier):
            left["no_bank"] += 1
        elif is_mp3 and with_copies and not second_download_settled(folder, identifier, failures):
            left["no_copies"] += 1
        else:
            found.append(item)
    return found, left


def size_on_disk(folder, item):
    try:
        return os.path.getsize(os.path.join(folder, item["file"]))
    except OSError:
        return 0


def drop_audio(folder, item):
    """Deletes the audio file of an entry of episodes.json (one that is already gone is fine) and
    puts the entry right: file null, bytes 0 and the error FREED, so the gathering never downloads
    it again. Raises OSError when the file cannot be deleted, and then the entry is not changed.
    teach_prepared.py uses it too."""
    try:
        os.remove(os.path.join(folder, item["file"]))
    except FileNotFoundError:
        pass
    item.update(file=None, bytes=0, error=FREED)


def free_space(folder, delete, say=print, backup=teach_backup.make_backup, with_copies=True):
    """Says what could be freed and, with `delete`, frees it. Returns the exit code."""
    entries = teach_store.require_manifest(folder)
    found, left = candidates(folder, entries, protected_ids(folder), with_copies)
    total = sum(size_on_disk(folder, item) for item in found)
    say("%d episodes have audio that can go (%.1f GB). What each one taught stays." % (len(found), total / GB))
    say("Kept: %d on the shelf, in the exam or waiting in the read-ahead, %d not written down yet, "
        "%d not marked yet, %d without a saved sound bank, %d waiting for their second download."
        % (left["protected"], left["no_transcript"], left["no_marks"], left["no_bank"], left["no_copies"]))
    if left["no_bank"]:
        say("The sound bank is written by 'Teach the phone again': run it, then this again.")
    if left["no_copies"]:
        more, _ = candidates(folder, entries, protected_ids(folder), with_copies=False)
        more_total = sum(size_on_disk(folder, item) for item in more) - total
        say("%d more episodes (%.1f GB) are waiting for their second download. Freeing them too "
            "(--without-copies, or typing all in the launcher) gives up that comparison."
            % (len(more) - len(found), more_total / GB))
    if not found:
        say("There is nothing to free.")
        return 0
    if not delete:
        say("Nothing was deleted. Run this again with --delete to free it.")
        return 0
    say("Making a backup of the marks first...")
    if backup(folder, check=True, say=say) != 0:
        say("Nothing was deleted, because the backup is not good.")
        return 1
    failed = 0
    for number, item in enumerate(found, 1):
        file = item["file"]
        try:
            drop_audio(folder, item)
        except OSError as error:
            failed += 1
            say("Could not delete %s: %s" % (file, error))
            continue
        if number % SAVE_EVERY == 0:
            save_manifest(folder, entries)
    save_manifest(folder, entries)
    say("Deleted the audio of %d episodes (%.1f GB). %.1f GB of the disk is free now."
        % (len(found) - failed, total / GB, shutil.disk_usage(folder).free / GB))
    if failed:
        say("%d could not be deleted. Run this again to try them again." % failed)
        return 4
    return 0


def main(argv=None, say=print, backup=teach_backup.make_backup):
    parser = argparse.ArgumentParser(description="Deletes the audio of episodes whose transcripts "
                                     "and marks are kept, to free disk space.")
    parser.add_argument("--folder", default=FOLDER)
    parser.add_argument("--delete", action="store_true", help="delete (without it, only say what could go)")
    parser.add_argument("--without-copies", action="store_true",
                        help="also free episodes still waiting for a second download (gives that up)")
    args = parser.parse_args(argv)
    folder = os.path.expanduser(args.folder)
    try:
        with run_lock(folder):
            return free_space(folder, args.delete, say, backup, not args.without_copies)
    except Busy as error:
        say(str(error))
        return 3
    except (teach_store.Problem, teach_backup.Problem) as error:
        say(str(error))
        return 2
    except ManifestError as error:
        say("%s\nNothing was changed. Fix or move that file and run this again." % error)
        return 2
    except OSError as error:
        say("The teaching folder %s cannot be used: %s" % (folder, error))
        return 2


if __name__ == "__main__":
    sys.exit(main())
