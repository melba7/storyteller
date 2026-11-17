// LOFI-FORK: the podcasts section's themes (see FORK.md).
import { readFileSync } from "node:fs"
import { join } from "node:path"

import { describe, expect, it } from "vitest"

import {
  DEFAULT_CHOICE,
  EXTRA_THEME_IDS,
  THEMES,
  isDarkTheme,
  parseChoice,
  resolveThemeName,
  serializeChoice,
} from "./theme"

const root = join(__dirname, "../..")

describe("parseChoice", () => {
  it("gives the default for nothing, rubbish and non-objects", () => {
    expect(parseChoice(null)).toEqual(DEFAULT_CHOICE)
    expect(parseChoice("not json")).toEqual(DEFAULT_CHOICE)
    expect(parseChoice("42")).toEqual(DEFAULT_CHOICE)
    expect(parseChoice("null")).toEqual(DEFAULT_CHOICE)
  })

  it("follows the app by default", () => {
    expect(DEFAULT_CHOICE.mode).toBe("app")
  })

  it("round-trips a saved choice", () => {
    const choice = {
      mode: "ios" as const,
      theme: "pod-forest",
      lightTheme: "pod-paper",
      darkTheme: "pod-midnight",
    }
    expect(parseChoice(serializeChoice(choice))).toEqual(choice)
  })

  it("replaces unknown names and wrong kinds field by field", () => {
    const saved = JSON.stringify({
      mode: "ios",
      theme: "neon",
      lightTheme: "dark",
      darkTheme: "light",
    })
    expect(parseChoice(saved)).toEqual({
      ...DEFAULT_CHOICE,
      mode: "ios",
    })
    expect(parseChoice(JSON.stringify({ mode: "sideways" })).mode).toBe("app")
  })
})

describe("resolveThemeName", () => {
  const base = { ...DEFAULT_CHOICE, theme: "pod-midnight" }

  it("follows the app's own light or dark", () => {
    expect(resolveThemeName({ ...base, mode: "app" }, "dark", "light")).toBe(
      "dark",
    )
    expect(resolveThemeName({ ...base, mode: "app" }, "light", "dark")).toBe(
      "light",
    )
  })

  it("uses the picked theme whatever the schemes are", () => {
    expect(resolveThemeName({ ...base, mode: "theme" }, "light", "light")).toBe(
      "pod-midnight",
    )
  })

  it("follows iOS with the picked light and dark themes", () => {
    const choice = {
      mode: "ios" as const,
      theme: "dark",
      lightTheme: "pod-paper",
      darkTheme: "pod-black",
    }
    expect(resolveThemeName(choice, "light", "dark")).toBe("pod-black")
    expect(resolveThemeName(choice, "dark", "light")).toBe("pod-paper")
  })

  it("falls back to the app's scheme when iOS says nothing", () => {
    const choice = { ...DEFAULT_CHOICE, mode: "ios" as const }
    expect(resolveThemeName(choice, "dark", null)).toBe(choice.darkTheme)
    expect(resolveThemeName(choice, "light", undefined)).toBe(choice.lightTheme)
  })
})

describe("the theme list", () => {
  it("knows which themes are dark", () => {
    expect(isDarkTheme("light")).toBe(false)
    expect(isDarkTheme("pod-paper")).toBe(false)
    expect(isDarkTheme("dark")).toBe(true)
    expect(isDarkTheme("pod-black")).toBe(true)
    expect(isDarkTheme("pod-forest")).toBe(true)
  })

  it("has true black for Extra Dark", () => {
    const black = THEMES.find((theme) => theme.id === "pod-black")
    expect(black?.swatch.background).toBe("#000000")
  })

  it("has a swatch with real colours and a unique id and name each", () => {
    expect(new Set(THEMES.map((theme) => theme.id)).size).toBe(THEMES.length)
    expect(new Set(THEMES.map((theme) => theme.name)).size).toBe(THEMES.length)
    for (const theme of THEMES) {
      expect(theme.swatch.background).toMatch(/^#[0-9a-f]{6}$/)
      expect(theme.swatch.accent).toMatch(/^#[0-9a-f]{6}$/)
    }
  })
})

describe("the style files", () => {
  const css = readFileSync(join(root, "podcasts/themes.css"), "utf8")
  const global = readFileSync(join(root, "global.css"), "utf8")
  const metro = readFileSync(join(root, "metro.config.js"), "utf8")

  /** The variable names inside `@variant <id> { ... }`. */
  function variables(source: string, id: string): string[] {
    const start = source.indexOf(`@variant ${id} {`)
    expect(start).toBeGreaterThan(-1)
    const end = source.indexOf("}", start)
    return [...source.slice(start, end).matchAll(/(--[a-z-]+):/g)].map(
      (match) => match[1]!,
    )
  }

  it("declares every extra theme with the same variables as light and dark", () => {
    const expected = variables(global, "dark").sort()
    expect(expected.length).toBeGreaterThan(10)
    expect(variables(global, "light").sort()).toEqual(expected)
    for (const id of EXTRA_THEME_IDS) {
      expect(variables(css, id).sort()).toEqual(expected)
    }
  })

  it("draws each swatch in its theme's own background and accent", () => {
    /** A variable's value in the last `@variant <id> { ... }`, the one that wins. */
    function value(source: string, id: string, name: string) {
      const start = source.lastIndexOf(`@variant ${id} {`)
      expect(start).toBeGreaterThan(-1)
      const block = source.slice(start, source.indexOf("}", start))
      return new RegExp(`${name}:\\s*(#[0-9a-f]{6})`).exec(block)?.[1]
    }
    for (const theme of THEMES) {
      const source = EXTRA_THEME_IDS.includes(theme.id) ? css : global
      expect(value(source, theme.id, "--color-background")).toBe(
        theme.swatch.background,
      )
      expect(value(source, theme.id, "--color-primary")).toBe(
        theme.swatch.accent,
      )
    }
  })

  it("is pulled in by global.css and listed in the metro config", () => {
    expect(global).toMatch(/@import "\.\/podcasts\/themes\.css";/)
    for (const id of EXTRA_THEME_IDS) expect(metro).toContain(`"${id}"`)
  })
})
