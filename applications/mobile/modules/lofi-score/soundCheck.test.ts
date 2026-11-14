// LOFI-FORK: tests for the sound check's steps and results (see FORK.md).
import { describe, expect, it } from "vitest"

import type { LofiSoundCheckStop } from "./index"
import {
  answerStop,
  currentStop,
  isFinished,
  resultsText,
  SOUND_CHECK_ANSWERS,
  startSoundCheck,
  stopLabel,
} from "./soundCheck"

const stops: LofiSoundCheckStop[] = [
  {
    globalIndex: 12,
    kind: "quietRoom",
    sounds: ["roomTone", "clock"],
    placeName: "the study",
    relativeUrl: "Audio/ch1.mp3",
    start: 40,
  },
  {
    globalIndex: 300,
    kind: "water",
    sounds: ["river.runningTap"],
    relativeUrl: "Audio/ch4.mp3",
    start: 12.5,
  },
  {
    globalIndex: 410,
    kind: "oneOff",
    sounds: ["doorKnock"],
    relativeUrl: "Audio/ch5.mp3",
    start: 3,
  },
]

describe("sound check", () => {
  it("offers the five answers in order", () => {
    expect(SOUND_CHECK_ANSWERS.map((a) => a.label)).toEqual([
      "Too loud",
      "Clear",
      "Faint",
      "Can't hear",
      "Wrong sound",
    ])
  })

  it("walks the stops one answer at a time", () => {
    let session = startSoundCheck(stops)
    expect(currentStop(session)).toBe(stops[0])
    expect(isFinished(session)).toBe(false)
    session = answerStop(session, "clear")
    expect(currentStop(session)).toBe(stops[1])
    session = answerStop(session, "faint")
    session = answerStop(session, "wrongSound")
    expect(isFinished(session)).toBe(true)
    expect(currentStop(session)).toBeNull()
    expect(session.answers).toEqual(["clear", "faint", "wrongSound"])
    // Answering after the end changes nothing.
    expect(answerStop(session, "clear")).toBe(session)
  })

  it("names what each stop should sound like", () => {
    expect(stopLabel(stops[0]!)).toBe(
      "A quiet room (the study): a quiet room and a ticking clock",
    )
    expect(stopLabel(stops[1]!)).toBe("Water: running tap")
    expect(stopLabel(stops[2]!)).toBe("A one-off sound: door knock")
  })

  it("writes the results as text to paste", () => {
    let session = startSoundCheck(stops)
    session = answerStop(session, "clear")
    session = answerStop(session, "cantHear")
    const text = resultsText(session, {
      book: "Redwood",
      levelDB: -10,
      defaultLevelDB: -10,
      intensity: 0.75,
    })
    expect(text).toBe(
      [
        "Sound check: Redwood",
        "Sounds volume -10 dB (default), how much is going on 75%",
        "1. #12 quietRoom roomTone, clock (the study): Clear",
        "2. #300 water river.runningTap: Can't hear",
        "3. #410 oneOff doorKnock: not answered",
      ].join("\n"),
    )
  })

  it("has nothing to check without stops", () => {
    expect(isFinished(startSoundCheck([]))).toBe(true)
  })
})
