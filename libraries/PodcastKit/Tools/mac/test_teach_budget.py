"""Tests for teach_budget.py: the spending file that keeps a budget across runs.
Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import json
import os
import unittest

import teach_budget as budget
import teach_store as store
from teach_testing import Folder


class BudgetTests(unittest.TestCase):
    def setUp(self):
        self.folder = Folder(self)

    def write(self, text):
        with open(self.folder.path("marking-spend.json"), "w") as f:
            f.write(text)

    def read(self):
        with open(self.folder.path("marking-spend.json")) as f:
            return json.load(f)

    def test_a_new_budget_starts_at_nothing_and_writes_no_file_until_it_spends(self):
        found = budget.Budget(self.folder.dir, "exam", 14)
        self.assertEqual((found.dollars, found.episodes, found.left()), (0.0, 0, 14))
        self.assertFalse(os.path.exists(self.folder.path("marking-spend.json")))

    def test_adding_writes_the_file_in_the_agreed_shape(self):
        found = budget.Budget(self.folder.dir, "exam", 14)
        found.add(1.25, 1)
        found.add(0.5, 0)
        self.assertEqual(self.read(), {"version": 1, "budgets": {"exam": {"dollars": 1.75, "episodes": 1}}})
        self.assertEqual(os.listdir(self.folder.dir), ["marking-spend.json"])  # no temporary file

    def test_the_next_run_starts_from_what_was_spent_and_other_budgets_are_kept(self):
        budget.Budget(self.folder.dir, "exam", 14).add(3.0, 2)
        budget.Budget(self.folder.dir, "other", 5).add(1.0, 1)
        again = budget.Budget(self.folder.dir, "exam", 14)
        self.assertEqual((again.dollars, again.episodes, again.left()), (3.0, 2, 11.0))
        self.assertEqual(set(self.read()["budgets"]), {"exam", "other"})

    def test_it_says_what_is_spent_and_what_is_left(self):
        budget.Budget(self.folder.dir, "exam", 14).add(3.0, 2)
        line = budget.Budget(self.folder.dir, "exam", 14).line()
        for text in ("exam", "$3.00", "$11.00", "$14.00", "2 episodes"):
            self.assertIn(text, line)

    def test_a_spent_budget_has_nothing_left(self):
        found = budget.Budget(self.folder.dir, "exam", 2)
        found.add(2.5, 1)
        self.assertEqual(found.left(), 0)

    def test_a_damaged_file_is_a_set_up_problem_not_a_fresh_start(self):
        for text in ("nope", "[]", '{"version": 2, "budgets": {}}', '{"version": 1}',
                     '{"version": 1, "budgets": []}',
                     '{"version": 1, "budgets": {"a": {"dollars": "x", "episodes": 1}}}',
                     '{"version": 1, "budgets": {"a": {"dollars": -1, "episodes": 1}}}',
                     '{"version": 1, "budgets": {"a": {"dollars": 1, "episodes": 1.5}}}',
                     '{"version": 1, "budgets": {"a": {"dollars": 1}}}',
                     '{"version": 1, "budgets": {"a": {"dollars": NaN, "episodes": 1}}}'):
            self.write(text)
            with self.assertRaises(store.Problem, msg=text):
                budget.Budget(self.folder.dir, "exam", 14)

    def test_a_bad_name_is_a_set_up_problem(self):
        for name in ("", "a b", "../x", "x" * 80):
            with self.assertRaises(store.Problem, msg=name):
                budget.Budget(self.folder.dir, name, 14)


if __name__ == "__main__":
    unittest.main()
