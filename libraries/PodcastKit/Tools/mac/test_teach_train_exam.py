"""Tests that teach_train.py leaves the sealed exam (exam.json) out: never trained on, never on
the shelf, and a training episode that repeats an exam episode is left out too.
Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import os
import unittest

import teach_exam
import teach_features as ft
from test_teach_train import Folder, run


class ExamTests(unittest.TestCase):
    def test_an_exam_episode_is_never_trained_on_and_is_counted(self):
        folder = Folder(self)
        for n in range(4):
            folder.add("a", n, brand="Sleepy")
        sealed = folder.add("a", 20, brand="Zorblax")
        teach_exam.add_to_exam(folder.path, [sealed])
        code, said = run(folder, "--min-episodes", "3")
        self.assertEqual(code, 0, said)
        model = folder.read("ad-model.json")
        self.assertNotIn(str(ft.bucket("u:zorblax")), model["weights"])
        self.assertEqual(model["trained"]["episodes"], 3)
        self.assertIn("Left 1 exam episode out of learning.", said)

    def test_an_exam_episode_is_never_put_on_the_shelf(self):
        folder = Folder(self)
        for n in range(3):
            folder.add("a", n)
        sealed = folder.add("a", 99)  # the newest of its show
        teach_exam.add_to_exam(folder.path, [sealed])
        code, said = run(folder, "--min-episodes", "2")
        self.assertEqual(code, 0, said)
        shelf = folder.read("shelf.json")["episodes"]
        self.assertEqual(len(shelf), 1)
        self.assertNotIn(sealed, shelf)

    def test_a_show_with_too_few_episodes_once_the_exam_is_left_out_gets_no_shelf(self):
        folder = Folder(self)
        folder.add("a", 1)
        folder.add("a", 2)
        sealed = folder.add("a", 3)
        teach_exam.add_to_exam(folder.path, [sealed])
        run(folder, "--min-episodes", "1")
        self.assertFalse(os.path.exists(folder.file("shelf.json")))

    def test_an_episode_that_repeats_an_exam_episode_is_left_out_of_training(self):
        folder = Folder(self)
        for n in range(3):
            folder.add("https://a.test/feed", n)
        sealed = folder.add("https://a.test/feed", 50)
        again = folder.add("http://www.a.test/feed/", 1)
        for one in folder.entries:
            if one["id"] in (sealed, again):
                one["guid"] = "same"
        folder.save()
        teach_exam.add_to_exam(folder.path, [sealed])
        code, said = run(folder, "--min-episodes", "2")
        self.assertEqual(code, 0, said)
        self.assertEqual(folder.read("ad-model.json")["trained"]["episodes"], 2)
        self.assertTrue(any(s.startswith("Left 1 episode out of training because it is the same as")
                            for s in said), said)

    def test_an_exam_episode_without_a_label_still_guards_against_repeats(self):
        folder = Folder(self)
        for n in range(3):
            folder.add("https://a.test/feed", n)
        sealed = folder.add("https://a.test/feed", 50, label=False)
        again = folder.add("http://www.a.test/feed/", 1)
        for one in folder.entries:
            if one["id"] in (sealed, again):
                one["guid"] = "same"
        folder.save()
        teach_exam.add_to_exam(folder.path, [sealed])
        run(folder, "--min-episodes", "2")
        self.assertEqual(folder.read("ad-model.json")["trained"]["episodes"], 2)

    def test_no_exam_no_line_about_it(self):
        folder = Folder(self)
        for n in range(4):
            folder.add("a", n)
        _, said = run(folder, "--min-episodes", "2")
        self.assertFalse([s for s in said if "exam" in s])

    def test_a_damaged_exam_file_is_a_setup_problem(self):
        folder = Folder(self)
        for n in range(4):
            folder.add("a", n)
        with open(folder.file("exam.json"), "w") as f:
            f.write("nope")
        code, said = run(folder, "--min-episodes", "2")
        self.assertEqual(code, 2)
        self.assertIn("exam.json", said[-1])


if __name__ == "__main__":
    unittest.main()
