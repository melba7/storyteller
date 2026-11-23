"""Tests for teach_snap.py, the files side: a label with nothing to snap is copied as it was, the
snapped folder mirrors Claude's labels without ever changing them, the folder names that are
refused, and the exit codes. The rules for moving borders are in test_teach_snap.py.
Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import hashlib
import json
import os
import unittest

import teach_snap as snap
from test_teach_snap import HEADER, Base, segment


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


class SameFolderTests(Base):
    def test_names_that_differ_only_in_case_are_the_same_when_neither_exists(self):
        self.assertTrue(snap.same_folder(self.folder.path("Labels-x"), self.folder.path("labels-x")))
        self.assertFalse(snap.same_folder(self.folder.path("one"), self.folder.path("two")))

    def test_a_folder_and_a_link_to_it_are_the_same(self):
        os.symlink(self.folder.path("labels"), self.folder.path("alias"))
        self.assertTrue(snap.same_folder(self.folder.path("alias"), self.folder.path("labels")))
        self.assertFalse(snap.same_folder(self.folder.path("transcripts"), self.folder.path("labels")))

    def test_one_that_is_there_and_one_that_is_not_are_compared_by_their_lower_case_names(self):
        self.assertTrue(snap.same_folder(self.folder.path("LABELS"), self.folder.path("labels")))
        self.assertFalse(snap.same_folder(self.folder.path("labels-snapped"), self.folder.path("labels")))

    def test_a_link_to_the_labels_folder_is_refused_as_the_output_folder(self):
        os.symlink(self.folder.path("labels"), self.folder.path("mine"))
        self.assertEqual(self.run_main("--out", "mine"), 2)


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

    def test_a_name_that_differs_only_in_case_is_the_same_folder(self):
        # On a Mac's usual disk "Labels" is "labels", and the output would overwrite Claude's labels.
        self.label([segment(7, 12, 30.0, 60.0)])
        before = self.raw("labels", self.id + ".json")
        self.assertEqual(self.run_main("--out", "Labels"), 2)
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
