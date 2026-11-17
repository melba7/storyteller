// LOFI-FORK: the podcasts section's stats rules (see FORK.md).
import { describe, expect, it } from "vitest"

import {
  type DayBar,
  dayKey,
  formatDuration,
  lastDays,
  readStats,
  savedRows,
  totalSaved,
} from "./stats"

function day(days: DayBar[], index: number): DayBar {
  return days[index] as DayBar
}

describe("formatDuration", () => {
  it("shows hours and minutes", () => {
    expect(formatDuration(3 * 3600 + 12 * 60)).toBe("3 h 12 min")
  })
  it("shows only minutes under an hour", () => {
    expect(formatDuration(45 * 60)).toBe("45 min")
  })
  it("leaves out zero minutes after hours", () => {
    expect(formatDuration(2 * 3600)).toBe("2 h")
  })
  it("rounds to the nearest minute, carrying into the hour", () => {
    expect(formatDuration(59 * 60 + 40)).toBe("1 h")
    expect(formatDuration(90 + 1)).toBe("2 min")
  })
  it("says under a minute for a little time and 0 min for none", () => {
    expect(formatDuration(20)).toBe("under 1 min")
    expect(formatDuration(0)).toBe("0 min")
  })
  it("treats bad numbers as none", () => {
    expect(formatDuration(Number.NaN)).toBe("0 min")
    expect(formatDuration(-50)).toBe("0 min")
    expect(formatDuration(Number.POSITIVE_INFINITY)).toBe("0 min")
  })
})

describe("readStats", () => {
  it("reads what Swift sends", () => {
    const stats = readStats({
      listened: 100,
      savedBySpeed: 10,
      savedBySkipping: 20,
      savedByTrim: 30,
      savedByAds: 40,
      savedByChapters: 50,
      days: { "2026-11-17": 60 },
    })
    expect(stats.listened).toBe(100)
    expect(stats.savedByAds).toBe(40)
    expect(stats.days).toEqual({ "2026-11-17": 60 })
  })
  it("turns anything else into zeros", () => {
    expect(readStats(null).listened).toBe(0)
    const stats = readStats({ listened: "x", savedByTrim: -1, days: [1, 2] })
    expect(stats.listened).toBe(0)
    expect(stats.savedByTrim).toBe(0)
    expect(stats.days).toEqual({})
  })
  it("drops days that are not a day or not a good number", () => {
    const stats = readStats({
      days: { "2026-11-17": 5, today: 4, "2026-11-18": Number.NaN },
    })
    expect(stats.days).toEqual({ "2026-11-17": 5 })
  })
})

describe("the savings", () => {
  const stats = readStats({
    savedBySpeed: 600,
    savedBySkipping: 60,
    savedByTrim: 120,
    savedByAds: 0,
    savedByChapters: 30,
  })
  it("adds them up", () => {
    expect(totalSaved(stats)).toBe(810)
  })
  it("lists the five kinds in order with a label", () => {
    expect(savedRows(stats).map((row) => row.label)).toEqual([
      "Speed",
      "Intros and outros",
      "Trimmed silence",
      "Skipped ads",
      "Skipped chapters",
    ])
    expect(savedRows(stats)[0]?.seconds).toBe(600)
  })
})

describe("dayKey", () => {
  it("is the phone's local day", () => {
    expect(dayKey(new Date(2026, 10, 7, 23, 59))).toBe("2026-11-07")
    expect(dayKey(new Date(2026, 0, 1, 0, 1))).toBe("2026-01-01")
  })
})

describe("lastDays", () => {
  const today = new Date(2026, 10, 17, 9, 0)

  it("gives 30 days ending today, oldest first", () => {
    const days = lastDays({}, today)
    expect(days).toHaveLength(30)
    expect(day(days, 29).key).toBe("2026-11-17")
    expect(day(days, 0).key).toBe("2026-10-19")
  })
  it("steps over a month and a year end", () => {
    const days = lastDays({}, new Date(2027, 0, 5, 12))
    expect(day(days, 0).key).toBe("2026-12-07")
    expect(day(days, 24).key).toBe("2026-12-31")
    expect(day(days, 25).key).toBe("2027-01-01")
  })
  it("scales the bars to the busiest day", () => {
    const days = lastDays({ "2026-11-17": 3600, "2026-11-16": 1800 }, today)
    expect(day(days, 29).height).toBe(1)
    expect(day(days, 28).height).toBe(0.5)
    expect(day(days, 27).height).toBe(0)
  })
  it("keeps a short day visible", () => {
    const days = lastDays({ "2026-11-17": 100000, "2026-11-16": 60 }, today)
    expect(day(days, 28).height).toBeGreaterThan(0.03)
  })
  it("has no bars at all when nothing was heard", () => {
    expect(lastDays({}, today).every((day) => day.height === 0)).toBe(true)
  })
  it("labels days like 17 Nov, and a few of them are shown", () => {
    const days = lastDays({}, today)
    expect(day(days, 29).label).toBe("17 Nov")
    expect(day(days, 29).showLabel).toBe(true)
    expect(day(days, 28).showLabel).toBe(false)
    expect(days.filter((day) => day.showLabel).length).toBeLessThanOrEqual(4)
  })
  it("ignores days older than the 30", () => {
    const days = lastDays({ "2026-01-01": 9999 }, today)
    expect(days.every((day) => day.seconds === 0)).toBe(true)
  })
})
