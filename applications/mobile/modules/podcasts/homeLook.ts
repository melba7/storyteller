// LOFI-FORK: the podcasts section's Home (see FORK.md).
//
// Pure rules for how Home's cards and shelves read: the line over a card's title, the time
// left, the description without markup, the card's colours and how often a show updates.
import { blendOver, contrastBetween, vivid } from "./artworkTint"
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

/**
 * "Updated Daily", "Weekly", "Biweekly" or "Monthly", from the median gap between a show's
 * newest episodes (the six newest are read). Empty with fewer than three dates, or when the
 * gap fits none of them.
 */
export function updateCadence(dates: readonly number[]): string {
  const newest = [...dates].sort((a, b) => b - a).slice(0, 6)
  if (newest.length < 3) return ""
  const gaps = newest
    .slice(1)
    .map((date, i) => ((newest[i] ?? date) - date) / DAY)
    .sort((a, b) => a - b)
  const middle = Math.floor(gaps.length / 2)
  const median =
    gaps.length % 2 === 1
      ? (gaps[middle] ?? 0)
      : ((gaps[middle - 1] ?? 0) + (gaps[middle] ?? 0)) / 2
  if (median <= 2.5) return "Updated Daily"
  if (median <= 9) return "Updated Weekly"
  if (median <= 18) return "Updated Biweekly"
  if (median <= 45) return "Updated Monthly"
  return ""
}

/** The bold line under a Top Shows tile: the show's first category, else its title. */
export function topShowCaption(show: Pick<Show, "categories" | "title">) {
  return topLevelNames(show.categories)[0] ?? show.title
}
