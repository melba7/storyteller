// LOFI-FORK: the podcasts section's full-screen player (see FORK.md).
import { describe, expect, it } from "vitest"

import { contrastBetween } from "./artworkTint"
import { PLAYER_FALLBACK_BACKGROUND } from "./playerLook"
import {
  dateWords,
  inkFor,
  isLightSheet,
  leftWords,
  miniSubtitle,
  sheetColors,
  titleFade,
} from "./playerSheet"

describe("inkFor", () => {
  it("is white on dark colours and black on light ones", () => {
    expect(inkFor("#000080")).toBe("#ffffff")
    expect(inkFor("#102030")).toBe("#ffffff")
    expect(inkFor("#ffffff")).toBe("#000000")
    expect(inkFor("#f5e663")).toBe("#000000")
  })

  it("always reads at least as well as the other choice", () => {
    for (const color of ["#808080", "#e07030", "#3060c0", "#40a040"]) {
      const ink = inkFor(color)
      const other = ink === "#ffffff" ? "#000000" : "#ffffff"
      expect(contrastBetween(color, ink)).toBeGreaterThanOrEqual(
        contrastBetween(color, other),
      )
    }
  })
})

describe("sheetColors", () => {
  it("falls back to the dark colour with white ink", () => {
    for (const bad of [null, "blue", ""]) {
      const colors = sheetColors(bad)
      expect(colors.top).toBe(PLAYER_FALLBACK_BACKGROUND)
      expect(colors.ink).toBe("#ffffff")
    }
  })

  it("uses the artwork's colour and a darker bottom", () => {
    const colors = sheetColors("#000080")
    expect(colors.top).toBe("#000080")
    expect(colors.bottom).not.toBe(colors.top)
    expect(colors.mid).not.toBe(colors.top)
    expect(colors.mid).not.toBe(colors.bottom)
    expect(colors.ink).toBe("#ffffff")
  })

  it("takes a colour without its hash", () => {
    expect(sheetColors("000080").top).toBe("#000080")
  })

  it("keeps the softened text readable on a dark and on a light sheet", () => {
    for (const color of ["#000080", "#f5e663", "#ffffff"]) {
      const colors = sheetColors(color)
      expect(contrastBetween(colors.tint, colors.top)).toBeGreaterThan(3)
      expect(colors.rest).not.toBe(colors.fill)
    }
  })

  it("says whether the sheet is light", () => {
    expect(isLightSheet("#ffffff")).toBe(true)
    expect(isLightSheet("#000080")).toBe(false)
    expect(isLightSheet(null)).toBe(false)
  })
})

describe("titleFade", () => {
  it("goes from clear to the sheet's colour", () => {
    expect(titleFade("#102030")).toBe(
      "linear-gradient(90deg, rgba(16,32,48,0), rgb(16,32,48))",
    )
  })

  it("draws nothing for a colour it can't read", () => {
    expect(titleFade("blue")).toBe("none")
  })
})

describe("dateWords", () => {
  const now = new Date(2026, 10, 17).getTime()
  it("says the month and day this year", () => {
    expect(dateWords(new Date(2026, 10, 12).getTime(), now)).toBe("November 12")
  })
  it("adds the year for another year", () => {
    expect(dateWords(new Date(2024, 0, 5).getTime(), now)).toBe(
      "January 5, 2024",
    )
  })
  it("is empty without a date", () => {
    expect(dateWords(null, now)).toBe("")
    expect(dateWords(Number.NaN, now)).toBe("")
  })
})

describe("leftWords", () => {
  it("rounds up to whole minutes", () => {
    expect(leftWords(0, 721)).toBe("13m left")
    expect(leftWords(600, 1500)).toBe("15m left")
  })
  it("uses hours from sixty minutes", () => {
    expect(leftWords(0, 3600)).toBe("1h left")
    expect(leftWords(0, 3900)).toBe("1h 5m left")
  })
  it("is empty when finished or unknown", () => {
    expect(leftWords(100, 100)).toBe("")
    expect(leftWords(0, null)).toBe("")
    expect(leftWords(0, 0)).toBe("")
  })
})

describe("miniSubtitle", () => {
  const now = new Date(2026, 10, 17).getTime()
  const published = new Date(2026, 10, 12).getTime()
  it("says the time left once the episode is under way", () => {
    expect(miniSubtitle(600, 1500, published, now)).toBe("15m left")
  })
  it("says the date for one not started", () => {
    expect(miniSubtitle(0, 1500, published, now)).toBe("November 12")
  })
  it("is empty with neither", () => {
    expect(miniSubtitle(0, null, null, now)).toBe("")
  })
})
