// LOFI-FORK: the podcasts section's show page list tests (see FORK.md).
import { describe, expect, it } from "vitest"

import {
  archivedCount,
  arrangeEpisodes,
  episodesInView,
  seasonTitle,
  sortForView,
} from "./episodeList"
import { type StoredEpisode } from "./library"

function episode(
  id: string,
  overrides: Partial<StoredEpisode> = {},
): StoredEpisode {
  return {
    id,
    showId: "s",
    guid: id,
    title: id,
    description: "",
    audioUrl: "",
    audioType: "audio/mpeg",
    audioBytes: null,
    durationSeconds: null,
    publishedAt: null,
    season: null,
    episodeNumber: null,
    imageUrl: null,
    link: null,
    positionSeconds: 0,
    played: false,
    lastPlayedAt: null,
    archived: false,
    starredAt: null,
    ...overrides,
  } as StoredEpisode
}

const ids = (list: readonly StoredEpisode[]) => list.map((e) => e.id)
const keys = (list: ReturnType<typeof arrangeEpisodes>) =>
  list.map((item) => (item.kind === "header" ? `# ${item.title}` : item.key))

const sample = [
  episode("a", { publishedAt: 10, durationSeconds: 300 }),
  episode("b", { publishedAt: 30, durationSeconds: 100 }),
  episode("c", { publishedAt: 20, durationSeconds: 200 }),
  episode("u", { publishedAt: null, durationSeconds: null }),
]

describe("sortForView", () => {
  it("sorts by date, newest or oldest, with undated last", () => {
    expect(ids(sortForView(sample, "newest"))).toEqual(["b", "c", "a", "u"])
    expect(ids(sortForView(sample, "oldest"))).toEqual(["a", "c", "b", "u"])
  })

  it("sorts by length, with unknown last", () => {
    expect(ids(sortForView(sample, "shortest"))).toEqual(["b", "c", "a", "u"])
    expect(ids(sortForView(sample, "longest"))).toEqual(["a", "c", "b", "u"])
  })

  it("keeps the given order for equal values", () => {
    const same = [episode("x"), episode("y"), episode("z")]
    expect(ids(sortForView(same, "oldest"))).toEqual(["x", "y", "z"])
  })
})

describe("episodesInView", () => {
  it("is the episodes as the list shows them: in order, archived ones hidden", () => {
    const list = [
      episode("a", { publishedAt: 1 }),
      episode("b", { publishedAt: 2, archived: true }),
      episode("c", { publishedAt: 3 }),
    ]
    const items = arrangeEpisodes(list, {
      sort: "oldest",
      groupBySeason: true,
      showArchived: false,
    })
    expect(episodesInView(items).map((e) => e.id)).toEqual(["a", "c"])
  })
})

describe("arrangeEpisodes", () => {
  const view = {
    sort: "newest" as const,
    groupBySeason: false,
    showArchived: false,
  }

  it("hides archived episodes unless asked", () => {
    const list = [episode("a", { archived: true }), episode("b")]
    expect(keys(arrangeEpisodes(list, view))).toEqual(["b"])
    expect(
      keys(arrangeEpisodes(list, { ...view, showArchived: true })),
    ).toEqual(["a", "b"])
    expect(archivedCount(list)).toBe(1)
  })

  it("groups by season, the highest first, no season last", () => {
    const list = [
      episode("s1a", { season: 1, publishedAt: 1 }),
      episode("s2a", { season: 2, publishedAt: 5 }),
      episode("s1b", { season: 1, publishedAt: 2 }),
      episode("bonus", { publishedAt: 9 }),
    ]
    expect(
      keys(arrangeEpisodes(list, { ...view, groupBySeason: true })),
    ).toEqual([
      "# Season 2",
      "s2a",
      "# Season 1",
      "s1b",
      "s1a",
      "# Other episodes",
      "bonus",
    ])
  })

  it("puts the lowest season first when sorted oldest first", () => {
    const list = [
      episode("s2", { season: 2, publishedAt: 5 }),
      episode("s1", { season: 1, publishedAt: 1 }),
    ]
    expect(
      keys(
        arrangeEpisodes(list, {
          sort: "oldest",
          groupBySeason: true,
          showArchived: false,
        }),
      ),
    ).toEqual(["# Season 1", "s1", "# Season 2", "s2"])
  })

  it("has no headers for an empty season group", () => {
    const list = [episode("a", { season: 3, archived: true })]
    expect(arrangeEpisodes(list, { ...view, groupBySeason: true })).toEqual([])
  })

  it("names seasons", () => {
    expect(seasonTitle(4)).toBe("Season 4")
    expect(seasonTitle(null)).toBe("Other episodes")
  })
})
