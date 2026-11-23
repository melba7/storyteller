"""Tests that teach_library.py leaves the sealed exam (exam.json) out of both libraries.
Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import json
import os

import teach_exam
from test_teach_library import Folder, word_list


class LibraryExamTests(Folder):
    def scored(self):
        with open(os.path.join(self.folder, "ad-library-score.json")) as f:
            return json.load(f)["ads"]

    def test_neither_library_has_the_ads_of_an_exam_episode(self):
        self.ad("aaaaaaaaaaaa", word_list("w", 40), who="Acme")
        self.ad("bbbbbbbbbbbb", word_list("z", 40), who="Sealed")
        teach_exam.add_to_exam(self.folder, ["bbbbbbbbbbbb"])
        self.assertEqual(self.run_main(), 0, self.messages)
        self.assertEqual([a["who"] for a in self.written()["ads"]], ["Acme"])
        self.assertEqual([a["who"] for a in self.scored()], ["Acme"])

    def test_the_score_library_leaves_out_shelf_and_exam_together(self):
        self.ad("aaaaaaaaaaaa", word_list("w", 40), who="Acme")
        self.ad("bbbbbbbbbbbb", word_list("z", 40), who="Sealed")
        self.ad("cccccccccccc", word_list("y", 40), who="OnShelf")
        teach_exam.add_to_exam(self.folder, ["bbbbbbbbbbbb"])
        with open(os.path.join(self.folder, "shelf.json"), "w") as f:
            json.dump({"version": 1, "episodes": ["cccccccccccc"]}, f)
        self.assertEqual(self.run_main(), 0, self.messages)
        self.assertEqual([a["who"] for a in self.written()["ads"]], ["Acme", "OnShelf"])
        self.assertEqual([a["who"] for a in self.scored()], ["Acme"])

    def test_an_exam_only_folder_has_no_labels_to_learn_from(self):
        self.ad("aaaaaaaaaaaa", word_list("w", 40))
        teach_exam.add_to_exam(self.folder, ["aaaaaaaaaaaa"])
        self.assertEqual(self.run_main(), 0)
        self.assertIn("No labels yet", self.messages[-1])
        self.assertFalse(os.path.exists(os.path.join(self.folder, "ad-library.json")))

    def test_a_damaged_exam_file_is_a_set_up_problem(self):
        self.ad("aaaaaaaaaaaa", word_list("w", 40))
        with open(os.path.join(self.folder, "exam.json"), "w") as f:
            f.write("nope")
        self.assertEqual(self.run_main(), 2)
