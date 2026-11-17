// LOFI-FORK: the podcasts section's voice boost and silence trimming (see FORK.md).
import { describe, expect, it } from "vitest"

import {
  boostLabel,
  parseBoost,
  parseShowBoost,
  parseShowTrim,
  parseTrim,
  savedLabel,
  trimLabel,
} from "./sound"

describe("sound choices", () => {
  it("reads stored values and falls back to off", () => {
    expect(parseBoost("medium")).toBe("medium")
    expect(parseBoost("loud")).toBe("off")
    expect(parseBoost(undefined)).toBe("off")
    expect(parseTrim("strong")).toBe("strong")
    expect(parseTrim(3)).toBe("off")
  })
  it("a show with no choice follows the main setting, and off is a choice", () => {
    expect(parseShowBoost(null)).toBeNull()
    expect(parseShowBoost("nope")).toBeNull()
    expect(parseShowBoost("off")).toBe("off")
    expect(parseShowTrim("mild")).toBe("mild")
    expect(parseShowTrim(undefined)).toBeNull()
  })
  it("has words for each choice", () => {
    expect(boostLabel("high")).toBe("High")
    expect(trimLabel("off")).toBe("Off")
  })
  it("says how much time was saved", () => {
    expect(savedLabel(0)).toBe("Nothing saved yet")
    expect(savedLabel(0.4)).toBe("Nothing saved yet")
    expect(savedLabel(40)).toBe("40 s saved")
    expect(savedLabel(300)).toBe("5 min saved")
    expect(savedLabel(3900)).toBe("1 h 5 min saved")
  })
})
