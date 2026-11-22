"""Tests for teach_fetch.py: the feed fetch (size cap, gzip), the download of a whole file (cut-off
answers, too big files), HTTP 308 and addresses with spaces. Fake answers only, no network.
Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import email.message
import gzip
import hashlib
import io
import os
import tempfile
import unittest
import urllib.error
import urllib.request

import teach_fetch as tf
from teach_testing import FakeResponse, ShortResponse, opener


class AddressSchemeTests(unittest.TestCase):
    def test_only_http_and_https_addresses_are_fetched(self):
        for address in ("file:///etc/hosts", "ftp://a/f", "data:text/plain,hi", "a/feed", ""):
            seen = []
            with self.assertRaises(ValueError, msg=address):
                tf.fetch_feed(address, open_url=lambda *a, **k: seen.append(a))
            with self.assertRaises(ValueError, msg=address):
                tf.download(address, os.path.join(tempfile.mkdtemp(), "x.mp3"),
                            open_url=lambda *a, **k: seen.append(a))
            self.assertEqual(seen, [], address)

    def test_a_redirect_to_another_scheme_is_not_followed(self):
        handler = tf.RedirectHandler()
        request = urllib.request.Request("https://a/feed")
        self.assertIsNone(handler.redirect_request(request, None, 302, "Found", {}, "file:///etc/hosts"))
        self.assertIsNone(handler.redirect_request(request, None, 302, "Found", {}, "ftp://a/x"))
        self.assertIsNotNone(handler.redirect_request(request, None, 302, "Found", {}, "https://b/x"))


class FetchFeedTests(unittest.TestCase):
    def test_returns_bytes_and_asks_for_identity(self):
        open_url = opener(b"<rss/>", content_type="application/rss+xml")
        self.assertEqual(tf.fetch_feed("https://a/feed", open_url=open_url), b"<rss/>")
        request = open_url.seen["request"]
        self.assertEqual(request.get_header("Accept-encoding"), "identity")
        self.assertEqual(request.get_header("User-agent"), tf.probe.USER_AGENT)

    def test_a_feed_bigger_than_the_old_limit_is_read_whole(self):
        data = b"x" * 5_000_100
        self.assertEqual(tf.fetch_feed("https://a/feed", open_url=opener(data)), data)

    def test_a_feed_over_the_cap_is_an_error(self):
        with self.assertRaises(ValueError) as caught:
            tf.fetch_feed("https://a/feed", open_url=opener(b"x" * 11), limit=10)
        self.assertIn("bigger than", str(caught.exception))
        self.assertEqual(tf.fetch_feed("https://a/feed", open_url=opener(b"x" * 10), limit=10), b"x" * 10)

    def test_the_cap_is_64_megabytes(self):
        self.assertEqual(tf.FEED_LIMIT, 64_000_000)

    def test_gzip_by_content_encoding(self):
        packed = gzip.compress(b"<rss>hello</rss>")
        open_url = opener(packed, **{"Content-Encoding": "gzip"})
        self.assertEqual(tf.fetch_feed("https://a/feed", open_url=open_url), b"<rss>hello</rss>")

    def test_gzip_by_magic_bytes_without_the_header(self):
        packed = gzip.compress(b"<rss>hello</rss>")
        self.assertEqual(tf.fetch_feed("https://a/feed", open_url=opener(packed)), b"<rss>hello</rss>")

    def test_unpacked_size_is_capped_too(self):
        packed = gzip.compress(b"x" * 1000)
        with self.assertRaises(ValueError):
            tf.fetch_feed("https://a/feed", open_url=opener(packed), limit=100)

    def test_damaged_or_cut_gzip_is_an_error(self):
        packed = gzip.compress(b"<rss>hello world, this is a feed</rss>" * 20)
        for body in (packed[:-10], b"\x1f\x8bnot gzip at all"):
            with self.assertRaises(ValueError, msg=body[:12]):
                tf.fetch_feed("https://a/feed", open_url=opener(body))

    def test_a_server_that_closes_early_is_an_error(self):
        def short(request, timeout=None):
            return ShortResponse(b"<rss><chan", 100)
        with self.assertRaises(OSError):
            tf.fetch_feed("https://a/feed", open_url=short)


class DownloadTests(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.dir.cleanup)
        self.path = os.path.join(self.dir.name, "x.mp3")

    def test_saves_file_and_reports_hash_bytes_host(self):
        data = b"abc" * 1000
        open_url = opener(data, url="https://cdn.example.com/final.mp3")
        info = tf.download("https://a/x.mp3", self.path, open_url=open_url)
        self.assertEqual(info, {"bytes": 3000, "sha256": hashlib.sha256(data).hexdigest(),
                                "host": "cdn.example.com"})
        with open(self.path, "rb") as handle:
            self.assertEqual(handle.read(), data)
        self.assertFalse(os.path.exists(self.path + ".part"))

    def test_request_headers_and_read_timeout(self):
        open_url = opener(b"data")
        tf.download("https://a/x.mp3", self.path, open_url=open_url)
        request = open_url.seen["request"]
        self.assertEqual(request.get_header("Accept-encoding"), "identity")
        self.assertEqual(request.get_header("User-agent"), tf.probe.USER_AGENT)
        self.assertEqual(open_url.seen["timeout"], 30)

    def assert_fails(self, open_url, error=(OSError, ValueError), **more):
        with self.assertRaises(error):
            tf.download("https://a/x.mp3", self.path, open_url=open_url, **more)
        self.assertFalse(os.path.exists(self.path))
        self.assertFalse(os.path.exists(self.path + ".part"))

    def test_empty_file_fails(self):
        self.assert_fails(opener(b""))

    def test_too_big_fails(self):
        self.assert_fails(opener(b"x" * 50), error=tf.TooLarge, max_bytes=40)

    def test_text_answer_fails(self):
        self.assert_fails(opener(b"<html>sorry</html>", content_type="text/html; charset=utf-8"))

    def test_too_slow_fails(self):
        ticks = iter(range(0, 100000, 700))
        self.assert_fails(opener(b"x" * 100), clock=lambda: next(ticks), chunk=10)

    def test_network_error_leaves_no_part(self):
        def broken(request, timeout=None):
            raise OSError("reset")
        self.assert_fails(broken)

    def test_a_half_file_is_not_resumed(self):
        with open(self.path + ".part", "wb") as handle:
            handle.write(b"old half")
        tf.download("https://a/x.mp3", self.path, open_url=opener(b"fresh"))
        with open(self.path, "rb") as handle:
            self.assertEqual(handle.read(), b"fresh")

    def test_a_server_that_closes_early_is_not_saved_as_finished(self):
        def short(request, timeout=None):
            return ShortResponse(b"x" * 60, 100)
        self.assert_fails(short, error=OSError)

    def test_the_whole_promised_length_is_fine(self):
        info = tf.download("https://a/x.mp3", self.path,
                           open_url=lambda r, timeout=None: ShortResponse(b"x" * 100, 100))
        self.assertEqual(info["bytes"], 100)

    def test_a_short_body_is_fine_when_the_answer_is_encoded(self):
        # With a Content-Encoding the Content-Length is not the length of what is read.
        info = tf.download("https://a/x.mp3", self.path, open_url=lambda r, timeout=None: FakeResponse(
            b"x" * 60, **{"Content-Length": "100", "Content-Encoding": "gzip"}))
        self.assertEqual(info["bytes"], 60)

    def test_a_promised_length_over_the_limit_is_refused_before_reading(self):
        reads = []

        class Watched(ShortResponse):
            def read(self, size=-1):
                reads.append(size)
                return super().read(size)
        self.assert_fails(lambda r, timeout=None: Watched(b"x" * 10, 5000), error=tf.TooLarge,
                          max_bytes=1000)
        self.assertEqual(reads, [])

    def test_the_limit_is_600_megabytes(self):
        self.assertEqual(tf.MAX_FILE, 600_000_000)


class RedirectTests(unittest.TestCase):
    """Python 3.9's urllib does not follow 308; the handler treats it like 307."""

    def follow(self, code, method="GET"):
        handler = tf.RedirectHandler()
        opened = []

        class Parent:
            def open(self, request, timeout=None):
                opened.append(request)
                return "opened"
        handler.parent = Parent()
        headers = email.message.Message()
        headers["Location"] = "https://cdn.example.com/new.mp3"
        request = urllib.request.Request("https://a/old.mp3", method=method)
        request.timeout = 5
        handler_method = getattr(handler, "http_error_%d" % code)
        return handler_method(request, io.BytesIO(b""), code, "Redirect", headers), opened

    def test_308_is_followed(self):
        answer, opened = self.follow(308)
        self.assertEqual((answer, [r.full_url for r in opened]), ("opened", ["https://cdn.example.com/new.mp3"]))

    def test_the_others_still_are(self):
        for code in (301, 302, 303, 307):
            self.assertEqual(self.follow(code)[0], "opened", code)

    def test_308_of_a_post_is_not_followed_like_307(self):
        with self.assertRaises(urllib.error.HTTPError):
            self.follow(308, method="POST")

    def test_one_opener_for_both_uses(self):
        self.assertIs(tf.opener(), tf.opener())
        self.assertTrue(any(isinstance(h, tf.RedirectHandler) for h in tf.opener().handlers))


class QuoteTests(unittest.TestCase):
    def test_spaces_and_non_ascii_in_path_and_query(self):
        self.assertEqual(tf.quote_address("https://a/my show/épisode 1.mp3?name=é t&x=1"),
                         "https://a/my%20show/%C3%A9pisode%201.mp3?name=%C3%A9%20t&x=1")

    def test_already_quoted_is_left_alone(self):
        for address in ("https://a/my%20show/x.mp3?sig=a%2Fb%3D&t=1", "https://a/x.mp3",
                        "https://u:p@a:8080/x;y=1/z?q=a+b#"[:-1]):
            self.assertEqual(tf.quote_address(address), address)

    def test_a_percent_that_starts_no_escape_is_quoted(self):
        self.assertEqual(tf.quote_address("https://a/100% real.mp3"), "https://a/100%25%20real.mp3")

    def test_a_non_ascii_host_and_a_fragment(self):
        self.assertEqual(tf.quote_address("https://bücher.example/x.mp3#t=5"),
                         "https://xn--bcher-kva.example/x.mp3")

    def test_the_request_uses_the_quoted_address(self):
        request = tf.make_request("https://a/with space.mp3")
        self.assertEqual(request.full_url, "https://a/with%20space.mp3")


if __name__ == "__main__":
    unittest.main()
