"""Tests for teach_prepare.py pick: the phone's list first, then the newest episodes of every
followed show of the last 72 hours; known episodes left out; the limit of a run and the weekly
limit; a feed that cannot be read; nothing to do. The feeds are made up and handed in, so nothing
touches the network. Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import json
import os
import unittest
from email.utils import formatdate

import teach_ahead_set as ahead
import teach_budget
import teach_prepare as prepare
import teach_store as store
from teach_feed import episode_id
from teach_testing import entry
from test_teach_ahead import NOW, Setup, queued

HOUR = 3600
SHOW = {"feed": "https://mac.example/a.xml", "title": "Show A"}
OTHER = {"feed": "https://mac.example/b.xml", "title": "Show B"}


def feed_of(*items):
    """A feed with items given as (guid, title, hours ago, address)."""
    body = ""
    for guid, title, hours, address in items:
        body += "<item><title>%s</title>" % title
        if guid:
            body += "<guid>%s</guid>" % guid
        body += "<pubDate>%s</pubDate>" % formatdate(NOW - hours * HOUR, usegmt=True)
        body += '<enclosure url="%s" type="audio/mpeg" length="5000"/></item>' % address
    return ('<?xml version="1.0"?><rss><channel><title>T</title>%s</channel></rss>' % body).encode()


class Prepare(Setup):
    def run_pick(self, *options, feeds=None, shows=(SHOW,), command_budget=True):
        feeds = feeds or {}
        asked = []

        def fetch(address):
            asked.append(address)
            answer = feeds[address]
            if isinstance(answer, Exception):
                raise answer
            return answer

        extra = ["--budget", "prepare-2026-W48"] if command_budget else []
        code = prepare.main(["pick", "--folder", self.folder] + extra + list(options),
                            say=self.said.append, defaults=lambda: [self.mac, self.icloud],
                            now=lambda: NOW, load_shows=lambda path: list(shows), fetch=fetch,
                            sleep=lambda seconds: None)
        self.asked = asked
        return code

    def titles(self):
        return [e["title"] for e in self.manifest()]


class OrderTests(Prepare):
    def test_the_phones_list_comes_first_whatever_its_age_then_the_newest_of_every_show(self):
        self.write_queue([queued(1, published=NOW - 900 * HOUR), queued(2)])
        feeds = {SHOW["feed"]: feed_of(("a1", "A old", 50, "https://cdn/a1.mp3"),
                                       ("a2", "A new", 5, "https://cdn/a2.mp3")),
                 OTHER["feed"]: feed_of(("b1", "B mid", 20, "https://cdn/b1.mp3"))}
        self.assertEqual(self.run_pick(feeds=feeds, shows=(SHOW, OTHER)), 0, self.said)
        self.assertEqual(self.titles(), ["Episode 1", "Episode 2", "A new", "B mid", "A old"])
        self.assertEqual([e["title"] for e in ahead.read_ahead(self.folder)], self.titles())

    def test_only_the_last_72_hours_of_a_feed_are_taken(self):
        feeds = {SHOW["feed"]: feed_of(("a1", "In", 71, "https://cdn/1.mp3"),
                                       ("a2", "Out", 73, "https://cdn/2.mp3"))}
        self.run_pick(feeds=feeds)
        self.assertEqual(self.titles(), ["In"])

    def test_the_hours_can_be_changed(self):
        feeds = {SHOW["feed"]: feed_of(("a1", "In", 71, "https://cdn/1.mp3"),
                                       ("a2", "Also", 100, "https://cdn/2.mp3"))}
        self.run_pick("--hours", "120", feeds=feeds)
        self.assertEqual(self.titles(), ["In", "Also"])

    def test_an_episode_with_no_date_is_not_taken_from_a_feed(self):
        data = (b'<rss><channel><item><title>No date</title><guid>g</guid>'
                b'<enclosure url="https://cdn/n.mp3" type="audio/mpeg"/></item></channel></rss>')
        self.assertEqual(self.run_pick(feeds={SHOW["feed"]: data}), 3)

    def test_feed_episodes_use_the_macs_feed_address_and_the_feeds_guid(self):
        feeds = {SHOW["feed"]: feed_of(("guid-a1", "A", 5, "https://cdn/a1.mp3"))}
        self.run_pick(feeds=feeds)
        found = ahead.read_ahead(self.folder)[0]
        self.assertEqual((found["feed"], found["guid"]), (SHOW["feed"], "guid-a1"))
        manifest = self.manifest()[0]
        self.assertEqual((manifest["id"], manifest["show"], manifest["address"]),
                         (episode_id(SHOW["feed"], "guid-a1", "https://cdn/a1.mp3"), "Show A",
                          "https://cdn/a1.mp3"))
        self.assertEqual(found["id"], manifest["id"])

    def test_a_phone_episode_of_a_followed_show_gets_the_macs_spelling_for_its_id(self):
        self.write_queue([queued(1, feed="http://www.mac.example/a.xml/", guid="g1")])
        self.run_pick(shows=(SHOW,), feeds={SHOW["feed"]: feed_of()})
        self.assertEqual(self.manifest()[0]["feed"], SHOW["feed"])
        self.assertEqual(ahead.read_ahead(self.folder)[0]["feed"], "http://www.mac.example/a.xml/")

    def test_a_missing_or_empty_phone_list_is_not_a_stop(self):
        feeds = {SHOW["feed"]: feed_of(("a1", "A", 5, "https://cdn/a1.mp3"))}
        self.assertEqual(self.run_pick(feeds=feeds), 0)
        self.assertEqual(self.titles(), ["A"])
        self.write_queue([])
        self.assertEqual(self.run_pick(feeds={SHOW["feed"]: feed_of(("a2", "B", 5, "https://cdn/2.mp3"))}), 0)
        self.assertEqual(self.titles(), ["A", "B"])

    def test_an_unusable_phone_list_is_said_and_the_feeds_still_count(self):
        with open(os.path.join(self.icloud, "Podcasts", "phone-queue.json"), "w") as f:
            f.write("nope")
        feeds = {SHOW["feed"]: feed_of(("a1", "A", 5, "https://cdn/a1.mp3"))}
        self.assertEqual(self.run_pick(feeds=feeds), 0)
        self.assertTrue(any("cannot be used" in line for line in self.said))
        self.assertEqual(self.titles(), ["A"])

    def test_a_feed_episode_with_no_guid_is_left_out_because_the_phone_cannot_match_it(self):
        feeds = {SHOW["feed"]: feed_of(("", "No guid", 5, "https://cdn/n.mp3"),
                                       ("g", "Has one", 6, "https://cdn/h.mp3"))}
        self.run_pick(feeds=feeds)
        self.assertEqual(self.titles(), ["Has one"])


class LanguageTests(Prepare):
    def feed_in(self, language, *items):
        data = feed_of(*items).decode()
        tag = "" if language is None else "<language>%s</language>" % language
        return data.replace("<title>T</title>", "<title>T</title>" + tag, 1).encode()

    def test_a_feed_that_says_it_is_not_english_is_left_out_and_counted_in_the_summary(self):
        feeds = {SHOW["feed"]: self.feed_in("de-DE", ("a1", "Eins", 5, "https://cdn/1.mp3"),
                                            ("a2", "Zwei", 6, "https://cdn/2.mp3")),
                 OTHER["feed"]: self.feed_in("en-US", ("b1", "One", 5, "https://cdn/b1.mp3"))}
        self.assertEqual(self.run_pick(feeds=feeds, shows=(SHOW, OTHER)), 0, self.said)
        self.assertEqual(self.titles(), ["One"])
        self.assertTrue(any("2 episodes" in line and "not in English" in line for line in self.said))

    def test_english_in_any_spelling_and_a_feed_with_no_language_count_as_english(self):
        spellings = ("en", "EN", "en-us", "en_GB", "en-AU")
        for number, language in enumerate(spellings + (None, "")):
            feeds = {SHOW["feed"]: self.feed_in(language, ("g%d" % number, "E%d" % number, 5,
                                                           "https://cdn/%d.mp3" % number))}
            self.run_pick(feeds=feeds)
        self.assertEqual(len(self.titles()), len(spellings) + 2)
        self.assertFalse(any("not in English" in line for line in self.said))

    def test_only_episodes_of_the_window_are_counted(self):
        feeds = {SHOW["feed"]: self.feed_in("fr", ("a1", "Un", 5, "https://cdn/1.mp3"),
                                            ("a2", "Vieux", 500, "https://cdn/2.mp3"))}
        self.run_pick(feeds=feeds)
        self.assertTrue(any("1 episode " in line and "not in English" in line for line in self.said))

    def test_when_only_other_languages_are_new_it_is_still_nothing_to_do_and_says_why(self):
        feeds = {SHOW["feed"]: self.feed_in("es", ("a1", "Uno", 5, "https://cdn/1.mp3"))}
        self.assertEqual(self.run_pick(feeds=feeds), 3)
        self.assertEqual(len(self.said), 1)
        self.assertIn("not in English", self.said[0])

    def test_the_phones_list_is_not_filtered_by_language(self):
        self.write_queue([queued(1)])
        self.assertEqual(self.run_pick(feeds={SHOW["feed"]: self.feed_in("de")}), 0)
        self.assertEqual(self.titles(), ["Episode 1"])


class KnownTests(Prepare):
    def feeds(self):
        return {SHOW["feed"]: feed_of(("a1", "A1", 5, "https://cdn/a1.mp3"),
                                      ("a2", "A2", 6, "https://cdn/a2.mp3"))}

    def test_an_episode_in_the_teaching_set_is_not_picked_again(self):
        known = entry(1, feed=SHOW["feed"], guid="a1", address="https://cdn/a1.mp3",
                      id=episode_id(SHOW["feed"], "a1", "https://cdn/a1.mp3"))
        store.save_manifest(self.folder, [known])
        self.run_pick(feeds=self.feeds())
        self.assertEqual(self.titles()[1:], ["A2"])

    def test_another_spelling_of_the_feed_is_known_by_its_guid(self):
        known = entry(1, feed="http://www.mac.example/a.xml/", guid="a1", address="https://old/x.mp3")
        store.save_manifest(self.folder, [known])
        self.run_pick(feeds=self.feeds())
        self.assertEqual(self.titles()[1:], ["A2"])

    def test_nothing_is_picked_twice(self):
        self.assertEqual(self.run_pick(feeds=self.feeds()), 0)
        self.assertEqual(self.run_pick(feeds=self.feeds()), 3)
        self.assertEqual(len(self.manifest()), 2)
        self.assertEqual(len(ahead.read_ahead(self.folder)), 2)

    def test_exam_and_shelf_episodes_are_never_picked(self):
        first = episode_id(SHOW["feed"], "a1", "https://cdn/a1.mp3")
        second = episode_id(SHOW["feed"], "a2", "https://cdn/a2.mp3")
        with open(os.path.join(self.folder, "exam.json"), "w") as f:
            json.dump({"version": 1, "episodes": [first]}, f)
        with open(os.path.join(self.folder, "shelf.json"), "w") as f:
            json.dump({"version": 1, "episodes": [second]}, f)
        self.assertEqual(self.run_pick(feeds=self.feeds()), 3)
        self.assertEqual(self.manifest(), [])

    def test_an_episode_on_the_phones_list_and_in_its_feed_is_picked_once(self):
        self.write_queue([queued(1, feed=SHOW["feed"], guid="a1", audio="https://cdn/a1.mp3")])
        self.run_pick(feeds=self.feeds())
        self.assertEqual(len(self.manifest()), 2)


class LimitTests(Prepare):
    def many(self, count):
        return {SHOW["feed"]: feed_of(*[("g%d" % n, "E%d" % n, n + 1, "https://cdn/%d.mp3" % n)
                                         for n in range(count)])}

    def test_at_most_six_a_run_and_the_phones_list_first(self):
        self.write_queue([queued(1)])
        self.run_pick(feeds=self.many(10))
        self.assertEqual(self.titles(), ["Episode 1", "E0", "E1", "E2", "E3", "E4"])

    def test_most_can_be_changed(self):
        self.run_pick("--most", "2", feeds=self.many(10))
        self.assertEqual(self.titles(), ["E0", "E1"])

    def test_the_weekly_budget_limits_the_run_by_the_rule_of_the_nightly_pick(self):
        teach_budget.Budget(self.folder, "prepare-2026-W48", 35).add(34.0, 180)
        # 1.00 left at 0.19 an episode: one more fits while spent plus its estimate stays under 35.
        self.run_pick(feeds=self.many(10))
        self.assertEqual(self.titles(), ["E0", "E1", "E2", "E3", "E4"])
        self.assertTrue(any("$1.00 left" in line for line in self.said))

    def test_a_spent_budget_picks_nothing_and_says_so_in_one_line(self):
        teach_budget.Budget(self.folder, "prepare-2026-W48", 35).add(35.0, 183)
        self.assertEqual(self.run_pick(feeds=self.many(3)), 3)
        self.assertEqual(self.said, [line for line in self.said if "weekly cap of $35.00" in line])
        self.assertEqual(len(self.said), 1)
        self.assertEqual(self.manifest(), [])

    def test_the_cap_and_the_estimate_can_be_changed(self):
        self.run_pick("--cap", "0.5", "--estimate", "0.2", feeds=self.many(10))
        self.assertEqual(len(self.manifest()), 2)

    def test_a_budget_name_is_needed(self):
        self.assertEqual(self.run_pick(command_budget=False, feeds=self.many(1)), 2)


class FailureTests(Prepare):
    def test_a_feed_that_fails_is_said_in_one_line_and_passed_over(self):
        feeds = {SHOW["feed"]: OSError("timed out"),
                 OTHER["feed"]: feed_of(("b1", "B", 5, "https://cdn/b.mp3"))}
        self.assertEqual(self.run_pick(feeds=feeds, shows=(SHOW, OTHER)), 0)
        failed = [line for line in self.said if "Show A" in line]
        self.assertEqual(len(failed), 1)
        self.assertIn("timed out", failed[0])
        self.assertEqual(self.titles(), ["B"])

    def test_a_feed_that_is_not_xml_is_passed_over_too(self):
        feeds = {SHOW["feed"]: b"<html>not a feed"}
        self.assertEqual(self.run_pick(feeds=feeds), 3)
        self.assertTrue(any("Show A" in line for line in self.said))

    def test_nothing_to_do_is_exit_3_with_one_plain_line(self):
        self.assertEqual(self.run_pick(feeds={SHOW["feed"]: feed_of()}), 3)
        self.assertEqual(len(self.said), 1)
        self.assertIn("nothing to prepare", self.said[0])

    def test_no_shows_and_no_list_is_nothing_to_do(self):
        self.assertEqual(self.run_pick(shows=()), 3)

    def test_another_run_holding_the_folder_is_exit_3(self):
        feeds = {SHOW["feed"]: feed_of(("a1", "A", 5, "https://cdn/a1.mp3"))}
        with store.run_lock(self.folder):
            self.assertEqual(self.run_pick(feeds=feeds), 3)
        self.assertIn("Another teaching run", self.said[-1])


if __name__ == "__main__":
    unittest.main()
