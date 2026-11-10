// LOFI-FORK: tests for the lofi music's wording (see FORK.md).
import { describe, expect, it } from "vitest"

import type { LofiMusicStatus } from "./index"
import {
  atmosphereSourceLabel,
  bookNeedingScore,
  canMarkWrongMood,
  describeAtmosphere,
  describeMusic,
  linkedFolderLabel,
  moodCounts,
  moodFeedbackLine,
  moodFeedbackTotals,
  musicLevelLabel,
  musicSourceLabel,
  nowPlayingLine,
  plainCredits,
  soundList,
  soundName,
  timeAgo,
  wrongMoodResult,
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

describe("reading on screen", () => {
  it("says the music follows the pages", () => {
    const base = status({ followsReading: true })
    const stopped = { ...base.playback, narrating: false }
    expect(describeMusic({ ...base, playback: stopped })).toBe(
      "Plays with the narration, or as you turn the pages",
    )
    expect(
      describeMusic({ ...base, playback: { ...stopped, reading: true } }),
    ).toBe("Playing calm music as you read")
    expect(
      describeMusic({
        ...base,
        followsReading: false,
        playback: stopped,
      }),
    ).toBe("Plays with the narration")
  })
})

describe("wrong mood", () => {
  it("is offered only while the music can be heard", () => {
    const base = status()
    expect(canMarkWrongMood(base)).toBe(true)
    expect(canMarkWrongMood({ ...base, enabled: false })).toBe(false)
    expect(
      canMarkWrongMood({
        ...base,
        playback: { ...base.playback, narrating: false },
      }),
    ).toBe(false)
    expect(
      canMarkWrongMood({
        ...base,
        playback: { ...base.playback, narrating: false, reading: true },
      }),
    ).toBe(true)
    const { musicMood: _, ...silent } = base.playback
    expect(canMarkWrongMood({ ...base, playback: silent })).toBe(false)
  })

  it("reports what changed and the counts", () => {
    expect(
      wrongMoodResult({
        rejected: "tense",
        chosen: "mysterious",
        picked: false,
        correction: false,
      }),
    ).toBe("Switched to mysterious music. Still wrong? Pick the mood.")
    const none = {
      bookChanges: 0,
      bookWrong: 0,
      totalChanges: 0,
      totalWrong: 0,
    }
    expect(moodFeedbackLine(none)).toBeNull()
    expect(moodFeedbackTotals(none)).toBeNull()
    expect(moodFeedbackLine({ ...none, bookChanges: 1, bookWrong: 1 })).toBe(
      "You marked 1 of 1 mood change wrong in this book",
    )
    expect(
      moodFeedbackTotals({ ...none, totalChanges: 31, totalWrong: 2 }),
    ).toBe("2 of 31 mood changes marked wrong (6%)")
  })
})

describe("now playing", () => {
  it("names the track, its artist and licence", () => {
    expect(
      nowPlayingLine({
        title: "Sky Lake",
        artist: "Purrple Cat",
        license: "CC BY-SA 3.0",
        mood: "calm",
      }),
    ).toBe("“Sky Lake” by Purrple Cat · CC BY-SA 3.0")
    expect(nowPlayingLine({ title: "calm-1", mood: "calm" })).toBe("“calm-1”")
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
  it("describes the linked music folder", () => {
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
    expect(linkedFolderLabel({ name: "Music", syncing: false }, now)).toBe(
      "Kept up to date with “Music”.",
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

  it("asks the server for a score only when the open book lacks one", () => {
    const book = { id: "b1", text: "ready" as const, moodTrack: false }
    expect(bookNeedingScore(null)).toBeNull()
    const { book: _none, ...noBook } = status()
    expect(bookNeedingScore(noBook)).toBeNull()
    expect(bookNeedingScore(status())).toBe("b")
    expect(bookNeedingScore(status({ book }))).toBe("b1")
    expect(
      bookNeedingScore(status({ book: { ...book, text: "loading" } })),
    ).toBeNull()
    expect(
      bookNeedingScore(status({ book: { ...book, moodTrack: true } })),
    ).toBeNull()
    expect(
      bookNeedingScore(
        status({
          book: { ...book, moodTrack: true },
          atmosphere: { ...atmosphere, available: true, track: false },
        }),
      ),
    ).toBe("b1")
    expect(
      bookNeedingScore(
        status({
          book: { ...book, moodTrack: true },
          atmosphere: { ...atmosphere, available: false, track: false },
        }),
      ),
    ).toBeNull()
    expect(
      bookNeedingScore(
        status({
          book: { ...book, moodTrack: true },
          atmosphere: { ...atmosphere, available: true, track: true },
        }),
      ),
    ).toBeNull()
  })
})
