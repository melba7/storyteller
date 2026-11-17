// LOFI-FORK: the podcasts section's ads (see FORK.md).
import { describe, expect, it } from "vitest"

import {
  adRows,
  adsMapFromList,
  adsStatus,
  applyAdsChange,
  formatClock,
  parseAdsFile,
  withAds,
} from "./ads"
import type { AdsInfo } from "./index"

const info = (
  state: AdsInfo["state"],
  extra: Partial<AdsInfo> = {},
): AdsInfo => ({ episodeId: "e1", state, ...extra })

describe("adsStatus", () => {
  it("says where the ad finding is", () => {
    expect(adsStatus(undefined)).toBe("")
    expect(adsStatus(info("waiting"))).toBe("Waiting to find ads")
    expect(adsStatus(info("finding", { percent: 30 }))).toBe("Finding ads")
    expect(adsStatus(info("found", { count: 3 }))).toBe("3 ads found")
    expect(adsStatus(info("found", { count: 1 }))).toBe("1 ad found")
    expect(adsStatus(info("noAds"))).toBe("No ads found")
  })

  it("gives the reason when ads can't be found", () => {
    expect(
      adsStatus(info("unavailable", { reason: "Apple Intelligence is off" })),
    ).toBe("Apple Intelligence is off")
    expect(adsStatus(info("unavailable"))).toBe("Can't find ads")
  })

  it("puts the ads after the download and transcript lines", () => {
    expect(
      withAds("340 MB · Transcript ready", info("found", { count: 2 })),
    ).toBe("340 MB · Transcript ready · 2 ads found")
    expect(withAds("", info("noAds"))).toBe("No ads found")
    expect(withAds("340 MB", undefined)).toBe("340 MB")
  })
})

describe("changes from Swift", () => {
  it("adds, replaces and removes", () => {
    let map = adsMapFromList([info("waiting")])
    map = applyAdsChange(map, info("found", { count: 2 }))
    expect(map["e1"]?.count).toBe(2)
    map = applyAdsChange(map, { episodeId: "e1", state: "none" })
    expect(map).toEqual({})
    expect(applyAdsChange(map, { episodeId: "x", state: "none" })).toBe(map)
  })
})

describe("formatClock", () => {
  it("writes minutes and seconds, and hours from an hour on", () => {
    expect(formatClock(0)).toBe("0:00")
    expect(formatClock(65.9)).toBe("1:05")
    expect(formatClock(3723)).toBe("1:02:03")
    expect(formatClock(-4)).toBe("0:00")
    expect(formatClock(Number.NaN)).toBe("0:00")
  })
})

const ad = (
  start: number,
  end: number,
  extra: Record<string, unknown> = {},
) => ({
  start,
  end,
  kind: "ad",
  advertiser: "Acme",
  confidence: "sure",
  firstWords: "this episode is brought to you by",
  ...extra,
})

describe("parseAdsFile", () => {
  it("reads the ads in order and the undone ones", () => {
    const file = parseAdsFile(
      JSON.stringify({
        ads: [ad(300, 360), ad(60, 120)],
        undone: [{ start: 300, end: 360 }],
      }),
    )
    expect(file?.ads.map((item) => item.start)).toEqual([60, 300])
    expect(file?.undone).toEqual([{ start: 300, end: 360 }])
  })

  it("leaves out entries that make no sense", () => {
    const file = parseAdsFile(
      JSON.stringify({
        ads: [
          ad(60, 120),
          ad(200, 100),
          ad(5, 50, { kind: "banner" }),
          ad(5, 50, { confidence: "certain" }),
          null,
          "x",
          ad(Number.NaN, 5),
        ],
      }),
    )
    expect(file?.ads).toHaveLength(1)
  })

  it("gives null for text that is not an ads file", () => {
    expect(parseAdsFile("not json")).toBeNull()
    expect(parseAdsFile("[]")).toBeNull()
    expect(parseAdsFile("{}")).toBeNull()
    expect(parseAdsFile("null")).toBeNull()
  })
})

describe("adRows", () => {
  it("lists time, length, kind, advertiser and first words", () => {
    const file = parseAdsFile(JSON.stringify({ ads: [ad(723, 788)] }))
    const [row] = adRows(file!)
    expect(row).toMatchObject({
      start: 723,
      time: "12:03",
      length: "1:05",
      kind: "Ad",
      advertiser: "Acme",
      firstWords: "this episode is brought to you by",
      skipped: true,
      undone: false,
    })
    expect(row?.label).toBe("Ad at 12:03, 1:05 long, Acme")
  })

  it("marks the host's plugs, the unsure ones and the undone ones", () => {
    const file = parseAdsFile(
      JSON.stringify({
        ads: [
          ad(10, 60, { kind: "ownPlug" }),
          ad(100, 160, { confidence: "unsure" }),
          ad(200, 260),
          ad(300, 360, { confidence: "guess" }),
        ],
        undone: [{ start: 200, end: 260 }],
      }),
    )
    const rows = adRows(file!)
    expect(rows.map((row) => row.kind)).toEqual(["Host plug", "Ad", "Ad"])
    expect(rows.map((row) => row.skipped)).toEqual([true, false, false])
    expect(rows.map((row) => row.undone)).toEqual([false, false, true])
    expect(rows[1]?.label).toContain("not sure")
  })
})
