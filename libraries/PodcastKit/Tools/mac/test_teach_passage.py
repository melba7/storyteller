"""Tests for teach_passage.py: which episodes it learns from and answers for, the cache that lets a
second run carry on, the answers file (no words), the held-out report and the exit codes, all on tiny
made-up teaching folders with a fake sentence model. No torch, no network, no Mac.
Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import contextlib
import io
import json
import os
import unittest
from unittest import mock

import numpy as np

import teach_passage as passage
import teach_passage_model as model
import teach_spans
import teach_store
from teach_passage_testing import FakeEncoder
from test_teach_train import Folder


def make_folder(test, teaching=12, shelf=2, exam=0):
    """A teaching folder with `teaching` marked episodes, `shelf` more that shelf.json names and
    `exam` that exam.json names. Returns (folder, shelf ids, exam ids)."""
    folder = Folder(test)
    for n in range(teaching):
        folder.add("feed%d" % (n % 4), 100 + n)
    shelved = [folder.add("shelf%d" % n, 200 + n) for n in range(shelf)]
    sealed = [folder.add("exam%d" % n, 300 + n) for n in range(exam)]
    teach_store.write_json(folder.file("shelf.json"), {"version": 1, "episodes": shelved})
    if sealed:
        teach_store.write_json(folder.file("exam.json"), {"episodes": sealed})
    return folder, shelved, sealed


def run(folder, *args, encoder=None):
    said = []
    code = passage.main(["--folder", folder.path, "--min-episodes", "8", "--epochs", "15"]
                        + list(args), say=said.append, encoder=encoder or FakeEncoder(),
                        now=lambda: 5)
    return code, said


class Base(unittest.TestCase):
    def setUp(self):
        # Forty lines an episode make a handful of steps a pass, so the steps are made larger than the
        # real run needs (it makes about a thousand steps a pass).
        patch = mock.patch.object(model, "RATE", 0.03)
        patch.start()
        self.addCleanup(patch.stop)


class AnswersTests(Base):
    def test_it_answers_for_the_shelf_episodes_only_and_the_file_holds_no_words(self):
        folder, shelved, _ = make_folder(self, exam=1)
        code, said = run(folder)
        self.assertEqual(code, 0, said)
        with open(folder.file("passage-model.json")) as f:
            text = f.read()
        data = json.loads(text)
        self.assertEqual(data["version"], 1)
        self.assertEqual(data["decoder"], 2)
        self.assertEqual(data["classes"], ["none", "sponsor", "network_promo", "host_ask", "intro_credits"])
        self.assertEqual(data["thresholds"], teach_spans.THRESHOLDS)
        self.assertEqual(sorted(data["episodes"]), sorted(shelved))
        for identifier in shelved:
            answer = data["episodes"][identifier]
            self.assertEqual(answer["lines"], 40)
            self.assertEqual(len(answer["rows"]), 40)
            for row in answer["rows"]:
                self.assertEqual(len(row), 5)
                self.assertAlmostEqual(sum(row), 1.0, delta=0.001)
        for word in ("brought", "percent", "weather", "river", "Sleepy", "Acme", "Zento"):
            self.assertNotIn(word, text)

    def test_the_rows_say_more_ad_on_the_ad_lines_than_on_the_talk(self):
        folder, shelved, _ = make_folder(self)
        run(folder)
        rows = np.array(folder.read("passage-model.json")["episodes"][shelved[0]]["rows"])
        ads = 1 - rows[9:14, 0]   # lines 10 to 14, 1-based
        talk = 1 - np.concatenate([rows[:6, 0], rows[20:, 0]])
        self.assertGreater(ads.mean(), 0.5)
        self.assertLess(talk.mean(), 0.3)

    def test_the_rows_go_through_the_word_models_decoder_to_one_span_over_the_ad(self):
        folder, shelved, _ = make_folder(self)
        run(folder)
        rows = folder.read("passage-model.json")["episodes"][shelved[0]]["rows"]
        starts = [10.0 * n for n in range(40)]
        ends = starts[1:] + [395.0]
        found = teach_spans.decode_two(rows, starts, ends)
        self.assertTrue(any(first <= 13 and last >= 9 and sort in teach_spans.SKIPPED_SORTS
                            for first, last, sort, _ in found), found)

    def test_it_says_what_it_learned_from_and_how_it_did_on_the_shelf(self):
        folder, shelved, _ = make_folder(self)
        code, said = run(folder)
        self.assertEqual(code, 0)
        trained = folder.read("passage-model.json")["trained"]
        self.assertEqual(trained["writtenAt"], 5)
        self.assertEqual(trained["labels"], "labels")
        self.assertEqual(trained["episodes"] + trained["checkEpisodes"], 12)
        self.assertEqual(trained["shelf"], 2)
        self.assertGreater(trained["checkEpisodes"], 0)
        held = trained["heldOut"]
        self.assertEqual(held["episodes"], 2)
        self.assertEqual(held["lines"], 80)
        for key in ("lineAccuracy", "lineAnyAd", "anyAd", "predictedAdSeconds", "adSeconds", "classes"):
            self.assertIn(key, held)
        self.assertGreater(held["lineAccuracy"], 0.8)
        everything = "\n".join(said)
        self.assertIn("Check on 2 held-out episodes", everything)
        self.assertIn("accuracy", everything)
        self.assertIn("recall", everything)

    def test_the_report_says_it_is_a_trial_and_what_the_go_rule_is(self):
        folder, _, _ = make_folder(self)
        _, said = run(folder)
        everything = "\n".join(said)
        self.assertIn("trial", everything)
        self.assertIn("Plus the passage model", everything)
        self.assertIn("10 more breaks", everything)
        self.assertIn("both label sets", everything)
        self.assertIn("2 more skips", everything)

    def test_a_second_run_gives_the_same_answers(self):
        folder, shelved, _ = make_folder(self)
        run(folder)
        first = folder.read("passage-model.json")["episodes"]
        run(folder)
        self.assertEqual(folder.read("passage-model.json")["episodes"], first)


class LearningSetTests(Base):
    def test_the_shelf_and_the_exam_are_never_read_for_learning_nor_embedded_for_it(self):
        folder, shelved, sealed = make_folder(self, exam=2)
        encoder = FakeEncoder()
        code, said = run(folder, encoder=encoder)
        self.assertEqual(code, 0, said)
        cached = os.listdir(folder.file("passage-cache"))
        for identifier in sealed:
            self.assertEqual([n for n in cached if n.startswith(identifier)], [], identifier)
        for identifier in shelved:
            self.assertEqual(len([n for n in cached if n.startswith(identifier)]), 1)
        self.assertEqual(encoder.lines, 14 * 40)
        self.assertIn("Left 2 exam episodes out of learning.", said)

    def test_an_episode_that_repeats_a_shelf_episode_is_not_trained_on(self):
        folder, shelved, _ = make_folder(self)
        shelf_entry = next(e for e in folder.entries if e["id"] == shelved[0])
        again = next(e for e in folder.entries if e["id"] not in shelved)
        again["feed"], again["guid"] = shelf_entry["feed"], shelf_entry["guid"]
        folder.save()
        code, said = run(folder)
        self.assertEqual(code, 0, said)
        trained = folder.read("passage-model.json")["trained"]
        self.assertEqual(trained["episodes"] + trained["checkEpisodes"], 11)
        self.assertTrue(any("Left 1 episode out of training" in line for line in said), said)

    def test_the_check_episodes_are_every_tenth_of_the_others(self):
        folder, _, _ = make_folder(self, teaching=20)
        run(folder)
        trained = folder.read("passage-model.json")["trained"]
        self.assertEqual((trained["episodes"], trained["checkEpisodes"]), (18, 2))

    def test_an_episode_with_no_label_or_a_damaged_one_is_skipped_with_a_line(self):
        folder, shelved, _ = make_folder(self)
        blank = folder.add("loose", 400, label=False)
        broken = folder.add("broken", 401)
        with open(folder.file("labels/%s.json" % broken), "w") as f:
            f.write("{not json")
        code, said = run(folder)
        self.assertEqual(code, 0, said)
        self.assertEqual(len([line for line in said if broken in line and "Skipping" in line]), 1)
        self.assertFalse([line for line in said if blank in line])
        trained = folder.read("passage-model.json")["trained"]
        self.assertEqual(trained["episodes"] + trained["checkEpisodes"], 12)

    def test_the_labels_folder_named_is_the_one_read(self):
        folder, _, _ = make_folder(self)
        os.rename(folder.file("labels"), folder.file("labels-snapped"))
        code, said = run(folder)
        self.assertEqual(code, 0)
        self.assertTrue(any("Only 0 episodes" in line for line in said), said)
        code, said = run(folder, "--labels", "labels-snapped")
        self.assertEqual(code, 0, said)
        self.assertEqual(folder.read("passage-model.json")["trained"]["labels"], "labels-snapped")

    def test_too_few_episodes_write_nothing_and_never_wake_the_sentence_model(self):
        folder, _, _ = make_folder(self, teaching=5)
        encoder = FakeEncoder()
        code, said = run(folder, encoder=encoder)
        self.assertEqual(code, 0)
        self.assertEqual(encoder.calls, 0)
        self.assertFalse(os.path.exists(folder.file("passage-model.json")))
        self.assertTrue(any("at least 8 are needed" in line and "no answers were written" in line
                            for line in said), said)


class CacheTests(Base):
    def test_a_second_run_embeds_nothing(self):
        folder, _, _ = make_folder(self)
        encoder = FakeEncoder()
        run(folder, encoder=encoder)
        first = encoder.lines
        self.assertEqual(first, 14 * 40)
        again = FakeEncoder()
        run(folder, encoder=again)
        self.assertEqual(again.calls, 0)

    def test_a_run_that_stopped_carries_on_with_what_was_embedded(self):
        folder, _, _ = make_folder(self)
        stopping = FakeEncoder()
        stopping.fail_on_call = 6
        with self.assertRaises(RuntimeError):
            run(folder, encoder=stopping)
        self.assertEqual(len(os.listdir(folder.file("passage-cache"))), 5)
        self.assertFalse(os.path.exists(folder.file("passage-model.json")))
        carrying = FakeEncoder()
        code, said = run(folder, encoder=carrying)
        self.assertEqual(code, 0, said)
        self.assertEqual(carrying.calls, 14 - 5)
        self.assertTrue(os.path.exists(folder.file("passage-model.json")))

    def test_it_gives_progress_lines_and_keeps_to_one_line_for_each_embedded_episode(self):
        folder, _, _ = make_folder(self)
        _, said = run(folder)
        embedding = [line for line in said if line.startswith("Embedded")]
        self.assertEqual(len(embedding), 14)
        self.assertIn("1 of 14", embedding[0])
        self.assertIn("14 of 14", embedding[-1])
        self.assertTrue(any("seconds" in line for line in embedding))


class SetUpTests(Base):
    def test_no_shelf_is_a_set_up_problem_that_says_where_it_comes_from(self):
        folder, _, _ = make_folder(self)
        os.remove(folder.file("shelf.json"))
        code, said = run(folder)
        self.assertEqual(code, 2)
        self.assertIn("shelf", " ".join(said))
        self.assertIn("Teach the phone again", " ".join(said))
        self.assertFalse(os.path.exists(folder.file("passage-model.json")))

    def test_no_episode_list_is_a_set_up_problem(self):
        folder = Folder(self)
        code, said = run(folder)
        self.assertEqual(code, 2)
        self.assertIn("episodes.json", " ".join(said))

    def test_a_damaged_shelf_or_exam_file_is_a_set_up_problem(self):
        folder, _, _ = make_folder(self)
        with open(folder.file("shelf.json"), "w") as f:
            f.write("{nope")
        code, said = run(folder)
        self.assertEqual(code, 2)
        self.assertIn("shelf.json is damaged", " ".join(said))

    def test_a_shelf_with_nothing_marked_is_a_set_up_problem(self):
        folder, shelved, _ = make_folder(self)
        for identifier in shelved:
            os.remove(folder.file("labels/%s.json" % identifier))
        code, said = run(folder)
        self.assertEqual(code, 2)
        self.assertIn("shelf", " ".join(said))

    def test_a_sentence_model_that_cannot_run_is_a_set_up_problem_with_its_own_sentence(self):
        folder, _, _ = make_folder(self)
        broken = FakeEncoder()
        broken.encode = mock.Mock(side_effect=teach_store.Problem("The sentence model needs torch."))
        code, said = run(folder, encoder=broken)
        self.assertEqual(code, 2)
        self.assertIn("The sentence model needs torch.", said)

    def test_bad_options_are_exit_2(self):
        folder, _, _ = make_folder(self)
        for option in (["--epochs", "0"], ["--seed", "x"], ["--nope"]):
            with contextlib.redirect_stderr(io.StringIO()):
                code, _ = run(folder, *option)
            self.assertEqual(code, 2, option)


if __name__ == "__main__":
    unittest.main()
