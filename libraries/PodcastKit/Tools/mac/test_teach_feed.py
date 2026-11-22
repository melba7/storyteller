"""Tests for teach_feed.py: reading a feed from bytes or text (also the usual mistakes in feeds),
choosing the newest episodes and naming the audio file. No network.
Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import codecs
import hashlib
import unittest

import teach_feed as tf
from teach_store import FILE_PATTERN
from teach_testing import dated, feed


class EpisodeIdTests(unittest.TestCase):
    def test_id_is_twelve_hex_digits_of_sha1(self):
        expected = hashlib.sha1("https://a/feed\nguid-1".encode("utf-8")).hexdigest()[:12]
        self.assertEqual(tf.episode_id("https://a/feed", "guid-1", "https://a/x.mp3"), expected)

    def test_address_is_used_without_guid(self):
        expected = hashlib.sha1("f\nhttps://a/x.mp3".encode("utf-8")).hexdigest()[:12]
        self.assertEqual(tf.episode_id("f", "", "https://a/x.mp3"), expected)


class FeedEpisodesTests(unittest.TestCase):
    def test_newest_first_by_date(self):
        xml = feed(dated("Old", 1, "https://a/1.mp3"), dated("New", 9, "https://a/9.mp3"),
                   dated("Mid", 5, "https://a/5.mp3"))
        result = tf.feed_episodes(xml, 2)
        self.assertEqual([e["title"] for e in result], ["New", "Mid"])

    def test_undated_come_after_dated_in_feed_order(self):
        xml = feed(dict(title="U1", address="https://a/u1.mp3"), dated("D", 3, "https://a/d.mp3"),
                   dict(title="U2", address="https://a/u2.mp3"))
        self.assertEqual([e["title"] for e in tf.feed_episodes(xml, 5)], ["D", "U1", "U2"])

    def test_each_address_once_and_no_audio_skipped(self):
        xml = feed(dated("A", 5, "https://a/x.mp3"), dated("B", 4, "https://a/x.mp3"),
                   dict(title="Text", date="Mon, 09 Jan 2024 10:00:00 +0000"),
                   dated("FTP", 8, "ftp://a/f.mp3"), dated("C", 3, "https://a/c.mp3"))
        self.assertEqual([e["title"] for e in tf.feed_episodes(xml, 5)], ["A", "C"])

    def test_video_enclosure_skipped(self):
        xml = feed(dated("Video", 9, "https://a/v.mp4", type="video/mp4"), dated("Audio", 1, "https://a/a.mp3"))
        self.assertEqual([e["title"] for e in tf.feed_episodes(xml, 5)], ["Audio"])

    def test_fields(self):
        xml = feed(dated("T", 2, "https://a/t.mp3", guid="g1", duration="1:02:03", length="12345"))
        episode = tf.feed_episodes(xml, 1)[0]
        self.assertEqual(episode["guid"], "g1")
        self.assertEqual(episode["seconds"], 3723)
        self.assertEqual(episode["size"], 12345)
        self.assertEqual(episode["address"], "https://a/t.mp3")
        self.assertEqual(episode["type"], "audio/mpeg")
        self.assertIsInstance(episode["published"], int)

    def test_missing_or_bad_length_is_unknown(self):
        for length in ("", "0", "-5", "abc", "1.5"):
            xml = feed(dated("T", 2, "https://a/t.mp3", length=length))
            self.assertIsNone(tf.feed_episodes(xml, 1)[0]["size"], length)

    def test_three_duration_forms_and_junk(self):
        cases = {"1:02:03": 3723, "45:10": 2710, "1800": 1800, "soon": None, "1:2:3:4": None, "": None}
        for text, seconds in cases.items():
            xml = feed(dated("T", 2, "https://a/t.mp3", duration=text))
            self.assertEqual(tf.feed_episodes(xml, 1)[0]["seconds"], seconds, text)

    def test_no_date_gives_null_published(self):
        xml = feed(dict(title="U", address="https://a/u.mp3"))
        self.assertIsNone(tf.feed_episodes(xml, 1)[0]["published"])

    def test_text_that_is_not_xml_raises_and_says_why(self):
        with self.assertRaises(tf.FeedError) as caught:
            tf.feed_episodes("<rss><channel>", 3)
        self.assertIn("not valid XML", str(caught.exception))
        with self.assertRaises(tf.FeedError):
            tf.feed_episodes(b"<html><body>Not a feed", 3)


class FeedBytesTests(unittest.TestCase):
    """Feeds arrive as bytes, with the mistakes real feeds have."""

    def titles(self, data):
        return [e["title"] for e in tf.feed_episodes(data, 5)]

    def feed(self, title="Tëst"):
        return feed(dated(title, 2, "https://a/t.mp3"))

    def test_utf8_bytes_and_a_byte_order_mark(self):
        data = self.feed().encode("utf-8")
        self.assertEqual(self.titles(data), ["Tëst"])
        self.assertEqual(self.titles(codecs.BOM_UTF8 + data), ["Tëst"])

    def test_white_space_and_newlines_before_the_declaration(self):
        data = self.feed().encode("utf-8")
        for front in (b"\n", b"  \r\n\t", codecs.BOM_UTF8 + b"\n "):
            self.assertEqual(self.titles(front + data), ["Tëst"], front)
        self.assertEqual(self.titles("\n ﻿" + self.feed()), ["Tëst"])

    def test_windows_1252_with_a_declaration(self):
        text = self.feed("Café “quoted”").replace('<?xml version="1.0"?>',
                                                    '<?xml version="1.0" encoding="windows-1252"?>')
        self.assertEqual(self.titles(text.encode("windows-1252")), ["Café “quoted”"])

    def test_utf16_with_a_byte_order_mark(self):
        text = self.feed().replace('<?xml version="1.0"?>', '<?xml version="1.0" encoding="UTF-16"?>')
        self.assertEqual(self.titles(text.encode("utf-16")), ["Tëst"])
        self.assertEqual(self.titles(codecs.BOM_UTF16_BE + text.encode("utf-16-be")), ["Tëst"])
        # White space after the byte order mark, before the declaration.
        self.assertEqual(self.titles(codecs.BOM_UTF16_LE + (" \n" + text).encode("utf-16-le")), ["Tëst"])

    def test_undefined_entities_and_a_bare_ampersand(self):
        for title, expected in (("Tom&nbsp;Jerry", "Tom&nbsp;Jerry"), ("Q & A", "Q & A"),
                                ("Fish &amp; Chips &lt;3", "Fish & Chips <3"),
                                ("A&B;C", "A&B;C"), ("&#65;&#x42;", "AB")):
            self.assertEqual(self.titles(self.feed(title).encode("utf-8")), [expected], title)

    def test_control_characters_are_removed_but_tab_and_newline_stay(self):
        data = self.feed("Pre\x0bfix\x00end\ttab\nline").encode("utf-8")
        self.assertEqual(self.titles(data), ["Prefixend\ttab\nline"])

    def test_a_reference_to_a_forbidden_character_is_dropped(self):
        self.assertEqual(self.titles(self.feed("a&#11;b&#xB;c").encode("utf-8")), ["abc"])

    def test_still_broken_after_cleaning_raises(self):
        with self.assertRaises(tf.FeedError):
            tf.feed_episodes(b"<rss><channel><item></channel></rss> & more", 3)

    def test_a_clean_feed_is_not_changed_by_the_second_try(self):
        data = self.feed("Fish &amp; Chips").encode("utf-8")
        self.assertEqual(self.titles(data), ["Fish & Chips"])


class AudioNameTests(unittest.TestCase):
    def test_extension_from_address(self):
        self.assertEqual(tf.audio_name("abc", "https://a/x.M4A?token=1"), "audio/abc.m4a")
        self.assertEqual(tf.audio_name("abc", "https://a/x.flac"), "audio/abc.mp3")
        self.assertEqual(tf.audio_name("abc", "https://a/download"), "audio/abc.mp3")

    def test_the_address_wins_over_the_type(self):
        self.assertEqual(tf.audio_name("abc", "https://a/x.ogg", "audio/mpeg"), "audio/abc.ogg")

    def test_the_type_is_used_when_the_address_shows_nothing(self):
        cases = {"audio/mpeg": "mp3", "audio/mp4": "m4a", "audio/x-m4a": "m4a", "audio/aac": "aac",
                 "audio/ogg": "ogg", "audio/opus": "opus", "audio/wav": "wav", "audio/x-wav": "wav",
                 "AUDIO/MP4; codecs=mp4a": "m4a", "audio/unheard-of": "mp3", "": "mp3", None: "mp3"}
        for kind, ext in cases.items():
            name = tf.audio_name("0123456789ab", "https://a/download?id=7", kind)
            self.assertEqual(name, "audio/0123456789ab." + ext, kind)
            self.assertTrue(FILE_PATTERN.match(name), name)


class FeedKeyTests(unittest.TestCase):
    """The same cases as FeedKeyTests.swift and feedKey in applePodcasts.test.ts."""

    def test_spellings_of_one_address_match(self):
        key = tf.feed_key("https://example.com/feed.xml")
        for spelling in ("http://example.com/feed.xml", "HTTPS://Example.COM/feed.xml#top",
                         "https://www.example.com/feed.xml", "feed://example.com/feed.xml"):
            self.assertEqual(tf.feed_key(spelling), key, spelling)
        self.assertEqual(tf.feed_key("https://example.com/feed/"),
                         tf.feed_key("https://example.com/feed"))
        self.assertEqual(tf.feed_key("https://example.com/feed/?a=1"),
                         tf.feed_key("https://example.com/feed?a=1"))

    def test_different_feeds_stay_apart(self):
        self.assertNotEqual(tf.feed_key("https://example.com/a"), tf.feed_key("https://example.com/b"))
        self.assertNotEqual(tf.feed_key("https://example.com/feed?show=1"),
                            tf.feed_key("https://example.com/feed?show=2"))
        self.assertNotEqual(tf.feed_key("https://example.com/Feed"),
                            tf.feed_key("https://example.com/feed"))

    def test_the_key_itself(self):
        self.assertEqual(tf.feed_key("https://www.Show-B.test/rss/"), "show-b.test/rss")
        self.assertEqual(tf.feed_key("  https://Example.com/Feed?A=1#x  "), "example.com/Feed?A=1")
        self.assertEqual(tf.feed_key("//example.com/a//"), "example.com/a")

    def test_an_address_with_no_scheme_is_kept_by_its_host_and_path(self):
        self.assertEqual(tf.feed_key("Example.com/feed/"), "example.com/feed")
        self.assertEqual(tf.feed_key("www.example.com?x=1"), "example.com?x=1")
        self.assertEqual(tf.feed_key(""), "")

    def test_a_key_is_its_own_key(self):
        for address in ("https://www.Show-B.test/rss/", "example.com/feed?a=1", "feed://x.test/"):
            key = tf.feed_key(address)
            self.assertEqual(tf.feed_key(key), key)


class WebAddressTests(unittest.TestCase):
    def test_only_http_and_https_with_a_host(self):
        for good in ("http://a.test/x", "HTTPS://a.test", "https://a.test:8080/feed?x=1"):
            self.assertTrue(tf.is_web_address(good), good)
        for bad in ("file:///etc/passwd", "ftp://a.test/x", "feed://a.test/x", "a.test/feed",
                    "https://", "https:///x", "", "javascript:alert(1)", None, 5):
            self.assertFalse(tf.is_web_address(bad), bad)


class FeedTitleTests(unittest.TestCase):
    def test_the_title_of_the_show(self):
        self.assertEqual(tf.feed_title(feed(dated("A", 1, "https://a/1.mp3"))), "Show")

    def test_no_title_is_empty(self):
        self.assertEqual(tf.feed_title("<rss><channel></channel></rss>"), "")
        self.assertEqual(tf.feed_title("<rss></rss>"), "")

    def test_a_feed_that_is_not_xml_is_an_error(self):
        with self.assertRaises(tf.FeedError):
            tf.feed_title("not xml at all <<<")


if __name__ == "__main__":
    unittest.main()
