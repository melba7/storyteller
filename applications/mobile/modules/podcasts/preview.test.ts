// LOFI-FORK: the podcasts section's show preview (see FORK.md).
import { describe, expect, it } from "vitest"

import { type PodcastFeedData } from "./index"
import { findEpisodeIndex, isPreviewId, previewFromFeed } from "./preview"

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

describe("previewFromFeed people and funding", () => {
  it("carries the feed's people and support links, and none when absent", () => {
    const person = { name: "Ann", role: "host", group: "cast" }
    const withTags = previewFromFeed("https://f.test/rss", {
      ...feed,
      people: [person],
      funding: [{ url: "https://x.test/give", label: "Give" }],
      episodes: [{ ...feed.episodes[0]!, people: [person] }],
    })
    expect(withTags.show.people).toHaveLength(1)
    expect(withTags.show.funding).toEqual([
      { url: "https://x.test/give", label: "Give" },
    ])
    expect(withTags.episodes[0]!.people).toHaveLength(1)
    const bare = previewFromFeed("https://f.test/rss", feed)
    expect(bare.show.people).toEqual([])
    expect(bare.show.funding).toEqual([])
    expect(bare.episodes[0]!.people).toEqual([])
  })
})

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

describe("findEpisodeIndex", () => {
  const list = [
    { guid: "a", audioUrl: "https://cdn.test/one.mp3?token=1" },
    { guid: "b", audioUrl: "https://cdn.test/two.mp3" },
  ]

  it("finds an episode by its guid first", () => {
    expect(
      findEpisodeIndex(list, {
        guid: "b",
        audioUrl: "https://cdn.test/one.mp3",
      }),
    ).toBe(1)
  })

  it("falls back to the audio address, ignoring scheme, query and case", () => {
    expect(
      findEpisodeIndex(list, {
        guid: "zzz",
        audioUrl: "http://CDN.test/one.mp3?src=apple",
      }),
    ).toBe(0)
    expect(
      findEpisodeIndex(list, { audioUrl: "https://cdn.test/two.mp3" }),
    ).toBe(1)
  })

  it("is -1 when the feed has no such episode or none was named", () => {
    expect(
      findEpisodeIndex(list, {
        guid: "zzz",
        audioUrl: "https://other.test/x.mp3",
      }),
    ).toBe(-1)
    expect(findEpisodeIndex(list, {})).toBe(-1)
    expect(findEpisodeIndex(list, { guid: null, audioUrl: "" })).toBe(-1)
    expect(findEpisodeIndex([], { guid: "a" })).toBe(-1)
  })
})
