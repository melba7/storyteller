"""Tests for the steps of teach-finish.sh that came with the second download, the meaning model and
the per-show settings: snapping the labels, passing --labels labels-snapped, the meaning step and
the settings step. The stand-in python3, swift and podcast-teach programs of test_teach_shell.py are
used. Every exit code of each new tool is run through the shell script, as a lesson in
docs/LESSONS.md asks.
Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import os

import test_teach_shell as shell

LABELS = "--labels labels-snapped"
# What the steps that read labels are, by the start of the call the stand-ins record.
READING_LABELS = ("python3 teach_habits.py", "python3 teach_train.py", "python3 teach_cues.py", "python3 teach_library.py",
                  "podcast-teach sounds", "podcast-teach meaning", "podcast-teach score")
NOT_READING_LABELS = ("python3 teach_settings.py", "python3 teach_publish.py")
CODES = (0, 1, 2, 3, 130)


def with_snap(order):
    """The finish steps in order with the snap, which comes right after the backup."""
    return order[:1] + ["python3 teach_snap.py"] + order[1:]


class Steps(shell.Setup):
    def setUp(self):
        super().setUp()
        self.folder = os.path.join(self.home, "Storyteller Lofi", "PodcastTeaching")

    def make(self, name):
        os.makedirs(os.path.join(self.folder, name), exist_ok=True)

    def calls_of(self, start):
        return [c for c in self.called() if c.startswith(start)]

    def finish(self, **more):
        done = self.run_script("teach-finish.sh", **more)
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        return done


class LabelsTests(Steps):
    def test_with_no_second_downloads_nothing_is_snapped_and_no_labels_option_is_given(self):
        self.finish()
        self.assertEqual(self.short(), shell.FINISH_ORDER)
        self.assertEqual(self.calls_of("python3 teach_snap.py"), [])
        for call in self.called():
            self.assertNotIn("--labels", call)

    def test_a_labels_snapped_folder_alone_is_snapped_again_and_then_used(self):
        # Without copies/ (second downloads were removed) the folder is still brought up to date, so
        # episodes marked since the last snap are in it: snapping copies a label that has no truth
        # file as it is.
        self.make("labels-snapped")
        self.finish()
        self.assertEqual(self.short(), with_snap([
            call + (" " + LABELS if call.startswith(READING_LABELS) else "")
            for call in shell.FINISH_ORDER]))

    def test_a_failed_snap_of_a_labels_snapped_folder_alone_leaves_it_unused(self):
        self.make("labels-snapped")
        done = self.finish(CODES="teach_snap.py=2")
        self.assertEqual(self.short(), with_snap(shell.FINISH_ORDER))
        self.assertIn("  Snap: failed", done.stdout)
        for call in self.called():
            self.assertNotIn("--labels", call)

    def test_every_tool_that_reads_labels_gets_the_option_and_the_others_do_not(self):
        self.make("labels-snapped")
        self.finish()
        for start in READING_LABELS:
            found = self.calls_of(start)
            self.assertEqual(len(found), 1, start)
            self.assertTrue(found[0].endswith(" " + LABELS), found[0])
        for start in NOT_READING_LABELS:
            found = self.calls_of(start)
            self.assertEqual(len(found), 1, start)
            self.assertNotIn("--labels", found[0])

    def test_neither_folder_means_no_snap_and_no_option(self):
        self.finish()
        self.assertEqual(self.calls_of("python3 teach_snap.py"), [])
        for call in self.called():
            self.assertNotIn("--labels", call)

    def test_the_folder_comes_before_the_option_for_the_swift_tools(self):
        self.make("labels-snapped")
        self.finish()
        for tool in ("sounds", "meaning", "score"):
            self.assertIn("podcast-teach %s %s %s" % (tool, self.folder, LABELS), self.called())

    def test_second_downloads_are_snapped_first_and_the_snapped_labels_are_used(self):
        self.make("copies")
        done = self.finish()
        self.assertEqual(self.short(), with_snap([
            call + (" " + LABELS if call.startswith(READING_LABELS) else "")
            for call in shell.FINISH_ORDER]))
        self.assertIn("  Snap: worked", done.stdout)
        # The run already holds the folder's lock: snap does not start its own.
        self.assertEqual(len([c for c in self.called() if " teach_store.py hold" in c]), 1)
        self.assertEqual(self.calls_of("python3 teach_snap.py"),
                         ["python3 teach_snap.py --folder %s" % self.folder])

    def test_the_backup_comes_first_after_the_lock_and_then_the_snap(self):
        self.make("copies")
        self.finish()
        names = [c.split()[1] for c in self.called() if c.startswith("python3")]
        self.assertEqual(names[:3], ["teach_store.py", "teach_backup.py", "teach_snap.py"])
        self.assertLess(names.index("teach_snap.py"), names.index("teach_habits.py"))

    def test_snapping_again_with_the_same_result_is_nothing_to_do(self):
        self.make("copies")
        self.program("python3", shell.PYTHON.replace(
            'echo "$RANDOM$RANDOM" > "$folder/labels-snapped/a.json"',
            'echo same > "$folder/labels-snapped/a.json"'))
        self.finish()
        done = self.finish()
        self.assertIn("  Snap: nothing to do", done.stdout)

    def test_every_exit_code_of_snap_is_run_through_the_script(self):
        # The stand-in that ends with a given code writes nothing, so the folder is there already: for
        # exit 0 it is the one snapping made, for the others it is an old one that must not be used.
        self.make("copies")
        self.make("labels-snapped")
        for code in CODES:
            open(self.calls, "w").close()
            done = self.finish(CODES="teach_snap.py=%d" % code)
            self.assertEqual(self.short()[1], "python3 teach_snap.py", code)
            self.assertEqual(self.short(), with_snap([
                call + (" " + LABELS if code == 0 and call.startswith(READING_LABELS) else "")
                for call in shell.FINISH_ORDER]), code)
            if code:
                self.assertIn("  Snap: failed", done.stdout, code)
                self.assertIn("Claude's own labels are used this time", done.stdout, code)
            else:
                self.assertNotIn("  Snap: failed", done.stdout)
            self.assertIn("  Publish: worked", done.stdout, code)

    def test_when_snapping_fails_an_old_labels_snapped_folder_is_not_used(self):
        self.make("copies")
        self.make("labels-snapped")  # left by an earlier run: it may be out of date
        self.finish(CODES="teach_snap.py=2")
        for call in self.called():
            self.assertNotIn("--labels", call)

    def test_a_labels_snapped_folder_that_snapping_could_not_make_is_not_given(self):
        self.make("copies")
        self.finish(NOOP="teach_snap.py")  # the stand-in says "nothing to do" and writes nothing
        for call in self.called():
            self.assertNotIn("--labels", call)
        self.assertEqual(self.short(), with_snap(shell.FINISH_ORDER))


class MeaningTests(Steps):
    def test_the_joints_are_found_before_the_score_and_a_failure_there_does_not_stop_it(self):
        done = self.finish()
        order = [c.split(" %s" % self.folder)[0] for c in self.called() if c.startswith("podcast-teach")]
        self.assertLess(order.index("podcast-teach joints"), order.index("podcast-teach score"))
        self.assertIn("  Joints: worked", done.stdout)
        for code in CODES:
            open(self.calls, "w").close()
            done = self.finish(TEACH_CODES="joints=%d" % code)
            self.assertEqual(len(self.calls_of("podcast-teach score")), 1, code)
            self.assertIn("  Score: worked", done.stdout, code)
            if code:
                self.assertIn("  Joints: failed", done.stdout, code)
                self.assertIn("No joints were saved this time", done.stdout, code)
        self.assertNotIn("--labels", self.calls_of("podcast-teach joints")[0])

    def test_it_runs_after_the_sounds_and_before_the_score(self):
        self.finish()
        order = self.short()
        self.assertLess(order.index("podcast-teach sounds"), order.index("podcast-teach meaning"))
        self.assertLess(order.index("podcast-teach meaning"), order.index("podcast-teach score"))
        self.assertLess(order.index("python3 teach_train.py"), order.index("podcast-teach meaning"))

    def test_it_is_wrapped_to_keep_the_mac_awake_like_the_python_steps(self):
        self.program("caffeinate", '#!/bin/bash\necho "caffeinate $*" >> "$CALLS"\nshift\nexec "$@"\n')
        self.finish()
        wrapped = [c for c in self.called() if c.startswith("caffeinate -i ")]
        for step in ("teach_habits.py", "teach_train.py", "teach_cues.py", "teach_library.py"):
            self.assertEqual(len([c for c in wrapped if step in c]), 1, step)
        meaning = [c for c in wrapped if " meaning " in c]
        self.assertEqual(meaning, ["caffeinate -i %s/podcast-teach meaning %s" % (self.bin, self.folder)])
        # The tool still ran, and with the same arguments as without the wrapper.
        self.assertIn("podcast-teach meaning %s" % self.folder, self.called())

    def test_every_exit_code_of_the_meaning_tool_lets_the_run_go_on(self):
        for code in CODES:
            open(self.calls, "w").close()
            done = self.finish(TEACH_CODES="meaning=%d" % code)
            self.assertEqual(self.short(), shell.FINISH_ORDER, code)
            if code:
                self.assertIn("  Meaning: failed", done.stdout, code)
                self.assertIn("Meaning did not work (see above)", done.stdout, code)
                self.assertIn("No new meaning model this time", done.stdout, code)
            else:
                self.assertNotIn("  Meaning: failed", done.stdout)
            for label in ("Sounds", "Score", "Settings", "Publish"):
                self.assertIn("  %s: worked" % label, done.stdout, (code, label))

    def test_the_set_up_problem_is_one_plain_line_in_the_log_and_the_run_ends_well(self):
        done = self.finish(FAIL="podcast-teach-meaning")  # the stand-in ends with 2
        self.assertEqual(done.stdout.count("No new meaning model this time"), 1)
        self.assertIn("No new meaning model this time", self.log())
        self.assertIn("The results are where the phone reads them", done.stdout)

    def test_no_shelf_yet_or_too_few_episodes_is_nothing_to_do(self):
        done = self.finish(NOOP="podcast-teach-meaning")
        self.assertIn("  Meaning: nothing to do", done.stdout)
        self.assertNotIn("No new meaning model", done.stdout)

    def test_a_new_model_is_worked(self):
        done = self.finish()
        self.assertIn("  Meaning: worked", done.stdout)
        self.assertTrue(os.path.exists(os.path.join(self.folder, "ad-meaning.json")))

    def test_it_is_left_out_with_the_others_when_podcast_teach_does_not_build(self):
        done = self.finish(BUILD_FAILS="1")
        self.assertEqual(self.calls_of("podcast-teach"), [])
        self.assertIn("  Meaning: failed (left out because podcast-teach is not built)", done.stdout)


class SettingsTests(Steps):
    def test_it_runs_after_the_score_and_before_publish(self):
        self.finish()
        order = self.short()
        self.assertLess(order.index("podcast-teach score"), order.index("python3 teach_settings.py"))
        self.assertLess(order.index("python3 teach_settings.py"), order.index("python3 teach_publish.py"))
        self.assertEqual(self.calls_of("python3 teach_settings.py"),
                         ["python3 teach_settings.py --folder %s" % self.folder])

    def test_every_exit_code_of_the_settings_tool_lets_the_run_go_on(self):
        for code in CODES:
            open(self.calls, "w").close()
            done = self.finish(CODES="teach_settings.py=%d" % code)
            self.assertEqual(self.short(), shell.FINISH_ORDER, code)
            if code:
                self.assertIn("  Settings: failed", done.stdout, code)
                self.assertIn("Settings did not work (see above)", done.stdout, code)
                self.assertIn("No new settings this time", done.stdout, code)
            self.assertIn("  Publish: worked", done.stdout, code)
            self.assertIn("The results are where the phone reads them", done.stdout, code)

    def test_no_scorecard_yet_is_nothing_to_do(self):
        done = self.finish(NOOP="teach_settings.py")
        self.assertIn("  Settings: nothing to do", done.stdout)
        self.assertNotIn("No new settings this time", done.stdout)

    def test_new_settings_are_worked(self):
        done = self.finish()
        self.assertIn("  Settings: worked", done.stdout)
        self.assertTrue(os.path.exists(os.path.join(self.folder, "show-settings.json")))

    def test_it_is_left_out_when_the_swift_steps_were_left_out(self):
        # The rule changed on purpose: this test used to say the settings step still runs. With
        # no build there is no new score, so the settings would be made from the scorecard of an
        # earlier run, which a failed score already forbids. Publish still runs.
        done = self.finish(BUILD_FAILS="1")
        self.assertEqual(self.calls_of("python3 teach_settings.py"), [])
        self.assertIn("  Settings: left out (the score failed)", done.stdout)
        self.assertEqual(len(self.calls_of("python3 teach_publish.py")), 1)

    def test_a_failing_publish_still_decides_the_exit_code(self):
        done = self.run_script("teach-finish.sh", CODES="teach_settings.py=2 teach_publish.py=2")
        self.assertEqual(done.returncode, 1)
        self.assertIn("  Settings: failed", done.stdout)
        self.assertIn("  Publish: failed", done.stdout)


class WholeRunTests(Steps):
    def test_the_summary_lists_every_step_that_ran_in_order(self):
        self.make("copies")
        done = self.finish()
        summary = done.stdout[done.stdout.index("Summary:"):]
        import re
        self.assertEqual(re.findall(r"^  (\w+): ", summary, re.M),
                         ["Backup", "Snap", "Habits", "Model", "Cues", "Library", "Sounds", "Meaning", "Joints",
                          "Score", "Settings", "Publish"])

    def test_the_weekly_run_goes_through_the_same_steps(self):
        self.make("copies")
        done = self.run_script("teach-weekly.sh")
        self.assertEqual(done.returncode, 0, done.stdout)
        self.assertEqual(len(self.calls_of("python3 teach_snap.py")), 1)
        self.assertEqual(len(self.calls_of("podcast-teach meaning")), 1)
        self.assertEqual(len(self.calls_of("python3 teach_settings.py")), 1)
