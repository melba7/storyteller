#!/usr/bin/env python3
"""Has Claude mark every advertisement and promotion in the transcripts of the teaching run, one
episode at a time, and saves one label file per episode.

Standard library only. It reads <folder>/episodes.json (written by the gather step) and
<folder>/transcripts/<id>.txt, and writes <folder>/<labels>/<id>.json as soon as each episode is
done. An episode that already has a label is not asked again, so a stopped run carries on where it
stopped. Each episode is one or a few `claude -p` runs, set up the way the app's Swift code
(ClaudeCodeTransport) sets them up: no tools, no saved session, an empty working folder, and
ANTHROPIC_API_KEY removed, so it runs on the Claude plan this Mac is signed in to and shares its
usage allowance. Nothing is sent anywhere else.

  teach_label.py [--folder F] [--labels labels] [--model claude-opus-5-5] [--limit N]
                 [--cap DOLLARS] [--yes]

Without --yes it says what it is about to do and waits for you to type yes. It stops when --limit
episodes are done, when the cost so far reaches --cap, when Claude says the usage limit is reached
or it is not signed in, or after three episodes in a row failed. Exit code: 0 everything waiting
was marked, there was nothing to do, or --limit was reached; 2 a set-up problem; 3 stopped early.

Run the tests: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import argparse
import json
import math
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time

import teach_segments as seg

DEFAULT_FOLDER = "~/Storyteller Lofi/PodcastTeaching"
DEFAULT_MODEL = "claude-opus-5-5"
RUN_SECONDS = 900
FAILURES_IN_A_ROW = 3
EXTRA_FOLDERS = (".local/bin", ".claude/local", "/opt/homebrew/bin", "/usr/local/bin")
USABLE_ID = re.compile(r"^[0-9A-Za-z_-]{1,64}$")


class Problem(Exception):
    """A set-up problem: the run cannot start (exit code 2)."""


class UsageLimit(RuntimeError):
    """Claude says the usage or rate limit is reached, or that it is not signed in."""


# MARK: Claude

def find_claude(environment):
    """The path of `claude`: the folders in PATH, then the folders Claude Code installs into
    (the same list as the Swift code), or None."""
    home = environment.get("HOME") or os.path.expanduser("~")
    folders = [f for f in environment.get("PATH", "").split(":") if f]
    folders += [f if f.startswith("/") else os.path.join(home, f) for f in EXTRA_FOLDERS]
    for folder in folders:
        path = os.path.join(folder, "claude")
        if os.path.isfile(path) and os.access(path, os.X_OK):
            return path
    return None


def is_usage_limit(message):
    """The Swift code's wording tests for not signed in (401) and usage or rate limits (429)."""
    m = message.lower()
    signed_out = ("not logged in", "/login", "invalid api key", "oauth")
    return (any(word in m for word in signed_out) or "limit" in m
            or re.search(r"\brate\b", m) is not None)


def printed_result(output):
    """The result object claude printed (the whole output, or its last line), or None."""
    text = output.strip()
    for candidate in [text] + list(reversed(text.splitlines())):
        try:
            value = json.loads(candidate)
        except ValueError:
            continue
        if isinstance(value, dict) and (value.get("type") == "result" or "result" in value):
            return value
    return None


def ask_claude(system, prompt, model, claude, runner=subprocess.run, timeout=RUN_SECONDS,
               environment=None):
    """One `claude -p` run. Returns {"text", "cost"}. Raises UsageLimit when the usage limit is
    reached or Claude is not signed in, and RuntimeError for any other failure. The prompt goes
    to claude's standard input, never into an argument or an error message."""
    arguments = [claude, "-p", "--output-format", "json", "--no-session-persistence",
                 "--tools", "", "--strict-mcp-config", "--disable-slash-commands",
                 "--model", model, "--system-prompt", system]
    child_environment = dict(os.environ if environment is None else environment)
    child_environment.pop("ANTHROPIC_API_KEY", None)
    child_environment["ENABLE_CLAUDEAI_MCP_SERVERS"] = "false"
    folder = tempfile.mkdtemp(prefix="lofi-claude-code-")
    try:
        done = runner(arguments, input=prompt, capture_output=True, encoding="utf-8",
                      env=child_environment, cwd=folder, timeout=timeout)
    except subprocess.TimeoutExpired:
        raise RuntimeError("claude took longer than %d seconds" % timeout)
    except OSError as error:
        raise RuntimeError("claude could not be run: %s" % error)
    finally:
        shutil.rmtree(folder, ignore_errors=True)
    result = printed_result(done.stdout or "")
    if result is None:
        detail = (done.stderr or done.stdout or "")[-300:].strip()
        message = "claude exited %s without a result: %s" % (done.returncode, detail)
        if is_usage_limit(detail):
            raise UsageLimit(message)
        raise RuntimeError(message)
    text = result.get("result")
    if result.get("is_error") is True or done.returncode != 0:
        message = text if isinstance(text, str) else result.get("subtype") or \
            "claude -p failed (exit %s)" % done.returncode
        raise (UsageLimit if is_usage_limit(message) else RuntimeError)(message)
    if not isinstance(text, str):
        raise RuntimeError("claude printed no answer text")
    cost = result.get("total_cost_usd")
    return {"text": text, "cost": float(cost) if isinstance(cost, (int, float)) else 0.0}


# MARK: Files

def read_episodes(folder):
    """The usable entries of <folder>/episodes.json (those with a plain `id`), in file order, with
    `feed`, `show` and `title` as strings. Raises Problem when the file is missing, not JSON,
    another version or not the expected shape."""
    path = os.path.join(folder, "episodes.json")
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
    except OSError:
        raise Problem("There is no episodes.json in %s. Run the gather step first." % folder)
    except ValueError:
        raise Problem("episodes.json in %s is not valid JSON." % folder)
    if not isinstance(data, dict) or data.get("version") != 1 \
            or not isinstance(data.get("episodes"), list):
        raise Problem("episodes.json in %s is not a version 1 episode list." % folder)
    episodes = []
    for item in data["episodes"]:
        if not isinstance(item, dict) or not isinstance(item.get("id"), str) \
                or not USABLE_ID.match(item["id"]):
            continue
        episodes.append({"id": item["id"],
                         "feed": item["feed"] if isinstance(item.get("feed"), str) else "",
                         "show": item["show"] if isinstance(item.get("show"), str) else "",
                         "title": item["title"] if isinstance(item.get("title"), str) else ""})
    return episodes


def write_json(path, value):
    """Writes `value` as JSON to `path` through a temporary file in the same folder."""
    folder = os.path.dirname(path)
    os.makedirs(folder, exist_ok=True)
    handle, temporary = tempfile.mkstemp(dir=folder, prefix=".", suffix=".part")
    try:
        with os.fdopen(handle, "w", encoding="utf-8") as f:
            json.dump(value, f, indent=1, ensure_ascii=False)
        os.replace(temporary, path)
    except BaseException:
        if os.path.exists(temporary):
            os.remove(temporary)
        raise


def waiting(folder, labels):
    """([(entry, lines)], [ids with no usable lines]): the episodes in episodes.json order that
    have a transcript and no label yet."""
    found, empty = [], []
    for item in read_episodes(folder):
        if os.path.exists(os.path.join(folder, labels, item["id"] + ".json")):
            continue
        try:
            with open(os.path.join(folder, "transcripts", item["id"] + ".txt"),
                      encoding="utf-8", errors="replace") as f:
                lines = seg.read_transcript(f.read())
        except OSError:
            continue
        if lines:
            found.append((item, lines))
        else:
            empty.append(item["id"])
    return found, empty


# MARK: Marking

def label_episode(entry, lines, model, ask, limit=seg.PART_CHARS, now=time.time):
    """The label for one episode. `ask(prompt)` returns {"text", "cost"}. An answer that cannot be
    read is asked for once more; the second failure raises ValueError."""
    segments, dropped, cost = [], 0, 0.0
    for first, last in seg.parts(lines, limit):
        question = seg.prompt(entry["show"], entry["title"], lines, first, last)
        for attempt in (1, 2):
            reply = ask(question)
            cost += reply["cost"]
            try:
                found, lost = seg.parse(reply["text"], first, last)
                break
            except ValueError:
                if attempt == 2:
                    raise
        segments += found
        dropped += lost
    return {"version": 1, "prompt": seg.PROMPT_VERSION, "model": model, "episode": entry["id"],
            "feed": entry["feed"], "show": entry["show"], "lines": len(lines),
            "length": lines[-1][0], "segments": seg.with_times(seg.merge(segments), lines),
            "dropped": dropped, "cost": cost, "writtenAt": int(now() * 1000)}


def counts_text(label):
    """"2 sponsor, 1 host_ask", or "no stretches found"."""
    parts = ["%d %s" % (n, sort) for sort in seg.SORTS
             for n in [sum(1 for s in label["segments"] if s["sort"] == sort)] if n]
    return ", ".join(parts) or "no stretches found"


def run(folder, labels, model, limit, cap, ask, say=print):
    """Marks the waiting episodes. Returns {"done", "failed", "cost", "stop", "reason"}; `stop` is
    None, "limit", "cap", "usage" or "failures"."""
    items, empty = waiting(folder, labels)
    for episode_id in empty:
        say("Skipping %s: its transcript has no usable lines." % episode_id)
    result = {"done": 0, "failed": 0, "cost": 0.0, "stop": None, "reason": ""}
    in_a_row = 0
    for number, (item, lines) in enumerate(items, 1):
        stop = None
        if limit is not None and result["done"] >= limit:
            stop = ("limit", "Stopped: the limit of %d episodes was reached." % limit)
        elif cap is not None and result["cost"] >= cap:
            stop = ("cap", "Stopped: the cost so far, $%.2f, reached the cap of $%.2f."
                    % (result["cost"], cap))
        if stop:
            result["stop"], result["reason"] = stop
            return result
        name = "%d of %d: %s, %s" % (number, len(items), item["show"], item["title"])
        try:
            made = label_episode(item, lines, model, ask)
        except UsageLimit as error:
            result["stop"] = "usage"
            result["reason"] = ("Stopped: Claude's usage limit is reached or it is not signed in "
                                "(%s). Everything done so far is saved." % str(error)[:150])
            return result
        except (RuntimeError, ValueError) as error:
            result["failed"] += 1
            in_a_row += 1
            say("%s: failed (%s)" % (name, str(error)[:150]))
            if in_a_row >= FAILURES_IN_A_ROW:
                result["stop"] = "failures"
                result["reason"] = "Stopped: %d episodes in a row failed." % FAILURES_IN_A_ROW
                return result
            continue
        in_a_row = 0
        write_json(os.path.join(folder, labels, item["id"] + ".json"), made)
        result["done"] += 1
        result["cost"] += made["cost"]
        say("%s: %s. Cost so far $%.2f." % (name, counts_text(made), result["cost"]))
    return result


# MARK: Command line

def positive_number(text):
    value = float(text)
    if not math.isfinite(value) or value <= 0:
        raise ValueError(text)
    return value


def main(argv, ask_person=input, runner=subprocess.run, environment=None, say=print):
    environment = dict(os.environ if environment is None else environment)
    parser = argparse.ArgumentParser(prog="teach_label.py")
    parser.add_argument("--folder", default=DEFAULT_FOLDER)
    parser.add_argument("--labels", default="labels")
    parser.add_argument("--model", default=DEFAULT_MODEL)
    parser.add_argument("--limit", type=int)
    parser.add_argument("--cap")
    parser.add_argument("--yes", action="store_true")
    options = parser.parse_args(argv)
    folder = os.path.expanduser(options.folder)
    try:
        cap = positive_number(options.cap) if options.cap is not None else None
        if options.limit is not None and options.limit < 1:
            raise ValueError("limit")
    except ValueError:
        say("The --cap must be a number of dollars above zero and the --limit a whole number "
            "above zero.")
        return 2
    try:
        items, _ = waiting(folder, options.labels)
    except Problem as error:
        say(str(error))
        return 2
    if not items:
        say("Nothing to do: every episode with a transcript already has a label.")
        return 0
    claude = find_claude(environment)
    if claude is None:
        say("Claude Code was not found. Install it and sign in once by running `claude`.")
        return 2
    chosen = items[:options.limit] if options.limit else items
    characters = sum(len(text) for _, lines in chosen for _, text in lines)
    say("%d episodes are waiting to be marked (%d this run), with %s."
        % (len(items), len(chosen), options.model))
    say("That is roughly {:,} tokens to read (an estimate: characters divided by 4)."
        .format(characters // 4))
    say("This uses the Claude plan this Mac is signed in to and shares its usage allowance.")
    if not options.yes:
        try:
            typed = ask_person("Type yes to start: ")
        except EOFError:
            typed = ""
        if typed.strip().lower() != "yes":
            say("Nothing was done.")
            return 0

    def ask(prompt):
        return ask_claude(seg.SYSTEM, prompt, options.model, claude, runner=runner,
                          environment=environment)

    result = run(folder, options.labels, options.model, options.limit, cap, ask, say=say)
    say("Marked %d episodes (%d failed). Cost as Claude counts it: $%.2f."
        % (result["done"], result["failed"], result["cost"]))
    if result["reason"]:
        say(result["reason"])
    return 3 if result["stop"] in ("cap", "usage", "failures") else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
