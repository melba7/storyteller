// LOFI-FORK: the podcasts section's teaching files from the Mac (see FORK.md).
import { describe, expect, it } from "vitest"

import { LOCAL_FEED_URL } from "./localFiles"
import {
  AHEAD_MOST,
  AHEAD_PER_SHOW,
  MAX_TEACHING_BYTES,
  TEACHING_NAMES,
  aheadEpisodesText,
  dueForAhead,
  dueForPlay,
  dueForTeaching,
  filesToFetch,
  parseTeachingList,
  parseTeachingState,
  showTable,
  showTableText,
} from "./teaching"

const SHA_A = "a".repeat(64)
const SHA_B = "b".repeat(64)

const list = (files: Record<string, unknown>, extra: object = {}) =>
  JSON.stringify({ version: 1, writtenAt: "2026-11-22", files, ...extra })

describe("parseTeachingList", () => {
  it("reads the four files with their sizes and checksums", () => {
    const parsed = parseTeachingList(
      list({
        "ad-model.json": { sha256: SHA_A, bytes: 1200 },
        "show-habits.json": { sha256: SHA_B, bytes: 40 },
      }),
    )
    expect(parsed).toEqual({
      "ad-model.json": { sha256: SHA_A, bytes: 1200 },
      "show-habits.json": { sha256: SHA_B, bytes: 40 },
    })
  })

  it("means nothing to do for anything that is not exactly version 1", () => {
    expect(parseTeachingList("")).toBeNull()
    expect(parseTeachingList("not json")).toBeNull()
    expect(parseTeachingList("[]")).toBeNull()
    expect(
      parseTeachingList(JSON.stringify({ version: 2, files: {} })),
    ).toBeNull()
    expect(parseTeachingList(JSON.stringify({ version: 1 }))).toBeNull()
    expect(
      parseTeachingList(JSON.stringify({ version: 1, files: [] })),
    ).toBeNull()
    expect(parseTeachingList(list({ "ad-model.json": "x" }))).toBeNull()
    expect(
      parseTeachingList(list({ "ad-model.json": { sha256: SHA_A } })),
    ).toBeNull()
    expect(
      parseTeachingList(list({ "ad-model.json": { sha256: "", bytes: 5 } })),
    ).toBeNull()
    expect(
      parseTeachingList(
        list({ "ad-model.json": { sha256: SHA_A, bytes: -1 } }),
      ),
    ).toBeNull()
    expect(
      parseTeachingList(
        list({ "ad-model.json": { sha256: SHA_A, bytes: "12" } }),
      ),
    ).toBeNull()
  })

  it("keeps only the eight known files", () => {
    const parsed = parseTeachingList(
      list({
        "ad-model.json": { sha256: SHA_A, bytes: 1 },
        "ad-meaning.json": { sha256: SHA_B, bytes: 2 },
        "show-settings.json": { sha256: SHA_B, bytes: 3 },
        "ahead-ads.json": { sha256: SHA_A, bytes: 4 },
        "ad-cues.json": { sha256: SHA_B, bytes: 5 },
        "../secret.json": { sha256: SHA_A, bytes: 1 },
        "other.json": { sha256: SHA_A, bytes: 1 },
      }),
    )
    expect(Object.keys(parsed ?? {})).toEqual([
      "ad-model.json",
      "ad-meaning.json",
      "show-settings.json",
      "ahead-ads.json",
      "ad-cues.json",
    ])
  })

  it("reads the meaning model and the settings with their sizes and checksums", () => {
    const parsed = parseTeachingList(
      list({
        "ad-meaning.json": { sha256: SHA_A, bytes: 90000 },
        "show-settings.json": { sha256: SHA_B, bytes: 800 },
      }),
    )
    expect(parsed).toEqual({
      "ad-meaning.json": { sha256: SHA_A, bytes: 90000 },
      "show-settings.json": { sha256: SHA_B, bytes: 800 },
    })
  })
})

describe("TEACHING_NAMES", () => {
  it("is the eight files of the Mac's teach_publish.py, the model files first", () => {
    expect([...TEACHING_NAMES]).toEqual([
      "ad-model.json",
      "ad-library.json",
      "show-habits.json",
      "ad-sounds.json",
      "ad-meaning.json",
      "show-settings.json",
      "ahead-ads.json",
      "ad-cues.json",
    ])
  })
})

describe("filesToFetch", () => {
  const files = {
    "ad-model.json": { sha256: SHA_A, bytes: 100 },
    "ad-library.json": { sha256: SHA_A, bytes: 100 },
    "show-habits.json": { sha256: SHA_A, bytes: MAX_TEACHING_BYTES },
    "ad-sounds.json": { sha256: SHA_A, bytes: MAX_TEACHING_BYTES + 1 },
  }

  it("asks for what is not installed or differs, never more than 5,000,000 bytes", () => {
    expect(filesToFetch(files, {})).toEqual([
      "ad-model.json",
      "ad-library.json",
      "show-habits.json",
    ])
  })

  it("leaves out a file the phone refused until the list shows another checksum", () => {
    const refused = { "ad-model.json": SHA_A.toUpperCase() }
    expect(filesToFetch(files, {}, refused)).toEqual([
      "ad-library.json",
      "show-habits.json",
    ])
    const changed = { ...files, "ad-model.json": { sha256: SHA_B, bytes: 100 } }
    expect(filesToFetch(changed, {}, refused)[0]).toBe("ad-model.json")
  })

  it("fetches the Mac's marks of the night before like the others", () => {
    const marks = { "ahead-ads.json": { sha256: SHA_A, bytes: 20000 } }
    expect(filesToFetch(marks, {})).toEqual(["ahead-ads.json"])
    expect(filesToFetch(marks, { "ahead-ads.json": SHA_A })).toEqual([])
    expect(
      filesToFetch(
        { "ahead-ads.json": { sha256: SHA_A, bytes: MAX_TEACHING_BYTES + 1 } },
        {},
      ),
    ).toEqual([])
  })

  it("fetches the meaning model and the settings like the others", () => {
    const more = {
      "ad-meaning.json": { sha256: SHA_A, bytes: 100 },
      "show-settings.json": { sha256: SHA_B, bytes: MAX_TEACHING_BYTES + 1 },
    }
    expect(filesToFetch(more, {})).toEqual(["ad-meaning.json"])
    expect(filesToFetch(more, { "ad-meaning.json": SHA_A })).toEqual([])
    expect(
      filesToFetch(
        { ...more, "show-settings.json": { sha256: SHA_B, bytes: 9 } },
        {
          "ad-meaning.json": SHA_A,
        },
      ),
    ).toEqual(["show-settings.json"])
    expect(filesToFetch(more, {}, { "ad-meaning.json": SHA_A })).toEqual([])
  })

  it("leaves out what is installed with the same checksum, in any letter case", () => {
    const installed = {
      "ad-model.json": SHA_A.toUpperCase(),
      "ad-library.json": SHA_B,
    }
    expect(filesToFetch(files, installed)).toEqual([
      "ad-library.json",
      "show-habits.json",
    ])
  })

  it("asks for nothing when the list has nothing", () => {
    expect(filesToFetch({}, {})).toEqual([])
    expect(TEACHING_NAMES).toHaveLength(8)
  })
})

describe("showTable", () => {
  it("maps each feed key to its show id", () => {
    const table = showTable([
      { id: "s1", feedUrl: "https://www.Example.com/feed/" },
      { id: "s2", feedUrl: "http://other.org/rss?x=1#top" },
    ])
    expect(table).toEqual({
      "example.com/feed": "s1",
      "other.org/rss?x=1": "s2",
    })
  })

  it("also maps the Apple export's address of a show matched by title", () => {
    const table = showTable(
      [{ id: "s1", feedUrl: "https://lib.test/feed", title: "The Daily" }],
      {
        shows: [
          { feed: "https://apple.test/new", title: " the daily " },
          { feed: "https://lib.test/feed", title: "The Daily" },
          { feed: "https://x.test/feed", title: "Another" },
          { feed: "https://y.test/feed", title: null },
        ],
        finished: [],
      },
    )
    expect(table).toEqual({ "lib.test/feed": "s1", "apple.test/new": "s1" })
    expect(showTableText([], null)).toBe("{}")
  })

  it("leaves out the added files' stand-in show", () => {
    expect(showTable([{ id: "local-files", feedUrl: "local:files" }])).toEqual(
      {},
    )
  })

  it("gives the same text whatever order the shows come in", () => {
    const a = { id: "s1", feedUrl: "https://a.com/f" }
    const b = { id: "s2", feedUrl: "https://b.com/f" }
    expect(showTableText([a, b])).toBe(showTableText([b, a]))
    expect(JSON.parse(showTableText([a, b]))).toEqual({
      "a.com/f": "s1",
      "b.com/f": "s2",
    })
  })
})

describe("dueForTeaching", () => {
  const TEN_MINUTES = 10 * 60 * 1000

  it("runs the first time, then at most once in ten minutes", () => {
    expect(dueForTeaching(null, 5000)).toBe(true)
    expect(dueForTeaching(1000, 1000 + TEN_MINUTES - 1)).toBe(false)
    expect(dueForTeaching(1000, 1000 + TEN_MINUTES)).toBe(true)
  })

  it("runs when the clock went back", () => {
    expect(dueForTeaching(9000, 1000)).toBe(true)
  })
})

describe("dueForPlay", () => {
  it("runs at Play the first time, then at most once a minute", () => {
    expect(dueForPlay(null, 5000)).toBe(true)
    expect(dueForPlay(1000, 1000 + 59_999)).toBe(false)
    expect(dueForPlay(1000, 1000 + 60_000)).toBe(true)
  })

  it("runs when the clock went back", () => {
    expect(dueForPlay(9000, 1000)).toBe(true)
  })
})

describe("parseTeachingState", () => {
  it("reads what the phone has installed", () => {
    const state = parseTeachingState(
      JSON.stringify({
        files: {
          "ad-model.json": { sha256: SHA_A, installedAt: 1700000000000 },
        },
        model: {
          writtenAt: "2026-11-10T09:00:00Z",
          episodes: 312,
          precision: 0.93,
          recall: 0.8,
        },
        library: 41,
        habits: 12,
        sounds: 7,
      }),
    )
    expect(state.installed).toEqual({ "ad-model.json": SHA_A })
    expect(state.model).toEqual({
      writtenAt: "2026-11-10T09:00:00Z",
      episodes: 312,
      precision: 0.93,
      recall: 0.8,
    })
    expect(state).toMatchObject({ library: 41, habits: 12, sounds: 7 })
  })

  it("is empty for anything it cannot read", () => {
    for (const text of [null, "", "nope", "[]", "{}"]) {
      expect(parseTeachingState(text)).toEqual({
        installed: {},
        model: null,
        library: 0,
        habits: 0,
        sounds: 0,
      })
    }
  })

  it("leaves out a model with no usable numbers", () => {
    const state = parseTeachingState(
      JSON.stringify({ model: { writtenAt: 5, episodes: "x" } }),
    )
    expect(state.model).toBeNull()
  })
})

describe("dueForAhead", () => {
  it("looks again after a minute, or when the clock went back", () => {
    expect(dueForAhead(null, 5000)).toBe(true)
    expect(dueForAhead(1000, 1000 + 59_999)).toBe(false)
    expect(dueForAhead(1000, 1000 + 60_000)).toBe(true)
    expect(dueForAhead(9000, 1000)).toBe(true)
  })
})

describe("aheadEpisodesText", () => {
  const show = (id: string, feedUrl = `https://${id}.test/feed`) => ({
    id,
    feedUrl,
  })
  const episode = (id: string, extra: object = {}) => ({
    id,
    guid: `guid-${id}`,
    title: `Title ${id}`,
    played: false,
    archived: false,
    ...extra,
  })

  it("tells each episode's feed, guid and title by its id", () => {
    const text = aheadEpisodesText([show("s1")], { s1: [episode("e1")] })
    expect(JSON.parse(text)).toEqual({
      e1: { feed: "https://s1.test/feed", guid: "guid-e1", title: "Title e1" },
    })
  })

  it("keeps the keys in order, so a table that did not change reads the same", () => {
    const shows = [show("s1"), show("s2")]
    const first = aheadEpisodesText(shows, {
      s1: [episode("e9"), episode("e2")],
      s2: [episode("e5")],
    })
    const second = aheadEpisodesText([...shows].reverse(), {
      s2: [episode("e5")],
      s1: [episode("e2"), episode("e9")],
    })
    expect(Object.keys(JSON.parse(first))).toEqual(["e2", "e5", "e9"])
    expect(second).toBe(first)
  })

  it("leaves out played and archived episodes", () => {
    const text = aheadEpisodesText([show("s1")], {
      s1: [
        episode("old", { played: true }),
        episode("away", { archived: true }),
        episode("next"),
      ],
    })
    expect(Object.keys(JSON.parse(text))).toEqual(["next"])
  })

  it("takes the newest few of each show (the list is newest first)", () => {
    const many = Array.from({ length: AHEAD_PER_SHOW + 5 }, (_, i) =>
      episode(`e${String(i).padStart(2, "0")}`),
    )
    const ids = Object.keys(
      JSON.parse(aheadEpisodesText([show("s1")], { s1: many })),
    )
    expect(ids).toHaveLength(AHEAD_PER_SHOW)
    expect(ids).toContain("e00")
    expect(ids).not.toContain(`e${String(AHEAD_PER_SHOW).padStart(2, "0")}`)
  })

  it("never tells more than the most the phone keeps, and skips shows with no feed", () => {
    const shows = Array.from({ length: 60 }, (_, i) => show(`s${i}`))
    const episodes: Record<string, ReturnType<typeof episode>[]> = {}
    for (const one of shows)
      episodes[one.id] = Array.from({ length: AHEAD_PER_SHOW }, (_, i) =>
        episode(`${one.id}-${i}`),
      )
    const withLocal = [{ id: "files", feedUrl: LOCAL_FEED_URL }, ...shows]
    episodes["files"] = [episode("a-file")]
    const table = JSON.parse(aheadEpisodesText(withLocal, episodes))
    expect(Object.keys(table)).toHaveLength(AHEAD_MOST)
    expect(table["a-file"]).toBeUndefined()
  })

  it("is an empty table when there is nothing to tell", () => {
    expect(aheadEpisodesText([], {})).toBe("{}")
    expect(aheadEpisodesText([show("s1")], {})).toBe("{}")
  })

  describe("the episodes of the phone's list for the Mac", () => {
    const many = (count: number, prefix = "e") =>
      Array.from({ length: count }, (_, i) =>
        episode(`${prefix}${String(i).padStart(2, "0")}`),
      )
    const listed = (feed: string, id: string) => ({
      feed,
      guid: `guid-${id}`,
    })

    it("are in the table even when they are older than the newest few of their show", () => {
      const older = `e${String(AHEAD_PER_SHOW + 5).padStart(2, "0")}`
      const text = aheadEpisodesText(
        [show("s1")],
        { s1: many(AHEAD_PER_SHOW + 8) },
        [listed("https://s1.test/feed", older)],
      )
      const ids = Object.keys(JSON.parse(text))
      expect(ids).toHaveLength(AHEAD_PER_SHOW + 1)
      expect(ids).toContain(older)
      expect(ids).toContain("e00")
    })

    it("are in the table whatever the library says about them being played or put away", () => {
      const text = aheadEpisodesText(
        [show("s1")],
        {
          s1: [
            episode("played", { played: true }),
            episode("away", { archived: true }),
            episode("other", { played: true }),
          ],
        },
        [
          listed("https://s1.test/feed", "played"),
          listed("https://s1.test/feed", "away"),
        ],
      )
      expect(Object.keys(JSON.parse(text))).toEqual(["away", "played"])
    })

    it("are found by feed and guid together, so another show's guid is not taken", () => {
      const text = aheadEpisodesText(
        [show("s1"), show("s2")],
        { s1: [], s2: many(AHEAD_PER_SHOW + 8) },
        [listed("https://s1.test/feed", "e15")],
      )
      const ids = Object.keys(JSON.parse(text))
      expect(ids).toHaveLength(AHEAD_PER_SHOW)
      expect(ids).not.toContain("e15")
    })

    it("are left out of the table when the library does not have them", () => {
      const text = aheadEpisodesText([show("s1")], { s1: many(2) }, [
        listed("https://s1.test/feed", "gone"),
      ])
      expect(Object.keys(JSON.parse(text))).toEqual(["e00", "e01"])
    })

    it("stay in the table when it is full", () => {
      const shows = Array.from({ length: 60 }, (_, i) => show(`s${i}`))
      const episodes: Record<string, ReturnType<typeof episode>[]> = {}
      for (const one of shows)
        episodes[one.id] = Array.from({ length: AHEAD_PER_SHOW + 3 }, (_, i) =>
          episode(`${one.id}-${String(i).padStart(2, "0")}`),
        )
      // The last show comes after the table is full, and this is not one of its newest.
      const last = `s59-${String(AHEAD_PER_SHOW + 2).padStart(2, "0")}`
      const table = JSON.parse(
        aheadEpisodesText(shows, episodes, [
          listed("https://s59.test/feed", last),
        ]),
      )
      expect(Object.keys(table)).toHaveLength(AHEAD_MOST)
      expect(table[last]).toBeDefined()
    })

    it("keep the keys in order, so a table that did not change reads the same", () => {
      const queue = [listed("https://s1.test/feed", "e03")]
      const first = aheadEpisodesText([show("s1")], { s1: many(20) }, queue)
      const keys = Object.keys(JSON.parse(first))
      expect(keys).toEqual([...keys].sort())
      expect(aheadEpisodesText([show("s1")], { s1: many(20) }, queue)).toBe(
        first,
      )
    })
  })
})
