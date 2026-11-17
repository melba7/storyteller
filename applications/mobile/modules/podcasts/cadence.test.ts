// LOFI-FORK: the podcasts section's update-rhythm rule (see FORK.md).
import { describe, expect, it } from "vitest"

import { cadenceWord } from "./cadence"
import { updateFrequency } from "./episodeRowLook"
import { updateCadence } from "./homeLook"

const NOW = new Date(2026, 10, 17, 12, 0).getTime()
const DAY = 24 * 3_600_000
const every = (days: number, count = 6, lastAgo = 0) =>
  Array.from({ length: count }, (_, i) => NOW - (lastAgo + i * days) * DAY)

describe("cadenceWord", () => {
  it("names daily, weekly, biweekly and monthly shows", () => {
    expect(cadenceWord(every(1), NOW)).toBe("Daily")
    expect(cadenceWord(every(3), NOW)).toBe("Weekly")
    expect(cadenceWord(every(7), NOW)).toBe("Weekly")
    expect(cadenceWord(every(14), NOW)).toBe("Biweekly")
    expect(cadenceWord(every(30), NOW)).toBe("Monthly")
  })

  it("is empty for few dates, a quiet show or a rare one", () => {
    expect(cadenceWord(every(7, 2), NOW)).toBe("")
    expect(cadenceWord(every(7, 8, 200), NOW)).toBe("")
    expect(cadenceWord(every(90), NOW)).toBe("")
  })

  it("ignores order and missing dates", () => {
    expect(cadenceWord([null, ...every(7)].reverse(), NOW)).toBe("Weekly")
  })

  it("is the same word on Home and on the show page", () => {
    for (const days of [1, 2, 3, 5, 7, 10, 14, 21, 30, 60]) {
      const dates = every(days, 8, 1)
      const word = cadenceWord(dates, NOW)
      expect(updateFrequency(dates, NOW)).toBe(word)
      expect(updateCadence(dates, NOW)).toBe(word ? `Updated ${word}` : "")
    }
  })
})
