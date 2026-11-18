// LOFI-FORK: the podcasts section's full-screen player (see FORK.md).
//
// The small calculations behind the player sheet in Apple's look: the sheet takes the
// artwork's colour, its text picks white or black from that colour, and a long title fades
// out at the right edge. Pure, so they are tested without a screen.
import { blendOver, contrastBetween, luminanceOf, vivid } from "./artworkTint"
import { PLAYER_FALLBACK_BACKGROUND } from "./playerLook"

const WHITE = "#ffffff"
const BLACK = "#000000"
/** The bottom of the sheet's gradient is the top at this share of its brightness. */
const BOTTOM_SHARE = 0.8

export interface SheetColors {
  top: string
  bottom: string
  /** The colour about two thirds down, where a title's fade ends. */
  mid: string
  /** The main text and controls: white or black. */
  ink: typeof WHITE | typeof BLACK
  /** The date and show name, and the times: the ink softened into the sheet's colour. */
  tint: string
  muted: string
  /** The scrubber: the played part, and the rest of the bar. */
  fill: string
  rest: string
}

function usable(color: string | null): color is string {
  return color !== null && /^#?[0-9a-f]{6}$/i.test(color.trim())
}

function withHash(color: string): string {
  const plain = color.trim()
  return plain.startsWith("#") ? plain : `#${plain}`
}

/** White or black, whichever reads better on this "#rrggbb" colour. */
export function inkFor(background: string): typeof WHITE | typeof BLACK {
  return contrastBetween(background, WHITE) >=
    contrastBetween(background, BLACK)
    ? WHITE
    : BLACK
}

function darkenBy(color: string, share: number): string {
  return blendOver(BLACK, color, 1 - share)
}

/** Everything the sheet draws with, from the show's artwork colour (null: the dark fallback). */
export function sheetColors(color: string | null): SheetColors {
  const top = usable(color)
    ? vivid(withHash(color))
    : PLAYER_FALLBACK_BACKGROUND
  const bottom = darkenBy(top, BOTTOM_SHARE)
  const ink = inkFor(top)
  return {
    top,
    bottom,
    mid: blendOver(bottom, top, 0.6),
    ink,
    tint: blendOver(ink, top, 0.6),
    muted: blendOver(ink, top, 0.45),
    fill: blendOver(ink, top, 0.55),
    rest: blendOver(ink, top, 0.2),
  }
}

/** Whether the sheet's colour is light, so its text is black. */
export function isLightSheet(color: string | null): boolean {
  return sheetColors(color).ink === BLACK
}

/** How bright a "#rrggbb" colour is, from 0 to 1 (re-exported for the screens). */
export const brightness = luminanceOf

/**
 * The CSS gradient laid over the title's right edge: from clear to the sheet's colour, so a
 * long title fades out instead of ending in "...". `background` is a "#rrggbb" colour.
 */
export function titleFade(background: string): string {
  const match = /^#?([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})$/i.exec(
    background.trim(),
  )
  if (!match) return "none"
  const [r, g, b] = [match[1], match[2], match[3]].map((part) =>
    parseInt(part ?? "0", 16),
  )
  return `linear-gradient(90deg, rgba(${r},${g},${b},0), rgb(${r},${g},${b}))`
}

const MONTHS = [
  "January",
  "February",
  "March",
  "April",
  "May",
  "June",
  "July",
  "August",
  "September",
  "October",
  "November",
  "December",
]

/**
 * The episode's date as the player says it: "November 12", with the year when it is not this
 * year. Empty when the feed gave no date.
 */
export function dateWords(
  publishedAt: number | null,
  now: number = Date.now(),
): string {
  if (publishedAt === null || !Number.isFinite(publishedAt)) return ""
  const date = new Date(publishedAt)
  const day = `${MONTHS[date.getMonth()]} ${date.getDate()}`
  return date.getFullYear() === new Date(now).getFullYear()
    ? day
    : `${day}, ${date.getFullYear()}`
}

/** "12m left", "1h 5m left"; empty when nothing is left or the length is not known. */
export function leftWords(position: number, duration: number | null): string {
  if (duration === null || !Number.isFinite(duration) || duration <= 0)
    return ""
  const minutes = Math.ceil(Math.max(0, duration - position) / 60)
  if (minutes <= 0) return ""
  const hours = Math.floor(minutes / 60)
  const rest = minutes % 60
  if (hours === 0) return `${minutes}m left`
  return rest === 0 ? `${hours}h left` : `${hours}h ${rest}m left`
}

/** The mini player's second line: the episode's date, as in Apple Podcasts, else nothing. */
export function miniSubtitle(
  publishedAt: number | null,
  now: number = Date.now(),
): string {
  return dateWords(publishedAt, now)
}
