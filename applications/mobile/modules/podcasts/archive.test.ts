// LOFI-FORK: the podcasts section's archive rules tests (see FORK.md).
import { describe, expect, it } from "vitest"

import { archivesByItself, episodesToArchive } from "./archive"
import { type StoredEpisode } from "./library"
import { DEFAULT_SHOW_SETTINGS, type ShowSettings } from "./showSettings"

const DAY = 24 * 60 * 60 * 1000
const NOW = 100 * DAY

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
    audioUrl: `https://x.test/${id}.mp3`,
    audioType: "audio/mpeg",
    audioBytes: null,
    durationSeconds: 1800,
    publishedAt: NOW - 3 * DAY,
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

const settings = (overrides: Partial<ShowSettings>): ShowSettings => ({
  ...DEFAULT_SHOW_SETTINGS,
  ...overrides,
})
const none = { now: NOW, loadedId: null, queuedIds: new Set<string>() }

describe("with every rule off", () => {
  it("archives nothing", () => {
    const episodes = [episode("a", { played: true, lastPlayedAt: 1 })]
    expect(episodesToArchive(episodes, DEFAULT_SHOW_SETTINGS, none)).toEqual([])
    expect(archivesByItself(DEFAULT_SHOW_SETTINGS)).toBe(false)
  })
})

describe("after playing", () => {
  const played = (id: string, ago: number) =>
    episode(id, { played: true, lastPlayedAt: NOW - ago })

  it("right away takes every played episode", () => {
    const episodes = [played("a", 0), episode("b"), played("c", 50 * DAY)]
    expect(
      episodesToArchive(
        episodes,
        settings({ archiveAfterPlayed: "now" }),
        none,
      ),
    ).toEqual(["a", "c"])
  })

  it("after a day waits a day", () => {
    const episodes = [played("new", DAY - 1), played("old", DAY)]
    expect(
      episodesToArchive(
        episodes,
        settings({ archiveAfterPlayed: "day" }),
        none,
      ),
    ).toEqual(["old"])
  })

  it("after a week waits a week, and an unknown listen time never archives", () => {
    const episodes = [
      played("six", 6 * DAY),
      played("seven", 7 * DAY),
      episode("unknown", { played: true }),
    ]
    expect(
      episodesToArchive(
        episodes,
        settings({ archiveAfterPlayed: "week" }),
        none,
      ),
    ).toEqual(["seven"])
  })
})

describe("after days unplayed", () => {
  it("takes old episodes that were never started", () => {
    const episodes = [
      episode("young", { publishedAt: NOW - 6 * DAY }),
      episode("old", { publishedAt: NOW - 7 * DAY }),
      episode("started", { publishedAt: NOW - 30 * DAY, positionSeconds: 60 }),
      episode("played", {
        publishedAt: NOW - 30 * DAY,
        played: true,
        lastPlayedAt: NOW,
      }),
      episode("undated", { publishedAt: null }),
    ]
    expect(
      episodesToArchive(episodes, settings({ archiveAfterDays: 7 }), none),
    ).toEqual(["old"])
  })
})

describe("keep the newest", () => {
  const list = [
    episode("e1", { publishedAt: 1 * DAY }),
    episode("e4", { publishedAt: 4 * DAY }),
    episode("e3", { publishedAt: 3 * DAY }),
    episode("e2", { publishedAt: 2 * DAY }),
  ]

  it("archives everything past the newest N", () => {
    expect(
      episodesToArchive(list, settings({ keepNewest: 2 }), none).sort(),
    ).toEqual(["e1", "e2"])
  })

  it("does not count archived episodes", () => {
    const withArchived = [
      ...list,
      episode("old", { publishedAt: 0, archived: true }),
      episode("newer", { publishedAt: 9 * DAY, archived: true }),
    ]
    expect(
      episodesToArchive(withArchived, settings({ keepNewest: 3 }), none),
    ).toEqual(["e1"])
  })
})

describe("keep the newest N and a half-listened episode", () => {
  it("leaves an unplayed episode with a saved place, which still takes its slot", () => {
    const list = [
      episode("n1", { publishedAt: 4 * DAY }),
      episode("n2", { publishedAt: 3 * DAY }),
      episode("half", { publishedAt: 2 * DAY, positionSeconds: 300 }),
      episode("done", {
        publishedAt: 1 * DAY,
        played: true,
        positionSeconds: 300,
      }),
      episode("n3", { publishedAt: 0 }),
    ]
    expect(
      episodesToArchive(list, settings({ keepNewest: 2 }), none).sort(),
    ).toEqual(["done", "n3"])
  })
})

describe("exceptions", () => {
  const all = settings({ archiveAfterPlayed: "now" })
  const played = (id: string) =>
    episode(id, { played: true, lastPlayedAt: NOW })

  it("never archives the loaded episode", () => {
    expect(
      episodesToArchive([played("a"), played("b")], all, {
        ...none,
        loadedId: "a",
      }),
    ).toEqual(["b"])
  })

  it("never archives a queued episode", () => {
    expect(
      episodesToArchive([played("a"), played("b")], all, {
        ...none,
        queuedIds: new Set(["b"]),
      }),
    ).toEqual(["a"])
  })

  it("keeps a protected episode in the count for keep the newest", () => {
    const list = [
      episode("n1", { publishedAt: 3 * DAY }),
      episode("n2", { publishedAt: 2 * DAY }),
      episode("n3", { publishedAt: 1 * DAY }),
    ]
    expect(
      episodesToArchive(list, settings({ keepNewest: 1 }), {
        ...none,
        queuedIds: new Set(["n2"]),
      }),
    ).toEqual(["n3"])
  })

  it("leaves an archived episode alone", () => {
    expect(
      episodesToArchive(
        [episode("a", { played: true, archived: true })],
        all,
        none,
      ),
    ).toEqual([])
  })
})
