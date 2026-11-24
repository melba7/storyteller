"""The check of the passage model on the shelf, and the plain sentences that report it.

Standard library only. The shelf episodes are never trained on, so their lines are the held-out
lines. The numbers are the ones teach_shelf.evaluate gives for the word model, so the two can be
compared: per line (how often the top class is right, and precision and recall of "any ad"), and in
seconds of the spans the phone would cut when the answers go through the word model's decoder
(teach_spans.py, version 2). They are a first look only: what decides is the scorecard row
"Plus the passage model", which counts whole ad breaks (see PODCASTS-ADS-TEACHING.md).

Run the tests: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import teach_spans as spans
from teach_features import CLASSES
from teach_shelf import check_lines, percent, ratio, scores

CLASS_COUNT = len(CLASSES)
ROW = "Plus the passage model"
GO_RULE = ("This is a trial. The numbers above are only a first look at the shelf's lines; what "
           "counts is the scorecard row \"%s\", which stands on the last finder row. The plan goes "
           "on with the passage model only when that row passes at least 10 more breaks than the "
           "last finder row on both label sets (run the score on labels and on labels-snapped) and "
           "adds at most 2 more skips where there is no ad." % ROW)


def held_out(shelved, rows):
    """The numbers for the shelf episodes (dicts with id, feed, classes, starts, ends) given each
    one's probability rows by id (five numbers a line, as they are written to the file). Lines
    whose class is None are left out of the per-line numbers."""
    lines = right_class = hit = predicted = actual = 0
    per = [[0, 0, 0] for _ in CLASSES]
    cut = right = real = 0.0
    for episode in shelved:
        answers = rows[episode["id"]]
        for cls, row in zip(episode["classes"], answers):
            if cls is None:
                continue
            lines += 1
            guess = row.index(max(row))
            right_class += guess == cls
            predicted += row[0] < 0.5
            actual += cls != 0
            hit += row[0] < 0.5 and cls != 0
            per[guess][1] += 1
            per[cls][2] += 1
            per[cls][0] += guess == cls
        one = spans.span_scores(answers, episode["classes"], episode["starts"], episode["ends"],
                                version=2)
        cut, right, real = cut + one[0], right + one[1], real + one[2]
    return {"episodes": len(shelved), "shows": len({e["feed"] for e in shelved}), "lines": lines,
            "lineAccuracy": ratio(right_class, lines),
            "predictedAdSeconds": round(cut, 1), "adSeconds": round(real, 1),
            "anyAd": scores(right, cut, real), "lineAnyAd": scores(hit, predicted, actual),
            "classes": {CLASSES[c]: scores(*per[c]) for c in range(1, CLASS_COUNT)}}


def report_lines(held):
    """The report as plain sentences: the same first lines the word model's check prints, then the
    per-line numbers and what the numbers are for."""
    out = check_lines(held)
    out.append("Line accuracy over the five classes (the top class is the marked one): %s. Any ad, "
               "line by line: precision %s, recall %s."
               % (percent(held["lineAccuracy"]), percent(held["lineAnyAd"]["precision"]),
                  percent(held["lineAnyAd"]["recall"])))
    out.append(GO_RULE)
    return out
