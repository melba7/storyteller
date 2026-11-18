// LOFI-FORK: the podcasts section's routes (see FORK.md).
import { describe, expect, it } from "vitest"

import {
  ACCOUNT_HREF,
  arrangeHref,
  bookmarksHref,
  categoryHref,
  downloadsHref,
  episodeHref,
  historyHref,
  latestHref,
  playlistEditHref,
  playlistHref,
  previewHref,
  savedHref,
  settingsHref,
  showHref,
  showsHref,
  tabBase,
  upNextHref,
} from "./routes"

describe("tabBase", () => {
  it.each(["(home)", "(new)", "(library)", "(search)"])(
    "stays in the %s tab",
    (tab) => {
      expect(tabBase(["(root)", "podcasts", "(tabs)", tab, "show"])).toBe(
        `/podcasts/(tabs)/${tab}`,
      )
    },
  )

  it("uses the Home tab otherwise", () => {
    expect(tabBase(["(root)", "podcasts", "(tabs)"])).toBe(
      "/podcasts/(tabs)/(home)",
    )
    expect(tabBase([])).toBe("/podcasts/(tabs)/(home)")
  })
})

describe("show and episode links", () => {
  it("keep the tab and carry the id as a parameter", () => {
    const segments = ["(tabs)", "(new)", "show", "[id]"]
    expect(showHref(segments, "s1")).toEqual({
      pathname: "/podcasts/(tabs)/(new)/show/[id]",
      params: { id: "s1" },
    })
    expect(episodeHref(segments, "e1")).toEqual({
      pathname: "/podcasts/(tabs)/(new)/episode/[id]",
      params: { id: "e1" },
    })
    expect(settingsHref(["(tabs)", "(library)"], "s1")).toEqual({
      pathname: "/podcasts/(tabs)/(library)/show-settings/[id]",
      params: { id: "s1" },
    })
  })
})

describe("playlist links", () => {
  it("open a playlist and its editor in the tab you are in", () => {
    expect(playlistHref(["(tabs)", "(library)"], "p1")).toEqual({
      pathname: "/podcasts/(tabs)/(library)/playlist/[id]",
      params: { id: "p1" },
    })
    expect(playlistEditHref(["(tabs)", "(library)"], "new")).toEqual({
      pathname: "/podcasts/(tabs)/(library)/playlist-edit/[id]",
      params: { id: "new" },
    })
  })
})

describe("pages without a parameter", () => {
  it("open in the tab you are in", () => {
    const library = ["(tabs)", "(library)"]
    const home = ["(tabs)", "(home)"]
    expect(downloadsHref(library)).toBe("/podcasts/(tabs)/(library)/downloads")
    expect(historyHref(library)).toBe("/podcasts/(tabs)/(library)/history")
    expect(bookmarksHref(library)).toBe("/podcasts/(tabs)/(library)/bookmarks")
    expect(savedHref(library)).toBe("/podcasts/(tabs)/(library)/saved")
    expect(latestHref(library)).toBe("/podcasts/(tabs)/(library)/latest")
    expect(showsHref(home)).toBe("/podcasts/(tabs)/(home)/shows")
    expect(arrangeHref(home)).toBe("/podcasts/(tabs)/(home)/arrange")
    expect(upNextHref(home)).toBe("/podcasts/(tabs)/(home)/up-next")
    expect(upNextHref(library)).toBe("/podcasts/(tabs)/(library)/up-next")
  })
})

describe("preview and category links", () => {
  it("open a preview in the tab you are in, with the feed as a parameter", () => {
    expect(previewHref(["(tabs)", "(search)"], "https://f.test/rss")).toEqual({
      pathname: "/podcasts/(tabs)/(search)/preview",
      params: { feed: "https://f.test/rss" },
    })
    expect(previewHref(["(tabs)", "(library)"], "u").pathname).toBe(
      "/podcasts/(tabs)/(library)/preview",
    )
  })

  it("name the episode a search result meant, when it is known", () => {
    expect(
      previewHref(["(tabs)", "(search)"], "u", { guid: "g", audioUrl: "a" })
        .params,
    ).toEqual({ feed: "u", guid: "g", audio: "a" })
    expect(
      previewHref(["(tabs)", "(search)"], "u", { guid: null, audioUrl: "" })
        .params,
    ).toEqual({ feed: "u" })
  })

  it("open a category's chart in New, or in Search when you are there", () => {
    expect(categoryHref("1321")).toEqual({
      pathname: "/podcasts/(tabs)/(new)/category/[id]",
      params: { id: "1321" },
    })
    expect(categoryHref("1321", ["(tabs)", "(search)"]).pathname).toBe(
      "/podcasts/(tabs)/(search)/category/[id]",
    )
  })
})

describe("the account sheet", () => {
  it("is its own stack over the tabs", () => {
    expect(ACCOUNT_HREF).toBe("/podcasts/account")
  })
})
