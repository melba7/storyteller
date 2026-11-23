"""Tests for the counting in teach_exam.py: how many exam episodes have a transcript, are marked
once and are marked twice, and the plain lines the exam launcher prints from them.
Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import json
import os
import unittest

import teach_exam as exam
from teach_testing import Teaching, transcript


class StatusTests(unittest.TestCase):
    def setUp(self):
        self.said = []

    def teaching(self, count, in_exam=None):
        teaching = Teaching(self, count)
        ids = [e["id"] for e in teaching.entries]
        exam.add_to_exam(teaching.dir, ids if in_exam is None else [ids[i] for i in in_exam])
        return teaching, ids

    def mark(self, teaching, ids, labels):
        os.makedirs(teaching.path(labels), exist_ok=True)
        for identifier in ids:
            with open(teaching.path(labels, identifier + ".json"), "w") as f:
                json.dump({"version": 1}, f)

    def test_it_counts_the_exam_episodes_with_a_usable_transcript_marked_once_and_twice(self):
        teaching, ids = self.teaching(5, in_exam=[0, 1, 2, 3])
        teaching.write_transcript(teaching.entries[3], "")  # no usable line: not counted
        self.mark(teaching, ids[:2], "labels")
        self.mark(teaching, ids[4:], "labels")  # not an exam episode: not counted
        self.mark(teaching, ids[:1], "labels-second")
        found = exam.status(teaching.dir)
        self.assertEqual((found["ready"], found["first"], found["second"]), (3, 2, 1))
        self.assertEqual(found["wanted_second"], 3)

    def test_an_exam_episode_that_is_not_in_episodes_json_is_not_counted(self):
        teaching, _ = self.teaching(1)
        exam.add_to_exam(teaching.dir, ["0000000000ff"])
        self.assertEqual(exam.status(teaching.dir)["ready"], 1)

    def test_the_second_marking_wants_at_most_15(self):
        teaching, _ = self.teaching(20)
        self.assertEqual(exam.status(teaching.dir)["wanted_second"], 15)

    def test_it_is_complete_only_when_every_ready_episode_has_a_first_label_and_enough_second_ones(self):
        teaching, ids = self.teaching(20)
        self.assertFalse(exam.status(teaching.dir)["complete"])
        self.mark(teaching, ids, "labels")
        self.assertFalse(exam.status(teaching.dir)["complete"])
        self.mark(teaching, ids[:14], "labels-second")
        self.assertFalse(exam.status(teaching.dir)["complete"])
        self.mark(teaching, ids[14:15], "labels-second")
        self.assertTrue(exam.status(teaching.dir)["complete"])

    def test_with_no_ready_episode_it_is_not_complete(self):
        teaching, _ = self.teaching(2, in_exam=[])
        found = exam.status(teaching.dir)
        self.assertEqual((found["ready"], found["complete"]), (0, False))

    def test_the_ready_command_says_how_many_and_fails_when_there_are_none(self):
        teaching, _ = self.teaching(3)
        self.assertEqual(exam.main(["ready", "--folder", teaching.dir], say=self.said.append), 0)
        self.assertIn("3 exam episodes have audio and a transcript", self.said[-1])
        empty, _ = self.teaching(2, in_exam=[])
        self.assertEqual(exam.main(["ready", "--folder", empty.dir], say=self.said.append), 1)
        self.assertIn("No exam episode has audio and a transcript", self.said[-1])

    def test_the_finish_command_says_done_only_when_everything_is_marked(self):
        teaching, ids = self.teaching(4)
        self.mark(teaching, ids, "labels")
        self.mark(teaching, ids, "labels-second")
        self.assertEqual(exam.main(["finish", "--folder", teaching.dir], say=self.said.append), 0)
        text = "\n".join(self.said)
        for words in ("4 exam episodes", "marked once: 0", "marked twice: 4", "Done", "ready to be scored"):
            self.assertIn(words, text)

    def test_the_finish_command_says_what_is_left_and_never_done(self):
        teaching, ids = self.teaching(4)
        self.mark(teaching, ids[:3], "labels")
        self.mark(teaching, ids[:1], "labels-second")
        self.assertEqual(exam.main(["finish", "--folder", teaching.dir], say=self.said.append), 1)
        text = "\n".join(self.said)
        self.assertNotIn("Done", text)
        for words in ("marked once: 2", "marked twice: 1", "1 exam episode has no first marking",
                      "second marking has 1 of the 4", "Double-click again to carry on"):
            self.assertIn(words, text)

    def test_a_damaged_exam_file_is_a_set_up_problem(self):
        teaching, _ = self.teaching(1)
        with open(teaching.path("exam.json"), "w") as f:
            f.write("nope")
        self.assertEqual(exam.main(["finish", "--folder", teaching.dir], say=self.said.append), 2)

    def test_a_bad_command_is_a_set_up_problem(self):
        self.assertEqual(exam.main(["nonsense"], say=self.said.append), 2)


if __name__ == "__main__":
    unittest.main()
