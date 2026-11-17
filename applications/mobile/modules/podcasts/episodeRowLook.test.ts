// LOFI-FORK: the podcasts section's episode row and show page rules (see FORK.md).
import { describe, expect, it } from "vitest"

import {
  capsuleLook,
  dateLineParts,
  dateWords,
  filterEpisodes,
  seasonEpisode,
  shortLength,
  showPlayTarget,
  showCaption,
  stripHtml,
  updateFrequency,
} from "./episodeRowLook"
import { type StoredEpisode } from "./library"

const NOW = new Date(2026, 10, 17, 15, 0, 0).getTime()
const HOUR = 3_600_000
const DAY = 24 * HOUR

describe("dateWords", () => {
  it("says minutes and hours for the first day", () => {
    expect(dateWords(NOW - 5 * HOUR - 1000, NOW)).toBe("5h ago")
    expect(dateWords(NOW - 12 * 60_000, NOW)).toBe("12m ago")
    expect(dateWords(NOW - 5_000, NOW)).toBe("1m ago")
  })

  it("says month and day after that, with the year for other years", () => {
    expect(dateWords(new Date(2026, 9, 6, 8).getTime(), NOW)).toBe("Oct 6")
    expect(dateWords(NOW - 25 * HOUR, NOW)).toBe("Nov 16")
    expect(dateWords(new Date(2023, 9, 6, 8).getTime(), NOW)).toBe(
      "Oct 6, 2023",
    )
  })

  it("is empty with no date and plain for the future", () => {
    expect(dateWords(null, NOW)).toBe("")
    expect(dateWords(NOW + 2 * DAY, NOW)).toBe("Nov 19")
  })
})

describe("the date line", () => {
  it("adds the season and episode and Played", () => {
    const parts = dateLineParts(
      { publishedAt: NOW - 2 * HOUR, season: 2, number: 5, played: true },
      NOW,
    )
    expect(parts).toEqual(["2h ago", "S2 E5", "Played"])
  })

  it("leaves out what is missing", () => {
    expect(
      dateLineParts(
        { publishedAt: null, season: null, number: null, played: false },
        NOW,
      ),
    ).toEqual([])
    expect(seasonEpisode(null, 7)).toBe("E7")
    expect(seasonEpisode(3, null)).toBe("S3")
  })
})

describe("the capsule", () => {
  it("writes short lengths", () => {
    expect(shortLength(24 * 60)).toBe("24m")
    expect(shortLength(65 * 60)).toBe("1h 5m")
    expect(shortLength(2 * 3600)).toBe("2h")
    expect(shortLength(10)).toBe("1m")
    expect(shortLength(null)).toBe("")
    expect(shortLength(0)).toBe("")
  })

  it("shows the length of an untouched episode", () => {
    expect(
      capsuleLook({ durationSeconds: 1500, positionSeconds: 0, played: false }),
    ).toEqual({ label: "25m", progress: null, spoken: "25m" })
  })

  it("shows time left and progress for a started one", () => {
    expect(
      capsuleLook({
        durationSeconds: 2000,
        positionSeconds: 500,
        played: false,
      }),
    ).toEqual({ label: "25m", progress: 0.25, spoken: "25m left" })
  })

  it("says Played for a played one", () => {
    expect(
      capsuleLook({ durationSeconds: 2000, positionSeconds: 500, played: true })
        .label,
    ).toBe("Played")
  })

  it("is empty for an unknown length", () => {
    expect(
      capsuleLook({ durationSeconds: null, positionSeconds: 0, played: false })
        .label,
    ).toBe("")
  })
})

describe("stripHtml", () => {
  it("drops tags and reads entities", () => {
    expect(
      stripHtml("<p>Tom &amp; Jerry&nbsp;say &#8220;hi&#8221;</p><p>Next</p>"),
    ).toBe("Tom & Jerry say “hi” Next")
  })

  it("drops scripts, keeps unknown entities and squeezes white space", () => {
    expect(stripHtml("a<script>x()</script>\n\n b &foo; <br/>c")).toBe(
      "a b &foo; c",
    )
  })
})

describe("updateFrequency", () => {
  const every = (days: number, count: number, lastAgo = 1) =>
    Array.from({ length: count }, (_, i) => NOW - (lastAgo + i * days) * DAY)

  it("reads daily, weekly, biweekly and monthly", () => {
    expect(updateFrequency(every(1, 8), NOW)).toBe("Daily")
    expect(updateFrequency(every(3, 8), NOW)).toBe("Every few days")
    expect(updateFrequency(every(7, 8), NOW)).toBe("Weekly")
    expect(updateFrequency(every(14, 8), NOW)).toBe("Biweekly")
    expect(updateFrequency(every(30, 8), NOW)).toBe("Monthly")
  })

  it("ignores order and missing dates", () => {
    const dates = [null, ...every(7, 6)].reverse()
    expect(updateFrequency(dates, NOW)).toBe("Weekly")
  })

  it("is empty for few episodes, quiet shows and rare ones", () => {
    expect(updateFrequency(every(7, 2), NOW)).toBe("")
    expect(updateFrequency(every(7, 8, 200), NOW)).toBe("")
    expect(updateFrequency(every(90, 8), NOW)).toBe("")
  })
})

describe("showCaption", () => {
  it("joins the first top-level category, frequency and author", () => {
    expect(
      showCaption(["Health › Fitness", "Science"], "Weekly", "Podium"),
    ).toBe("Science · Weekly · Podium")
  })

  it("leaves out what is missing", () => {
    expect(showCaption([], "", "Podium")).toBe("Podium")
    expect(showCaption(["Arts"], "", null)).toBe("Arts")
  })
})

describe("filterEpisodes", () => {
  const episode = (id: string, extra: Partial<StoredEpisode>) =>
    ({
      id,
      played: false,
      archived: false,
      starredAt: null,
      ...extra,
    }) as StoredEpisode
  const list = [
    episode("a", {}),
    episode("b", { played: true }),
    episode("c", { starredAt: 1 }),
    episode("d", { archived: true }),
  ]
  const ids = (filter: Parameters<typeof filterEpisodes>[1]) =>
    filterEpisodes(list, filter, new Set(["b", "c"])).map((e) => e.id)

  it("lets through what each filter names", () => {
    expect(ids("all")).toEqual(["a", "b", "c", "d"])
    expect(ids("unplayed")).toEqual(["a", "c", "d"])
    expect(ids("downloaded")).toEqual(["b", "c"])
    expect(ids("saved")).toEqual(["c"])
    expect(ids("archived")).toEqual(["d"])
  })
})

describe("showPlayTarget", () => {
  const make = (id: string, extra: Partial<StoredEpisode>) =>
    ({
      id,
      played: false,
      archived: false,
      positionSeconds: 0,
      lastPlayedAt: null,
      publishedAt: 1,
      ...extra,
    }) as StoredEpisode

  it("resumes the episode started last", () => {
    const target = showPlayTarget([
      make("a", { publishedAt: 9 }),
      make("b", { positionSeconds: 30, lastPlayedAt: 5 }),
      make("c", { positionSeconds: 30, lastPlayedAt: 8 }),
      make("d", { positionSeconds: 30, lastPlayedAt: 9, played: true }),
    ])
    expect(target?.kind).toBe("resume")
    expect(target?.episode.id).toBe("c")
  })

  it("else plays the newest one that is not archived", () => {
    const target = showPlayTarget([
      make("old", { publishedAt: 1 }),
      make("gone", { publishedAt: 9, archived: true }),
      make("new", { publishedAt: 5 }),
    ])
    expect(target?.kind).toBe("latest")
    expect(target?.episode.id).toBe("new")
  })

  it("is null for no episodes", () => {
    expect(showPlayTarget([])).toBeNull()
  })
})
