"""The owner's bar in the settings step: whether steady files get joints, from the breaks the
scorecard's rows pass. Standard library only.

The steady-joints row stands on the row before it, which is the "Plus joints" row. Steady joints are on
when the steady row passes at least BAR_MORE_BREAKS more breaks than the row before it and adds at most
BAR_MORE_SKIPS skips that cut show where there was no ad. When one of the two rows has no bar (a
scorecard from before the bar, or a damaged one) nothing is decided here and teach_settings.py reads
the seconds as it always did.

Run the tests: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""

BAR_MORE_BREAKS = 3
BAR_MORE_SKIPS = 1


def bar_decision(pair, lines):
    """Whether steady joints are on by the owner's bar, or None when the steady row and the row before
    it do not both carry one. They are on when the steady row passes at least BAR_MORE_BREAKS more
    breaks than the row before it and adds at most BAR_MORE_SKIPS skips with no ad. Says why in `lines`."""
    row, before = pair
    if row.bar is None or before.bar is None:
        return None
    breaks = row.bar.passed - before.bar.passed
    skips = row.bar.skips - before.bar.skips
    if breaks >= BAR_MORE_BREAKS and skips <= BAR_MORE_SKIPS:
        lines.append("Joints are used in steady files too: they pass %d more of %d breaks and change the "
                     "skips with no ad by %+d." % (breaks, row.bar.breaks, skips))
        return True
    lines.append("Joints are not used in steady files: they pass %d more of %d breaks (%d needed) and change "
                 "the skips with no ad by %+d (at most +%d allowed)."
                 % (breaks, row.bar.breaks, BAR_MORE_BREAKS, skips, BAR_MORE_SKIPS))
    return False
