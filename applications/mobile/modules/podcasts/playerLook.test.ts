// LOFI-FORK: the podcasts section's full-screen player (see FORK.md).
import { describe, expect, it } from "vitest"

import {
  PLAYER_FALLBACK_BACKGROUND,
  barFraction,
  playerBackground,
  positionAt,
  progressFraction,
} from "./playerLook"

describe("playerBackground", () => {
  it("falls back to the dark theme colour without a usable colour", () => {
    expect(playerBackground(null)).toBe(PLAYER_FALLBACK_BACKGROUND)
    expect(playerBackground("")).toBe(PLAYER_FALLBACK_BACKGROUND)
    expect(playerBackground("blue")).toBe(PLAYER_FALLBACK_BACKGROUND)
    expect(playerBackground("#12345")).toBe(PLAYER_FALLBACK_BACKGROUND)
  })

  it("keeps a colour that is already dark", () => {
    expect(playerBackground("#102030")).toBe("#102030")
  })

  it("darkens a bright colour, keeping its hue", () => {
    const result = playerBackground("#ffcc00")
    const r = parseInt(result.slice(1, 3), 16)
    const g = parseInt(result.slice(3, 5), 16)
    const b = parseInt(result.slice(5, 7), 16)
    expect((0.299 * r + 0.587 * g + 0.114 * b) / 255).toBeLessThanOrEqual(0.33)
    expect(r).toBeGreaterThan(g)
    expect(g).toBeGreaterThan(b)
  })

  it("turns white into a dark grey", () => {
    const result = playerBackground("#FFFFFF")
    expect(result).toMatch(/^#[0-9a-f]{6}$/)
    expect(parseInt(result.slice(1, 3), 16)).toBeLessThan(100)
  })
})

describe("the seek bar", () => {
  it("turns a touch into a fraction of the bar", () => {
    expect(barFraction(50, 200)).toBe(0.25)
    expect(barFraction(-10, 200)).toBe(0)
    expect(barFraction(500, 200)).toBe(1)
    expect(barFraction(10, 0)).toBe(0)
  })

  it("turns a fraction into a place in the episode", () => {
    expect(positionAt(0.5, 600)).toBe(300)
    expect(positionAt(2, 600)).toBe(600)
    expect(positionAt(0.5, null)).toBe(0)
  })

  it("fills the bar by how far along the episode is", () => {
    expect(progressFraction(150, 600)).toBe(0.25)
    expect(progressFraction(900, 600)).toBe(1)
    expect(progressFraction(10, null)).toBe(0)
  })
})
