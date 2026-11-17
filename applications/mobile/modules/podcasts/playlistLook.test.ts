// LOFI-FORK: the podcasts section's playlists (see FORK.md).
import { describe, expect, it } from "vitest"

import { type StoredEpisode } from "./library"
import { type PlaylistEntry } from "./manualPlaylist"
import {
  entryDetails,
  entryLabel,
  episodeCount,
  playlistLine,
} from "./playlistLook"

function entry(show: string | null, seconds: number | null): PlaylistEntry {
  return {
    episode: { title: "A talk", durationSeconds: seconds } as StoredEpisode,
    show: show === null ? null : ({ title: show } as PlaylistEntry["show"]),
    inLibrary: false,
  }
}

describe("episodeCount", () => {
  it("counts episodes", () => {
    expect(episodeCount(0)).toBe("0 episodes")
    expect(episodeCount(1)).toBe("1 episode")
    expect(episodeCount(12)).toBe("12 episodes")
  })
})

describe("entryDetails", () => {
  it("joins the show and the length, leaving out what is not known", () => {
    expect(entryDetails(entry("The Show", 2700))).toBe("The Show · 45 min")
    expect(entryDetails(entry("The Show", null))).toBe("The Show")
    expect(entryDetails(entry(null, 600))).toBe("10 min")
    expect(entryDetails(entry(null, null))).toBe("")
  })
})

describe("entryLabel", () => {
  it("reads title, details and place", () => {
    expect(entryLabel(entry("The Show", 600), 1, 4)).toBe(
      "A talk, The Show · 10 min, place 2 of 4",
    )
  })
})

describe("playlistLine", () => {
  it("joins the count and the rules", () => {
    expect(playlistLine(12, "Unplayed · Starred")).toBe(
      "12 episodes · Unplayed · Starred",
    )
    expect(playlistLine(1, "Filled by you")).toBe("1 episode · Filled by you")
  })
  it("leaves the count out until it is known", () => {
    expect(playlistLine(undefined, "Every episode")).toBe("Every episode")
  })
})
