"""Tests for teach_taps.py: how a note of a prepared episode becomes a short line, the 20-line cap per
show (the newest kept), that new notes are read once, that the lines reach the prompt of the marking
and no other prompt, that an unreadable notes file is skipped with a line, and that the file of lines
is in .gitignore. All words are made up.
Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import json
import os
import unittest

import teach_label as label
import teach_segments as seg
import teach_taps as taps
from teach_testing import answer, entry
import teach_store as store
from test_teach_feedback import Setup, note

FEED = "https://a.example/feed"
WORDS = ("[00:00:05.0] Welcome to the made up show.\n[00:00:10.0] Today we talk about gardens.\n"
         "[00:00:20.0] This part is brought to you by Examplesoap.\n"
         "[00:00:30.0] Use the code GARDEN for ten percent off.\n"
         "[00:00:40.0] Now back to the garden.\n[00:00:50.0] Roses need sun.\n")


class TapsSetup(Setup):
    def setUp(self):
        super().setUp()
        os.makedirs(self.teaching)

    def episode(self, guid="g1", feed=FEED, show="Garden Show"):
        """Episode 1 of episodes.json, spelled as the phone's notes spell it, with a transcript."""
        item = entry(1, feed=feed, show=show, guid=guid, address="https://a.example/1.mp3")
        store.save_manifest(self.teaching, [item])
        os.makedirs(os.path.join(self.teaching, "transcripts"), exist_ok=True)
        with open(os.path.join(self.teaching, "transcripts", item["id"] + ".txt"), "w") as f:
            f.write(WORDS)
        return item

    def learn(self, notes=None, **more):
        if notes is not None:
            self.put(self.cloud, notes)
        return taps.learn(self.teaching, self.said.append, lambda: [self.mac, self.cloud])

    def stored(self):
        with open(os.path.join(self.teaching, taps.FILE)) as f:
            return json.load(f)


class LineTests(unittest.TestCase):
    LINES = seg.read_transcript(WORDS)

    def line(self, what, start, end=None):
        return taps.line_for({"what": what, "start": start, "end": end}, self.LINES)

    def test_an_undo_gives_the_first_and_the_last_words_of_the_skip(self):
        text = self.line("undone", 20.0, 40.0)
        self.assertIn("Undo of a skip from 0:20 to 0:40", text)
        self.assertIn('began with "This part is brought to you by Examplesoap. Use the code GARDEN', text)
        self.assertIn('ended with "Use the code GARDEN for ten percent off. Now back to the garden."', text)

    def test_a_skip_ad_where_nothing_was_marked_gives_the_words_there(self):
        text = self.line("missed", 20.0)
        self.assertTrue(text.startswith("Skip ad pressed at 0:20 where nothing was marked"), text)
        self.assertIn('"This part is brought to you by Examplesoap.', text)

    def test_going_back_into_a_skip_says_it_went_too_far(self):
        text = self.line("trimmed", 20.0, 30.0)
        self.assertIn("went too far", text)
        self.assertIn("0:20 to 0:30", text)

    def test_other_notes_and_notes_with_no_transcript_make_no_line(self):
        for what in ("skipped", "confirmed", "denied"):
            self.assertIsNone(self.line(what, 20.0, 30.0), what)
        self.assertIsNone(taps.line_for({"what": "undone", "start": 1, "end": 2}, []))

    def test_a_long_stretch_of_words_is_cut_short(self):
        long = [(0.0, " ".join("w%d" % n for n in range(100)))]
        text = taps.line_for({"what": "undone", "start": 0.0, "end": 1.0}, long)
        self.assertLess(len(text), 400)

    def test_a_time_over_an_hour_is_written_with_the_hour(self):
        self.assertEqual(taps.clock(3725), "1:02:05")
        self.assertEqual(taps.clock(65), "1:05")


class LearnTests(TapsSetup):
    def test_notes_of_a_prepared_episode_become_lines_of_its_show_and_the_log_counts_them(self):
        self.episode()
        notes = [note("undone", at=10, by="prepared", start=20.0, end=40.0),
                 note("missed", at=11, by="prepared", start=20.0),
                 note("undone", at=12, by="own-sound", start=20.0, end=40.0),  # not a prepared copy
                 note("skipped", at=13, by="prepared", start=20.0, end=40.0)]
        self.assertEqual(self.learn(notes), 0)
        data = self.stored()
        key = list(data["shows"])[0]
        self.assertEqual(data["shows"][key]["show"], "Garden Show")
        self.assertEqual(len(data["shows"][key]["lines"]), 2)
        self.assertEqual(data["readThrough"], 13)
        self.assertIn("Taps: read 4 notes from the phone (4 new, 3 of those by prepared episodes); "
                      "2 lines made", self.text())

    def test_a_note_is_read_once(self):
        self.episode()
        notes = [note("undone", at=10, by="prepared", start=20.0, end=40.0)]
        self.learn(notes)
        self.learn()
        self.assertEqual(len(list(self.stored()["shows"].values())[0]["lines"]), 1)
        self.assertIn("(0 new, 0 of those", self.said[-1])
        notes.append(note("missed", at=20, by="prepared", start=30.0))
        self.learn(notes)
        self.assertEqual(len(list(self.stored()["shows"].values())[0]["lines"]), 2)

    def test_at_most_20_lines_are_kept_per_show_and_the_newest_stay(self):
        self.episode()
        notes = [note("missed", at=100 + n, by="prepared", start=5.0 + n) for n in range(25)]
        self.learn(notes)
        lines = list(self.stored()["shows"].values())[0]["lines"]
        self.assertEqual(len(lines), 20)
        self.assertEqual([one["at"] for one in lines], list(range(105, 125)))

    def test_the_cap_holds_across_runs(self):
        self.episode()
        notes = [note("missed", at=100 + n, by="prepared", start=5.0) for n in range(15)]
        self.learn(notes)
        notes += [note("missed", at=200 + n, by="prepared", start=5.0) for n in range(15)]
        self.learn(notes)
        lines = list(self.stored()["shows"].values())[0]["lines"]
        self.assertEqual((len(lines), lines[0]["at"], lines[-1]["at"]), (20, 110, 214))

    def test_each_show_has_its_own_lines(self):
        self.episode()
        notes = [note("missed", at=1, by="prepared", start=5.0),
                 note("missed", at=2, by="prepared", start=5.0, feed="https://b.example/feed", guid="x")]
        self.learn(notes)
        self.assertEqual(len(self.stored()["shows"]), 1)  # the other show is not in episodes.json

    def test_a_notes_file_that_cannot_be_read_is_skipped_with_a_line(self):
        self.episode()
        # A folder where the file should be: stat works, reading it fails like an iCloud file that
        # is not downloaded yet.
        os.makedirs(os.path.join(self.cloud, "Podcasts", "phone-notes.jsonl"))
        self.assertEqual(self.learn(), 0)
        self.assertIn("could not be read", self.text())
        self.assertFalse(os.path.exists(os.path.join(self.teaching, taps.FILE)))

    def test_no_notes_file_is_not_an_error(self):
        self.assertEqual(self.learn(), 0)
        self.assertIn("no phone notes to read yet", self.text())

    def test_a_damaged_lines_file_starts_again(self):
        self.episode()
        with open(os.path.join(self.teaching, taps.FILE), "w") as f:
            f.write("{nope")
        self.assertEqual(self.learn([note("missed", at=1, by="prepared", start=5.0)]), 0)
        self.assertEqual(len(list(self.stored()["shows"].values())[0]["lines"]), 1)

    def test_a_note_for_an_episode_without_a_transcript_is_counted_as_left_out(self):
        item = self.episode()
        os.remove(os.path.join(self.teaching, "transcripts", item["id"] + ".txt"))
        self.learn([note("missed", at=1, by="prepared", start=5.0)])
        self.assertIn("0 lines made, 1 left out", self.text())

    def test_the_command_line_reads_the_folder(self):
        self.episode()
        self.put(self.cloud, [note("missed", at=1, by="prepared", start=5.0)])
        code = taps.main(["learn", "--folder", self.teaching], say=self.said.append,
                         defaults=lambda: [self.mac, self.cloud])
        self.assertEqual(code, 0)
        self.assertTrue(os.path.exists(os.path.join(self.teaching, taps.FILE)))


class PromptTests(TapsSetup):
    def test_the_lines_of_a_show_are_in_the_prompt_of_its_next_episodes(self):
        item = self.episode()
        self.learn([note("undone", at=1, by="prepared", start=20.0, end=40.0)])
        asked = []

        def ask(prompt):
            asked.append(prompt)
            return {"text": answer((1, 1)), "cost": 0.0}

        guidance = taps.guidance(self.teaching)
        result = label.run(self.teaching, "labels", "m", None, None, ask, say=lambda t: None,
                           only={item["id"]}, taps=guidance)
        self.assertEqual(result["done"], 1, result)
        self.assertIn("What the listener's taps showed", asked[0])
        self.assertIn("- Undo of a skip from 0:20 to 0:40", asked[0])
        self.assertIn("not rules", asked[0])

    def test_without_lines_the_prompt_is_exactly_as_before(self):
        lines = seg.read_transcript(WORDS)
        self.assertEqual(seg.prompt("S", "T", lines, 1, 6), seg.prompt("S", "T", lines, 1, 6, ()))
        self.assertNotIn("taps", seg.prompt("S", "T", lines, 1, 6))

    def test_another_shows_lines_do_not_reach_the_prompt(self):
        item = self.episode()
        asked = []
        label.run(self.teaching, "labels", "m", None, None,
                  lambda p: asked.append(p) or {"text": answer((1, 1)), "cost": 0.0},
                  say=lambda t: None, only={item["id"]},
                  taps={"https://other.example/feed": ["Undo of a skip from 1:00 to 2:00."]})
        self.assertNotIn("Undo of a skip", asked[0])


class CommandTests(TapsSetup):
    """teach_label.py main: only the preparing run (--only-ahead) hands the lines to the prompt."""

    def run_marking(self, *options):
        import shutil
        import tempfile
        from teach_testing import FakeRunner, printed
        home = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, home, True)
        os.makedirs(os.path.join(home, "bin"))
        claude = os.path.join(home, "bin", "claude")
        with open(claude, "w") as f:
            f.write("#!/bin/sh\n")
        os.chmod(claude, 0o755)
        runner = FakeRunner(stdout=printed(answer((1, 2))))
        code = label.main(["--folder", self.teaching, "--yes"] + list(options), ask_person=lambda q: "yes",
                          runner=runner, environment={"HOME": home, "PATH": os.path.join(home, "bin")},
                          say=self.said.append, extra_folders=())
        return code, runner

    def prepare(self):
        import teach_ahead_set as ahead
        item = self.episode()
        ahead.add_ahead(self.teaching, [{"id": item["id"], "feed": item["feed"], "guid": "g1",
                                         "title": "T", "picked": 1}])
        self.learn([note("undone", at=1, by="prepared", start=20.0, end=40.0)])

    def test_the_preparing_run_puts_the_lines_in_the_prompt(self):
        self.prepare()
        code, runner = self.run_marking("--only-ahead")
        self.assertEqual(code, 0, self.said)
        self.assertIn("Undo of a skip from 0:20 to 0:40", runner.calls[0][1]["input"])

    def test_a_run_for_the_teaching_set_does_not(self):
        self.prepare()
        code, runner = self.run_marking()
        self.assertEqual(code, 0, self.said)
        self.assertNotIn("Undo of a skip", runner.calls[0][1]["input"])


class StorageTests(unittest.TestCase):
    def test_the_file_of_lines_is_listed_in_gitignore(self):
        here = os.path.dirname(os.path.abspath(__file__))
        with open(os.path.join(here, ".gitignore")) as f:
            self.assertIn(taps.FILE, f.read().split())


if __name__ == "__main__":
    unittest.main()
