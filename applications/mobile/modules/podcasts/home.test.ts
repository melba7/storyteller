// LOFI-FORK: the podcasts section's Home (see FORK.md).
import { describe, expect, it } from "vitest"

import { orderUpNextShelf, rankTopShows } from "./home"
import { SHOW_PLAYS_SQL, UP_NEXT_CANDIDATES_SQL } from "./homeSql"
import { type Show, type StoredEpisode, episodeFromRow } from "./library"
import { addEpisode, addShow, openTestDatabase } from "./testDatabase"

function episode(values: Partial<StoredEpisode> & { id: string }) {
  return {
    showId: "s1",
    publishedAt: 1000,
    positionSeconds: 0,
    played: false,
    archived: false,
    lastPlayedAt: null,
    ...values,
  } as StoredEpisode
}

const ids = (list: { episode: StoredEpisode }[]) =>
  list.map((entry) => entry.episode.id)

describe("orderUpNextShelf", () => {
  it("puts episodes in progress first, the one played last first", () => {
    const shelf = orderUpNextShelf([
      episode({ id: "new", showId: "s1", publishedAt: 9000 }),
      episode({ id: "old", positionSeconds: 5, lastPlayedAt: 100 }),
      episode({ id: "recent", positionSeconds: 5, lastPlayedAt: 200 }),
    ])
    expect(ids(shelf)).toEqual(["recent", "old", "new"])
    expect(shelf.map((entry) => entry.kind)).toEqual([
      "resume",
      "resume",
      "new",
    ])
  })

  it("orders the new ones by date and keeps one per show", () => {
    const shelf = orderUpNextShelf([
      episode({ id: "a1", showId: "a", publishedAt: 100 }),
      episode({ id: "b1", showId: "b", publishedAt: 300 }),
      episode({ id: "a2", showId: "a", publishedAt: 200 }),
    ])
    expect(ids(shelf)).toEqual(["b1", "a2"])
  })

  it("never lists an episode twice", () => {
    const shelf = orderUpNextShelf([
      episode({ id: "x", positionSeconds: 5, lastPlayedAt: 1 }),
      episode({ id: "x", positionSeconds: 5, lastPlayedAt: 1 }),
    ])
    expect(ids(shelf)).toEqual(["x"])
  })

  it("leaves out played and archived ones", () => {
    expect(
      orderUpNextShelf([
        episode({ id: "p", played: true, positionSeconds: 5 }),
        episode({ id: "r", archived: true }),
      ]),
    ).toEqual([])
  })

  it("counts an added file only while it is in progress", () => {
    const shelf = orderUpNextShelf([
      episode({ id: "f1", showId: "local-files", publishedAt: 9000 }),
      episode({
        id: "f2",
        showId: "local-files",
        positionSeconds: 3,
        lastPlayedAt: 5,
      }),
    ])
    expect(ids(shelf)).toEqual(["f2"])
  })

  it("holds at most 20", () => {
    const many = Array.from({ length: 30 }, (_, i) =>
      episode({ id: `e${i}`, showId: `s${i}`, publishedAt: i }),
    )
    expect(orderUpNextShelf(many)).toHaveLength(20)
    expect(ids(orderUpNextShelf(many, 3))).toEqual(["e29", "e28", "e27"])
  })

  it("puts undated episodes after dated ones", () => {
    const shelf = orderUpNextShelf([
      episode({ id: "u", showId: "a", publishedAt: null }),
      episode({ id: "d", showId: "b", publishedAt: 1 }),
    ])
    expect(ids(shelf)).toEqual(["d", "u"])
  })
})

describe("the shelf's SQL", () => {
  function setup() {
    const db = openTestDatabase()
    addShow(db, "s1")
    addShow(db, "s2")
    addShow(db, "local-files", "Your files")
    return db
  }
  function shelfIds(db: ReturnType<typeof setup>) {
    const found = db.prepare(UP_NEXT_CANDIDATES_SQL).all()
    return orderUpNextShelf(
      (found as Record<string, unknown>[]).map(episodeFromRow),
    ).map((entry) => `${entry.kind}:${entry.episode.id}`)
  }

  it("gives resumed episodes, then the newest unplayed one of each show", () => {
    const db = setup()
    addEpisode(db, { id: "a1", show_id: "s1", published_at: 100 })
    addEpisode(db, { id: "a2", show_id: "s1", published_at: 200 })
    addEpisode(db, { id: "b1", show_id: "s2", published_at: 150 })
    addEpisode(db, {
      id: "b0",
      show_id: "s2",
      published_at: 50,
      position_seconds: 30,
      last_played_at: 7,
    })
    expect(shelfIds(db)).toEqual(["resume:b0", "new:a2", "new:b1"])
  })

  it("skips a played newest episode and takes the next unplayed one", () => {
    const db = setup()
    addEpisode(db, { id: "a1", show_id: "s1", published_at: 100 })
    addEpisode(db, { id: "a2", show_id: "s1", published_at: 200, played: 1 })
    addEpisode(db, { id: "a3", show_id: "s1", published_at: 300, archived: 1 })
    expect(shelfIds(db)).toEqual(["new:a1"])
  })

  it("lists a file added by the listener only while in progress", () => {
    const db = setup()
    addEpisode(db, { id: "f1", show_id: "local-files", published_at: 100 })
    addEpisode(db, {
      id: "f2",
      show_id: "local-files",
      published_at: 90,
      position_seconds: 4,
      last_played_at: 1,
    })
    expect(shelfIds(db)).toEqual(["resume:f2"])
  })

  it("does not repeat an episode that is both in progress and the newest", () => {
    const db = setup()
    addEpisode(db, {
      id: "a1",
      show_id: "s1",
      published_at: 100,
      position_seconds: 9,
      last_played_at: 1,
    })
    expect(shelfIds(db)).toEqual(["resume:a1"])
  })
})

describe("rankTopShows", () => {
  const show = (id: string, title = id) => ({ id, title }) as Show
  const shows = [show("a"), show("b"), show("c"), show("local-files")]

  it("puts the most recently listened shows first, then the newest episodes", () => {
    const ranked = rankTopShows(
      shows,
      new Map([["b", 50]]),
      new Map([
        ["a", 10],
        ["c", 20],
      ]),
    )
    expect(ranked.map((s) => s.id)).toEqual(["b", "c", "a"])
  })

  it("uses the title when nothing else tells them apart, and caps the list", () => {
    const ranked = rankTopShows(shows, new Map(), new Map(), 2)
    expect(ranked.map((s) => s.id)).toEqual(["a", "b"])
  })
})

describe("the plays SQL", () => {
  it("gives each followed show's last listen from the history", () => {
    const db = openTestDatabase()
    addShow(db, "s1")
    addShow(db, "local-files", "Your files")
    addEpisode(db, { id: "a", show_id: "s1", history_at: 10 })
    addEpisode(db, { id: "b", show_id: "s1", history_at: 30 })
    addEpisode(db, { id: "c", show_id: "s1", history_at: null })
    addEpisode(db, { id: "f", show_id: "local-files", history_at: 99 })
    expect(db.prepare(SHOW_PLAYS_SQL).all()).toEqual([
      { show_id: "s1", last_at: 30 },
    ])
  })
})
