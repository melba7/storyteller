// LOFI-FORK: the podcasts section's Up Next rules (see FORK.md).
import { describe, expect, it } from "vitest"

import type { UpNextItem } from "./index"
import type { Show, StoredEpisode } from "./library"
import {
  isQueued,
  moveBetween,
  orderAfterMove,
  outsideQueue,
  progressFraction,
  queueItem,
  queueTimeLeft,
  queuedLabel,
  rowLabel,
  upNextBadge,
  upNextSummary,
} from "./upNext"

const item = (
  id: string,
  duration: number | null = 600,
  position = 0,
): UpNextItem => ({
  id,
  url: `https://cdn.example.com/${id}.mp3`,
  type: "audio/mpeg",
  title: `Episode ${id}`,
  showTitle: "The Show",
  duration,
  position,
})

describe("queueTimeLeft", () => {
  it("adds up what is left of each episode", () => {
    expect(
      queueTimeLeft([
        item("a", 3600, 0),
        item("b", 3600, 1800),
        item("c", 1200),
      ]),
    ).toBe("1 h 50 min left")
  })
  it("leaves out episodes of unknown length", () => {
    expect(queueTimeLeft([item("a", null), item("b", 600, 0)])).toBe(
      "10 min left",
    )
  })
  it("says nothing for an empty queue or no lengths", () => {
    expect(queueTimeLeft([])).toBe("")
    expect(queueTimeLeft([item("a", null)])).toBe("")
  })
  it("never counts a place past the end as negative time", () => {
    expect(queueTimeLeft([item("a", 600, 900), item("b", 600)])).toBe(
      "10 min left",
    )
  })
})

describe("the count on the tab", () => {
  it("is the number of queued episodes", () => {
    expect(upNextBadge([item("a"), item("b")])).toBe("2")
  })
  it("is empty at 0 and reads 99+ past 99", () => {
    expect(upNextBadge([])).toBe("")
    const many = Array.from({ length: 100 }, (_, i) => item(String(i)))
    expect(upNextBadge(many)).toBe("99+")
  })
})

describe("upNextSummary", () => {
  it("reads as a count and the time left", () => {
    expect(upNextSummary([item("a")])).toBe("1 episode · 10 min left")
    expect(upNextSummary([item("a"), item("b", null)])).toBe(
      "2 episodes · 10 min left",
    )
    expect(upNextSummary([item("a", null)])).toBe("1 episode")
    expect(upNextSummary([])).toBe("")
  })
})

describe("orderAfterMove", () => {
  const items = [item("a"), item("b"), item("c"), item("d")]
  it("moves an episode to a new place", () => {
    expect(orderAfterMove(items, 0, 2).map((i) => i.id)).toEqual([
      "b",
      "c",
      "a",
      "d",
    ])
    expect(orderAfterMove(items, 3, 0).map((i) => i.id)).toEqual([
      "d",
      "a",
      "b",
      "c",
    ])
  })
  it("clamps a move outside the list and leaves the input alone", () => {
    expect(orderAfterMove(items, 1, 99).map((i) => i.id)).toEqual([
      "a",
      "c",
      "d",
      "b",
    ])
    expect(items.map((i) => i.id)).toEqual(["a", "b", "c", "d"])
  })
  it("keeps each item's details", () => {
    expect(orderAfterMove([item("a", 100, 5), item("b")], 0, 1)[1]).toEqual(
      item("a", 100, 5),
    )
  })
  it("copes with an empty queue", () => {
    expect(orderAfterMove([], 0, 1)).toEqual([])
  })
})

describe("queued episodes", () => {
  const items = [item("a"), item("b")]
  it("knows which episodes are queued and where", () => {
    expect(isQueued(items, "b")).toBe(true)
    expect(isQueued(items, "z")).toBe(false)
    expect(queuedLabel(items, "b")).toBe("Up Next, number 2")
    expect(queuedLabel(items, "z")).toBe("")
  })
  it("labels a row for VoiceOver", () => {
    expect(rowLabel(item("a", 3600, 600), 0, 2)).toBe(
      "Episode a, The Show, 50 min left, place 1 of 2",
    )
  })
})

describe("queueItem", () => {
  const episode = {
    id: "e1",
    showId: "s1",
    guid: "g",
    title: "One",
    publishedAt: null,
    durationSeconds: 1000,
    notes: "",
    audioUrl: "https://cdn.example.com/1.mp3",
    audioType: "audio/mpeg",
    audioBytes: null,
    imageUrl: null,
    season: null,
    number: null,
    transcriptUrl: null,
    transcriptType: null,
    chaptersUrl: null,
    positionSeconds: 300,
    played: false,
    lastPlayedAt: null,
    archived: false,
    starredAt: null,
  } as StoredEpisode
  const show = {
    id: "s1",
    title: "The Show",
    imageUrl: "https://x/a.jpg",
  } as Show

  it("carries what the player needs to start it", () => {
    expect(queueItem(episode, show)).toEqual({
      id: "e1",
      showId: "s1",
      url: "https://cdn.example.com/1.mp3",
      type: "audio/mpeg",
      title: "One",
      showTitle: "The Show",
      artworkUrl: "https://x/a.jpg",
      duration: 1000,
      position: 300,
      chaptersUrl: null,
      language: null,
      notes: "",
      showLink: null,
    })
  })
  it("carries the notes, cut to 4,000 characters, and the show's link", () => {
    const noted = { ...episode, notes: "x".repeat(5000) }
    const item = queueItem(noted, { ...show, link: "https://show.test" })
    expect(item.notes).toBe("x".repeat(4000))
    expect(item.showLink).toBe("https://show.test")
  })
  it("carries the show's language, so the next episode is transcribed in it", () => {
    expect(queueItem(episode, { ...show, language: "de" }).language).toBe("de")
  })
  it("carries the chapters address", () => {
    const chaptered = { ...episode, chaptersUrl: "https://x.test/c.json" }
    expect(queueItem(chaptered, show).chaptersUrl).toBe("https://x.test/c.json")
  })
  // The rule changed with Mo's OK (S14). This test used to expect 0 for 995 of the feed's
  // length: only the played mark starts an episode over now, the feed's length does not.
  it("starts a played episode over and resumes a nearly finished one", () => {
    expect(queueItem({ ...episode, played: true }, show).position).toBe(0)
    expect(queueItem({ ...episode, positionSeconds: 995 }, show).position).toBe(
      995,
    )
  })
  it("copes with a show that is not in the library", () => {
    expect(queueItem(episode, null)).toMatchObject({
      showTitle: "",
      artworkUrl: null,
    })
  })
})

describe("moveBetween", () => {
  const before = ["a", "b", "c", "d"]
  it("finds a move down and a move up", () => {
    expect(moveBetween(before, ["b", "c", "a", "d"])).toEqual({
      from: 0,
      to: 2,
    })
    expect(moveBetween(before, ["a", "d", "b", "c"])).toEqual({
      from: 3,
      to: 1,
    })
    expect(moveBetween(before, ["a", "c", "b", "d"])).toEqual({
      from: 1,
      to: 2,
    })
  })
  it("finds nothing when the lists are the same or differ otherwise", () => {
    expect(moveBetween(before, before)).toBeNull()
    expect(moveBetween(before, ["a", "b", "c"])).toBeNull()
    expect(moveBetween(before, ["d", "c", "b", "a"])).toBeNull()
  })
})

describe("progressFraction", () => {
  it("is the share played, once an episode has started", () => {
    expect(progressFraction(150, 600)).toBe(0.25)
  })
  it("is null before the start, or when the length is unknown", () => {
    expect(progressFraction(0, 600)).toBeNull()
    expect(progressFraction(30, null)).toBeNull()
    expect(progressFraction(30, 0)).toBeNull()
  })
  it("stays within the bar", () => {
    expect(progressFraction(900, 600)).toBe(1)
  })
})

describe("outsideQueue", () => {
  const entries = [{ episode: { id: "a" } }, { episode: { id: "b" } }]
  const queue = [{ id: "b" }] as UpNextItem[]
  it("leaves out the episodes already queued", () => {
    expect(outsideQueue(entries, queue)).toEqual([{ episode: { id: "a" } }])
  })
  it("keeps everything when nothing is queued", () => {
    expect(outsideQueue(entries, [])).toEqual(entries)
  })
})
