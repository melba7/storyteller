// LOFI-FORK: the podcasts section's library rules (see FORK.md).
import { describe, expect, it } from "vitest"

import {
  type FetchedEpisode,
  type Show,
  type StoredEpisode,
  categoriesFromJson,
  episodeFromRow,
  fetchedEpisode,
  formatDuration,
  formatEpisodeDate,
  formatEpisodeLength,
  mergeEpisodes,
  showFromRow,
  sortEpisodes,
} from "./library"
import { DEFAULT_SHOW_SETTINGS } from "./showSettings"

function show(overrides: Partial<Show> = {}): Show {
  return {
    id: "s1",
    feedUrl: "https://example.com/rss",
    title: "Show",
    author: null,
    description: "",
    imageUrl: null,
    link: null,
    language: null,
    addedAt: 1,
    refreshedAt: 1,
    artworkColor: null,
    ownPosition: null,
    categories: [],
    funding: [],
    people: [],
    settings: DEFAULT_SHOW_SETTINGS,
    ...overrides,
  }
}

function fetched(
  guid: string,
  overrides: Partial<FetchedEpisode> = {},
): FetchedEpisode {
  return {
    guid,
    title: `Episode ${guid}`,
    publishedAt: 1000,
    durationSeconds: 60,
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
    ...overrides,
  }
}

function stored(
  guid: string,
  overrides: Partial<StoredEpisode> = {},
): StoredEpisode {
  return {
    ...fetched(guid),
    id: `id-${guid}`,
    showId: "s1",
    positionSeconds: 0,
    played: false,
    lastPlayedAt: null,
    archived: false,
    starredAt: null,
    ...overrides,
  }
}

describe("mergeEpisodes", () => {
  it("inserts everything into an empty library", () => {
    const result = mergeEpisodes([], [fetched("a"), fetched("b")])
    expect(result.insert.map((e) => e.guid)).toEqual(["a", "b"])
    expect(result.update).toEqual([])
  })

  it("inserts only the new episodes and updates the changed ones", () => {
    const result = mergeEpisodes(
      [stored("a"), stored("b")],
      [fetched("a"), fetched("b", { title: "Renamed" }), fetched("c")],
    )
    expect(result.insert.map((e) => e.guid)).toEqual(["c"])
    expect(result.update.map((e) => [e.id, e.episode.title])).toEqual([
      ["id-b", "Renamed"],
    ])
  })

  it("leaves unchanged episodes alone", () => {
    const result = mergeEpisodes([stored("a")], [fetched("a")])
    expect(result.insert).toEqual([])
    expect(result.update).toEqual([])
  })

  it("never duplicates when the feed repeats a guid", () => {
    const result = mergeEpisodes(
      [],
      [
        fetched("a", { title: "First" }),
        fetched("a", { title: "Second" }),
        fetched("b"),
      ],
    )
    expect(result.insert.map((e) => [e.guid, e.title])).toEqual([
      ["a", "First"],
      ["b", "Episode b"],
    ])
  })

  it("updates once when a repeated guid is already stored", () => {
    const result = mergeEpisodes(
      [stored("a")],
      [fetched("a", { title: "One" }), fetched("a", { title: "Two" })],
    )
    expect(result.update).toHaveLength(1)
    expect(result.update[0]?.episode.title).toBe("One")
  })

  it("never deletes an episode that left the feed", () => {
    const result = mergeEpisodes([stored("old")], [fetched("new")])
    expect(result.insert.map((e) => e.guid)).toEqual(["new"])
    expect(result.update).toEqual([])
    expect(result).not.toHaveProperty("delete")
  })
})

describe("mergeEpisodes with changed guids", () => {
  it("moves a stored row to the new guid when the audio address matches", () => {
    const result = mergeEpisodes(
      [
        stored("old", {
          audioUrl: "https://cdn.example.com/x.mp3",
          title: "A",
        }),
      ],
      [
        fetched("new", {
          audioUrl: "https://cdn.example.com/x.mp3",
          title: "B",
        }),
      ],
    )
    expect(result.insert).toEqual([])
    expect(result.update.map((u) => [u.id, u.episode.guid])).toEqual([
      ["id-old", "new"],
    ])
  })

  it("matches by title and date when the audio address changed too", () => {
    const result = mergeEpisodes(
      [
        stored("old", {
          title: "Same",
          publishedAt: 5,
          audioUrl: "https://a/1",
        }),
      ],
      [
        fetched("new", {
          title: "Same",
          publishedAt: 5,
          audioUrl: "https://b/1",
        }),
      ],
    )
    expect(result.insert).toEqual([])
    expect(result.update[0]?.id).toBe("id-old")
  })

  it("does not match on the title alone or the date alone", () => {
    const result = mergeEpisodes(
      [
        stored("old", {
          title: "Same",
          publishedAt: 5,
          audioUrl: "https://a/1",
        }),
      ],
      [
        fetched("n1", {
          title: "Same",
          publishedAt: 6,
          audioUrl: "https://b/1",
        }),
        fetched("n2", {
          title: "Other",
          publishedAt: 5,
          audioUrl: "https://b/2",
        }),
      ],
    )
    expect(result.insert.map((e) => e.guid)).toEqual(["n1", "n2"])
    expect(result.update).toEqual([])
  })

  it("never takes a row whose guid is still in the feed", () => {
    const result = mergeEpisodes(
      [stored("a", { audioUrl: "https://x/1" })],
      [
        fetched("a", { audioUrl: "https://x/2" }),
        fetched("b", { audioUrl: "https://x/1" }),
      ],
    )
    expect(result.insert.map((e) => e.guid)).toEqual(["b"])
  })

  it("matches a stored row once, and prefers the audio address to the title", () => {
    const result = mergeEpisodes(
      [
        stored("o1", { title: "T", publishedAt: 5, audioUrl: "https://a/1" }),
        stored("o2", { title: "T", publishedAt: 5, audioUrl: "https://a/2" }),
      ],
      [
        fetched("n2", { title: "T", publishedAt: 5, audioUrl: "https://a/2" }),
        fetched("n1", { title: "T", publishedAt: 5, audioUrl: "https://a/1" }),
        fetched("n3", { title: "T", publishedAt: 5, audioUrl: "https://a/3" }),
      ],
    )
    expect(result.update.map((u) => [u.id, u.episode.guid]).sort()).toEqual([
      ["id-o1", "n1"],
      ["id-o2", "n2"],
    ])
    expect(result.insert.map((e) => e.guid)).toEqual(["n3"])
  })

  it("still stores two episodes with the same title and date", () => {
    const twins = [
      fetched("a", { title: "T", publishedAt: 5, audioUrl: "https://a/1" }),
      fetched("b", { title: "T", publishedAt: 5, audioUrl: "https://a/2" }),
    ]
    expect(mergeEpisodes([], twins).insert).toHaveLength(2)
    const again = mergeEpisodes(
      [stored("a", twins[0]), stored("b", twins[1])],
      twins,
    )
    expect(again.insert).toEqual([])
    expect(again.update).toEqual([])
  })
})

describe("sortEpisodes", () => {
  it("puts the newest first and the undated last", () => {
    const sorted = sortEpisodes([
      stored("none", { publishedAt: null }),
      stored("old", { publishedAt: 1 }),
      stored("new", { publishedAt: 3 }),
      stored("mid", { publishedAt: 2 }),
    ])
    expect(sorted.map((e) => e.guid)).toEqual(["new", "mid", "old", "none"])
  })

  it("keeps the feed order for equal dates and does not change the input", () => {
    const input = [
      stored("a", { publishedAt: 5 }),
      stored("b", { publishedAt: 5 }),
      stored("c", { publishedAt: null }),
      stored("d", { publishedAt: null }),
    ]
    const copy = [...input]
    expect(sortEpisodes(input).map((e) => e.guid)).toEqual(["a", "b", "c", "d"])
    expect(input).toEqual(copy)
  })
})

describe("formatDuration", () => {
  it("writes minutes and hours", () => {
    expect(formatDuration(42 * 60)).toBe("42 min")
    expect(formatDuration(65 * 60)).toBe("1 h 5 min")
    expect(formatDuration(2 * 3600)).toBe("2 h")
    expect(formatDuration(3600 + 29)).toBe("1 h")
  })

  it("rounds to the nearest minute, but never says 0", () => {
    expect(formatDuration(42 * 60 + 40)).toBe("43 min")
    expect(formatDuration(20)).toBe("1 min")
  })

  it("is empty when the length is unknown", () => {
    expect(formatDuration(null)).toBe("")
    expect(formatDuration(0)).toBe("")
    expect(formatDuration(Number.NaN)).toBe("")
  })
})

describe("formatEpisodeDate", () => {
  it("writes day, month and year", () => {
    expect(formatEpisodeDate(new Date(2023, 0, 2, 12).getTime())).toBe(
      "2 Jan 2023",
    )
    expect(formatEpisodeDate(new Date(2026, 10, 16, 12).getTime())).toBe(
      "16 Nov 2026",
    )
  })

  it("is empty when the date is unknown", () => {
    expect(formatEpisodeDate(null)).toBe("")
  })
})

describe("rows", () => {
  it("reads a show row", () => {
    expect(
      showFromRow({
        id: "s1",
        feed_url: "https://example.com/rss",
        title: "Show",
        author: null,
        description: "About",
        image_url: "https://img",
        link: null,
        language: "en",
        added_at: 5,
        refreshed_at: 6,
      }),
    ).toEqual(
      show({
        description: "About",
        imageUrl: "https://img",
        language: "en",
        addedAt: 5,
        refreshedAt: 6,
      }),
    )
  })

  it("reads an episode row", () => {
    expect(
      episodeFromRow({
        id: "e1",
        show_id: "s1",
        guid: "g",
        title: "T",
        published_at: 1000,
        duration_seconds: 61.5,
        notes: "N",
        audio_url: "https://a",
        audio_type: "audio/mpeg",
        audio_bytes: 99,
        image_url: null,
        season: 1,
        number: null,
      }),
    ).toEqual({
      id: "e1",
      showId: "s1",
      guid: "g",
      title: "T",
      publishedAt: 1000,
      durationSeconds: 61.5,
      notes: "N",
      audioUrl: "https://a",
      audioType: "audio/mpeg",
      audioBytes: 99,
      imageUrl: null,
      season: 1,
      number: null,
      transcriptUrl: null,
      transcriptType: null,
      chaptersUrl: null,
      people: [],
      positionSeconds: 0,
      played: false,
      lastPlayedAt: null,
      archived: false,
      starredAt: null,
    })
  })

  it("reads the playing columns of a show and an episode", () => {
    expect(
      showFromRow({ id: "s1", artwork_color: "#336699" }).artworkColor,
    ).toBe("#336699")
    expect(
      showFromRow({ id: "s1", artwork_color: null }).artworkColor,
    ).toBeNull()
    expect(
      episodeFromRow({
        id: "e1",
        position_seconds: 42.5,
        played: 1,
        last_played_at: 9000,
      }),
    ).toMatchObject({ positionSeconds: 42.5, played: true, lastPlayedAt: 9000 })
    expect(
      episodeFromRow({ id: "e1", position_seconds: -3, played: 0 }),
    ).toMatchObject({ positionSeconds: 0, played: false, lastPlayedAt: null })
  })
})

describe("formatEpisodeLength", () => {
  const base = { durationSeconds: 3000, positionSeconds: 0, played: false }

  it("shows the full length for an episode not started", () => {
    expect(formatEpisodeLength(base)).toBe("50 min")
  })

  it("shows the time left for one in progress", () => {
    expect(formatEpisodeLength({ ...base, positionSeconds: 600 })).toBe(
      "40 min left",
    )
  })

  it("says played for a played one", () => {
    expect(formatEpisodeLength({ ...base, played: true })).toBe("Played")
  })

  it("is empty when the length is unknown", () => {
    expect(formatEpisodeLength({ ...base, durationSeconds: null })).toBe("")
  })
})

describe("categories", () => {
  it("are read from the saved JSON list", () => {
    expect(categoriesFromJson('["Business","Business › Investing"]')).toEqual([
      "Business",
      "Business › Investing",
    ])
  })

  it("are none for a missing, broken or wrong value", () => {
    expect(categoriesFromJson(null)).toEqual([])
    expect(categoriesFromJson("not json")).toEqual([])
    expect(categoriesFromJson('{"a":1}')).toEqual([])
    expect(categoriesFromJson('["Comedy",3,null]')).toEqual(["Comedy"])
  })

  it("come with a show's row", () => {
    expect(
      showFromRow({ id: "s", feed_url: "u", categories: '["News"]' })
        .categories,
    ).toEqual(["News"])
    expect(showFromRow({ id: "s", feed_url: "u" }).categories).toEqual([])
  })
})

describe("an episode's transcript", () => {
  const feedEpisode = {
    guid: "g",
    title: "T",
    notes: "",
    audioUrl: "https://cdn.example.com/g.mp3",
    audioType: "audio/mpeg",
  }

  it("keeps the best transcript of the feed's tags", () => {
    const episode = fetchedEpisode({
      ...feedEpisode,
      transcripts: [
        { url: "https://x.test/g.txt", type: "text/plain" },
        { url: "https://x.test/g.srt", type: "application/x-subrip" },
        { url: "https://x.test/g.json", type: "application/json" },
      ],
    })
    expect(episode.transcriptUrl).toBe("https://x.test/g.json")
    expect(episode.transcriptType).toBe("application/json")
  })

  it("is null when the feed has none", () => {
    const episode = fetchedEpisode(feedEpisode)
    expect(episode.transcriptUrl).toBeNull()
    expect(episode.transcriptType).toBeNull()
  })

  it("is filled in for a stored episode at the next refresh", () => {
    const { update } = mergeEpisodes(
      [stored("g")],
      [
        fetched("g", {
          transcriptUrl: "https://x.test/g.vtt",
          transcriptType: "text/vtt",
        }),
      ],
    )
    expect(update).toHaveLength(1)
    expect(update[0]?.episode.transcriptUrl).toBe("https://x.test/g.vtt")
  })

  it("keeps the chapters address of the feed", () => {
    expect(fetchedEpisode(feedEpisode).chaptersUrl).toBeNull()
    expect(
      fetchedEpisode({ ...feedEpisode, chaptersUrl: "https://x.test/c.json" })
        .chaptersUrl,
    ).toBe("https://x.test/c.json")
    const { update } = mergeEpisodes(
      [stored("g")],
      [fetched("g", { chaptersUrl: "https://x.test/c.json" })],
    )
    expect(update).toHaveLength(1)
  })

  it("is read from the database row", () => {
    const row = {
      id: "e",
      show_id: "s",
      guid: "g",
      title: "T",
      notes: "",
      audio_url: "https://cdn.example.com/g.mp3",
      audio_type: "audio/mpeg",
      transcript_url: "https://x.test/g.vtt",
      transcript_type: "text/vtt",
    }
    expect(episodeFromRow(row).transcriptUrl).toBe("https://x.test/g.vtt")
    expect(episodeFromRow(row).chaptersUrl).toBeNull()
    expect(
      episodeFromRow({ ...row, chapters_url: "https://x.test/c.json" })
        .chaptersUrl,
    ).toBe("https://x.test/c.json")
    expect(
      episodeFromRow({ ...row, transcript_url: null }).transcriptType,
    ).toBe("text/vtt")
    expect(
      episodeFromRow({ ...row, transcript_url: null }).transcriptUrl,
    ).toBeNull()
  })
})

describe("hosts, guests and support links", () => {
  const person = { name: "Ann", role: "host", group: "cast" }

  it("reads them from the feed, with none when the feed has none", () => {
    const base = {
      guid: "g",
      title: "T",
      notes: "",
      audioUrl: "https://cdn.example.com/g.mp3",
      audioType: "audio/mpeg",
    }
    expect(fetchedEpisode(base).people).toEqual([])
    expect(fetchedEpisode({ ...base, people: [person] }).people).toEqual([
      { ...person, img: null, href: null },
    ])
  })

  it("reads a show's and an episode's saved JSON safely", () => {
    const people = JSON.stringify([person])
    expect(showFromRow({ id: "s", feed_url: "u", people }).people).toHaveLength(
      1,
    )
    expect(showFromRow({ id: "s", feed_url: "u" }).people).toEqual([])
    expect(showFromRow({ id: "s", feed_url: "u" }).funding).toEqual([])
    expect(
      showFromRow({
        id: "s",
        feed_url: "u",
        funding:
          '[{"url":"https://x.test/give","label":"Give"},{"url":"ftp://x"}]',
      }).funding,
    ).toEqual([{ url: "https://x.test/give", label: "Give" }])
    expect(episodeFromRow({ id: "e", people }).people).toHaveLength(1)
    expect(episodeFromRow({ id: "e", people: "oops" }).people).toEqual([])
  })

  it("updates a stored episode when its people changed", () => {
    const changed = fetched("g", {
      people: [{ ...person, img: null, href: null }],
    })
    expect(mergeEpisodes([stored("g")], [fetched("g")]).update).toEqual([])
    expect(mergeEpisodes([stored("g")], [changed]).update).toHaveLength(1)
  })
})
