// LOFI-FORK: the podcasts section's own audio files tests (see FORK.md).
import { describe, expect, it } from "vitest"

import { planFollows, planPlayed } from "./applePodcasts"
import { downloadsToDelete, DEFAULT_SETTINGS } from "./automatic"
import { pickForYou } from "./categories"
import {
  LOCAL_FEED_URL,
  LOCAL_SHOW_ID,
  cleanName,
  feedShows,
  importSummary,
  withoutLocalIds,
  isLocalAudioUrl,
  isLocalEpisodeId,
  localAudioUrl,
  localEpisodeValues,
} from "./localFiles"
import { writeOpml } from "./opml"
import { episodeShare } from "./share"

const local = {
  id: LOCAL_SHOW_ID,
  feedUrl: LOCAL_FEED_URL,
  title: "Your files",
}
const real = { id: "s1", feedUrl: "https://a.example.com/feed", title: "A" }

describe("the local show is never treated as a feed", () => {
  it("is left out of anything that works on feeds", () => {
    expect(feedShows([local, real])).toEqual([real])
  })

  it("is not written to an OPML file", () => {
    const xml = writeOpml([local, real], new Date(0))
    expect(xml).toContain("a.example.com")
    expect(xml).not.toContain("local:files")
  })

  it("is not matched to what Apple Podcasts finished", () => {
    const file = {
      shows: [],
      finished: [{ feed: LOCAL_FEED_URL, guid: "file-1" }],
    }
    expect(planPlayed(file, [local])).toEqual([])
  })

  it("is not something Apple Podcasts follows", () => {
    const file = {
      shows: [{ feed: LOCAL_FEED_URL, title: "x" }],
      finished: [],
    }
    expect(planFollows(file, [], []).subscribe).toEqual([])
  })

  it("adds no category to the suggestions", () => {
    const picks = pickForYou([
      { title: "Your files", feedUrl: LOCAL_FEED_URL, categories: ["Comedy"] },
    ])
    expect(picks).toEqual([])
  })

  it("never has its files deleted as played downloads", () => {
    const day = 24 * 60 * 60 * 1000
    const old = { played: true, lastPlayedAt: 0 }
    const ids = downloadsToDelete(
      [
        { id: "file-abc", ...old },
        { id: "uuid-1", ...old },
      ],
      10 * day,
      null,
      { ...DEFAULT_SETTINGS, deletePlayed: true },
    )
    expect(ids).toEqual(["uuid-1"])
  })

  it("has no address to share", () => {
    const url = localAudioUrl("file-abc", "mp3")
    expect(isLocalAudioUrl(url)).toBe(true)
    expect(isLocalAudioUrl("https://example.com/a.mp3")).toBe(false)
    expect(episodeShare({ title: "t", audioUrl: url }, null)).toBeNull()
  })
})

describe("an added file's episode", () => {
  it("is made from what Swift reports", () => {
    const values = localEpisodeValues(
      {
        episodeId: "file-abc",
        title: "Talk",
        durationSeconds: 12.5,
        bytes: 99,
        fileExtension: "m4a",
      },
      1000,
    )
    expect(values).toMatchObject({
      id: "file-abc",
      guid: "file-abc",
      title: "Talk",
      publishedAt: 1000,
      durationSeconds: 12.5,
      audioType: "audio/mp4",
      audioBytes: 99,
    })
    expect(values.audioUrl).toBe("https://files.invalid/file-abc.m4a")
    expect(isLocalEpisodeId(values.id)).toBe(true)
    expect(isLocalEpisodeId("5a1b-uuid")).toBe(false)
  })

  it("is renamed with a trimmed, non-empty name", () => {
    expect(cleanName("  New name ")).toBe("New name")
    expect(cleanName("   ")).toBeNull()
  })
})

describe("importSummary", () => {
  it("counts what was added, what was there already and what failed", () => {
    expect(importSummary(2, 1, [{ name: "a.txt", reason: "Not audio." }])).toBe(
      "Added 2 files.\n1 file was already added.\na.txt: Not audio.",
    )
    expect(importSummary(1, 2, [])).toBe(
      "Added 1 file.\n2 files were already added.",
    )
  })
})

describe("withoutLocalIds", () => {
  it("drops the added files, whose download is their only copy", () => {
    expect(withoutLocalIds(["a-uuid", "file-1", "b-uuid"])).toEqual([
      "a-uuid",
      "b-uuid",
    ])
  })
})
