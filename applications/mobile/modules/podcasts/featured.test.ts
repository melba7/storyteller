// LOFI-FORK: the podcasts section's New tab rules (see FORK.md).
import { describe, expect, it } from "vitest"

import { type ChartShow } from "./charts"
import { FEATURED_TOP, featuredCards } from "./featured"

const show = (n: number): ChartShow => ({
  appleId: String(n),
  title: `Show ${n}`,
  author: "A",
  feedUrl: `https://feeds.test/${n}`,
  imageUrl: null,
})
const chart = (count: number) =>
  Array.from({ length: count }, (_, i) => show(i + 1))

describe("featuredCards", () => {
  it("takes the first top shows, labelled TOP SHOW", () => {
    const cards = featuredCards(chart(20), [])
    expect(cards).toHaveLength(FEATURED_TOP)
    expect(cards[0]).toMatchObject({ label: "TOP SHOW", show: show(1) })
  })

  it("adds one card per suggestion, labelled with its category in capitals", () => {
    const cards = featuredCards(chart(20), [
      {
        category: { id: "1533", name: "Science" },
        because: "X",
        shows: [show(30), show(31)],
      },
    ])
    expect(cards.at(-1)).toMatchObject({ label: "SCIENCE", show: show(30) })
  })

  it("never shows the same show twice", () => {
    const cards = featuredCards(chart(3), [
      {
        category: { id: "1533", name: "Science" },
        because: "X",
        shows: [show(1), show(2)],
      },
    ])
    expect(new Set(cards.map((c) => c.show.appleId)).size).toBe(cards.length)
  })

  it("is empty with no chart", () => {
    expect(featuredCards([], [])).toEqual([])
  })
})
