// LOFI-FORK: the podcasts section's sleep timer rules (see FORK.md).
import { describe, expect, it } from "vitest"

import {
  minutesLabel,
  parseCustomMinutes,
  readSleepState,
  sleepButtonLabel,
  sleepButtonText,
  sleepSecondsLeft,
} from "./sleepTimer"

describe("readSleepState", () => {
  it("reads the three states", () => {
    expect(readSleepState({ kind: "countdown", endsAt: 5000 })).toEqual({
      kind: "countdown",
      endsAt: 5000,
    })
    expect(readSleepState({ kind: "endOfEpisode" })).toEqual({
      kind: "endOfEpisode",
    })
    expect(readSleepState({ kind: "none" })).toEqual({ kind: "none" })
  })
  it("takes anything else as no timer", () => {
    expect(readSleepState(null)).toEqual({ kind: "none" })
    expect(readSleepState("soon")).toEqual({ kind: "none" })
    expect(readSleepState({ kind: "countdown" })).toEqual({ kind: "none" })
    expect(readSleepState({ kind: "countdown", endsAt: NaN })).toEqual({
      kind: "none",
    })
  })
})

describe("parseCustomMinutes", () => {
  it("takes whole minutes from 1 to 720", () => {
    expect(parseCustomMinutes("20")).toBe(20)
    expect(parseCustomMinutes(" 90 ")).toBe(90)
    expect(parseCustomMinutes("720")).toBe(720)
  })
  it("refuses everything else", () => {
    for (const text of ["", "0", "721", "-5", "1.5", "ten", "5 min", "00000"]) {
      expect(parseCustomMinutes(text)).toBeNull()
    }
  })
})

describe("sleepSecondsLeft", () => {
  it("counts down from the end time and stops at zero", () => {
    const state = { kind: "countdown", endsAt: 10_000 } as const
    expect(sleepSecondsLeft(state, 4000, 0, null, 1)).toBe(6)
    expect(sleepSecondsLeft(state, 12_000, 0, null, 1)).toBe(0)
  })
  it("for the end of the episode, is what is left at the current speed", () => {
    const state = { kind: "endOfEpisode" } as const
    expect(sleepSecondsLeft(state, 0, 600, 1800, 2)).toBe(600)
    expect(sleepSecondsLeft(state, 0, 2000, 1800, 1)).toBe(0)
  })
  it("has no answer for an unknown length or no timer", () => {
    expect(
      sleepSecondsLeft({ kind: "endOfEpisode" }, 0, 10, null, 1),
    ).toBeNull()
    expect(sleepSecondsLeft({ kind: "none" }, 0, 10, 100, 1)).toBeNull()
  })
})

describe("the moon button's words", () => {
  const countdown = { kind: "countdown", endsAt: 0 } as const
  it("shows the time left", () => {
    expect(sleepButtonText(754, countdown)).toBe("12:34")
    expect(sleepButtonLabel(754, countdown)).toBe("Sleep timer, 12:34 left")
  })
  it("says End while the episode's length is unknown", () => {
    expect(sleepButtonText(null, { kind: "endOfEpisode" })).toBe("End")
    expect(sleepButtonLabel(null, { kind: "endOfEpisode" })).toBe(
      "Sleep timer, at the end of the episode",
    )
  })
  it("is empty and off with no timer", () => {
    expect(sleepButtonText(null, { kind: "none" })).toBe("")
    expect(sleepButtonLabel(null, { kind: "none" })).toBe("Sleep timer, off")
  })
})

describe("minutesLabel", () => {
  it("reads naturally", () => {
    expect(minutesLabel(5)).toBe("5 minutes")
    expect(minutesLabel(60)).toBe("1 hour")
    expect(minutesLabel(1)).toBe("1 minute")
  })
})
