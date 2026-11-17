// LOFI-FORK: the podcasts section's "For you" rules (see FORK.md).
//
// Pure functions. Apple has no "shows like this" list, so suggestions go by category: the
// categories of the shows you follow, most common first, each with that category's chart.
import { CHART_CATEGORIES, type ChartCategory, type ChartShow } from "./charts"

/** What "For you" needs to know about a followed show. */
export type FollowedShow = {
  title: string
  feedUrl: string
  categories: string[]
}

export type ForYouPick = {
  category: ChartCategory
  /** The title of one followed show in this category. */
  because: string
}

export type ForYouSuggestion = ForYouPick & { shows: ChartShow[] }

const SUB_SEPARATOR = " › "

/** The top-level names of a show's categories, each once ("Business › Investing" is Business). */
export function topLevelNames(categories: string[]): string[] {
  const names: string[] = []
  for (const category of categories) {
    const top = (category.split(SUB_SEPARATOR)[0] ?? "").trim()
    if (top !== "" && !names.includes(top)) names.push(top)
  }
  return names
}

/** Apple's chart category with this feed category name, ignoring case and spacing. */
export function chartCategoryFor(name: string): ChartCategory | null {
  const wanted = name.trim().toLowerCase()
  return CHART_CATEGORIES.find((c) => c.name.toLowerCase() === wanted) ?? null
}

/**
 * The categories to suggest from: followed shows' top-level categories, most common first
 * (ties by name), only those Apple has a chart for, at most `limit`. Each carries the
 * first followed show (in the order given) that has it.
 */
export function pickForYou(followed: FollowedShow[], limit = 3): ForYouPick[] {
  const counts = new Map<string, { count: number; because: string }>()
  for (const show of followed) {
    for (const name of topLevelNames(show.categories)) {
      const found = counts.get(name)
      if (found) found.count += 1
      else counts.set(name, { count: 1, because: show.title })
    }
  }
  const picks: (ForYouPick & { count: number })[] = []
  for (const [name, { count, because }] of counts) {
    const category = chartCategoryFor(name)
    if (category) picks.push({ category, because, count })
  }
  picks.sort(
    (a, b) =>
      b.count - a.count || a.category.name.localeCompare(b.category.name),
  )
  return picks
    .slice(0, limit)
    .map(({ category, because }) => ({ category, because }))
}

function titleKey(title: string): string {
  return title.trim().toLowerCase()
}

function feedKey(url: string): string {
  return url
    .trim()
    .toLowerCase()
    .replace(/^https?:\/\//, "")
    .replace(/\/+$/, "")
}

/** True when a chart show is one of the followed shows, by feed link or by title. */
export function isFollowed(show: ChartShow, followed: FollowedShow[]): boolean {
  const feed = feedKey(show.feedUrl)
  const title = titleKey(show.title)
  return followed.some(
    (f) => feedKey(f.feedUrl) === feed || titleKey(f.title) === title,
  )
}

/**
 * Each pick with its category's chart minus the shows already followed, at most
 * `perCategory` of them. A pick whose chart isn't there, or ends up empty, is left out.
 */
export function buildForYou(
  picks: ForYouPick[],
  charts: Map<string, ChartShow[]>,
  followed: FollowedShow[],
  perCategory = 12,
): ForYouSuggestion[] {
  const suggestions: ForYouSuggestion[] = []
  for (const pick of picks) {
    const shows = (charts.get(pick.category.id) ?? [])
      .filter((show) => !isFollowed(show, followed))
      .slice(0, perCategory)
    if (shows.length > 0) suggestions.push({ ...pick, shows })
  }
  return suggestions
}
