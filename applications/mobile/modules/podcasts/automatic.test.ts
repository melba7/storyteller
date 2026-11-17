// LOFI-FORK: the podcasts section's automatic downloads and clean-up (see FORK.md).
import { describe, expect, it } from "vitest"

import {
  type AutomaticSettings,
  DAY_MS,
  DEFAULT_SETTINGS,
  FOREGROUND_GAP_MS,
  type NewEpisode,
  downloadsToDelete,
  episodesForUpNext,
  episodesToDownload,
  episodesToNotify,
  newEpisodes,
  parseSettings,
  refreshDue,
  serializeSettings,
} from "./automatic"
import type { FetchedEpisode } from "./library"

const added = (
  id: string,
  showId: string,
  publishedAt: number | null,
): NewEpisode => ({
  id,
  showId,
  publishedAt,
  audioUrl: `https://cdn.example.com/${id}.mp3`,
  audioType: "audio/mpeg",
})

describe("episodesToDownload", () => {
  it("takes the newest new episode of each show", () => {
    const picked = episodesToDownload(
      [
        added("a1", "A", 100),
        added("a2", "A", 300),
        added("a3", "A", 200),
        added("b1", "B", 50),
      ],
      DEFAULT_SETTINGS,
    )
    expect(picked.map((e) => e.id).sort()).toEqual(["a2", "b1"])
  })

  it("has nothing for a show with nothing new, and nothing when nothing was added", () => {
    expect(episodesToDownload([], DEFAULT_SETTINGS)).toEqual([])
    const picked = episodesToDownload([added("a1", "A", 1)], DEFAULT_SETTINGS)
    expect(picked.map((e) => e.showId)).toEqual(["A"])
  })

  it("has nothing when the setting is off", () => {
    expect(
      episodesToDownload([added("a1", "A", 1)], {
        ...DEFAULT_SETTINGS,
        downloadNew: false,
      }),
    ).toEqual([])
  })

  it("counts an undated episode as older than a dated one", () => {
    expect(
      episodesToDownload(
        [added("u", "A", null), added("d", "A", 5)],
        DEFAULT_SETTINGS,
      ).map((e) => e.id),
    ).toEqual(["d"])
    expect(
      episodesToDownload(
        [added("u1", "A", null), added("u2", "A", null)],
        DEFAULT_SETTINGS,
      ).map((e) => e.id),
    ).toEqual(["u1"])
  })

  it("skips a show whose own switch is off", () => {
    const picked = episodesToDownload(
      [added("a1", "A", 1), added("b1", "B", 1)],
      DEFAULT_SETTINGS,
      new Map([["A", false]]),
    )
    expect(picked.map((e) => e.id)).toEqual(["b1"])
  })

  it("keeps what the download needs", () => {
    expect(
      episodesToDownload([added("a1", "A", 1)], DEFAULT_SETTINGS)[0],
    ).toEqual(added("a1", "A", 1))
  })
})

describe("newEpisodes", () => {
  const fetched = (
    guid: string,
    publishedAt: number | null,
  ): FetchedEpisode => ({
    guid,
    title: guid,
    publishedAt,
    durationSeconds: null,
    notes: "",
    audioUrl: `https://cdn.example.com/${guid}.mp3`,
    audioType: "audio/mpeg",
    audioBytes: null,
    imageUrl: null,
    season: null,
    number: null,
    transcriptUrl: null,
    transcriptType: null,
    people: [],
    chaptersUrl: null,
  })

  const stored = (publishedAt: number | null) => ({ publishedAt })

  it("pairs each inserted episode with the id it was saved under", () => {
    expect(
      newEpisodes(
        "S",
        [fetched("x", 10), fetched("y", 20)],
        ["id1", "id2"],
        [stored(5)],
      ).map((e) => [e.id, e.publishedAt, e.audioUrl]),
    ).toEqual([
      ["id1", 10, "https://cdn.example.com/x.mp3"],
      ["id2", 20, "https://cdn.example.com/y.mp3"],
    ])
  })

  it("has nothing when nothing was inserted", () => {
    expect(newEpisodes("S", [], [], [stored(1)])).toEqual([])
  })

  it("counts only episodes newer than the newest stored one", () => {
    const picked = newEpisodes(
      "S",
      [fetched("old", 50), fetched("same", 100), fetched("new", 101)],
      ["i1", "i2", "i3"],
      [stored(100), stored(40), stored(null)],
    )
    expect(picked.map((e) => e.id)).toEqual(["i3"])
  })

  it("counts nothing as new on a show's first refresh, and nothing undated", () => {
    expect(newEpisodes("S", [fetched("a", 10)], ["i1"], [])).toEqual([])
    expect(newEpisodes("S", [fetched("u", null)], ["i1"], [stored(5)])).toEqual(
      [],
    )
  })

  it("counts a dated episode when the stored ones have no dates", () => {
    expect(
      newEpisodes("S", [fetched("a", 10)], ["i1"], [stored(null)]).map(
        (e) => e.id,
      ),
    ).toEqual(["i1"])
  })
})

describe("episodesToNotify", () => {
  it("keeps episodes of shows whose own notify switch is on", () => {
    const list = [added("a", "A", 1), added("b", "B", 2), added("c", "C", 3)]
    const picked = episodesToNotify(
      list,
      new Map([
        ["A", true],
        ["B", false],
      ]),
    )
    expect(picked.map((e) => e.id)).toEqual(["a"])
  })
})

describe("downloadsToDelete", () => {
  const now = 10 * DAY_MS
  const on = DEFAULT_SETTINGS
  const ep = (id: string, played: boolean, lastPlayedAt: number | null) => ({
    id,
    played,
    lastPlayedAt,
  })

  it("deletes a played download last played more than a day ago", () => {
    expect(
      downloadsToDelete([ep("a", true, now - DAY_MS - 1)], now, null, on),
    ).toEqual(["a"])
  })

  it("keeps a played download that is recent, even at exactly a day", () => {
    expect(
      downloadsToDelete([ep("a", true, now - 1000)], now, null, on),
    ).toEqual([])
    expect(
      downloadsToDelete([ep("a", true, now - DAY_MS)], now, null, on),
    ).toEqual([])
  })

  it("keeps an unplayed download, however old its last play", () => {
    expect(
      downloadsToDelete([ep("a", false, now - 5 * DAY_MS)], now, null, on),
    ).toEqual([])
  })

  it("never deletes the episode loaded in the player", () => {
    expect(
      downloadsToDelete(
        [ep("a", true, now - 5 * DAY_MS), ep("b", true, now - 5 * DAY_MS)],
        now,
        "a",
        on,
      ),
    ).toEqual(["b"])
  })

  it("keeps a played download with no last-played time", () => {
    expect(downloadsToDelete([ep("a", true, null)], now, null, on)).toEqual([])
  })

  it("deletes nothing when the setting is off", () => {
    const off: AutomaticSettings = { ...on, deletePlayed: false }
    expect(downloadsToDelete([ep("a", true, 0)], now, null, off)).toEqual([])
  })
})

describe("refreshDue", () => {
  const now = 1_000_000_000
  it("is due the first time", () => {
    expect(refreshDue(null, now)).toBe(true)
  })
  it("waits 30 minutes between refreshes", () => {
    expect(refreshDue(now - FOREGROUND_GAP_MS + 1, now)).toBe(false)
    expect(refreshDue(now - FOREGROUND_GAP_MS, now)).toBe(true)
    expect(refreshDue(now - 1000, now)).toBe(false)
  })
  it("is due when the saved time is in the future (the clock moved)", () => {
    expect(refreshDue(now + 5000, now)).toBe(true)
  })
})

describe("settings", () => {
  it("are both on by default", () => {
    expect(parseSettings(null)).toEqual({
      downloadNew: true,
      deletePlayed: true,
    })
  })
  it("round trip", () => {
    const settings = { downloadNew: false, deletePlayed: true }
    expect(parseSettings(serializeSettings(settings))).toEqual(settings)
  })
  it("fall back to the defaults for broken or partial values", () => {
    expect(parseSettings("nope")).toEqual(DEFAULT_SETTINGS)
    expect(parseSettings("null")).toEqual(DEFAULT_SETTINGS)
    expect(parseSettings('{"downloadNew":false}')).toEqual({
      downloadNew: false,
      deletePlayed: true,
    })
    expect(parseSettings('{"downloadNew":"yes"}')).toEqual(DEFAULT_SETTINGS)
  })
})

describe("episodesForUpNext", () => {
  const modes = new Map<string, "off" | "top" | "bottom">([
    ["A", "top"],
    ["B", "bottom"],
    ["C", "off"],
  ])

  it("adds nothing for a show that is off or not listed", () => {
    expect(
      episodesForUpNext([added("c1", "C", 1), added("d1", "D", 1)], modes),
    ).toEqual([])
  })

  it("adds to the top newest first, so the oldest new episode ends up on top", () => {
    const picked = episodesForUpNext(
      [added("a1", "A", 100), added("a2", "A", 300), added("a3", "A", 200)],
      modes,
    )
    expect(picked.map((p) => p.episode.id)).toEqual(["a2", "a3", "a1"])
    expect(picked.every((p) => p.place === "next")).toBe(true)
  })

  it("adds to the bottom oldest first", () => {
    const picked = episodesForUpNext(
      [added("b2", "B", 300), added("b1", "B", 100), added("bu", "B", null)],
      modes,
    )
    expect(picked.map((p) => p.episode.id)).toEqual(["bu", "b1", "b2"])
    expect(picked.every((p) => p.place === "last")).toBe(true)
  })

  it("does the top ones before the bottom ones", () => {
    const picked = episodesForUpNext(
      [added("b1", "B", 1), added("a1", "A", 2)],
      modes,
    )
    expect(picked.map((p) => p.place)).toEqual(["next", "last"])
  })
})
