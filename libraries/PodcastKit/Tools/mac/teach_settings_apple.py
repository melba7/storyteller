"""Apple's on-device model in the settings step (teach_settings.py): one more finder, "apple-model",
that ASKS by default, because on the owner's labels its answers made the phone worse: they added
skips where there was no ad. Standard library only.

The scorecard has two rows for it (AppleScoreRow.swift). The phone's row places Apple's answers as
the show-settings.json of that run says, so it moves with the settings. The what-if row lets every
answer skip, and stands on the last finder row whatever the settings say; that row is the evidence.
A show gets "skip" only when, on that show, the what-if row passes at least BAR_MORE_BREAKS more
breaks than the last finder row and adds at most BAR_MORE_SKIPS skips with no ad (the same bar as
steady joints, teach_settings_bar.py). Otherwise it keeps asking. Two undone or two "not an ad"
answers on a show (the phone's notes) still make it ask or turn it off there, as for every finder.

Run the tests: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
from teach_settings_bar import BAR_MORE_BREAKS, BAR_MORE_SKIPS

NAME = "apple-model"
PHONE_ROW = "Plus Apple's model (asked on the Mac)"
WHAT_IF_ROW = "Plus Apple's model, if every show let it skip"


def standing_on(rows, index):
    """The row that `rows[index]` is judged against: the one before it, except the what-if row, which
    is judged against the row before the phone's Apple row (the last finder row), so the skips the
    settings of the run already gave do not take away its evidence."""
    if rows[index].name == WHAT_IF_ROW:
        for at, each in enumerate(rows[:index]):
            if each.name == PHONE_ROW and at > 0:
                return rows[at - 1]
    return rows[index - 1]


def change(pair, key):
    """(more breaks passed, more skips with no ad, breaks) the what-if row has over the last finder row
    on the show `key`, or None when either row lacks the show or its bar."""
    if pair is None:
        return None
    row, before = pair
    if key not in row.shows or key not in before.shows:
        return None
    bar, base = row.shows[key].bar, before.shows[key].bar
    if bar is None or base is None:
        return None
    return bar.passed - base.passed, bar.skips - base.skips, bar.breaks


def pays(found):
    """Whether a `change` is enough to let the show skip: None never is."""
    return found is not None and found[0] >= BAR_MORE_BREAKS and found[1] <= BAR_MORE_SKIPS


def why(found):
    """The change in words that follow "its answers"."""
    return "would pass %d more of %d breaks and change the skips with no ad by %+d" \
        % (found[0], found[2], found[1])
