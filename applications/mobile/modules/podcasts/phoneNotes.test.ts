// LOFI-FORK: the podcasts section's notes for the Mac (see FORK.md).
import { readFileSync } from "node:fs"
import { dirname, join } from "node:path"
import { fileURLToPath } from "node:url"

import { describe, expect, it } from "vitest"

import {
  MAX_NOTE_LINES,
  diaryStamp,
  oldNotesText,
  mergeNoteLines,
  newestNoteAt,
  noteLine,
  parsePendingNotes,
} from "./phoneNotes"

const pending = (extra: Record<string, unknown> = {}) =>
  JSON.stringify({
    v: 1,
    at: 1_700_000_000_000,
    what: "skipped",
    episode: "e1",
    show: "s1",
    start: 120.5,
    end: 185,
    kind: "ad",
    ...extra,
  })

describe("parsePendingNotes", () => {
  it("reads the lines and counts every line it read", () => {
    const text = [pending(), pending({ what: "missed", end: null })].join("\n")
    const read = parsePendingNotes(text)
    expect(read.count).toBe(2)
    expect(read.notes.map((note) => note.what)).toEqual(["skipped", "missed"])
    expect(read.notes[1]?.end).toBeNull()
  })

  it("drops a line that does not parse but still counts it as read", () => {
    const text = [
      "not json",
      pending({ what: "other" }),
      pending({ at: "soon" }),
      pending({ start: null }),
      pending({ episode: 5 }),
      "[]",
      pending(),
    ].join("\n")
    const read = parsePendingNotes(text)
    expect(read.notes).toHaveLength(1)
    expect(read.count).toBe(7)
  })

  it("has nothing for empty text and ignores blank lines", () => {
    expect(parsePendingNotes("")).toEqual({ notes: [], count: 0 })
    expect(parsePendingNotes(`\n${pending()}\n\n`).count).toBe(1)
  })

  it("keeps the answers to a question, with the finder's name when there is one", () => {
    const text = [
      pending({ what: "confirmed", by: "repeat-words" }),
      pending({ what: "denied", by: "meaning" }),
      pending({ what: "confirmed" }),
    ].join("\n")
    const read = parsePendingNotes(text)
    expect(read.count).toBe(3)
    expect(read.notes.map((note) => [note.what, note.by])).toEqual([
      ["confirmed", "repeat-words"],
      ["denied", "meaning"],
      ["confirmed", ""],
    ])
  })

  it("reads a note with no finder, a null finder or one that is not text as having none", () => {
    for (const by of [undefined, null, 5, ["own-sound"], {}]) {
      expect(parsePendingNotes(pending({ by })).notes[0]?.by).toBe("")
    }
  })

  it("keeps a missing or unknown kind empty, and a missing show for none", () => {
    const [note] = parsePendingNotes(
      pending({ kind: "weird", show: undefined }),
    ).notes
    expect(note?.kind).toBe("")
    expect(note?.show).toBe("")
    expect(parsePendingNotes(pending({ kind: null })).notes[0]?.kind).toBe("")
    expect(parsePendingNotes(pending({ kind: "promo" })).notes[0]?.kind).toBe(
      "promo",
    )
  })
})

describe("noteLine", () => {
  const [note] = parsePendingNotes(pending()).notes

  it("writes the line as the contract gives it, in this order", () => {
    const line = noteLine(note!, {
      feed: "https://example.com/feed",
      guid: "g-1",
      title: "Episode one",
      address: "https://example.com/1.mp3",
    })
    expect(line).toBe(
      '{"v":1,"at":1700000000000,"what":"skipped","feed":"https://example.com/feed","guid":"g-1","title":"Episode one","address":"https://example.com/1.mp3","start":120.5,"end":185,"kind":"ad"}',
    )
  })

  it("writes no by when the note has none", () => {
    const line = JSON.parse(noteLine(note!, null)) as Record<string, unknown>
    expect("by" in line).toBe(false)
  })

  it("writes by last, after kind, when the note has one", () => {
    const [named] = parsePendingNotes(
      pending({ what: "denied", by: "meaning" }),
    ).notes
    const line = noteLine(named!, null)
    expect(line.endsWith('"kind":"ad","by":"meaning"}')).toBe(true)
    expect(Object.keys(JSON.parse(line) as object).at(-1)).toBe("by")
  })

  it("passes by prepared through for the skip, the Undo and the miss of a prepared ad", () => {
    for (const what of ["skipped", "undone", "missed"]) {
      const [prepared] = parsePendingNotes(
        pending({ what, by: "prepared" }),
      ).notes
      const line = JSON.parse(noteLine(prepared!, null)) as Record<
        string,
        unknown
      >
      expect(line["by"]).toBe("prepared")
      expect(line["what"]).toBe(what)
    }
  })

  it("writes empty text for an episode that is gone and null for no end", () => {
    const [missed] = parsePendingNotes(pending({ end: null })).notes
    const line = JSON.parse(noteLine(missed!, null)) as Record<string, unknown>
    expect(line).toMatchObject({
      feed: "",
      guid: "",
      title: "",
      address: "",
      end: null,
    })
  })

  it("keeps what is known of the show when the episode is gone", () => {
    const line = JSON.parse(
      noteLine(note!, null, "https://example.com/feed"),
    ) as Record<string, unknown>
    expect(line["feed"]).toBe("https://example.com/feed")
    expect(line["guid"]).toBe("")
  })
})

describe("mergeNoteLines", () => {
  it("puts the new lines after the old ones, one per line, ending in a line break", () => {
    expect(mergeNoteLines('{"a":1}\n{"a":2}\n', ['{"a":3}'])).toBe(
      '{"a":1}\n{"a":2}\n{"a":3}\n',
    )
    expect(mergeNoteLines("", ['{"a":1}'])).toBe('{"a":1}\n')
  })

  it("keeps the newest 2,000 lines", () => {
    const old = Array.from({ length: MAX_NOTE_LINES }, (_, i) => `old${i}`)
    const merged = mergeNoteLines(`${old.join("\n")}\n`, ["new1", "new2"])
    const lines = merged.trimEnd().split("\n")
    expect(lines).toHaveLength(MAX_NOTE_LINES)
    expect(lines[0]).toBe("old2")
    expect(lines.at(-1)).toBe("new2")
  })

  it("skips added lines that are already in the old text", () => {
    expect(mergeNoteLines('{"a":1}\n{"a":2}\n', ['{"a":2}', '{"a":3}'])).toBe(
      '{"a":1}\n{"a":2}\n{"a":3}\n',
    )
    expect(mergeNoteLines('{"a":1}\n', ['{"a":1}'])).toBe('{"a":1}\n')
  })

  it("ignores blank lines in the old file", () => {
    expect(mergeNoteLines("\n\nx\n\n", ["y"])).toBe("x\ny\n")
  })
})

describe("newestNoteAt", () => {
  it("is the latest time of the notes, or the fallback when none was read", () => {
    const notes = parsePendingNotes(
      [pending({ at: 5 }), pending({ at: 9 }), pending({ at: 7 })].join("\n"),
    ).notes
    expect(newestNoteAt(notes, 100)).toBe(9)
    expect(newestNoteAt([], 100)).toBe(100)
  })
})

describe("diaryStamp", () => {
  it("is the same for the same text and differs when the text does", () => {
    expect(diaryStamp("line one\nline two\n")).toBe(
      diaryStamp("line one\nline two\n"),
    )
    expect(diaryStamp("line one\nline two\n")).not.toBe(
      diaryStamp("line one\nline twp\n"),
    )
    expect(diaryStamp("a\n")).not.toBe(diaryStamp("a\nb\n"))
  })
})

describe("oldNotesText", () => {
  it("is the file's text when it was read, and empty when there is no file yet", () => {
    expect(oldNotesText({ status: "found", text: "x\n" })).toBe("x\n")
    expect(oldNotesText({ status: "missing" })).toBe("")
  })

  it("is null when the file may be there but could not be read, so nothing is overwritten", () => {
    expect(oldNotesText({ status: "notDownloaded" })).toBeNull()
    expect(oldNotesText({ status: "unreadable", message: "no" })).toBeNull()
    expect(oldNotesText({ status: "notLinked" })).toBeNull()
    expect(oldNotesText({ status: "folderGone" })).toBeNull()
  })
})

// The two lines the Swift tests and the Mac's Python test share
// (libraries/PodcastKit/Tests/PodcastAdsTests/MacFixtures.swift): what the phone keeps, and what
// `noteLine` must make of it for the folder. Read from the Swift file, so one side cannot change
// without this test saying so.
const FIXTURES = join(
  dirname(fileURLToPath(import.meta.url)),
  "../../../../libraries/PodcastKit/Tests/PodcastAdsTests/MacFixtures.swift",
)

function fixtureLine(name: string): string {
  const found = new RegExp(`static let ${name} =\\s*#"(.*)"#`).exec(
    readFileSync(FIXTURES, "utf8"),
  )
  if (found?.[1] === undefined) throw new Error(`MacFixtures has no ${name}`)
  return found[1]
}

describe("the line the Mac reads", () => {
  it("is the shared folder line for the shared pending line, byte for byte", () => {
    const { notes, count } = parsePendingNotes(
      fixtureLine("confirmedPendingNote"),
    )
    expect(count).toBe(1)
    expect(notes).toHaveLength(1)
    const line = noteLine(notes[0]!, {
      feed: "https://show-a.test/feed",
      guid: "guid-1",
      title: "One",
      address: "https://show-a.test/one.mp3",
    })
    expect(line).toBe(fixtureLine("confirmedNote"))
  })
})
