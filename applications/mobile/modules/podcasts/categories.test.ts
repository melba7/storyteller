// LOFI-FORK: the podcasts section's "For you" rules (see FORK.md).
import { describe, expect, it } from "vitest"

import {
  type FollowedShow,
  buildForYou,
  chartCategoryFor,
  isFollowed,
  pickForYou,
  topLevelNames,
} from "./categories"
import { type ChartShow } from "./charts"

function followed(
  title: string,
  categories: string[],
  feedUrl = `https://feeds.test/${title}`,
): FollowedShow {
  return { title, feedUrl, categories }
}

function chartShow(
  title: string,
  feedUrl = `https://charts.test/${title}`,
): ChartShow {
  return { appleId: title, title, author: "", feedUrl, imageUrl: null }
}

describe("topLevelNames", () => {
  it("keeps each top-level name once and reads subcategories as their top", () => {
    expect(
      topLevelNames([
        "Business",
        "Business › Investing",
        "Comedy",
        "Tech › AI",
      ]),
    ).toEqual(["Business", "Comedy", "Tech"])
    expect(topLevelNames([])).toEqual([])
  })
})

describe("chartCategoryFor", () => {
  it("finds Apple's category by name, ignoring case", () => {
    expect(chartCategoryFor("health & fitness")?.id).toBe("1512")
    expect(chartCategoryFor("Government")?.id).toBe("1511")
    expect(chartCategoryFor("Gardening")).toBeNull()
  })
})

describe("pickForYou", () => {
  it("puts the most common categories first and stops at three", () => {
    const picks = pickForYou([
      followed("A", ["Comedy", "News"]),
      followed("B", ["News", "Comedy", "Sports"]),
      followed("C", ["News", "Technology"]),
      followed("D", ["History"]),
    ])
    expect(picks.map((p) => p.category.name)).toEqual([
      "News",
      "Comedy",
      "History",
    ])
  })

  it("breaks ties by name, and names the first followed show in the category", () => {
    const picks = pickForYou([
      followed("Zed", ["Science", "Arts"]),
      followed("Amy", ["Arts"]),
      followed("Bo", ["Science"]),
    ])
    expect(picks.map((p) => [p.category.name, p.because])).toEqual([
      ["Arts", "Zed"],
      ["Science", "Zed"],
    ])
  })

  it("counts a show once for a category even with subcategories", () => {
    const picks = pickForYou([
      followed("A", ["Business", "Business › Investing", "Business › Careers"]),
      followed("B", ["Comedy"]),
      followed("C", ["Comedy"]),
    ])
    expect(picks.map((p) => p.category.name)).toEqual(["Comedy", "Business"])
  })

  it("skips categories Apple has no chart for, and gives nothing without categories", () => {
    const picks = pickForYou([
      followed("A", ["Gardening"]),
      followed("B", ["Gardening", "Music"]),
    ])
    expect(picks.map((p) => p.category.name)).toEqual(["Music"])
    expect(pickForYou([followed("A", [])])).toEqual([])
    expect(pickForYou([])).toEqual([])
  })
})

describe("isFollowed", () => {
  const mine = [followed("The Daily", [], "https://Feeds.example.com/daily/")]

  it("matches by feed link, ignoring scheme, case and a trailing slash", () => {
    expect(
      isFollowed(chartShow("Other", "http://feeds.example.com/daily"), mine),
    ).toBe(true)
  })

  it("matches by title, ignoring case", () => {
    expect(isFollowed(chartShow("the daily "), mine)).toBe(true)
  })

  it("does not match a different show", () => {
    expect(isFollowed(chartShow("Planet Money"), mine)).toBe(false)
  })
})

describe("buildForYou", () => {
  const mine = [
    followed("My Money Show", ["Business"], "https://feeds.test/money"),
    followed("My Jokes", ["Comedy"]),
  ]
  const picks = pickForYou(mine)
  const charts = new Map([
    [
      "1321",
      [
        chartShow("Planet Money"),
        chartShow("Same Feed", "https://feeds.test/money"),
        chartShow("Acquired"),
      ],
    ],
    ["1303", [chartShow("my jokes")]],
  ])

  it("leaves out followed shows and says which show each comes from", () => {
    const result = buildForYou(picks, charts, mine)
    expect(result).toHaveLength(1)
    expect(result[0]?.category.name).toBe("Business")
    expect(result[0]?.because).toBe("My Money Show")
    expect(result[0]?.shows.map((s) => s.title)).toEqual([
      "Planet Money",
      "Acquired",
    ])
  })

  it("leaves out a category whose chart is missing or all followed", () => {
    expect(buildForYou(picks, new Map(), mine)).toEqual([])
  })

  it("keeps at most the number asked for", () => {
    const result = buildForYou(picks, charts, mine, 1)
    expect(result[0]?.shows).toHaveLength(1)
  })
})
