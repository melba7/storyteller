// LOFI-FORK: the podcasts section's page sizes (see FORK.md).

/** The least space kept at each side of a page, which lines shelves up with the page's text. */
export const GUTTER = 16

/** What a page's content is laid out with: each side's padding and the width to size from. */
export type PageFrame = {
  left: number
  right: number
  /**
   * The width the sizing helpers expect: the window's, less what the insets take beyond the
   * 16 pt gutters (the helpers subtract those 32 pt themselves). On a window with no side insets
   * it is the window's own width.
   */
  width: number
}

/**
 * The page frame for a window width and its side safe-area insets. Each side is at least the
 * 16 pt gutter, or its inset when that is larger (a phone in landscape, or the folded Duo's
 * strip on the trailing edge). It follows the measured window, so it follows a fold or unfold.
 */
export function pageFrame(
  windowWidth: number,
  insets: { left: number; right: number },
): PageFrame {
  const left = Math.max(GUTTER, insets.left)
  const right = Math.max(GUTTER, insets.right)
  return {
    left,
    right,
    width: Math.max(1, windowWidth - left - right + GUTTER * 2),
  }
}

/** The most a show page's header picture measures. */
export const SHOW_HEADER_MAX = 430

/**
 * The side of a show page's square header picture: the window's width, but at most 430 and at
 * most 60% of the window's height, so a landscape phone, an iPad or an open Duo gets a header
 * that leaves room for the episodes. A portrait phone gets its full width, as before.
 */
export function showHeaderSide(windowWidth: number, windowHeight: number) {
  return Math.max(
    1,
    Math.min(windowWidth, SHOW_HEADER_MAX, Math.round(windowHeight * 0.6)),
  )
}

/** The most an Up Next card measures across. */
export const UP_NEXT_MAX = 300

/** The least height an Up Next card is cut down to: its words and buttons need about this. */
const UP_NEXT_MIN_HEIGHT = 300

/**
 * An Up Next card for a layout width: two thirds across, a third taller than wide, up to 300
 * wide. With the window's height, a card is at most about half of it (but never under 300
 * tall), so on a short window the card's buttons stay above the mini player and tab bar.
 */
export function upNextCardSize(layoutWidth: number, windowHeight = Infinity) {
  let width = Math.min(UP_NEXT_MAX, Math.round(layoutWidth * 0.66))
  let height = Math.round(width * 1.34)
  const cap = Math.max(Math.round(windowHeight * 0.52), UP_NEXT_MIN_HEIGHT)
  if (height > cap) {
    height = cap
    width = Math.round(cap / 1.34)
  }
  return { width, height }
}

/** A category tile's width with its 12 pt gap: how many fit across at about 180 pt each. */
const TILE_SLOT = 192

/** The columns of the category tiles: two on a phone, more as the window widens. */
export function categoryColumns(layoutWidth: number): number {
  return Math.max(2, Math.floor((layoutWidth - GUTTER * 2 + 12) / TILE_SLOT))
}

/** From this window width on, the grids of shows hold twice their usual columns. */
export const WIDE_FROM = 600

/** A grid's columns: its usual count, doubled on a wide window. */
export function gridColumns(base: number, layoutWidth: number): number {
  return layoutWidth >= WIDE_FROM && base > 1 ? base * 2 : base
}

/**
 * Splits a list into rows of `size` (the last may be shorter). The grids render these rows
 * as one-column list items, so a change of columns never remounts the list.
 */
export function chunkRows<T>(items: readonly T[], size: number): T[][] {
  const step = Math.max(1, Math.floor(size))
  const rows: T[][] = []
  for (let i = 0; i < items.length; i += step) {
    rows.push(items.slice(i, i + step))
  }
  return rows
}

/** The space between the cells of a grid. */
export const GRID_GAP = 12

/** The side of a grid cell for a layout width and a column count, between the 16 pt gutters. */
export function gridCellSize(layoutWidth: number, columns: number): number {
  const room = layoutWidth - GUTTER * 2 - GRID_GAP * (columns - 1)
  return Math.max(1, Math.floor(room / columns))
}
