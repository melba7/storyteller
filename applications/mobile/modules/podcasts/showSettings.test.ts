// LOFI-FORK: the podcasts section's per-show settings tests (see FORK.md).
import { describe, expect, it } from "vitest"

import {
  DEFAULT_SHOW_SETTINGS,
  SETTING_COLUMNS,
  afterDaysLabel,
  afterPlayedLabel,
  clampSkip,
  followLabel,
  keepNewestLabel,
  settingsMirror,
  showSettingsFromRow,
  showSettingsToValues,
  skipLabel,
  stepSkip,
  upNextLabel,
} from "./showSettings"

describe("defaults", () => {
  it("download and notify are on, everything else is off or follows the app", () => {
    expect(DEFAULT_SHOW_SETTINGS).toMatchObject({
      skipIntro: 0,
      skipOutro: 0,
      speed: null,
      autoDownload: true,
      autoUpNext: "off",
      notify: true,
      skipAds: null,
      skipPlugs: null,
      voiceBoost: null,
      trimSilence: null,
      archiveAfterPlayed: "never",
      archiveAfterDays: null,
      keepNewest: null,
      sort: "newest",
      groupBySeason: false,
      showArchived: false,
    })
  })

  it("is what an empty row gives", () => {
    expect(showSettingsFromRow({})).toEqual(DEFAULT_SHOW_SETTINGS)
  })
})

describe("skip lengths", () => {
  it("stay in 0 to 120 in steps of 5", () => {
    expect(clampSkip(-10)).toBe(0)
    expect(clampSkip(7)).toBe(5)
    expect(clampSkip(8)).toBe(10)
    expect(clampSkip(500)).toBe(120)
    expect(clampSkip(Number.NaN)).toBe(0)
    expect(stepSkip(120, 1)).toBe(120)
    expect(stepSkip(0, -1)).toBe(0)
    expect(stepSkip(30, 1)).toBe(35)
    expect(stepSkip(30, -1)).toBe(25)
  })
})

describe("reading a row", () => {
  it("takes every column and clamps the odd ones", () => {
    expect(
      showSettingsFromRow({
        skip_intro: 33,
        skip_outro: 900,
        speed: 1.5,
        auto_download: 0,
        auto_up_next: "bottom",
        notify: 0,
        skip_ads: 1,
        skip_plugs: 0,
        archive_after_played: "week",
        archive_after_days: 14,
        keep_newest: 5,
        episode_sort: "longest",
        group_by_season: 1,
        show_archived: 1,
        voice_boost: "high",
        trim_silence: "off",
      }),
    ).toEqual({
      skipIntro: 35,
      skipOutro: 120,
      speed: 1.5,
      autoDownload: false,
      autoUpNext: "bottom",
      notify: false,
      skipAds: true,
      skipPlugs: false,
      archiveAfterPlayed: "week",
      archiveAfterDays: 14,
      keepNewest: 5,
      sort: "longest",
      groupBySeason: true,
      showArchived: true,
      voiceBoost: "high",
      trimSilence: "off",
    })
  })

  it("falls back for values it does not know", () => {
    const settings = showSettingsFromRow({
      auto_up_next: "middle",
      archive_after_played: "soon",
      archive_after_days: 3,
      keep_newest: 7,
      episode_sort: "random",
    })
    expect(settings).toEqual(DEFAULT_SHOW_SETTINGS)
  })

  it("round-trips through the column values", () => {
    const settings = {
      ...DEFAULT_SHOW_SETTINGS,
      skipIntro: 15,
      speed: 1.2,
      skipAds: false,
      autoUpNext: "top" as const,
      keepNewest: 2,
    }
    const values = showSettingsToValues(settings)
    expect(values).toHaveLength(SETTING_COLUMNS.length)
    const row = Object.fromEntries(
      SETTING_COLUMNS.map((column, index) => [column, values[index]]),
    )
    expect(showSettingsFromRow(row)).toEqual(settings)
  })
})

describe("settingsMirror", () => {
  it("leaves out a show with nothing set", () => {
    expect(
      settingsMirror([{ id: "a", settings: DEFAULT_SHOW_SETTINGS }]),
    ).toEqual({})
  })

  it("carries what the player needs", () => {
    expect(
      settingsMirror([
        {
          id: "a",
          settings: {
            ...DEFAULT_SHOW_SETTINGS,
            skipIntro: 30,
            skipOutro: 10,
            speed: 1.4,
            skipAds: true,
            autoDownload: false,
          },
        },
        { id: "b", settings: { ...DEFAULT_SHOW_SETTINGS, skipPlugs: false } },
        { id: "c", settings: { ...DEFAULT_SHOW_SETTINGS, trimSilence: "off" } },
        { id: "d", settings: { ...DEFAULT_SHOW_SETTINGS, voiceBoost: "low" } },
      ]),
    ).toEqual({
      a: { introSeconds: 30, outroSeconds: 10, speed: 1.4, skipAds: true },
      b: { introSeconds: 0, outroSeconds: 0, skipPlugs: false },
      // Off is the show's own choice, so it is kept.
      c: { introSeconds: 0, outroSeconds: 0, trimSilence: "off" },
      d: { introSeconds: 0, outroSeconds: 0, voiceBoost: "low" },
    })
  })
})

describe("labels", () => {
  it("read in plain words", () => {
    expect(skipLabel(0)).toBe("Off")
    expect(skipLabel(45)).toBe("45 seconds")
    expect(skipLabel(60)).toBe("1 minute")
    expect(skipLabel(90)).toBe("1 minute 30 seconds")
    expect(upNextLabel("top")).toBe("Top")
    expect(upNextLabel("off")).toBe("Off")
    expect(followLabel(null)).toBe("Follow the main setting")
    expect(followLabel(true)).toBe("On")
    expect(afterPlayedLabel("now")).toBe("Right away")
    expect(afterDaysLabel(null)).toBe("Never")
    expect(afterDaysLabel(7)).toBe("After 1 week")
    expect(afterDaysLabel(56)).toBe("After 8 weeks")
    expect(keepNewestLabel(null)).toBe("All episodes")
    expect(keepNewestLabel(5)).toBe("The newest 5")
  })
})
