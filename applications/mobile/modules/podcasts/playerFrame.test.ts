import { describe, expect, it } from "vitest"

import {
  MIN_ART_AREA,
  actionGap,
  artworkPlan,
  rowHeightFor,
  sheetGutters,
  sideBySide,
  splitWidths,
  transportSizes,
} from "./playerFrame"

describe("sideBySide", () => {
  it("is false until the sheet is measured", () => {
    expect(sideBySide({ width: 0, height: 0 })).toBe(false)
  })
  it("is true for a short, wide sheet (phone landscape)", () => {
    expect(sideBySide({ width: 852, height: 393 })).toBe(true)
  })
  it("is false in portrait and on a tall wide sheet", () => {
    expect(sideBySide({ width: 393, height: 780 })).toBe(false)
    expect(sideBySide({ width: 1024, height: 768 })).toBe(false)
  })
  it("is true for the open iPhone Duo's sheet and false for the folded one", () => {
    expect(sideBySide({ width: 653, height: 587 })).toBe(true)
    expect(sideBySide({ width: 466, height: 596 })).toBe(false)
  })
})

describe("splitWidths", () => {
  it("gives both halves a whole width that adds up to the sheet", () => {
    expect(splitWidths(650)).toEqual({ area: 325, controls: 325 })
    expect(splitWidths(653)).toEqual({ area: 326, controls: 327 })
  })
})

describe("artworkPlan", () => {
  const base = { sheetWidth: 393, areaWidth: 393, grabber: 24, minArea: 140 }
  it("is edge to edge, as wide as the sheet, before the area is measured", () => {
    expect(
      artworkPlan({ ...base, areaHeight: null, sideBySide: false }),
    ).toEqual({ kind: "edge", height: 393 })
  })
  it("stays edge to edge on a normal phone", () => {
    expect(
      artworkPlan({ ...base, areaHeight: 330, sideBySide: false }),
    ).toEqual({ kind: "edge", height: 354 })
  })
  it("is left out when the area is too small, but not when it is unmeasured", () => {
    expect(
      artworkPlan({ ...base, areaHeight: 0, sideBySide: false }).kind,
    ).toBe("hidden")
    expect(
      artworkPlan({ ...base, areaHeight: 139, sideBySide: false }).kind,
    ).toBe("hidden")
  })
  it("shows a small cover where the folded Duo leaves about 133 pt", () => {
    expect(
      artworkPlan({
        sheetWidth: 466,
        areaWidth: 466,
        areaHeight: 133,
        grabber: 24,
        minArea: MIN_ART_AREA,
        sideBySide: false,
      }),
    ).toEqual({ kind: "contained", height: 133 })
  })
  it("is a contained square on a wide sheet with little height", () => {
    expect(
      artworkPlan({
        sheetWidth: 600,
        areaWidth: 600,
        areaHeight: 280,
        grabber: 24,
        minArea: 140,
        sideBySide: false,
      }).kind,
    ).toBe("contained")
  })
  it("is contained in the left half when side by side", () => {
    expect(
      artworkPlan({
        sheetWidth: 852,
        areaWidth: 426,
        areaHeight: 330,
        grabber: 24,
        minArea: 140,
        sideBySide: true,
      }),
    ).toEqual({ kind: "contained", height: 330 })
  })
})

describe("sheetGutters", () => {
  it("keeps 32 each side in portrait", () => {
    expect(
      sheetGutters({
        side: 32,
        insets: { left: 0, right: 0 },
        sideBySide: false,
      }),
    ).toEqual({
      areaLeft: 32,
      areaRight: 32,
      controlsLeft: 32,
      controlsRight: 32,
    })
  })
  it("clears the island and the Duo strip", () => {
    expect(
      sheetGutters({
        side: 32,
        insets: { left: 62, right: 40 },
        sideBySide: false,
      }),
    ).toEqual({
      areaLeft: 62,
      areaRight: 40,
      controlsLeft: 62,
      controlsRight: 40,
    })
  })
  it("uses each inset only at its own screen edge when side by side", () => {
    expect(
      sheetGutters({
        side: 32,
        insets: { left: 62, right: 40 },
        sideBySide: true,
      }),
    ).toEqual({
      areaLeft: 62,
      areaRight: 16,
      controlsLeft: 16,
      controlsRight: 40,
    })
  })
})

describe("rowHeightFor", () => {
  it("is unchanged at the default text size", () => {
    expect(rowHeightFor(76, 1)).toBe(76)
    expect(rowHeightFor(76, 0.8)).toBe(76)
  })
  it("grows with the text and stops at 1.5 times", () => {
    expect(rowHeightFor(64, 1.2)).toBe(77)
    expect(rowHeightFor(64, 3)).toBe(96)
  })
})

describe("transportSizes", () => {
  const normal = { play: 80, skip: 56, side: 48 }
  it("keeps today's sizes when the row is wide enough or not measured", () => {
    expect(transportSizes(null)).toEqual(normal)
    expect(transportSizes(288)).toEqual(normal)
    expect(transportSizes(330)).toEqual(normal)
  })
  it("shrinks to fit a 320 pt screen (256 pt row)", () => {
    const s = transportSizes(256)
    expect(s.play + s.skip * 2 + s.side * 2).toBeLessThanOrEqual(256)
    expect(s.side).toBeGreaterThanOrEqual(44)
  })
  it("never goes under the smallest sizes", () => {
    expect(transportSizes(100)).toEqual({ play: 64, skip: 48, side: 44 })
  })
})

describe("actionGap", () => {
  it("keeps 16 when the buttons fit", () => {
    expect(actionGap(null, 5)).toBe(16)
    expect(actionGap(304, 5)).toBe(16)
    expect(actionGap(400, 5)).toBe(16)
  })
  it("tightens in a narrow row", () => {
    expect(actionGap(288, 5)).toBe(12)
  })
  it("never goes under 4 and handles a single button", () => {
    expect(actionGap(200, 5)).toBe(4)
    expect(actionGap(100, 1)).toBe(16)
  })
})
