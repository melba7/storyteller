// LOFI-FORK: the podcasts section's ads (see FORK.md).
import { describe, expect, it } from "vitest"

import {
  type AdsFile,
  SKIP_NOTE_BACK_SECONDS,
  SKIP_NOTE_MS,
  adMarks,
  adRows,
  adsFileAfterRead,
  adsMapFromList,
  adKindOf,
  adsStatus,
  applyAdsChange,
  readAdSkipSettings,
  DEFAULT_AD_SKIP_SETTINGS,
  formatClock,
  noteAfterUndo,
  readsAdsFile,
  unavailableReason,
  parseAdsFile,
  skipNote,
  skipNoteBackLabels,
  skipNoteShown,
  skipNoteText,
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

  it("says when some parts could not be checked", () => {
    expect(adsStatus(info("noAds", { unchecked: true }))).toBe(
      "Couldn't check some parts for ads",
    )
    expect(adsStatus(info("found", { count: 2, unchecked: true }))).toBe(
      "2 ads found. Couldn't check some parts",
    )
    expect(adsStatus(info("found", { count: 1, unchecked: false }))).toBe(
      "1 ad found",
    )
  })

  it("gives the reason when ads can't be found", () => {
    expect(
      adsStatus(info("unavailable", { reason: "Apple Intelligence is off" })),
    ).toBe("Apple Intelligence is off")
    expect(adsStatus(info("unavailable"))).toBe("Can't find ads")
  })

  it("shows one short line for a failure of this episode's own search", () => {
    const reason =
      "Finding ads stopped: The model couldn't finish: x [model error: A.B concurrentRequests]."
    const line = adsStatus(info("unavailable", { reason }))
    expect(line).toBe("Ad check paused. Trying again soon")
    expect(line).not.toContain("model error")
    // The same line wherever the status is used, with no technical tail or with another one.
    expect(
      adsStatus(
        info("unavailable", {
          reason: "Finding ads stopped: The model refused to read a part.",
        }),
      ),
    ).toBe("Ad check paused. Trying again soon")
    expect(withAds("340 MB", info("unavailable", { reason }))).toBe(
      "340 MB · Ad check paused. Trying again soon",
    )
  })

  it("keeps the words of a reason that belongs to the phone", () => {
    for (const reason of [
      "Apple Intelligence is off",
      "The model is downloading",
      "This iPhone can't run Apple Intelligence",
      "Needs iOS 26",
      "Apple Intelligence is not available",
      "The transcript could not be read",
    ]) {
      expect(adsStatus(info("unavailable", { reason }))).toBe(reason)
    }
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

  it("reads all four sorts and takes an unknown one for an ad", () => {
    const file = parseAdsFile(
      JSON.stringify({
        ads: [
          ad(10, 20, { kind: "ownPlug" }),
          ad(30, 40, { kind: "promo" }),
          ad(50, 60, { kind: "credits" }),
          ad(70, 80, { kind: "banner" }),
          ad(90, 100, { kind: undefined }),
        ],
      }),
    )
    expect(file?.ads.map((item) => item.kind)).toEqual([
      "ownPlug",
      "promo",
      "credits",
      "ad",
      "ad",
    ])
  })

  it("leaves out entries that make no sense", () => {
    const file = parseAdsFile(
      JSON.stringify({
        ads: [
          ad(60, 120),
          ad(200, 100),
          ad(5, 50, { confidence: "certain" }),
          null,
          "x",
          ad(Number.NaN, 5),
        ],
      }),
    )
    expect(file?.ads).toHaveLength(1)
  })

  it("cuts an ad short where the listener found the skip too far", () => {
    const file = parseAdsFile(
      JSON.stringify({
        ads: [ad(60, 120), ad(300, 360)],
        trims: [
          { adStart: 60, end: 110 },
          // A trim never makes an ad longer, and one for no ad here is ignored.
          { adStart: 300, end: 400 },
          { adStart: 700, end: 710 },
        ],
      }),
    )
    expect(file?.ads.map((item) => [item.start, item.end])).toEqual([
      [60, 110],
      [300, 360],
    ])
  })

  it("takes the same ad found a little differently as the trimmed one", () => {
    const file = parseAdsFile(
      JSON.stringify({
        ads: [ad(59.7, 130)],
        trims: [{ adStart: 60, end: 110 }],
      }),
    )
    expect(file?.ads[0]?.end).toBe(110)
  })

  it("leaves out an ad that a trim leaves with no length, and bad trims", () => {
    const file = parseAdsFile(
      JSON.stringify({
        ads: [ad(60, 120), ad(300, 360)],
        trims: [
          { adStart: 60, end: 60 },
          null,
          "x",
          { adStart: 300 },
          { adStart: Number.NaN, end: 310 },
        ],
      }),
    )
    expect(file?.ads.map((item) => item.start)).toEqual([300])
    expect(file?.ads[0]?.end).toBe(360)
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
    const more = adRows(
      parseAdsFile(
        JSON.stringify({
          ads: [ad(1, 5, { kind: "promo" }), ad(10, 15, { kind: "credits" })],
        }),
      )!,
    )
    expect(more.map((row) => row.kind)).toEqual(["Promo", "Credits"])
    // Sure and unsure ads are both skipped, unless the listener undid the skip.
    expect(rows.map((row) => row.skipped)).toEqual([true, true, false])
    expect(rows.map((row) => row.unsure)).toEqual([false, true, false])
    expect(rows.map((row) => row.undone)).toEqual([false, false, true])
    expect(rows[1]?.label).toContain("not sure")
  })
})

describe("the note after a skip", () => {
  const event = { episodeId: "e1", start: 723, end: 788, length: 65 }

  it("says how long the skipped ad was", () => {
    expect(skipNoteText(skipNote(event, 1000))).toBe("Skipped ad (1:05)")
    expect(skipNoteText(skipNote({ ...event, length: 3725 }, 0))).toBe(
      "Skipped ad (1:02:05)",
    )
  })

  it("stays for six seconds", () => {
    const note = skipNote(event, 10_000)
    expect(SKIP_NOTE_MS).toBe(6000)
    expect(skipNoteShown(note, 10_000)).toBe(true)
    expect(skipNoteShown(note, 15_999)).toBe(true)
    expect(skipNoteShown(note, 16_000)).toBe(false)
    expect(skipNoteShown(null, 16_000)).toBe(false)
  })

  it("goes when that skip is undone and stays for another one", () => {
    const note = skipNote(event, 0)
    expect(noteAfterUndo(note, { episodeId: "e1", start: 723 })).toBeNull()
    expect(noteAfterUndo(note, { episodeId: "e1", start: 5 })).toBe(note)
    expect(noteAfterUndo(note, { episodeId: "e2", start: 723 })).toBe(note)
    expect(noteAfterUndo(null, { episodeId: "e1", start: 723 })).toBeNull()
  })
})

describe("the note's Back button", () => {
  it("goes back ten seconds and says so", () => {
    expect(SKIP_NOTE_BACK_SECONDS).toBe(10)
    expect(skipNoteBackLabels()).toEqual({
      text: "Back 10 s",
      accessibility: "Back 10 seconds, the skip went too far",
    })
  })

  it("follows the seconds it is given", () => {
    expect(skipNoteBackLabels(15).text).toBe("Back 15 s")
  })
})

describe("adMarks", () => {
  const rows = [
    { start: 100, end: 160, skipped: true, unsure: false },
    { start: 500, end: 560, skipped: false, unsure: false },
    { start: 700, end: 760, skipped: true, unsure: true },
  ]

  it("places each ad as shares of the episode", () => {
    const marks = adMarks(rows, 1000)
    expect(marks[0]).toEqual({
      left: 0.1,
      width: 0.06,
      skipped: true,
      unsure: false,
    })
    expect(marks[1]?.left).toBe(0.5)
    expect(marks[1]?.skipped).toBe(false)
  })

  it("keeps the unsure ones apart: skipped, drawn faint", () => {
    expect(adMarks(rows, 1000)[2]).toMatchObject({
      skipped: true,
      unsure: true,
    })
  })

  it("draws nothing while the length is unknown", () => {
    expect(adMarks(rows, null)).toEqual([])
    expect(adMarks(rows, 0)).toEqual([])
  })

  it("keeps a mark inside the bar", () => {
    const [mark] = adMarks(
      [{ start: 950, end: 1100, skipped: true, unsure: false }],
      1000,
    )
    expect(mark?.left).toBe(0.95)
    expect(mark?.width).toBeCloseTo(0.05)
    expect(
      adMarks([{ start: 1200, end: 1300, skipped: true, unsure: false }], 1000),
    ).toEqual([])
  })
})

describe("the ads file while the full pass runs", () => {
  const partial = { ads: [] } as unknown as AdsFile
  it("is read when found and while finding, not otherwise", () => {
    expect(readsAdsFile(info("found"))).toBe(true)
    expect(readsAdsFile(info("finding", { percent: 10 }))).toBe(true)
    for (const state of ["waiting", "noAds", "unavailable"] as const) {
      expect(readsAdsFile(info(state))).toBe(false)
    }
    expect(readsAdsFile(undefined)).toBe(false)
  })

  it("keeps the last file when a read finds none while finding", () => {
    const kept = { episodeId: "a", file: partial }
    expect(adsFileAfterRead("finding", kept, "a", null)).toBe(partial)
    expect(adsFileAfterRead("found", kept, "a", null)).toBeNull()
    const next = { ads: [1] } as unknown as AdsFile
    expect(adsFileAfterRead("finding", kept, "a", next)).toBe(next)
  })

  it("never keeps another episode's file", () => {
    const kept = { episodeId: "a", file: partial }
    expect(adsFileAfterRead("finding", kept, "b", null)).toBeNull()
    expect(adsFileAfterRead("finding", null, "b", null)).toBeNull()
  })
})

describe("unavailableReason", () => {
  it("gives the phone's reason when any episode has one", () => {
    const map = adsMapFromList([
      info("found", { count: 1 }),
      {
        episodeId: "e2",
        state: "unavailable",
        reason: "Apple Intelligence is off",
      },
    ])
    expect(unavailableReason(map)).toBe("Apple Intelligence is off")
  })

  it("ignores one episode's own failure", () => {
    const map = adsMapFromList([
      info("unavailable", { reason: "Finding ads stopped: The model failed." }),
    ])
    expect(unavailableReason(map)).toBeNull()
    const both = adsMapFromList([
      info("unavailable", { reason: "Finding ads stopped: The model failed." }),
      {
        episodeId: "e2",
        state: "unavailable",
        reason: "The model is downloading",
      },
    ])
    expect(unavailableReason(both)).toBe("The model is downloading")
  })

  it("shows only the phone-wide reasons", () => {
    for (const reason of [
      "Apple Intelligence is off",
      "The model is downloading",
      "This iPhone can't run Apple Intelligence",
      "Needs iOS 26",
      "Apple Intelligence is not available",
    ]) {
      expect(
        unavailableReason(adsMapFromList([info("unavailable", { reason })])),
      ).toBe(reason)
    }
  })

  it("treats any other reason as one episode's failure", () => {
    for (const reason of [
      "The transcript could not be read",
      "The model refused this episode",
      "Finding ads stopped: The model failed.",
    ]) {
      expect(
        unavailableReason(adsMapFromList([info("unavailable", { reason })])),
      ).toBeNull()
    }
    expect(unavailableReason(adsMapFromList([info("unavailable")]))).toBeNull()
  })

  it("is null when ads can be found", () => {
    expect(unavailableReason(adsMapFromList([info("noAds")]))).toBeNull()
    expect(unavailableReason({})).toBeNull()
  })
})

describe("what a skip note says", () => {
  const event = { episodeId: "e1", start: 10, end: 75, length: 65 }

  it("names the sort that was skipped", () => {
    const text = (kind?: string) =>
      skipNoteText(skipNote({ ...event, kind }, 0))
    expect(text("ad")).toBe("Skipped ad (1:05)")
    expect(text("promo")).toBe("Skipped promo (1:05)")
    expect(text("ownPlug")).toBe("Skipped the hosts' plug (1:05)")
    expect(text("credits")).toBe("Skipped credits (1:05)")
  })

  it("says ad when the sort is missing or not known", () => {
    expect(skipNoteText(skipNote(event, 0))).toBe("Skipped ad (1:05)")
    expect(skipNoteText(skipNote({ ...event, kind: "x" }, 0))).toBe(
      "Skipped ad (1:05)",
    )
    expect(adKindOf(42)).toBe("ad")
  })
})

describe("the four switches", () => {
  it("start with ads, plugs and promos on and credits off", () => {
    expect(DEFAULT_AD_SKIP_SETTINGS).toEqual({
      skipAds: true,
      skipOwnPlugs: true,
      skipPromos: true,
      skipCredits: false,
    })
  })

  it("fills what the phone did not say from the defaults", () => {
    expect(readAdSkipSettings(null)).toEqual(DEFAULT_AD_SKIP_SETTINGS)
    expect(readAdSkipSettings({ skipAds: false, skipOwnPlugs: false })).toEqual(
      {
        skipAds: false,
        skipOwnPlugs: false,
        skipPromos: true,
        skipCredits: false,
      },
    )
    expect(
      readAdSkipSettings({
        skipAds: true,
        skipOwnPlugs: true,
        skipPromos: false,
        skipCredits: true,
      }),
    ).toMatchObject({ skipPromos: false, skipCredits: true })
  })
})
