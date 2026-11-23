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
        self.assertEqual((added["sort"], added["confidence"], added["who"]), ("sponsor", "copy", ""))
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

    def test_two_labels_of_one_ad_become_one_with_the_biggest_ones_sort(self):
        self.label([segment(7, 16, 30.0, 50.0, who="Acme"),
                    segment(17, 18, 50.0, 60.0, sort="host_ask", who="")])
        self.truth(("0:31.000", "1:01.000"))
        self.run_main()
        found = self.snapped()["segments"]
        self.assertEqual(len(found), 1)
        self.assertEqual((found[0]["sort"], found[0]["who"]), ("sponsor", "Acme"))
        self.assertEqual((found[0]["start"], found[0]["end"]), (31.0, 61.0))
        self.assertIn("joined", self.text())

    def test_a_label_that_is_half_in_two_stretches_goes_to_the_earlier_one(self):
        self.label([segment(7, 12, 30.0, 60.0)])
        self.truth(("0:20.000", "0:45.000"), ("0:45.000", "1:20.000"))
        self.run_main()
        found = self.snapped()["segments"]
        # The later stretch is only 15 s of its 35 s inside the label, so it was not marked.
        self.assertEqual([(s["start"], s["end"], s["confidence"]) for s in found],
                         [(20.0, 45.0, "high"), (45.0, 80.0, "copy")])

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


class UnchangedTests(Base):
    def test_an_episode_without_a_truth_file_is_copied_byte_for_byte(self):
        self.label([segment(7, 12, 30.0, 60.0)])
        self.assertEqual(self.run_main(), 0)
        self.assertEqual(self.raw("labels-snapped", self.id + ".json"), self.raw("labels", self.id + ".json"))
        self.assertIn("1 had no second download", self.text())

    def test_a_truth_file_with_no_stretch_leaves_the_label_as_it_was_and_says_why(self):
        self.label([segment(7, 12, 30.0, 60.0)])
        self.write("copies/%s.truth.txt" % self.id, HEADER + "# The two files have no frame in common\n")
        self.run_main()
        self.assertEqual(self.raw("labels-snapped", self.id + ".json"), self.raw("labels", self.id + ".json"))
        self.assertIn("the same ads", self.text())
        self.assertIn("nothing is learned", self.text())

    def test_a_stretch_that_changes_nothing_leaves_the_label_as_it_was(self):
        self.label([segment(21, 80, 100.0, 400.0)])
        self.truth(("3:20.000", "3:50.000"))
        self.run_main()
        self.assertEqual(self.raw("labels-snapped", self.id + ".json"), self.raw("labels", self.id + ".json"))

    def test_a_truth_file_that_cannot_be_read_leaves_the_label_as_it_was(self):
        self.label([segment(7, 12, 30.0, 60.0)])
        self.write("copies/%s.truth.txt" % self.id, "this is not a truth file\n")
        self.assertEqual(self.run_main(), 0)
        self.assertEqual(self.raw("labels-snapped", self.id + ".json"), self.raw("labels", self.id + ".json"))
        self.assertIn(self.id, self.text())
        self.assertIn("not two times", self.text())

    def test_a_label_that_cannot_be_read_is_copied_as_it_is_and_said(self):
        self.write("labels/%s.json" % self.id, "{broken")
        self.truth(("0:33.480", "1:02.120"))
        self.assertEqual(self.run_main(), 0)
        self.assertEqual(self.raw("labels-snapped", self.id + ".json"), b"{broken")
        self.assertIn("could not be read", self.text())

    def test_a_label_with_odd_segments_does_not_stop_the_run(self):
        odd = [None, 5, {"sort": "sponsor"}, {"sort": "sponsor", "start": "a", "end": 3},
               {"sort": "sponsor", "start": float("inf"), "end": float("inf")},
               {"sort": "sponsor", "start": 50.0, "end": 40.0}, segment(7, 12, 30.0, 60.0)]
        self.write("labels/%s.json" % self.id, json.dumps({"segments": odd, "length": 600}))
        self.truth(("0:33.480", "1:02.120"))
        self.assertEqual(self.run_main(), 0)
        found = self.snapped()["segments"]
        self.assertEqual(found[:6], odd[:6])
        self.assertEqual((found[-1]["start"], found[-1]["end"]), (33.48, 62.12))

    def test_without_a_transcript_borders_move_but_lines_stay_and_nothing_is_added(self):
        os.remove(self.folder.path("transcripts", self.id + ".txt"))
        self.label([segment(7, 12, 30.0, 60.0)])
        self.truth(("0:33.480", "1:02.120"), ("3:20.000", "3:50.000"))
        self.run_main()
        found = self.snapped()["segments"]
        self.assertEqual([(s["first"], s["last"], s["start"], s["end"]) for s in found], [(7, 12, 33.48, 62.12)])


class FolderTests(Base):
    def test_claudes_own_labels_are_never_changed(self):
        self.label([segment(7, 12, 30.0, 60.0)])
        other = "%012x" % 2
        self.label([segment(1, 3, 0.0, 15.0)], identifier=other)
        self.truth(("0:33.480", "1:02.120"), ("3:20.000", "3:50.000"))
        before = {name: hashlib.sha256(self.raw("labels", name)).hexdigest() for name in os.listdir(self.folder.path("labels"))}
        self.assertEqual(self.run_main(), 0)
        after = {name: hashlib.sha256(self.raw("labels", name)).hexdigest() for name in os.listdir(self.folder.path("labels"))}
        self.assertEqual(before, after)
        self.assertEqual(sorted(os.listdir(self.folder.path("labels-snapped"))), sorted(before))

    def test_every_label_gets_a_snapped_one(self):
        ids = ["%012x" % n for n in range(1, 6)]
        for identifier in ids:
            self.label([segment(7, 12, 30.0, 60.0)], identifier=identifier)
        self.run_main()
        self.assertEqual(sorted(os.listdir(self.folder.path("labels-snapped"))), sorted(i + ".json" for i in ids))

    def test_files_that_are_not_labels_are_left_alone(self):
        self.label([segment(7, 12, 30.0, 60.0)])
        self.write("labels/notes.txt", "x")
        self.write("labels/.%s.part" % self.id, "x")
        self.run_main()
        self.assertEqual(os.listdir(self.folder.path("labels-snapped")), [self.id + ".json"])

    def test_a_snapped_label_whose_label_is_gone_is_removed(self):
        self.label([segment(7, 12, 30.0, 60.0)])
        self.run_main()
        os.rename(self.folder.path("labels", self.id + ".json"), self.folder.path("moved.json"))
        self.run_main()
        self.assertEqual(os.listdir(self.folder.path("labels-snapped")), [])

    def test_running_it_again_gives_the_same_files(self):
        self.label([segment(7, 12, 30.0, 60.0)])
        self.truth(("0:33.480", "1:02.120"), ("3:20.000", "3:50.000"))
        self.run_main()
        first = self.raw("labels-snapped", self.id + ".json")
        self.run_main()
        self.assertEqual(self.raw("labels-snapped", self.id + ".json"), first)

    def test_no_temporary_file_is_left_behind(self):
        self.label([segment(7, 12, 30.0, 60.0)])
        self.truth(("0:33.480", "1:02.120"))
        self.run_main()
        self.assertEqual([n for n in os.listdir(self.folder.path("labels-snapped")) if n.startswith(".")], [])

    def test_other_folder_names_can_be_used(self):
        self.label([segment(7, 12, 30.0, 60.0)])
        self.assertEqual(self.run_main("--labels", "labels", "--out", "mine"), 0)
        self.assertTrue(os.path.exists(self.folder.path("mine", self.id + ".json")))


class ExitCodeTests(Base):
    def test_no_labels_folder_gives_2(self):
        os.rmdir(self.folder.path("labels"))
        self.assertEqual(self.run_main(), 2)
        self.assertIn("no labels", self.text().lower())
        self.assertFalse(os.path.exists(self.folder.path("labels-snapped")))

    def test_an_empty_labels_folder_is_nothing_to_do_and_gives_0(self):
        self.assertEqual(self.run_main(), 0)
        self.assertIn("No labels", self.text())

    def test_the_output_folder_may_not_be_the_labels_folder(self):
        self.label([segment(7, 12, 30.0, 60.0)])
        before = self.raw("labels", self.id + ".json")
        self.assertEqual(self.run_main("--out", "labels"), 2)
        self.assertEqual(self.raw("labels", self.id + ".json"), before)

    def test_folder_names_must_be_plain(self):
        for name in ("../x", "a/b", "", ".", "..", "a b"):
            self.assertEqual(self.run_main("--out", name), 2, name)
            self.assertEqual(self.run_main("--labels", name), 2, name)

    def test_a_folder_that_cannot_be_written_gives_2(self):
        self.label([segment(7, 12, 30.0, 60.0)])
        self.write("labels-snapped", "a file where the folder should be")
        self.assertEqual(self.run_main(), 2)
        self.assertIn("Could not write", self.text())


if __name__ == "__main__":
    unittest.main()
