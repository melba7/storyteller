"""Tests for the playbook's phrases in ad-cues.json (teach_cues.py --with-playbook and the switch
file playbook-on): written only when asked, put in the show's own entry, and a damaged playbook.
Made-up lines and feeds only. No network.
Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import json
import os
import unittest

import teach_cues as cues
from test_teach_cues import Setup, lines_of

SHOW = "https://show/a"
OPENER = "Quick message from our friends."


class PlaybookTests(Setup):
    def playbook(self, *shows):
        with open(self.folder.path("playbook.json"), "w", encoding="utf-8") as f:
            json.dump({"version": 1, "writtenAt": 1, "shows": list(shows)}, f)

    def show(self, feed=SHOW, **lists):
        return dict({"feed": feed, "handoffs": [], "returns": [], "segments": [], "plugs": []}, **lists)

    def six(self):
        for number in range(1, 7):
            self.episode(number)

    def test_without_the_option_or_the_switch_the_file_is_as_before(self):
        self.six()
        self.playbook(self.show(handoffs=["a word from"]))
        self.assertEqual(self.run_it(), 0)
        self.assertNotIn("phrases", json.dumps(self.written()))
        self.assertNotIn("phrases", " ".join(self.said))

    def test_the_option_adds_a_shows_phrases_as_an_entry_of_its_own(self):
        self.six()
        self.playbook(self.show(handoffs=["a word from", "After the Break!"], returns=["and we are back"],
                                segments=["mail bag time"], plugs=["a word from", "leave a review"]))
        self.assertEqual(self.run_it("--with-playbook"), 0)
        self.assertEqual(self.written()["shows"], [
            {"feed": SHOW, "starts": [], "returns": [],
             "phrases": ["a word from", "after the break", "leave a review", "mail bag time"]}])
        self.assertIn("4 phrases of the playbook for 1 show", self.said[-1])

    def test_the_switch_file_turns_it_on_too(self):
        self.six()
        self.playbook(self.show(plugs=["leave a review"]))
        open(self.folder.path(cues.PLAYBOOK_SWITCH), "w").close()
        self.assertEqual(cues.PLAYBOOK_SWITCH, "playbook-on")
        self.assertEqual(self.run_it(), 0)
        self.assertEqual(self.written()["shows"][0]["phrases"], ["leave a review"])

    def test_the_phrases_join_the_shows_cue_entry_whatever_the_spelling_of_the_feed(self):
        for number in range(1, 4):
            self.episode(number, lines=lines_of(number, opener=OPENER))
        self.playbook(self.show(feed="http://www.show/a/", handoffs=["a word from"]),
                      self.show(feed="https://show/0", segments=["mail bag time"]))
        self.assertEqual(self.run_it("--with-playbook"), 0)
        shows = self.written()["shows"]
        self.assertEqual([s["feed"] for s in shows], ["https://show/0", SHOW], "sorted by feed")
        self.assertEqual(shows[0], {"feed": "https://show/0", "starts": [], "returns": [],
                                    "phrases": ["mail bag time"]})
        self.assertEqual(shows[1]["phrases"], ["a word from"])
        self.assertEqual(shows[1]["starts"], ["quick message from"], "the show's own cues stay")

    def test_only_phrases_of_two_words_or_more_that_are_text_are_kept(self):
        self.six()
        self.playbook(self.show(handoffs=["word", "", 7, None, "  Two   WORDS ", ["a list"]], segments="no list"),
                      self.show(feed="https://show/b", plugs=["one"]), "not a show", {"handoffs": ["no feed here"]})
        self.assertEqual(self.run_it("--with-playbook"), 0)
        self.assertEqual(self.written()["shows"], [
            {"feed": SHOW, "starts": [], "returns": [], "phrases": ["two words"]}])

    def test_no_playbook_adds_nothing_and_says_so(self):
        self.six()
        self.assertEqual(self.run_it("--with-playbook"), 0)
        self.assertNotIn("phrases", json.dumps(self.written()))
        self.assertIn("playbook.json", " ".join(self.said))

    def test_a_damaged_playbook_is_a_set_up_problem(self):
        self.six()
        with open(self.folder.path("playbook.json"), "w") as f:
            f.write("{")
        self.assertEqual(self.run_it("--with-playbook"), 2)
        self.assertIn("damaged", self.said[-1])
        self.assertFalse(os.path.exists(self.folder.path("ad-cues.json")))

    def test_turning_it_off_later_writes_the_file_without_the_phrases(self):
        self.six()
        self.playbook(self.show(handoffs=["a word from"]))
        self.run_it("--with-playbook")
        self.said.clear()
        self.assertEqual(self.run_it("--with-playbook"), 0)
        self.assertIn("up to date", " ".join(self.said))
        self.assertEqual(self.run_it(), 0)
        self.assertNotIn("phrases", json.dumps(self.written()))



if __name__ == "__main__":
    unittest.main()
