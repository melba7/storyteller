// LOFI-FORK: the podcasts section's show page wash (see FORK.md).
//
// The soft colour from a show's artwork behind the top of its page and its episode card. It is
// as strong as the theme's text allows: the wash is laid over the page, and the text must
// stay readable on the blend.
import { blendOver, contrastBetween } from "./artworkTint"

/** The weakest and the strongest wash (opacity of the artwork colour). */
export const WASH_MIN = 0.15
export const WASH_MAX = 0.45
/** Text must reach this contrast on the blend (WCAG AA). */
const MIN_CONTRAST = 4.5
const STEP = 0.01
const HEX = /^#[0-9a-f]{6}$/i

/**
 * The strongest alpha from 0.15 to 0.45 that keeps `foreground` at 4.5:1 over `color` laid on
 * `background`. When even the weakest wash can't hold it (or the colour can't be read) it is
 * 0.15. All three are "#rrggbb".
 */
export function headerWash(
  color: string,
  background: string,
  foreground: string,
): number {
  if (!HEX.test(color)) return WASH_MIN
  // Whole hundredths, so 0.15 + 0.01 * n has no drift.
  for (
    let hundredths = WASH_MAX * 100;
    hundredths > WASH_MIN * 100;
    hundredths--
  ) {
    const alpha = hundredths * STEP
    const blended = blendOver(color, background, alpha)
    if (contrastBetween(foreground, blended) >= MIN_CONTRAST) return alpha
  }
  return WASH_MIN
}

/**
 * The style of the wash's view: a gradient from the colour laid over the page at `alpha` down
 * to the page colour, so it fades into the page. Both ends are solid, so the plain
 * `backgroundColor` (the colour at half that alpha) shows only where the gradient can't be
 * drawn. A colour it can't read gives just the page colour.
 */
export function washStyle(
  color: string,
  alpha: number,
  background: string,
): { backgroundImage?: string; backgroundColor: string } {
  if (!HEX.test(color)) return { backgroundColor: background }
  return {
    backgroundImage: `linear-gradient(180deg, ${blendOver(color, background, alpha)}, ${background})`,
    backgroundColor: blendOver(color, background, alpha / 2),
  }
}
