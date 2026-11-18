// LOFI-FORK: the podcasts section's player rules (see FORK.md).
import { describe, expect, it } from "vitest"

import type { StoredEpisode } from "./library"
import {
  clampSpeed,
  miniPlayerLabel,
  formatTime,
  isPlayed,
  resumeStart,
  showsMiniPlayer,
  speedLabel,
  stepSpeed,
  timeLeft,
} from "./playbackRules"

describe("formatTime", () => {
  it("reads seconds, minutes and hours", () => {
    expect(formatTime(5)).toBe("0:05")
    expect(formatTime(754)).toBe("12:34")
    expect(formatTime(3723)).toBe("1:02:03")
    expect(formatTime(59.9)).toBe("0:59")
  })

  it("reads nonsense as zero", () => {
    expect(formatTime(-4)).toBe("0:00")
    expect(formatTime(Number.NaN)).toBe("0:00")
  })
})

describe("timeLeft", () => {
  it("shows the time left with a minus", () => {
    expect(timeLeft(0, 754)).toBe("-12:34")
    expect(timeLeft(3600, 3723)).toBe("-2:03")
    expect(timeLeft(800, 754)).toBe("-0:00")
  })

  it("shows dashes while the length is unknown", () => {
    expect(timeLeft(10, null)).toBe("--:--")
    expect(timeLeft(10, 0)).toBe("--:--")
  })
})

describe("speed", () => {
  it("is labelled with one decimal", () => {
    expect(speedLabel(1)).toBe("1.0x")
    expect(speedLabel(1.5)).toBe("1.5x")
    expect(speedLabel(2.4)).toBe("2.4x")
  })

  it("steps by a tenth inside 0.5x to 3.0x", () => {
    expect(stepSpeed(1, 1)).toBe(1.1)
    expect(stepSpeed(1.1, 1)).toBe(1.2)
    expect(stepSpeed(1, -1)).toBe(0.9)
    expect(stepSpeed(3, 1)).toBe(3)
    expect(stepSpeed(0.5, -1)).toBe(0.5)
  })

  it("rounds to a tenth and clamps", () => {
    expect(clampSpeed(1.26)).toBe(1.3)
    expect(clampSpeed(9)).toBe(3)
    expect(clampSpeed(0)).toBe(0.5)
    expect(clampSpeed(Number.NaN)).toBe(1)
  })
})

describe("resumeStart and isPlayed", () => {
  // The rule changed with Mo's OK (S14): the feed's length no longer decides where an episode
  // resumes. This test used to expect 0 for 595 and 700 of 600. Only the played mark and an
  // unusable place start an episode over.
  it("resumes where the listener stopped, unless played", () => {
    expect(resumeStart(120, 600, false)).toBe(120)
    expect(resumeStart(120, 600, true)).toBe(0)
    expect(resumeStart(595, 600, false)).toBe(595)
    expect(resumeStart(700, 600, false)).toBe(700)
    expect(resumeStart(120, null, false)).toBe(120)
  })

  it("keeps a place past the feed's length", () => {
    expect(resumeStart(3660, 3600, false)).toBe(3660)
    expect(resumeStart(3595, 3600, false)).toBe(3595)
    expect(resumeStart(3660, 3600, true)).toBe(0)
  })

  it("starts over for a place that is not a usable number", () => {
    expect(resumeStart(-5, 600, false)).toBe(0)
    expect(resumeStart(0, 600, false)).toBe(0)
    expect(resumeStart(Number.NaN, 600, false)).toBe(0)
    expect(resumeStart(Number.POSITIVE_INFINITY, 600, false)).toBe(0)
  })

  it("never starts later than the saved place", () => {
    for (const saved of [0, 0.4, 5, 590, 595, 600, 601, 3600, 99999]) {
      for (const duration of [null, 0, 1, 600, 3600]) {
        expect(resumeStart(saved, duration, false)).toBeLessThanOrEqual(saved)
      }
    }
  })

  it("counts played at the end or within 5 seconds of it", () => {
    expect(isPlayed(10, 600, true)).toBe(true)
    expect(isPlayed(595, 600, false)).toBe(true)
    expect(isPlayed(594, 600, false)).toBe(false)
    expect(isPlayed(595, null, false)).toBe(false)
  })
})

describe("showsMiniPlayer", () => {
  it("shows when an episode is loaded or one was played before", () => {
    const episode = {} as StoredEpisode
    expect(showsMiniPlayer(null, null)).toBe(false)
    expect(showsMiniPlayer(episode, null)).toBe(true)
    expect(showsMiniPlayer(null, episode)).toBe(true)
  })
})

describe("miniPlayerLabel", () => {
  it("says the title and the time left for VoiceOver", () => {
    expect(miniPlayerLabel("Episode 4", 600, 3600)).toBe(
      "Open the player, Episode 4, 50 min left",
    )
    expect(miniPlayerLabel("Episode 4", 0, 3900)).toBe(
      "Open the player, Episode 4, 1 h 5 min left",
    )
  })

  it("leaves the time out when the length is unknown or used up", () => {
    expect(miniPlayerLabel("Episode 4", 10, null)).toBe(
      "Open the player, Episode 4",
    )
    expect(miniPlayerLabel("Episode 4", 3600, 3600)).toBe(
      "Open the player, Episode 4",
    )
  })
})
