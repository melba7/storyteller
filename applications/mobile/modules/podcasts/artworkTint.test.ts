// LOFI-FORK: the podcasts section's full-screen player (see FORK.md).
import { describe, expect, it } from "vitest"

import {
  HEADER_FALLBACK,
  contrastBetween,
  gradientEnds,
  headerColors,
  playerGradient,
  vivid,
  contrastWithWhite,
} from "./artworkTint"
import { PLAYER_FALLBACK_BACKGROUND } from "./playerLook"

function saturation(hex: string): number {
  const r = parseInt(hex.slice(1, 3), 16)
  const g = parseInt(hex.slice(3, 5), 16)
  const b = parseInt(hex.slice(5, 7), 16)
  const max = Math.max(r, g, b)
  return max === 0 ? 0 : (max - Math.min(r, g, b)) / max
}

const SAMPLES: (string | null)[] = [
  "#ffffff",
  "#ffff00",
  "#000000",
  "#ffcc00",
  "#00ff00",
  "#00ffff",
  "#ff0000",
  "#0000ff",
  "#ff00ff",
  "#808080",
  "#8a7f7a",
  "#c0c0c0",
  "#7fff00",
  "#102030",
  "not a colour",
  null,
]

describe("vivid", () => {
  it("raises the saturation of a greyish colour and keeps its hue", () => {
    const result = vivid("#8a7f7a")
    expect(saturation(result)).toBeGreaterThan(saturation("#8a7f7a"))
    const r = parseInt(result.slice(1, 3), 16)
    const b = parseInt(result.slice(5, 7), 16)
    expect(r).toBeGreaterThan(b)
  })

  it("leaves true greys, white and black alone", () => {
    expect(vivid("#ffffff")).toBe("#ffffff")
    expect(vivid("#000000")).toBe("#000000")
    expect(vivid("#808080")).toBe("#808080")
  })

  it("leaves an already vivid colour alone", () => {
    expect(vivid("#ff0000")).toBe("#ff0000")
  })

  it("passes an unusable colour through", () => {
    expect(vivid("blue")).toBe("blue")
  })
})

describe("playerGradient", () => {
  it("keeps white text at 4.5:1 on both ends for every sample", () => {
    for (const color of SAMPLES) {
      const [top, bottom] = gradientEnds(color)
      expect(contrastWithWhite(top), `${color} top`).toBeGreaterThanOrEqual(4.5)
      expect(
        contrastWithWhite(bottom),
        `${color} bottom`,
      ).toBeGreaterThanOrEqual(4.5)
    }
  })

  it("makes the bottom darker than the top", () => {
    const [top, bottom] = gradientEnds("#3366cc")
    expect(contrastWithWhite(bottom)).toBeGreaterThan(contrastWithWhite(top))
  })

  it("falls back to the dark theme colour without a colour", () => {
    expect(gradientEnds(null)[0]).toBe(PLAYER_FALLBACK_BACKGROUND)
  })

  it("is the style string for the player's background", () => {
    const [top, bottom] = gradientEnds("#3366cc")
    expect(playerGradient("#3366cc")).toBe(
      `linear-gradient(180deg, ${top}, ${bottom})`,
    )
  })
})

describe("headerColors", () => {
  it("keeps white text readable and the tint lighter than the background", () => {
    for (const color of ["#2e7d6b", "#f5d90a", "#ffffff", "#101010", null]) {
      const { background, tint } = headerColors(color)
      expect(contrastWithWhite(background)).toBeGreaterThanOrEqual(4.5)
      expect(contrastBetween(tint, background)).toBeGreaterThan(3)
    }
  })

  it("uses a plain dark grey without a colour", () => {
    expect(headerColors(null).background).toBe(HEADER_FALLBACK)
  })
})
