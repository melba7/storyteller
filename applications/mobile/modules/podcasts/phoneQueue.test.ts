// LOFI-FORK: the podcasts section's list of next episodes for the Mac (see FORK.md).
import { describe, expect, it } from "vitest"

import {
  QUEUE_MOST,
  QUEUE_NEWEST_SQL,
  type QueueCandidate,
  type QueueEntry,
  chooseQueue,
  newestSince,
  queueCandidate,
  queueText,
  queueToWrite,
  queueUpNextSql,
} from "./phoneQueue"
import { addEpisode, addShow, openTestDatabase } from "./testDatabase"

const MAIN = {
  skipAds: true,
  skipOwnPlugs: true,
  skipPromos: true,
  skipCredits: false,
}

function candidate(
  id: string,
  more: Partial<QueueCandidate> = {},
): QueueCandidate {
  return {
    id,
    feed: "https://example.com/feed.xml",
    guid: `guid-${id}`,
    title: `Episode ${id}`,
    show: "A show",
    audio: `https://example.com/${id}.mp3`,
    published: 1_700_000_000,
    skipAds: null,
    skipPlugs: null,
    ...more,
  }
}

const guids = (entries: readonly QueueEntry[]) =>
  entries.map((entry) => entry.guid)

describe("chooseQueue", () => {
  it("puts Up Next first in its order, then the newest episodes", () => {
    const entries = chooseQueue(
      [candidate("b"), candidate("a")],
      [candidate("n1"), candidate("n2")],
      MAIN,
    )
    expect(guids(entries)).toEqual(["guid-b", "guid-a", "guid-n1", "guid-n2"])
    expect(entries.map((entry) => entry.reason)).toEqual([
      "upNext",
      "upNext",
      "newest",
      "newest",
    ])
    expect(entries.map((entry) => entry.rank)).toEqual([0, 1, 2, 3])
  })

  it("gives each entry the words the Mac reads, in that order", () => {
    const [entry] = chooseQueue([candidate("a")], [], MAIN)
    expect(entry).toEqual({
      feed: "https://example.com/feed.xml",
      guid: "guid-a",
      title: "Episode a",
      show: "A show",
      audio: "https://example.com/a.mp3",
      published: 1_700_000_000,
      reason: "upNext",
      rank: 0,
    })
    expect(Object.keys(entry ?? {})).toEqual([
      "feed",
      "guid",
      "title",
      "show",
      "audio",
      "published",
      "reason",
      "rank",
    ])
  })

  it("carries when each episode came out, or null when the feed gave no date", () => {
    const entries = chooseQueue(
      [
        candidate("a", { published: 1_700_086_400 }),
        candidate("b", { published: null }),
      ],
      [],
      MAIN,
    )
    expect(entries.map((entry) => entry.published)).toEqual([
      1_700_086_400,
      null,
    ])
    expect(JSON.parse(queueText(entries, 1))["episodes"]).toEqual([
      expect.objectContaining({ guid: "guid-a", published: 1_700_086_400 }),
      expect.objectContaining({ guid: "guid-b", published: null }),
    ])
  })

  it("holds 12 at most, Up Next first", () => {
    const upNext = Array.from({ length: 10 }, (_, i) => candidate(`u${i}`))
    const newest = Array.from({ length: 10 }, (_, i) => candidate(`n${i}`))
    const entries = chooseQueue(upNext, newest, MAIN)
    expect(QUEUE_MOST).toBe(12)
    expect(entries).toHaveLength(12)
    expect(entries.filter((e) => e.reason === "upNext")).toHaveLength(10)
    expect(entries.at(-1)?.rank).toBe(11)
    expect(
      chooseQueue([...upNext, ...upNext, candidate("x")], [], MAIN),
    ).toHaveLength(11)
  })

  it("never lists an episode twice, and a queued one keeps its Up Next place", () => {
    const entries = chooseQueue(
      [candidate("a"), candidate("a"), candidate("b")],
      [candidate("b"), candidate("c")],
      MAIN,
    )
    expect(guids(entries)).toEqual(["guid-a", "guid-b", "guid-c"])
    expect(entries.map((entry) => entry.reason)).toEqual([
      "upNext",
      "upNext",
      "newest",
    ])
    expect(entries.map((entry) => entry.rank)).toEqual([0, 1, 2])
  })

  it("leaves out an episode the listener added from the Files app", () => {
    const entries = chooseQueue(
      [candidate("file-123"), candidate("a")],
      [candidate("file-9")],
      MAIN,
    )
    expect(guids(entries)).toEqual(["guid-a"])
  })

  it("leaves out an episode the Mac could not fetch", () => {
    const entries = chooseQueue(
      [
        candidate("noguid", { guid: "" }),
        candidate("nofeed", { feed: "local:files" }),
        candidate("noaudio", { audio: "" }),
        candidate("ftp", { audio: "ftp://example.com/a.mp3" }),
        candidate("ok"),
      ],
      [],
      MAIN,
    )
    expect(guids(entries)).toEqual(["guid-ok"])
  })

  it("leaves out a show whose ad skipping the listener turned off", () => {
    const off = { skipAds: false, skipPlugs: false }
    const entries = chooseQueue(
      [candidate("off", off), candidate("on")],
      [candidate("off2", off), candidate("n")],
      MAIN,
    )
    expect(guids(entries)).toEqual(["guid-on", "guid-n"])
  })

  it("keeps a show that only turned sponsor ads off but still skips the hosts' plugs", () => {
    const entries = chooseQueue([candidate("a", { skipAds: false })], [], MAIN)
    expect(guids(entries)).toEqual(["guid-a"])
  })

  it("follows the main switches for a show that has no choice of its own", () => {
    const allOff = {
      skipAds: false,
      skipOwnPlugs: false,
      skipPromos: false,
      skipCredits: false,
    }
    expect(chooseQueue([candidate("a")], [], allOff)).toEqual([])
    // A show that turned ad skipping on for itself is read ahead whatever the main switches say.
    expect(
      guids(chooseQueue([candidate("a", { skipAds: true })], [], allOff)),
    ).toEqual(["guid-a"])
  })

  it("has nothing for no episodes", () => {
    expect(chooseQueue([], [], MAIN)).toEqual([])
  })
})

describe("queueText", () => {
  it("is a version 1 file with the time in seconds and the episodes", () => {
    const entries = chooseQueue([candidate("a")], [], MAIN)
    expect(JSON.parse(queueText(entries, 1_700_000_000))).toEqual({
      version: 1,
      writtenAt: 1_700_000_000,
      episodes: entries,
    })
  })
})

describe("queueToWrite", () => {
  const entries = chooseQueue([candidate("a")], [candidate("n")], MAIN)

  it("writes when there is no file and there is something to say", () => {
    const text = queueToWrite({ status: "missing" }, entries, 5)
    expect(JSON.parse(text ?? "{}").writtenAt).toBe(5)
  })

  it("writes nothing for no file and no episodes", () => {
    expect(queueToWrite({ status: "missing" }, [], 5)).toBeNull()
  })

  it("writes nothing when the file already holds these episodes, whatever its time", () => {
    const old = queueText(entries, 1)
    expect(queueToWrite({ status: "found", text: old }, entries, 99)).toBeNull()
  })

  it("writes when the episodes changed, also to an empty list", () => {
    const old = queueText(entries, 1)
    expect(
      queueToWrite({ status: "found", text: old }, entries.slice(0, 1), 9),
    ).not.toBeNull()
    const empty = queueToWrite({ status: "found", text: old }, [], 9)
    expect(JSON.parse(empty ?? "{}").episodes).toEqual([])
  })

  it("writes over a file that is not a queue", () => {
    for (const text of ["", "not json", "[]", '{"version":2}']) {
      expect(queueToWrite({ status: "found", text }, entries, 9)).not.toBeNull()
    }
  })

  it("tries to write when it could not read the file", () => {
    expect(queueToWrite({ status: "notDownloaded" }, entries, 9)).not.toBeNull()
  })
})

describe("the queue's SQL", () => {
  const DAY = 86_400_000
  const NOW = 100 * DAY

  function setup() {
    const db = openTestDatabase()
    addShow(db, "s1", "Show one")
    addShow(db, "s2", "Show two")
    addShow(db, "s3", "Show three")
    addShow(db, "local-files", "Your files")
    return db
  }

  function newestGuids(db: ReturnType<typeof setup>) {
    const found = db.prepare(QUEUE_NEWEST_SQL).all(newestSince(NOW)) as Record<
      string,
      unknown
    >[]
    return found.map((row) => queueCandidate(row).guid)
  }

  it("takes the newest unplayed episode of each show played in the last 14 days", () => {
    const db = setup()
    addEpisode(db, {
      id: "a1",
      show_id: "s1",
      published_at: 100,
      played: 1,
      history_at: NOW - 2 * DAY,
    })
    addEpisode(db, { id: "a2", show_id: "s1", published_at: 200 })
    addEpisode(db, { id: "a3", show_id: "s1", published_at: 300 })
    addEpisode(db, {
      id: "b1",
      show_id: "s2",
      published_at: 100,
      played: 1,
      history_at: NOW - 1 * DAY,
    })
    addEpisode(db, { id: "b2", show_id: "s2", published_at: 150 })
    // The most recently played show comes first.
    expect(newestGuids(db)).toEqual(["b2", "a3"])
  })

  it("leaves out a show that was last played longer ago than that", () => {
    const db = setup()
    addEpisode(db, {
      id: "a1",
      show_id: "s1",
      published_at: 100,
      played: 1,
      history_at: NOW - 15 * DAY,
    })
    addEpisode(db, { id: "a2", show_id: "s1", published_at: 200 })
    addEpisode(db, {
      id: "b1",
      show_id: "s2",
      published_at: 100,
      played: 1,
      history_at: NOW - 14 * DAY,
    })
    addEpisode(db, { id: "b2", show_id: "s2", published_at: 200 })
    expect(newestGuids(db)).toEqual(["b2"])
  })

  it("skips played, archived and undated episodes and the added files", () => {
    const db = setup()
    addEpisode(db, {
      id: "a1",
      show_id: "s1",
      published_at: 100,
      played: 1,
      history_at: NOW,
    })
    addEpisode(db, { id: "a2", show_id: "s1", published_at: 300, played: 1 })
    addEpisode(db, { id: "a3", show_id: "s1", published_at: 400, archived: 1 })
    addEpisode(db, { id: "a4", show_id: "s1", published_at: null })
    addEpisode(db, { id: "a5", show_id: "s1", published_at: 150 })
    addEpisode(db, {
      id: "f1",
      show_id: "local-files",
      published_at: 100,
      history_at: NOW,
    })
    addEpisode(db, { id: "f2", show_id: "local-files", published_at: 200 })
    expect(newestGuids(db)).toEqual(["a5"])
  })

  it("carries what the Mac and the settings need", () => {
    const db = setup()
    db.prepare("UPDATE shows SET skip_ads = 0 WHERE id = 's1'").run()
    addEpisode(db, {
      id: "a1",
      show_id: "s1",
      guid: "g1",
      title: "First",
      published_at: 100,
      history_at: NOW - DAY,
      played: 1,
    })
    addEpisode(db, {
      id: "a2",
      show_id: "s1",
      guid: "g2",
      title: "Second",
      audio_url: "https://cdn.example.com/second.mp3",
      published_at: 1_700_000_123_456,
    })
    const [row] = db.prepare(QUEUE_NEWEST_SQL).all(newestSince(NOW)) as Record<
      string,
      unknown
    >[]
    expect(queueCandidate(row ?? {})).toEqual({
      id: "a2",
      feed: "https://example.com/s1.xml",
      guid: "g2",
      title: "Second",
      show: "Show one",
      audio: "https://cdn.example.com/second.mp3",
      // The database holds milliseconds; the file, like the Mac's files, seconds.
      published: 1_700_000_123,
      skipAds: false,
      skipPlugs: null,
    })
  })

  it("gives no published time for an episode the database has no date for", () => {
    const db = setup()
    addEpisode(db, { id: "a1", show_id: "s1", guid: "g1", published_at: null })
    const [row] = db.prepare(queueUpNextSql(1)).all("a1") as Record<
      string,
      unknown
    >[]
    expect(queueCandidate(row ?? {}).published).toBeNull()
    expect(queueCandidate({}).published).toBeNull()
    expect(queueCandidate({ published_at: "soon" }).published).toBeNull()
  })

  it("finds the queued episodes by their ids", () => {
    const db = setup()
    addEpisode(db, { id: "a1", show_id: "s1", guid: "g1" })
    addEpisode(db, { id: "b1", show_id: "s2", guid: "g2" })
    addEpisode(db, { id: "c1", show_id: "s3", guid: "g3" })
    const found = db
      .prepare(queueUpNextSql(3))
      .all("b1", "a1", "gone") as Record<string, unknown>[]
    expect(found.map((row) => queueCandidate(row).id).sort()).toEqual([
      "a1",
      "b1",
    ])
  })
})
