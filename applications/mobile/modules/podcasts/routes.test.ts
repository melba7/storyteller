// LOFI-FORK: the podcasts section's routes (see FORK.md).
import { describe, expect, it } from "vitest"

import {
  categoryHref,
  episodeHref,
  previewHref,
  showHref,
  tabBase,
} from "./routes"

describe("tabBase", () => {
  it("stays in the Discover tab", () => {
    expect(
      tabBase(["(root)", "podcasts", "(tabs)", "(discover)", "discover"]),
    ).toBe("/podcasts/(tabs)/(discover)")
  })

  it("stays in the Profile tab", () => {
    expect(
      tabBase(["(root)", "podcasts", "(tabs)", "(profile)", "downloads"]),
    ).toBe("/podcasts/(tabs)/(profile)")
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

describe("preview and category links", () => {
  it("open a preview in the tab you are in, with the feed as a parameter", () => {
    expect(previewHref(["(tabs)", "(discover)"], "https://f.test/rss")).toEqual(
      {
        pathname: "/podcasts/(tabs)/(discover)/preview",
        params: { feed: "https://f.test/rss" },
      },
    )
    expect(previewHref(["(tabs)", "(library)"], "u").pathname).toBe(
      "/podcasts/(tabs)/(library)/preview",
    )
  })

  it("name the episode a search result meant, when it is known", () => {
    expect(
      previewHref(["(tabs)", "(library)"], "u", { guid: "g", audioUrl: "a" })
        .params,
    ).toEqual({ feed: "u", guid: "g", audio: "a" })
    expect(
      previewHref(["(tabs)", "(library)"], "u", { guid: null, audioUrl: "" })
        .params,
    ).toEqual({ feed: "u" })
  })

  it("open a category's chart in the Discover tab", () => {
    expect(categoryHref("1321")).toEqual({
      pathname: "/podcasts/(tabs)/(discover)/category/[id]",
      params: { id: "1321" },
    })
  })
})
