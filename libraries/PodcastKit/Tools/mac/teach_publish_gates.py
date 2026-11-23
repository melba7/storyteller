"""The two checks of teach_publish.py that are about the newest teaching files: the scorecard half of
the gate for ad-meaning.json, and the shape of show-settings.json.

Standard library only. The meaning model is published only when it passes the word model's check on
held-out episodes (teach_publish.py does that half) AND the newest run of scorecard.json shows that
the row "Plus the meaning model" helps. Rows are cumulative: each stands on the row before it, so
what the model added is the difference between the two (right seconds are adSeconds - heardSeconds,
wrong seconds are cutSeconds, as in teach_settings_rows.py). The row must

- add right seconds for host_ask or network_promo (the sorts the model is meant for: plugs read
  by the host that use no ad words), which the scorecard keeps per row in total.bySort
  (seconds of the sort, and seconds of it still heard);
- add them with a precision of at least the bar (85 percent): the right seconds it added divided
  by the right and the wrong seconds it added;
- come from a scorecard that is not older than the model (a model trained after the last score
  has not been scored).

With no scorecard, no such row or no numbers per sort the model is not published: the phone never
runs a meaning model nobody has measured.

Run the tests: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import json
import math
import os

from teach_settings_rows import SCORECARD, read_scorecard, rows_in
from teach_store import Problem

MEANING_ROW = "Plus the meaning model"
SORTS = ("host_ask", "network_promo")
EPSILON = 1e-6


def finite(value):
    """A finite JSON number (a boolean or a string is not one)."""
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return False
    try:
        return math.isfinite(value)
    except OverflowError:
        return False


def written_at(data):
    """When the meaning model says it was trained (milliseconds), or None."""
    trained = json.loads(data).get("trained")
    value = trained.get("writtenAt") if isinstance(trained, dict) else None
    return value if finite(value) else None


def sort_gain(row, before):
    """The right seconds of host_ask and network_promo that the raw row `row` has over `before`, or
    None when either row has no numbers for them."""
    gain = 0.0
    for sort in SORTS:
        found = []
        for item in (row, before):
            total = item.get("total") if isinstance(item, dict) else None
            kept = total.get("bySort") if isinstance(total, dict) else None
            one = kept.get(sort) if isinstance(kept, dict) else None
            seconds = one.get("seconds") if isinstance(one, dict) else None
            heard = one.get("heardSeconds") if isinstance(one, dict) else None
            if not (finite(seconds) and finite(heard)):
                return None
            found.append(seconds - heard)
        gain += found[0] - found[1]
    return gain


def percent(value):
    return "%g%%" % round(value * 100, 1)


def scorecard_reason(folder, meaning, minimum):
    """A sentence saying why the scorecard in `folder` does not show that the meaning model (the
    bytes `meaning`) helps, or None when it does."""
    try:
        root = read_scorecard(os.path.join(folder, SCORECARD))
    except Problem as error:
        return "the scorecard could not be used (%s)" % str(error).replace(" Nothing was written.", "")
    if root is None:
        return "there is no scorecard yet, so nobody has measured it (run \"Score the ad skipping\")"
    rows = rows_in(root)
    names = [row.name for row in rows]
    if MEANING_ROW not in names:
        return "the newest run of the scorecard has no row \"%s\" (run \"Score the ad skipping\")" \
            % MEANING_ROW
    index = names.index(MEANING_ROW)
    if index == 0:
        return "the scorecard has no row before \"%s\" to compare it with" % MEANING_ROW
    at = root["runs"][-1].get("at")
    trained = written_at(meaning)
    if finite(at) and trained is not None and at < trained:
        return "the scorecard is older than the meaning model, so it was not scored (run " \
            "\"Score the ad skipping\")"
    right = rows[index].total.right - rows[index - 1].total.right
    wrong = max(0.0, rows[index].total.wrong - rows[index - 1].total.wrong)
    if right <= EPSILON:
        return "it added no right seconds to the row before it in the scorecard"
    if right / (right + wrong) < minimum - 1e-9:
        return "what it added in the scorecard was right with a precision of %s, and %s is needed" \
            % (percent(right / (right + wrong)), percent(minimum))
    raw = {}
    for item in root["runs"][-1].get("rows", []):
        if isinstance(item, dict):
            raw.setdefault(item.get("name"), item)  # the first row of a name, as the chooser takes it
    gain = sort_gain(raw.get(names[index]), raw.get(names[index - 1]))
    if gain is None:
        return "the scorecard has no numbers per sort, so it cannot say whether the model finds " \
            "%s" % " or ".join(SORTS)
    if gain <= EPSILON:
        return "it added no right seconds for %s in the scorecard" % " or ".join(SORTS)
    return None


def settings_shape(data):
    """Raises ValueError (with the reason in plain words) when the phone would refuse these bytes of
    show-settings.json: it must have a list of shows, which the Mac always writes."""
    if not isinstance(json.loads(data).get("shows"), list):
        raise ValueError("it has no list of shows")
