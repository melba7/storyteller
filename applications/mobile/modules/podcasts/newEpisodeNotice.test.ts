// LOFI-FORK: the podcasts section's new-episode notifications (see FORK.md).
import { describe, expect, it } from "vitest"

import { noticesForNewEpisodes } from "./newEpisodeNotice"

const shows = new Map([
  ["A", "Show A"],
  ["B", "Show B"],
])
const titles = new Map([
  ["a1", "First"],
  ["a2", "Second"],
  ["b1", "Only one"],
])

describe("noticesForNewEpisodes", () => {
  it("names the episode when a show has one", () => {
    expect(
      noticesForNewEpisodes([{ id: "b1", showId: "B" }], shows, titles),
    ).toEqual([{ id: "B", title: "Show B", body: "Only one" }])
  })
  it("counts the episodes when a show has several", () => {
    expect(
      noticesForNewEpisodes(
        [
          { id: "a1", showId: "A" },
          { id: "a2", showId: "A" },
          { id: "a3", showId: "A" },
        ],
        shows,
        titles,
      ),
    ).toEqual([{ id: "A", title: "Show A", body: "3 new episodes" }])
  })
  it("makes one notice per show, in the order the shows first appear", () => {
    const notices = noticesForNewEpisodes(
      [
        { id: "b1", showId: "B" },
        { id: "a1", showId: "A" },
        { id: "a2", showId: "A" },
      ],
      shows,
      titles,
    )
    expect(notices.map((notice) => [notice.id, notice.body])).toEqual([
      ["B", "Only one"],
      ["A", "2 new episodes"],
    ])
  })
  it("says nothing when nothing was added", () => {
    expect(noticesForNewEpisodes([], shows, titles)).toEqual([])
  })
  it("falls back to plain words for names it does not have", () => {
    expect(
      noticesForNewEpisodes([{ id: "x", showId: "Z" }], shows, titles),
    ).toEqual([
      { id: "Z", title: "New episode", body: "A new episode is ready." },
    ])
    expect(
      noticesForNewEpisodes(
        [{ id: "b1", showId: "B" }],
        new Map([["B", "  "]]),
        new Map([["b1", " "]]),
      ),
    ).toEqual([
      { id: "B", title: "New episode", body: "A new episode is ready." },
    ])
  })
})
