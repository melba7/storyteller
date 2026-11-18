// LOFI-FORK: the podcasts section's chart list plan (see FORK.md).
import { describe, expect, it } from "vitest"

import type { FollowedShow } from "./categories"
import { POPULAR_ORDER, planChartLists } from "./chartLists"
import { CHART_CATEGORIES, TOP_CHART } from "./charts"
import { LOCAL_FEED_URL } from "./localFiles"

function show(title: string, categories: string[]): FollowedShow {
  return { title, feedUrl: `https://feeds.test/${title}`, categories }
}

const titles = (lists: { title: string }[]) => lists.map((l) => l.title)

describe("planChartLists", () => {
  it("with nothing followed gives Top Shows then the popular eight for Home", () => {
    expect(titles(planChartLists([], "home"))).toEqual([
      "Top Shows",
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
    expect(titles(lists).slice(0, 3)).toEqual([
      "Top Shows",
      "Top in Science",
      "Top in History",
    ])
    expect(lists).toHaveLength(9)
    expect(new Set(lists.map((l) => l.id)).size).toBe(9)
  })

  it("ignores Your files", () => {
    const plain = planChartLists([], "home")
    const files = [
      { title: "Local", feedUrl: LOCAL_FEED_URL, categories: ["Science"] },
    ]
    expect(planChartLists(files, "home")).toEqual(plain)
  })

  it("gives New Top Shows and all nineteen categories", () => {
    const lists = planChartLists([show("A", ["Music"])], "new")
    expect(lists).toHaveLength(1 + 19)
    expect(lists[1]!.title).toBe("Top in Music")
    expect(new Set(lists.map((l) => l.id)).size).toBe(20)
  })

  it("uses only known category ids and a shelf of 20", () => {
    const known = new Set(CHART_CATEGORIES.map((c) => c.id))
    expect([...POPULAR_ORDER].sort()).toEqual([...known].sort())
    for (const list of planChartLists([], "new")) {
      expect(list.shelf).toBe(20)
      if (list.id !== TOP_CHART) expect(known.has(list.id)).toBe(true)
    }
  })

  it("leaves out the ids in omit and keeps the order", () => {
    const lists = planChartLists([], "home", [TOP_CHART, "1303"])
    expect(titles(lists).slice(0, 3)).toEqual([
      "Top in News",
      "Top in True Crime",
      "Top in Society & Culture",
    ])
    expect(lists).toHaveLength(7)
  })
})
