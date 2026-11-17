// LOFI-FORK: the podcasts section's routes (see FORK.md).
import { describe, expect, it } from "vitest"

import { episodeHref, showHref, tabBase } from "./routes"

describe("tabBase", () => {
  it("stays in the Discover tab", () => {
    expect(
      tabBase(["(root)", "podcasts", "(tabs)", "(discover)", "discover"]),
    ).toBe("/podcasts/(tabs)/(discover)")
  })

  it("uses the Podcasts tab otherwise", () => {
    expect(tabBase(["(root)", "podcasts", "(tabs)", "(library)"])).toBe(
      "/podcasts/(tabs)/(library)",
    )
    expect(tabBase([])).toBe("/podcasts/(tabs)/(library)")
  })
})

describe("show and episode links", () => {
  it("keep the tab and carry the id as a parameter", () => {
    const segments = ["(tabs)", "(discover)", "show", "[id]"]
    expect(showHref(segments, "s1")).toEqual({
      pathname: "/podcasts/(tabs)/(discover)/show/[id]",
      params: { id: "s1" },
    })
    expect(episodeHref(segments, "e1")).toEqual({
      pathname: "/podcasts/(tabs)/(discover)/episode/[id]",
      params: { id: "e1" },
    })
  })
})
