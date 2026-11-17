import { describe, expect, it } from "vitest"

import {
  chapterArtwork,
  chapterEndOf,
  currentChapterIndex,
  readChapters,
} from "./chapters"

const raw = [
  { start: 0, title: "Intro", skipped: false },
  { start: 60, title: "Story", imageUrl: "https://x/a.jpg", skipped: false },
  { start: 600, end: 650, title: "Ad", skipped: true },
  { start: 700, title: "Outro", skipped: false },
]
const chapters = readChapters(raw)

describe("readChapters", () => {
  it("reads what Swift sends", () => {
    expect(chapters).toHaveLength(4)
    expect(chapters[2]).toEqual({
      start: 600,
      end: 650,
      title: "Ad",
      imageUrl: null,
      url: null,
      skipped: true,
    })
  })

  it("drops anything that is not a chapter and orders by start", () => {
    expect(readChapters("nope")).toEqual([])
    expect(readChapters(null)).toEqual([])
    const read = readChapters([
      { start: 20, title: "B" },
      { start: "x", title: "bad" },
      { title: "no start" },
      7,
      { start: 5, title: "A", skipped: true },
    ])
    expect(read.map((c) => c.title)).toEqual(["A", "B"])
    expect(read[0]?.skipped).toBe(true)
    expect(read[1]?.skipped).toBe(false)
  })
})

describe("currentChapterIndex", () => {
  it("is the last chapter that has started", () => {
    expect(currentChapterIndex(chapters, 0)).toBe(0)
    expect(currentChapterIndex(chapters, 59.9)).toBe(0)
    expect(currentChapterIndex(chapters, 60)).toBe(1)
    expect(currentChapterIndex(chapters, 9999)).toBe(3)
  })

  it("is none before the first chapter, with no chapters or for no time", () => {
    expect(
      currentChapterIndex(readChapters([{ start: 30, title: "A" }]), 5),
    ).toBe(null)
    expect(currentChapterIndex([], 5)).toBeNull()
    expect(currentChapterIndex(chapters, Number.NaN)).toBeNull()
  })

  it("is none in a gap after a chapter's own end", () => {
    expect(currentChapterIndex(chapters, 649)).toBe(2)
    expect(currentChapterIndex(chapters, 660)).toBeNull()
    expect(currentChapterIndex(chapters, 700)).toBe(3)
  })
})

describe("chapterEndOf", () => {
  it("is its own end, else the next start, else the episode's end", () => {
    expect(chapterEndOf(chapters, 2, 900)).toBe(650)
    expect(chapterEndOf(chapters, 1, 900)).toBe(600)
    expect(chapterEndOf(chapters, 3, 900)).toBe(900)
    expect(chapterEndOf(chapters, 3, null)).toBeNull()
  })
})

describe("chapterArtwork", () => {
  it("is the current chapter's picture, or null", () => {
    expect(chapterArtwork(chapters, 100)).toBe("https://x/a.jpg")
    expect(chapterArtwork(chapters, 10)).toBeNull()
    expect(chapterArtwork([], 10)).toBeNull()
  })
})
