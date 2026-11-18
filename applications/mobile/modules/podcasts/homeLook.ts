// LOFI-FORK: the podcasts section's Home (see FORK.md).
//
// Pure rules for how Home's cards and shelves read: the line over a card's title, the time
// left, the description without markup, the card's colours and how often a show updates.
import { blendOver, contrastBetween, vivid } from "./artworkTint"
import { cadenceWord } from "./cadence"
import { topLevelNames } from "./categories"
import { type ShelfEntry } from "./home"
import { type Show, formatEpisodeDate } from "./library"

const MINUTE = 60_000
const HOUR = 60 * MINUTE
const DAY = 24 * HOUR

/** "now", "12m ago", "17h ago", "5d ago", and the date after 30 days. */
export function agoLabel(at: number, now: number): string {
  const age = Math.max(0, now - at)
  if (age < MINUTE) return "now"
  if (age < HOUR) return `${Math.floor(age / MINUTE)}m ago`
  if (age < DAY) return `${Math.floor(age / HOUR)}h ago`
  if (age < 30 * DAY) return `${Math.floor(age / DAY)}d ago`
  return formatEpisodeDate(at)
}

/**
 * The tinted line over a card's title: "New · 17h ago" for a new episode (from its date),
 * "Resume · 5d ago" for one in progress (from when it was last played).
 */
export function cardLine(entry: ShelfEntry, now: number): string {
  const { episode, kind } = entry
  const word = kind === "resume" ? "Resume" : "New"
  const at =
    kind === "resume"
      ? (episode.lastPlayedAt ?? episode.publishedAt)
      : episode.publishedAt
  return at === null ? word : `${word} · ${agoLabel(at, now)}`
}

/**
 * The time on a card's capsule: what is left of an episode in progress, else its length, as
 * "19m", "1h 2m", "2h". Empty when the length is not known.
 */
export function timeLeftLabel(
  durationSeconds: number | null,
  positionSeconds: number,
): string {
  if (durationSeconds === null || !(durationSeconds > 0)) return ""
  const started = positionSeconds > 0 && positionSeconds < durationSeconds
  const seconds = started ? durationSeconds - positionSeconds : durationSeconds
  const minutes = Math.max(1, Math.round(seconds / 60))
  const hours = Math.floor(minutes / 60)
  const rest = minutes % 60
  if (hours === 0) return `${minutes}m`
  return rest === 0 ? `${hours}h` : `${hours}h ${rest}m`
}

const ENTITIES: Record<string, string> = {
  amp: "&",
  lt: "<",
  gt: ">",
  quot: '"',
  apos: "'",
  nbsp: " ",
}

/** Show notes as one plain line: tags gone, entities read, white space collapsed. */
export function plainText(html: string): string {
  return html
    .replace(/<\s*(br|\/p|\/div|\/li)\b[^>]*>/gi, " ")
    .replace(/<[^>]*>/g, "")
    .replace(/&(#x[0-9a-f]+|#\d+|[a-z]+);/gi, (whole, name: string) => {
      if (name[0] === "#") {
        const code =
          name[1] === "x" || name[1] === "X"
            ? parseInt(name.slice(2), 16)
            : parseInt(name.slice(1), 10)
        return Number.isFinite(code) && code > 0 && code < 0x110000
          ? String.fromCodePoint(code)
          : ""
      }
      return ENTITIES[name.toLowerCase()] ?? whole
    })
    .replace(/\s+/g, " ")
    .trim()
}

export type CardPalette = {
  /** The card's colour. */
  background: string
  /** The title and description. */
  text: string
  /** The "New · 17h ago" line, a lighter (or darker) tint of the colour. */
  label: string
  /** The translucent capsule behind the play button. */
  capsule: string
}

const NEAR_BLACK = "#111111"

/**
 * The colours of a card for an artwork colour: the colour a little deepened, and white or
 * near-black text, whichever reads better on it (white on ties).
 */
export function cardPalette(color: string): CardPalette {
  const background = blendOver("#000000", vivid(color), 0.25)
  const light = contrastBetween("#ffffff", background)
  const dark = contrastBetween(NEAR_BLACK, background)
  if (light >= dark) {
    return {
      background,
      text: "#ffffff",
      label: blendOver("#ffffff", background, 0.6),
      capsule: "rgba(255,255,255,0.25)",
    }
  }
  return {
    background,
    text: NEAR_BLACK,
    label: blendOver("#000000", background, 0.55),
    capsule: "rgba(0,0,0,0.12)",
  }
}

/** "Updated Daily", "Weekly", "Biweekly" or "Monthly"; empty when the rhythm is unknown. */
export function updateCadence(dates: readonly number[], now: number): string {
  const word = cadenceWord(dates, now)
  return word ? `Updated ${word}` : ""
}

/** The bold line under a Top Shows tile: the show's first category, else its title. */
export function topShowCaption(show: Pick<Show, "categories" | "title">) {
  return topLevelNames(show.categories)[0] ?? show.title
}

/** The height of one line of shelf text (Tailwind's `text-lg`: 18 pt on 28 pt). */
export const SHELF_LINE_HEIGHT = 28
/** The space between a shelf tile's artwork and its text (Tailwind's `mt-2`). */
export const SHELF_TEXT_GAP = 8
/** The space between neighbouring shelf tiles. */
export const SHELF_GAP = 12
/** The space at each end of a shelf, which lines it up with the page's text. */
export const SHELF_GUTTER = 16

/** The most a shelf tile's artwork measures, so a wide window draws no huge squares. */
export const SHELF_TILE_MAX = 220

/** The side of a shelf tile's square artwork: 45% of the window's width, rounded, up to 220. */
export function shelfTileSize(windowWidth: number): number {
  return Math.min(SHELF_TILE_MAX, Math.round(windowWidth * 0.45))
}

/** How far the shelf's text may grow with the system text size (its `maxFontSizeMultiplier`). */
export const SHELF_MAX_TEXT_SCALE = 1.2

/** The text scale a shelf plans for: the system's, but from 1 to `SHELF_MAX_TEXT_SCALE`. */
export function shelfTextScale(fontScale: number): number {
  return Math.min(SHELF_MAX_TEXT_SCALE, Math.max(1, fontScale))
}

/**
 * The height of a shelf: the artwork, the gap, then two lines of text (title and caption),
 * or three when the shelf shows ranks. The loading shelf uses it too, so they always agree.
 * `textScale` (from `shelfTextScale`) grows the lines as the system text size does.
 */
export function shelfHeight(
  tileSize: number,
  ranked: boolean,
  textScale = 1,
): number {
  const line = Math.ceil(SHELF_LINE_HEIGHT * textScale)
  return tileSize + SHELF_TEXT_GAP + (ranked ? 3 : 2) * line
}

/** Rows in one page of the episode shelf, and the side of a row's cover. */
export const EPISODE_ROWS = 3
export const EPISODE_COVER = 60
/** One episode row: the cover with 8 pt above and below. Three lines of 20 pt text fit in it. */
export const EPISODE_ROW_HEIGHT = EPISODE_COVER + 16
/** How much of the next page shows beside the current one. */
export const EPISODE_PEEK = 28

/** The width of one page of episode rows: the window less the gutter, the gap and the peek. */
export function episodeColumnWidth(windowWidth: number): number {
  return Math.max(0, windowWidth - SHELF_GUTTER - SHELF_GAP - EPISODE_PEEK)
}

/** The height of the episode shelf, which its loading shelf shares. */
export const EPISODE_SHELF_HEIGHT = EPISODE_ROWS * EPISODE_ROW_HEIGHT

/** Splits a list into pages of `EPISODE_ROWS`; the last page may be shorter. */
export function pagesOfRows<T>(items: readonly T[]): T[][] {
  const pages: T[][] = []
  for (let i = 0; i < items.length; i += EPISODE_ROWS) {
    pages.push(items.slice(i, i + EPISODE_ROWS))
  }
  return pages
}
