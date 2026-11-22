"""Tests for teach_train.py: the examples, the shelf, training, the check on the shelf, the written
model and the exit codes, all on tiny made-up teaching folders. No network.
Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import contextlib
import io
import json
import os
import random
import shutil
import tempfile
import unittest

import teach_collect as collect
import teach_features as ft
import teach_train as train

ADS = ["This episode is brought to you by {b}.", "Use promo code {b} at {b} dot com slash show.",
       "Go to {b} dot com slash {b} for twenty percent off."]
CHAT = ["We walked along the river {w} this morning.", "The weather was {w} and quite calm.",
        "My neighbour has a {w} dog that barks.", "Anyway the {w} story goes on for a while."]
WORDS = ["green", "slow", "loud", "tiny", "heavy", "quiet", "old", "wild"]
BRANDS = ["Sleepy", "Acme", "Zento", "Mellow", "Nimbus", "Kiwi"]


def stamp(seconds):
    return "[%02d:%02d:%04.1f]" % (seconds // 3600, seconds % 3600 // 60, seconds % 60)


def segment(first, last, sort="sponsor", confidence="high"):
    return {"first": first, "last": last, "start": 0, "end": 1, "sort": sort, "who": "",
            "delivery": "host", "confidence": confidence, "why": ""}


def entry(identifier, feed, published):
    one = {"id": identifier, "feed": feed, "show": "Show " + feed, "guid": "g" + identifier,
           "title": "Episode " + identifier, "published": published, "seconds": 400,
           "address": "https://example.com/" + identifier, "size": None,
           "file": None, "bytes": 0, "sha256": None, "host": None, "error": None}
    collect.check_entry(one)
    return one


class Folder:
    """A temporary teaching folder that episodes are added to."""

    def __init__(self, test):
        self.path = tempfile.mkdtemp()
        test.addCleanup(shutil.rmtree, self.path, True)
        self.entries = []
        self.counter = 0

    def add(self, feed, published, label=True, brand=None, ads=(10, 14), segments=None):
        """An episode of 40 lines, ten seconds apart, with ad lines at `ads` (1-based first, last)."""
        self.counter += 1
        identifier = "%012x" % (0xabc000 + self.counter)
        rng = random.Random(self.counter)
        brand = brand or rng.choice(BRANDS)
        lines = []
        for n in range(1, 41):
            if ads[0] <= n <= ads[1]:
                lines.append(rng.choice(ADS).format(b=brand))
            else:
                # A word nobody else has makes every chat line its own, as real talk is: two
                # episodes of one show do not share half their 5-word runs.
                chat = rng.choice(CHAT).format(w=rng.choice(WORDS))
                lines.append(chat + " " + "".join(rng.choice("abcdefghijklmnop") for _ in range(8)))
        os.makedirs(os.path.join(self.path, "transcripts"), exist_ok=True)
        with open(os.path.join(self.path, "transcripts", identifier + ".txt"), "w") as f:
            f.write("\n".join("%s %s" % (stamp(10 * (n - 1)), t) for n, t in enumerate(lines, 1)))
        if label:
            if segments is None:
                segments = [segment(ads[0], ads[1])]
            self.write_label(identifier, feed, segments)
        self.entries.append(entry(identifier, feed, published))
        self.save()
        return identifier

    def write_label(self, identifier, feed, segments, name="labels"):
        os.makedirs(os.path.join(self.path, name), exist_ok=True)
        with open(os.path.join(self.path, name, identifier + ".json"), "w") as f:
            json.dump({"version": 1, "episode": identifier, "feed": feed, "show": "Show " + feed,
                       "lines": 40, "length": 400, "segments": segments}, f)

    def save(self):
        with open(os.path.join(self.path, "episodes.json"), "w") as f:
            json.dump({"version": 1, "writtenAt": 0, "episodes": self.entries}, f)

    def file(self, name):
        return os.path.join(self.path, name)

    def read(self, name):
        with open(self.file(name)) as f:
            return json.load(f)


def run(folder, *args, **named):
    said = []
    code = train.main(["--folder", folder.path] + list(args), say=said.append,
                      now=lambda: 5, **named)
    return code, said


def toy_folder(test, episodes=6):
    folder = Folder(test)
    for n in range(episodes):
        folder.add("feedA", 100 + n)
    return folder


class ClassTests(unittest.TestCase):
    def test_classes_of_lines(self):
        classes = train.line_classes([segment(2, 3), segment(5, 5, "host_ask", "medium"),
                                      segment(7, 8, "network_promo", "low"),
                                      segment(9, 9, "intro_credits")], 10)
        self.assertEqual(classes, [0, 1, 1, 0, 3, 0, None, None, 4, 0])

    def test_a_strong_segment_beats_a_low_one_over_the_same_line(self):
        classes = train.line_classes([segment(1, 3, "sponsor", "low"),
                                      segment(2, 2, "host_ask", "high")], 4)
        self.assertEqual(classes, [None, 3, None, 0])

    def test_unknown_sorts_are_ignored(self):
        self.assertEqual(train.line_classes([segment(1, 2, "other")], 3), [0, 0, 0])


class ExampleTests(unittest.TestCase):
    def test_an_episode_becomes_one_example_per_line(self):
        folder = Folder(self)
        identifier = folder.add("f", 1, ads=(3, 4), segments=[segment(3, 4), segment(6, 6, confidence="low")])
        said = []
        found = train.load_episode(folder.path, "labels", folder.entries[0], said.append)
        self.assertEqual(found["id"], identifier)
        self.assertEqual(found["classes"][:7], [0, 0, 1, 1, 0, None, 0][:7])
        self.assertEqual(len(found["buckets"]), 40)
        self.assertEqual(said, [])

    def test_the_end_feature_uses_the_episode_seconds_when_known(self):
        folder = Folder(self)
        folder.add("f", 1)
        folder.entries[0]["seconds"] = 500
        found = train.load_episode(folder.path, "labels", folder.entries[0], print)
        end = ft.bucket("#end")
        # Length 500: lines starting at 380 s or later (line 40 starts at 390) are near the end.
        self.assertNotIn(end, found["buckets"][37])
        self.assertIn(end, found["buckets"][39])

    def test_without_episode_seconds_the_end_is_the_last_lines_start(self):
        for seconds in (None, 0, -5, True, "400"):
            folder = Folder(self)
            folder.add("f", 1)
            folder.entries[0]["seconds"] = seconds
            found = train.load_episode(folder.path, "labels", folder.entries[0], print)
            end = ft.bucket("#end")
            # The last line starts at 390 s, so lines from 270 s (line 28) are within 120 s of it.
            self.assertNotIn(end, found["buckets"][26], seconds)
            self.assertIn(end, found["buckets"][28], seconds)

    def test_missing_files_are_skipped_quietly(self):
        folder = Folder(self)
        folder.add("f", 1, label=False)
        said = []
        self.assertIsNone(train.load_episode(folder.path, "labels", folder.entries[0], said.append))
        self.assertEqual(said, [])

    def test_a_damaged_label_is_skipped_with_one_line(self):
        folder = Folder(self)
        identifier = folder.add("f", 1)
        with open(folder.file("labels/%s.json" % identifier), "w") as f:
            f.write("{not json")
        said = []
        self.assertIsNone(train.load_episode(folder.path, "labels", folder.entries[0], said.append))
        self.assertEqual(len(said), 1)
        self.assertIn(identifier, said[0])

    def test_a_label_of_the_wrong_shape_is_skipped(self):
        folder = Folder(self)
        identifier = folder.add("f", 1, segments=[{"first": "x", "last": 2, "sort": "sponsor",
                                                   "confidence": "high"}])
        said = []
        self.assertIsNone(train.load_episode(folder.path, "labels", folder.entries[0], said.append))
        self.assertEqual(len(said), 1)


class ShelfTests(unittest.TestCase):
    def test_a_new_show_joins_later(self):
        folder = Folder(self)
        for n in range(3):
            folder.add("a", n)
        folder.add("b", 1)
        folder.add("b", 2)
        code, _ = run(folder, "--min-episodes", "2")
        self.assertEqual(code, 0)
        first = folder.read("shelf.json")
        self.assertEqual(first["version"], 1)
        self.assertEqual(len(first["episodes"]), 1)
        folder.add("b", 3)
        run(folder, "--min-episodes", "2")
        second = folder.read("shelf.json")["episodes"]
        self.assertEqual(second[0], first["episodes"][0])
        self.assertEqual(len(second), 2)
        folder.add("a", 99)
        run(folder, "--min-episodes", "2")
        self.assertEqual(folder.read("shelf.json")["episodes"], second)

    def test_the_shelf_file_is_left_alone_when_nothing_changes(self):
        folder = toy_folder(self)
        run(folder, "--min-episodes", "2")
        before = os.stat(folder.file("shelf.json")).st_mtime_ns
        run(folder, "--min-episodes", "2")
        self.assertEqual(os.stat(folder.file("shelf.json")).st_mtime_ns, before)

    def test_a_damaged_shelf_is_a_setup_problem(self):
        folder = toy_folder(self)
        with open(folder.file("shelf.json"), "w") as f:
            f.write("nope")
        code, said = run(folder, "--min-episodes", "2")
        self.assertEqual(code, 2)
        self.assertIn("shelf.json", said[-1])


class TrainingTests(unittest.TestCase):
    def test_the_shelf_is_never_trained_on(self):
        folder = Folder(self)
        for n in range(4):
            folder.add("a", n, brand="Sleepy")
        shelved = folder.add("a", 50, brand="Zorblax")
        code, _ = run(folder, "--min-episodes", "3")
        self.assertEqual(code, 0)
        self.assertEqual(folder.read("shelf.json")["episodes"], [shelved])
        model = folder.read("ad-model.json")
        self.assertEqual(model["trained"]["episodes"], 4)
        self.assertEqual(model["trained"]["lines"], 160)
        self.assertEqual(model["trained"]["shelf"], 1)
        self.assertNotIn(str(ft.bucket("u:zorblax")), model["weights"])
        self.assertIn(str(ft.bucket("u:sleepy")), model["weights"])

    def test_it_learns_to_tell_ads_from_chatter_on_unseen_lines(self):
        folder = toy_folder(self, 8)
        code, said = run(folder, "--min-episodes", "3")
        self.assertEqual(code, 0)
        model = folder.read("ad-model.json")
        weights = {int(k): v for k, v in model["weights"].items()}
        lines = [(0.0, "We walked along the river slow this morning."),
                 (10.0, "My neighbour has a quiet dog that barks."),
                 (20.0, "Use promo code Blorp at Blorp dot com slash show."),
                 (30.0, "This episode is brought to you by Blorp."),
                 (40.0, "The weather was old and quite calm."),
                 (50.0, "Anyway the green story goes on for a while.")]
        for i in (0, 1, 4, 5):
            self.assertGreater(train.probabilities(weights, lines, i, 400)[0], 0.5, i)
        for i in (2, 3):
            self.assertLess(train.probabilities(weights, lines, i, 400)[0], 0.5, i)
        self.assertEqual(len([s for s in said if s.startswith("Pass ")]), 5)

    def test_the_same_seed_gives_the_same_file(self):
        folder = toy_folder(self)
        run(folder, "--min-episodes", "3", "--seed", "7")
        with open(folder.file("ad-model.json"), "rb") as f:
            first = f.read()
        run(folder, "--min-episodes", "3", "--seed", "7")
        with open(folder.file("ad-model.json"), "rb") as f:
            self.assertEqual(f.read(), first)
        run(folder, "--min-episodes", "3", "--seed", "8")
        with open(folder.file("ad-model.json"), "rb") as f:
            self.assertNotEqual(f.read(), first)

    def test_class_weights(self):
        self.assertEqual(train.class_weights([90, 10, 30, 0, 90]), [1.0, 5.0, 3.0, 5.0, 1.0])
        self.assertEqual(train.class_weights([0, 0, 0, 0, 0]), [1.0, 5.0, 5.0, 5.0, 5.0])

    def test_epochs_option_sets_the_passes(self):
        folder = toy_folder(self)
        _, said = run(folder, "--min-episodes", "3", "--epochs", "2")
        self.assertEqual(len([s for s in said if s.startswith("Pass ")]), 2)


class ModelFileTests(unittest.TestCase):
    def flat(self, values):
        weights = train.new_weights()
        for b, five in values.items():
            weights[b * 5:b * 5 + 5] = train.array("d", five)
        return weights

    def build(self, values, **named):
        trained = {"writtenAt": 5, "episodes": 1, "lines": 2, "shelf": 0}
        text = train.build_model(self.flat(values), trained, lambda w: {"episodes": 0, "w": len(w)},
                                 **named)
        return json.loads(text), text

    def test_shape_rounding_and_zero_buckets(self):
        model, _ = self.build({3: [0.123456, -0.00004, 0, 0, 0], 4: [0.00002, 0, 0, 0, 0.00004],
                               9: [0, 0, 0, 0, -1.5]})
        self.assertEqual(model["version"], 1)
        self.assertEqual(model["buckets"], 262144)
        self.assertEqual(model["classes"], ft.CLASSES)
        self.assertEqual(model["thresholds"], {"start": 0.6, "stay": 0.4, "sure": 0.85})
        self.assertEqual(model["weights"], {"3": [0.1235, -0.0, 0.0, 0.0, 0.0],
                                            "9": [0.0, 0.0, 0.0, 0.0, -1.5]})
        self.assertEqual(model["trained"]["heldOut"], {"episodes": 0, "w": 2})
        self.assertEqual(model["trained"]["lines"], 2)

    def test_only_the_biggest_buckets_up_to_the_cap(self):
        values = {b: [0, b / 10.0, 0, 0, 0] for b in range(1, 11)}
        model, _ = self.build(values, max_buckets=3)
        self.assertEqual(sorted(model["weights"], key=int), ["8", "9", "10"])

    def test_the_size_cap_writes_fewer_buckets(self):
        values = {b: [0, b / 10.0, 0.1, 0.1, 0.1] for b in range(1, 201)}
        _, full = self.build(values)
        cap = len(full) // 2
        model, text = self.build(values, max_bytes=cap)
        self.assertLessEqual(len(text.encode("utf-8")), cap)
        self.assertGreater(len(model["weights"]), 50)
        self.assertLess(len(model["weights"]), 200)
        self.assertIn("200", model["weights"])

    def test_the_default_caps(self):
        self.assertEqual(train.MAX_BUCKETS, 40000)
        self.assertEqual(train.MAX_BYTES, 4500000)


class CheckTests(unittest.TestCase):
    def test_the_run_saves_the_check(self):
        folder = Folder(self)
        for n in range(5):
            folder.add("a", n)
        run(folder, "--min-episodes", "3")
        held = folder.read("ad-model.json")["trained"]["heldOut"]
        self.assertEqual(held["episodes"], 1)
        self.assertEqual(held["lines"], 40)
        self.assertGreater(held["anyAd"]["recall"], 0.5)
        # What the publish step needs to trust the check.
        self.assertEqual((held["shows"], held["predictedAdSeconds"] > 0), (1, True))
        self.assertIn("lineAnyAd", held)


class ShelfAfterModelTests(unittest.TestCase):
    def test_the_shelf_is_not_saved_when_no_model_follows(self):
        folder = Folder(self)
        for n in range(3):
            folder.add("a", n)
        code, _ = run(folder, "--min-episodes", "3")
        self.assertEqual(code, 0)
        self.assertFalse(os.path.exists(folder.file("ad-model.json")))
        self.assertFalse(os.path.exists(folder.file("shelf.json")))

    def test_the_shelf_is_not_saved_when_the_model_cannot_be_written(self):
        folder = toy_folder(self)
        os.makedirs(folder.file("ad-model.json"))  # a folder in the way
        code, _ = run(folder, "--min-episodes", "2")
        self.assertEqual(code, 2)
        self.assertFalse(os.path.exists(folder.file("shelf.json")))


class RepeatedEpisodeTests(unittest.TestCase):
    def test_an_episode_that_repeats_a_shelf_episode_is_left_out_and_counted(self):
        folder = Folder(self)
        for n in range(3):
            folder.add("https://a.test/feed", n)
        shelved = folder.add("https://a.test/feed", 50)
        again = folder.add("http://www.a.test/feed/", 1)
        for one in folder.entries:  # the same episode under two spellings of its feed
            if one["id"] in (shelved, again):
                one["guid"] = "same"
        folder.save()
        code, said = run(folder, "--min-episodes", "3")
        self.assertEqual(code, 0, said)
        self.assertIn("Left 1 episode out of training because it is the same as one on the shelf.",
                      said)
        self.assertEqual(folder.read("shelf.json")["episodes"], [shelved])
        self.assertEqual(folder.read("ad-model.json")["trained"]["episodes"], 3)

    def test_nothing_is_said_when_nothing_repeats(self):
        folder = toy_folder(self)
        _, said = run(folder, "--min-episodes", "2")
        self.assertFalse([s for s in said if s.startswith("Left ")])


class RunTests(unittest.TestCase):
    def test_too_little_data_writes_nothing_and_exits_zero(self):
        folder = toy_folder(self, 4)
        code, said = run(folder)
        self.assertEqual(code, 0)
        self.assertFalse(os.path.exists(folder.file("ad-model.json")))
        self.assertEqual(len(said), 1)
        self.assertIn("20", said[0])

    def test_min_episodes_is_not_counting_the_shelf(self):
        folder = Folder(self)
        for n in range(3):
            folder.add("a", n)
        code, _ = run(folder, "--min-episodes", "3")
        self.assertEqual(code, 0)
        self.assertFalse(os.path.exists(folder.file("ad-model.json")))

    def test_a_damaged_label_is_skipped_and_the_rest_trains(self):
        folder = toy_folder(self, 6)
        with open(folder.file("labels/%s.json" % folder.entries[0]["id"]), "w") as f:
            f.write("[")
        code, said = run(folder, "--min-episodes", "3")
        self.assertEqual(code, 0)
        self.assertEqual(len([s for s in said if "Skipping" in s]), 1)
        self.assertEqual(folder.read("ad-model.json")["trained"]["episodes"] +
                         folder.read("ad-model.json")["trained"]["shelf"], 5)

    def test_a_different_labels_folder(self):
        folder = toy_folder(self, 6)
        os.rename(folder.file("labels"), folder.file("more"))
        code, _ = run(folder, "--min-episodes", "3", "--labels", "more")
        self.assertEqual(code, 0)
        self.assertTrue(os.path.exists(folder.file("ad-model.json")))

    def test_the_closing_sentence_names_the_file_and_the_buckets(self):
        folder = toy_folder(self)
        _, said = run(folder, "--min-episodes", "3")
        model = folder.read("ad-model.json")
        self.assertIn(folder.file("ad-model.json"), said[-1])
        self.assertIn(str(len(model["weights"])), said[-1])

    def test_no_episodes_file_is_a_setup_problem(self):
        folder = Folder(self)
        code, said = run(folder)
        self.assertEqual(code, 2)
        self.assertEqual(len(said), 1)

    def test_a_damaged_episodes_file_is_a_setup_problem(self):
        folder = Folder(self)
        with open(folder.file("episodes.json"), "w") as f:
            f.write("{")
        self.assertEqual(run(folder)[0], 2)
        folder.entries = [{"id": "nope"}]
        folder.save()
        self.assertEqual(run(folder)[0], 2)

    def test_an_unreadable_folder_is_a_setup_problem(self):
        said = []
        code = train.main(["--folder", "/nonexistent/folder"], say=said.append)
        self.assertEqual(code, 2)

    def test_bad_arguments_exit_two(self):
        folder = toy_folder(self)
        for args in (["--epochs", "0"], ["--epochs", "x"], ["--seed", "x"], ["--bogus"],
                     ["--min-episodes", "-1"]):
            with contextlib.redirect_stderr(io.StringIO()):
                self.assertEqual(run(folder, *args)[0], 2, args)


if __name__ == "__main__":
    unittest.main()
