"""Tests for teach_snap.py: moving a label's borders onto the stretches where two downloads differ,
adding a stretch Claude did not mark, copying an episode that has no truth file as it was, the
figures it prints and its exit codes. No audio, no network, no Claude. The truth file itself is
tested in test_teach_truth.py. Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import hashlib
import json
import os
import unittest

import teach_snap as snap
import teach_testing
import teach_train

HEADER = "# Ads marked from the differences between two downloads of one episode.\n"


def lines_of_five_seconds(count=120):
    """A transcript text where line n (from 1) starts at (n - 1) * 5 seconds."""
    return "".join("[%02d:%02d:%02d.0] line %d\n" % (n * 5 // 3600, n * 5 // 60 % 60, n * 5 % 60, n + 1)
                   for n in range(count))


def segment(first, last, start, end, sort="sponsor", who="Acme", confidence="high"):
    return {"first": first, "last": last, "sort": sort, "who": who, "delivery": "host",
            "confidence": confidence, "why": "x", "start": start, "end": end}


class Base(unittest.TestCase):
    def setUp(self):
        self.folder = teach_testing.Folder(self)
        self.entry = teach_testing.entry(1, audio=True)
        self.id = self.entry["id"]
        self.said = []
        os.makedirs(self.folder.path("labels"))
        os.makedirs(self.folder.path("copies"))
        os.makedirs(self.folder.path("transcripts"))
        self.write("transcripts/%s.txt" % self.id, lines_of_five_seconds())

    def say(self, line):
        self.said.append(line)

    def write(self, name, text):
        with open(self.folder.path(*name.split("/")), "w", encoding="utf-8") as handle:
            handle.write(text)

    def label(self, segments, identifier=None, **more):
        label = {"version": 1, "prompt": "t1", "model": "m", "episode": identifier or self.id,
                 "feed": "https://feed/1", "show": "Show", "lines": 120, "length": 600.0,
                 "segments": segments, "dropped": 0, "cost": 0.25, "writtenAt": 1}
        label.update(more)
        self.write("labels/%s.json" % (identifier or self.id), json.dumps(label, indent=1))
        return label

    def truth(self, *times, identifier=None):
        text = HEADER + "".join("%s %s\n" % pair for pair in times)
        self.write("copies/%s.truth.txt" % (identifier or self.id), text)

    def run_main(self, *extra):
        return snap.main(["--folder", self.folder.dir] + list(extra), say=self.say)

    def snapped(self, identifier=None):
        with open(self.folder.path("labels-snapped", (identifier or self.id) + ".json"), encoding="utf-8") as f:
            return json.load(f)

    def raw(self, *names):
        with open(self.folder.path(*names), "rb") as handle:
            return handle.read()

    def text(self):
        return "\n".join(self.said)


class SnapTests(Base):
    def test_a_label_that_overlaps_a_stretch_by_half_takes_its_start_and_end(self):
        self.label([segment(7, 12, 30.0, 60.0)])
        self.truth(("0:33.480", "1:02.120"))
        self.assertEqual(self.run_main(), 0)
        found = self.snapped()["segments"]
        self.assertEqual(len(found), 1)
        self.assertEqual((found[0]["start"], found[0]["end"]), (33.48, 62.12))
        self.assertEqual((found[0]["first"], found[0]["last"]), (8, 12))
        for key in ("sort", "who", "delivery", "confidence", "why"):
            self.assertEqual(found[0][key], segment(7, 12, 30.0, 60.0)[key])

    def test_a_label_of_claudes_that_moves_keeps_its_confidence_and_gains_no_key(self):
        self.label([segment(7, 12, 30.0, 60.0, confidence="low")])
        self.truth(("0:33.480", "1:02.120"))
        self.run_main()
        found = self.snapped()["segments"][0]
        self.assertEqual(found["confidence"], "low")
        self.assertEqual(set(found), set(segment(7, 12, 30.0, 60.0)))

    def test_everything_else_in_the_label_stays(self):
        label = self.label([segment(7, 12, 30.0, 60.0)])
        self.truth(("0:33.480", "1:02.120"))
        self.run_main()
        after = self.snapped()
        after["segments"] = label["segments"]
        self.assertEqual(after, label)

    def test_a_label_with_less_than_half_inside_the_stretch_stays_where_it_was(self):
        # Claude marked 5 minutes; the stretch is 30 s of it. The label is not cut down to it.
        self.label([segment(21, 80, 100.0, 400.0)])
        self.truth(("3:20.000", "3:50.000"))
        self.run_main()
        found = self.snapped()["segments"]
        self.assertEqual([(s["start"], s["end"]) for s in found], [(100.0, 400.0)])
        self.assertIn("Stretches Claude had not marked: 0", self.text())

    def test_a_stretch_without_a_label_of_10_s_or_more_is_added_as_a_sponsor(self):
        self.label([segment(7, 12, 30.0, 60.0)])
        self.truth(("3:20.000", "3:50.000"))
        self.run_main()
        found = self.snapped()["segments"]
        self.assertEqual([(s["start"], s["end"]) for s in found], [(30.0, 60.0), (200.0, 230.0)])
        added = found[1]
        self.assertEqual((added["sort"], added["confidence"], added["who"]), ("sponsor", "medium", ""))
        self.assertEqual(added["origin"], "copy")
        self.assertEqual((added["first"], added["last"]), (41, 46))
        self.assertIn(added["delivery"], ("host", "spot", "unsure"))
        self.assertTrue(added["why"])

    def test_a_stretch_under_10_s_without_a_label_is_not_added(self):
        self.label([segment(7, 12, 30.0, 60.0)])
        self.truth(("5:00.000", "5:09.900"))
        self.run_main()
        self.assertEqual(len(self.snapped()["segments"]), 1)
        self.assertIn("Stretches Claude had not marked: 1", self.text())
        self.assertIn("under 10 s", self.text())

    def test_a_stretch_beyond_the_transcript_is_left_out_and_said(self):
        self.label([])
        self.truth(("12:00.000", "12:40.000"))
        self.run_main()
        self.assertEqual(self.snapped()["segments"], [])
        self.assertIn("transcript does not reach", self.text())

    def test_added_stretches_keep_the_label_readable_for_the_training(self):
        self.label([segment(7, 12, 30.0, 60.0)])
        self.truth(("0:33.480", "1:02.120"), ("3:20.000", "3:50.000"))
        self.run_main()
        self.assertTrue(teach_train.valid_label(self.snapped()))

    def test_a_label_that_is_half_in_two_stretches_goes_to_the_earlier_one(self):
        self.label([segment(7, 12, 30.0, 60.0)])
        self.truth(("0:20.000", "0:45.000"), ("0:45.000", "1:20.000"))
        self.run_main()
        found = self.snapped()["segments"]
        # The label grows to the start of the earlier stretch but is not cut back by 15 s at its end.
        # The later stretch is only 15 s of its 35 s inside the label, so it was not marked.
        self.assertEqual([(s["start"], s["end"], s.get("origin")) for s in found],
                         [(20.0, 60.0, None), (45.0, 80.0, "copy")])

    def test_the_figures_say_how_many_borders_moved_and_by_how_much(self):
        self.label([segment(7, 12, 30.0, 60.0)])
        self.truth(("0:33.480", "1:02.120"), ("3:20.000", "3:50.000"))
        self.run_main()
        text = self.text()
        self.assertIn("Borders moved: 2 (median 2.8 s)", text)
        self.assertIn("Stretches Claude had not marked: 1 (1 added", text)

    def test_a_border_that_stays_put_is_not_counted(self):
        self.label([segment(7, 12, 30.0, 60.0)])
        self.truth(("0:30.000", "1:02.000"))
        self.run_main()
        self.assertIn("Borders moved: 1 (median 2.0 s)", self.text())

    def test_no_border_moving_is_said(self):
        self.label([segment(7, 12, 30.0, 60.0)])
        self.truth(("0:30.000", "1:00.000"))
        self.run_main()
        self.assertIn("No border moved", self.text())


class NeverJoinTests(Base):
    def test_labels_in_one_stretch_are_never_joined_only_the_outer_borders_move(self):
        # A break where every slot differs is one stretch; each advertiser keeps its own label.
        labels = [segment(61, 66, 300.0, 330.0, who="Acme"), segment(67, 73, 330.0, 365.0, who="Shoe Co"),
                  segment(74, 79, 365.0, 395.0, sort="network_promo", who="Other Show trailer")]
        self.label(labels)
        self.truth(("4:59.200", "6:35.400"))
        self.run_main()
        found = self.snapped()["segments"]
        self.assertEqual([(s["start"], s["end"]) for s in found],
                         [(299.2, 330.0), (330.0, 365.0), (365.0, 395.4)])
        for new, old in zip(found, labels):
            for key in ("sort", "who", "delivery", "confidence", "why"):
                self.assertEqual(new[key], old[key])
        self.assertIn("Borders moved: 2 (median 0.6 s)", self.text())
        self.assertNotIn("joined", self.text())
        self.assertIn("Stretches Claude had not marked: 0", self.text())

    def test_two_labels_in_one_stretch_stay_two_with_their_own_sort_and_who(self):
        self.label([segment(7, 16, 30.0, 50.0, who="Acme"), segment(17, 18, 50.0, 60.0, sort="host_ask", who="")])
        self.truth(("0:31.000", "1:01.000"))
        self.run_main()
        found = self.snapped()["segments"]
        self.assertEqual([(s["start"], s["end"], s["sort"], s["who"]) for s in found],
                         [(31.0, 50.0, "sponsor", "Acme"), (50.0, 61.0, "host_ask", "")])


class InwardTests(Base):
    """A border may grow to the stretch's, but never moves inward by more than 10 s."""

    def test_a_label_does_not_shrink_to_the_later_of_two_stretches(self):
        self.label([segment(25, 36, 120.0, 180.0)])
        self.truth(("2:00.000", "2:20.000"), ("2:25.000", "3:00.000"))
        self.run_main()
        self.assertEqual([(s["start"], s["end"]) for s in self.snapped()["segments"]], [(120.0, 180.0)])
        self.assertIn("No border moved", self.text())
        self.assertIn("Stretches Claude had not marked: 0", self.text())

    def test_a_label_does_not_shrink_past_a_baked_in_ad_that_both_downloads_have(self):
        self.label([segment(25, 38, 120.0, 190.0)])  # a shared ad 2:00 to 2:30, then a slot
        self.truth(("2:30.000", "3:10.000"))
        self.run_main()
        self.assertEqual([(s["start"], s["end"]) for s in self.snapped()["segments"]], [(120.0, 190.0)])
        self.assertEqual(self.raw("labels-snapped", self.id + ".json"), self.raw("labels", self.id + ".json"))

    def test_the_limit_is_10_s_inward_and_does_not_apply_outward(self):
        self.label([segment(21, 28, 100.0, 140.0)])
        self.truth(("1:30.000", "2:10.000"))  # the end is 10 s inward: allowed
        self.run_main()
        self.assertEqual([(s["start"], s["end"]) for s in self.snapped()["segments"]], [(90.0, 130.0)])
        self.truth(("1:30.000", "2:09.000"))  # 11 s inward: the end stays, the start still grows
        self.run_main()
        self.assertEqual([(s["start"], s["end"]) for s in self.snapped()["segments"]], [(90.0, 140.0)])

    def test_a_stretch_is_checked_against_the_labels_as_they_were_snapped(self):
        # The label shrinks by 10 s to 100-130, so the 130-150 stretch is no longer inside it. Before
        # the shrinking it was half inside the label (10 s of 20 s).
        self.label([segment(21, 28, 100.0, 140.0)])
        self.truth(("1:40.000", "2:10.000"), ("2:10.000", "2:30.000"))
        self.run_main()
        found = self.snapped()["segments"]
        self.assertEqual([(s["start"], s["end"], s.get("origin")) for s in found],
                         [(100.0, 130.0, None), (130.0, 150.0, "copy")])


class RuleTests(Base):
    def test_a_label_that_overlaps_a_stretch_by_40_percent_does_not_move(self):
        self.label([segment(7, 12, 30.0, 60.0)])
        self.truth(("0:48.000", "1:20.000"))  # 12 s of the label's 30 s
        self.run_main()
        found = self.snapped()["segments"]
        self.assertEqual([(s["start"], s["end"], s.get("origin")) for s in found],
                         [(30.0, 60.0, None), (48.0, 80.0, "copy")])

    def test_a_label_that_overlaps_a_stretch_by_exactly_half_moves(self):
        self.label([segment(7, 12, 30.0, 60.0)])
        self.truth(("0:15.000", "0:45.000"))  # 15 s of the label's 30 s
        self.run_main()
        self.assertEqual([(s["start"], s["end"]) for s in self.snapped()["segments"]], [(15.0, 60.0)])

    def test_a_stretch_of_300_s_is_used_and_a_longer_one_is_left_out_and_said(self):
        self.label([])
        self.truth(("3:20.000", "8:20.000"))
        self.run_main()
        self.assertEqual([(s["start"], s["end"]) for s in self.snapped()["segments"]], [(200.0, 500.0)])
        self.truth(("3:20.000", "8:21.000"))
        self.run_main()
        self.assertEqual(self.snapped()["segments"], [])
        self.assertIn("over 300 s", self.text())

    def test_a_stretch_over_300_s_moves_no_label_either(self):
        self.label([segment(25, 26, 120.0, 130.0)])
        self.truth(("1:40.000", "7:00.000"))
        self.run_main()
        self.assertEqual([(s["start"], s["end"]) for s in self.snapped()["segments"]], [(120.0, 130.0)])


if __name__ == "__main__":
    unittest.main()
