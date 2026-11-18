import { type FollowedShow, pickForYou } from "./categories"
// LOFI-FORK: which chart lists a podcasts page shows, and in what order (see FORK.md).
//
// Pure functions. Home and New ask the same planner, so they can't drift apart.
import { CHART_CATEGORIES, TOP_CHART } from "./charts"

export type ChartListPage = "home" | "new"

/** One list on a page: its chart id, its heading and how many shows its shelf draws. */
export type ChartListPlan = { id: string; title: string; shelf: number }

/** How many shows a shelf draws (the "See All" page has all 50). */
export const SHELF_SIZE = 20

/** How many categories Home shows; New shows all of them. */
export const HOME_CATEGORIES = 8

/** How many followed categories go first. */
const FOLLOWED_FIRST = 4

/** The categories in the order of how many people listen, as chart ids (not names). */
export const POPULAR_ORDER: readonly string[] = [
  "1489", // News
  "1303", // Comedy
  "1488", // True Crime
  "1324", // Society & Culture
  "1321", // Business
  "1545", // Sports
  "1512", // Health & Fitness
  "1318", // Technology
  "1487", // History
  "1533", // Science
  "1309", // TV & Film
  "1304", // Education
  "1301", // Arts
  "1305", // Kids & Family
  "1483", // Fiction
  "1314", // Religion & Spirituality
  "1310", // Music
  "1502", // Leisure
  "1511", // Government
]

/**
 * The lists for a page: "Top Shows", then "Top in <name>" for the categories of the
 * followed shows (most common first, up to four), then the popularity order, no repeats.
 * `omit` leaves chart ids out and keeps the order of the rest.
 */
export function planChartLists(
  followed: FollowedShow[],
  page: ChartListPage,
  omit: readonly string[] = [],
): ChartListPlan[] {
  const names = new Map(CHART_CATEGORIES.map((c) => [c.id, c.name]))
  const ids: string[] = pickForYou(followed, FOLLOWED_FIRST).map(
    (pick) => pick.category.id,
  )
  for (const id of POPULAR_ORDER) if (!ids.includes(id)) ids.push(id)
  const categories = page === "home" ? ids.slice(0, HOME_CATEGORIES) : ids

  const lists: ChartListPlan[] = [
    { id: TOP_CHART, title: "Top Shows", shelf: SHELF_SIZE },
  ]
  for (const id of categories) {
    lists.push({
      id,
      title: `Top in ${names.get(id) ?? id}`,
      shelf: SHELF_SIZE,
    })
  }
  return lists.filter((list) => !omit.includes(list.id))
}
