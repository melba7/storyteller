// LOFI-FORK: the podcasts section's category colours (see FORK.md).
import { describe, expect, it } from "vitest"

import { CATEGORY_COLORS, categoryColors } from "./categoryColors"
import { CHART_CATEGORIES } from "./charts"

describe("CATEGORY_COLORS", () => {
  it("has a colour for every category in the chart list", () => {
    for (const category of CHART_CATEGORIES) {
      expect(CATEGORY_COLORS[category.id], category.name).toMatch(
        /^#[0-9a-f]{6}$/,
      )
    }
  })
})

describe("categoryColors", () => {
  it("gives a lighter top, a deeper bottom and a symbol shade", () => {
    const { from, to, symbol } = categoryColors("1533")
    expect(from).toMatch(/^#[0-9a-f]{6}$/)
    expect(to).toMatch(/^#[0-9a-f]{6}$/)
    expect(symbol).toMatch(/^#[0-9a-f]{6}$/)
    expect(from).not.toBe(to)
  })

  it("falls back to a grey for a category it does not know", () => {
    expect(categoryColors("nope").from).toMatch(/^#[0-9a-f]{6}$/)
  })
})
