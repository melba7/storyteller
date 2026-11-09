// LOFI-FORK: tests for the lofi music's wording (see FORK.md).
import { describe, expect, it } from "vitest"

import type { LofiMusicStatus } from "./index"
import {
  atmosphereSourceLabel,
  describeAtmosphere,
  describeMusic,
  moodCounts,
  musicLevelLabel,
  musicSourceLabel,
  plainCredits,
  soundList,
  soundName,
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

describe("describeAtmosphere", () => {
  const atmosphere: NonNullable<LofiMusicStatus["atmosphere"]> = {
    enabled: true,
    available: true,
    levelDB: -28,
    defaultLevelDB: -28,
    levelRange: [-40, -16],
    source: "standIns",
    preparing: false,
    sounds: 26,
    totalSounds: 26,
    track: true,
    trackOrigin: "the book's score",
    place: "the tavern",
    playing: ["rainIndoors", "fireplace"],
    musicYielding: false,
    chapterDip: false,
    missingSounds: [],
    engineRunning: true,
  }

  it("names the sounds playing", () => {
    expect(describeAtmosphere(status({ atmosphere }))).toBe(
      "Rain on the windows and a fire",
    )
    expect(
      describeAtmosphere(
        status({
          atmosphere: {
            ...atmosphere,
            playing: ["crowd"],
            musicYielding: true,
          },
        }),
      ),
    ).toBe("Crowd, with the music paused")
  })

  it("explains why nothing is playing", () => {
    expect(describeAtmosphere(status())).toBe("Not in this version of the app")
    expect(
      describeAtmosphere(
        status({ atmosphere: { ...atmosphere, enabled: false } }),
      ),
    ).toBe("Atmosphere is off")
    expect(
      describeAtmosphere(
        status({ atmosphere: { ...atmosphere, track: false } }),
      ),
    ).toBe("This book has no atmosphere track yet")
    expect(
      describeAtmosphere(
        status({ atmosphere: { ...atmosphere, playing: [] } }),
      ),
    ).toBe("Quiet here")
  })

  it("names sounds and their source", () => {
    expect(soundName("heavyRain")).toBe("heavy rain")
    expect(soundName("seaShore")).toBe("waves")
    expect(soundList(["wind", "rain", "clock"])).toBe(
      "Wind, rain and a ticking clock",
    )
    expect(
      atmosphereSourceLabel({ ...atmosphere, source: "imported", sounds: 12 }),
    ).toBe("12 of 26 sounds, imported")
    expect(
      atmosphereSourceLabel({
        ...atmosphere,
        source: "imported",
        sounds: 26,
        variants: 31,
      }),
    ).toBe("26 of 26 sounds, imported, and 31 more specific sounds")
    expect(
      atmosphereSourceLabel({
        ...atmosphere,
        source: "mixed",
        sounds: 20,
        variants: 1,
      }),
    ).toBe(
      "20 sounds: imported recordings, with stand-ins for the rest, and 1 more specific sound",
    )
  })
})
