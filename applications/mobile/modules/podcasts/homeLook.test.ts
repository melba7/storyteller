// LOFI-FORK: the podcasts section's Home (see FORK.md).
import { describe, expect, it } from "vitest"

import { contrastBetween } from "./artworkTint"
import { type ShelfEntry } from "./home"
import {
  agoLabel,
  cardLine,
  cardPalette,
  plainText,
  timeLeftLabel,
  topShowCaption,
  updateCadence,
} from "./homeLook"
import { SHOW_DATES_SQL } from "./homeSql"
import { type StoredEpisode } from "./library"
import { addEpisode, addShow, openTestDatabase } from "./testDatabase"

const now = new Date(2026, 10, 17, 12, 0).getTime()
const HOUR = 3_600_000
const DAY = 24 * HOUR

describe("agoLabel", () => {
  it("reads minutes, hours and days", () => {
    expect(agoLabel(now - 10_000, now)).toBe("now")
    expect(agoLabel(now - 12 * 60_000, now)).toBe("12m ago")
    expect(agoLabel(now - 17 * HOUR, now)).toBe("17h ago")
    expect(agoLabel(now - 5 * DAY, now)).toBe("5d ago")
    expect(agoLabel(now + HOUR, now)).toBe("now")
  })
  it("gives the date after thirty days", () => {
    expect(agoLabel(new Date(2026, 8, 1).getTime(), now)).toBe("1 Sep 2026")
  })
})

describe("cardLine", () => {
  const entry = (kind: ShelfEntry["kind"], values: Partial<StoredEpisode>) =>
    ({
      kind,
      episode: { publishedAt: null, lastPlayedAt: null, ...values },
    }) as ShelfEntry
  it("says New from the publish date", () => {
    expect(cardLine(entry("new", { publishedAt: now - 17 * HOUR }), now)).toBe(
      "New · 17h ago",
    )
  })
  it("says Resume from the last play, else the publish date", () => {
    expect(
      cardLine(
        entry("resume", { lastPlayedAt: now - 5 * DAY, publishedAt: now }),
        now,
      ),
    ).toBe("Resume · 5d ago")
    expect(cardLine(entry("resume", { publishedAt: now - 2 * DAY }), now)).toBe(
      "Resume · 2d ago",
    )
  })
  it("has no time for an undated episode", () => {
    expect(cardLine(entry("new", {}), now)).toBe("New")
  })
})

describe("timeLeftLabel", () => {
  it("shows the whole length when not started", () => {
    expect(timeLeftLabel(19 * 60, 0)).toBe("19m")
    expect(timeLeftLabel(3720, 0)).toBe("1h 2m")
    expect(timeLeftLabel(7200, 0)).toBe("2h")
  })
  it("shows the time left when started", () => {
    expect(timeLeftLabel(3600, 3000)).toBe("10m")
    expect(timeLeftLabel(3600, 60)).toBe("59m")
  })
  it("is at least a minute, and empty when the length is unknown", () => {
    expect(timeLeftLabel(10, 0)).toBe("1m")
    expect(timeLeftLabel(null, 5)).toBe("")
    expect(timeLeftLabel(0, 0)).toBe("")
  })
})

describe("plainText", () => {
  it("strips markup, reads entities and collapses space", () => {
    expect(
      plainText(
        "<p>On <b>Friday</b>, the FAA&nbsp;said</p><p>Tom &amp; Jerry &#39;hi&#x21;</p>",
      ),
    ).toBe("On Friday, the FAA said Tom & Jerry 'hi!")
  })
  it("leaves an unknown entity and a bad number alone", () => {
    expect(plainText("a &foo; b &#99999999; c")).toBe("a &foo; b c")
  })
})

describe("cardPalette", () => {
  it("uses white text on a dark colour", () => {
    const palette = cardPalette("#1a237e")
    expect(palette.text).toBe("#ffffff")
    expect(contrastBetween(palette.text, palette.background)).toBeGreaterThan(7)
  })
  it("uses near-black text on a light colour", () => {
    const palette = cardPalette("#ffeb3b")
    expect(palette.text).toBe("#111111")
    expect(contrastBetween(palette.text, palette.background)).toBeGreaterThan(7)
  })
  it("always reads well, whatever the colour", () => {
    for (const color of [
      "#ff8800",
      "#00aa88",
      "#888888",
      "#e91e63",
      "#cddc39",
    ]) {
      const p = cardPalette(color)
      expect(contrastBetween(p.text, p.background)).toBeGreaterThan(4.5)
    }
  })
  it("tints the label towards the text colour", () => {
    expect(cardPalette("#1a237e").label).not.toBe(cardPalette("#1a237e").text)
  })
})

describe("updateCadence", () => {
  const every = (days: number, count = 6) =>
    Array.from({ length: count }, (_, i) => now - i * days * DAY)
  it("names daily, weekly, biweekly and monthly shows", () => {
    expect(updateCadence(every(1), now)).toBe("Updated Daily")
    expect(updateCadence(every(7), now)).toBe("Updated Weekly")
    expect(updateCadence(every(14), now)).toBe("Updated Biweekly")
    expect(updateCadence(every(30), now)).toBe("Updated Monthly")
  })
  it("uses the median, so one long break does not matter", () => {
    expect(
      updateCadence(
        [now, now - 7 * DAY, now - 14 * DAY, now - 21 * DAY, now - 100 * DAY],
        now,
      ),
    ).toBe("Updated Weekly")
  })
  it("says nothing with too few dates or an odd rhythm", () => {
    expect(updateCadence(every(7, 2), now)).toBe("")
    expect(updateCadence(every(120), now)).toBe("")
  })
  it("does not depend on the order of the dates", () => {
    expect(updateCadence(every(7).reverse(), now)).toBe("Updated Weekly")
  })
})

describe("topShowCaption", () => {
  it("is the first category's top level, else the title", () => {
    expect(
      topShowCaption({
        title: "T",
        categories: ["News", "Business › Investing"],
      }),
    ).toBe("News")
    expect(
      topShowCaption({ title: "T", categories: ["Business › Investing"] }),
    ).toBe("Business")
    expect(topShowCaption({ title: "T", categories: [] })).toBe("T")
  })
})

describe("the dates SQL", () => {
  it("gives each show's six newest dates, newest first, without added files", () => {
    const db = openTestDatabase()
    addShow(db, "s1")
    addShow(db, "local-files", "Your files")
    for (let i = 1; i <= 8; i++) {
      addEpisode(db, { id: `e${i}`, show_id: "s1", published_at: i * 100 })
    }
    addEpisode(db, { id: "u", show_id: "s1", published_at: null })
    addEpisode(db, { id: "f", show_id: "local-files", published_at: 5 })
    const found = db.prepare(SHOW_DATES_SQL).all() as {
      show_id: string
      published_at: number
    }[]
    expect(found.map((row) => row.published_at)).toEqual([
      800, 700, 600, 500, 400, 300,
    ])
    expect(new Set(found.map((row) => row.show_id))).toEqual(new Set(["s1"]))
  })
})
