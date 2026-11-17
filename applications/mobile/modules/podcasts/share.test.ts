// LOFI-FORK: the podcasts section's sharing (see FORK.md).
import { describe, expect, it } from "vitest"

import { episodeShare, placeShare, showShare } from "./share"

const show = {
  title: "The Show",
  feedUrl: "https://example.com/feed.xml",
  link: "https://example.com",
}
const episode = {
  title: "Episode one",
  audioUrl: "https://cdn.example.com/1.mp3",
}

describe("showShare", () => {
  it("gives the feed link and the web link", () => {
    expect(showShare(show)).toEqual({
      title: "The Show",
      message:
        "The Show\nFeed: https://example.com/feed.xml\nWeb: https://example.com",
    })
  })
  it("leaves out a web link the show does not have", () => {
    expect(showShare({ ...show, link: null }).message).toBe(
      "The Show\nFeed: https://example.com/feed.xml",
    )
  })
  it("leaves out a link that is not a web address", () => {
    expect(showShare({ ...show, link: "not a link" }).message).not.toContain(
      "Web:",
    )
  })
})

describe("episodeShare", () => {
  it("gives the title, the show and the audio address", () => {
    expect(episodeShare(episode, show)).toEqual({
      title: "Episode one",
      message: "Episode one\nThe Show\nhttps://cdn.example.com/1.mp3",
    })
  })
  it("works without the show", () => {
    expect(episodeShare(episode, null)?.message).toBe(
      "Episode one\nhttps://cdn.example.com/1.mp3",
    )
  })
  it("has nothing to share without a web address", () => {
    expect(episodeShare({ ...episode, audioUrl: "" }, show)).toBeNull()
    expect(
      episodeShare({ ...episode, audioUrl: "file:///a.mp3" }, show),
    ).toBeNull()
  })
})

describe("placeShare", () => {
  it("says where in the episode", () => {
    expect(placeShare(episode, show, 754.9)?.message).toBe(
      "Episode one at 12:34\nThe Show\nhttps://cdn.example.com/1.mp3",
    )
  })
  it("reads hours for a long episode", () => {
    expect(placeShare(episode, null, 3723)?.message.split("\n")[0]).toBe(
      "Episode one at 1:02:03",
    )
  })
  it("starts at 0:00", () => {
    expect(placeShare(episode, null, 0)?.message).toContain("at 0:00")
  })
  it("has nothing to share without a web address", () => {
    expect(placeShare({ ...episode, audioUrl: "x" }, show, 5)).toBeNull()
  })
})
