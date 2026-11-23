"""Finding and calling the `claude` command line, set up the way the app's Swift code
(ClaudeCodeTransport) sets it up: no tools, no saved session, one fixed empty working folder, and
ANTHROPIC_API_KEY removed, so a run uses the Claude plan this Mac is signed in to.

Standard library only. teach_label.py uses it.

Run the tests: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import json
import os
import re
import subprocess
import tempfile

RUN_SECONDS = 900
# Where the Swift code looks, after PATH: relative names are under the home folder.
EXTRA_FOLDERS = (".local/bin", ".claude/local", "/opt/homebrew/bin", "/usr/local/bin")
# The Swift transport's folder for every run (under the temporary folder, so nothing in it is
# picked up from a project).
WORKING_FOLDER = os.path.join(tempfile.gettempdir(), "lofi-claude-code")
# The Swift code answers 401 for these.
SIGNED_OUT = ("not logged in", "/login", "invalid api key", "oauth")
# What Claude Code says when a plan's allowance or the rate is used up ("Claude AI usage limit
# reached", "429 rate limit", "5-hour limit reached", "You've hit your limit"). Other talk of limits
# (a context limit, a heap limit, Node's MaxListeners warning) is not one.
USAGE_LIMIT = re.compile(
    r"\b(?:usage|rate|session|weekly|daily|hourly|\d+-hour|five-hour)[ _-]?limit|too many requests"
    r"|\b429\b|hit your .{0,40}\blimit", re.IGNORECASE)


class UsageLimit(RuntimeError):
    """Claude says the usage or rate limit is reached, or that it is not signed in."""


class ClaudeError(RuntimeError):
    """A failed run; `cost` is what the run cost anyway, in dollars (0 when unknown)."""
    cost = 0.0


def find_claude(environment, extra_folders=EXTRA_FOLDERS):
    """The path of `claude`: the folders in PATH, then the folders Claude Code installs into
    (the same list as the Swift code), or None."""
    home = environment.get("HOME") or os.path.expanduser("~")
    folders = [f for f in environment.get("PATH", "").split(":") if f]
    folders += [f if f.startswith("/") else os.path.join(home, f) for f in extra_folders]
    for folder in folders:
        path = os.path.join(folder, "claude")
        if os.path.isfile(path) and os.access(path, os.X_OK):
            return path
    return None


def is_signed_out(message):
    """True when the message says Claude is not signed in (as opposed to a usage limit)."""
    return any(word in message.lower() for word in SIGNED_OUT)


def is_usage_limit(message):
    """True for not-signed-in wording and for usage or rate limit wording, as the Swift code
    decides (401 and 429), but not for other uses of the word "limit"."""
    return is_signed_out(message) or USAGE_LIMIT.search(message) is not None


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


def failure(error_class, message, cost=0.0):
    error = error_class(message)
    error.cost = cost
    return error


def ask_claude(system, prompt, model, claude, runner=subprocess.run, timeout=RUN_SECONDS,
               environment=None, folder=WORKING_FOLDER):
    """One `claude -p` run, started in `folder`. Returns {"text", "cost"}. Raises UsageLimit when
    the usage limit is reached or Claude is not signed in, and ClaudeError (a RuntimeError) for
    any other failure; both carry `cost`, what the run cost even though it failed. The prompt goes
    to claude's standard input, never into an argument or an error message."""
    arguments = [claude, "-p", "--output-format", "json", "--no-session-persistence",
                 "--tools", "", "--strict-mcp-config", "--disable-slash-commands",
                 "--model", model, "--system-prompt", system]
    child_environment = dict(os.environ if environment is None else environment)
    child_environment.pop("ANTHROPIC_API_KEY", None)
    child_environment["ENABLE_CLAUDEAI_MCP_SERVERS"] = "false"
    try:
        os.makedirs(folder, exist_ok=True)
        done = runner(arguments, input=prompt, capture_output=True, encoding="utf-8",
                      env=child_environment, cwd=folder, timeout=timeout)
    except subprocess.TimeoutExpired:
        raise failure(ClaudeError, "claude took longer than %d seconds" % timeout)
    except OSError as error:
        raise failure(ClaudeError, "claude could not be run: %s" % error)
    result = printed_result(done.stdout or "")
    if result is None:
        raw = "%s\n%s" % (done.stdout or "", done.stderr or "")
        detail = (done.stderr or done.stdout or "")[-300:].strip()
        message = "claude exited %s without a result: %s" % (done.returncode, detail)
        raise failure(UsageLimit if is_usage_limit(raw) else ClaudeError, message)
    text = result.get("result")
    cost = result.get("total_cost_usd")
    cost = float(cost) if isinstance(cost, (int, float)) and not isinstance(cost, bool) else 0.0
    if result.get("is_error") is True or done.returncode != 0:
        message = text if isinstance(text, str) else result.get("subtype") or \
            "claude -p failed (exit %s)" % done.returncode
        raise failure(UsageLimit if is_usage_limit(message) else ClaudeError, message, cost)
    if not isinstance(text, str):
        raise failure(ClaudeError, "claude printed no answer text", cost)
    return {"text": text, "cost": cost}
