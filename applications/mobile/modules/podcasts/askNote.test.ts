// LOFI-FORK: the podcasts section's question note (see FORK.md).
import { describe, expect, it, vi } from "vitest"

import {
  ASK_LEAD_SECONDS,
  ASK_NOTE_TEXT,
  type AskNote,
  askNoteFor,
  askNoteShown,
  createAskNotes,
} from "./askNote"

const event = {
  episodeId: "e1",
  start: 600,
  end: 660,
  kind: "ad",
}

function notes(answer = vi.fn().mockResolvedValue(true), warn = vi.fn()) {
  return { store: createAskNotes(answer, warn), answer, warn }
}

describe("the words", () => {
  it("asks Ad? Skip", () => {
    expect(ASK_NOTE_TEXT).toBe("Ad? Skip")
  })
})

describe("askNoteFor", () => {
  it("makes the note of an onAdAsk event", () => {
    expect(askNoteFor(event)).toEqual(event)
  })

  it("ignores an event that is not a stretch of one episode", () => {
    for (const bad of [
      null,
      "e1",
      [],
      {},
      { ...event, episodeId: "" },
      { ...event, episodeId: 5 },
      { ...event, start: "600" },
      { ...event, start: Number.NaN },
      { ...event, end: Number.POSITIVE_INFINITY },
      { ...event, end: 600 },
      { ...event, end: 599 },
      { ...event, start: -1 },
    ]) {
      expect(askNoteFor(bad)).toBeNull()
    }
  })

  it("keeps a missing kind as an empty one", () => {
    expect(askNoteFor({ ...event, kind: undefined })?.kind).toBe("")
  })
})

describe("askNoteShown", () => {
  const note = askNoteFor(event)

  it("is shown while the playhead is in the stretch of the loaded episode", () => {
    expect(askNoteShown(note, "e1", 600)).toBe(true)
    expect(askNoteShown(note, "e1", 630)).toBe(true)
    expect(askNoteShown(note, "e1", 659.9)).toBe(true)
  })

  it("is shown a moment before the start, because the screen's clock may be behind", () => {
    expect(ASK_LEAD_SECONDS).toBe(2)
    expect(askNoteShown(note, "e1", 598.5)).toBe(true)
    expect(askNoteShown(note, "e1", 598)).toBe(true)
  })

  it("is gone once the playhead is at or past the end", () => {
    expect(askNoteShown(note, "e1", 660)).toBe(false)
    expect(askNoteShown(note, "e1", 1000)).toBe(false)
  })

  it("is gone after a seek back to well before the stretch", () => {
    expect(askNoteShown(note, "e1", 597.9)).toBe(false)
    expect(askNoteShown(note, "e1", 0)).toBe(false)
  })

  it("is gone when another episode is loaded, or none is", () => {
    expect(askNoteShown(note, "e2", 630)).toBe(false)
    expect(askNoteShown(note, null, 630)).toBe(false)
  })

  it("is gone for no note and for a place that is not a number", () => {
    expect(askNoteShown(null, "e1", 630)).toBe(false)
    expect(askNoteShown(note, "e1", Number.NaN)).toBe(false)
  })
})

describe("the note store", () => {
  it("shows the note when the phone asks, and tells its listeners", () => {
    const { store } = notes()
    const listener = vi.fn()
    store.subscribe(listener)
    expect(store.note()).toBeNull()
    store.asked(event)
    expect(store.note()).toEqual(event)
    expect(listener).toHaveBeenCalledTimes(1)
  })

  it("keeps showing nothing for an event that is not a question", () => {
    const { store } = notes()
    const listener = vi.fn()
    store.subscribe(listener)
    store.asked({ episodeId: "e1" })
    expect(store.note()).toBeNull()
    expect(listener).not.toHaveBeenCalled()
  })

  it("shows the newest question when a second one is asked", () => {
    const { store } = notes()
    store.asked(event)
    store.asked({ ...event, start: 900, end: 940 })
    expect(store.note()?.start).toBe(900)
  })

  it("stops telling a listener that unsubscribed", () => {
    const { store } = notes()
    const listener = vi.fn()
    const stop = store.subscribe(listener)
    stop()
    store.asked(event)
    expect(listener).not.toHaveBeenCalled()
  })

  it("hides the note it is told to hide, but not a newer one", () => {
    const { store } = notes()
    store.asked(event)
    const old = store.note() as AskNote
    store.asked({ ...event, start: 900, end: 940 })
    store.hide(old)
    expect(store.note()?.start).toBe(900)
    store.hide(store.note() as AskNote)
    expect(store.note()).toBeNull()
  })

  it("hides the note when a skip of that stretch is reported, and not for another one", () => {
    const { store } = notes()
    store.asked(event)
    store.skipped({ episodeId: "e2", start: 600, end: 660 })
    store.skipped({ episodeId: "e1", start: 100, end: 160 })
    expect(store.note()).not.toBeNull()
    store.skipped({ episodeId: "e1", start: 600, end: 660 })
    expect(store.note()).toBeNull()
  })

  it("asks the player the question with the stretch's start and says yes for Skip", () => {
    const { store, answer } = notes()
    store.asked(event)
    store.answer(true)
    expect(answer).toHaveBeenCalledTimes(1)
    expect(answer).toHaveBeenCalledWith("e1", 600, true)
  })

  it("says no for Not an ad", () => {
    const { store, answer } = notes()
    store.asked(event)
    store.answer(false)
    expect(answer).toHaveBeenCalledWith("e1", 600, false)
  })

  it("hides the note at the answer, so a second tap answers nothing", () => {
    const { store, answer } = notes()
    const listener = vi.fn()
    store.asked(event)
    store.subscribe(listener)
    store.answer(true)
    expect(store.note()).toBeNull()
    expect(listener).toHaveBeenCalledTimes(1)
    store.answer(true)
    store.answer(false)
    expect(answer).toHaveBeenCalledTimes(1)
  })

  it("does nothing for an answer when no question is shown", () => {
    const { store, answer } = notes()
    store.answer(true)
    expect(answer).not.toHaveBeenCalled()
  })

  it("keeps the note hidden and says why when the player cannot take the answer", async () => {
    const cause = new Error("no player")
    const { store, warn } = notes(vi.fn().mockRejectedValue(cause))
    store.asked(event)
    store.answer(true)
    await Promise.resolve()
    await Promise.resolve()
    expect(store.note()).toBeNull()
    expect(warn).toHaveBeenCalledWith(expect.any(String), cause)
  })
})
