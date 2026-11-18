// LOFI-FORK: the podcasts section's feed refresh (see FORK.md).
import { describe, expect, it } from "vitest"

import { feedChanged } from "./feedChanges"
import type { PodcastFeedData } from "./index"
import { type Show, showFromRow } from "./library"
import { fundingFromJson, peopleFromJson, toJson } from "./people"
import { DEFAULT_SHOW_SETTINGS } from "./showSettings"

const ann = { name: "Ann", role: "host", group: "cast", img: null, href: null }
const tip = { url: "https://x.test/tip", label: "Tip jar" }

function stored(overrides: Partial<Show> = {}): Show {
  return {
    id: "s1",
    feedUrl: "https://example.com/rss",
    title: "Show",
    author: "Bo",
    description: "About the show.",
    imageUrl: "https://example.com/a.jpg",
    link: "https://example.com",
    language: "en",
    addedAt: 1,
    refreshedAt: 1,
    artworkColor: null,
    ownPosition: null,
    categories: ["Comedy", "Comedy › Improv"],
    funding: [tip],
    people: [ann],
    settings: DEFAULT_SHOW_SETTINGS,
    ...overrides,
  }
}

function feed(overrides: Partial<PodcastFeedData> = {}): PodcastFeedData {
  return {
    title: "Show",
    author: "Bo",
    description: "About the show.",
    imageUrl: "https://example.com/a.jpg",
    link: "https://example.com",
    language: "en",
    categories: ["Comedy", "Comedy › Improv"],
    funding: [tip],
    people: [ann],
    episodes: [],
    ...overrides,
  }
}

/** The feed with these optional values missing, as a feed that does not have them. */
function feedWithout(...keys: (keyof PodcastFeedData)[]): PodcastFeedData {
  const full = feed()
  for (const key of keys) delete full[key]
  return full
}

const none = { inserted: 0, updated: 0 }

describe("feedChanged", () => {
  it("a feed with nothing new tells no screen", () => {
    expect(feedChanged(stored(), feed(), none)).toBe(false)
  })

  it("a new or a changed episode is a change", () => {
    expect(feedChanged(stored(), feed(), { inserted: 1, updated: 0 })).toBe(
      true,
    )
    expect(feedChanged(stored(), feed(), { inserted: 0, updated: 1 })).toBe(
      true,
    )
  })

  it.each([
    ["title", { title: "Show, renamed" }],
    ["author", { author: "Cy" }],
    ["description", { description: "Something else." }],
    ["picture", { imageUrl: "https://example.com/b.jpg" }],
    ["link", { link: "https://example.com/new" }],
    ["language", { language: "de" }],
    ["categories", { categories: ["Comedy"] }],
    ["funding", { funding: [] }],
    ["people", { people: [{ ...ann, name: "Ann Lee" }] }],
  ] satisfies [string, Partial<PodcastFeedData>][])(
    "a changed %s is a change",
    (_field, change) => {
      expect(feedChanged(stored(), feed(change), none)).toBe(true)
    },
  )

  it("a value the feed lost is a change", () => {
    expect(feedChanged(stored(), feed({ author: null }), none)).toBe(true)
    expect(feedChanged(stored(), feedWithout("imageUrl"), none)).toBe(true)
    expect(feedChanged(stored(), feedWithout("people"), none)).toBe(true)
  })

  it("no author stored and none in the feed is no change", () => {
    expect(
      feedChanged(
        stored({ author: null, link: null, language: null, imageUrl: null }),
        feedWithout("author", "link", "language", "imageUrl"),
        none,
      ),
    ).toBe(false)
    expect(
      feedChanged(stored({ author: null }), feed({ author: null }), none),
    ).toBe(false)
  })

  it("a feed with no categories, funding or people matches empty lists", () => {
    expect(
      feedChanged(
        stored({ categories: [], funding: [], people: [] }),
        feedWithout("categories", "funding", "people"),
        none,
      ),
    ).toBe(false)
  })

  it("a feed that needed tidying matches what was saved from it", () => {
    // The same values the refresh writes, then read back the way the screens read them.
    const untidy = feed({
      people: [{ name: " Ann ", role: "HOST", group: "Cast" }],
      funding: [tip, tip, { url: "ftp://x.test", label: "No" }],
    })
    const row = {
      id: "s1",
      feed_url: "https://example.com/rss",
      title: untidy.title,
      author: untidy.author ?? null,
      description: untidy.description,
      image_url: untidy.imageUrl ?? null,
      link: untidy.link ?? null,
      language: untidy.language ?? null,
      categories: JSON.stringify(untidy.categories ?? []),
      funding: toJson(fundingFromJson(toJson(untidy.funding))),
      people: toJson(peopleFromJson(toJson(untidy.people))),
    }
    expect(feedChanged(showFromRow(row), untidy, none)).toBe(false)
  })
})
