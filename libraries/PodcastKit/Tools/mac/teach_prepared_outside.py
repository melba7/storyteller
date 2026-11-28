"""What teach_prepared.py asks of the world outside the program: running a command, the free disk
space, what iCloud says it has left, and whether a folder can really be written to. They are handed
to the tools as arguments, so the tests stand in for them.

Standard library only.

Run the tests: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import os
import re
import shutil
import subprocess
import tempfile

GB = 1_000_000_000
ICLOUD_ROOM = 2 * GB  # what iCloud must have left after a file
QUOTA = re.compile(r"([0-9][0-9,]*)\s+bytes of quota remaining")


def run_command(command):
    """(exit code, what it printed). Raises OSError when the program cannot be started."""
    done = subprocess.run(command, capture_output=True, text=True, timeout=None if command[0] == "cp" else 30)
    return done.returncode, done.stdout + done.stderr


def disk_free(path):
    return shutil.disk_usage(path).free


def quota_left(run):
    """The bytes iCloud says it has left, or None when `brctl quota` is missing, fails or says
    something this does not understand."""
    try:
        code, text = run(["brctl", "quota"])
    except (OSError, subprocess.SubprocessError):
        return None
    found = QUOTA.search(text or "") if code == 0 else None
    return int(found.group(1).replace(",", "")) if found else None


def writable(folder):
    """None when a small file can really be written into `folder` (made when it is not there) and
    removed again; else the reason in words. os.access is not enough: macOS refuses a background job
    at the write itself. The test file's name starts with a dot and it is gone afterwards, also after
    a failure."""
    path = None
    try:
        os.makedirs(folder, exist_ok=True)
        handle, path = tempfile.mkstemp(dir=folder, prefix=".ready-")
        try:
            os.write(handle, b"ready")
        finally:
            os.close(handle)
        os.remove(path)
        return None
    except OSError as error:
        if path and os.path.exists(path):
            try:
                os.remove(path)
            except OSError:
                pass
        return str(error) or error.__class__.__name__
