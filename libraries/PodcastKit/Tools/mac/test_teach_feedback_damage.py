"""Tests for what teach_feedback.py does with damaged notes, addresses that are not http or https,
and a notes folder macOS will not let it read. Temporary folders only, no network.
Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import json
import os
import unittest
from unittest import mock

import teach_feedback as feedback
from test_teach_feedback import Setup, note


class DamagedLineTests(Setup):
    def test_a_line_nested_too_deeply_is_a_bad_line_not_a_crash(self):
        deep = '{"a":' * 5000 + "1" + "}" * 5000
        self.assertIsNone(feedback.read_note(deep))
        raw = (json.dumps(note()) + "\n" + deep + "\n").encode("utf-8")
        self.put(self.cloud, None, raw=raw)
        self.assertEqual(self.run_main(), 0)
        self.assertIn("1 line in the notes was not valid", self.text())
        self.assertEqual(len(self.wanted()["episodes"]), 1)

    def test_a_line_over_64_kb_is_skipped(self):
        big = json.dumps(note(title="x" * 70000))
        self.assertIsNone(feedback.read_note(big))
        raw = (big + "\n" + json.dumps(note()) + "\n").encode("utf-8")
        self.put(self.cloud, None, raw=raw)
        self.assertEqual(self.run_main(), 0)
        self.assertIn("1 line in the notes was not valid", self.text())

    def test_a_time_that_is_not_a_finite_number_is_a_bad_line(self):
        plain = json.dumps(note())
        for value in ("NaN", "Infinity", "-Infinity", "1e999", "1" + "0" * 400):
            for field, old in (("at", "1000"), ("start", "10.0")):
                line = plain.replace('"%s": %s' % (field, old), '"%s": %s' % (field, value), 1)
                self.assertNotEqual(line, plain)
                self.assertIsNone(feedback.read_note(line), (field, value))
        end = plain.replace('"end": null', '"end": Infinity', 1)
        self.assertNotEqual(end, plain)
        self.assertIsNone(feedback.read_note(end))

    def test_a_notes_file_over_8_mb_is_refused_with_a_plain_message(self):
        path = self.put(self.cloud, [note()])
        with open(path, "ab") as f:
            f.write(b"\n" * (8 * 1024 * 1024))
        self.assertEqual(self.run_main(), 2)
        self.assertIn("bigger than 8 MB", self.text())
        self.assertFalse(os.path.exists(os.path.join(self.teaching, "wanted.json")))


class AddressTests(Setup):
    def test_only_http_and_https_addresses_are_accepted(self):
        for good in ("https://a.test/feed", "HTTP://a.test/feed"):
            self.assertIsNotNone(feedback.read_note(json.dumps(note(feed=good))), good)
        for bad in ("file:///etc/hosts", "ftp://a.test/f", "data:text/plain,hi", "feed://a.test/f",
                    "a.test/feed"):
            self.assertIsNone(feedback.read_note(json.dumps(note(feed=bad))), bad)
            self.assertIsNone(feedback.read_note(json.dumps(note(address=bad))), bad)

    def test_a_note_with_no_audio_address_is_still_fine(self):
        self.assertIsNotNone(feedback.read_note(json.dumps(note(address="", guid="g"))))

    def test_such_notes_are_counted_and_skipped(self):
        self.put(self.cloud, [note(feed="file:///x"), note(guid="ok")])
        self.assertEqual(self.run_main(), 0)
        self.assertEqual([e["guid"] for e in self.wanted()["episodes"]], ["ok"])
        self.assertIn("1 line in the notes was not valid", self.text())


class PermissionTests(Setup):
    def deny(self, *names):
        real = os.stat

        def stat(path, *a, **k):
            if any(name in str(path) for name in names):
                raise PermissionError(1, "Operation not permitted")
            return real(path, *a, **k)

        return mock.patch.object(feedback.os, "stat", stat)

    def test_a_denied_notes_folder_says_so_and_not_that_there_are_no_notes(self):
        self.put(self.cloud, [note()])
        with self.deny("cloud"):
            self.assertEqual(self.run_main(), 2)
        self.assertIn("permission problem", self.text())
        self.assertIn("Full Disk Access", self.text())
        self.assertNotIn("has sent no notes yet", self.text())
        self.assertFalse(os.path.exists(self.teaching))

    def test_the_macs_copy_is_used_with_a_warning_when_the_cloud_is_denied(self):
        self.put(self.cloud, [note(guid="cloud")])
        self.put(self.mac, [note(guid="mac")])
        with self.deny("cloud"):
            self.assertEqual(self.run_main(), 0)
        self.assertIn("permission problem", self.text())
        self.assertEqual([e["guid"] for e in self.wanted()["episodes"]], ["mac"])

    def test_a_denied_notes_option_says_so(self):
        path = self.put(self.cloud, [note()])
        with self.deny("cloud"):
            self.assertEqual(self.run_main("--notes", path), 2)
        self.assertIn("permission problem", self.text())


if __name__ == "__main__":
    unittest.main()
