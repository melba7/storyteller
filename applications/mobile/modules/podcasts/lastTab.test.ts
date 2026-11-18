import { describe, expect, it } from "vitest"

import { lastTabSegments, rememberTabFrom, resetLastTab } from "./lastTab"
import { tabBase } from "./routes"

describe("lastTab", () => {
  it("starts in Home", () => {
    resetLastTab()
    expect(tabBase(lastTabSegments())).toBe("/podcasts/(tabs)/(home)")
  })

  it("remembers the tab the segments are in", () => {
    resetLastTab()
    rememberTabFrom(["podcasts", "(tabs)", "(library)", "show", "[id]"])
    expect(tabBase(lastTabSegments())).toBe("/podcasts/(tabs)/(library)")
  })

  it("keeps the last tab while the player (no tab in the segments) is up", () => {
    resetLastTab()
    rememberTabFrom(["podcasts", "(tabs)", "(search)"])
    rememberTabFrom(["podcasts", "player"])
    expect(tabBase(lastTabSegments())).toBe("/podcasts/(tabs)/(search)")
  })

  it("follows a change of tab", () => {
    resetLastTab()
    rememberTabFrom(["podcasts", "(tabs)", "(new)"])
    rememberTabFrom(["podcasts", "(tabs)", "(library)"])
    expect(tabBase(lastTabSegments())).toBe("/podcasts/(tabs)/(library)")
  })
})
