"""Tests for sporc_sample.py (a small sample of the SPoRC public transcripts for the teaching folder):
no network. The parts that read parquet files run only where pyarrow is installed (the Mac's
sample launcher installs it). Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import json
import os
import shutil
import tempfile
import unittest

import sporc_sample as sporc
import teach_label as label
import teach_segments as seg
import teach_store as store
from teach_testing import answer

try:
    import pyarrow as pa
    import pyarrow.parquet as pq
except ImportError:  # the sample launcher installs it on the Mac
    pa = pq = None


def row(number, podcast="p1", language="en", seconds=3600.0):
    return {"episode_id": "e%03d" % number, "podcast_id": podcast, "ep_title": "Episode %d" % number,
            "mp3_url": "https://a.example/%d.mp3" % number, "duration_seconds": seconds,
            "language": language, "category1": "news", "episode_date": "1700000000000"}


class ChooseTests(unittest.TestCase):
    def test_only_english_episodes_of_a_sensible_length_that_have_turns(self):
        rows = [row(1), row(2, language="es"), row(3, seconds=300.0), row(4, seconds=99999.0), row(5)]
        picked = sporc.choose_episodes(rows, {"e001", "e002", "e003", "e004"}, count=10)
        self.assertEqual([r["episode_id"] for r in picked], ["e001"])

    def test_spreads_over_shows_before_a_show_gets_a_second_episode(self):
        rows = [row(n, podcast="a") for n in range(1, 6)] + [row(n, podcast="b") for n in range(6, 9)]
        available = {r["episode_id"] for r in rows}
        picked = sporc.choose_episodes(rows, available, count=2)
        self.assertEqual({r["podcast_id"] for r in picked}, {"a", "b"})

    def test_a_show_gives_at_most_per_podcast_episodes(self):
        rows = [row(n, podcast="a") for n in range(1, 8)]
        picked = sporc.choose_episodes(rows, {r["episode_id"] for r in rows}, count=5, per_podcast=2)
        self.assertEqual(len(picked), 2)

    def test_the_choice_is_the_same_every_time(self):
        rows = [row(n, podcast="p%d" % (n % 4)) for n in range(40)]
        available = {r["episode_id"] for r in rows}
        first = sporc.choose_episodes(rows, available, count=6)
        self.assertEqual(first, sporc.choose_episodes(list(reversed(rows)), available, count=6))


class LinesTests(unittest.TestCase):
    def turn(self, number, text, start, end):
        return {"turn_count": number, "turn_text": text, "start_time": start, "end_time": end}

    def test_splits_a_turn_into_sentences_with_times_inside_it(self):
        lines = sporc.lines_from_turns([self.turn(0, "One two. Three four five six! Seven?", 10.0, 22.0)])
        self.assertEqual(len(lines), 3)
        self.assertTrue(lines[0].startswith("[00:00:10.0] One two."))
        times = [seg.LINE.match(line) for line in lines]
        self.assertTrue(all(times))
        seconds = [int(m.group(1)) * 3600 + int(m.group(2)) * 60 + float(m.group(3)) for m in times]
        self.assertEqual(seconds, sorted(seconds))
        self.assertTrue(10.0 <= seconds[-1] < 22.0)

    def test_turns_are_put_in_order_and_empty_ones_dropped(self):
        lines = sporc.lines_from_turns([self.turn(1, "Second.", 5.0, 6.0), self.turn(0, "First.", 0.0, 1.0),
                                        self.turn(2, "   ", 6.0, 7.0), self.turn(3, None, 7.0, 8.0)])
        self.assertEqual(len(lines), 2)
        self.assertIn("First.", lines[0])

    def test_hours_and_rounding_never_make_sixty_seconds(self):
        line = sporc.lines_from_turns([self.turn(0, "Late.", 3659.97, 3661.0)])[0]
        self.assertTrue(line.startswith("[01:01:00.0]"), line)

    def test_a_turn_with_a_bad_time_is_kept_at_the_last_good_time(self):
        lines = sporc.lines_from_turns([self.turn(0, "A.", 4.0, 5.0), self.turn(1, "B.", None, None)])
        self.assertEqual(len(lines), 2)
        self.assertTrue(lines[1].startswith("[00:00:05.0]"))


class FolderTests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.folder, ignore_errors=True)

    def test_writes_transcripts_and_a_list_the_marking_step_accepts(self):
        rows = [row(1), row(2, podcast="p2")]
        turns = {"e001": ["[00:00:01.0] Hello there."], "e002": ["[00:00:02.0] Brought to you by Acme."]}
        sporc.write_folder(self.folder, rows, turns)
        entries = store.load_manifest(self.folder)
        self.assertEqual(len(entries), 2)
        for entry in entries:
            store.check_entry(entry)
            self.assertIsNone(entry["file"])
            self.assertEqual(entry["host"], "sporc")
            path = os.path.join(self.folder, "transcripts", entry["id"] + ".txt")
            with open(path, encoding="utf-8") as handle:
                self.assertTrue(seg.LINE.match(handle.readline()))
        self.assertTrue(os.path.exists(os.path.join(self.folder, "SOURCE.txt")))

    def test_the_source_note_says_the_terms(self):
        sporc.write_folder(self.folder, [row(1)], {"e001": ["[00:00:01.0] Hi."]})
        with open(os.path.join(self.folder, "SOURCE.txt"), encoding="utf-8") as handle:
            note = handle.read()
        self.assertIn("research", note.lower())
        self.assertIn("never commit", note.lower())

    def test_an_episode_without_turns_is_left_out(self):
        sporc.write_folder(self.folder, [row(1), row(2)], {"e001": ["[00:00:01.0] Hi."], "e002": []})
        self.assertEqual(len(store.load_manifest(self.folder)), 1)

    def test_an_unchanged_transcript_is_not_written_again(self):
        sporc.write_folder(self.folder, [row(1)], {"e001": ["[00:00:01.0] Hi."]})
        path = os.path.join(self.folder, "transcripts", store.load_manifest(self.folder)[0]["id"] + ".txt")
        os.utime(path, (1000.0, 1000.0))
        sporc.write_folder(self.folder, [row(1), row(2, podcast="p2")],
                           {"e001": ["[00:00:01.0] Hi."], "e002": ["[00:00:02.0] New."]})
        self.assertEqual(os.stat(path).st_mtime, 1000.0)
        self.assertEqual(len(store.load_manifest(self.folder)), 2)

    def test_a_changed_transcript_is_written_again(self):
        sporc.write_folder(self.folder, [row(1)], {"e001": ["[00:00:01.0] Hi."]})
        path = os.path.join(self.folder, "transcripts", store.load_manifest(self.folder)[0]["id"] + ".txt")
        sporc.write_folder(self.folder, [row(1)], {"e001": ["[00:00:01.0] Hello again."]})
        with open(path, encoding="utf-8") as handle:
            self.assertIn("Hello again.", handle.read())

    def test_the_same_episode_gets_the_same_id(self):
        sporc.write_folder(self.folder, [row(1)], {"e001": ["[00:00:01.0] Hi."]})
        first = store.load_manifest(self.folder)[0]["id"]
        sporc.write_folder(self.folder, [row(1)], {"e001": ["[00:00:01.0] Hi."]})
        self.assertEqual(store.load_manifest(self.folder)[0]["id"], first)


class ReportTests(unittest.TestCase):
    def test_counts_hours_shows_and_ad_phrases(self):
        rows = [row(1, seconds=3600.0), row(2, podcast="p2", seconds=1800.0)]
        turns = {"e001": ["[00:00:01.0] This is brought to you by Acme. Use promo code SHOW."],
                 "e002": ["[00:00:01.0] Plain talk."]}
        text = sporc.build_report(rows, turns)
        self.assertIn("2 episodes", text)
        self.assertIn("1.5 hours", text)
        self.assertIn("2 shows", text)
        self.assertIn("1 of 2 episodes hold a spoken ad phrase", text)


class MarkingTests(unittest.TestCase):
    def test_the_marking_step_accepts_the_folder_this_writes(self):
        folder = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, folder, ignore_errors=True)
        turns = sporc.lines_from_turns([
            {"turn_count": 0, "turn_text": "Welcome back. This episode is brought to you by Acme. Use code SHOW.",
             "start_time": 0.0, "end_time": 12.0},
            {"turn_count": 1, "turn_text": "Now to the news. Nothing happened.", "start_time": 12.0, "end_time": 20.0}])
        sporc.write_folder(folder, [row(1)], {"e001": turns})
        said = []
        result = label.run(folder, "labels", "m", None, None,
                           lambda prompt: {"text": answer((2, 3)), "cost": 0.1}, say=said.append)
        self.assertEqual(result["done"], 1, said)
        with open(os.path.join(folder, "labels", store.load_manifest(folder)[0]["id"] + ".json")) as handle:
            segments = json.load(handle)["segments"]
        self.assertEqual(len(segments), 1)
        self.assertGreater(segments[0]["end"], segments[0]["start"])


@unittest.skipUnless(pq, "pyarrow is not installed")
class ParquetTests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.folder, ignore_errors=True)
        rows = [row(n, podcast="p%d" % (n % 3)) for n in range(1, 13)]
        rows[0]["language"] = "es"
        self.catalog = os.path.join(self.folder, "catalog.parquet")
        pq.write_table(pa.Table.from_pylist(rows), self.catalog)
        turns = []
        for number in range(1, 9):
            for count in range(3):
                turns.append({"episode_id": "e%03d" % number, "podcast_id": "p", "turn_count": count,
                              "turn_text": "Sentence one. Brought to you by Acme turn %d." % count,
                              "start_time": count * 10.0, "end_time": count * 10.0 + 9.0})
        self.turns = os.path.join(self.folder, "turns.parquet")
        pq.write_table(pa.Table.from_pylist(turns), self.turns)

    def test_reads_the_catalog_and_the_turns(self):
        ids = sporc.read_turn_ids(self.turns)
        self.assertEqual(len(ids), 8)
        rows = sporc.read_catalog(self.catalog)
        self.assertNotIn("e001", {r["episode_id"] for r in rows})
        self.assertEqual(len(rows), 11)
        turns = sporc.read_turns(self.turns, {"e002", "e003"})
        self.assertEqual(sorted(turns), ["e002", "e003"])
        self.assertEqual(len(turns["e002"]), 3)

    def test_the_whole_run_writes_a_folder(self):
        out = os.path.join(self.folder, "out")
        names = {"metadata/episode_catalog.parquet": self.catalog, "turns/text/part-0.parquet": self.turns}
        said = []
        code = sporc.run(out, count=4, part=0, fetch=lambda name: names[name],
                         listing=lambda: sorted(names), say=said.append)
        self.assertEqual(code, 0, said)
        entries = store.load_manifest(out)
        self.assertEqual(len(entries), 4)
        self.assertTrue(os.path.exists(os.path.join(out, "SAMPLE-REPORT.txt")))
        with open(os.path.join(out, "SAMPLE-REPORT.txt"), encoding="utf-8") as handle:
            self.assertIn("4 episodes", handle.read())

    def test_a_gated_dataset_gives_a_plain_message(self):
        class Gated(Exception):
            pass

        def refuse(_):
            raise Gated("403 Forbidden: you must accept the conditions")

        said = []
        code = sporc.run(os.path.join(self.folder, "out"), count=4, part=0, fetch=refuse,
                         listing=lambda: ["metadata/episode_catalog.parquet", "turns/text/part-0.parquet"],
                         say=said.append)
        self.assertEqual(code, 2)
        self.assertIn("huggingface.co/datasets/blitt/SPoRC", " ".join(said))


if __name__ == "__main__":
    unittest.main()
