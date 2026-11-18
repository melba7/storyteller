// LOFI-FORK: the podcasts section's player screen (see FORK.md).
//
// The player's sizes that depend on the room it gets: which layout the sheet uses, how the
// artwork is drawn, the gutters, the drag rows' height under large text and the two rows
// that are too wide on a 320 pt screen. Pure, and based only on measured sizes, so it holds
// on any phone, in landscape and on the iPhone Duo folded or open.

/**
 * Under this sheet height a wide sheet is laid out in two columns. It is 640 so that the open
 * iPhone Duo's sheet (about 653 by 587 pt) is split too.
 */
const SHORT_SHEET = 640
/** Under this much room above the controls (large text, a folded Duo) the artwork is left out. */
export const MIN_ART_AREA = 100
/** A sheet this much wider than the room above its controls shows the artwork as a square. */
const WIDE_RATIO = 0.75

/** Whether the sheet is a short, wide one (phone landscape): artwork or panel beside the controls. */
export function sideBySide(sheet: { width: number; height: number }): boolean {
  return (
    sheet.width > 0 &&
    sheet.height > 0 &&
    sheet.width > sheet.height &&
    sheet.height < SHORT_SHEET
  )
}

/**
 * The widths of the two columns of a split sheet. Both are set outright, because left to share
 * the room by `flex`, the iPhone Duo folded in landscape gave the artwork under a quarter of it.
 */
export function splitWidths(sheetWidth: number): {
  area: number
  controls: number
} {
  const area = Math.floor(sheetWidth / 2)
  return { area, controls: sheetWidth - area }
}

export type ArtworkPlan =
  | { kind: "hidden" }
  /** As wide as the sheet, cut off at `height`, fading into the sheet. */
  | { kind: "edge"; height: number }
  /** A centred rounded square inside the free `height`, with no fade. */
  | { kind: "contained"; height: number }

/**
 * How to draw the artwork. `areaHeight` is the measured room above the controls, or null until
 * it is measured (then the artwork is as tall as it can be, so it doesn't jump).
 */
export function artworkPlan(input: {
  sheetWidth: number
  areaWidth: number
  areaHeight: number | null
  grabber: number
  minArea: number
  sideBySide: boolean
}): ArtworkPlan {
  const { sheetWidth, areaHeight, grabber, minArea } = input
  if (areaHeight === null) {
    return input.sideBySide
      ? { kind: "contained", height: 0 }
      : { kind: "edge", height: sheetWidth }
  }
  if (areaHeight < minArea) return { kind: "hidden" }
  if (input.sideBySide || areaHeight + grabber < sheetWidth * WIDE_RATIO) {
    return { kind: "contained", height: areaHeight }
  }
  return { kind: "edge", height: Math.min(sheetWidth, areaHeight + grabber) }
}

/** The space left and right of the panels (area) and of the controls, clear of the safe-area insets. */
export function sheetGutters(input: {
  side: number
  insets: { left: number; right: number }
  sideBySide: boolean
}) {
  const left = Math.max(input.side, input.insets.left)
  const right = Math.max(input.side, input.insets.right)
  const inner = input.side / 2
  return input.sideBySide
    ? {
        areaLeft: left,
        areaRight: inner,
        controlsLeft: inner,
        controlsRight: right,
      }
    : {
        areaLeft: left,
        areaRight: right,
        controlsLeft: left,
        controlsRight: right,
      }
}

/** A drag row's height for the text size: it grows with large text, up to 1.5 times. */
export function rowHeightFor(base: number, fontScale: number): number {
  return Math.ceil(base * Math.min(1.5, Math.max(1, fontScale)))
}

const TRANSPORT = { play: 80, skip: 56, side: 48 }
const TRANSPORT_MIN = { play: 64, skip: 48, side: 44 }

/**
 * The transport row's box sizes for the width it has. Today's sizes (288 pt in all) when they
 * fit; on a narrower row the play box shrinks first, then the skip boxes, then the two outer
 * ones, so the row is never wider than the screen.
 */
export function transportSizes(available: number | null) {
  const sizes = { ...TRANSPORT }
  if (available === null) return sizes
  const total = () => sizes.play + sizes.skip * 2 + sizes.side * 2
  for (const key of ["play", "skip", "side"] as const) {
    const over = total() - available
    if (over <= 0) break
    const cut = key === "play" ? over : Math.ceil(over / 2)
    sizes[key] = Math.max(TRANSPORT_MIN[key], sizes[key] - cut)
  }
  return sizes
}

/** The gap between the episode page's round buttons (48 pt): 16, or less if the row is narrow. */
export function actionGap(available: number | null, count: number): number {
  if (available === null || count < 2) return 16
  const room = Math.floor((available - count * 48) / (count - 1))
  return Math.max(4, Math.min(16, room))
}

/** Every orientation, for the modals: React Native's Modal allows only portrait on iOS without it. */
export const ALL_ORIENTATIONS: (
  | "portrait"
  | "portrait-upside-down"
  | "landscape"
  | "landscape-left"
  | "landscape-right"
)[] = [
  "portrait",
  "portrait-upside-down",
  "landscape",
  "landscape-left",
  "landscape-right",
]
