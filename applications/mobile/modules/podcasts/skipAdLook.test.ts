// LOFI-FORK: the podcasts section's full-screen player (see FORK.md).
import { describe, expect, it } from "vitest"

import { SKIP_NOTE_MS } from "./ads"
import {
  MISSED_AD_NOTE,
  SKIP_AD_BUTTON,
  SKIP_AD_LABEL,
  missedAdNote,
  missedAdNoteShown,
} from "./skipAdLook"

describe("the Skip ad button", () => {
  it("is labelled Skip ad and is a comfortable touch target", () => {
    expect(SKIP_AD_LABEL).toBe("Skip ad")
    expect(SKIP_AD_BUTTON.height).toBeGreaterThanOrEqual(44)
    expect(SKIP_AD_BUTTON.minWidth).toBeGreaterThanOrEqual(44)
  })
})

describe("missedAdNote", () => {
  it("shows nothing when the phone knew the ad (the skip event has its own note)", () => {
    expect(missedAdNote({ to: 500, known: true }, 1000)).toBeNull()
  })

  it("says it jumped 30 seconds and noted a missed ad when the phone knew none", () => {
    expect(missedAdNote({ to: 530, known: false }, 1000)).toEqual({
      text: "Jumped 30 seconds. Noted as a missed ad.",
      shownAt: 1000,
    })
    expect(MISSED_AD_NOTE).toBe("Jumped 30 seconds. Noted as a missed ad.")
  })

  it("shows nothing when nothing is loaded", () => {
    expect(missedAdNote(null, 1000)).toBeNull()
  })
})

describe("missedAdNoteShown", () => {
  it("stays as long as the skipped-ad note does", () => {
    const note = missedAdNote({ to: 1, known: false }, 10_000)
    expect(missedAdNoteShown(note, 10_000 + SKIP_NOTE_MS - 1)).toBe(true)
    expect(missedAdNoteShown(note, 10_000 + SKIP_NOTE_MS)).toBe(false)
    expect(missedAdNoteShown(null, 10_000)).toBe(false)
  })
})
