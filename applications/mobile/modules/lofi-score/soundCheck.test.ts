// LOFI-FORK: tests for the sound check's wording and results (see FORK.md).
import { describe, expect, it } from "vitest"

import type { LofiSoundCheckReading, LofiSoundCheckStop } from "./index"
import {
  resultsText,
  SOUND_CHECK_ANSWERS,
  stopLabel,
  stopQuestion,
} from "./soundCheck"

const stops: LofiSoundCheckStop[] = [
  {
    globalIndex: 12,
    lastIndex: 25,
    kind: "quietRoom",
    sounds: [
      { key: "roomTone", level: "soft" },
      { key: "clock", level: "faint" },
    ],
    placeName: "the study",
    relativeUrl: "Audio/ch1.mp3",
    start: 40,
  },
  {
    globalIndex: 300,
    lastIndex: 320,
    kind: "water",
    sounds: [{ key: "river.runningTap", level: "full" }],
    relativeUrl: "Audio/ch4.mp3",
    start: 12.5,
  },
  {
    globalIndex: 405,
    lastIndex: 411,
    kind: "oneOff",
    sounds: [{ key: "doorKnock" }],
    cueIndex: 410,
    relativeUrl: "Audio/ch5.mp3",
    start: 3,
  },
]

const reading: LofiSoundCheckReading = {
  voices: [
    {
      sound: "roomTone",
      level: "soft",
      recording: "fs123",
      gainDB: 6,
      atGainCap: true,
    },
  ],
  missingSounds: ["clock"],
  route: "wired",
  routeMuted: false,
  voiceLoudnessLUFS: -16,
  bedLevelDB: -10,
  oneShotsEnabled: true,
  pausesEnabled: false,
}

describe("sound check wording", () => {
  it("offers the five answers in order, each with what it means", () => {
    expect(SOUND_CHECK_ANSWERS.map((a) => a.label)).toEqual([
      "Too loud",
      "Clear",
      "Faint",
      "Can't hear",
      "Wrong sound",
    ])
    expect(SOUND_CHECK_ANSWERS.every((a) => a.hint.length > 0)).toBe(true)
  })

  it("names the main sound to listen for, and the others as also there", () => {
    expect(stopLabel(stops[0]!)).toBe(
      "Listen for a quiet room (soft) in the study. Also there: a ticking clock.",
    )
    expect(stopLabel(stops[1]!)).toBe("Listen for running tap (full).")
    expect(stopLabel(stops[2]!)).toBe("Listen for a one-off sound: door knock.")
    expect(stopQuestion(stops[1]!)).toBe(
      "How did running tap come through under the voice?",
    )
  })
})

describe("sound check results", () => {
  it("writes the run's conditions, each answer and what played", () => {
    const text = resultsText(
      stops,
      [{ answer: "clear", reading }, { couldNotPlay: true }, {}],
      {
        book: "Redwood",
        appVersion: "2.12.0",
        levelDB: -10,
        defaultLevelDB: -10,
        intensity: 0.5,
        defaultIntensity: 0.75,
        source: "imported",
        playbackRate: 1.25,
        startedAt: "2026-11-14 18:00",
      },
    )
    expect(text).toBe(
      [
        "Sound check: Redwood (2026-11-14 18:00)",
        "App 2.12.0, sounds imported, narration speed 1.25x",
        "Sounds volume -10 dB (default), how much is going on 50%",
        "Output wired, bed -10 dB under a -16 LUFS voice, one-offs on, pauses off",
        "1. #12-25 quietRoom roomTone soft, clock faint (the study): Clear",
        "    roomTone soft: fs123, gain +6 dB (at the gain cap)",
        "    missing: clock",
        "2. #300-320 water river.runningTap full: could not play",
        "3. #405-411 oneOff doorKnock: not answered",
        "    (nothing read)",
      ].join("\n"),
    )
  })
})
