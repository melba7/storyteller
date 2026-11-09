// LOFI-FORK: tests for the lofi music's wording (see FORK.md).
import { describe, expect, it } from "vitest"

import type { LofiMusicStatus } from "./index"
import {
  describeMusic,
  moodCounts,
  musicLevelLabel,
  musicSourceLabel,
  plainCredits,
} from "./status"

function status(overrides: Partial<LofiMusicStatus> = {}): LofiMusicStatus {
  return {
    enabled: true,
    mutedInCar: false,
    musicLevelDB: -12,
    defaultMusicLevelDB: -12,
    musicLevelRange: [-30, -4],
    library: {
      source: "imported",
      preparing: false,
      importedFolderName: "LofiMusic",
      tracks: 32,
      moods: [
        { mood: "calm", tracks: 4 },
        { mood: "tense", tracks: 0 },
      ],
    },
    book: { id: "b", text: "ready", moodTrack: false },
    playback: {
      narrating: true,
      estimatedRate: 1,
      readings: 3,
      musicMood: "calm",
      engineRunning: true,
      routeMuted: false,
      recentMoods: ["calm"],
    },
    recentEvents: [],
    ...overrides,
  }
}

describe("describeMusic", () => {
  it("says what is playing", () => {
    expect(describeMusic(status())).toBe("Playing calm music")
  })

  it("explains why nothing is playing", () => {
    expect(describeMusic(status({ enabled: false }))).toBe("Music is off")
    const base = status()
    expect(
      describeMusic({
        ...base,
        library: { ...base.library, source: "none", tracks: 0 },
      }),
    ).toBe("No music yet. Import a music folder in Settings.")
    expect(
      describeMusic({
        ...base,
        book: { id: "b", text: "unavailable", moodTrack: false },
      }),
    ).toBe("This book has no text for the music to follow")
    expect(
      describeMusic({
        ...base,
        playback: { ...base.playback, narrating: false },
      }),
    ).toBe("Plays with the narration")
    expect(
      describeMusic({
        ...base,
        playback: { ...base.playback, routeMuted: true },
      }),
    ).toBe("Off in the car")
  })
})

describe("labels", () => {
  it("shows the level relative to the voice", () => {
    expect(musicLevelLabel(-12)).toBe("12 dB under the voice")
    expect(musicLevelLabel(0)).toBe("As loud as the voice")
  })

  it("names the music's source and moods", () => {
    expect(musicSourceLabel(status().library)).toBe(
      "32 tracks from “LofiMusic”",
    )
    expect(moodCounts(status().library)).toBe("Calm 4 · no Tense yet")
  })
})

describe("plainCredits", () => {
  it("drops Markdown marks but keeps names, licences and links", () => {
    const markdown = [
      "# Music credits",
      "",
      "",
      "",
      "## Calm",
      "- **Rain on Glass** by [HoliznaCC0](https://example.com/holizna), CC0",
      "* Night Bus by Someone, [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)",
      "Source: [https://example.com](https://example.com) and `SOURCES.csv`",
    ].join("\r\n")
    expect(plainCredits(markdown)).toBe(
      [
        "Music credits",
        "",
        "Calm",
        "• Rain on Glass by HoliznaCC0 (https://example.com/holizna), CC0",
        "• Night Bus by Someone, CC BY 4.0 (https://creativecommons.org/licenses/by/4.0/)",
        "Source: https://example.com and SOURCES.csv",
      ].join("\n"),
    )
  })
})
