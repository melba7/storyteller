"""Tests for teach_library.py: which stretches are candidates, when two are the same ad, the
grouping, the fields of an entry, the order and limits, damaged inputs and the written file. No
network. Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import json
import os
import shutil
import tempfile
import unittest

import teach_label
import teach_library as library


# MARK: Helpers

def word_list(prefix, count):
    """`count` distinct words that start with `prefix`."""
    return ["%s%d" % (prefix, i) for i in range(count)]


def entry(episode, feed="f1", show="Show"):
    return {"id": episode, "feed": feed, "show": show, "guid": "g" + episode,
            "title": "T" + episode, "published": None, "seconds": None,
            "address": "https://example.com/" + episode, "size": None, "file": None,
            "bytes": 0, "sha256": None, "host": None, "error": None}


def segment(first, last, start=0.0, end=60.0, sort="sponsor", who="Acme", confidence="high"):
    return {"first": first, "last": last, "start": start, "end": end, "sort": sort, "who": who,
            "delivery": "host", "confidence": confidence, "why": ""}


class Folder(unittest.TestCase):
    """A temporary teaching folder with helpers to fill it."""

    def setUp(self):
        self.folder = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.folder, ignore_errors=True)
        self.entries = []
        self.messages = []

    def say(self, text):
        self.messages.append(text)

    def episode(self, episode, lines, segments, feed="f1", labels="labels"):
        """Adds an episode: `lines` is a list of text lines, `segments` the label's segments."""
        self.entries.append(entry(episode, feed))
        os.makedirs(os.path.join(self.folder, "transcripts"), exist_ok=True)
        with open(os.path.join(self.folder, "transcripts", episode + ".txt"), "w") as f:
            for number, text in enumerate(lines):
                f.write("[00:%02d:%02d.0] %s\n" % (number // 60, number % 60, text))
        os.makedirs(os.path.join(self.folder, labels), exist_ok=True)
        with open(os.path.join(self.folder, labels, episode + ".json"), "w") as f:
            json.dump({"version": 1, "episode": episode, "feed": feed, "show": "Show",
                       "lines": len(lines), "length": 0, "segments": segments}, f)
        with open(os.path.join(self.folder, "episodes.json"), "w") as f:
            json.dump({"version": 1, "writtenAt": 0, "episodes": self.entries}, f)

    def ad(self, episode, words, feed="f1", **kw):
        """An episode that is one single stretch of `words` (a list of words, one line)."""
        self.episode(episode, [" ".join(words)], [segment(1, 1, **kw)], feed=feed)

    def run_main(self, *arguments, **kw):
        return library.main(["--folder", self.folder] + list(arguments), say=self.say, **kw)

    def written(self):
        with open(os.path.join(self.folder, "ad-library.json")) as f:
            return json.load(f)


# MARK: Pure parts

class WordTests(unittest.TestCase):
    def test_words_keep_only_letters_and_digits_in_lower_case(self):
        self.assertEqual(library.normalise("Hello, World-1!"), "helloworld1")
        self.assertEqual(library.normalise("--"), "")

    def test_words_of_a_text_drop_empty_words_and_stop_at_the_limit(self):
        text = "One -- two, THREE " + " ".join(word_list("x", 700))
        words = library.words_of(text)
        self.assertEqual(len(words), 600)
        self.assertEqual(words[:3], ["One", "two,", "THREE"])

    def test_runs_are_the_three_word_runs(self):
        self.assertEqual(library.runs(["a", "b", "c", "d"]),
                         {("a", "b", "c"), ("b", "c", "d")})
        self.assertEqual(library.runs(["a", "b"]), set())


class SameAdTests(unittest.TestCase):
    def runs_of(self, count):
        """The runs of `count` distinct words (count - 2 runs)."""
        return library.runs(word_list("w", count))

    def test_the_same_text_is_the_same_ad(self):
        self.assertTrue(library.same_ad(self.runs_of(30), self.runs_of(30)))

    def test_exactly_sixty_percent_of_the_shorter_one_is_enough(self):
        small = self.runs_of(12)  # 10 runs
        other = set(sorted(small)[:6]) | {("o", "t", "h%d" % i) for i in range(20)}
        self.assertEqual(len(small & other), 6)
        self.assertTrue(library.same_ad(small, other))
        self.assertTrue(library.same_ad(other, small))

    def test_just_below_sixty_percent_is_not(self):
        small = self.runs_of(12)  # 10 runs
        other = set(sorted(small)[:5]) | {("o", "t", "h%d" % i) for i in range(20)}
        self.assertFalse(library.same_ad(small, other))
        self.assertFalse(library.same_ad(other, small))

    def test_nothing_in_common_or_nothing_at_all(self):
        self.assertFalse(library.same_ad(self.runs_of(30), library.runs(word_list("z", 30))))
        self.assertFalse(library.same_ad(set(), set()))


# MARK: Candidates

class CandidateTests(Folder):
    def candidates(self):
        return library.read_candidates(self.folder, "labels", self.say)[0]

    def test_a_high_confidence_stretch_of_enough_words_and_seconds(self):
        self.ad("aaaaaaaaaaaa", word_list("w", 25), start=0, end=8)
        self.assertEqual(len(self.candidates()), 1)

    def test_confidence_must_be_high_or_medium(self):
        self.ad("aaaaaaaaaaaa", word_list("w", 40), confidence="medium")
        self.assertEqual(len(self.candidates()), 1)
        self.ad("bbbbbbbbbbbb", word_list("w", 40), confidence="low")
        self.assertEqual(len(self.candidates()), 1)

    def test_a_long_ad_keeps_up_to_600_words(self):
        self.ad("aaaaaaaaaaaa", word_list("w", 700), end=300)
        self.assertEqual(len(self.candidates()[0]["words"]), 600)
        self.assertEqual(self.candidates()[0]["words"][-1], "w599")

    def test_at_least_25_words(self):
        self.ad("aaaaaaaaaaaa", word_list("w", 24))
        self.assertEqual(self.candidates(), [])

    def test_words_that_are_only_punctuation_do_not_count(self):
        self.ad("aaaaaaaaaaaa", word_list("w", 20) + ["-"] * 10)
        self.assertEqual(self.candidates(), [])

    def test_length_from_8_to_300_seconds(self):
        words = word_list("w", 30)
        for name, start, end in (("a", 0, 7.9), ("b", 0, 8), ("c", 10, 310), ("d", 10, 310.1)):
            self.ad(name * 12, words, start=start, end=end)
        self.assertEqual([c["episode"] for c in self.candidates()], ["b" * 12, "c" * 12])

    def test_the_text_joins_the_lines_first_to_last(self):
        self.episode("aaaaaaaaaaaa", ["skip me"] + ["line one"] * 13 + ["line two"] * 13,
                     [segment(2, 27)])
        found = self.candidates()
        self.assertEqual(len(found), 1)
        self.assertEqual(len(found[0]["words"]), 52)
        self.assertEqual(found[0]["length"], 60.0)
        self.assertNotIn("skip", found[0]["words"])

    def test_candidates_come_in_manifest_then_segment_order(self):
        words = word_list("w", 30)
        self.ad("bbbbbbbbbbbb", words, who="first")
        self.episode("aaaaaaaaaaaa", [" ".join(words)] * 2,
                     [segment(1, 1, who="second"), segment(2, 2, who="third")])
        self.assertEqual([c["who"] for c in self.candidates()], ["first", "second", "third"])

    def test_an_episode_without_a_label_is_not_mentioned(self):
        self.ad("aaaaaaaaaaaa", word_list("w", 30))
        self.entries.append(entry("cccccccccccc"))
        with open(os.path.join(self.folder, "episodes.json"), "w") as f:
            json.dump({"version": 1, "writtenAt": 0, "episodes": self.entries}, f)
        found, labels = library.read_candidates(self.folder, "labels", self.say)
        self.assertEqual((len(found), labels), (1, 1))
        self.assertEqual(self.messages, [])

    def test_a_label_that_cannot_be_read_is_skipped_with_one_line(self):
        self.ad("aaaaaaaaaaaa", word_list("w", 30))
        with open(os.path.join(self.folder, "labels", "aaaaaaaaaaaa.json"), "w") as f:
            f.write("{nope")
        self.ad("bbbbbbbbbbbb", word_list("w", 30))
        found, labels = library.read_candidates(self.folder, "labels", self.say)
        self.assertEqual([c["episode"] for c in found], ["b" * 12])
        self.assertEqual(labels, 1)
        self.assertEqual(len(self.messages), 1)
        self.assertIn("aaaaaaaaaaaa", self.messages[0])

    def test_a_label_of_the_wrong_shape_is_skipped_with_one_line(self):
        self.ad("aaaaaaaaaaaa", word_list("w", 30))
        with open(os.path.join(self.folder, "labels", "aaaaaaaaaaaa.json"), "w") as f:
            json.dump({"version": 1, "segments": "no"}, f)
        self.assertEqual(self.candidates(), [])
        self.assertEqual(len(self.messages), 1)

    def test_a_missing_transcript_skips_the_label_with_one_line(self):
        self.ad("aaaaaaaaaaaa", word_list("w", 30))
        os.remove(os.path.join(self.folder, "transcripts", "aaaaaaaaaaaa.txt"))
        self.assertEqual(self.candidates(), [])
        self.assertEqual(len(self.messages), 1)

    def test_a_segment_outside_the_transcript_or_without_times_is_ignored(self):
        self.episode("aaaaaaaaaaaa", [" ".join(word_list("w", 30))],
                     [segment(1, 5), {"first": 1, "last": 1, "sort": "sponsor",
                                      "confidence": "high"}, "text", segment(1, 1)])
        self.assertEqual(len(self.candidates()), 1)

    def test_another_labels_folder(self):
        self.episode("aaaaaaaaaaaa", [" ".join(word_list("w", 30))], [segment(1, 1)],
                     labels="more")
        self.assertEqual(self.candidates(), [])
        self.assertEqual(len(library.read_candidates(self.folder, "more", self.say)[0]), 1)


# MARK: Groups and entries

def candidate(episode, words, feed="f1", sort="sponsor", who="Acme", length=30.0):
    return {"episode": episode, "feed": feed, "sort": sort, "who": who, "length": length,
            "words": words, "runs": library.runs([library.normalise(w) for w in words])}


class GroupTests(unittest.TestCase):
    def test_a_candidate_joins_the_first_group_it_matches(self):
        a = candidate("e1", word_list("a", 30))
        b = candidate("e2", word_list("b", 30))
        c = candidate("e3", word_list("a", 30))
        d = candidate("e4", word_list("b", 30))
        groups = library.group([a, b, c, d])
        self.assertEqual([[m["episode"] for m in g] for g in groups], [["e1", "e3"], ["e2", "e4"]])

    def test_it_is_compared_with_the_first_member_only(self):
        # b matches a (7 of 10 runs); c matches b but only 4 of a's 10 runs.
        base = word_list("w", 12)
        a = candidate("e1", base)
        b = candidate("e2", base[:9] + word_list("x", 3))
        c = candidate("e3", base[5:] + word_list("y", 5))
        groups = library.group([a, b, c])
        self.assertEqual([[m["episode"] for m in g] for g in groups], [["e1", "e2"], ["e3"]])


class EntryTests(unittest.TestCase):
    def test_fields_of_an_entry(self):
        words = word_list("w", 150)
        members = [candidate("e1", words, sort="sponsor", who="Acme", length=40.04),
                   candidate("e2", words, sort="host_ask", who="", length=50),
                   candidate("e3", words, sort="sponsor", who="Beta", length=45)]
        made = library.make_entry(members)
        self.assertEqual(made["feed"], "f1")
        self.assertEqual(made["scope"], "show")
        self.assertEqual(made["sort"], "sponsor")
        self.assertEqual(made["who"], "Acme")
        self.assertEqual(made["length"], 45)
        self.assertEqual(made["seen"], 3)
        self.assertEqual(made["text"], " ".join(words[:150]))
        self.assertEqual(sorted(made), ["feed", "length", "scope", "seen", "sort", "text", "who"])

    def test_ties_go_to_the_earliest_and_who_ignores_empty_ones(self):
        words = word_list("w", 30)
        members = [candidate("e1", words, sort="host_ask", who=""),
                   candidate("e2", words, sort="sponsor", who="Beta"),
                   candidate("e3", words, sort="sponsor", who="Acme"),
                   candidate("e4", words, sort="host_ask", who="")]
        made = library.make_entry(members)
        self.assertEqual(made["sort"], "host_ask")
        self.assertEqual(made["who"], "Beta")

    def test_who_is_empty_when_all_are_empty(self):
        made = library.make_entry([candidate("e1", word_list("w", 30), who="")])
        self.assertEqual(made["who"], "")

    def test_median_length_rounds_to_one_decimal(self):
        words = word_list("w", 30)
        made = library.make_entry([candidate("e1", words, length=10.0),
                                   candidate("e2", words, length=21.26)])
        self.assertEqual(made["length"], 15.6)

    def test_seen_counts_episodes_not_segments(self):
        words = word_list("w", 30)
        made = library.make_entry([candidate("e1", words), candidate("e1", words),
                                   candidate("e2", words)])
        self.assertEqual(made["seen"], 2)

    def test_scope_is_all_with_two_feeds_and_the_first_feed_is_kept(self):
        words = word_list("w", 30)
        made = library.make_entry([candidate("e1", words, feed="f2"),
                                   candidate("e2", words, feed="f1")])
        self.assertEqual(made["scope"], "all")
        self.assertEqual(made["feed"], "f2")

    def test_text_keeps_the_original_case_and_punctuation(self):
        words = ["Hello,", "World!"] + word_list("w", 30)
        made = library.make_entry([candidate("e1", words)])
        self.assertTrue(made["text"].startswith("Hello, World! w0"))


class OrderTests(unittest.TestCase):
    def groups(self):
        a, b, c = (candidate("e%d" % i, word_list(p, 30)) for i, p in enumerate("abc"))
        extra = candidate("e9", word_list("c", 30))
        return library.group([a, b, c, extra])

    def test_more_seen_first_then_the_order_the_groups_started(self):
        made = library.entries_of(self.groups(), most=10, max_bytes=10 ** 7)
        self.assertEqual([e["text"][:2] for e in made], ["c0", "a0", "b0"])
        self.assertEqual([e["seen"] for e in made], [2, 1, 1])

    def test_most_limits_the_entries(self):
        made = library.entries_of(self.groups(), most=2, max_bytes=10 ** 7)
        self.assertEqual([e["text"][:2] for e in made], ["c0", "a0"])

    def test_the_size_cap_drops_entries_from_the_end(self):
        everything = library.entries_of(self.groups(), most=10, max_bytes=10 ** 7)
        one = len(library.document(everything[:1], 0))
        two = len(library.document(everything[:2], 0))
        self.assertEqual(len(library.entries_of(self.groups(), 10, two)), 2)
        self.assertEqual(len(library.entries_of(self.groups(), 10, two - 1)), 1)
        self.assertEqual(library.entries_of(self.groups(), 10, one - 1), [])


# MARK: Whole run

class MainTests(Folder):
    def test_no_labels_says_so_writes_nothing_and_exits_0(self):
        self.assertEqual(self.run_main(), 0)
        self.assertFalse(os.path.exists(os.path.join(self.folder, "ad-library.json")))
        self.assertTrue(any("No labels yet" in m for m in self.messages))

    def test_the_written_file_and_the_report(self):
        words = word_list("w", 40)
        self.ad("aaaaaaaaaaaa", words, feed="f1", who="Acme", end=40)
        self.ad("bbbbbbbbbbbb", words, feed="f2", who="Acme", end=50)
        self.ad("cccccccccccc", word_list("z", 40), feed="f1", who="Solo")
        self.assertEqual(self.run_main(), 0, self.messages)
        document = self.written()
        self.assertEqual(document["version"], 1)
        self.assertIsInstance(document["writtenAt"], int)
        self.assertEqual([(a["who"], a["seen"], a["scope"]) for a in document["ads"]],
                         [("Acme", 2, "all"), ("Solo", 1, "show")])
        self.assertEqual(document["ads"][0]["length"], 45.0)
        report = "\n".join(self.messages)
        self.assertIn("3 stretches", report)
        self.assertIn("2 different ads", report)
        self.assertIn("1 of them in more than one show", report)
        self.assertIn("Acme", report)
        self.assertEqual([n for n in os.listdir(self.folder) if n.endswith(".part")], [])

    def test_the_score_library_leaves_out_the_shelf_episodes(self):
        words = word_list("w", 40)
        self.ad("aaaaaaaaaaaa", words, feed="f1", who="Acme")
        self.ad("bbbbbbbbbbbb", words, feed="f2", who="Acme")
        self.ad("cccccccccccc", word_list("z", 40), feed="f1", who="OnShelf")
        with open(os.path.join(self.folder, "shelf.json"), "w") as f:
            json.dump({"version": 1, "episodes": ["cccccccccccc"]}, f)
        self.assertEqual(self.run_main(), 0, self.messages)
        self.assertEqual([(a["who"], a["seen"]) for a in self.written()["ads"]],
                         [("Acme", 2), ("OnShelf", 1)])
        with open(os.path.join(self.folder, "ad-library-score.json")) as f:
            scored = json.load(f)
        self.assertEqual(scored["version"], 1)
        self.assertEqual([(a["who"], a["seen"]) for a in scored["ads"]], [("Acme", 2)])

    def test_without_a_shelf_both_libraries_are_the_same(self):
        self.ad("aaaaaaaaaaaa", word_list("w", 40))
        self.run_main()
        with open(os.path.join(self.folder, "ad-library-score.json")) as f:
            self.assertEqual(json.load(f)["ads"], self.written()["ads"])

    def test_a_damaged_shelf_is_a_set_up_problem(self):
        self.ad("aaaaaaaaaaaa", word_list("w", 40))
        with open(os.path.join(self.folder, "shelf.json"), "w") as f:
            f.write("nope")
        self.assertEqual(self.run_main(), 2)

    def test_labels_with_nothing_to_learn_still_write_an_empty_library(self):
        self.ad("aaaaaaaaaaaa", word_list("w", 5))
        self.assertEqual(self.run_main(), 0)
        self.assertEqual(self.written()["ads"], [])

    def test_most_limits_the_file(self):
        for prefix in "abc":
            self.ad(prefix * 12, word_list(prefix, 40))
        self.assertEqual(self.run_main("--most", "2"), 0)
        self.assertEqual(len(self.written()["ads"]), 2)

    def test_the_size_cap_is_applied_to_the_file(self):
        for prefix in "abc":
            self.ad(prefix * 12, word_list(prefix, 40))
        self.assertEqual(self.run_main(max_bytes=500), 0)
        size = os.path.getsize(os.path.join(self.folder, "ad-library.json"))
        self.assertLessEqual(size, 500)
        self.assertEqual(len(self.written()["ads"]), 1)

    def test_the_ten_most_seen_are_listed(self):
        for number in range(12):
            self.ad("%012x" % number, word_list("p%d" % number, 40), who="Ad%d" % number)
        self.run_main()
        listed = [m for m in self.messages if m.startswith("  ")]
        self.assertEqual(len(listed), 10)

    def test_a_missing_episodes_file_gives_no_labels_yet(self):
        self.assertEqual(self.run_main(), 0)

    def test_a_damaged_episodes_file_is_a_set_up_problem(self):
        with open(os.path.join(self.folder, "episodes.json"), "w") as f:
            f.write("{nope")
        self.assertEqual(self.run_main(), 2)
        self.assertEqual(len(self.messages), 1)

    def test_bad_arguments_exit_2(self):
        self.assertEqual(self.run_main("--most", "0"), 2)
        self.assertEqual(self.run_main("--most", "many"), 2)

    def test_a_problem_from_teach_label_is_a_set_up_problem(self):
        original = library.read_candidates

        def broken(*args):
            raise teach_label.Problem("broken")

        library.read_candidates = broken
        self.addCleanup(setattr, library, "read_candidates", original)
        self.assertEqual(self.run_main(), 2)
        self.assertEqual(self.messages, ["broken"])


if __name__ == "__main__":
    unittest.main()
