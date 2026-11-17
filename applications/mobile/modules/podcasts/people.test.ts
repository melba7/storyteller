// LOFI-FORK: the podcasts section's hosts, guests and support links (see FORK.md).
import { describe, expect, it } from "vitest"

import {
  fundingFromJson,
  MAX_FUNDING,
  MAX_PEOPLE,
  peopleForEpisode,
  peopleFromJson,
  samePeople,
  toJson,
  webUrl,
} from "./people"

const ann = { name: "Ann", role: "host", group: "cast", img: null, href: null }
const bo = { name: "Bo", role: "guest", group: "cast", img: null, href: null }

describe("webUrl", () => {
  it("keeps only http and https addresses", () => {
    expect(webUrl("https://x.test/a")).toBe("https://x.test/a")
    expect(webUrl(" http://x.test ")).toBe("http://x.test")
    expect(webUrl("javascript:alert(1)")).toBeNull()
    expect(webUrl("ftp://x.test")).toBeNull()
    expect(webUrl(3)).toBeNull()
  })
})

describe("peopleFromJson", () => {
  it("reads saved people and fills the spec's defaults", () => {
    expect(
      peopleFromJson(
        '[{"name":"Ann"},{"name":" Bo ","role":"Guest","img":"https://x.test/b.jpg","href":"https://x.test/b"}]',
      ),
    ).toEqual([
      ann,
      {
        name: "Bo",
        role: "guest",
        group: "cast",
        img: "https://x.test/b.jpg",
        href: "https://x.test/b",
      },
    ])
  })

  it("gives none for anything that is not a list, and skips bad entries", () => {
    expect(peopleFromJson(null)).toEqual([])
    expect(peopleFromJson("not json")).toEqual([])
    expect(peopleFromJson('{"name":"Ann"}')).toEqual([])
    expect(
      peopleFromJson('[3,null,{"name":""},{"role":"host"},{"name":"Ann"}]'),
    ).toEqual([ann])
  })

  it("drops links that are not http(s) and keeps at most 20", () => {
    expect(
      peopleFromJson(
        '[{"name":"Ann","img":"file:///a.jpg","href":"javascript:x"}]',
      ),
    ).toEqual([ann])
    const many = Array.from({ length: 30 }, (_, i) => ({ name: `P${i}` }))
    expect(peopleFromJson(JSON.stringify(many))).toHaveLength(MAX_PEOPLE)
  })
})

describe("fundingFromJson", () => {
  it("keeps http(s) links with their labels", () => {
    expect(
      fundingFromJson(
        '[{"url":"https://x.test/give","label":"Give"},{"url":"http://x.test"},{"url":"mailto:a@x.test","label":"Mail"},{"label":"none"},"x"]',
      ),
    ).toEqual([
      { url: "https://x.test/give", label: "Give" },
      { url: "http://x.test", label: "" },
    ])
  })

  it("keeps a repeated address once", () => {
    expect(
      fundingFromJson(
        '[{"url":"https://x.test/give","label":"Give"},{"url":"https://x.test/give","label":"Again"},{"url":"https://x.test/other"}]',
      ).map((l) => l.url),
    ).toEqual(["https://x.test/give", "https://x.test/other"])
  })

  it("gives none for bad input and keeps at most 5", () => {
    expect(fundingFromJson(undefined)).toEqual([])
    expect(fundingFromJson("{")).toEqual([])
    const many = Array.from({ length: 9 }, (_, i) => ({
      url: `https://x.test/${i}`,
    }))
    expect(fundingFromJson(JSON.stringify(many))).toHaveLength(MAX_FUNDING)
  })
})

describe("peopleForEpisode", () => {
  it("uses the episode's own people instead of the show's", () => {
    expect(peopleForEpisode({ people: [bo] }, { people: [ann] })).toEqual([bo])
  })

  it("falls back to the show's people when the episode has none", () => {
    expect(peopleForEpisode({ people: [] }, { people: [ann] })).toEqual([ann])
    expect(peopleForEpisode({ people: [] }, null)).toEqual([])
  })
})

describe("saving", () => {
  it("writes a list as JSON, and none as an empty list", () => {
    expect(toJson([ann])).toBe(JSON.stringify([ann]))
    expect(toJson(undefined)).toBe("[]")
  })

  it("compares people by value", () => {
    expect(samePeople([ann], [{ ...ann }])).toBe(true)
    expect(samePeople([ann], [bo])).toBe(false)
  })
})
