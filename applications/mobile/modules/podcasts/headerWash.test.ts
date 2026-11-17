// LOFI-FORK: the podcasts section's show page wash (see FORK.md).
import { readFileSync } from "node:fs"
import { join } from "node:path"

import { describe, expect, it } from "vitest"

import { blendOver, contrastBetween } from "./artworkTint"
import { WASH_MAX, WASH_MIN, headerWash, washStyle } from "./headerWash"

const root = join(__dirname, "../..")
const globalCss = readFileSync(join(root, "global.css"), "utf8")
const themesCss = readFileSync(join(root, "podcasts/themes.css"), "utf8")

/** The background and foreground of the `@variant` block with this name. */
function themeColors(css: string, name: string) {
  const start = css.indexOf(`@variant ${name} {`)
  expect(start, name).toBeGreaterThan(-1)
  const block = css.slice(start, css.indexOf("}", start))
  const read = (variable: string) =>
    new RegExp(`--color-${variable}:\\s*(#[0-9a-f]{6})`, "i").exec(
      block,
    )?.[1] ?? ""
  return { background: read("background"), foreground: read("foreground") }
}

const THEMES = {
  light: themeColors(globalCss, "light"),
  dark: themeColors(globalCss, "dark"),
  black: themeColors(themesCss, "pod-black"),
  midnight: themeColors(themesCss, "pod-midnight"),
  paper: themeColors(themesCss, "pod-paper"),
  forest: themeColors(themesCss, "pod-forest"),
}

const SAMPLES = [
  "#ffffff",
  "#000000",
  "#ff0000",
  "#00ff00",
  "#0000ff",
  "#ffff00",
  "#ff00ff",
  "#00ffff",
  "#808080",
  "#ffcc00",
  "#336699",
  "#7fff00",
]

describe("headerWash", () => {
  it("reads real colours for all six themes", () => {
    for (const colors of Object.values(THEMES)) {
      expect(colors.background).toMatch(/^#[0-9a-f]{6}$/i)
      expect(colors.foreground).toMatch(/^#[0-9a-f]{6}$/i)
    }
  })

  for (const [name, { background, foreground }] of Object.entries(THEMES)) {
    it(`keeps the text at 4.5:1 in ${name}, for every sample colour`, () => {
      for (const color of SAMPLES) {
        const alpha = headerWash(color, background, foreground)
        expect(alpha).toBeGreaterThanOrEqual(WASH_MIN)
        expect(alpha).toBeLessThanOrEqual(WASH_MAX)
        const blended = blendOver(color, background, alpha)
        expect(contrastBetween(foreground, blended)).toBeGreaterThanOrEqual(4.5)
      }
    })

    it(`is the strongest alpha that holds in ${name}`, () => {
      for (const color of SAMPLES) {
        const alpha = headerWash(color, background, foreground)
        if (alpha >= WASH_MAX) continue
        // A little stronger would break the limit (the search steps by 0.01).
        const stronger = blendOver(color, background, alpha + 0.011)
        expect(contrastBetween(foreground, stronger)).toBeLessThan(4.5)
      }
    })
  }

  it("takes the full 0.45 where the colour is close to the background", () => {
    expect(headerWash("#0a0a0a", "#0a0a0a", "#fafafa")).toBe(WASH_MAX)
  })

  it("falls back to the weakest wash when nothing holds", () => {
    // Mid-grey text on a mid-grey page never reaches 4.5:1.
    expect(headerWash("#ffffff", "#808080", "#909090")).toBe(WASH_MIN)
  })

  it("gives the weakest wash for a colour it cannot read", () => {
    expect(headerWash("not a colour", "#000000", "#ffffff")).toBe(WASH_MIN)
  })
})

describe("washStyle", () => {
  it("fades from the blended colour to the page colour", () => {
    const style = washStyle("#336699", 0.3, "#000000")
    expect(style.backgroundImage).toBe(
      `linear-gradient(180deg, ${blendOver("#336699", "#000000", 0.3)}, #000000)`,
    )
  })

  it("has a plain colour for a screen that can't draw the gradient", () => {
    const style = washStyle("#336699", 0.3, "#ffffff")
    expect(style.backgroundColor).toBe(blendOver("#336699", "#ffffff", 0.15))
  })

  it("is the page colour for a colour it cannot read", () => {
    expect(washStyle("nope", 0.3, "#101010")).toEqual({
      backgroundColor: "#101010",
    })
  })
})
