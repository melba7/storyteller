// LOFI-FORK: the podcasts section's teaching files from the Mac (see FORK.md).
import { describe, expect, it } from "vitest"

import {
  MAX_TEACHING_BYTES,
  TEACHING_NAMES,
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

  it("keeps only the four known files", () => {
    const parsed = parseTeachingList(
      list({
        "ad-model.json": { sha256: SHA_A, bytes: 1 },
        "../secret.json": { sha256: SHA_A, bytes: 1 },
        "other.json": { sha256: SHA_A, bytes: 1 },
      }),
    )
    expect(Object.keys(parsed ?? {})).toEqual(["ad-model.json"])
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
    expect(TEACHING_NAMES).toHaveLength(4)
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
