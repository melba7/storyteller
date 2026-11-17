// LOFI-FORK: the podcasts section's playback settings (see FORK.md).
import { describe, expect, it } from "vitest"

import { isPlayed } from "./playbackRules"
import {
  DEFAULT_PLAYBACK_SETTINGS,
  markPlayedLabel,
  parsePlaybackSettings,
  secondsLabel,
  skipLabel,
} from "./playbackSettings"

describe("parsePlaybackSettings", () => {
  it("defaults to what the player used before", () => {
    expect(DEFAULT_PLAYBACK_SETTINGS.skipBack).toBe(10)
    expect(DEFAULT_PLAYBACK_SETTINGS.skipForward).toBe(45)
    expect(parsePlaybackSettings(undefined)).toEqual(DEFAULT_PLAYBACK_SETTINGS)
    expect(parsePlaybackSettings("nope")).toEqual(DEFAULT_PLAYBACK_SETTINGS)
  })
  it("reads stored values", () => {
    const saved = {
      skipBack: 15,
      skipForward: 30,
      headphoneNext: "nextEpisode",
      markPlayedWhenLeft: 60,
      rewindAfterPause: true,
    }
    expect(parsePlaybackSettings(saved)).toEqual(saved)
  })
  it("keeps the default for anything that is not a choice", () => {
    expect(
      parsePlaybackSettings({
        skipBack: 7,
        skipForward: "45",
        headphoneNext: "teleport",
        markPlayedWhenLeft: 25,
        rewindAfterPause: "yes",
      }),
    ).toEqual(DEFAULT_PLAYBACK_SETTINGS)
  })
})

describe("labels", () => {
  it("reads naturally", () => {
    expect(secondsLabel(5)).toBe("5 s")
    expect(secondsLabel(60)).toBe("1 min")
    expect(markPlayedLabel(0)).toBe("Off")
    expect(markPlayedLabel(30)).toBe("30 s")
    expect(skipLabel("back", 15)).toBe("Back 15 seconds")
    expect(skipLabel("ahead", 45)).toBe("Ahead 45 seconds")
  })
})

describe("isPlayed with a wider window", () => {
  it("counts the last N seconds as played", () => {
    expect(isPlayed(570, 600, false, 30)).toBe(true)
    expect(isPlayed(569, 600, false, 30)).toBe(false)
  })
  it("keeps the 5 seconds when off or smaller", () => {
    expect(isPlayed(595, 600, false, 0)).toBe(true)
    expect(isPlayed(594, 600, false, 0)).toBe(false)
    expect(isPlayed(596, 600, false, 2)).toBe(true)
  })
  it("needs a known length", () => {
    expect(isPlayed(595, null, false, 60)).toBe(false)
  })
})
