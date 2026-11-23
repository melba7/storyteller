"""Tests for teach_night.py: the night window (also over midnight), waiting for it to open in steps
of at most ten minutes, and waiting for the usage allowance. A fake clock; nothing really sleeps.
Run: python3 -m unittest discover -s libraries/PodcastKit/Tools/mac"""
import unittest
from datetime import datetime, timedelta

import teach_night as night


class FakeTime:
    """A clock that only moves when the code sleeps."""

    def __init__(self, hour, minute=0):
        self.now = datetime(2026, 1, 10, hour, minute)
        self.naps = []

    def clock(self):
        return self.now

    def sleep(self, seconds):
        self.naps.append(seconds)
        self.now += timedelta(seconds=seconds)


class WindowTests(unittest.TestCase):
    def test_the_text_is_two_hours(self):
        self.assertEqual(night.parse_window("23-7"), (23, 7))
        self.assertEqual(night.parse_window(" 0-24 "), (0, 24))
        for bad in ("", "23", "23-", "a-b", "7-7", "25-3", "-1-3", "23-7-9", "23:00-7:00"):
            with self.assertRaises(ValueError, msg=bad):
                night.parse_window(bad)

    def test_a_window_inside_one_day(self):
        self.assertTrue(night.in_window(9, (9, 17)))
        self.assertTrue(night.in_window(16, (9, 17)))
        self.assertFalse(night.in_window(17, (9, 17)))
        self.assertFalse(night.in_window(8, (9, 17)))

    def test_a_window_over_midnight(self):
        for hour in (23, 0, 3, 6):
            self.assertTrue(night.in_window(hour, (23, 7)), hour)
        for hour in (7, 12, 22):
            self.assertFalse(night.in_window(hour, (23, 7)), hour)

    def test_a_window_that_ends_at_midnight(self):
        self.assertTrue(night.in_window(23, (20, 24)))
        self.assertFalse(night.in_window(0, (20, 24)))


class WaiterTests(unittest.TestCase):
    def waiter(self, fake, between="23-7", wait_hours=None, said=None):
        return night.Waiter(night.parse_window(between) if between else None, wait_hours,
                            fake.clock, fake.sleep, (said if said is not None else []).append)

    def test_inside_the_window_it_does_not_wait(self):
        fake = FakeTime(2)
        self.waiter(fake).for_window()
        self.assertEqual(fake.naps, [])

    def test_without_a_window_it_never_waits(self):
        fake = FakeTime(12)
        self.waiter(fake, between=None).for_window()
        self.assertEqual(fake.naps, [])

    def test_outside_the_window_it_sleeps_in_steps_of_at_most_ten_minutes_until_it_opens(self):
        fake, said = FakeTime(21, 30), []
        self.waiter(fake, said=said).for_window()
        self.assertEqual(fake.now, datetime(2026, 1, 10, 23, 0))
        self.assertTrue(all(0 < nap <= 600 for nap in fake.naps), fake.naps)
        self.assertEqual(sum(fake.naps), 90 * 60)
        self.assertEqual(len(said), 1)  # said once, not at every step
        self.assertIn("23", said[0])

    def test_the_last_step_is_not_longer_than_what_is_left(self):
        fake = FakeTime(22, 55)
        self.waiter(fake).for_window()
        self.assertEqual(fake.naps, [300])

    def test_it_waits_for_the_morning_start_of_a_day_window(self):
        fake = FakeTime(20)
        self.waiter(fake, between="9-17").for_window()
        self.assertEqual(fake.now, datetime(2026, 1, 11, 9, 0))


class AllowanceTests(unittest.TestCase):
    def waiter(self, fake, hours, said):
        return night.Waiter(None, hours, fake.clock, fake.sleep, said.append)

    def test_without_wait_hours_it_does_not_wait(self):
        fake = FakeTime(1)
        self.assertFalse(self.waiter(fake, None, []).for_allowance())
        self.assertEqual(fake.naps, [])

    def test_it_waits_half_an_hour_at_a_time_up_to_the_hours_given(self):
        fake, said = FakeTime(1), []
        waiter = self.waiter(fake, 1.5, said)
        self.assertEqual([waiter.for_allowance() for _ in range(4)], [True, True, True, False])
        self.assertEqual(sum(fake.naps), 3 * 1800)
        self.assertTrue(all(nap <= 600 for nap in fake.naps))
        self.assertTrue(all("30 minutes" in line for line in said[:3]), said)

    def test_what_is_left_of_the_total_is_waited_in_full_and_no_more(self):
        fake = FakeTime(1)
        waiter = self.waiter(fake, 0.75, [])
        self.assertEqual([waiter.for_allowance() for _ in range(3)], [True, True, False])
        self.assertEqual(sum(fake.naps), 1800 + 900)

    def test_the_wait_sleeps_in_steps_of_at_most_ten_minutes(self):
        fake = FakeTime(1)
        self.waiter(fake, 1, []).for_allowance()
        self.assertEqual(fake.naps, [600, 600, 600])


if __name__ == "__main__":
    unittest.main()
