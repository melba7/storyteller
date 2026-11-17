// LOFI-FORK: the podcasts section's full-screen player (see FORK.md).
//
// The player's gradient from a show's artwork colour. The measured colour is often greyish,
// so `vivid` lifts its saturation first; `playerBackground` then keeps it dark enough for
// white text, and the gradient's bottom is darker still.
import { playerBackground } from "./playerLook"

/** A colour with some hue is raised to at least this saturation (0 to 1). */
const MIN_SATURATION = 0.5
/** Below this saturation a colour counts as grey and keeps its look. */
const GREY = 0.08
/** The bottom of the gradient is the top at this share of its brightness. */
const BOTTOM_SHARE = 0.55
/** White text needs this much contrast on both ends (WCAG AA, with a little room). */
const MIN_CONTRAST = 4.6

type Rgb = [number, number, number]

function parse(color: string): Rgb | null {
  const match = /^#?([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})$/i.exec(
    color.trim(),
  )
  if (!match) return null
  return [
    parseInt(match[1] ?? "0", 16),
    parseInt(match[2] ?? "0", 16),
    parseInt(match[3] ?? "0", 16),
  ]
}

function toHex([r, g, b]: Rgb): string {
  const part = (value: number) =>
    Math.round(Math.min(255, Math.max(0, value)))
      .toString(16)
      .padStart(2, "0")
  return `#${part(r)}${part(g)}${part(b)}`
}

/**
 * The colour with its saturation raised to at least a half, brightness and hue kept. Greys,
 * white and black stay as they are, and so does anything that isn't a "#rrggbb" colour.
 */
export function vivid(color: string): string {
  const rgb = parse(color)
  if (!rgb) return color
  const max = Math.max(...rgb)
  const min = Math.min(...rgb)
  const saturation = max === 0 ? 0 : (max - min) / max
  if (saturation < GREY || saturation >= MIN_SATURATION) return color
  // Pull the dimmer channels towards the darkest one's side so the ratio grows.
  const newMin = max * (1 - MIN_SATURATION)
  const scale = (max - newMin) / (max - min)
  return toHex(rgb.map((value) => max - (max - value) * scale) as Rgb)
}

/** The WCAG contrast of white text on a "#rrggbb" colour (21 on black; 1 on white). */
export function contrastWithWhite(color: string): number {
  const rgb = parse(color) ?? [0, 0, 0]
  const [r, g, b] = rgb.map((value) => {
    const unit = value / 255
    return unit <= 0.03928 ? unit / 12.92 : ((unit + 0.055) / 1.055) ** 2.4
  }) as Rgb
  const luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
  return 1.05 / (luminance + 0.05)
}

function darken(color: string, share: number): string {
  const rgb = parse(color)
  return rgb ? toHex(rgb.map((value) => value * share) as Rgb) : color
}

/** The top and the bottom of the player's gradient, both readable under white text. */
export function gradientEnds(color: string | null): [string, string] {
  let top = playerBackground(color === null ? null : vivid(color))
  // The brightness cap alone leaves greens close to the limit, so darken until it holds.
  while (contrastWithWhite(top) < MIN_CONTRAST) top = darken(top, 0.95)
  return [top, darken(top, BOTTOM_SHARE)]
}

/** The `backgroundImage` style for the player: the artwork colour fading to a darker one. */
export function playerGradient(color: string | null): string {
  const [top, bottom] = gradientEnds(color)
  return `linear-gradient(180deg, ${top}, ${bottom})`
}
