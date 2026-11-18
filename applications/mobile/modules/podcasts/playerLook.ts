// LOFI-FORK: the podcasts section's full-screen player (see FORK.md).
//
// The small calculations behind the player's look: the background colour taken from a
// show's artwork, and the seek bar's positions. Pure, so they are tested without a screen.
import { type SFSymbol } from "sf-symbols-typescript"

/** The player's background when a show has no artwork colour: the app's dark theme colour. */
export const PLAYER_FALLBACK_BACKGROUND = "#0a0a0a"

/** The darkest the brightness (0 to 1) of the tint may be, so white text stays readable. */
const MAX_BRIGHTNESS = 0.32

function channels(hex: string): [number, number, number] | null {
  const match = /^#?([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})$/i.exec(hex.trim())
  if (!match) return null
  return [
    parseInt(match[1] ?? "0", 16),
    parseInt(match[2] ?? "0", 16),
    parseInt(match[3] ?? "0", 16),
  ]
}

function hex(value: number): string {
  return Math.round(Math.min(255, Math.max(0, value)))
    .toString(16)
    .padStart(2, "0")
}

/**
 * The player's background for an artwork colour ("#rrggbb"): the same colour, darkened
 * until white text reads well on it. Without a usable colour, the dark theme colour.
 */
export function playerBackground(color: string | null): string {
  const rgb = color ? channels(color) : null
  if (!rgb) return PLAYER_FALLBACK_BACKGROUND
  const [r, g, b] = rgb
  const brightness = (0.299 * r + 0.587 * g + 0.114 * b) / 255
  const scale = brightness > MAX_BRIGHTNESS ? MAX_BRIGHTNESS / brightness : 1
  return `#${hex(r * scale)}${hex(g * scale)}${hex(b * scale)}`
}

/**
 * How far along the bar a touch is, from 0 to 1. The seek bar's gesture callbacks call this on
 * the UI thread, so it is a worklet (it may use only its arguments and globals).
 */
export function barFraction(x: number, width: number): number {
  "worklet"
  if (!(width > 0) || !Number.isFinite(x)) return 0
  return Math.min(1, Math.max(0, x / width))
}

/** The place in the episode a fraction of the bar stands for. */
export function positionAt(fraction: number, duration: number | null): number {
  if (duration === null || !(duration > 0)) return 0
  return Math.min(1, Math.max(0, fraction)) * duration
}

/** How full the bar is, from 0 to 1 (empty while the length is unknown). */
export function progressFraction(
  position: number,
  duration: number | null,
): number {
  if (duration === null || !(duration > 0)) return 0
  return Math.min(1, Math.max(0, position / duration))
}

/** The skip lengths that have a numbered SF Symbol ("gobackward.15"). */
const NUMBERED_SKIPS = [5, 10, 15, 30, 45, 60, 75, 90]

/** The SF Symbol for a skip button: the numbered one when there is one, else the plain arrow. */
export function skipSymbol(
  direction: "back" | "ahead",
  seconds: number,
): SFSymbol {
  const base = direction === "back" ? "gobackward" : "goforward"
  return (
    NUMBERED_SKIPS.includes(seconds) ? `${base}.${seconds}` : base
  ) as SFSymbol
}
