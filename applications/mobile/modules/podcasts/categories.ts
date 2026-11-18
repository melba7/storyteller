// LOFI-FORK: the podcasts section's "For you" rules (see FORK.md).
//
// Pure functions. Apple has no "shows like this" list, so suggestions go by category: the
// categories of the shows you follow, most common first, each with that category's chart.
import { CHART_CATEGORIES, type ChartCategory, type ChartShow } from "./charts"
import { feedShows } from "./localFiles"

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
  // Counted by the chart category, so "comedy" and "Comedy" are one.
  const counts = new Map<
    string,
    { category: ChartCategory; count: number; because: string }
  >()
  for (const show of feedShows(followed)) {
    const seen = new Set<string>()
    for (const name of topLevelNames(show.categories)) {
      const category = chartCategoryFor(name)
      if (!category || seen.has(category.id)) continue
      seen.add(category.id)
      const found = counts.get(category.id)
      if (found) found.count += 1
      else counts.set(category.id, { category, count: 1, because: show.title })
    }
  }
  const picks: (ForYouPick & { count: number })[] = [...counts.values()]
  picks.sort(
    (a, b) =>
      b.count - a.count || a.category.name.localeCompare(b.category.name),
  )
  return picks
    .slice(0, limit)
    .map(({ category, because }) => ({ category, because }))
}

/**
 * A short text of what "For you" depends on: the picked categories and the followed feed
 * links. A page keys its loading on it, so a library change that touches neither (a played
 * episode saving its place) does not start the suggestions over.
 */
export function forYouKey(
  picks: readonly ForYouPick[],
  followed: readonly FollowedShow[],
): string {
  const feeds = followed.map((show) => show.feedUrl).sort()
  return `${picks.map((pick) => pick.category.id).join(",")}|${feeds.join(",")}`
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

/**
 * The category ids New's chart lists leave out because "For You" already shows them. While
 * For You loads that is every pick, so the planned lists stay the same; once it has loaded it
 * is only the categories it drew, so a pick whose chart failed still gets its "Top in ..."
 * list.
 */
export function forYouOmit(
  picks: ForYouPick[],
  drawn: ForYouSuggestion[],
  loaded: boolean,
): string[] {
  const shown = loaded ? drawn : picks
  return shown.map((pick) => pick.category.id)
}
