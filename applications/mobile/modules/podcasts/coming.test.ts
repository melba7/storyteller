// LOFI-FORK: the podcasts section's wait for the Mac's copy (see FORK.md).
import { readFileSync } from "node:fs"

import { describe, expect, it } from "vitest"

import { type NewEpisode, parseFollowUps } from "./automatic"

import {
  COMING_HOLD_MS,
  comingKey,
  heldKeys,
  parseComing,
  sortHeld,
  WAITING_KEEP_MS,
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

describe("comingKey", () => {
  it("is the same for two spellings of one feed address, as on the phone's native side", () => {
    const key = comingKey("https://feeds.example.com/show", "g1")
    for (const spelled of [
      "http://feeds.example.com/show",
      "https://www.Feeds.Example.com/show/",
      " https://feeds.example.com/show#top ",
    ])
      expect(comingKey(spelled, "g1")).toBe(key)
    expect(comingKey("https://feeds.example.com/Show", "g1")).not.toBe(key)
    expect(comingKey("https://feeds.example.com/show", "g2")).not.toBe(key)
  })
  it("holds an episode whose feed the Mac spelled differently", () => {
    const coming = [
      { feed: "http://www.example.com/feed/", guid: "g", since: sec(NOW) },
    ]
    expect(
      heldKeys(coming, NOW).has(comingKey("https://example.com/feed", "g")),
    ).toBe(true)
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

describe("sortHeld", () => {
  const episode: NewEpisode = {
    id: "e1",
    showId: "s1",
    publishedAt: 5,
    audioUrl: "https://x/e1.mp3",
    audioType: "audio/mpeg",
  }
  const coming = [{ feed: "f", guid: "g", since: sec(NOW) }]
  // The library says episode e1 is the one with this feed and guid.
  const heldIds = (now: number) =>
    new Set(heldKeys(coming, now).has(comingKey("f", "g")) ? ["e1"] : [])
  /** One run: what starts now, and what is saved for the next run (through the saved text). */
  const run = (saved: NewEpisode[], now: number) => {
    const { start, waiting } = sortHeld(saved, heldIds(now), now)
    return { start, saved: parseFollowUps(JSON.stringify(waiting)) }
  }

  it("downloads a held new episode on a later run, once the hold has ended", () => {
    const first = run([episode], NOW)
    expect(first.start).toEqual([])
    expect(first.saved).toEqual([{ ...episode, waitingSince: NOW }])
    // Still held an hour later: it stays kept, with the time it was first held.
    const second = run(first.saved, NOW + 60 * 60 * 1000)
    expect(second.start).toEqual([])
    expect(second.saved).toEqual([{ ...episode, waitingSince: NOW }])
    // The Mac's copy never came and the 2 hours are over: it downloads now and is kept no more.
    const third = run(second.saved, NOW + COMING_HOLD_MS)
    expect(third.start.map((one) => one.id)).toEqual(["e1"])
    expect(third.saved).toEqual([])
  })
  it("downloads it as soon as the entry is gone from the Mac's list", () => {
    const { saved } = run([episode], NOW)
    const later = sortHeld(saved, new Set<string>(), NOW + 60_000)
    expect(later.start.map((one) => one.id)).toEqual(["e1"])
    expect(later.waiting).toEqual([])
  })
  it("starts what is not held at once", () => {
    expect(sortHeld([episode], new Set<string>(), NOW)).toEqual({
      start: [episode],
      waiting: [],
    })
  })
  it("forgets an episode that is still held after 2 days, so the list cannot grow for ever", () => {
    const old = { ...episode, waitingSince: NOW - WAITING_KEEP_MS }
    expect(sortHeld([old], new Set(["e1"]), NOW)).toEqual({
      start: [],
      waiting: [],
    })
    const young = { ...episode, waitingSince: NOW - WAITING_KEEP_MS + 1000 }
    expect(sortHeld([young], new Set(["e1"]), NOW).waiting).toEqual([young])
  })
  it("does not believe a time it was first held that is ahead of the clock", () => {
    const ahead = { ...episode, waitingSince: NOW + 10 * WAITING_KEEP_MS }
    expect(sortHeld([ahead], new Set(["e1"]), NOW).waiting).toEqual([
      { ...episode, waitingSince: NOW },
    ])
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
    // The newest-episode download keeps the held ones for the next run instead of dropping them.
    expect(read("newEpisodesRun.ts")).toMatch(/sortHeld/)
  })
})
