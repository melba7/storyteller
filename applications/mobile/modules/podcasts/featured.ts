// LOFI-FORK: the podcasts section's New tab rules (see FORK.md).
import { type ForYouSuggestion } from "./categories"
import { type ChartShow } from "./charts"

/** How many of the top chart become featured cards. */
export const FEATURED_TOP = 5

/** One featured card: a grey caps label over the show it presents. */
export type FeaturedCard = { label: string; show: ChartShow }

/**
 * The cards of New's paging row: the first top shows ("TOP SHOW"), then the first show of
 * each "For you" suggestion labelled with its category. A show appears once.
 */
export function featuredCards(
  top: readonly ChartShow[],
  suggestions: readonly ForYouSuggestion[],
): FeaturedCard[] {
  const cards: FeaturedCard[] = top
    .slice(0, FEATURED_TOP)
    .map((show) => ({ label: "TOP SHOW", show }))
  const seen = new Set(cards.map((card) => card.show.appleId))
  for (const suggestion of suggestions) {
    const show = suggestion.shows.find((s) => !seen.has(s.appleId))
    if (!show) continue
    seen.add(show.appleId)
    cards.push({ label: suggestion.category.name.toUpperCase(), show })
  }
  return cards
}

/** Room kept at the left of the row, between the cards and for the next card's peek, in points. */
const GUTTER = 16
const GAP = 12
const PEEK = 28

/** The side of a featured card: the window minus the gutter, the gap and the peek; at least 1. */
export function featuredCardSize(windowWidth: number): number {
  return Math.max(1, windowWidth - GUTTER - GAP - PEEK)
}
