// LOFI-FORK: the podcasts section's show preview (see FORK.md).
import { describe, expect, it } from "vitest"

import { type PodcastFeedData } from "./index"
import { isPreviewId, previewFromFeed } from "./preview"

const feed: PodcastFeedData = {
  title: "The Show",
  author: "Ada",
  description: "About it.",
  categories: ["Comedy"],
  episodes: [
    {
      guid: "old",
      title: "Old",
      publishedAt: 1000,
      notes: "",
      audioUrl: "https://a/1.mp3",
      audioType: "audio/mpeg",
    },
    {
      guid: "new",
      title: "New",
      publishedAt: 2000,
      notes: "n",
      audioUrl: "https://a/2.mp3",
      audioType: "audio/mpeg",
      durationSeconds: 60,
    },
    {
      guid: "new",
      title: "New again",
      publishedAt: 3000,
      notes: "",
      audioUrl: "https://a/3.mp3",
      audioType: "audio/mpeg",
    },
  ],
}

describe("previewFromFeed", () => {
  const { show, episodes } = previewFromFeed("https://f.test/rss", feed)

  it("makes a show with a temporary id from the feed", () => {
    expect(isPreviewId(show.id)).toBe(true)
    expect(show).toMatchObject({
      feedUrl: "https://f.test/rss",
      title: "The Show",
      author: "Ada",
      imageUrl: null,
      categories: ["Comedy"],
    })
  })

  it("lists the episodes newest first, a repeated guid once, none played", () => {
    expect(episodes.map((e) => e.title)).toEqual(["New", "Old"])
    expect(
      episodes.every((e) => isPreviewId(e.id) && e.showId === show.id),
    ).toBe(true)
    expect(new Set(episodes.map((e) => e.id)).size).toBe(2)
    expect(episodes[0]).toMatchObject({
      played: false,
      positionSeconds: 0,
      lastPlayedAt: null,
      durationSeconds: 60,
      audioBytes: null,
    })
  })

  it("does not take a library id for a preview", () => {
    expect(isPreviewId("3f2a-uuid")).toBe(false)
  })
})
