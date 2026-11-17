// LOFI-FORK: the podcasts section's hand-filled playlists (see FORK.md).
import { describe, expect, it } from "vitest"

import { type Show, type StoredEpisode } from "./library"
import {
  playAllPlan,
  parseSnapshot,
  resolveItems,
  snapshotOf,
} from "./manualPlaylist"
import { serializeRules } from "./playlistRules"
import {
  ADD_ITEM_SQL,
  DELETE_PLAYLIST_SQL,
  ITEM_COUNTS_SQL,
  LIST_ITEMS_SQL,
  PLAYLISTS_WITH_SQL,
  REMOVE_ITEM_SQL,
  SAVE_PLAYLIST_SQL,
  SET_ITEM_POSITION_SQL,
} from "./playlistSql"
import { newPlaylist, playlistFromRow } from "./playlists"
import { DEFAULT_SHOW_SETTINGS } from "./showSettings"
import { openTestDatabase } from "./testDatabase"

const show: Show = {
  id: "preview:https://x.test/feed",
  feedUrl: "https://x.test/feed",
  title: "Unfollowed show",
  author: "Someone",
  description: "long text that is not kept",
  imageUrl: "https://x.test/art.jpg",
  link: null,
  language: "en",
  addedAt: 5,
  refreshedAt: 6,
  artworkColor: "#123456",
  ownPosition: 2,
  categories: ["News"],
  settings: DEFAULT_SHOW_SETTINGS,
}

function episode(
  id: string,
  patch: Partial<StoredEpisode> = {},
): StoredEpisode {
  return {
    id,
    showId: show.id,
    guid: `guid-${id}`,
    title: `Episode ${id}`,
    publishedAt: 1000,
    durationSeconds: 600,
    notes: "notes",
    audioUrl: `https://x.test/${id}.mp3`,
    audioType: "audio/mpeg",
    audioBytes: null,
    imageUrl: null,
    season: null,
    number: null,
    transcriptUrl: null,
    transcriptType: null,
    positionSeconds: 42,
    played: true,
    lastPlayedAt: 99,
    archived: true,
    starredAt: 7,
    ...patch,
  }
}

describe("snapshotOf and parseSnapshot", () => {
  it("keeps what is needed to play the episode and show it, not where the listener was", () => {
    const kept = parseSnapshot(snapshotOf(episode("a"), show))
    expect(kept?.episode).toMatchObject({
      id: "a",
      showId: show.id,
      title: "Episode a",
      audioUrl: "https://x.test/a.mp3",
      audioType: "audio/mpeg",
      durationSeconds: 600,
    })
    expect(kept?.episode).not.toHaveProperty("positionSeconds")
    expect(kept?.episode).not.toHaveProperty("played")
    expect(kept?.show).toEqual({
      id: show.id,
      feedUrl: show.feedUrl,
      title: "Unfollowed show",
      author: "Someone",
      imageUrl: show.imageUrl,
      link: null,
      language: "en",
    })
  })

  it("keeps an episode whose show is not known", () => {
    expect(parseSnapshot(snapshotOf(episode("a"), null))?.show).toBeNull()
  })

  it("gives null for anything that is not a kept episode", () => {
    expect(parseSnapshot("{nope")).toBeNull()
    expect(parseSnapshot("[]")).toBeNull()
    expect(parseSnapshot(JSON.stringify({ episode: { id: "a" } }))).toBeNull()
  })
})

describe("resolveItems", () => {
  const items = [
    { episodeId: "a", snapshot: snapshotOf(episode("a"), show) },
    { episodeId: "b", snapshot: snapshotOf(episode("b"), show) },
    { episodeId: "c", snapshot: "garbage" },
    { episodeId: "d", snapshot: "garbage" },
  ]

  it("reads an episode in the library from the library, and any other from what was kept", () => {
    const live = new Map([
      ["a", episode("a", { positionSeconds: 300, played: false })],
      ["d", episode("d")],
    ])
    const libraryShow = { ...show, id: "lib", title: "Followed" }
    const entries = resolveItems(
      items,
      new Map([
        ...live,
        [
          "a",
          episode("a", { showId: "lib", positionSeconds: 300, played: false }),
        ],
      ]),
      new Map([["lib", libraryShow]]),
    )
    expect(entries.map((e) => [e.episode.id, e.inLibrary])).toEqual([
      ["a", true],
      ["b", false],
      ["d", true],
    ])
    expect(entries[0]?.episode.positionSeconds).toBe(300)
    expect(entries[0]?.show?.title).toBe("Followed")
    // From the snapshot: unplayed, no place, and a show that plays.
    expect(entries[1]?.episode).toMatchObject({
      played: false,
      positionSeconds: 0,
      archived: false,
      starredAt: null,
    })
    expect(entries[1]?.show?.title).toBe("Unfollowed show")
  })

  it("falls back to the kept show when the library no longer has the episode's show", () => {
    const entries = resolveItems(
      [items[0]!],
      new Map([["a", episode("a")]]),
      new Map(),
    )
    expect(entries[0]?.show?.title).toBe("Unfollowed show")
  })
})

describe("playAllPlan", () => {
  it("plays the first and queues the rest at the top, last one first, so they end up in order", () => {
    expect(playAllPlan(["a", "b", "c"])).toEqual({
      play: "a",
      queue: [
        { id: "c", place: "next" },
        { id: "b", place: "next" },
      ],
    })
  })

  it("has nothing to play for an empty playlist, and queues nothing for one episode", () => {
    expect(playAllPlan([])).toEqual({ play: null, queue: [] })
    expect(playAllPlan(["a"])).toEqual({ play: "a", queue: [] })
  })
})

describe("hand-filled playlists in the database", () => {
  function setup() {
    const db = openTestDatabase()
    const mine = newPlaylist("mine", 3, 10, "manual")
    db.prepare(SAVE_PLAYLIST_SQL).run(
      mine.id,
      mine.title || "Mine",
      mine.position,
      serializeRules(mine.rules),
      mine.sort,
      0,
      mine.createdAt,
      mine.kind,
    )
    return db
  }
  const add = (
    db: ReturnType<typeof openTestDatabase>,
    episodeId: string,
    playlist = "mine",
  ) =>
    db
      .prepare(ADD_ITEM_SQL)
      .run(playlist, episodeId, playlist, `{"id":"${episodeId}"}`, 5)
  const order = (db: ReturnType<typeof openTestDatabase>, playlist = "mine") =>
    db
      .prepare(LIST_ITEMS_SQL)
      .all(playlist)
      .map((row) => String((row as { episode_id: string }).episode_id))

  it("saves the kind, and the starters stay smart", () => {
    const db = setup()
    const kinds = db
      .prepare("SELECT id, kind FROM playlists ORDER BY position")
      .all()
    expect(kinds.at(-1)).toEqual({ id: "mine", kind: "manual" })
    expect(
      kinds
        .slice(0, 3)
        .every((row) => (row as { kind: string }).kind === "smart"),
    ).toBe(true)
    expect(
      playlistFromRow(
        db.prepare("SELECT * FROM playlists WHERE id = 'mine'").get() as Record<
          string,
          unknown
        >,
      ).kind,
    ).toBe("manual")
  })

  it("adds episodes at the end, once each", () => {
    const db = setup()
    add(db, "a")
    add(db, "b")
    add(db, "a")
    add(db, "c")
    expect(order(db)).toEqual(["a", "b", "c"])
  })

  it("moves an item by giving the items new places", () => {
    const db = setup()
    for (const id of ["a", "b", "c"]) add(db, id)
    ;["c", "a", "b"].forEach((id, position) =>
      db.prepare(SET_ITEM_POSITION_SQL).run(position, "mine", id),
    )
    expect(order(db)).toEqual(["c", "a", "b"])
  })

  it("removes an item, and adds the next one after the highest place", () => {
    const db = setup()
    for (const id of ["a", "b", "c"]) add(db, id)
    db.prepare(REMOVE_ITEM_SQL).run("mine", "b")
    add(db, "d")
    expect(order(db)).toEqual(["a", "c", "d"])
  })

  it("keeps each playlist's items apart and says which playlists hold an episode", () => {
    const db = setup()
    const other = newPlaylist("other", 4, 11, "manual")
    db.prepare(SAVE_PLAYLIST_SQL).run(
      "other",
      "Other",
      4,
      serializeRules(other.rules),
      "newest",
      0,
      11,
      "manual",
    )
    add(db, "a")
    add(db, "a", "other")
    add(db, "b", "other")
    expect(order(db, "other")).toEqual(["a", "b"])
    expect(
      db
        .prepare(PLAYLISTS_WITH_SQL)
        .all("a")
        .map((r) => (r as { playlist_id: string }).playlist_id)
        .sort(),
    ).toEqual(["mine", "other"])
    expect(db.prepare(ITEM_COUNTS_SQL).all()).toEqual(
      expect.arrayContaining([
        { playlist_id: "mine", items: 1 },
        { playlist_id: "other", items: 2 },
      ]),
    )
  })

  it("drops its items with the playlist", () => {
    const db = setup()
    add(db, "a")
    db.prepare(DELETE_PLAYLIST_SQL).run("mine")
    expect(
      db.prepare("SELECT COUNT(*) AS n FROM playlist_items").get(),
    ).toEqual({ n: 0 })
  })

  it("keeps its items when the playlist is saved again", () => {
    const db = setup()
    add(db, "a")
    db.prepare(SAVE_PLAYLIST_SQL).run(
      "mine",
      "Renamed",
      3,
      "{}",
      "newest",
      0,
      10,
      "manual",
    )
    expect(order(db)).toEqual(["a"])
  })
})
