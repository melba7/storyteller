// LOFI-FORK: tests for the lofi score kept inside the read-aloud EPUB (see FORK.md).
import { mkdtemp, rm } from "node:fs/promises"
import { tmpdir } from "node:os"
import { join } from "node:path"

import { describe, expect, it, onTestFinished } from "vitest"

import { Epub } from "@storyteller-platform/epub"

import {
  describeScore,
  readScore,
  writeScore,
} from "@/app/api/v2/books/[bookId]/lofi-score/score"

/** A small EPUB of its own, saved to disk (the fixtures are LFS pointers in CI). */
async function freshBook() {
  const directory = await mkdtemp(join(tmpdir(), "lofi-score-"))
  onTestFinished(async () => {
    await rm(directory, { recursive: true, force: true })
  })
  const path = join(directory, "book.epub")
  using epub = await Epub.create(path, {
    title: "The Reader",
    language: new Intl.Locale("en-US"),
    identifier: "reader-1",
  })
  await epub.saveAndClose()
  return path
}

describe("the score inside the book", () => {
  it("knows a score from anything else", () => {
    expect(describeScore("not json")).toBeNull()
    expect(describeScore("[]")).toBeNull()
    expect(describeScore('{"format":2,"mood":{}}')).toBeNull()
    expect(describeScore('{"format":1}')).toBeNull()
    expect(describeScore('{"format":1,"mood":{"entries":[]}}')).toEqual({
      mood: true,
      atmosphere: false,
    })
    expect(
      describeScore('{"format":1,"mood":{},"atmosphere":{"cues":[]}}'),
    ).toEqual({ mood: true, atmosphere: true })
    expect(describeScore('{"format":1,"mood":null,"atmosphere":{}}')).toEqual({
      mood: false,
      atmosphere: true,
    })
  })

  it("is absent until put, then read back, replaced and still a valid EPUB", async () => {
    const path = await freshBook()
    expect(await readScore(path)).toBeNull()

    const first = '{"format":1,"mood":{"entries":[]},"atmosphere":{"cues":[]}}'
    await writeScore(path, first)
    expect((await readScore(path))?.toString("utf-8")).toBe(first)

    const second = '{"format":1,"atmosphere":{"cues":[{"place":"sea"}]}}'
    await writeScore(path, second)
    expect((await readScore(path))?.toString("utf-8")).toBe(second)

    using epub = await Epub.from(path)
    expect(await epub.getTitle()).toBe("The Reader")
  })
})
