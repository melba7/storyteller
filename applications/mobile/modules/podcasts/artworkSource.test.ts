// LOFI-FORK: the podcasts section's cover pictures (see FORK.md).
import { describe, expect, it } from "vitest"

import { artworkSources, nextSource } from "./artworkSource"
import { LOCAL_ARTWORK } from "./localFiles"

const BASE =
  "https://is1-ssl.mzstatic.com/image/thumb/Podcasts/v4/a/b/c/mza_1.jpg"

describe("artworkSources", () => {
  it("asks for the 640 file for a 177 pt tile at 3x and keeps the original second", () => {
    expect(artworkSources(`${BASE}/100x100bb.png`, 177, 3)).toEqual([
      `${BASE}/640x640bb.jpg`,
      `${BASE}/100x100bb.png`,
    ])
  })

  it("picks the bucket from points times scale", () => {
    const url = `${BASE}/100x100bb.png`
    expect(artworkSources(url, 60, 3)[0]).toBe(`${BASE}/320x320bb.jpg`)
    expect(artworkSources(url, 40, 2)[0]).toBe(`${BASE}/160x160bb.jpg`)
    expect(artworkSources(url, 393, 3)[0]).toBe(`${BASE}/1280x1280bb.jpg`)
    expect(artworkSources(url, 2000, 3)[0]).toBe(`${BASE}/1280x1280bb.jpg`)
  })

  it("treats a scale of 0, NaN or 4 as 1 to 3", () => {
    const url = `${BASE}/100x100bb.png`
    expect(artworkSources(url, 100, 0)[0]).toBe(`${BASE}/160x160bb.jpg`)
    expect(artworkSources(url, 100, NaN)[0]).toBe(`${BASE}/160x160bb.jpg`)
    expect(artworkSources(url, 100, 4)[0]).toBe(artworkSources(url, 100, 3)[0])
    expect(artworkSources(url, 100, 3)[0]).toBe(`${BASE}/320x320bb.jpg`)
  })

  it("recognises 170x170bb.png and 600x600bb.jpg", () => {
    expect(artworkSources(`${BASE}/170x170bb.png`, 177, 3)[0]).toBe(
      `${BASE}/640x640bb.jpg`,
    )
    expect(artworkSources(`${BASE}/600x600bb.jpg`, 177, 3)).toEqual([
      `${BASE}/640x640bb.jpg`,
      `${BASE}/600x600bb.jpg`,
    ])
  })

  it("returns every other address unchanged and alone", () => {
    for (const url of [
      "https://feeds.example.com/show/cover.jpg",
      "https://i.scdn.co/image/ab67616d0000b273abc",
      `${BASE}`,
      "https://notmzstatic.com/a/100x100bb.png",
      "https://example.com/mzstatic.com/100x100bb.png",
      LOCAL_ARTWORK,
    ]) {
      expect(artworkSources(url, 177, 3)).toEqual([url])
    }
  })

  it("gives an empty list for null", () => {
    expect(artworkSources(null, 100, 3)).toEqual([])
  })

  it("does not throw on a malformed string", () => {
    expect(artworkSources("not a url ::: 100x100bb.png", 100, 3)).toEqual([
      "not a url ::: 100x100bb.png",
    ])
  })
})

describe("nextSource", () => {
  const sources = ["a", "b"]
  it("moves to the next address after a failure", () => {
    expect(nextSource(sources, 0)).toBe(1)
  })
  it("stays on the last address when none is left", () => {
    expect(nextSource(sources, 1)).toBe(1)
    expect(nextSource([], 0)).toBe(0)
  })
})
