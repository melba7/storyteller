// LOFI-FORK: tests for the atmosphere's wording (see FORK.md).
import { describe, expect, it } from "vitest"

import type { LofiAtmosphereStatus, LofiStatus } from "./index"
import {
  atmosphereSourceLabel,
  bookNeedingScore,
  describeAtmosphere,
  intensityLabel,
  levelLabel,
  linkedFolderLabel,
  plainCredits,
  soundList,
  soundName,
  timeAgo,
} from "./status"

const atmosphere: LofiAtmosphereStatus = {
  enabled: true,
  available: true,
  levelDB: -24,
  defaultLevelDB: -24,
  levelRange: [-40, -14],
  intensity: 0.75,
  defaultIntensity: 0.75,
  source: "imported",
  preparing: false,
  sounds: 38,
  totalSounds: 38,
  variants: 0,
  edition: "personal",
  pausesEnabled: true,
  pausesAvailable: true,
  oneShotsEnabled: false,
  oneShots: 3,
  totalOneShots: 12,
  track: true,
  trackOrigin: "the book's score",
  place: "the tavern",
  playing: ["rainIndoors", "fireplace"],
  chapterDip: false,
  routeMuted: false,
  missingSounds: [],
  engineRunning: true,
}

function status(overrides: Partial<LofiStatus> = {}): LofiStatus {
  return {
    mutedInCar: false,
    followsReading: true,
    folder: { imported: true, importedFolderName: "LofiMusic" },
    book: { id: "b", text: "ready" },
    playback: {
      narrating: true,
      reading: false,
      sentence: 12,
      estimatedRate: 1,
    },
    atmosphere,
    recentEvents: [],
    ...overrides,
  }
}

function withSounds(changes: Partial<LofiAtmosphereStatus>): LofiStatus {
  return status({ atmosphere: { ...atmosphere, ...changes } })
}

describe("describeAtmosphere", () => {
  it("names the sounds playing", () => {
    expect(describeAtmosphere(status())).toBe("Rain on the windows and a fire")
    expect(describeAtmosphere(withSounds({ playing: ["crowd"] }))).toBe("Crowd")
    expect(describeAtmosphere(withSounds({ playing: [] }))).toBe("Quiet here")
  })

  it("explains why nothing is playing", () => {
    expect(describeAtmosphere(withSounds({ available: false }))).toBe(
      "Not in this version of the app",
    )
    expect(describeAtmosphere(withSounds({ enabled: false }))).toBe(
      "Atmosphere sounds are off",
    )
    expect(describeAtmosphere(withSounds({ preparing: true }))).toBe(
      "Getting the sounds ready…",
    )
    expect(describeAtmosphere(withSounds({ source: "none" }))).toBe(
      "No sounds yet",
    )
    const { book: _none, ...noBook } = status()
    expect(describeAtmosphere(noBook)).toBe(
      "Plays with readaloud books that have an atmosphere track",
    )
    expect(
      describeAtmosphere(status({ book: { id: "b", text: "unavailable" } })),
    ).toBe("This book has no text for the sounds to follow")
    expect(
      describeAtmosphere(status({ book: { id: "b", text: "loading" } })),
    ).toBe("Reading the book…")
    expect(describeAtmosphere(withSounds({ track: false }))).toBe(
      "This book has no atmosphere track yet",
    )
    expect(describeAtmosphere(withSounds({ routeMuted: true }))).toBe(
      "Off in the car",
    )
  })

  it("says the sounds follow the pages", () => {
    const base = status()
    const stopped = { ...base.playback, narrating: false }
    expect(describeAtmosphere({ ...base, playback: stopped })).toBe(
      "Plays with the narration, or as you turn the pages",
    )
    expect(
      describeAtmosphere({
        ...base,
        playback: { ...stopped, reading: true },
      }),
    ).toBe("Rain on the windows and a fire")
    expect(
      describeAtmosphere({ ...base, followsReading: false, playback: stopped }),
    ).toBe("Plays with the narration")
  })
})

describe("labels", () => {
  it("shows the level relative to the voice", () => {
    expect(levelLabel(-24)).toBe("24 dB under the voice")
    expect(levelLabel(0)).toBe("As loud as the voice")
  })

  it("says how much of the scene the intensity dial lets through", () => {
    expect(intensityLabel(0)).toBe("Just the main sound")
    expect(intensityLabel(0.25)).toBe("Sparse")
    expect(intensityLabel(0.5)).toBe("Some of the scene")
    expect(intensityLabel(0.75)).toBe("Most of the scene")
    expect(intensityLabel(1)).toBe("The whole scene")
  })

  it("names sounds and their source", () => {
    expect(soundName("heavyRain")).toBe("heavy rain")
    expect(soundName("seaShore")).toBe("waves")
    expect(soundName("murmur")).toBe("murmuring voices")
    expect(soundName("emptyHall")).toBe("an empty hall")
    expect(soundList(["wind", "rain", "clock"])).toBe(
      "Wind, rain and a ticking clock",
    )
    expect(soundList([])).toBe("")
    expect(
      atmosphereSourceLabel({ ...atmosphere, sounds: 12, totalSounds: 26 }),
    ).toBe("12 of 26 sounds, imported")
    expect(atmosphereSourceLabel({ ...atmosphere, variants: 31 })).toBe(
      "38 of 38 sounds, imported, and 31 more specific sounds",
    )
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
    expect(atmosphereSourceLabel({ ...atmosphere, source: "standIns" })).toBe(
      "Stand-in sounds. Import a sounds folder (with an Atmosphere folder in it) for the real thing.",
    )
    expect(atmosphereSourceLabel({ ...atmosphere, source: "none" })).toBe(
      "No sounds yet",
    )
  })

  it("describes the linked sounds folder", () => {
    const now = Date.parse("2026-11-10T12:00:00Z")
    const minutesAgo = (minutes: number) => (now - minutes * 60_000) / 1000
    expect(
      linkedFolderLabel(
        { name: "LofiMusic", lastSync: minutesAgo(5), syncing: false },
        now,
      ),
    ).toBe("Kept up to date with “LofiMusic”. Last checked 5 minutes ago.")
    expect(
      linkedFolderLabel(
        {
          name: "LofiMusic",
          lastSync: minutesAgo(5),
          lastResult: "new: 1 book score",
          syncing: false,
        },
        now,
      ),
    ).toBe(
      "Kept up to date with “LofiMusic”. Last checked 5 minutes ago. New: 1 book score.",
    )
    expect(
      linkedFolderLabel(
        { name: "LofiMusic", lastSync: minutesAgo(5), syncing: true },
        now,
      ),
    ).toBe("Kept up to date with “LofiMusic”. Checking it now…")
    expect(linkedFolderLabel({ name: "Sounds", syncing: false }, now)).toBe(
      "Kept up to date with “Sounds”.",
    )
  })

  it("says how long ago", () => {
    const now = Date.parse("2026-11-10T12:00:00Z")
    const ago = (seconds: number) => timeAgo(now - seconds * 1000, now)
    expect(ago(0)).toBe("just now")
    expect(ago(59)).toBe("just now")
    expect(ago(60)).toBe("a minute ago")
    expect(ago(5 * 60)).toBe("5 minutes ago")
    expect(ago(60 * 60)).toBe("an hour ago")
    expect(ago(3 * 60 * 60)).toBe("3 hours ago")
    expect(ago(24 * 60 * 60)).toBe("yesterday")
    expect(ago(3 * 24 * 60 * 60)).toBe("3 days ago")
    expect(timeAgo(now + 5000, now)).toBe("just now")
  })
})

describe("bookNeedingScore", () => {
  it("asks the server for a score only when the open book lacks one", () => {
    expect(bookNeedingScore(null)).toBeNull()
    const { book: _none, ...noBook } = status()
    expect(bookNeedingScore(noBook)).toBeNull()
    expect(bookNeedingScore(status())).toBeNull()
    expect(bookNeedingScore(withSounds({ track: false }))).toBe("b")
    expect(
      bookNeedingScore({
        ...withSounds({ track: false }),
        book: { id: "b", text: "loading" },
      }),
    ).toBeNull()
    expect(
      bookNeedingScore(withSounds({ track: false, available: false })),
    ).toBeNull()
  })
})

describe("plainCredits", () => {
  it("drops Markdown marks but keeps names, licences and links", () => {
    const markdown = [
      "# Sound credits",
      "",
      "",
      "",
      "## Rain",
      "- **Rain on Glass** by [someone](https://example.com/someone), CC0",
      "* Night Rain by Someone, [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)",
      "Source: [https://example.com](https://example.com) and `SOURCES.csv`",
    ].join("\r\n")
    expect(plainCredits(markdown)).toBe(
      [
        "Sound credits",
        "",
        "Rain",
        "• Rain on Glass by someone (https://example.com/someone), CC0",
        "• Night Rain by Someone, CC BY 4.0 (https://creativecommons.org/licenses/by/4.0/)",
        "Source: https://example.com and SOURCES.csv",
      ].join("\n"),
    )
  })
})
