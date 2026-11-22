// LOFI-FORK: the podcasts section's notes for the Mac (see FORK.md).
import { describe, expect, it } from "vitest"

import {
  MAX_NOTE_LINES,
  diaryStamp,
  oldNotesText,
  mergeNoteLines,
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

  it("takes a kind it does not know for an ad, and a missing show for none", () => {
    const [note] = parsePendingNotes(
      pending({ kind: "weird", show: undefined }),
    ).notes
    expect(note?.kind).toBe("ad")
    expect(note?.show).toBe("")
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

  it("ignores blank lines in the old file", () => {
    expect(mergeNoteLines("\n\nx\n\n", ["y"])).toBe("x\ny\n")
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
