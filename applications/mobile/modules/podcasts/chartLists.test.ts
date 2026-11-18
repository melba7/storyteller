// LOFI-FORK: the podcasts section's chart list plan (see FORK.md).
import { describe, expect, it } from "vitest"

import type { FollowedShow } from "./categories"
import { POPULAR_ORDER, planChartLists } from "./chartLists"
import { CHART_CATEGORIES, TOP_CHART } from "./charts"
import { LOCAL_FEED_URL } from "./localFiles"
import { EPISODES_CHART } from "./topEpisodes"

function show(title: string, categories: string[]): FollowedShow {
  return { title, feedUrl: `https://feeds.test/${title}`, categories }
}

const titles = (lists: { title: string }[]) => lists.map((l) => l.title)

describe("planChartLists", () => {
  it("with nothing followed gives Top Shows then the popular eight for Home", () => {
    expect(titles(planChartLists([], "home"))).toEqual([
      "Top Shows",
      "Top Episodes",
      "Top in News",
      "Top in Comedy",
      "Top in True Crime",
      "Top in Society & Culture",
      "Top in Business",
      "Top in Sports",
      "Top in Health & Fitness",
      "Top in Technology",
    ])
  })

  it("puts followed categories first, most common first, with no repeats", () => {
    const followed = [
      show("A", ["Science"]),
      show("B", ["Science"]),
      show("C", ["History"]),
    ]
    const lists = planChartLists(followed, "home")
    expect(titles(lists).slice(0, 4)).toEqual([
      "Top Shows",
      "Top Episodes",
      "Top in Science",
      "Top in History",
    ])
    expect(lists).toHaveLength(10)
    expect(new Set(lists.map((l) => l.id)).size).toBe(10)
  })

  it("ignores Your files", () => {
    const plain = planChartLists([], "home")
    const files = [
      { title: "Local", feedUrl: LOCAL_FEED_URL, categories: ["Science"] },
    ]
    expect(planChartLists(files, "home")).toEqual(plain)
  })

  it("gives New Top Shows, Top Episodes and all nineteen categories", () => {
    const lists = planChartLists([show("A", ["Music"])], "new")
    expect(lists).toHaveLength(2 + 19)
    expect(lists[2]!.title).toBe("Top in Music")
    expect(new Set(lists.map((l) => l.id)).size).toBe(21)
  })

  it("uses only known category ids and a shelf of 20 (30 for episodes)", () => {
    const known = new Set(CHART_CATEGORIES.map((c) => c.id))
    expect([...POPULAR_ORDER].sort()).toEqual([...known].sort())
    for (const list of planChartLists([], "new")) {
      if (list.kind === "episodes") {
        expect(list.shelf).toBe(30)
        continue
      }
      expect(list.shelf).toBe(20)
      if (list.id !== TOP_CHART) expect(known.has(list.id)).toBe(true)
    }
  })

  it("marks only Top Episodes as the episodes kind", () => {
    const lists = planChartLists([], "home")
    expect(lists.filter((l) => l.kind === "episodes").map((l) => l.id)).toEqual(
      [EPISODES_CHART],
    )
  })

  it("puts Top Episodes first on New once Top Shows is left out", () => {
    const lists = planChartLists([], "new", [TOP_CHART])
    expect(titles(lists).slice(0, 2)).toEqual(["Top Episodes", "Top in News"])
  })

  it("leaves out the ids in omit and keeps the order", () => {
    const lists = planChartLists([], "home", [TOP_CHART, "1303"])
    expect(titles(lists).slice(0, 4)).toEqual([
      "Top Episodes",
      "Top in News",
      "Top in True Crime",
      "Top in Society & Culture",
    ])
    expect(lists).toHaveLength(8)
  })
})
