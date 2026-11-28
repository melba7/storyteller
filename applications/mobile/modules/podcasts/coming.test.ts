// LOFI-FORK: the podcasts section's wait for the Mac's copy (see FORK.md).
import { readFileSync } from "node:fs"

import { describe, expect, it } from "vitest"

import {
  COMING_HOLD_MS,
  comingKey,
  heldKeys,
  parseComing,
  withoutHeld,
} from "./coming"

const NOW = 1_700_000_000_000
const sec = (ms: number) => Math.floor(ms / 1000)

describe("parseComing", () => {
  it("reads the top-level coming list next to episodes", () => {
    const text = JSON.stringify({
      version: 1,
      writtenAt: 1,
      episodes: [],
      coming: [{ feed: "f", guid: "g", since: 1_700_000_000 }],
    })
    expect(parseComing(text)).toEqual([
      { feed: "f", guid: "g", since: 1_700_000_000 },
    ])
  })
  it("is empty for a file without coming, damaged text or entries of the wrong shape", () => {
    expect(parseComing(JSON.stringify({ version: 1, episodes: [] }))).toEqual(
      [],
    )
    expect(parseComing("{nope")).toEqual([])
    expect(parseComing(JSON.stringify({ coming: "x" }))).toEqual([])
    expect(
      parseComing(
        JSON.stringify({
          coming: [
            { feed: "f", guid: "ok", since: 5 },
            { feed: "f", guid: 3, since: 5 },
            { feed: "", guid: "x", since: 5 },
            { feed: "f", guid: "y", since: "5" },
            null,
          ],
        }),
      ),
    ).toEqual([{ feed: "f", guid: "ok", since: 5 }])
  })
})

describe("heldKeys", () => {
  const entry = (agoMs: number) => ({
    feed: "f",
    guid: "g",
    since: sec(NOW - agoMs),
  })
  it("holds an episode that is coming and young", () => {
    expect(heldKeys([entry(60_000)], NOW).has(comingKey("f", "g"))).toBe(true)
  })
  it("releases it at 2 hours", () => {
    expect(heldKeys([entry(COMING_HOLD_MS - 2000)], NOW).size).toBe(1)
    expect(heldKeys([entry(COMING_HOLD_MS)], NOW).size).toBe(0)
    expect(heldKeys([entry(COMING_HOLD_MS + 60_000)], NOW).size).toBe(0)
  })
  it("releases it when the entry is gone", () => {
    expect(heldKeys([], NOW).size).toBe(0)
  })
  it("does not believe a since far ahead of the phone's clock", () => {
    expect(heldKeys([entry(-3 * 60 * 60 * 1000)], NOW).size).toBe(0)
  })
})

describe("withoutHeld", () => {
  it("leaves out the held episodes of an automatic download", () => {
    const list = [{ id: "a" }, { id: "b" }, { id: "c" }]
    expect(withoutHeld(list, new Set(["b"]))).toEqual([
      { id: "a" },
      { id: "c" },
    ])
    expect(withoutHeld(list, new Set())).toEqual(list)
  })
})

describe("what never waits", () => {
  const read = (name: string) =>
    readFileSync(new URL(`./${name}`, import.meta.url), "utf8")
  it("keeps Play and a download the listener starts out of the wait", () => {
    // Only automaticRun.ts filters; the play-through and the manual download never see the list.
    for (const name of [
      "downloadOnPlay.ts",
      "downloads.ts",
      "downloadsNative.ts",
    ])
      expect(read(name)).not.toMatch(/\.\/coming/)
    expect(read("automaticRun.ts")).toMatch(/withoutHeld/)
  })
})
